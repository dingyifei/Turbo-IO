#import "LanguageFlag.h"
#import "TIOLanguage.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import <UIKit/UIKit.h>
static TIOLanguageFlagLink *Link(void){
 static TIOLanguageFlagLink *link;static dispatch_once_t once;
 dispatch_once(&once,^{link=[[TIOLanguageFlagLink alloc]initWithPeer:^{return TIOProtocolDevice();} allowed:^BOOL{
  id stage=TIOOTAFlashStatus()[@"stage"];
  return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;
 } clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(NSData *data){return TIOProtocolSendBusiness(15,data);}];});return link;
}
static NSUInteger PushEpoch;
static void SchedulePush(void){
 NSCAssert(NSThread.isMainThread,@"main only");NSUInteger epoch=++PushEpoch;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  if(epoch!=PushEpoch)return;
  [Link() pushLanguage:TIOGlassesLanguageCode(TIOUILanguage())];
 });
}
void TIOLanguageFlagStart(void){
 NSCAssert(NSThread.isMainThread,@"main only");static dispatch_once_t once;
 dispatch_once(&once,^{
  (void)Link();NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
  for(NSString *name in @[UIApplicationDidBecomeActiveNotification,TIOUILanguageDidChangeNotification,TIOProtocolDeviceDidChangeNotification]){
   [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){SchedulePush();}];
  }
  [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){++PushEpoch;[Link() cancel];}];
  // Installation can happen after didBecomeActive; the first peer notification
  // supplies the target when the cold-launch push finds none.
  SchedulePush();
 });
}
BOOL TIOLanguageFlagConsume(NSDictionary *e){return [Link() consume:e];}
NSDictionary *TIOLanguageFlagStatus(void){return Link().status;}
