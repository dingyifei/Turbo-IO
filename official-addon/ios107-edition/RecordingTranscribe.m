#if TIO_APPLE_AI
#import "RecordingTranscribe.h"
#import "RecordingExports.h"
#import "AppleAICore.h"
#import "AppleAI.h"
#import <Speech/Speech.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
@interface TIORecordingTranscriber()
@property(atomic) BOOL cancelled;
@property(atomic) id activeTask;
@property(atomic) dispatch_semaphore_t waiter;
@property(nonatomic) dispatch_queue_t queue;
@end
@implementation TIORecordingTranscriber
- (instancetype)init{if((self=[super init]))_queue=dispatch_queue_create("io.turboio.apple.transcribe",DISPATCH_QUEUE_SERIAL);return self;}
- (void)cancel{self.cancelled=YES;id task=self.activeTask;SEL cancel=NSSelectorFromString(@"cancel");if([task respondsToSelector:cancel])((void(*)(id,SEL))objc_msgSend)(task,cancel);dispatch_semaphore_t waiter=self.waiter;if(waiter)dispatch_semaphore_signal(waiter);}
- (NSString *)recognize:(AVAudioFile *)file locale:(NSString *)locale frames:(AVAudioFramePosition)frames code:(NSString **)code {
    if(self.cancelled){*code=@"cancelled";return nil;}
    SFSpeechRecognizer *recognizer=[[SFSpeechRecognizer alloc]initWithLocale:[NSLocale localeWithLocaleIdentifier:locale]];
    if(!recognizer.supportsOnDeviceRecognition){*code=@"localeUnsupported";return nil;}
    recognizer.queue=[NSOperationQueue new];recognizer.queue.maxConcurrentOperationCount=1;
    SFSpeechAudioBufferRecognitionRequest *request=[SFSpeechAudioBufferRecognitionRequest new];request.requiresOnDeviceRecognition=YES;request.shouldReportPartialResults=NO;request.addsPunctuation=YES;
    dispatch_semaphore_t semaphore=dispatch_semaphore_create(0);self.waiter=semaphore;NSObject *lock=[NSObject new];__block BOOL finished=NO;__block NSString *text=nil,*failure=nil;
    SFSpeechRecognitionTask *task=[recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result,NSError *error){
        @synchronized(lock){if(finished)return;if(error||result.isFinal){finished=YES;text=result.bestTranscription.formattedString;failure=error?@"other":nil;dispatch_semaphore_signal(semaphore);}}
    }];self.activeTask=task;
    AVAudioFramePosition left=MIN(frames,file.length-file.framePosition);NSError *readError=nil;
    while(left>0&&!self.cancelled){@autoreleasepool{
        AVAudioFrameCount count=(AVAudioFrameCount)MIN(left,4096);AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:file.processingFormat frameCapacity:count];
        if(!buffer||![file readIntoBuffer:buffer frameCount:count error:&readError]||!buffer.frameLength)break;
        [request appendAudioPCMBuffer:buffer];left-=buffer.frameLength;
    }}
    [request endAudio];long timeout=dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC));
    @synchronized(lock){finished=YES;if(timeout||readError)failure=@"other";if(self.cancelled)failure=@"cancelled";if(failure)*code=failure;}
    [task cancel];self.activeTask=nil;self.waiter=nil;return failure?nil:text?:@"";
}
- (void)transcribeFile:(NSURL *)source language:(NSString *)language progress:(void(^)(NSString *,double))progress completion:(void(^)(NSString *,NSString *))completion {
    dispatch_async(self.queue,^{@autoreleasepool{
        NSString *code=nil,*markdown=nil;NSError *error=nil;NSURL *copy=TIOAudioShareCopy([NSURL fileURLWithPath:NSHomeDirectory()],source,&error);NSURL *directory=copy.URLByDeletingLastPathComponent;
        void(^stage)(NSString *,double)=^(NSString *key,double fraction){dispatch_async(dispatch_get_main_queue(),^{if(!self.cancelled&&progress)progress(TAIText(@"Transcribing on device",/*i18n:keep*/@"正在本机转写"),fraction);});};
        do {
            if(!copy){code=@"decodeFailed";break;}
            if(self.cancelled){code=@"cancelled";break;}
            if(TIOTranscribeNeedsTranscode(copy.pathExtension)){
                Class ff=NSClassFromString(@"FFmpegKit"),rcClass=NSClassFromString(@"ReturnCode");SEL execute=NSSelectorFromString(@"executeWithArguments:"),get=NSSelectorFromString(@"getReturnCode"),success=NSSelectorFromString(@"isSuccess:");
                if(![ff respondsToSelector:execute]||![rcClass respondsToSelector:success]){code=@"decodeFailed";break;}
                NSURL *decoded=[directory URLByAppendingPathComponent:@"decoded.wav"];NSArray *args=TIOTranscodeArguments(copy.path,decoded.path);
                id session=((id(*)(id,SEL,id))objc_msgSend)(ff,execute,args);if(![session respondsToSelector:get]){code=@"decodeFailed";break;}
                id rc=((id(*)(id,SEL))objc_msgSend)(session,get);if(!((BOOL(*)(id,SEL,id))objc_msgSend)(rcClass,success,rc)){code=@"decodeFailed";break;}
                [NSFileManager.defaultManager removeItemAtURL:copy error:NULL];copy=decoded;
            }
            if(self.cancelled){code=@"cancelled";break;}
            dispatch_semaphore_t auth=dispatch_semaphore_create(0);self.waiter=auth;__block SFSpeechRecognizerAuthorizationStatus permission=SFSpeechRecognizerAuthorizationStatusNotDetermined;
            dispatch_async(dispatch_get_main_queue(),^{[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus value){@synchronized(auth){permission=value;}dispatch_semaphore_signal(auth);}];});
            long timedOut=dispatch_semaphore_wait(auth,dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC));self.waiter=nil;
            if(self.cancelled){code=@"cancelled";break;}if(timedOut||permission!=SFSpeechRecognizerAuthorizationStatusAuthorized){code=@"notAuthorized";break;}
            AVAudioFile *audio=[[AVAudioFile alloc]initForReading:copy error:&error];double rate=audio.processingFormat.sampleRate;
            if(!audio||rate<=0||audio.length<=0){code=@"decodeFailed";break;}
            AVAudioFramePosition cap=MIN(audio.length,(AVAudioFramePosition)(rate*14400));
            NSString *locale=[language isEqual:@"zh"]?@"zh-CN":@"en-US";
            if([language isEqual:@"auto"]){NSString *probeCode=nil;NSString *probe=[self recognize:audio locale:@"zh-CN" frames:(AVAudioFramePosition)(rate*30) code:&probeCode];if([probeCode isEqual:@"cancelled"]){code=probeCode;break;}locale=probe.length?TIOTranscriptLocaleFromProbe(probe):@"en-US";audio.framePosition=0;}
            // Prefer installed SpeechTranscriber assets, then retain the on-device SFSpeech path.
            if(TIOAppleAILoaded()&&audio.length<=cap){
                dispatch_semaphore_t ready=dispatch_semaphore_create(0);self.waiter=ready;NSObject *lock=[NSObject new];__block BOOL installed=NO,closed=NO;
                TIOAppleSpeechStatus(locale,^(NSDictionary *status){@synchronized(lock){if(!closed)installed=[status[@"installed"] boolValue];}dispatch_semaphore_signal(ready);});
                long timeout=dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC));@synchronized(lock){closed=YES;}
                if(!timeout&&installed&&!self.cancelled){
                    dispatch_semaphore_t done=dispatch_semaphore_create(0);self.waiter=done;__block NSString *result=nil,*failure=nil;__block BOOL finished=NO;
                    self.activeTask=TIOAppleSpeechTranscribe(copy,locale,^(double fraction){stage(@"transcribing",fraction);},^(NSString *text,NSString *errorCode){@synchronized(lock){if(!finished){result=text;failure=errorCode;finished=YES;}}dispatch_semaphore_signal(done);});
                    if(self.activeTask){long expired=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(14400+120)*NSEC_PER_SEC));@synchronized(lock){finished=YES;if(!expired&&!self.cancelled&&!failure)markdown=result;}
                        if(expired||self.cancelled){id task=self.activeTask;SEL cancel=NSSelectorFromString(@"cancel");if([task respondsToSelector:cancel])((void(*)(id,SEL))objc_msgSend)(task,cancel);}
                    }
                    self.activeTask=nil;if([failure isEqual:@"cancelled"]){code=@"cancelled";break;}if(markdown)break;
                }
                self.waiter=nil;if(self.cancelled){code=@"cancelled";break;}
            }
            NSMutableArray *segments=[NSMutableArray new];
            while(audio.framePosition<cap&&!self.cancelled){AVAudioFramePosition start=audio.framePosition;NSString *text=[self recognize:audio locale:locale frames:MIN((AVAudioFramePosition)(rate*50),cap-start) code:&code];if(!text)break;[segments addObject:@{@"t":@((double)start/rate),@"text":text}];stage(@"transcribing",MIN(1,(double)audio.framePosition/cap));}
            if(self.cancelled)code=@"cancelled";if(!code)markdown=TIOTranscriptMarkdown(segments);
        }while(NO);
        if(directory)[NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
        dispatch_async(dispatch_get_main_queue(),^{completion(markdown,code?TIOAppleErrorMessage(code):nil);});
    }});
}
@end
#endif
