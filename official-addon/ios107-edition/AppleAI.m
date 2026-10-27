#if TIO_APPLE_AI
#import "AppleAI.h"
#import "AppleAICore.h"
#import "TIOLanguage.h"
#import <Speech/Speech.h>
#import <dlfcn.h>
#import <objc/message.h>
static void TAIMain(dispatch_block_t block){if(NSThread.isMainThread)block();else dispatch_sync(dispatch_get_main_queue(),block);}
static void *TAIHandle;
static NSDictionary *TAILoad;
static void TAILoadModule(void){
    NSCAssert(NSThread.isMainThread,@"main thread");
    static dispatch_once_t once;dispatch_once(&once,^{
        TAISetLanguageProvider(^{return TIOUILanguage();});
        NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TurboAppleAI.dylib"]?:@"";
        BOOL exists=path.length&&[NSFileManager.defaultManager fileExistsAtPath:path];NSString *error=@"";
        if(@available(iOS 26.0,*)){if(exists){dlerror();TAIHandle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);if(!TAIHandle){const char *reason=dlerror();error=reason?[NSString stringWithUTF8String:reason]:@"";if(error.length>300)error=[error substringToIndex:300];}}}
        Class probe=TAIHandle?NSClassFromString(@"TIOAppleAIProbe"):Nil;SEL version=NSSelectorFromString(@"moduleVersion");
        NSString *module=[probe respondsToSelector:version]?((id(*)(id,SEL))objc_msgSend)(probe,version):@"";
        TAILoad=@{@"loaded":@(TAIHandle!=NULL),@"exists":@(exists),@"path":path,@"error":error?:@"",@"module":module?:@""};
    });
    Class probe=TAIHandle?NSClassFromString(@"TIOAppleAIProbe"):Nil;SEL language=NSSelectorFromString(@"setUILanguage:");
    if([probe respondsToSelector:language])((void(*)(id,SEL,id))objc_msgSend)(probe,language,TIOUILanguage());
}
NSDictionary *TIOAppleAILoadStatus(void){__block NSDictionary *value;TAIMain(^{TAILoadModule();value=TAILoad;});return value;}
BOOL TIOAppleAILoaded(void){return [TIOAppleAILoadStatus()[@"loaded"] boolValue];}
NSDictionary *TIOAppleModelAvailability(void){__block NSDictionary *value;TAIMain(^{
    if(@available(iOS 26.0,*)){TAILoadModule();if(!TAIHandle){value=@{@"available":@NO,@"reason":[TAILoad[@"exists"] boolValue]?@"loadFailed":@"moduleMissing"};return;}
        Class cls=NSClassFromString(@"TIOAppleLLM");SEL selector=NSSelectorFromString(@"availability");
        value=[cls respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(cls,selector):@{@"available":@NO,@"reason":@"moduleOld"};
        if(![value isKindOfClass:NSDictionary.class])value=@{@"available":@NO,@"reason":@"moduleOld"};
    }else value=@{@"available":@NO,@"reason":@"osTooOld"};
});return value;}
id TIOAppleModelRespond(NSString *q,NSArray *history,NSString *instructions,NSString *language,BOOL stream,void(^update)(NSString *,BOOL,NSString *)){
    __block id task=nil;TAIMain(^{
        if(![TIOAppleModelAvailability()[@"available"] boolValue])return;
        Class cls=NSClassFromString(@"TIOAppleLLM");SEL selector=NSSelectorFromString(@"respondTo:history:instructions:language:stream:update:");
        if([cls respondsToSelector:selector])task=((id(*)(id,SEL,id,id,id,id,BOOL,id))objc_msgSend)(cls,selector,q,history,instructions,language,stream,[update copy]);
    });return task;
}
void TIOAppleAIProbe(void(^completion)(NSDictionary *)) {TAIMain(^{
    NSMutableDictionary *report=[@{@"loadStatus":TIOAppleAILoadStatus(),@"speech.authorization":@([SFSpeechRecognizer authorizationStatus]),@"ffmpegKit":@(NSClassFromString(@"FFmpegKit")!=Nil),@"os":NSProcessInfo.processInfo.operatingSystemVersionString} mutableCopy];
    for(NSString *code in @[@"en-US",@"zh-CN"]){SFSpeechRecognizer *recognizer=[[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:code]];NSString *prefix=[@"sf." stringByAppendingString:code];report[[prefix stringByAppendingString:@".onDevice"]]=@(recognizer.supportsOnDeviceRecognition);report[[prefix stringByAppendingString:@".available"]]=@(recognizer.isAvailable);}
    Class probe=TAIHandle?NSClassFromString(@"TIOAppleAIProbe"):Nil;SEL selector=NSSelectorFromString(@"runWithCompletion:");
    if([probe respondsToSelector:selector])((void(*)(id,SEL,id))objc_msgSend)(probe,selector,^(NSDictionary *facts){TAIMain(^{if([facts isKindOfClass:NSDictionary.class])[report addEntriesFromDictionary:facts];completion([report copy]);});});
    else {report[@"fm.available"]=@NO;report[@"fm.reason"]=TIOAppleModelAvailability()[@"reason"];completion([report copy]);}
});}
NSString *TIOAppleAIStatusLine(void){NSDictionary *availability=TIOAppleModelAvailability();return [availability[@"available"] boolValue]?TIOText(@"apple.status.ready"):TIOAppleErrorMessage(availability[@"reason"]);}
void TIOAppleSpeechStatus(NSString *locale,void(^completion)(NSDictionary *)){TAIMain(^{
    Class cls=TIOAppleAILoaded()?NSClassFromString(@"TIOAppleSpeech"):Nil;SEL selector=NSSelectorFromString(@"statusForLocale:completion:");
    if([cls respondsToSelector:selector])((void(*)(id,SEL,id,id))objc_msgSend)(cls,selector,locale,[completion copy]);else completion(@{@"installed":@NO,@"assets":@"unsupported",@"reason":@"moduleOld"});
});}
void TIOAppleSpeechPrepare(NSString *locale,void(^progress)(double),void(^completion)(NSString *)){TAIMain(^{
    Class cls=TIOAppleAILoaded()?NSClassFromString(@"TIOAppleSpeech"):Nil;SEL selector=NSSelectorFromString(@"prepareLocale:progress:completion:");
    if([cls respondsToSelector:selector])((void(*)(id,SEL,id,id,id))objc_msgSend)(cls,selector,locale,[progress copy],[completion copy]);else completion(@"moduleOld");
});}
id TIOAppleSpeechTranscribe(NSURL *file,NSString *locale,void(^progress)(double),void(^completion)(NSString *,NSString *)){__block id task=nil;TAIMain(^{
    Class cls=TIOAppleAILoaded()?NSClassFromString(@"TIOAppleSpeech"):Nil;SEL selector=NSSelectorFromString(@"transcribeFile:locale:progress:completion:");
    if([cls respondsToSelector:selector])task=((id(*)(id,SEL,id,id,id,id))objc_msgSend)(cls,selector,file,locale,[progress copy],[completion copy]);
});return task;}
#endif
