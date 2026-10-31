// Music while navigating (bug 3). Three layers, all against the unchanged phone sources and the byte-shared glasses runtimes
// (nav_runtime.c = TNV1/TNR, music.c = TMU1):
//   1. TNVSession pump interleaving on a fake clock: never two files in flight, STOP and urgent UPDATE never yield, the
//      non-urgent slot is yielded once per window and music gets a turn within a bounded number of nav sends, 8 s deadline intact.
//   2. TMMusicBridge: TM_BUSY on OPEN and TM_NO_SESSION on CLOCK/COVER/LYRICS/CLOSE rest the bridge (not failed) and the glasses'
//      TM_RESUME reopens it; BAD and STALE stay fatal.
//   3. End to end on real time: NativeNavigationUI (TNVStart/Offer/Pump/Stop) and MusicPlayer (setGlasses -> showOnGlasses) against a
//      glasses model, including the TMG8 background route (tn_detach): showOnGlasses sends TM_OPEN and never reports "blocked".
// MusicPlayer.m and NativeNavigationUI.m compile unchanged against tests/shims/UIKit/UIKit.h.
#import "MusicPlayer.h"
#import "MusicBridge.h"
#import "NativeNavigationUI.h"
#import "NativeNavigation.h"
#import "ProtocolContext.h"
#import "TIOLanguage.h"
#include "music.h"
#include "nav_runtime.h"
#include <assert.h>
#include <stdio.h>

// ---- UIKit shim implementation and the app seams the two sources reach for ------------------------------------------------
NSString *const UIApplicationWillEnterForegroundNotification=@"UIApplicationWillEnterForegroundNotification";
@implementation UIImage
+ (instancetype)imageWithCGImage:(CGImageRef)image{return [self new];}
- (CGImageRef)CGImage{return NULL;}
@end
@implementation UIViewController
@end
@implementation UIApplication
+ (UIApplication *)sharedApplication{static UIApplication *a;static dispatch_once_t once;dispatch_once(&once,^{a=[self new];});return a;}
- (UIApplicationState)applicationState{return UIApplicationStateActive;}
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void(^)(void))handler{return 1;}
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task{}
@end
static NSString *Root;
NSString *NSHomeDirectory(void){assert(Root.length);return Root;}   // test.py defines NSHomeDirectory=TIOTestHome for every linked source
static NSUInteger OTAStage;
NSDictionary *TIOOTAFlashStatus(void){return @{@"stage":@(OTAStage)};}
static id Plugin;
id TIOProtocolPlugin(void){return Plugin;}
NSString *TIOProtocolDevice(void){return @"peer";}
void TDPDiagConfigure(NSURL *url){(void)url;}

static uint32_t U32(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return v;}
static void Put(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static NSTimeInterval Uptime(void){return NSProcessInfo.processInfo.systemUptime;}

// ---- Wire helpers (the same shapes the glasses send) -------------------------------------------------------------------------
static NSDictionary *Message(NSString *cmd,const uint8_t raw[32]){
 NSMutableString *hex=[NSMutableString new];for(int i=0;i<32;i++)[hex appendFormat:@"%02x",raw[i]];
 NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":cmd,@"payload":@{@"value":@0,@"mode":@0,@"data":hex}} options:0 error:nil];
 NSMutableData *pb=[NSMutableData dataWithBytes:(uint8_t[]){8,1,16,6,26} length:5];NSUInteger n=json.length;do{uint8_t v=n&127;n>>=7;if(n)v|=128;[pb appendBytes:&v length:1];}while(n);[pb appendData:json];
 return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"peer",@"businessId":@15,@"payload":pb}};
}
static NSDictionary *NavReply(NSData *packet,unsigned result,BOOL active,BOOL awake){
 const uint8_t *p=packet.bytes;uint8_t raw[32];tn_reply_encode(raw,32,(TNReply){.result=result,.sid=U32(p+8),.sequence=U32(p+12),.active=active,.awake=awake});
 if(p[5]==TN_QUERY){raw[24]=3;Put(raw+28,tn_crc(raw,28));}
 return Message(@"turbo_nav_v1",raw);
}
static NSDictionary *MusicReply(unsigned event,unsigned result,unsigned flags,uint32_t sid,uint32_t gen,uint32_t seq,uint32_t request){
 uint8_t raw[32]={'T','M','A','1',1};raw[5]=event;raw[6]=result;raw[7]=flags;Put(raw+8,sid);Put(raw+12,gen);Put(raw+16,seq);Put(raw+20,request);Put(raw+28,tm_crc(raw,28));
 return Message(@"turbo_music_v1",raw);
}
static NSDictionary *FileEvent(NSString *native,NSString *name){return @{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"peer"},@"taskId":native,@"fileName":name,@"role":@"sender"};}
static NSDictionary *Frame(unsigned meters,int icon){return @{@"phase":@"navigating",@"icon":@(icon),@"meters":@(meters),@"remainingMeters":@(meters+1000),@"remainingSeconds":@600,@"road":@"Road",@"turn":@"Turn right",@"navPoints":@[@[@100,@900],@[@100,@500],@[@900,@500]],@"navHeading":@90};}
static unsigned Op(NSData *packet){return ((const uint8_t *)packet.bytes)[5];}

// =================================================================================================================================
// 1. TNVSession pump interleaving on a fake clock
// =================================================================================================================================
typedef struct{BOOL holds,waits;}Peer;
static void Walk30(BOOL contended,unsigned out[3]){
 __block NSTimeInterval now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;__block BOOL holds=NO,waits=contended;__block NSTimeInterval holdUntil=0,quietUntil=0;
  __block unsigned musicTurns=0,sinceTurn=0,maxSinceTurn=0,navSends=0;
  TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:44 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted d){assert(!holds);assert(!wire);wire=b;submit=d;n++;} cleanup:nil];
  s.peerFileInFlight=^{return holds;};s.peerWaiting=^{return waits;};
  uint8_t map[32]={0};map[0]=1;map[4]=320&255;map[5]=320>>8;map[6]=1;map[8]=2;map[16]=2;map[18]=6;int16_t pts[4]={0,0,2000,0};memcpy(map+24,pts,8);NSData *mapData=[NSData dataWithBytes:map length:32];
  NSDictionary *(^Walk)(double)=^NSDictionary *(double along){uint8_t pose[12]={0};pose[0]=1;int16_t x=(int16_t)lround(along*4),y=0;pose[8]=90;memcpy(pose+4,&x,2);memcpy(pose+6,&y,2);
   long meters=lround((500-along)/10)*10;return @{@"phase":@"navigating",@"icon":@3,@"meters":@(meters),@"remainingMeters":@(meters+200),@"remainingSeconds":@600,@"road":@"Main St",@"turn":@"Turn right",@"navPoints":@[@[@512,@(1023-(int)lround(along))],@[@512,@0]],@"navHeading":@90,@"tnrScene":mapData,@"tnrPose":[NSData dataWithBytes:pose length:12],@"tnrPoseAt":@(now)};};
  assert([s start:Walk(0) always:NO]);double offerAt=-1;unsigned lastYields=0;
  for(unsigned tick=0;tick<600;tick++){   // 30 s at 50 ms
   double t=tick*0.05;if(t-offerAt>=0.2-1e-9){offerAt=t;[s offer:Walk(1.4*t)];}
   if(wire){navSends++;sinceTurn++;maxSinceTurn=MAX(maxSinceTurn,sinceTurn);NSString *native=[NSString stringWithFormat:@"nav-%u",n];NSData *w=wire;wire=nil;submit(YES,native);[s consume:NavReply(w,TN_OK,YES,YES)];[s consume:FileEvent(native,@"turbo-navigation.tnv")];assert(!s.busy);}
   if(holds&&now>=holdUntil){holds=NO;quietUntil=now+0.2;waits=NO;}
   if(contended&&!waits&&!holds&&now>=quietUntil)waits=YES;
   [s pump];now+=0.05;
   unsigned y=[s.status[@"yields"] unsignedIntValue];if(y>lastYields){lastYields=y;assert(!wire);musicTurns++;sinceTurn=0;holds=YES;waits=NO;holdUntil=now+0.3;}   // music takes the slot nav yielded
  }
  assert(![s.status[@"failed"] boolValue]);out[0]=navSends;out[1]=musicTurns;out[2]=maxSinceTurn;
}
static void SessionTests(void){
 // Routine UPDATE yields one window; urgent UPDATE, STOP and the 8 s deadline do not.
 {__block NSTimeInterval now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;__block BOOL holds=NO,waits=NO;
  TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:41 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted d){wire=b;submit=d;n++;} cleanup:nil];
  s.peerFileInFlight=^{return holds;};s.peerWaiting=^{return waits;};
  void(^Settle)(void)=^{NSString *native=[NSString stringWithFormat:@"nav-%u",n];submit(YES,native);[s consume:NavReply(wire,TN_OK,YES,YES)];[s consume:FileEvent(native,@"turbo-navigation.tnv")];assert(!s.busy);wire=nil;};
  holds=YES;assert(![s start:Frame(90,3) always:NO]);assert(!s.active&&n==0&&!s.busy);   // a music file in flight: nothing is sent, no half-started session
  holds=NO;assert([s start:Frame(90,3) always:NO]);assert(n==1&&s.fileInFlight&&Op(wire)==TN_START);Settle();assert(!s.fileInFlight);
  // Routine change, music waiting: the slot is yielded for the window, then taken.
  waits=YES;now+=1.1;[s offer:Frame(80,3)];[s pump];assert(n==1&&[s.status[@"yields"] unsignedIntValue]==1);
  now+=0.2;[s pump];assert(n==1);now+=0.15;[s pump];assert(n==1);
  now+=0.2;[s pump];assert(n==2&&Op(wire)==TN_UPDATE&&[s.status[@"yields"] unsignedIntValue]==1);Settle();
  // Music holds the link: even a due STOP waits, and goes the moment the link is free.
  holds=YES;[s stop];assert(n==2&&s.active);now+=0.5;[s pump];assert(n==2);holds=NO;now+=1.2;[s pump];assert(n==3&&Op(wire)==TN_STOP);
  submit(YES,@"nav-stop");[s consume:NavReply(wire,TN_OK,NO,YES)];[s consume:FileEvent(@"nav-stop",@"turbo-navigation.tnv")];assert(!s.active&&!s.busy);}
 // Urgent UPDATE (new icon) and STOP are sent at once with music waiting; the 8 s deadline still fails a silent packet.
 {__block NSTimeInterval now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;
  TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:42 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted d){wire=b;submit=d;n++;} cleanup:nil];
  s.peerFileInFlight=^{return NO;};s.peerWaiting=^{return YES;};
  void(^Settle)(void)=^{NSString *native=[NSString stringWithFormat:@"nav-%u",n];submit(YES,native);[s consume:NavReply(wire,TN_OK,YES,YES)];[s consume:FileEvent(native,@"turbo-navigation.tnv")];assert(!s.busy);};
  assert([s start:Frame(90,3) always:NO]);Settle();
  now+=1.1;[s offer:Frame(90,2) /* turn icon changed: urgent */];[s pump];assert(n==2&&Op(wire)==TN_UPDATE&&[s.status[@"yields"] unsignedIntValue]==0);Settle();
  now+=1.1;[s offer:Frame(70,2)];[s pump];assert(n==2);                      // routine: yields
  [s stop];assert(n==3&&Op(wire)==TN_STOP);                                   // STOP never yields
  now+=8.1;[s pump];assert(!s.active&&[s.status[@"failed"] boolValue]);}    // the 8 s ack deadline is untouched by the hooks
 // A failed session keeps an uncertain file but does not hold the link against music.
 {__block NSTimeInterval now=100;__block TNVSubmitted submit;
  TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:43 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted d){submit=d;} cleanup:nil];
  assert([s start:Frame(90,3) always:NO]);assert(s.fileInFlight);now+=8.1;[s pump];assert([s.status[@"failed"] boolValue]&&!s.fileInFlight&&s.busy);}
 // Walking route with pose corrections, 30 s: with music uncontended, then with music always waiting (it takes the link for 0.3 s
 // whenever nav yields). Bounded nav sends between music turns, nav not starved, never a nav send while music holds the link.
 {unsigned free[3],busy[3];Walk30(NO,free);Walk30(YES,busy);
  printf("  walking route, 30 s: uncontended %u nav sends; with music waiting %u nav sends, %u music turns, max %u nav sends between music turns\n",free[0],busy[0],busy[1],busy[2]);
  assert(free[1]==0);
  assert(busy[1]>=10);                 // music keeps getting slots
  assert(busy[2]<=8);                  // ... within a bounded number of nav sends
  assert(busy[0]*10>=free[0]*6);}      // ... and navigation keeps at least 60% of its uncontended sends
}

// =================================================================================================================================
// The glasses model: files cross a fake native link, one at a time; replies come from the byte-shared runtimes
// =================================================================================================================================
@interface FlutterMethodCall:NSObject
@property(nonatomic,copy) NSString *method;@property(nonatomic,copy) NSDictionary *args;
+ (instancetype)methodCallWithMethodName:(NSString *)method arguments:(id)arguments;
@end
@implementation FlutterMethodCall
+ (instancetype)methodCallWithMethodName:(NSString *)method arguments:(id)arguments{FlutterMethodCall *c=[self new];c.method=method;c.args=arguments;return c;}
@end
static NSMutableArray *Pending;            // files accepted by the link, not yet delivered
static unsigned FilesInFlight,MaxInFlight,Natives;
static NSMutableArray *Log;                // "N<op>" / "M<op>" in link order
static TNRuntime GN;static TNUI GU;static TMMusic *GM;
static unsigned MusicOps[8];               // files per music op
static TMMusicBridge *TB;                  // bridge under direct test; nil = the player's own bridge
static NSDictionary *(^MusicOverride)(unsigned op,NSData *packet);   // return a reply to force the glasses' answer
static NSTimeInterval LinkDelay=0.12;
static bool ok_avail(void *c){return true;}
static bool ok_enter(void *c,const TNScene *s){return true;}
static bool ok_render(void *c,const TNScene *s,bool st){return true;}
static bool ok_power(void *c,enum TNPower p){return true;}
static void ok_leave(void *c){}
static BOOL NavPageVisible(void){return GN.active&&!GN.hidden;}
@interface FakePlugin:NSObject
@end
@implementation FakePlugin
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result{
 assert([call.method isEqual:@"rayneonet_sendFile"]);
 NSString *path=call.args[@"filePath"];NSData *data=[NSData dataWithContentsOfFile:path];assert(data.length>=32);
 NSString *name=path.lastPathComponent;BOOL nav=[name isEqual:@"turbo-navigation.tnv"];assert(nav||[name isEqual:@"turbo-music.tmu"]);
 FilesInFlight++;MaxInFlight=MAX(MaxInFlight,FilesInFlight);   // the link carries one file at a time; the test fails on any overlap
 NSString *native=[NSString stringWithFormat:@"native-%u",++Natives];
 [Pending addObject:@{@"nav":@(nav),@"data":data,@"native":native,@"at":@(Uptime())}];
 [Log addObject:[NSString stringWithFormat:@"%@%u",nav?@"N":@"M",((const uint8_t *)data.bytes)[5]]];
 if(!nav)MusicOps[((const uint8_t *)data.bytes)[5]&7]++;
 result(@{@"success":@YES,@"taskId":native});
}
@end
static void Route(NSDictionary *e){
 if(TB){if([TB consume:e])return;}else if(TMMusicConsume(e))return;
 TNVConsume(e);
}
static uint32_t Tick32(void){return (uint32_t)(Uptime()*1000);}
static void Deliver(void){
 NSTimeInterval now=Uptime();
 while(Pending.count){
  NSDictionary *f=Pending[0];if(now-[f[@"at"] doubleValue]<LinkDelay)break;[Pending removeObjectAtIndex:0];FilesInFlight--;
  NSData *data=f[@"data"];NSString *native=f[@"native"];
  if([f[@"nav"] boolValue]){
   TNReply r=tn_receive(&GN,&GU,data.bytes,data.length,Tick32(),true);
   Route(FileEvent(native,@"turbo-navigation.tnv"));Route(NavReply(data,r.result,r.active,r.awake));
  }else{
   TMPacket p;assert(tm_decode(data.bytes,data.length,&p));enum TMResult result;
   NSDictionary *forced=MusicOverride?MusicOverride(p.op,data):nil;
   if(forced){Route(FileEvent(native,@"turbo-music.tmu"));Route(forced);continue;}
   // music_service.c: OPEN is answered BUSY while the navigation page is on screen; tm_receive decides everything else.
   if(p.op==TM_OPEN&&NavPageVisible())result=TM_BUSY;else result=tm_receive(GM,&p,Tick32());
   Route(FileEvent(native,@"turbo-music.tmu"));
   Route(MusicReply(TM_ACK,result,(GM->active?1:0)|(GM->awake?2:0),p.sid,p.generation,p.sequence,0));
  }
 }
}
static void Spin(NSTimeInterval seconds){
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(end.timeIntervalSinceNow>0){[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];if(TB)[TB pump];Deliver();}
}
static BOOL SpinUntil(NSTimeInterval limit,BOOL(^done)(void)){
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:limit];
 while(end.timeIntervalSinceNow>0){if(done())return YES;Spin(0.02);}
 return done();
}
static void ResetGlasses(void){
 [Pending removeAllObjects];[Log removeAllObjects];FilesInFlight=0;memset(MusicOps,0,sizeof MusicOps);
 tn_init(&GN);GU=(TNUI){NULL,ok_avail,ok_enter,ok_render,ok_power,ok_leave};memset(GM,0,sizeof *GM);MusicOverride=nil;
}
static NSString *LastLog(void){return Log.lastObject;}

// =================================================================================================================================
// 2. TMMusicBridge: BUSY / NO_SESSION rest the bridge; the glasses' RESUME reopens it; BAD / STALE stay fatal
// =================================================================================================================================
static NSData *Cover(void){NSMutableData *d=[NSMutableData dataWithLength:TM_COVER_BYTES];memset(d.mutableBytes,0x55,d.length);return d;}
static NSArray *Rows(unsigned n){NSMutableArray *a=[NSMutableArray new];for(unsigned i=0;i<n;i++)[a addObject:@{@"ms":@(i*1000),@"text":[NSString stringWithFormat:@"line %u",i]}];return a;}
static TMMusicBridge *NewBridge(void){
 TMMusicBridge *b=[TMMusicBridge new];__weak TMMusicBridge *weak=b;
 b.snapshot=^NSDictionary *{return @{@"title":@"Song",@"artist":@"Artist",@"position":@0,@"duration":@200000,@"playing":@YES,@"mode":@0,@"request":@0};};
 // What MusicPlayer does with the glasses' Resume request (resumeFromGlasses -> finishResume -> showOnGlasses -> reopen).
 b.command=^(NSDictionary *q){if([q[@"event"] unsignedIntValue]==TM_RESUME)[weak reopen];};return b;
}
static void BridgeTests(void){
 // BUSY on OPEN: the navigation page is on screen. Not failed, not retrying, and recoverable.
 ResetGlasses();TB=NewBridge();[TB openWithCover:Cover() lyrics:Rows(3)];assert(TB.active);
 {TNScene sc;assert(TNVScene(Frame(90,3),NO,&sc));uint8_t b[512];size_t len=tn_encode(b,sizeof b,TN_START,500,1,&sc);assert(len&&tn_receive(&GN,&GU,b,len,1,true).result==TN_OK);assert(NavPageVisible());}   // the nav page is on screen
 assert(SpinUntil(3,^BOOL{return !TB.active&&!TB.busy;}));
 assert(MusicOps[TM_OPEN]==1&&MusicOps[TM_COVER]==0&&MusicOps[TM_LYRICS]==0&&MusicOps[TM_CLOCK]==0);
 assert([TB.note isEqual:TIOText(@"music.bridge.busy")]);
 Spin(0.6);assert(MusicOps[TM_OPEN]==1&&!TB.busy);                       // no retry loop
 // The page closes (TMG8 close_page); the glasses' Resume request reopens through -reopen, and assets then flow.
 assert(tn_detach(&GN,&GU)&&!NavPageVisible());
 Route(MusicReply(TM_RESUME,TM_OK,0,0,0,0,7));                            // TM_RESUME is accepted for any sid/generation
 assert(TB.active);
 assert(SpinUntil(5,^BOOL{return GM->cover_ready&&GM->lyrics_ready&&!TB.busy;}));
 assert(GM->active&&MusicOps[TM_OPEN]==2);
 // NO_SESSION on CLOCK / COVER / LYRICS / CLOSE: the glasses closed the music page (their state is not active).
 struct{unsigned op;const char *name;}cases[]={{TM_CLOCK,"CLOCK"},{TM_COVER,"COVER"},{TM_LYRICS,"LYRICS"},{TM_CLOSE,"CLOSE"}};
 for(unsigned i=0;i<4;i++){
  ResetGlasses();TB=NewBridge();unsigned op=cases[i].op;__block BOOL fired=NO;
  MusicOverride=^NSDictionary *(unsigned o,NSData *packet){
   const uint8_t *p=packet.bytes;if(o==TM_OPEN)return nil;if(o!=op)return nil;fired=YES;
   return MusicReply(TM_ACK,TM_NO_SESSION,0,U32(p+8),U32(p+12),U32(p+16),0);};
  [TB openWithCover:Cover() lyrics:Rows(3)];
  if(op==TM_CLOSE){assert(SpinUntil(5,^BOOL{return GM->cover_ready&&GM->lyrics_ready&&!TB.busy;}));[TB close];}
  else if(op==TM_CLOCK){assert(SpinUntil(5,^BOOL{return GM->cover_ready&&GM->lyrics_ready&&!TB.busy;}));[TB changed];}   // clock re-sync request
  assert(SpinUntil(5,^BOOL{return fired&&!TB.busy;}));
  assert(!TB.active);assert([TB.note isEqual:TIOText(@"music.bridge.noSession")]);
  unsigned before=MusicOps[TM_OPEN];MusicOverride=nil;
  Route(MusicReply(TM_RESUME,TM_OK,0,0,0,0,100+i));assert(TB.active);                  // recoverable, not failed
  assert(SpinUntil(5,^BOOL{return MusicOps[TM_OPEN]==before+1&&!TB.busy;}));
  printf("  NO_SESSION on %s: rested, reopened by RESUME\n",cases[i].name);
 }
 // BAD and STALE stay fatal for every op; BUSY elsewhere than OPEN stays fatal; NO_SESSION on OPEN stays fatal.
 struct{unsigned result;unsigned op;const char *name;}fatal[]={{TM_BAD,TM_OPEN,"BAD/OPEN"},{TM_STALE,TM_OPEN,"STALE/OPEN"},{TM_BAD,TM_COVER,"BAD/COVER"},{TM_STALE,TM_LYRICS,"STALE/LYRICS"},{TM_BUSY,TM_COVER,"BUSY/COVER"},{TM_NO_SESSION,TM_OPEN,"NO_SESSION/OPEN"}};
 for(unsigned i=0;i<6;i++){
  ResetGlasses();TB=NewBridge();unsigned op=fatal[i].op,result=fatal[i].result;
  MusicOverride=^NSDictionary *(unsigned o,NSData *packet){
   const uint8_t *p=packet.bytes;if(o!=op)return nil;
   return MusicReply(TM_ACK,result,0,U32(p+8),U32(p+12),U32(p+16),0);};
  [TB openWithCover:Cover() lyrics:Rows(3)];
  assert(SpinUntil(5,^BOOL{return !TB.active&&MusicOps[op]>=1;}));Spin(0.3);
  unsigned opens=MusicOps[TM_OPEN];MusicOverride=nil;
  [TB reopen];Route(MusicReply(TM_RESUME,TM_OK,0,0,0,0,200+i));Spin(0.6);
  assert(!TB.active&&MusicOps[TM_OPEN]==opens);                                  // failed: reopen does nothing
  assert(![TB.note isEqual:TIOText(@"music.bridge.busy")]&&![TB.note isEqual:TIOText(@"music.bridge.noSession")]);
  printf("  %s: still fatal\n",fatal[i].name);
 }
 // The bridge never sends while the peer (navigation) holds the link.
 ResetGlasses();TB=NewBridge();__block BOOL held=YES;TB.peerFileInFlight=^{return held;};[TB openWithCover:Cover() lyrics:Rows(3)];
 Spin(0.5);assert(Log.count==0&&TB.active&&TB.waiting&&!TB.fileInFlight);held=NO;assert(SpinUntil(2,^BOOL{return Log.count>0;}));
 assert(SpinUntil(5,^BOOL{return GM->cover_ready&&!TB.busy;}));
 TB=nil;
}

// =================================================================================================================================
// 3. End to end, real time: NativeNavigationUI + MusicPlayer against the glasses model
// =================================================================================================================================
static void EndToEnd(void){
 ResetGlasses();TB=nil;
 TMPlayer *player=TMPlayer.shared;assert(player.status.length);
 NSString *blocked=TIOText(@"music.status.blocked");
 // (a) Reverse gate: with the glasses music page open, TNVStart is refused and says why.
 player.glasses=YES;assert(SpinUntil(3,^BOOL{return GM->active&&MusicOps[TM_OPEN]>=1;}));assert(![player.status isEqual:blocked]);
 assert(!TNVStart(Frame(90,3)));assert([TNVStatus()[@"note"] isEqual:TIOText(@"nav.blockedByMusic")]);
 player.glasses=NO;assert(SpinUntil(3,^BOOL{return MusicOps[TM_CLOSE]>=1&&TMMusicPauseForOTA();}));
 assert([TNVStatus()[@"note"] isEqual:TIOText(@"TNV1专用固件：手机开始导航后可自动打开眼镜页面")]);   // the note clears with the cause
 // (b) Navigation page on screen: music OPEN is sent, the glasses answer BUSY, the player is not "blocked" and not failed.
 tn_init(&GN);GU=(TNUI){NULL,ok_avail,ok_enter,ok_render,ok_power,ok_leave};[Pending removeAllObjects];[Log removeAllObjects];
 assert(TNVStart(Frame(90,3)));assert(SpinUntil(3,^BOOL{return NavPageVisible()&&![TNVStatus()[@"busy"] boolValue];}));
 assert(!TNVPauseForOTA());   // the predicate that used to block showOnGlasses is false: a session is active
 unsigned opensBefore=MusicOps[TM_OPEN];
 player.glasses=YES;
 assert(![player.status isEqual:blocked]);
 assert(SpinUntil(3,^BOOL{return MusicOps[TM_OPEN]==opensBefore+1&&!TMMusicFileInFlight();}));
 Spin(0.4);assert([player.bridgeStatus isEqual:TIOText(@"music.bridge.busy")]);assert(TMMusicPauseForOTA());   // rested: OTA/idle gate sees it idle
 // (c) TMG8 close_page: the page closes, the route stays. showOnGlasses (via the glasses' RESUME) now reaches an open music page.
 assert(tn_detach(&GN,&GU));assert(!TNVPauseForOTA());
 Route(MusicReply(TM_RESUME,TM_OK,0,0,0,0,31));
 assert(SpinUntil(3,^BOOL{return GM->active&&MusicOps[TM_OPEN]==opensBefore+2;}));assert(![player.status isEqual:blocked]);
 // (d) Interleave: the player pushes cover + lyrics while navigation keeps sending UPDATEs. One file at a time throughout.
 // A new track: the player owns a new ticket, cover and lyrics, so it opens a new generation and pushes them (7 more files).
 [player setValue:@{@"title":@"Song",@"artist":@"Artist",@"progress_ms":@0,@"duration_ms":@200000,@"playing":@YES} forKey:@"_state"];
 [player setValue:Cover() forKey:@"_gray"];[player setValue:Rows(24) forKey:@"_lyrics"];[player setValue:@([[player valueForKey:@"_ticket"] unsignedIntegerValue]+1) forKey:@"_ticket"];
 [player showOnGlasses];
 unsigned navBefore=0;for(NSString *l in Log)if([l hasPrefix:@"N"])navBefore++;
 NSTimeInterval startedAt=Uptime();unsigned meters=800;
 while(Uptime()-startedAt<6&&!(GM->cover_ready&&GM->lyrics_ready)){TNVOffer(Frame(meters-=10,3));Spin(0.25);}
 assert(GM->cover_ready&&GM->lyrics_ready);
 NSTimeInterval musicDone=Uptime()-startedAt;
 // Keep going so navigation provably continues after the burst, then count.
 for(unsigned i=0;i<12;i++){TNVOffer(Frame(meters-=10,3));Spin(0.25);}
 unsigned navAfter=0;for(NSString *l in Log)if([l hasPrefix:@"N"])navAfter++;
 assert(MaxInFlight==1);                                           // never two files on the link
 assert(navAfter>=navBefore+3);                                    // navigation was not starved by the cover burst
 assert([TNVStatus()[@"failed"] boolValue]==NO);
 printf("  end to end: music assets complete in %.1f s while navigation sent %u UPDATE/other files, max %u in flight\n",musicDone,navAfter-navBefore,MaxInFlight);
 // (e) STOP is prompt with music active.
 NSTimeInterval stopAt=Uptime();TNVStop();assert(SpinUntil(2,^BOOL{return [LastLog() isEqual:[NSString stringWithFormat:@"N%u",TN_STOP]];}));
 printf("  STOP on the link %.2f s after the request\n",Uptime()-stopAt);assert(Uptime()-stopAt<1.5);
 assert(SpinUntil(2,^BOOL{return ![TNVStatus()[@"active"] boolValue]&&![TNVStatus()[@"busy"] boolValue];}));
 player.glasses=NO;Spin(0.6);
}

int main(int argc,char **argv){@autoreleasepool{
 Root=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"music-nav-%d",getpid()]];
 [NSFileManager.defaultManager createDirectoryAtPath:Root withIntermediateDirectories:YES attributes:nil error:nil];
 [NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSProcessInfo.processInfo.processName];
 Pending=[NSMutableArray new];Log=[NSMutableArray new];GM=calloc(1,sizeof *GM);Plugin=[FakePlugin new];
 puts("session pump interleaving");SessionTests();
 puts("music bridge BUSY / NO_SESSION");BridgeTests();
 puts("navigation + music end to end");EndToEnd();
 [NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSProcessInfo.processInfo.processName];
 [NSFileManager.defaultManager removeItemAtPath:Root error:nil];
 puts("PASS music while navigating: showOnGlasses with an active session, BUSY/NO_SESSION rest, one file in flight, STOP and urgent UPDATE never yield");
}return 0;}
