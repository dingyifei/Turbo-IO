#import "notification-archive-v1/NotificationRuntime.h"
#import "camera-v1/CameraUI.h"
#import "dots-v1/DotsPhoneBridge.h"
#import "Brightness.h"
#import "TodoRuntime.h"
#import "context-english-v1/CEAutoRuntime.h"
#if TIO_IMAGE_RX_LAB
#import "ImageUploadUI.h"
#endif
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneUI.h"
#import "DisplayDiagnostics.h"
#endif
#import "ProtocolContext.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import "A2UIProbe.h"
#import "DashboardCard.h"
#import "EditorTransport.h"
#import "AppBridge.h"
#import "GlassesLogProbe.h"
#import "NavigationTransport.h"
#import "SubtitleHUD.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "GlassesChannelHook.h"

static void (*PriorMethod)(id,SEL,id,id);
static void (*PriorSend)(id,SEL,id,id,id);
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Data(id v){if([v isKindOfClass:NSData.class])return v;if([NSStringFromClass([v class]) isEqual:@"FlutterStandardTypedData"]){id d=Get(v,@"data");if([d isKindOfClass:NSData.class])return d;}return nil;}
static BOOL Sign(Method m,NSUInteger n){if(!m||method_getNumberOfArguments(m)!=n)return NO;char *r=method_copyReturnType(m);BOOL ok=r&&r[0]=='v';free(r);for(NSUInteger i=2;i<n;i++){char *t=method_copyArgumentType(m,(unsigned)i);ok=ok&&t&&t[0]=='@';free(t);}return ok;}
static BOOL Installed;
#if TIO_IMAGE_RX_LAB || TIO_DISPLAY_PHONE
static BOOL RouteFileEvent(id event,BOOL(^consume)(NSDictionary *),void(^completion)(BOOL)){
 if(![event isKindOfClass:NSDictionary.class]||!consume||!completion||
    (![[event objectForKey:@"eventType"] isEqual:@"fileShareSuccess"]&&![[event objectForKey:@"eventType"] isEqual:@"fileShareFailed"]))return NO;
 NSDictionary *snapshot=[event copy];
 void(^work)(void)=^{completion(consume(snapshot));};
 if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
 return YES;
}
#endif
static void MethodHook(id self,SEL cmd,id call,id result){
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"]&&!NSThread.isMainThread){
        dispatch_async(dispatch_get_main_queue(),^{MethodHook(self,cmd,call,result);});return;
    }
    BOOL otaBlocked=TIOOTAFlashBlockCall(call);
#if TIO_DISPLAY_PHONE
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"])TDPDiagRecord(@"gate",@{@"blocked":@(otaBlocked),@"otaStage":TIOOTAFlashStatus()[@"stage"]?:@0});
#endif
    if(otaBlocked){TDDotsPhoneRejectedBeforeSDK(Get(call,@"arguments"));if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO transfer gate: not authorized or packet mismatch"});return;}
    if(TIOOTABlockPreparationCall(call)){TDDotsPhoneRejectedBeforeSDK(Get(call,@"arguments"));if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Turbo IO OTA preparation only: outbound traffic blocked"});return;}
    if(TIOGlassesLogBlockCall(call)){TDDotsPhoneRejectedBeforeSDK(Get(call,@"arguments"));if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"本机日志研究任务隔离中，未重复请求"});return;}
    if(TDDotsPhoneBlocks(Get(call,@"method"),Get(call,@"arguments"))){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":@"Dots file transfer active; retry after completion"});return;}
    {NSString *method=Get(call,@"method");id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]){void(^work)(void)=^{TIOProtocolObserveCall(self,method,args);TIONewsTeleObserveCall(self,method,args);TIOA2UIObserveCall(self,method,args);TIOGlassesLogObserveCall(self,method,args);TIONavObserveCall(self,method,args);TIOSubtitleObserveCall(self,method,args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    if([Get(call,@"method") isEqual:@"rayneonet_sendMessage"]){id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]&&[args[@"businessId"] isEqual:@22]){void (^work)(void)=^{TIOTodoObserveSnapshotMessage(args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    id args=Get(call,@"arguments");
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"]&&[args isKindOfClass:NSDictionary.class]){
        CEAutoHostFileActivity();
        NSString *dotsTicket=TDDotsPhoneWillSend(args);
        void(^original)(id)=result;
        PriorMethod(self,cmd,call,[^(id response){dispatch_async(dispatch_get_main_queue(),^{TDDotsPhoneFileResult(dotsTicket,response);TIONewsTeleObserveFileResult(args,response);});if(original)original(response);} copy]);
    }else PriorMethod(self,cmd,call,result);
}
static void Send(id self,SEL cmd,NSString *channel,NSData *message,id reply){
    if([channel isKindOfClass:NSString.class]&&[channel.lowercaseString containsString:@"rayneonet"]&&message.length<262144){
        Class cls=NSClassFromString(@"FlutterStandardMethodCodec");
        @try{if([cls respondsToSelector:@selector(sharedInstance)]){id codec=((id(*)(id,SEL))objc_msgSend)(cls,@selector(sharedInstance));id event=((id(*)(id,SEL,id))objc_msgSend)(codec,NSSelectorFromString(@"decodeEnvelope:"),message);
            if([event isKindOfClass:NSDictionary.class]){dispatch_async(dispatch_get_main_queue(),^{TCCameraObserveConnection(event);TDDotsPhoneObserveConnection(event);});NSMutableDictionary *copy=[event mutableCopy];id original=copy[@"message"];if([original isKindOfClass:NSDictionary.class]){NSMutableDictionary *m=[original mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;copy[@"message"]=m;}
#if TIO_DISPLAY_PHONE
                TDPDiagEnvelope(copy);
#endif
                TNAObserveEvent(copy);
                if(TIOGlassesLogConsumeEvent(copy)){if(reply)((void(^)(NSData *))reply)(nil);return;}}
#if TIO_IMAGE_RX_LAB || TIO_DISPLAY_PHONE
            // File results are siblings of messageReceived, not business messages.
            // Only our exact sender task is consumed; foreign events keep Flutter's path.
            if(RouteFileEvent(event, ^BOOL(NSDictionary *e){
                TDDotsPhoneObserveFile(e);
                TAPObserveEvent(e); // Observe on main before the shared file router returns. Do not consume foreign tasks.
#if TIO_DISPLAY_PHONE
                if(TDPPhoneConsumeEvent(e))return YES;
#endif
#if TIO_IMAGE_RX_LAB
                return TIOImageUploadLabConsumeFileEvent(e);
#else
                return NO;
#endif
            }, ^(BOOL owned){
                if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);
            }))return;
#endif
            if([event isKindOfClass:NSDictionary.class]&&[event[@"eventType"] isEqual:@"messageReceived"]&&[event[@"message"] isKindOfClass:NSDictionary.class]){
                NSMutableDictionary *e=[event mutableCopy],*m=[event[@"message"] mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;e[@"message"]=m;TIOOTAFlashObserveEvent(e);NSDictionary *physical=TIOTodoPhysicalStatus(e);
#if TIO_DISPLAY_PHONE
                if(TCCameraRouteReply(e,^(BOOL owned){if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);}))return;
                if(TDPPhoneRouteReply(e,^(BOOL owned){if(owned){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);}))return;
#endif
                if([m[@"businessId"] isEqual:@20]){
                    // Own manuscripts live in TurboIO, not the official Dart
                    // repository. Let our state machine consume their replies
                    // before Flutter mistakes the unknown DID for a deleted doc.
                    // Foreign DID/device, list messages and unknown types pass.
                    void(^work)(void)=^{BOOL own=TIONewsTeleOwnsEvent(e);TIOProtocolObserveEvent(e);TIOBrightnessObserveEvent(e);TIONewsTeleObserveEvent(e);TIOA2UIObserveEvent(e);TDCObserveEvent(e);TCEObserveEvent(e);TAPObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);if(own){if(reply)((void(^)(NSData *))reply)(nil);}else PriorSend(self,cmd,channel,message,reply);};
                    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);return;
                }
                dispatch_async(dispatch_get_main_queue(),^{TIOProtocolObserveEvent(e);TIOBrightnessObserveEvent(e);TIONewsTeleObserveEvent(e);TIOA2UIObserveEvent(e);TDCObserveEvent(e);TCEObserveEvent(e);TAPObserveEvent(e);TIONavObserveEvent(e);TIOSubtitleObserveEvent(e);});
                if(physical)dispatch_async(dispatch_get_main_queue(),^{TIOTodoObservePhysical(physical);});
            }
        }}@catch(NSException *e){}
    }PriorSend(self,cmd,channel,message,reply);
}
BOOL TIOInstallGlassesChannelHook(void){if(Installed)return YES;Method method=class_getInstanceMethod(NSClassFromString(@"rayneo_venus_sdk_plugin.RayneoNetPluginBridge"),NSSelectorFromString(@"handleMethodCall:result:"));Method send=class_getInstanceMethod(NSClassFromString(@"FlutterEngine"),NSSelectorFromString(@"sendOnChannel:message:binaryReply:"));if(!Sign(method,4)||!Sign(send,5))return NO;PriorMethod=(void *)method_setImplementation(method,(IMP)MethodHook);PriorSend=(void *)method_setImplementation(send,(IMP)Send);Installed=YES;TIOOTARecordTransportHookReady();TDDotsPhoneHooksReady();return YES;}
BOOL TIOGlassesChannelHookInstalled(void){return Installed;}
