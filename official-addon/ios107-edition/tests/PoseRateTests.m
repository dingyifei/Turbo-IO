#import "NativeNavigation.h"
#include "nav_map.h"
#include <assert.h>
#include <stdio.h>
#import <objc/runtime.h>
// A minute of MapKit-style walking (offers every 0.2 s at 1.4 m/s) over an instant link: count files by op.
static uint32_t U32(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return v;}
static unsigned Caps;
static BOOL FailMirrorAllocation;
void *TNVTestCalloc(size_t count,size_t size){if(FailMirrorAllocation)return NULL;if(size&&count>SIZE_MAX/size)return NULL;void *p=malloc(count*size);if(p)memset(p,0,count*size);return p;}

// Independent expected clock: integer narrowing is defined modulo 2^32.
static uint32_t Milliseconds(double seconds){return (uint32_t)(uint64_t)(seconds*1000);}
static NSDictionary *Ack(NSData *packet){const uint8_t *p=packet.bytes;uint8_t raw[32];tn_reply_encode(raw,32,(TNReply){.result=TN_OK,.sid=U32(p+8),.sequence=U32(p+12),.active=p[5]!=TN_STOP,.awake=true});if(p[5]==TN_QUERY){raw[24]=Caps;uint32_t crc=tn_crc(raw,28);memcpy(raw+28,&crc,4);}NSMutableString *hex=[NSMutableString new];for(int i=0;i<32;i++)[hex appendFormat:@"%02x",raw[i]];NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_nav_v1",@"payload":@{@"data":hex}} options:0 error:nil];uint8_t head[]={8,1,16,6,26,(uint8_t)json.length};NSMutableData *pb=[NSMutableData dataWithBytes:head length:6];[pb appendData:json];return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":@"peer",@"payload":pb}};}
static NSDictionary *File(NSString *task){return @{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"peer"},@"role":@"sender",@"fileName":@"turbo-navigation.tnv",@"taskId":task};}
typedef struct{unsigned updates,poses,other,pose2,maxPose2Body,minPose2Body;double maxPoseGap,minPoseGap,maxError,turnPoseAt;BOOL failed;} Walk;
// fileSeconds: how long each file takes to report fileShareSuccess.
static Walk Run(unsigned caps,BOOL background,double fileSeconds,unsigned speedQ,double turnAt){
 Caps=caps;__block NSTimeInterval now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:7 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted done){wire=b;submit=done;n++;} cleanup:nil];
#ifndef TIO_BASELINE
 [s setBackground:background];
#endif
 uint8_t map[32]={0};map[0]=1;map[4]=320&255;map[5]=320>>8;map[6]=1;map[8]=2;map[16]=2;map[18]=6;int16_t pts[4]={0,0,2000,0};memcpy(map+24,pts,8);
 Walk w={0};w.minPoseGap=INFINITY;w.minPose2Body=UINT_MAX;w.turnPoseAt=-1;double lastPose=-1,settleAt=-1,offerAt=-1;
 for(unsigned tick=0;tick<1200;tick++){ // 60 s at 50 ms, like the TNVPump timer
  double t=tick*0.05;
  if(t-offerAt>=0.2-1e-9){offerAt=t;double along=((caps&2)&&!speedQ)?0:1.4*t,left=500-along;
   // MapKitNavigationUI rounds distances to display steps before offering.
   long meters=left<100?lround(left/5)*5:lround(left/10)*10;
   uint8_t pose[12]={0};pose[0]=1;int16_t x=(int16_t)lround(along*4),y=0;pose[8]=90;if(turnAt>=0&&t>=turnAt){x=(int16_t)lround(1.4*turnAt*4);y=(int16_t)lround(1.4*(t-turnAt)*4);pose[8]=180;}memcpy(pose+4,&x,2);memcpy(pose+6,&y,2);
   NSMutableDictionary *f=[@{@"phase":@"navigating",@"icon":@3,@"meters":@(meters),@"remainingMeters":@(meters+200),@"remainingSeconds":@(60*(long)ceil((meters+200)/1.4/60)),@"road":@"Main St",@"turn":@"Turn right",
    @"navPoints":@[@[@512,@(1023-(int)lround(along))],@[@512,@0]],@"navHeading":@90,@"tnrScene":[NSData dataWithBytes:map length:32],@"tnrPose":[NSData dataWithBytes:pose length:12],@"tnrPoseAt":@(now)} mutableCopy];if(caps&2)f[@"tnrSpeed"]=@(speedQ);
   if(!tick)assert([s start:f always:NO]);else [s offer:f];}
  if(wire)assert(((const uint8_t *)wire.bytes)[5]!=TNR_POSE);
  if(wire&&settleAt<0)settleAt=now+fileSeconds;
  if(wire&&now>=settleAt){const uint8_t op=((const uint8_t *)wire.bytes)[5];unsigned bodyBytes=(unsigned)wire.length-32;NSString *native=[NSString stringWithFormat:@"n%u",n];submit(YES,native);[s consume:Ack(wire)];[s consume:File(native)];wire=nil;settleAt=-1;
   if(op==TN_UPDATE)w.updates++;else if(op==TNR_POSE||op==TNR_SCENE2||op==TNR_POSE2){if(op==TNR_POSE2){w.pose2++;unsigned body=bodyBytes;w.maxPose2Body=MAX(w.maxPose2Body,body);w.minPose2Body=MIN(w.minPose2Body,body);if(turnAt>=0&&t>=turnAt&&w.turnPoseAt<0)w.turnPoseAt=t;}if(lastPose>=0){w.maxPoseGap=MAX(w.maxPoseGap,now-lastPose);w.minPoseGap=MIN(w.minPoseGap,now-lastPose);}lastPose=now;w.poses++;}else w.other++;}
  [s pump];now+=0.05;
 }
 w.failed=[s.status[@"failed"] boolValue];w.maxError=[s.status[@"pose2MaxErrorQm"] doubleValue];return w;
}
// Read the private mirror only to compare its committed protocol state with an
// independent receiver fed the actual wire body. Scheduling assertions use packets.
static TNRState *Mirror(TNVSession *s){
 Ivar ivar=class_getInstanceVariable(TNVSession.class,"_mirror");assert(ivar);
 TNRState *mirror=NULL;memcpy(&mirror,(const uint8_t *)(__bridge void *)s+ivar_getOffset(ivar),sizeof mirror);return mirror;
}
static void SameMirror(TNVSession *s,const TNRState *expected,double now){
 TNRState *m=Mirror(s);assert(m);
 assert(m->valid==expected->valid&&m->located==expected->located&&m->pending==expected->pending);
 assert(m->pose_at==expected->pose_at&&m->target.generation==expected->target.generation&&m->target.speed==expected->target.speed);
 TNRPose a,b;BOOL av=tnr_position(m,Milliseconds(now),&a),bv=tnr_position(expected,Milliseconds(now),&b);assert(av==bv);
 if(av)assert(a.p.x==b.p.x&&a.p.y==b.p.y&&a.heading==b.heading);
}
static NSDictionary *MirrorFrame(double now,unsigned generation,int x,unsigned speed,BOOL scene2){
 uint8_t map[32]={0},pose[12]={0};memcpy(map,&generation,4);memcpy(pose,&generation,4);
 map[4]=320&255;map[5]=320>>8;map[6]=1;map[8]=2;map[16]=2;map[18]=6;int16_t pts[4]={0,0,2000,0};memcpy(map+24,pts,8);
 int16_t px=(int16_t)x;memcpy(pose+4,&px,2);pose[8]=90;
 NSMutableDictionary *frame=[@{@"phase":@"navigating",@"icon":@3,@"meters":@500,@"remainingMeters":@700,@"remainingSeconds":@300,@"road":@"Main St",@"turn":@"Turn right",@"navHeading":@90,
 @"tnrScene":[NSData dataWithBytes:map length:32],@"tnrPose":[NSData dataWithBytes:pose length:12],@"tnrPoseAt":@(now),@"tnrSpeed":@(speed)} mutableCopy];
 if(scene2){NSMutableData *combined=[NSMutableData dataWithBytes:map length:32];uint8_t trailing[12]={0};memcpy(trailing,&generation,4);trailing[8]=90;[combined appendBytes:trailing length:12];frame[@"tnrScene2"]=combined;}return frame;
}
static void CheckAsyncMirror(unsigned caps,BOOL scene2,NSTimeInterval initialTime){
 unsigned sceneOp=scene2?TNR_SCENE2:TNR_SCENE;
 Caps=caps;__block double now=initialTime;__block NSData *wire=nil;__block TNVSubmitted submitted=nil;
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:11 clock:^{return now;} sender:^(NSData *p,NSString *task,TNVSubmitted done){(void)task;assert(!wire);wire=[p copy];submitted=[done copy];} cleanup:nil];
 __block unsigned transfer=0;__block TNRState expected={0};
 void (^finish)(unsigned)=^(unsigned order){
  NSData *packet=wire;assert(packet);unsigned op=((const uint8_t *)packet.bytes)[5];NSString *native=[NSString stringWithFormat:@"async%u",++transfer];
  // Alternating orders cover ACK before native submission, early queued file
  // completion, and file completion before ACK. Neither half may commit alone.
  if(order==0){[s consume:Ack(packet)];if(caps&2)SameMirror(s,&expected,now);[s consume:File(native)];if(caps&2)SameMirror(s,&expected,now);submitted(YES,native);}
  else{submitted(YES,native);[s consume:File(native)];if(caps&2)SameMirror(s,&expected,now);[s consume:Ack(packet)];}
  if(caps&2){if(op>=TNR_SCENE){assert(tnr_receive(&expected,op,(const uint8_t *)packet.bytes+32,packet.length-32,Milliseconds(now)));}SameMirror(s,&expected,now);}
  else assert(Mirror(s)==NULL);
  wire=nil;submitted=nil;
 };
 // Start and QUERY; query creates the initially empty mirror before committing.
 assert([s start:MirrorFrame(now,1,0,6,scene2) always:NO]);
 submitted(YES,@"start");[s consume:Ack(wire)];[s consume:File(@"start")];wire=nil;submitted=nil;
 [s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==TN_QUERY);finish(0);
 [s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==sceneOp);finish(1);
 now+=0.25;[s offer:MirrorFrame(now,1,0,6,scene2)];[s pump];unsigned poseOp=TNR_POSE2;assert(wire&&((const uint8_t *)wire.bytes)[5]==poseOp);
 // A newer speed arrives without a position jump while the first correction is in flight.
 // Committing must still use speed 6 and x=0 from the exact packet body.
 now+=0.30;[s offer:MirrorFrame(now,1,0,20,scene2)];finish(0);
 if(caps&2){assert(Mirror(s)->target.speed==6&&Mirror(s)->target.p.x==0);now+=0.21;[s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==TNR_POSE2);finish(1);assert(Mirror(s)->target.speed==20&&Mirror(s)->target.p.x==0);}
 // A new generation offered during a geometry transfer must not leak into its
 // committed mirror. The following geometry and pose then advance in order.
 now+=0.6;[s offer:MirrorFrame(now,2,30,8,scene2)];[s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==sceneOp);
 now+=0.1;[s offer:MirrorFrame(now,3,40,12,scene2)];finish(1);
 if(caps&2){if(scene2)assert(!Mirror(s)->pending&&Mirror(s)->target.generation==2&&Mirror(s)->target.speed==0);else assert(Mirror(s)->pending&&Mirror(s)->scenes[Mirror(s)->bank^1u].generation==2);}
 [s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==sceneOp);finish(0);
 now+=0.6;[s offer:MirrorFrame(now,3,40,12,scene2)];[s pump];assert(wire&&((const uint8_t *)wire.bytes)[5]==poseOp);finish(1);
 if(caps&2)assert(Mirror(s)->valid&&!Mirror(s)->pending&&Mirror(s)->target.generation==3&&Mirror(s)->target.speed==12);
 assert(![s.status[@"failed"] boolValue]);
}

static void CheckUnsupported(unsigned caps,BOOL allocationFailure){
 Caps=caps;FailMirrorAllocation=allocationFailure;__block double now=100;__block NSData *wire=nil;__block TNVSubmitted submitted=nil;__block unsigned sent=0;
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:21 clock:^{return now;} sender:^(NSData *p,NSString *task,TNVSubmitted done){(void)task;assert(((const uint8_t *)p.bytes)[5]!=TNR_POSE);wire=p;submitted=done;sent++;} cleanup:nil];
 assert([s start:MirrorFrame(now,1,0,6,YES) always:NO]);submitted(YES,@"start");[s consume:Ack(wire)];[s consume:File(@"start")];
 [s pump];assert(((const uint8_t *)wire.bytes)[5]==TN_QUERY);submitted(YES,@"query");[s consume:Ack(wire)];assert(!s.active&&[s.status[@"failed"]boolValue]&&s.busy);[s consume:File(@"query")];assert(!s.busy&&[s.status[@"note"]length]);
 for(unsigned i=0;i<50;i++){now+=.25;[s offer:MirrorFrame(now,1,i,6,YES)];[s pump];}assert(sent==2);FailMirrorAllocation=NO;
}

int main(void){@autoreleasepool{
 CheckUnsupported(0,NO);CheckUnsupported(1,NO);CheckUnsupported(5,NO);CheckUnsupported(3,YES);
 CheckAsyncMirror(2,NO,200);CheckAsyncMirror(7,NO,200);CheckAsyncMirror(3,NO,200);CheckAsyncMirror(3,YES,200);
 // A real session must commit and predict correctly on both sides of the
 // 49.7-day millisecond wrap, including a transfer that crosses the boundary.
 double wrap=(double)(UINT64_C(1)<<32)/1000;
 CheckAsyncMirror(3,NO,wrap-0.125);CheckAsyncMirror(3,YES,wrap+0.125);
 Walk p2=Run(3,NO,0,6,-1),turn=Run(3,NO,0,6,30),still=Run(3,NO,0,0,-1);
 assert(!p2.failed&&p2.minPose2Body==14&&p2.maxPose2Body==14&&p2.pose2>=1);
 assert(p2.poses<=3*8+2&&p2.maxPoseGap<=4.25&&p2.updates<=20&&p2.maxError<=16);
 // Binding stress fixture: heading 180 while +y motion opposes the predictor; still require prompt correction.
 assert(!turn.failed&&turn.turnPoseAt>=30&&turn.turnPoseAt<=30.25);
 assert(!still.failed&&still.pose2>=1&&still.maxPoseGap<=2.75);
 Walk bg=Run(3,YES,0,6,-1),slow=Run(3,NO,1.5,6,-1),future=Run(7,NO,0,6,-1);
 assert(!bg.failed&&!slow.failed&&!future.failed&&bg.minPoseGap>=1-1e-6&&slow.minPoseGap>=1-1e-6&&slow.maxPoseGap<=8&&future.pose2==p2.pose2);
 printf("POSE2 background gap=%.2f slow gap=%.2f\n",bg.maxPoseGap,slow.maxPoseGap);
 printf("POSE2 straight=%u updates=%u maxGap=%.2f maxError=%.2f turnAt=%.2f stationaryGap=%.2f\n",p2.pose2,p2.updates,p2.maxPoseGap,p2.maxError,turn.turnPoseAt,still.maxPoseGap);

 puts("PASS pose rate: display-step UPDATEs, bounded POSE2 mirror/corrections, future bits accepted, missing capability/allocation fails closed without op8");
}return 0;}
