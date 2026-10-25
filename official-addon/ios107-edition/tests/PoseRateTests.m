#import "NativeNavigation.h"
#include "nav_map.h"
#include <assert.h>
#include <stdio.h>
// A minute of MapKit-style walking (offers every 0.2 s at 1.4 m/s) over an instant link: count files by op.
static uint32_t U32(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return v;}
static unsigned Caps;
static NSDictionary *Ack(NSData *packet){const uint8_t *p=packet.bytes;uint8_t raw[32];tn_reply_encode(raw,32,(TNReply){.result=TN_OK,.sid=U32(p+8),.sequence=U32(p+12),.active=p[5]!=TN_STOP,.awake=true});if(p[5]==TN_QUERY){raw[24]=Caps;uint32_t crc=tn_crc(raw,28);memcpy(raw+28,&crc,4);}NSMutableString *hex=[NSMutableString new];for(int i=0;i<32;i++)[hex appendFormat:@"%02x",raw[i]];NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_nav_v1",@"payload":@{@"data":hex}} options:0 error:nil];uint8_t head[]={8,1,16,6,26,(uint8_t)json.length};NSMutableData *pb=[NSMutableData dataWithBytes:head length:6];[pb appendData:json];return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":@"peer",@"payload":pb}};}
static NSDictionary *File(NSString *task){return @{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"peer"},@"role":@"sender",@"fileName":@"turbo-navigation.tnv",@"taskId":task};}
typedef struct{unsigned updates,poses,other;double maxPoseGap,minPoseGap;BOOL failed;} Walk;
// fileSeconds: how long each file takes to report fileShareSuccess.
static Walk Run(unsigned caps,BOOL background,double fileSeconds){
 Caps=caps;__block NSTimeInterval now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:7 clock:^{return now;} sender:^(NSData *b,NSString *t,TNVSubmitted done){wire=b;submit=done;n++;} cleanup:nil];
#ifndef TIO_BASELINE
 [s setBackground:background];
#endif
 uint8_t map[32]={0};map[0]=1;map[4]=320&255;map[5]=320>>8;map[6]=1;map[8]=2;map[16]=2;map[18]=6;int16_t pts[4]={0,0,2000,0};memcpy(map+24,pts,8);
 Walk w={0};w.minPoseGap=INFINITY;double lastPose=-1,settleAt=-1,offerAt=-1;
 for(unsigned tick=0;tick<1200;tick++){ // 60 s at 50 ms, like the TNVPump timer
  double t=tick*0.05;
  if(t-offerAt>=0.2-1e-9){offerAt=t;double along=1.4*t,left=500-along;
   // MapKitNavigationUI rounds distances to display steps before offering.
   long meters=left<100?lround(left/5)*5:lround(left/10)*10;
   uint8_t pose[12]={0};pose[0]=1;int16_t x=(int16_t)lround(along*4);memcpy(pose+4,&x,2);pose[8]=90;
   NSDictionary *f=@{@"phase":@"navigating",@"icon":@3,@"meters":@(meters),@"remainingMeters":@(meters+200),@"remainingSeconds":@(60*(long)ceil((meters+200)/1.4/60)),@"road":@"Main St",@"turn":@"Turn right",
    @"navPoints":@[@[@512,@(1023-(int)lround(along))],@[@512,@0]],@"navHeading":@90,@"tnrScene":[NSData dataWithBytes:map length:32],@"tnrPose":[NSData dataWithBytes:pose length:12],@"tnrPoseAt":@(now)};
   if(!tick)assert([s start:f always:NO]);else [s offer:f];}
  if(wire&&settleAt<0)settleAt=now+fileSeconds;
  if(wire&&now>=settleAt){const uint8_t op=((const uint8_t *)wire.bytes)[5];NSString *native=[NSString stringWithFormat:@"n%u",n];submit(YES,native);[s consume:Ack(wire)];[s consume:File(native)];wire=nil;settleAt=-1;
   if(op==TN_UPDATE)w.updates++;else if(op==TNR_POSE||op==TNR_SCENE2){if(lastPose>=0){w.maxPoseGap=MAX(w.maxPoseGap,now-lastPose);w.minPoseGap=MIN(w.minPoseGap,now-lastPose);}lastPose=now;w.poses++;}else w.other++;}
  [s pump];now+=0.05;
 }
 w.failed=[s.status[@"failed"] boolValue];return w;
}
int main(void){@autoreleasepool{
 Walk fg=Run(1,NO,0),bg=Run(1,NO,0),slow=Run(1,NO,1.5),future=Run(3,NO,0);
#ifndef TIO_BASELINE
 bg=Run(1,YES,0);
#endif
 printf("foreground: updates=%u poses=%u other=%u poseGap=%.2f-%.2fs\n",fg.updates,fg.poses,fg.other,fg.minPoseGap,fg.maxPoseGap);
 printf("background: updates=%u poses=%u poseGap=%.2f-%.2fs\n",bg.updates,bg.poses,bg.minPoseGap,bg.maxPoseGap);
 printf("slow link (1.5 s files): updates=%u poses=%u poseGap=%.2f-%.2fs failed=%d\n",slow.updates,slow.poses,slow.minPoseGap,slow.maxPoseGap,slow.failed);
#ifndef TIO_BASELINE
 assert(!fg.failed&&!bg.failed&&!slow.failed);
 // Text and numbers only when the display changes: 5 m steps at 1.4 m/s, plus the 10 s refresh.
 assert(fg.updates<=20);
 // ~2 Hz poses while walking, never close to the 5 s glasses stale limit.
 assert(fg.poses>=50&&fg.poses<=125&&fg.minPoseGap>=0.5-1e-6&&fg.maxPoseGap<=1.1);
 assert(bg.poses<=62&&bg.minPoseGap>=1-1e-6&&bg.maxPoseGap<=1.1);
 assert(slow.minPoseGap>=1-1e-6&&slow.maxPoseGap<=3.5); // old code: 3.2 s with twice the UPDATEs; glasses grey at 5 s
 // Firmware advertising a future capability bit must not break acks.
 assert(!future.failed&&future.poses==fg.poses);
#endif
 puts("PASS pose rate: display-step UPDATEs, 2 Hz moving poses, 1 Hz in background or on slow links, future caps accepted");
}return 0;}
