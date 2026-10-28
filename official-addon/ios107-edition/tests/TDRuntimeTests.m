#import "TDPhoneRun.h"
#import "TDPhoneReply.h"
#include "diagnostics.h"
#include <assert.h>
static NSData *Packet(TDCommand q,unsigned kind,unsigned state,int64_t net,uint64_t absolute){
 TDSample s={.build=TD_BUILD_TMG4,.kind=kind,.session=q.session,.sequence=q.sequence,.caps=TD_CAPS_ALL,.detent=600,.extension_valid=7,.nand_total=128000,.nand_available=64000,.tile_generation=5,.language=1,.language_source=2,.settings_flags=3,.valid=1u<<TD_LV_USED};s.values[TD_LV_USED]=1024;memset(s.build_sha,0xab,32);
 if(state){s.extension_valid|=TD_EXT_CALIBRATION;s.calibration_state=state;s.calibration_window=q.session;s.calibration_elapsed=2000;s.calibration_samples=8;s.calibration_net=net;s.calibration_absolute=absolute;s.calibration_sequence=q.sequence;}
 uint8_t bytes[TD_WIRE_BYTES];assert(td_encode(&s,bytes,sizeof bytes));return [NSData dataWithBytes:bytes length:sizeof bytes];
}
static NSDictionary *Status(TDRuntimeSession *s){return s.status;}
static NSData *Carrier(NSData *raw){NSMutableString *hex=[NSMutableString new];const uint8_t *p=raw.bytes;for(NSUInteger i=0;i<raw.length;i++)[hex appendFormat:@"%02x",p[i]];NSData *json=[[NSString stringWithFormat:@"{\"cmd\":\"turbo_diagnostics_v1\",\"payload\":{\"data\":\"%@\"}}",hex]dataUsingEncoding:NSUTF8StringEncoding];assert(json.length==564);uint8_t head[]={8,1,16,6,26,0xb4,4};NSMutableData *out=[NSMutableData dataWithBytes:head length:7];[out appendData:json];return out;}
static NSDictionary *Event(NSData *raw){return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":@"peer-one",@"payload":Carrier(raw)}};}
static void LeaseOrdering(void){
 for(unsigned order=0;order<3;order++){
  __block double now=100;__block TDCommand command;__block unsigned sends=0;__block __weak TDRuntimeSession *weak=nil;
  TDRuntimeSession *r=[[TDRuntimeSession alloc]initWithPeer:^{return @"lease";} allowed:^BOOL{return YES;} clock:^{return now;} send:^BOOL(TDCommand q){command=q;sends++;weak.fileBusy=YES;return YES;}];weak=r;assert([r beginCalibration]);TDCommand start=command;
  if(order==1){now=101;r.fileBusy=NO;}
  if(order<2){now=102;assert([r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:@"lease"]);if(order==0){now=110;r.fileBusy=NO;}now=130;assert(r.idleForOTA);[r finishCalibration];assert(!r.holdsLease&&sends==1&&[r.status[@"state"]isEqual:@"expired"]);}
  else{now=131;[r poll];assert(!r.holdsLease&&!r.idleForOTA&&r.fileBusy);r.fileBusy=NO;assert(r.holdsLease&&!r.idleForOTA&&sends==1);now=160.999;assert(!r.idleForOTA);now=161;assert(r.idleForOTA);[r finishCalibration];assert(!r.holdsLease&&sends==1);}
 }
 // A queued Finish must not be dispatched by a late terminal after known expiry.
 __block double now=100;__block TDCommand command;__block unsigned sends=0;__block __weak TDRuntimeSession *weak=nil;
 TDRuntimeSession *r=[[TDRuntimeSession alloc]initWithPeer:^{return @"queue";} allowed:^BOOL{return YES;} clock:^{return now;} send:^BOOL(TDCommand q){command=q;sends++;weak.fileBusy=YES;return YES;}];weak=r;assert([r beginCalibration]);now=102;assert([r receive:Packet(command,TD_CALIBRATION,TK_ACTIVE,600,600) device:@"queue"]);now=129;[r finishCalibration];assert(sends==1);now=131;r.fileBusy=NO;assert(sends==1&&r.idleForOTA&&!r.holdsLease);
}
static void RejectedStart(void){@autoreleasepool{
 __block double now=100;__block TDCommand sent;__block __weak TDRuntimeSession *weak=nil;
 TDRuntimeSession *r=[[TDRuntimeSession alloc]initWithPeer:^{return @"host-peer";} allowed:^BOOL{return YES;} clock:^{return now;} send:^BOOL(TDCommand q){sent=q;weak.fileBusy=YES;return YES;}];weak=r;
 assert([r beginCalibration]);TDSample s={.build=TD_BUILD_TMG4,.kind=TD_CALIBRATION,.session=sent.session,.sequence=sent.sequence,.caps=TD_CAPS_ALL,.detent=600,.calibration_result=TK_BLOCKED};
 uint8_t raw[TD_WIRE_BYTES];assert(td_encode(&s,raw,sizeof raw));now=101;assert([r receive:[NSData dataWithBytes:raw length:sizeof raw] device:@"host-peer"]);
 printf("REPRO refused START: state=%s pending=%d holdsLease=%d fileBusy=%d expected_lease=0\n",[r.status[@"state"]UTF8String],r.pending,r.holdsLease,r.fileBusy);bool bad=r.holdsLease;
 now=102;r.fileBusy=NO;printf("REPRO file terminal after refused START: holdsLease=%d idleForOTA=%d expected_lease=0 expected_idle=1\n",r.holdsLease,r.idleForOTA);bad|=r.holdsLease;
 now=131;printf("REPRO 31s after send: holdsLease=%d (deadline renewed by file terminal)\n",r.holdsLease);
 assert(!bad);
}}

int main(void){@autoreleasepool{
 RejectedStart();LeaseOrdering();
 __block NSString *peer=@"peer-one";__block BOOL allowed=YES;__block double now=100;__block TDCommand sent={0};__block unsigned sends=0;__block __weak TDRuntimeSession *weak=nil;
 TDRuntimeSession *r=[[TDRuntimeSession alloc]initWithPeer:^{return peer;} allowed:^BOOL{return allowed;} clock:^{return now;} send:^BOOL(TDCommand q){sent=q;sends++;weak.fileBusy=YES;return YES;}];weak=r;
 assert([r query]&&r.pending&&r.fileBusy&&sent.op==TDQ_STATUS);unsigned pure_sends=sends;assert(![r idleForOTA]&&sends==pure_sends);TDCommand query=sent;TDCommand wrong=sent;wrong.sequence++;assert(![r receive:Packet(wrong,TD_STATUS,0,0,0) device:peer]);assert(![r receive:Packet(query,TD_STATUS,0,0,0) device:@"other"]);assert(![r receive:Packet(query,TD_SAMPLE,0,0,0) device:peer]);assert([r receive:Packet(query,TD_STATUS,0,0,0) device:peer]&&!r.pending&&!r.holdsLease);assert([Status(r)[@"sample"][@"nand_available"]unsignedLongLongValue]==64000);assert(![r query]&&sends==1);r.fileBusy=NO;
 assert([r beginCalibration]&&r.holdsLease&&r.pending);TDCommand start=sent;unsigned before=sends;[r finishCalibration];assert(sends==before);assert([r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]&&!r.pending&&sends==before);r.fileBusy=NO;assert(sends==before+1&&sent.op==TDQ_KNOB_STOP&&r.pending);TDCommand stop=sent;assert(![r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]);assert([r receive:Packet(stop,TD_CALIBRATION,TK_FINISHED,4800,4800) device:peer]&&!r.holdsLease);assert([Status(r)[@"estimate"]unsignedLongLongValue]==4800);r.fileBusy=NO;
 // File terminal before START reply is the opposite valid ordering.
 assert([r beginCalibration]);start=sent;r.fileBusy=NO;before=sends;[r finishCalibration];assert(sends==before);assert([r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]&&sends==before+1);stop=sent;r.fileBusy=NO;assert(r.holdsLease);assert([r receive:Packet(stop,TD_CALIBRATION,TK_FINISHED,500,1500) device:peer]&&Status(r)[@"estimate"]==NSNull.null);
 assert([r beginCalibration]);start=sent;r.fileBusy=NO;now+=3;[r poll];assert(!r.pending&&r.holdsLease);assert(![r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]);before=sends;now+=31;[r poll];assert(!r.holdsLease&&sends==before);
 assert([r beginCalibration]);start=sent;r.fileBusy=NO;assert([r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]);before=sends;[r invalidate];assert(!r.pending&&r.holdsLease&&sends==before);assert(![r beginCalibration]);now+=31;[r poll];assert(!r.holdsLease);assert([r query]);before=sends;[r transportFailed];assert(!r.pending&&r.fileBusy&&! [r query]&&sends==before);r.fileBusy=NO;
 assert([r beginCalibration]);start=sent;r.fileBusy=NO;assert([r receive:Packet(start,TD_CALIBRATION,TK_ACTIVE,600,600) device:peer]);[r cancelCalibration];stop=sent;assert(stop.op==TDQ_KNOB_STOP);assert([r receive:Packet(stop,TD_CALIBRATION,TK_FINISHED,4800,4800) device:peer]&&Status(r)[@"estimate"]==NSNull.null);r.fileBusy=NO;
 assert([r beginCalibration]);peer=@"peer-two";[r poll];assert(!r.pending&&!r.holdsLease&&![r query]);assert([[Status(r)description]rangeOfString:@"peer-one"].location==NSNotFound);
 // A synchronous response cannot be overwritten when submission returns.
 __block __weak TDRuntimeSession *syncWeak=nil;TDRuntimeSession *sync=[[TDRuntimeSession alloc]initWithPeer:^{return @"sync";} allowed:^BOOL{return YES;} clock:^{return now;} send:^BOOL(TDCommand q){syncWeak.fileBusy=YES;assert([syncWeak receive:Packet(q,TD_STATUS,0,0,0) device:@"sync"]);return YES;}];syncWeak=sync;assert([sync query]&&!sync.pending&&[sync.status[@"sample"]count]);
 TDPhoneStore *autoStore=[[TDPhoneStore alloc]initWithBuild:0 device:@"store"];assert([autoStore begin:12]);
 TDSample newer={.build=TD_BUILD_TMG5,.session=12,.sequence=1,.caps=TD_CAPS_TMG5,.detent=600};uint8_t newerWire[TD_WIRE_BYTES];assert(td_encode(&newer,newerWire,sizeof newerWire));assert([autoStore receive:[NSData dataWithBytes:newerWire length:sizeof newerWire] fromDevice:@"store"]);
 newer.build=TD_BUILD_TMG4;newer.caps=TD_CAPS_ALL;newer.sequence=2;assert(td_encode(&newer,newerWire,sizeof newerWire));assert(![autoStore receive:[NSData dataWithBytes:newerWire length:sizeof newerWire] fromDevice:@"store"]);[autoStore end];assert([autoStore begin:12]);assert([autoStore receive:[NSData dataWithBytes:newerWire length:sizeof newerWire] fromDevice:@"store"]);
 TDPhoneStore *store=[[TDPhoneStore alloc]initWithBuild:TD_BUILD_TMG4 device:@"store"];assert([store begin:11]);TDCommand sq={TDQ_START,11,1,600000};assert([store receive:Packet(sq,TD_SAMPLE,0,0,0) fromDevice:@"store"]&&store.count==1);sq.sequence=2;assert(![store receive:Packet(sq,TD_STATUS,0,0,0) fromDevice:@"store"]&&store.count==1);assert([store receive:Packet(sq,TD_SAMPLE,0,0,0) fromDevice:@"store"]&&store.count==2);
 NSData *raw=Packet((TDCommand){TDQ_STATUS,1,1,0},TD_STATUS,0,0,0);NSDictionary *event=Event(raw);assert([event[@"message"][@"payload"]length]==571&&[TDPhoneReply(event)isEqual:raw]);NSMutableData *bad=[event[@"message"][@"payload"]mutableCopy];((uint8_t *)bad.mutableBytes)[312]='A';assert(!TDPhoneReply(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"payload":bad}}));assert(!TDPhoneReply(@{}));
 NSLog(@"PASS runtime phone: kinds/correlation, both file-ACK orders, single queued finish, leases/uncertain ownership, synthetic-free estimate policy and strict 571-byte carrier");
}return 0;}
