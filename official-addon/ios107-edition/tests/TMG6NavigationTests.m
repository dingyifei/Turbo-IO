#define main ExistingPoseRateMain
#include "tests/PoseRateTests.m"
#undef main
#include "nav_text.h"
static void Check(unsigned caps){
 Caps=caps;__block double now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;unsigned passing=0;TNRState receiver={0};
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:81 clock:^{return now;} sender:^(NSData *p,NSString *task,TNVSubmitted done){assert(!wire);wire=p;submit=done;n++;} cleanup:nil];
 for(unsigned tick=0;tick<80;tick++){NSMutableDictionary *frame=[MirrorFrame(now,1,0,0,YES) mutableCopy];frame[@"tnrPassing"]=@"Passing Martin Luther King Junior Boulevard";
  if(!tick)assert([s start:frame always:NO]);else [s offer:frame];
  if(wire){NSData *packet=wire;const uint8_t *b=packet.bytes;unsigned op=b[5];assert(tn_packet_valid(b,packet.length));if(op>=TNR_SCENE)assert(tnr_receive(&receiver,op,b+32,packet.length-32,Milliseconds(now)));
   if(op==12){assert(caps&8);passing++;assert(!strcmp(receiver.passing,"Passing Martin Luther King Junior Boulevard"));char fit[196];unsigned font=tn_text_fit(receiver.passing,strlen(receiver.passing),receiver.passing_breaks,200,fit,sizeof fit);assert(font==14&&strstr(fit,"…"));assert(strstr("Passing Martin Luther King Junior Boulevard",fit)==NULL);}
   NSString *native=[NSString stringWithFormat:@"tmg6-%u",n];submit(YES,native);[s consume:Ack(packet)];[s consume:File(native)];wire=nil;submit=nil;
  }
  [s pump];now+=.05;
 }
 assert(![s.status[@"failed"] boolValue]);assert(passing==((caps&8)?1:0));
}
static void Churn(unsigned caps){
 Caps=caps;__block double now=100;__block NSData *wire;__block TNVSubmitted submit;__block unsigned n=0;unsigned passing=0,poses=0;TNRState receiver={0};
 TNVSession *s=[[TNVSession alloc]initWithDevice:@"peer" session:81 clock:^{return now;} sender:^(NSData *p,NSString *task,TNVSubmitted done){assert(!wire);wire=p;submit=done;n++;} cleanup:nil];
 for(unsigned tick=0;tick<80;tick++){NSMutableDictionary *frame=[MirrorFrame(now,1,0,0,YES) mutableCopy];frame[@"tnrPassing"]=((tick/4)&1)?@"Passing Oak Street":@"Passing Pine Street";
  if(!tick)assert([s start:frame always:NO]);else [s offer:frame];
  if(wire&&tick%4==0){NSData *packet=wire;const uint8_t *b=packet.bytes;unsigned op=b[5];assert(tn_packet_valid(b,packet.length));if(op>=TNR_SCENE)assert(tnr_receive(&receiver,op,b+32,packet.length-32,Milliseconds(now)));
   if(op==12){passing++;}if(op==TNR_POSE2){poses++;}
   NSString *native=[NSString stringWithFormat:@"tmg6-%u",n];submit(YES,native);[s consume:Ack(packet)];[s consume:File(native)];wire=nil;submit=nil;
  }
  [s pump];now+=.05;
 }
 assert(![s.status[@"failed"] boolValue]);assert(poses>=2);assert((caps&8)?passing>0:passing==0);
}

int main(void){@autoreleasepool{Check(7);Check(15);Churn(7);Churn(15);puts("PASS TMG5 receives no new opcode; FW6 Passing roundtrip, capability gating and bounded word-safe fitting");}return 0;}
