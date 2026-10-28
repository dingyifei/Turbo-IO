#import "MenuLayout.h"
#include "tile_config.h"
#include <assert.h>
extern int native_remote_baseline_main(void);
extern void diagnosis_reset(void),diagnosis_reboot(void),diagnosis_finish(void),diagnosis_send(const uint8_t *,unsigned,uint8_t *);
extern unsigned diagnosis_count(void),diagnosis_rank(unsigned);
int main(void){@autoreleasepool{
 assert(native_remote_baseline_main()==0);diagnosis_reset();
 __block __weak TIOTileLayoutLink *weak=nil;__block unsigned sent=0;__block TTReply last;
 TIOTileLayoutLink *link=[[TIOTileLayoutLink alloc]initWithPeer:^{return @"host-peer";} allowed:^BOOL{return YES;} clock:^{return 100.0;} send:^BOOL(NSData *data){
  sent++;uint8_t out[74],raw[32];diagnosis_send(data.bytes,(unsigned)data.length,out);assert(tt_uncarrier(out,74,raw,true)&&tt_reply_decode(raw,32,&last));
  NSDictionary *e=@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"host-peer",@"businessId":@15,@"payload":[NSData dataWithBytes:out length:74]}};
  assert(TIOMenuLayoutIsReply(e));assert([weak consume:e]);return YES;
 }];weak=link;[link query:nil];assert(link.ready&&last.token==77&&last.generation==0&&sent==1);
 NSArray *order=@[@0,@1,@2,@3,@4,@5,@6,@12,@11,@10,@9,@8,@7];[link saveOrder:order hide:0xf80 done:nil];
 assert(!link.busy&&!link.ready&&[link.order isEqual:order]&&link.hide==0xf80&&last.generation==1&&last.result==TT_OK&&sent==2);
 assert(diagnosis_count()==8&&diagnosis_rank(12)==7);diagnosis_reboot();assert(diagnosis_count()==8&&diagnosis_rank(12)==7);
 [link query:nil];assert(link.ready&&[link.order isEqual:order]&&link.hide==0xf80&&last.generation==1&&sent==3);
 printf("PASS actual phone TTL codec/link -> native handler -> durable mock A/B -> actual TTA decoder: sends=%u generation=%u visible=%u CameraRank=%u; reboot reload preserved\n",sent,last.generation,diagnosis_count(),diagnosis_rank(12));
 [link cancel];diagnosis_finish();return 0;
}}
