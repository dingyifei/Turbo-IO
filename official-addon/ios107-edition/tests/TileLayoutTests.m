#import "MenuLayout.h"
#include "tile_config.h"
#include <assert.h>
static NSDictionary *Event(TTReply reply,NSString *peer){uint8_t raw[32],wire[74];tt_reply_encode(raw,&reply);tt_carrier(wire,raw,true);return @{ @"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:wire length:74]}};}
int main(void){@autoreleasepool{
 __block NSString *peer=@"one";__block BOOL allowed=YES;__block double now=100;__block NSData *wire=nil;__block NSUInteger sends=0,done=0;
 TIOTileLayoutLink *link=[[TIOTileLayoutLink alloc]initWithPeer:^{return peer;} allowed:^BOOL{return allowed;} clock:^{return now;} send:^BOOL(NSData *d){wire=d;sends++;return YES;}];
 assert(!link.ready&&!link.busy&&!link.order);[link query:^{done++;}];assert(link.busy&&sends==1);uint8_t raw[32];TTCommand q;assert(tt_uncarrier(wire.bytes,wire.length,raw,false)&&tt_decode(raw,32,&q)&&q.op==TT_QUERY);
 TTReply a={.request=q.request,.client=q.client,.token=99,.generation=UINT32_MAX,.op=TT_QUERY,.count=13};
 assert(TIOTileLayoutIsReply(Event(a,peer))&&TIOMenuLayoutIsReply(Event(a,peer)));a.request++;assert([link consume:Event(a,peer)]&&link.busy&&done==0);a.request--;assert([link consume:Event(a,@"two")]&&link.busy);assert([link consume:Event(a,peer)]&&!link.busy&&done==1&&link.ready&&link.order.count==13);
 NSArray *order=@[@0,@1,@2,@3,@4,@5,@6,@12,@11,@10,@9,@8,@7];[link saveOrder:order hide:0xf80 done:^{done++;}];assert(link.busy&&!link.ready&&sends==2);assert(tt_uncarrier(wire.bytes,wire.length,raw,false)&&tt_decode(raw,32,&q)&&q.op==TT_SET&&q.rank==719&&q.generation==UINT32_MAX);
 a=(TTReply){.request=q.request,.client=q.client,.generation=1,.op=TT_SET,.count=8,.rank=719,.hide=0xf80};assert([link consume:Event(a,peer)]&&!link.busy&&done==2&&[link.order isEqual:order]&&link.hide==0xf80&&!link.ready);
 // A SET consumes its grant, even after a successful ACK: another read is explicit.
 [link saveOrder:order hide:0 done:^{done++;}];assert(sends==2&&done==3&&!link.busy);
 [link query:^{done++;}];assert(tt_uncarrier(wire.bytes,wire.length,raw,false)&&tt_decode(raw,32,&q));a=(TTReply){.request=q.request,.client=q.client,.token=7,.op=TT_QUERY,.count=13};[link consume:Event(a,peer)];assert(link.ready);now+=111;assert(!link.ready);[link saveOrder:order hide:0 done:nil];assert(!link.busy&&sends==3);
 [link query:nil];assert(link.busy);[link cancel];a.request=q.request;[link consume:Event(a,peer)];assert(!link.busy&&!link.ready);
 [link query:nil];peer=@"two";assert(!link.ready);[link cancel];allowed=NO;NSUInteger previous=sends;[link query:nil];assert(sends==previous&&!link.busy);
 allowed=YES;[link query:nil];assert(tt_uncarrier(wire.bytes,wire.length,raw,false)&&tt_decode(raw,32,&q));a=(TTReply){.request=q.request,.client=q.client,.op=TT_QUERY,.count=13,.result=TT_UNAVAILABLE};[link consume:Event(a,peer)];assert(!link.busy&&!link.ready);
 // Arm ownership before send: a synchronous reply must survive the return path.
 __block __weak TIOTileLayoutLink *weak=nil;TIOTileLayoutLink *sync=[[TIOTileLayoutLink alloc]initWithPeer:^{return @"sync";} allowed:^BOOL{return YES;} clock:^{return now;} send:^BOOL(NSData *d){TTCommand cq;uint8_t r[32];assert(tt_uncarrier(d.bytes,d.length,r,false)&&tt_decode(r,32,&cq));TTReply ca={.request=cq.request,.client=cq.client,.token=9,.op=TT_QUERY,.count=13};[weak consume:Event(ca,@"sync")];return YES;}];weak=sync;[sync query:nil];assert(sync.ready&&!sync.busy);
 NSLog(@"PASS tile phone: wrap-safe authoritative ACK, peer/request correlation, grant consumption, expiry, unavailable and synchronous reply");
}return 0;}
