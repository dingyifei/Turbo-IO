#define main ExistingPoseRateMain
#include "tests/PoseRateTests.m"
#undef main
#import "NavigationGuidance.h"
static NSDictionary *Frame(double now,double t,double speed,BOOL movingShape,BOOL turns){
 NSMutableDictionary *f=[MirrorFrame(now,1,(int)lround(t*speed*4),(unsigned)lround(speed*4),YES) mutableCopy];
 f[@"tnrSource"]=@"mapkit-simulation";
 if(movingShape)f[@"navPoints"]=@[@[@512,@(1023-(int)lround(t*speed))],@[@512,@0]];
 f[@"meters"]=@(TIOGuideRoundMeters(400-t*speed));
 if(turns){f[@"road"]=[NSString stringWithFormat:@"Road %d",(int)(t/2)];f[@"icon"]=@((int)(t/2)%2?2:3);}
 return f;
}
static void Replay(double fileSeconds,double speed,BOOL shape,BOOL turns){
 Caps=3;__block double now=100;__block NSData *wire=nil;__block TNVSubmitted submit=nil;__block double settle=0;__block unsigned count=0;
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:71 clock:^{return now;} sender:^(NSData *p,NSString *task,TNVSubmitted done){assert(!wire);wire=p;submit=done;settle=now+fileSeconds;count++;} cleanup:nil];
 TNRState receiver={0};int lastX=0;BOOL positioned=NO;unsigned reverseFrames=0,maxForward=0,maxReverse=0;double firstScene=-1;unsigned updatesBefore=0;NSMutableArray *ops=[NSMutableArray new];
 for(unsigned tick=0;tick<=1200;tick++){
  double t=tick*.05;now=100+t;
  if(tick%4==0){NSDictionary *f=Frame(now,t,speed,shape,turns);if(!tick)assert([s start:f always:NO]);else [s offer:f];}
  if(wire&&now+1e-8>=settle){NSData *p=wire;const uint8_t *b=p.bytes;unsigned op=b[5];
   if(t<15)[ops addObject:[NSString stringWithFormat:@"%.2f:%u",t,op]];
   if(op==TN_UPDATE&&firstScene<0)updatesBefore++;
   if(op>=TNR_SCENE){assert(tnr_receive(&receiver,op,b+32,p.length-32,Milliseconds(now)));if((op==TNR_SCENE||op==TNR_SCENE2)&&firstScene<0)firstScene=t;}
   NSString *native=[NSString stringWithFormat:@"file%u",count];submit(YES,native);[s consume:Ack(p)];[s consume:File(native)];wire=nil;submit=nil;
  }
  TNRPose pose;if(tnr_position(&receiver,Milliseconds(now),&pose)){if(positioned){int dx=pose.p.x-lastX;if(dx<0){reverseFrames++;maxReverse=MAX(maxReverse,-dx);}else maxForward=MAX(maxForward,dx);}lastX=pose.p.x;positioned=YES;}
  [s pump];
 }
 assert(firstScene>=0&&firstScene<=3*fileSeconds+.2&&updatesBefore==0);
 printf("file=%.2fs speed=%.1fm/s shape=%d turns=%d first_scene=%.2fs pre_scene_updates=%u reverse_frames=%u max_reverse_step=%uqm max_forward_step=%uqm files=%u failed=%d ops=%s\n",fileSeconds,speed,shape,turns,firstScene,updatesBefore,reverseFrames,maxReverse,maxForward,count,[s.status[@"failed"] boolValue],[[ops componentsJoinedByString:@","] UTF8String]);
}
int main(void){@autoreleasepool{Replay(0,1.4,YES,NO);Replay(.3,1.4,YES,NO);Replay(1.5,11,YES,YES);Replay(3,11,YES,YES);puts("PASS first scene precedes all updates under slow links and turns");}return 0;}
