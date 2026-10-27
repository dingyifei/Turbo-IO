#if TIO_APPLE_AI
#import "AppleAI.h"
#endif
#import "LocalTranslationEntry.h"
#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import <dlfcn.h>
#import <objc/message.h>
#import "NavigationSubtitleHUD.h"
static NSDictionary *(^TIOCaptionHostCallback(void))(NSString *,NSDictionary *) {
    return [^NSDictionary *(NSString *operation,NSDictionary *args){
                    if(!NSThread.isMainThread)return @{@"available":@NO};
                    if([operation isEqual:@"status"])return TIOSubtitleNavigationStatus();
                    if([operation isEqual:@"start"]){
                        // UI has just obtained explicit idle confirmation; never called automatically.
                        if(!TIOSubtitleConfirmIdle())return @{};
                        return @{@"sid":TIOSubtitleLiveCaptionStart()?:@""};
                    }
                    NSString *sid=[args[@"sid"] isKindOfClass:NSString.class]?args[@"sid"]:@"";
                    if([operation isEqual:@"text"]&&[args[@"text"] isKindOfClass:NSString.class])return @{@"ok":@(TIOSubtitleNavigationText(sid,args[@"text"]))};
                    if([operation isEqual:@"stop"])TIOSubtitleNavigationStop(sid,TIOText(@"用户结束本机字幕"));
                    return @{};
                } copy];
}
static BOOL TIOLoadLocalTranslation(void) {
    if (@available(iOS 26.0, *)) {
        static void *handle; static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TurboCaptionTranslation.dylib"];
            handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
            Class bridge=NSClassFromString(@"TIOCaptionHost"); SEL configure=NSSelectorFromString(@"configure:");
            if(handle&&[bridge respondsToSelector:configure]){
                ((void(*)(id,SEL,id))objc_msgSend)(bridge,configure,TIOCaptionHostCallback());
            }
        });
        return handle!=NULL;
    }
    return NO;
}
#if TIO_APPLE_AI
static BOOL TIOLoadAppleCaptions(void) {
    if(!NSThread.isMainThread||!TIOAppleAILoaded())return NO;
    Class host=NSClassFromString(@"TIOAppleCaptionHost");SEL configure=NSSelectorFromString(@"configure:");
    if([host respondsToSelector:configure]){static dispatch_once_t once;dispatch_once(&once,^{((void(*)(id,SEL,id))objc_msgSend)(host,configure,TIOCaptionHostCallback());});}
    Class panel=NSClassFromString(@"TIOAppleCaptionPanel");return [panel respondsToSelector:NSSelectorFromString(@"makeController")];
}
#endif
void TIOOpenLocalTranslation(UIViewController *presenter) {
    Class cls=TIOLoadLocalTranslation()?NSClassFromString(@"TIOCaptionLocalPanel"):Nil;
    SEL factory=NSSelectorFromString(@"makeController");
    if(cls&&[cls respondsToSelector:factory]){
        UIViewController *page=((id(*)(id,SEL))objc_msgSend)(cls,factory);
        if([page isKindOfClass:UIViewController.class]){[presenter.navigationController pushViewController:page animated:YES];return;}
    }
#if TIO_APPLE_AI
    if(TIOLoadAppleCaptions()){
        Class apple=NSClassFromString(@"TIOAppleCaptionPanel");
        if([apple respondsToSelector:factory]){UIViewController *page=((id(*)(id,SEL))objc_msgSend)(apple,factory);if([page isKindOfClass:UIViewController.class]){[presenter.navigationController pushViewController:page animated:YES];return;}}
    }
    TIONotice(presenter,TIOText(@"apple.captions.unavailable.title"),TIOText(@"apple.captions.unavailable.message"));
#else
    TIONotice(presenter,TIOText(@"common.ui.localTranslation.unavailable.title"),TIOText(@"common.ui.localTranslation.unavailable.message"));
#endif
}
void TIOCaptionRunFixedProbeIfRequested(void) {
    if(![NSProcessInfo.processInfo.environment[@"TIO_LOCAL_TRANSLATION_PROBE"] isEqual:@"HYMT_PHONE_01"])return;
    if(!TIOLoadLocalTranslation())return;
    Class cls=NSClassFromString(@"TIOCaptionPhoneProbe");SEL run=NSSelectorFromString(@"runFixedProbe");
    if([cls respondsToSelector:run])((void(*)(id,SEL))objc_msgSend)(cls,run);
}
