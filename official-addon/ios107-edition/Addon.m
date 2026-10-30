#if TIO_APPLE_AI
#import "AppleAI.h"
#import "AppleAICore.h"
#import "NoNetworkTurn.h"
#endif
#import "camera-v1/CameraUI.h"
extern BOOL TDPPhoneAutomaticIdle(void);
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import "Core.h"
#import "LanguageFlag.h"
#import "LocalTranslationEntry.h"
#import "RecordingExports.h"
#import "RecordingText.h"
#import "AlwaysOnAudio.h"
#import "WebSearch.h"
#import "TodoRuntime.h"
#import "GlassesChannelHook.h"
#import "TodoProtocol.h"
#import "MusicPlayer.h"
#import "TDPhoneBridge.h"
#import "PrivateBootstrap.h"
#if TIO_MAPKIT_ENABLED
#import "MapKitNavigationUI.h"
#endif
#import "ResearchCatalog.h"
#import "ExperimentalOTAUI.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import <math.h>
#import "TIOConfirm.h"
#import "TIODesign.h"
#import "ProtocolContext.h"
#import "OTAWizardModel.h"
#import "ExperimentalOTAGuard.h"
#import "Brightness.h"
#import "MenuLayoutUI.h"
#import "WatchRemoteAddon.h"
#import "HomeTabBridge.h"
#import "KnowledgeUI.h"
#import "KnowledgeClient.h"
#import "A2UIProbe.h"
#import "DashboardCard.h"
#import "EditorUI.h"
#import "AppUI.h"
#import "EditorAI.h"
#import "GlassesLogProbe.h"
#import "SubtitleHUD.h"
#import "VoiceTTS.h"
#if __has_include("TIOLanguage.h")
#import "TIOLanguage.h"
static NSString *AddonUILanguage(void){NSString *l=TIOUILanguage();return TIOScriptLanguageIsChinese(l)?@"zh-Hans":@"en";}
#else
static NSString *AddonUILanguage(void){NSString *l=NSLocale.preferredLanguages.firstObject?:@"en";return TIOScriptLanguageIsChinese(l)?@"zh-Hans":@"en";}
#endif
#if TIO_IMAGE_RX_LAB
#import "ImageUploadUI.h"
#import "ClenchLabUI.h"
#endif
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneUI.h"
#endif

#ifndef TIO_TARGET_BUNDLE_ID
#define TIO_TARGET_BUNDLE_ID "com.rayneo.venus.pub"
#endif
static NSString *const TargetBundle=@TIO_TARGET_BUNDLE_ID;

// No Frida, inline patching, device credentials or official token access.
static NSString *const Domain=@"io.turboio.official-private-addon";
static NSUserDefaults *Prefs;
static TIOTranscriptArchive *Archive;
static dispatch_queue_t ArchiveQueue;
static NSString *Diagnostic=/*i18n:id*/@"尚未收到回调";
static BOOL HooksReady=NO;
static UIButton *Entry;
static void (*OriginalAsr)(id,SEL,id,BOOL,id);
static void (*OriginalNlp)(id,SEL,id);
static void (*OriginalComplete)(id,SEL);
static void (*OriginalAlwaysOn)(id,SEL,id);
static void (*OriginalAudioStart)(id,SEL);
static BOOL VoiceExitReady=NO;
static NSUInteger CompletionEvents;
static TIOVoiceTTS *VoiceTTS;

static NSDictionary *KeyQuery(NSString *host) {return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Domain,(__bridge id)kSecAttrAccount:host};}
static NSString *ReadKey(NSString *host) {
    NSMutableDictionary *q=[KeyQuery(host) mutableCopy];q[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef out=NULL; if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&out)!=errSecSuccess)return @"";
    return [[NSString alloc]initWithData:CFBridgingRelease(out) encoding:NSUTF8StringEncoding]?:@"";
}
static BOOL TTSOn(void){return [Prefs boolForKey:@"ttsEnabled"];}
static BOOL StoreKey(NSString *host,NSString *key) {
    NSDictionary *q=KeyQuery(host);
    if(!key.length){OSStatus s=SecItemDelete((__bridge CFDictionaryRef)q);return s==errSecSuccess||s==errSecItemNotFound;}
    NSDictionary *attrs=@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);
    if(result==errSecItemNotFound){NSMutableDictionary *all=[q mutableCopy];[all addEntriesFromDictionary:attrs];result=SecItemAdd((__bridge CFDictionaryRef)all,NULL);}
    return result==errSecSuccess;
}
static void ImportPrivateBootstrap(void){
    // User-requested private IPA only. Never log resource data or overwrite a
    // user's existing configuration. The resource remains extractable in IPA.
    if([Prefs boolForKey:@"privateBootstrapImported"])return;
    if([[Prefs stringForKey:@"endpoint"] length])return;
    NSString *path=[NSBundle.mainBundle pathForResource:@"TurboIOPrivateBootstrap" ofType:@"json"];
    if(!path||[[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>16384)return;
    NSDictionary *j=TIOPrivateBootstrapConfig([NSData dataWithContentsOfFile:path]);if(!j)return;
    NSString *endpoint=[TIOValidateEndpoint(j[@"endpoint"]) absoluteString];
    if(!ReadKey(endpoint).length&&!StoreKey(endpoint,j[@"modelKey"]))return;
    if(!ReadKey(@"https://api.search.tinyfish.ai").length&&!StoreKey(@"https://api.search.tinyfish.ai",j[@"tinyfishKey"]))return;
    [Prefs setObject:endpoint forKey:@"endpoint"];[Prefs setObject:j[@"model"] forKey:@"model"];
    for(NSString *k in @[@"tinyfishEnabled",@"deepseekDisableThinking",@"voiceExitCommands"])[Prefs setObject:j[k] forKey:k];
    [Prefs setBool:YES forKey:@"privateBootstrapImported"];
}
static id Get(id obj,NSString *key) {if(!obj)return nil;@try{return [obj valueForKey:key];}@catch(NSException *e){return nil;}}
static NSString *String(id obj) {return [obj isKindOfClass:NSString.class]?obj:@"";}
static UIViewController *TopController(void) {
    UIWindow *window=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if(scene.activationState==UISceneActivationStateForegroundActive && [scene isKindOfClass:UIWindowScene.class]) {
        for(UIWindow *w in ((UIWindowScene *)scene).windows) if(w.isKeyWindow){window=w;break;}
    }
    // Official Flutter 1.0.2 uses the legacy application window lifecycle.
    if(!window){for(UIWindow *w in UIApplication.sharedApplication.windows)if(w.isKeyWindow){window=w;break;}}
    UIViewController *c=window.rootViewController;while(c.presentedViewController)c=c.presentedViewController;return c;
}
static void Alert(NSString *t,NSString *m){TIONotice(nil,t,m);}

@interface TIORequest : TIOWebChatRequest
@property(nonatomic,copy) NSArray<NSDictionary *> *history;
#if TIO_APPLE_AI
@property(nonatomic) BOOL voiceTurn;
@property(nonatomic) BOOL configMissing;
@property(nonatomic) BOOL appleCancelled;
@property(nonatomic) id appleTask;
- (void)startAppleQuestion:(NSString *)question marker:(BOOL)marker;
#endif
- (void)startQuestion:(NSString *)question;
@end
@implementation TIORequest
#if TIO_APPLE_AI
- (void)startAppleQuestion:(NSString *)question marker:(BOOL)marker {
    NSString *language=TIOAppleLanguageForText(question);
    void(^outer)(NSString *,BOOL,NSString *)=[self.update copy];__weak typeof(self) weak=self;
    id task=TIOAppleModelRespond(question,self.history?:@[],TIOAppleInstructions(language,[Prefs stringForKey:@"aboutMe"]),language,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,^(NSString *text,BOOL done,NSString *code){
        typeof(self) s=weak;if(!s||s.appleCancelled)return;
        if(outer)outer([(marker?TIOAppleFallbackMarker(language):@"") stringByAppendingString:text?:@""],done,code?TIOAppleErrorMessage(code):nil);
    });self.appleTask=task;
    if(!task&&!self.appleCancelled&&outer)outer(@"",YES,TIOAppleErrorMessage(TIOAppleModelAvailability()[@"reason"]?:@"other"));
}
- (void)cancel {self.appleCancelled=YES;SEL selector=NSSelectorFromString(@"cancel");if([self.appleTask respondsToSelector:selector])((void(*)(id,SEL))objc_msgSend)(self.appleTask,selector);self.appleTask=nil;[super cancel];}
#endif
- (void)startQuestion:(NSString *)question {
#if TIO_APPLE_AI
    NSInteger appleMode=[Prefs integerForKey:@"mode"];
    if(TIOAppleShouldUseAppleMode(appleMode,self.voiceTurn)){[self startAppleQuestion:question marker:NO];return;}
    if(self.voiceTurn&&appleMode==2){
        void(^outer)(NSString *,BOOL,NSString *)=[self.update copy];__weak typeof(self) weak=self;
        self.update=^(NSString *text,BOOL done,NSString *error){typeof(self) s=weak;if(!s||s.appleCancelled)return;
            if(done&&error&&TIOAppleShouldFallback(appleMode,s.voiceTurn,[Prefs boolForKey:@"appleFallback"],s.modelTransportFailed||s.configMissing,text.length)&&[TIOAppleModelAvailability()[@"available"] boolValue]){s.update=outer;[s startAppleQuestion:question marker:YES];return;}
            if(outer)outer(text,done,error);
        };
    }
#endif
    NSString *endpoint=[Prefs stringForKey:@"endpoint"]?:@"",*model=[Prefs stringForKey:@"model"]?:@"";
    NSURL *url=TIOValidateEndpoint(endpoint); NSString *key=ReadKey(endpoint);
    NSDictionary *payload=TIOChatRequestWithHistory(model,question,_history?:@[]);
    if(!url||!payload||!key.length){
#if TIO_APPLE_AI
        self.configMissing=YES;
#endif
        if(self.update)self.update(@"",YES,TIOWebStatusText(@"config.missing",TIOScriptLanguage(question,AddonUILanguage())));return;}
    // Optional provider extension, sent only when explicitly selected by user.
    NSMutableDictionary *body=[payload mutableCopy];if([Prefs boolForKey:@"deepseekDisableThinking"])body[@"thinking"]=@{@"type":@"disabled"};
    NSString *searchKey=[Prefs boolForKey:@"tinyfishEnabled"]?ReadKey(@"https://api.search.tinyfish.ai"):@"";
    TIOImportKnowledgeConnection();if(TIOKnowledgeEnabled()){TIOKnowledgeClient *client=[TIOKnowledgeClient new];self.cancelKnowledge=^{[client cancel];};self.knowledgeQuery=^(NSDictionary *input,BOOL statusOnly,void(^done)(NSDictionary *)){void(^completion)(NSDictionary *,NSString *)=^(NSDictionary *j,NSString *e){done(j?:@{@"status":@"failed"});};if(statusOnly)[client refreshLast:completion];else [client query:input completion:completion];};}
    [self startEndpoint:url key:key payload:body searchKey:searchKey];
}
@end

@interface TIOController : NSObject
@property(nonatomic) TIORequest *request;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,weak) id listener;
@property(nonatomic) NSString *asr;
@property(nonatomic) NSString *sid;
@property(nonatomic) id responseTemplate;
@property(nonatomic) NSString *emitted;
@property(nonatomic) BOOL ownsTurn;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL responseDone;
@property(nonatomic) NSMutableSet<NSString *> *seenFinals;
@property(nonatomic) NSString *captureEpoch;
@property(nonatomic) TIOConversationHistory *history;
@property(nonatomic,copy) NSString *requestQuestion;
@property(nonatomic) BOOL voiceExited;
@property(nonatomic) TIOTodoTurnGate *taskGate;
@property(nonatomic,copy) NSString *officialTTSAnswer;
@property(nonatomic) BOOL officialTTSActive;
- (BOOL)exitVoice;
#if TIO_APPLE_AI
- (BOOL)takeLocalTurn:(id)response question:(NSString *)question listener:(id)listener;
#endif
@end
static TIOController *Controller;

static id CopyResponse(id source,NSString *answer,BOOL final) {
    // Only use the observed wrapper class. Do not call guessed Swift addresses.
    Class cls=NSClassFromString(@"RayNeoNlpResultWrapper");if(!cls||![source isKindOfClass:cls])return nil;
    id copy=[cls new];
    @try {
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"command",@"hasNextRound",@"rawData"]) {id v=[source valueForKey:field];if(v)[copy setValue:v forKey:field];}
        [copy setValue:answer forKey:@"answer"];[copy setValue:@"" forKey:@"spoken"];[copy setValue:@(final) forKey:@"finished"];
    }@catch(NSException *e){return nil;}
    return copy;
}
@implementation TIOController
- (instancetype)init {if((self=[super init])){_seenFinals=[NSMutableSet set];_captureEpoch=NSUUID.UUID.UUIDString;_history=[TIOConversationHistory new];_taskGate=[TIOTodoTurnGate new];}return self;}
- (void)cancel {++_generation;[_request cancel];_request=nil;_ownsTurn=NO;_started=NO;_responseDone=NO;_responseTemplate=nil;_emitted=@"";_officialTTSAnswer=@"";_officialTTSActive=NO;[Prefs setObject:@"controller.cancel" forKey:@"ttsLastReset"];[VoiceTTS cancel];}
- (BOOL)exitVoice {
    if(!VoiceExitReady)return NO;
    Class cls=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
    id helper=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"shared"));
    if(!helper)return NO;
    // Cancel our stream before asking the official workflow to stop, so a late
    // network delta cannot re-open the page. New audio start releases this gate.
    [self cancel];_voiceExited=YES;_asr=@"";_sid=@"";
    ((void(*)(id,SEL))objc_msgSend)(helper,NSSelectorFromString(@"stopWorkflow"));
    Diagnostic=TIOText(@"语音退出已调用官方停止入口；等待镜片确认");
    return YES;
}
- (void)acceptAsr:(NSString *)text finished:(BOOL)final session:(NSString *)sid listener:(id)listener {
    if(![Prefs integerForKey:@"mode"]||!text.length)return;
    if(!final){if(_ownsTurn&&_started){[self cancel];}_asr=text;return;}
    NSString *identity=[NSString stringWithFormat:@"%@|%@",sid,text];if([_seenFinals containsObject:identity])return;
    if(_seenFinals.count>=256)[_seenFinals removeAllObjects];[_seenFinals addObject:identity];
    [self cancel];[_taskGate beginTurn];_listener=listener;_asr=text;_sid=sid;
    // Do not seize an unknown response shape. Wait for an eligible official template.
    Diagnostic=TIOText(@"ASR final 已到达，等待官方聊天回包模板");
}
- (void)emitText:(NSString *)text done:(BOOL)done error:(NSString *)error generation:(NSUInteger)gen {
    if(gen!=_generation||!_ownsTurn||_responseDone||!_listener)return;
    if(error)text=[(_emitted?:@"") stringByAppendingFormat:@"\n[%@]",error];
    NSString *delta=TIOAppendDelta(_emitted?:@"",text);
    if(!delta){
        // Close an owned turn even if a provider rewrites a previous chunk.
        // Keep ownership until the next turn so late official chunks stay suppressed.
        [_request cancel];_request=nil;_responseDone=YES;
        id failure=CopyResponse(_responseTemplate,TIOWebStatusText(@"stream.rewritten",TIOScriptLanguage(_requestQuestion?:@"",AddonUILanguage())),YES);
        if(failure)OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),failure);
        OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));
        Diagnostic=@"模型输出不是追加流，已提交错误收尾";return;
    }
    if(delta.length||done){id wrapper=CopyResponse(_responseTemplate,delta,done);if(!wrapper){[_request cancel];_request=nil;_responseDone=YES;OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));Diagnostic=@"回复模板复制失败，已提交收尾";return;}OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),wrapper);_emitted=[text copy];if(TTSOn()&&!error)[VoiceTTS appendFullText:text finished:done];}
    if(done){_responseDone=YES;if(!error&&_request&&text.length)[_history appendQuestion:_requestQuestion answer:text];Diagnostic=error?@"自定义回复失败，已提交错误收尾":@"自定义回复结束，已提交官方收尾回调";OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));}
}
- (BOOL)receiveNlp:(id)response listener:(id)listener {
    NSString *domain=String(Get(response,@"domain")),*intent=String(Get(response,@"intent")),*sub=String(Get(response,@"sub"));
    BOOL offline=[Get(response,@"offline") boolValue];
    // Metadata whitelist: no question, answer, rawData, IDs or tokens in diagnostics.
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    NSString *(^safe)(NSString *)=^NSString *(NSString *s){return s.length<64&&[s rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound?s:@"(other)";};
    Diagnostic=[NSString stringWithFormat:@"NLP domain=%@ / intent=%@ / sub=%@ / offline=%d",safe(domain),safe(intent),safe(sub),offline];
    id command=Get(response,@"command");
    if([_taskGate observeDomain:domain intent:intent command:String(Get(command,@"name")) params:Get(command,@"params") session:String(Get(response,@"sessionId")) expectedSession:_sid?:@"" sameListener:listener==_listener]){
        // Invalidate in-flight private deltas before forwarding the official
        // command. Keep subsequent acknowledgement and completion official too.
        [self cancel];Diagnostic=TIOText(@"官方待办接管本轮；自有回复已取消，完成回调交回官方");
    }
    if(_taskGate.official)return NO;
    BOOL eligible=TIOIsEligibleChat(domain,intent,sub,offline,Get(response,@"command")!=nil);
    if(eligible)
        [Prefs setObject:@"chat" forKey:@"verifiedChatDomain"];
    if(![Prefs integerForKey:@"mode"]||listener!=_listener||!_asr.length||offline)return NO;
    NSString *sid=String(Get(response,@"sessionId"));if(_sid.length&&sid.length&&![_sid isEqual:sid])return NO;
    // Exact chat-domain allowlist must be confirmed on the current phone. Skill commands are never replaced.
    NSString *approved=[Prefs stringForKey:@"verifiedChatDomain"];
    if(!approved.length||![domain isEqual:approved]||!eligible)return NO;
    if(_ownsTurn)return YES;
    _responseTemplate=response;_ownsTurn=YES;_started=YES;_emitted=@"";NSUInteger gen=_generation;
    if([Prefs integerForKey:@"mode"]==1){
        NSString *test=[TIOText(@"私用模型测试 ") stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self emitText:test done:YES error:nil generation:gen];});
    }else{
        _request=[TIORequest new];
#if TIO_APPLE_AI
        _request.voiceTurn=YES;
#endif
        __weak typeof(self) weakSelf=self;
        TIOTodoSetChatContext(listener,response);
        _request.createTodo=^(NSString *title,void (^completion)(NSDictionary *result)){TIOTodoCreateFromTool(title,completion);};
        _requestQuestion=[_asr copy];_request.history=[_history snapshot];
        _request.update=^(NSString *text,BOOL done,NSString *error){[weakSelf emitText:text done:done error:error generation:gen];};
        [_request startQuestion:_asr];
    }
    return YES;
}
#if TIO_APPLE_AI
- (BOOL)takeLocalTurn:(id)response question:(NSString *)question listener:(id)listener {
    NSString *trim=[question stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(listener!=_listener||_ownsTurn||_voiceExited||!trim.length)return NO;
    NSString *prior=_asr;NSUInteger generation=_generation;_asr=trim;
    BOOL accepted=[self receiveNlp:response listener:listener];
    if(!accepted&&generation==_generation)_asr=prior;
    return accepted;
}
#endif
- (id)observeOfficialVoice:(id)response {
    if(!TTSOn()||!TIOIsEligibleChat(String(Get(response,@"domain")),String(Get(response,@"intent")),String(Get(response,@"sub")),[Get(response,@"offline") boolValue],Get(response,@"command")!=nil))return response;
    NSString *answer=String(Get(response,@"answer"));if(!answer.length)return response;
    if(!_officialTTSActive){_officialTTSActive=YES;_officialTTSAnswer=@"";[Prefs setObject:@"official.answer" forKey:@"ttsLastReset"];[VoiceTTS beginTurn];}
    NSString *prior=_officialTTSAnswer?:@"";
    NSString *full=[answer hasPrefix:prior]?answer:([prior hasPrefix:answer]?prior:[prior stringByAppendingString:answer]);
    _officialTTSAnswer=full;
    [VoiceTTS appendFullText:full finished:[Get(response,@"finished") boolValue]];
    // Only for eligible chat text: suppress a potential official spoken-text
    // duplicate while preserving the wrapper's display and command metadata.
    return String(Get(response,@"spoken")).length?(CopyResponse(response,answer,[Get(response,@"finished") boolValue])?:response):response;
}
- (void)completeOfficialVoice {
    if(_officialTTSActive&&_officialTTSAnswer.length)[VoiceTTS appendFullText:_officialTTSAnswer finished:YES];
    _officialTTSActive=NO;_officialTTSAnswer=@"";
}
@end

#if TIO_APPLE_AI
static void AsrHook(id self,SEL cmd,id text,BOOL final,id sid) {
    NSString *copy=[String(text) copy],*session=[String(sid) copy];
    void (^work)(void)=^{
        BOOL duplicate=final&&[Controller.seenFinals containsObject:[NSString stringWithFormat:@"%@|%@",session,copy]];
        id token=TIONoNetworkBeginAsr(self,copy,final,session,duplicate,Controller.generation);
        @try {
            TIONoNetworkWillAsr(copy);
            if(final&&[Prefs boolForKey:@"voiceExitCommands"]&&TIOIsVoiceExitCommand(copy)&&[Controller exitVoice])return;
            if(Controller.voiceExited)return;
            if(copy.length&&[Prefs boolForKey:@"ttsEnabled"]){[Prefs setObject:@"user.asr" forKey:@"ttsLastReset"];[VoiceTTS cancel];}
            OriginalAsr(self,cmd,text,final,sid);
            [Controller acceptAsr:copy finished:final session:session listener:self];
            TIONoNetworkDidAcceptAsr(token,self,copy,final,session);
        } @finally { TIONoNetworkEndAsr(token); }
    };
    TIONoNetworkSubmit(TIONoNetworkAsrEvent,self,NO,work);
}
#else
static void AsrHook(id self,SEL cmd,id text,BOOL final,id sid) {
    NSString *copy=String(text),*session=String(sid);
    void (^work)(void)=^{
        if(final&&[Prefs boolForKey:@"voiceExitCommands"]&&TIOIsVoiceExitCommand(copy)&&[Controller exitVoice])return;
        if(Controller.voiceExited)return;
        // The official app reopens the microphone automatically after a
        // response. Only recognized user speech, not audio-start, is a barge-in.
        if(copy.length&&[Prefs boolForKey:@"ttsEnabled"]){[Prefs setObject:@"user.asr" forKey:@"ttsLastReset"];[VoiceTTS cancel];}
        OriginalAsr(self,cmd,text,final,sid);
        [Controller acceptAsr:copy finished:final session:session listener:self];
    };
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
#endif
#if TIO_APPLE_AI
static void AudioStartHook(id self,SEL cmd) {
    void (^work)(void)=^{TIONoNetworkAudioStart();TMMusicPauseForVoice();Controller.voiceExited=NO;[Controller.taskGate beginTurn];OriginalAudioStart(self,cmd);};
    TIONoNetworkSubmit(TIONoNetworkAudioEvent,self,NO,work);
}
#else
static void AudioStartHook(id self,SEL cmd) {
    void (^work)(void)=^{TMMusicPauseForVoice();Controller.voiceExited=NO;[Controller.taskGate beginTurn];OriginalAudioStart(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
#endif
#if TIO_APPLE_AI
static void NlpHook(id self,SEL cmd,id value) {
    void (^work)(void)=^{if(Controller.voiceExited)return;if(TIOTodoIsToolDispatching()){OriginalNlp(self,cmd,value);return;}if(TIONoNetworkNlp(self,value))return;TIOTodoObserveNlp(self,value);if(![Controller receiveNlp:value listener:self])OriginalNlp(self,cmd,[Controller observeOfficialVoice:value]);};
    void (^submit)(void)=^{TIONoNetworkSubmit(TIONoNetworkNlpEvent,self,TIOTodoIsToolDispatching(),work);};
    if(NSThread.isMainThread)submit();else dispatch_async(dispatch_get_main_queue(),submit);
}
#else
static void NlpHook(id self,SEL cmd,id value) {
    // Route decisions on the main queue to serialize ASR, cancellation and stream completion.
    void (^work)(void)=^{if(Controller.voiceExited)return;if(TIOTodoIsToolDispatching()){OriginalNlp(self,cmd,value);return;}TIOTodoObserveNlp(self,value);if(![Controller receiveNlp:value listener:self])OriginalNlp(self,cmd,[Controller observeOfficialVoice:value]);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
#endif
#if TIO_APPLE_AI
static void CompleteHook(id self,SEL cmd) {
    void (^work)(void)=^{CompletionEvents++;if(Controller.voiceExited)return;if(TIONoNetworkComplete(self))return;[Controller completeOfficialVoice];if(![Prefs integerForKey:@"mode"]||!(Controller.listener==self&&Controller.ownsTurn))OriginalComplete(self,cmd);};
    TIONoNetworkSubmit(TIONoNetworkCompleteEvent,self,NO,work);
}
#else
static void CompleteHook(id self,SEL cmd) {
    void (^work)(void)=^{CompletionEvents++;if(Controller.voiceExited)return;[Controller completeOfficialVoice];if(![Prefs integerForKey:@"mode"]||!(Controller.listener==self&&Controller.ownsTurn))OriginalComplete(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
#endif
static void AlwaysOnHook(id self,SEL cmd,id value) {
    OriginalAlwaysOn(self,cmd,value);
    if(![Prefs boolForKey:@"captureFinalText"]||![Get(value,@"finish") boolValue])return;
    NSString *text=String(Get(value,@"text")),*round=String(Get(value,@"roundId"));
    id r=Get(value,@"role");NSString *role=[r respondsToSelector:@selector(stringValue)]?[r stringValue]:String(r);
    NSString *identity=round.length?[NSString stringWithFormat:@"%@:%@",Controller.captureEpoch,round]:@"";
    dispatch_async(ArchiveQueue,^{NSError *error=nil;BOOL ok=[Archive recordText:text round:identity role:role at:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{Diagnostic=ok?TIOText(@"全天智记最终文字已保存到扩展本机归档"):TIOText(@"全天智记归档失败，官方数据未改");});});
}

// Leading glasses card: name, an optional firmware line and whether the RayNeo app has
// reported a device. Words plus a symbol; battery is not read passively. `detail` is the
// firmware the glasses themselves reported; with none observed it is nil and the line and its
// VoiceOver phrase are left out (the bundled candidate is not what the glasses run, and it
// belongs on the Glasses firmware row). stacked is set from the accessibility content size:
// the pill drops under the labels.
static UIView *TIOHubStatusCard(NSString *name,NSString *detail,TIODesignStatus status,NSString *word,BOOL stacked) {
    UIView *card=[UIView new];
    card.backgroundColor=TIODesignColor(TIODesignColorBgRaised);
    card.layer.cornerRadius=TIORadiusLG;card.layer.cornerCurve=kCACornerCurveContinuous;
    UIView *tile=[UIView new];tile.backgroundColor=TIODesignColor(TIODesignColorAccentSoft);tile.layer.cornerRadius=24;
    UIImageView *glyph=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"eyeglasses" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]]];
    glyph.tintColor=TIODesignColor(TIODesignColorAccent);glyph.contentMode=UIViewContentModeScaleAspectFit;
    glyph.translatesAutoresizingMaskIntoConstraints=NO;tile.translatesAutoresizingMaskIntoConstraints=NO;[tile addSubview:glyph];
    [NSLayoutConstraint activateConstraints:@[[tile.widthAnchor constraintEqualToConstant:48],[tile.heightAnchor constraintEqualToConstant:48],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],[glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor]]];
    UILabel *title=[UILabel new],*sub=[UILabel new];
    title.text=name;title.font=TIODesignFontWeight(TIODesignTextStyleHeadline,UIFontWeightSemibold);title.textColor=TIODesignColor(TIODesignColorLabel);
    sub.text=detail;sub.hidden=!detail.length;sub.font=TIODesignFont(TIODesignTextStyleSubheadline);sub.textColor=TIODesignColor(TIODesignColorLabelSecondary);
    for (UILabel *l in @[title,sub]) {l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;}
    UIStackView *labels=[[UIStackView alloc]initWithArrangedSubviews:@[title,sub]];labels.axis=UILayoutConstraintAxisVertical;labels.spacing=TIOSpace1/2;
    [labels setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIView *pill=TIODesignStatusPill(status,word);
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[tile,labels,pill]];
    stack.axis=stacked?UILayoutConstraintAxisVertical:UILayoutConstraintAxisHorizontal;
    stack.alignment=stacked?UIStackViewAlignmentLeading:UIStackViewAlignmentCenter;stack.spacing=TIOSpace3+TIOSpace1/2;
    [pill setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:TIOSpace4],[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-TIOSpace4],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:TIOSpace4],[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-TIOSpace4],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin]]];
    // One element; the pill's word is part of the sentence.
    card.isAccessibilityElement=YES;
    card.accessibilityLabel=detail.length?[NSString stringWithFormat:@"%@, %@, %@",name,[NSString stringWithFormat:TIOText(@"hub.card.firmware"),detail],word]:[NSString stringWithFormat:@"%@, %@",name,word];
    card.accessibilityTraits=UIAccessibilityTraitStaticText;card.accessibilityIdentifier=@"hub-glasses-card";
    return card;
}

@interface TIOPanel : UITableViewController
@property(nonatomic) TIORequest *testRequest;
@property(nonatomic,copy) NSString *page;
@property(nonatomic) NSArray<NSDictionary *> *sections;
@end

// Status text is bounded by composed characters so a model name or diagnostic
// cannot split an emoji or exceed the hub's per-language status budget.
static NSString *TIOHubBoundStatus(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return nil;
    NSUInteger limit = [TIOUILanguage() hasPrefix:@"zh"] ? 20 : 40;
    __block NSUInteger count=0, end=0, beforeLast=0;
    [value enumerateSubstringsInRange:NSMakeRange(0,value.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        if (count == limit) { *stop=YES; return; }
        beforeLast=end; count++; end=NSMaxRange(range);
    }];
    if (end == value.length) return value;
    // The ellipsis is part of the limit.
    return [[value substringToIndex:beforeLast] stringByAppendingString:@"…"];
}

@implementation TIOPanel
- (NSDictionary *)catalogRowForKey:(NSString *)key {
    for (NSDictionary *row in TIOHubCatalog()) if ([row[@"key"] isEqual:key]) return row;
    return nil;
}
- (void)updateCard {
    if (self.page.length) {self.tableView.tableHeaderView=nil;return;}
    // No firmware line: the catalog's code for the OTA row is the bundled candidate (TMG7), not what the glasses run, and the
    // glasses keep reporting their previous build identity until a flash has been done and read back.
    BOOL seen=TIOProtocolDevice().length>0;
    UIView *card=TIOHubStatusCard(TIOText(@"hub.card.name"),nil,
        seen?TIODesignStatusOk:TIODesignStatusNeutral,TIOText(seen?@"hub.card.detected":@"hub.card.notDetected"),
        UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory));
    UIView *holder=[UIView new];card.translatesAutoresizingMaskIntoConstraints=NO;[holder addSubview:card];
    [NSLayoutConstraint activateConstraints:@[[card.topAnchor constraintEqualToAnchor:holder.topAnchor constant:TIOSpace2],[card.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [card.leadingAnchor constraintEqualToAnchor:holder.layoutMarginsGuide.leadingAnchor],[card.trailingAnchor constraintEqualToAnchor:holder.layoutMarginsGuide.trailingAnchor]]];
    holder.layoutMargins=UIEdgeInsetsMake(0,TIOSpace4,0,TIOSpace4);
    self.tableView.tableHeaderView=holder;[self fitHeader];
}
- (void)fitHeader {
    UIView *header=self.tableView.tableHeaderView;CGFloat width=self.tableView.bounds.size.width;
    if (!header||width<=0) return;
    CGSize size=[header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height-size.height)>.5||fabs(header.frame.size.width-width)>.5) {header.frame=CGRectMake(0,0,width,size.height);self.tableView.tableHeaderView=header;}
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self fitHeader];}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {[super traitCollectionDidChange:previous];if(!self.page.length)[self updateCard];}
- (void)refresh {
    self.sections=TIOHubSections(self.page);
    self.title=self.page.length ? ([self catalogRowForKey:self.page][@"title"] ?: TIOText(@"hub.title")) : TIOText(@"hub.title");
    if (!self.page.length) {
        NSMutableString *body=[TIOText(@"hub.info.body") mutableCopy];
        for (NSString *infoKey in [[TIOStringTable() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![infoKey hasPrefix:@"hub.info.topic."]) continue;
            NSString *details=TIOText(infoKey);
            if ([infoKey isEqual:@"hub.info.topic.tools"]) {
                NSString *state=TIOText(TIOKnowledgeEnabled()?@"hub.info.tools.active":@"hub.info.tools.inactive");
                details=[NSString stringWithFormat:details,state];
            }
            [body appendFormat:@"\n\n%@",details];
        }
        [body appendFormat:@"\n\n%@: \n",TIOText(@"hub.info.codes")];
        for (NSDictionary *row in TIOHubCatalog()) {
            NSString *code=row[@"code"];
            if (code.length) [body appendFormat:@"%@ — %@\n",row[@"title"],code];
        }
        TIOAttachInfo(self,TIOText(@"hub.info.title"),body);
    }
    [self updateCard];
    [self.tableView reloadData];
}
- (void)viewDidLoad {
    [super viewDidLoad];self.page=self.page?:@"";TIOStyleResearchTable(self);
    self.tableView.tableHeaderView=nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelPanelTest) name:@"TIOResearchClosed" object:nil];
    for (NSString *name in @[@"TIOHubReload",TIOUILanguageDidChangeNotification,UIApplicationDidBecomeActiveNotification,TIOProtocolDeviceDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refresh];}
- (void)cancelPanelTest {[_testRequest cancel];_testRequest=nil;}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_testRequest cancel];}
- (void)close {[_testRequest cancel];[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return self.sections.count;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSDictionary *group=self.sections[section];
    if (!self.page.length && [group[@"section"] integerValue]==TIOHubSectionDeveloper && ![Prefs boolForKey:@"hubDeveloperExpanded"]) return 0;
    return [group[@"rows"] count];
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSDictionary *group=self.sections[section];
    if (self.page.length || [group[@"section"] integerValue]!=TIOHubSectionDeveloper) return nil;
    __weak typeof(self) weak=self;
    return TIOFoldHeader(group[@"title"],[Prefs boolForKey:@"hubDeveloperExpanded"],^{
        [Prefs setBool:![Prefs boolForKey:@"hubDeveloperExpanded"] forKey:@"hubDeveloperExpanded"];
        [weak.tableView reloadSections:[NSIndexSet indexSetWithIndex:section]
                     withRowAnimation:UIAccessibilityIsReduceMotionEnabled()?UITableViewRowAnimationNone:UITableViewRowAnimationFade];
    });
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.page.length || [self.sections[section][@"section"] integerValue]!=TIOHubSectionDeveloper) return UITableViewAutomaticDimension;
    UIView *fold=[self tableView:tableView viewForHeaderInSection:section];
    CGSize size=[fold systemLayoutSizeFittingSize:CGSizeMake(tableView.bounds.size.width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return MAX(TIOHitMin,ceil(size.height));
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSDictionary *group=self.sections[section];
    return !self.page.length && [group[@"section"] integerValue]==TIOHubSectionDeveloper ? nil : group[@"title"];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSDictionary *group=self.sections[section];
    return !self.page.length && [group[@"section"] integerValue]==TIOHubSectionDeveloper && [Prefs boolForKey:@"hubDeveloperExpanded"] ? TIOText(@"hub.developer.footer") : nil;
}
- (NSString *)statusForKey:(NSString *)key {
    NSString *status=nil;
    if ([key isEqual:@"language"]) {
        NSString *code=TIOUILanguageOverride();
        status=TIOText([@"hub.status.language." stringByAppendingString:[@[@"auto",@"en",@"zh"] containsObject:code]?code:@"auto"]);
    } else if ([key isEqual:@"languageStatus"]) status=TIOLanguageFlagStatus()[@"state"];
    else if ([key isEqual:@"mode"]) {
        NSInteger mode=[Prefs integerForKey:@"mode"];
        NSString *kind=mode==1?@"test":mode==2?@"custom":@"official"; // WP7 adds mode 3.
#if TIO_APPLE_AI
        if(mode==3)kind=@"apple";
#endif
        status=TIOText([@"hub.status.mode." stringByAppendingString:kind]);
    }
#if TIO_APPLE_AI
    else if ([key isEqual:@"appleAI"]) status=TIOAppleAIStatusLine();
#endif
    else if ([key isEqual:@"api"]) status=[Prefs stringForKey:@"model"]?:TIOText(@"hub.status.api.unset");
    else if ([key isEqual:@"tts"]) status=TIOText(TTSOn()?@"hub.status.tts.on":@"hub.status.tts.off");
    else if ([key isEqual:@"ttsSpeed"]) status=TIOText(@"hub.status.ttsSpeed");
    else if ([key isEqual:@"search"]) status=TIOText(ReadKey(@"https://api.search.tinyfish.ai").length?@"hub.status.search.ready":@"hub.status.search.nokey");
    else if ([key isEqual:@"knowledge"]) status=TIOText([TIOSelectedAgent() isEqual:@"Codex"]?@"hub.status.knowledge.codex":@"hub.status.knowledge.none");
    else if ([key isEqual:@"assistantMore"]) status=TIOText(@"hub.status.more");
    else if ([key isEqual:@"exit"]) status=VoiceExitReady?nil:TIOText(@"hub.status.exit.unavailable");
    else if ([key isEqual:@"history"]) {NSString *format=TIOText(@"hub.status.history");status=[NSString stringWithFormat:format,(unsigned long)[Controller.history snapshot].count];}
    else if ([key isEqual:@"tools"]) status=TIOText(@"hub.status.tools");
    else if ([key isEqual:@"navigation"]) status=TIOText(@"hub.status.navigation");
    else if ([key isEqual:@"focus"]) {
        NSUserDefaults *focus=[[NSUserDefaults alloc]initWithSuiteName:@"org.turboio.addon.focus"];
        NSTimeInterval remaining=[focus doubleForKey:@"end"]-NSDate.date.timeIntervalSince1970;
        if (remaining>0) {NSString *format=TIOText(@"hub.status.focus.running");status=[NSString stringWithFormat:format,TIOOTAFormatClock((NSInteger)ceil(remaining))];}
        else {NSString *format=TIOText(@"hub.status.focus.idle");status=[NSString stringWithFormat:format,(long)MAX(1,[focus integerForKey:@"minutes"]?:25)];}
    } else if ([key isEqual:@"recordings"]) status=TIOText(@"hub.status.recordings");
    else if ([key isEqual:@"lifelog"] || [key isEqual:@"capture"]) status=TIOText([Prefs boolForKey:@"captureFinalText"]?@"hub.status.lifelog.on":@"hub.status.lifelog.off");
    else if ([key isEqual:@"status"]) status=TIOText(HooksReady?@"hub.status.status.ok":@"hub.status.status.off");
    else if ([key isEqual:@"experimentalOTA"]) {
        NSDictionary *snapshot=TIOOTAWizardSnapshot(@{@"flash":TIOOTAFlashStatus()?:@{},@"feed":TIOExperimentalOTAFeedStatus()?:@{},@"guard":TIOOTAGuardStatus()?:@{},@"prefs":NSUserDefaults.standardUserDefaults.dictionaryRepresentation?:@{}});
        NSString *statusKey=TIOOTAWizardHubStatusKey(snapshot);
        status=[statusKey isEqual:@"ota.hub.download"] ? [NSString stringWithFormat:TIOText(statusKey),TIOOTAFormatClock([snapshot[@"downloadSecondsLeft"] integerValue])] : TIOText(statusKey);
    } else if ([key isEqual:@"aboutMe"]) status=[Prefs stringForKey:@"aboutMe"];
    return TIOHubBoundStatus(status);
}
- (UIView *)accessoryForKey:(NSString *)key {
    NSString *pref=nil;SEL action=NULL;BOOL enabled=YES;
    if ([key isEqual:@"tts"]) {pref=@"ttsEnabled";action=@selector(ttsToggle:);}
    else if ([key isEqual:@"thinking"]) {pref=@"deepseekDisableThinking";action=@selector(thinking:);}
    else if ([key isEqual:@"exit"]) {pref=@"voiceExitCommands";action=@selector(voiceExit:);enabled=VoiceExitReady;}
    else if ([key isEqual:@"search"]) {pref=@"tinyfishEnabled";action=@selector(searchToggle:);}
    else if ([key isEqual:@"capture"]) {pref=@"captureFinalText";action=@selector(capture:);}
    if (pref) {UISwitch *control=[UISwitch new];control.on=[Prefs boolForKey:pref];control.enabled=enabled;[control addTarget:self action:action forControlEvents:UIControlEventValueChanged];return control;}
    if ([key isEqual:@"ttsSpeed"]) return TIODesignValueAccessory([NSString stringWithFormat:@"%.3g×",TIOVoiceTTSSpeedMultiplier(Prefs)]);
    if ([key isEqual:@"agent"]) {__weak typeof(self) weak=self;return TIOAgentPicker(^{[weak.tableView reloadData];});}
    if ([key isEqual:@"ttsTest"]) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:TIOText(@"播放") forState:UIControlStateNormal];button.accessibilityIdentifier=@"research-tts-play-button";button.frame=CGRectMake(0,0,58,TIOHitMin);
        [button addTarget:self action:@selector(testTTS) forControlEvents:UIControlEventTouchUpInside];return button;
    }
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row=self.sections[ip.section][@"rows"][ip.row];NSString *key=row[@"key"];
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=row[@"title"];cell.detailTextLabel.text=[self statusForKey:key];
    cell.imageView.image=TIOHubIcon(row[@"icon"],[row[@"section"] integerValue]);
    cell.accessoryView=[self accessoryForKey:key];
    // Toggle rows read as one element: "Read answers aloud, switch, on".
    if ([cell.accessoryView isKindOfClass:UISwitch.class]) cell.accessoryView.accessibilityLabel=row[@"title"];
    if ([key isEqual:@"ttsSpeed"]) {cell.accessibilityValue=[NSString stringWithFormat:@"%.3g×",TIOVoiceTTSSpeedMultiplier(Prefs)];cell.accessibilityTraits|=UIAccessibilityTraitButton;}
    if (!cell.accessoryView && ![@[@"status",@"prompt",@"tools",@"ttsTest"] containsObject:key]) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier=[@"hub-" stringByAppendingString:key];
    return cell;
}

- (void)thinking:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"deepseekDisableThinking"];}
- (void)ttsSpeed {UIAlertController *alert=[UIAlertController alertControllerWithTitle:TIOText(@"hub.row.ttsSpeed") message:nil preferredStyle:UIAlertControllerStyleAlert];NSArray *titles=@[@"0.9×",@"1.0×",@"1.2×",@"1.35×",@"1.5×"];__weak typeof(self) weak=self;for(NSInteger step=0;step<5;step++)[alert addAction:[UIAlertAction actionWithTitle:titles[step] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;[Prefs setInteger:step forKey:@"ttsSpeedStep"];[weak.tableView reloadData];}]];[alert addAction:[UIAlertAction actionWithTitle:TIOText(@"取消") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:alert animated:YES completion:nil];}
- (void)ttsToggle:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"ttsEnabled"];if(!sender.on)[VoiceTTS cancel];[self.tableView reloadData];}
- (void)testTTS {
    [Prefs setObject:TIOText(@"已触发固定短句测试") forKey:@"ttsTestDiagnostic"];
    if(!TTSOn()){Alert(TIOText(@"hub.ttsTest.off.title"),TIOText(@"hub.ttsTest.off.message"));return;}
    [Prefs setObject:@"manual.test" forKey:@"ttsLastReset"];
    [VoiceTTS beginTurn];[VoiceTTS appendFullText:@"Turbo IO voice test. 这是中文语音测试。" /*i18n:keep*/ finished:YES];
    [Prefs setObject:VoiceTTS.status?:@"" forKey:@"ttsTestImmediate"];
    [self.tableView reloadData];
    __weak typeof(self) weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[Prefs setObject:VoiceTTS.status?:@"" forKey:@"ttsTestDiagnostic"];[weak.tableView reloadData];});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{[Prefs setObject:VoiceTTS.status?:@"" forKey:@"ttsTestDiagnostic"];[weak.tableView reloadData];});
}
- (void)voiceExit:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"voiceExitCommands"];}
- (void)searchToggle:(UISwitch *)sender {if(sender.on&&!ReadKey(@"https://api.search.tinyfish.ai").length){sender.on=NO;Alert(TIOText(@"请先配置"),TIOText(@"需要你自己的 TinyFish API Key。"));return;}[Prefs setBool:sender.on forKey:@"tinyfishEnabled"];[Controller cancel];}
- (void)configureAboutMe {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:TIOText(@"hub.row.aboutMe") message:TIOText(@"hub.alert.aboutMe.message") preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[Prefs stringForKey:@"aboutMe"];f.placeholder=TIOText(@"hub.aboutMe.placeholder");}];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=a;
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSString *v=TIOSanitizeAboutMe(weakAlert.textFields.firstObject.text);if(v.length)[Prefs setObject:v forKey:@"aboutMe"];else [Prefs removeObjectForKey:@"aboutMe"];TIOSetUserProfile(v);[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[Prefs removeObjectForKey:@"aboutMe"];TIOSetUserProfile(nil);[self.tableView reloadData];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)configureSearch {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:TIOText(@"TinyFish 搜索配置") message:TIOText(@"hub.alert.search.message") preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=TIOText(@"TinyFish API Key（不回显）");f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"保存并启用") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *key=a.textFields[0].text?:@"";a.textFields[0].text=@"";if((key.length&&(![key hasPrefix:@"sk-tinyfish-"]||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound||!StoreKey(@"https://api.search.tinyfish.ai",key)))||(!key.length&&!ReadKey(@"https://api.search.tinyfish.ai").length)){Alert(TIOText(@"未保存"),TIOText(@"Key 格式或钥匙串写入失败。"));return;}[Controller cancel];[Prefs setBool:YES forKey:@"tinyfishEnabled"];[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"移除本机搜索 Key") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[Controller cancel];[Prefs setBool:NO forKey:@"tinyfishEnabled"];BOOL ok=StoreKey(@"https://api.search.tinyfish.ai",@"");[self.tableView reloadData];if(!ok)Alert(TIOText(@"未移除"),TIOText(@"钥匙串删除失败；搜索已关闭。"));}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)testSearch {
    if(![Prefs boolForKey:@"tinyfishEnabled"]||!ReadKey(@"https://api.search.tinyfish.ai").length){Alert(TIOText(@"未启用"),TIOText(@"请先配置并开启 TinyFish 搜索。"));return;}
    [_testRequest cancel];_testRequest=[TIORequest new];__weak typeof(self) weak=self;
    _testRequest.update=^(NSString *text,BOOL done,NSString *error){if(done){typeof(self) strong=weak;Alert(TIOText(@"联网测试结果"),[NSString stringWithFormat:TIOText(@"实际搜索请求：%lu 次\n%@"),(unsigned long)strong.testRequest.searchCount,error?:text]);}};
    [_testRequest startQuestion:@"Search the web for the official address of the TinyFish Search API and answer in one sentence with the official source URL."];
}
- (void)capture:(UISwitch *)sender {
    if(!sender.on){[Prefs setBool:NO forKey:@"captureFinalText"];return;}
    sender.on=NO;
    TIOConfirm(self,TIOText(@"hub.confirm.capture.title"),TIOText(@"hub.alert.capture.message"),TIOText(@"hub.confirm.capture.action"),NO,^{Controller.captureEpoch=NSUUID.UUID.UUIDString;[Prefs setBool:YES forKey:@"captureFinalText"];[self.tableView reloadData];});
}
- (void)configure {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:TIOText(@"自有模型接口") message:TIOText(@"hub.alert.api.message") preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"https://…/v1/chat/completions";f.text=[Prefs stringForKey:@"endpoint"];f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=TIOText(@"模型名称");f.text=[Prefs stringForKey:@"model"];f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=TIOText(@"新 API Key（不回显）");f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *url=a.textFields[0].text?:@"",*model=a.textFields[1].text?:@"",*key=a.textFields[2].text?:@"";NSURL *valid=TIOValidateEndpoint(url);if(!valid||!TIOChatRequest(model,TIOText(@"测试"))){Alert(TIOText(@"未保存"),TIOText(@"需要有效的 HTTPS chat/completions 地址和模型名称。"));return;}url=valid.absoluteString;if(key.length&&!StoreKey(url,key)){Alert(TIOText(@"未保存"),TIOText(@"钥匙串写入失败。"));return;}[Controller cancel];if(![[Prefs stringForKey:@"endpoint"] isEqual:url]||![[Prefs stringForKey:@"model"] isEqual:model])[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[Prefs setObject:url forKey:@"endpoint"];[Prefs setObject:model forKey:@"model"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row=self.sections[ip.section][@"rows"][ip.row];NSString *key=row[@"key"];
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if ([TIOHubSections(key) count]) {TIOPanel *child=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];child.page=key;[self.navigationController pushViewController:child animated:YES];return;}
    [self openKey:key];
}
- (void)openKey:(NSString *)key {
#if TIO_APPLE_AI
    if([key isEqual:@"appleAI"]){[self.navigationController pushViewController:TIOAppleAIController() animated:YES];return;}
#endif
    UIViewController *screen=nil;
    if ([key isEqual:@"experimentalOTA"]) screen=TIOExperimentalOTAController();
#if TIO_MAPKIT_ENABLED
    else if ([key isEqual:@"navigation"]) screen=TIOMapKitNavigationController();
#endif
    else if ([key isEqual:@"camera"]) screen=TCCameraController();
    else if ([key isEqual:@"focus"]) screen=TIOFocusController();
    else if ([key isEqual:@"menuLayout"]) screen=TIOMenuLayoutController();
    else if ([key isEqual:@"brightness"]) screen=TIOBrightnessController();
    else if ([key isEqual:@"watchRemote"]) screen=TIOWatchRemoteController();
    else if ([key isEqual:@"developerApps"]) screen=TAPAppsController();
    else if ([key isEqual:@"dashboardEditor"]) {
        TCEAIConfigure(^NSDictionary *{NSString *e=[Prefs stringForKey:@"endpoint"]?:@"";return @{@"endpoint":e,@"model":[Prefs stringForKey:@"model"]?:@"",@"key":ReadKey(e)?:@"",@"disableThinking":@([Prefs boolForKey:@"deepseekDisableThinking"])};});
        screen=TCEEditorController();
    } else if ([key isEqual:@"language"]) {
        NSArray *values=@[@"auto",@"en",@"zh"];
        NSUInteger found=[values indexOfObject:TIOUILanguageOverride()];NSInteger selected=found==NSNotFound?0:(NSInteger)found;
        TIOChoose(self,TIOText(@"hub.row.language"),nil,@[TIOText(@"hub.language.auto"),TIOText(@"hub.language.en"),TIOText(@"hub.language.zh")],selected,nil,^(NSInteger index){
            if (index<0 || index>=values.count) return;
            TIOSetUILanguageOverride(values[index]);
            // WP1's setter invalidates its cache but does not post here.
            TIOUILanguage();
            [NSNotificationCenter.defaultCenter postNotificationName:TIOUILanguageDidChangeNotification object:nil];
            TIOHubReload();
        });return;
    } else if ([key isEqual:@"knowledge"]) {TIOOpenKnowledge(self);return;}
    else if ([key isEqual:@"music"]) screen=TMMusicController();
    else if ([key isEqual:@"localTranslation"]) {TIOOpenLocalTranslation(self);return;}
    else if ([key isEqual:@"diagnosticsRuntime"]) screen=TDDiagnosticsController();
    else if ([key isEqual:@"glassesLog"]) screen=TIOGlassesLogController();
#if TIO_IMAGE_RX_LAB && TIO_DISPLAY_PHONE
    else if ([key isEqual:@"displayPhone"]) screen=TDPPhoneController();
#endif
#if TIO_IMAGE_RX_LAB
    else if ([key isEqual:@"imageRXLab"]) screen=TIOImageUploadLabController();
    else if ([key isEqual:@"clenchLab"]) screen=TIOClenchLabController();
#endif
    else if ([key isEqual:@"dashboardCard"]) screen=TDCDashboardController();
    else if ([key isEqual:@"a2ui"]) screen=TIOA2UIController();
    else if ([key isEqual:@"subtitleHUD"]) screen=TIOSubtitleHUDController();
    else if ([key isEqual:@"ttsSpeed"]) {[self ttsSpeed];return;}
    else if ([key isEqual:@"ttsTest"]) {[self testTTS];return;}
    else if ([key isEqual:@"aboutMe"]) {[self configureAboutMe];return;}
    else if ([key isEqual:@"languageStatus"]) {
        NSDictionary *diagnostics=@{@"ui":TIOLanguageDiagnostics(),@"glasses":TIOLanguageFlagStatus()};
        NSData *data=[NSJSONSerialization dataWithJSONObject:diagnostics options:NSJSONWritingPrettyPrinted error:nil];
        TIONotice(self,TIOText(@"hub.row.languageStatus"),[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]?:@"{}");return;
    } else if ([@[@"tts",@"ttsSpeed",@"thinking",@"exit",@"capture",@"agent"] containsObject:key]) return;
    else if ([@[@"recordings",@"summary",@"lifelogText",@"lifelogAudio"] containsObject:key]) {
        NSUInteger index=[@[@"recordings",@"summary",@"lifelogText",@"lifelogAudio"] indexOfObject:key];
        Class cls=NSClassFromString(@[@"TIORecordingExportsPanel",@"TIORecordingTextPanel",@"TIOLifelogExportsPanel",@"TIOAlwaysOnAudioPanel"][index]);
        screen=[cls isSubclassOfClass:UITableViewController.class]?[(UITableViewController *)[cls alloc]initWithStyle:UITableViewStyleInsetGrouped]:[cls new];
    } else {[self performKey:key];return;}
    if (screen) [self.navigationController pushViewController:screen animated:YES];
}
- (void)performKey:(NSString *)key {
    if ([key isEqual:@"mode"]) {
        NSArray *titles=@[TIOText(@"hub.choose.mode.official"),TIOText(@"hub.choose.mode.test"),TIOText(@"hub.choose.mode.custom")]; // WP7 appends option 4.
#if TIO_APPLE_AI
        titles=[titles arrayByAddingObject:TIOText(@"hub.choose.mode.apple")];
#endif
        TIOChoose(self,TIOText(@"hub.choose.mode.title"),TIOText(@"hub.alert.mode.message"),titles,[Prefs integerForKey:@"mode"],nil,^(NSInteger i){
#if TIO_APPLE_AI
            if(i==3){NSDictionary *availability=TIOAppleModelAvailability();if(![availability[@"available"] boolValue]){Alert(TIOText(@"apple.model.unavailable"),TIOAppleErrorMessage(availability[@"reason"]));return;}}
#endif
            [Controller cancel];[Prefs setInteger:i forKey:@"mode"];[self.tableView reloadData];if(i&&![Prefs stringForKey:@"verifiedChatDomain"])Alert(TIOText(@"hub.notice.takeover.title"),TIOText(@"hub.notice.takeover.message"));
        });return;
    }
    if ([key isEqual:@"api"]) {[self configure];return;}
    if ([key isEqual:@"search"]) {[self configureSearch];return;}
    if ([key isEqual:@"searchTest"]) {[self testSearch];return;}
    if ([key isEqual:@"todoTest"]) {TIOOpenTodoRuntime(self);return;}
    if ([key isEqual:@"tools"]) {NSString *format=TIOText(@"hub.alert.tools.message");Alert(TIOText(@"hub.row.tools"),[NSString stringWithFormat:format,TIOKnowledgeEnabled()?TIOText(@"hub.info.tools.active"):TIOText(@"hub.info.tools.inactive")]);return;}
    if ([key isEqual:@"history"]) {TIOConfirm(self,TIOText(@"hub.confirm.history.title"),TIOText(@"hub.alert.history.message"),TIOText(@"hub.confirm.history.action"),YES,^{[Controller cancel];[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[self.tableView reloadData];});return;}
    if ([key isEqual:@"prompt"]) {Alert(TIOText(@"当前系统提示词"),TIOSystemPrompt([Prefs stringForKey:@"model"]?:TIOText(@"尚未配置")));return;}
    if ([key isEqual:@"apiTest"]) {[_testRequest cancel];_testRequest=[TIORequest new];__weak typeof(self) weakSelf=self;_testRequest.update=^(NSString *text,BOOL done,NSString *error){if(done){Alert(error?TIOText(@"API 测试失败"):TIOText(@"API 测试结果"),error?:text);weakSelf.testRequest=nil;}};[_testRequest startQuestion:@"Reply with exactly: API test passed."];return;}
    if ([key isEqual:@"archive"]) {dispatch_async(ArchiveQueue,^{NSError *error=nil;NSArray *urls=[Archive exportAt:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{if(!urls){Alert(TIOText(@"暂无可分享文件"),error.localizedDescription?:TIOText(@"导出失败，原件未改。"));return;}UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:urls applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:sheet animated:YES completion:nil];});});return;}
    if ([key isEqual:@"status"]) {NSString *message=[[TIOText(Diagnostic) stringByAppendingFormat:TIOText(@"\n官方完成回调：%lu；语音退出入口：%@"),(unsigned long)CompletionEvents,VoiceExitReady?TIOText(@"已校验"):TIOText(@"不可用")] copy];TIONotice(self,TIOText(@"hub.row.status"),message);[self.tableView reloadData];return;}
}
@end


// Simulator-only host uses these same UIKit controllers, no official binary,
// credentials, hardware hooks or network-backed model service.
#if TIO_UI_PREVIEW
UIViewController *TIOCreateTurboPreview(void){
    Prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.research.preview"];
    [Prefs registerDefaults:@{@"appleFallback":@YES,@"mode":@0,@"voiceExitCommands":@YES,@"ttsEnabled":@YES,@"hubDeveloperExpanded":@NO}];
    TIOSetUserProfile([Prefs stringForKey:@"aboutMe"]);
    VoiceTTS=[TIOVoiceTTS new];VoiceTTS.fallbackLanguage=AddonUILanguage();VoiceTTS.willBeginTurn=^{TMMusicPauseForVoice();};
    Controller=[TIOController new];Diagnostic=TIOText(@"界面预览：未连接眼镜，未加载官方通信库");
    ArchiveQueue=dispatch_queue_create("io.turboio.preview.archive",DISPATCH_QUEUE_SERIAL);
    Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ResearchPreview"]]];
    TIOPanel *root=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];root.page=@"";
    return TIOCreateTurboHub(root);
}
#endif

static BOOL TIOInsideTurboHub(UIViewController *top) {
    for(UIViewController *current=top;current;current=current.presentingViewController) {
        if(current.view.tag==7920||current.navigationController.view.tag==7920)return YES;
    }
    return NO;
}

@interface TIOEntryTarget : NSObject
+ (void)show;
@end
@implementation TIOEntryTarget
+ (void)show {
    UIViewController *top=TopController();
    if(!top||TIOInsideTurboHub(top))return;
    static UINavigationController *hub;
    if(!hub){TIOPanel *root=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];root.page=@"";hub=TIOCreateTurboHub(root);}
    [hub popToRootViewControllerAnimated:NO];Entry.hidden=YES;[top presentViewController:hub animated:YES completion:nil];
}
@end
static BOOL Signature(Class cls,NSString *name,NSUInteger argc,const char *returnType,NSArray<NSString *> *types) {
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));if(!m||method_getNumberOfArguments(m)!=argc)return NO;
    char *r=method_copyReturnType(m);BOOL ok=r&&r[0]==returnType[0];free(r);
    for(NSUInteger i=2;i<argc;i++){char *t=method_copyArgumentType(m,(unsigned)i);NSString *allowed=types[i-2];if(!t||![allowed containsString:[NSString stringWithFormat:@"%c",t[0]]])ok=NO;free(t);}return ok;
}
#import "HostCompatibility.h"
static BOOL VersionMatches(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle])return NO;
    const struct mach_header *h=NULL;
    const char *executable=NSBundle.mainBundle.executablePath.fileSystemRepresentation;
    for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&executable&&strcmp(name,executable)==0){h=_dyld_get_image_header(i);break;}}
    return TIOHostImageMatches(h,NSBundle.mainBundle.infoDictionary);
}
static void AddEntry(void) {
    UIViewController *top=TopController();UIWindow *window=top.view.window;if(!window)return;
    if(TIOInsideTurboHub(top)){Entry.hidden=YES;return;}
    if(!Entry){Entry=[UIButton buttonWithType:UIButtonTypeSystem];[Entry setTitle:TIOText(@"hub.entry") forState:UIControlStateNormal];Entry.accessibilityLabel=TIOText(@"hub.title");Entry.backgroundColor=TIODesignColor(TIODesignColorAccentFill);[Entry setTitleColor:TIODesignColor(TIODesignColorOnAccent) forState:UIControlStateNormal];Entry.titleLabel.font=TIODesignFontWeight(TIODesignTextStyleSubheadline,UIFontWeightSemibold);Entry.layer.cornerRadius=TIOHitMin/2;[Entry addTarget:TIOEntryTarget.class action:@selector(show) forControlEvents:UIControlEventTouchUpInside];}
    Entry.hidden=NO;Entry.frame=CGRectMake(window.bounds.size.width-70,window.safeAreaInsets.top+80,58,TIOHitMin);[window addSubview:Entry];
    if(VersionMatches())TIOStartHomeTabBridge(Entry,^{[TIOEntryTarget show];});
}
__attribute__((constructor)) static void Load(void) {
    // Do not message Foundation/UIKit or create an ObjC autorelease pool under
    // the remote loader lock. All setup runs on main after scheduling via C API.
    dispatch_async(dispatch_get_main_queue(),^{
        @autoreleasepool {
            if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle])return;
            TIOStartExperimentalOTAFeedIfMarked();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{TIOCaptionRunFixedProbeIfRequested();});
            Prefs=[[NSUserDefaults alloc]initWithSuiteName:Domain];
            TIOLanguageFlagStart();
            if(![Prefs boolForKey:@"ttsCloudRemoved"]){BOOL removed=StoreKey(@"",@"");[Prefs removeObjectForKey:@"ttsEngine"];if(removed)[Prefs setBool:YES forKey:@"ttsCloudRemoved"];} // ttsCloudRemoved: cleanup of the deleted Alibaba TTS Keychain item (account "") and engine pref; retry failed deletion next launch
            [Prefs registerDefaults:@{@"appleFallback":@YES,@"voiceExitCommands":@YES,@"ttsEnabled":@YES,@"hubDeveloperExpanded":@NO}];
            TIOSetUserProfile([Prefs stringForKey:@"aboutMe"]);
            Controller=[TIOController new];
            ImportPrivateBootstrap();
            VoiceTTS=[TIOVoiceTTS new];VoiceTTS.fallbackLanguage=AddonUILanguage();VoiceTTS.willBeginTurn=^{TMMusicPauseForVoice();};
            // Research rows are explicit routes now, not a chain of table hooks.
            [Prefs registerDefaults:@{@"appleFallback":@YES,@"voiceExitCommands":@YES,@"ttsEnabled":@YES}];
            TIOSetUserProfile([Prefs stringForKey:@"aboutMe"]);
            // Do not automatically resume model takeover. Text capture remains opt-in and persistent.
            [Prefs setInteger:0 forKey:@"mode"]; // Keep the explicitly chosen text-save preference across launches.
            [Prefs removeObjectForKey:@"verifiedChatDomain"];
            NSURL *library=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[library URLByAppendingPathComponent:@"TurboIOPrivateAddon" isDirectory:YES]];ArchiveQueue=dispatch_queue_create("io.turboio.private.archive",DISPATCH_QUEUE_SERIAL);


            Class voice=NSClassFromString(@"rayneo_venus_sdk_plugin.AiResultListenerBridge"),ao=NSClassFromString(@"rayneo_venus_sdk_plugin.AlwaysOnResultListenerBridge");
            BOOL valid=VersionMatches()&&Signature(voice,@"onAsrResult:isFinish:sessionId:",5,"v",@[@"@",@"Bc",@"@"])&&Signature(voice,@"onNlpResult:",3,"v",@[@"@"])&&Signature(voice,@"onResponseComplete",2,"v",@[])&&Signature(ao,@"onAlwaysOnResponse:",3,"v",@[@"@"]);
            if(valid){OriginalAsr=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAsrResult:isFinish:sessionId:")),(IMP)AsrHook);OriginalNlp=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onNlpResult:")),(IMP)NlpHook);OriginalComplete=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onResponseComplete")),(IMP)CompleteHook);OriginalAlwaysOn=(void *)method_setImplementation(class_getInstanceMethod(ao,NSSelectorFromString(@"onAlwaysOnResponse:")),(IMP)AlwaysOnHook);HooksReady=YES;Diagnostic=TIOText(@"版本和 ObjC 回调签名匹配，等待真实事件");}else Diagnostic=TIOText(@"版本或 ABI 不匹配：未修改任何回调");
            Class helper=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
            VoiceExitReady=valid&&Signature(object_getClass(helper),@"shared",2,"@",@[])&&Signature(helper,@"stopWorkflow",2,"v",@[])&&Signature(voice,@"onAudioRecordStart",2,"v",@[]);
            if(VoiceExitReady)OriginalAudioStart=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAudioRecordStart")),(IMP)AudioStartHook);
#if TIO_APPLE_AI
            if(valid&&VoiceExitReady)TIONoNetworkInstall(voice,
                ^BOOL(id value,NSString *question,id listener){return [Controller takeLocalTurn:value question:question listener:listener];},
                ^(id listener,id value){if(Controller.voiceExited)return;if(TIOTodoIsToolDispatching()){OriginalNlp(listener,NSSelectorFromString(@"onNlpResult:"),value);return;}TIOTodoObserveNlp(listener,value);if(![Controller receiveNlp:value listener:listener])OriginalNlp(listener,NSSelectorFromString(@"onNlpResult:"),[Controller observeOfficialVoice:value]);},
                ^(id listener){if(Controller.voiceExited)return;[Controller completeOfficialVoice];if(![Prefs integerForKey:@"mode"]||!(Controller.listener==listener&&Controller.ownsTurn))OriginalComplete(listener,NSSelectorFromString(@"onResponseComplete"));},
                ^{TIONoNetworkSnapshot *state=[TIONoNetworkSnapshot new];state.mode=[Prefs integerForKey:@"mode"];state.appleFallback=[Prefs boolForKey:@"appleFallback"];state.verified=[[Prefs stringForKey:@"verifiedChatDomain"] length]>0;state.hooksReady=HooksReady;state.voiceExitReady=VoiceExitReady;state.listener=Controller.listener;state.ownsTurn=Controller.ownsTurn;state.responseDone=Controller.responseDone;state.voiceExited=Controller.voiceExited;state.generation=Controller.generation;state.sid=Controller.sid?:@"";state.asr=Controller.asr?:@"";id timeout=[Prefs objectForKey:@"noNetworkTimeout"];state.timeout=[timeout isKindOfClass:NSNumber.class]?timeout:nil;state.stopHost=[Prefs boolForKey:@"noNetworkStopHost"];state.forceForeground=[Prefs boolForKey:@"noNetworkForceForeground"];return state;},
                ^{id instance=((id(*)(id,SEL))objc_msgSend)(helper,NSSelectorFromString(@"shared"));if(instance)((void(*)(id,SEL))objc_msgSend)(instance,NSSelectorFromString(@"stopWorkflow"));});
#endif
            if(valid){TIOInstallGlassesChannelHook();TIOInstallTodoRuntime();}
#if TIO_IMAGE_RX_LAB
            TIOClenchLabInstallRecovery();
#endif
            TCCameraReportLoaded();
            NSMutableString *loadInfo=[NSMutableString stringWithFormat:@"setup reached; hooks=%d; version=%d; voiceClass=%d; alwaysOnClass=%d\n",valid,VersionMatches(),voice!=Nil,ao!=Nil];
#if TIO_DISPLAY_PHONE
#if TIO_DISPLAY_FLASH
            [loadInfo appendString:@"display extension=APP107-OTA-PHONE-01; loopback restart recovery; OTA default locked\n"];
#else
            [loadInfo appendString:@"display extension=MUSIC-OTA-PHONE-01; numeric diagnostics; OTA writes disabled; legacy N8W retained\n"];
#endif
#endif
            [loadInfo appendFormat:@"bundle=%@; version=%@; build=%@\n",NSBundle.mainBundle.bundleIdentifier,[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
            for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&[[NSString stringWithUTF8String:name].lastPathComponent isEqual:@"Runner"]){const struct mach_header *h=_dyld_get_image_header(i);[loadInfo appendFormat:@"Runner image index=%u magic=%x\n",i,h->magic];}}
            for(NSString *sel in @[@"onAsrResult:isFinish:sessionId:",@"onNlpResult:",@"onResponseComplete",@"onAlwaysOnResponse:"]){Method m=class_getInstanceMethod([sel isEqual:@"onAlwaysOnResponse:"]?ao:voice,NSSelectorFromString(sel));[loadInfo appendFormat:@"%@ %s\n",sel,m?method_getTypeEncoding(m):"missing"];}
            [loadInfo writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"TurboIOPrivateAddon-load.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            [NSNotificationCenter.defaultCenter addObserverForName:@"TIOResearchClosed" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{AddEntry();});
        }
    });
}
