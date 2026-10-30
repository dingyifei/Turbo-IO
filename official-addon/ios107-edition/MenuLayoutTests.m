#import "MenuLayout.h"
#include "menu_config.h"
#include "diagnostics.h"
#include <assert.h>
static NSDictionary *Event(TMLCommand q,unsigned rows,unsigned result,uint32_t token,NSString *peer){
 TMLState state={.token=token,.stored={.rows=rows,.generation=1}};uint8_t raw[32],wire[74];tml_reply(raw,&state,&q,result);tml_carrier(wire,raw,true);
 return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:wire length:74]}};
}
/* What a frozen TMG7 glasses decoder accepts (FW7 menu_config.c): the proof that a TMG7 peer never receives layout 1. */
static uint32_t Le(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static BOOL Tmg7Accepts(NSData *wire){
 uint8_t p[32];if(!tml_uncarrier(wire.bytes,wire.length,p,false))return NO;
 if(memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]||Le(p+24)||!Le(p+8)||!Le(p+20)||Le(p+28)!=tml_crc(p,28))return NO;
 return p[5]==TML_QUERY?(!p[6]&&!Le(p+12)&&!Le(p+16)):((p[6]==2||p[6]==3)&&Le(p+12));
}
static void Carousel(void){@autoreleasepool{
 __block uint32_t caps=TD_CAPS_TMG6;__block NSString *peer=@"glasses-8";__block double now=200;__block NSMutableArray<NSData *> *wires=[NSMutableArray new];__block unsigned finished=0;__block TMLCommand q;
 TIOMenuLayoutLink *link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return peer;} allowed:^{return YES;} clock:^{return now;} caps:^uint32_t{return caps;} send:^BOOL(NSData *p){[wires addObject:p];return YES;}];
 void(^done)(void)=^{finished++;};
 void(^last)(void)=^{uint8_t raw[32];assert(wires.count&&tml_uncarrier(wires.lastObject.bytes,wires.lastObject.length,raw,false)&&tml_decode(raw,32,&q));};
 /* A TMG7 peer: no caps bit, so layout 1 is refused before anything is encoded or sent. */
 assert(!link.glassesReportTMG8Caps);
 [link choose:1 done:done];assert(finished==1&&!wires.count&&!link.busy);
 [link query:done];last();assert(q.op==TML_QUERY&&q.caps==0);[link consume:Event(q,3,0,91,peer)];assert(finished==2&&link.ready&&link.rows==3);
 [link choose:1 done:done];assert(finished==3&&wires.count==1&&!link.busy&&link.ready); /* refused, still no write, token untouched */
 [link choose:2 done:done];last();assert(q.op==TML_SET&&q.rows==2&&q.caps==0&&Tmg7Accepts(wires.lastObject));[link consume:Event(q,2,0,0,peer)];assert(link.rows==2);
 for(NSData *w in wires){assert(Tmg7Accepts(w));} /* every byte this TMG7 peer received is TMG7-valid, and none carries layout 1 */
 /* A TMG8 peer reports the bit: layout 1 is a SET with the caps byte, and the confirmation of 1 is accepted. */
 caps=TD_CAPS_TMG8;[wires removeAllObjects];assert(link.glassesReportTMG8Caps);
 [link query:done];last();[link consume:Event(q,3,0,92,peer)];assert(link.ready&&link.rows==3);
 [link choose:1 done:done];last();assert(q.op==TML_SET&&q.rows==TML_CAROUSEL&&q.caps==TML_PEER_TMG8&&q.token==92&&!Tmg7Accepts(wires.lastObject));
 [link consume:Event(q,1,0,0,peer)];assert(!link.busy&&link.rows==1&&!link.ready);
 /* Grid writes to a TMG8 peer keep the TMG7 form. */
 [link query:done];last();[link consume:Event(q,1,0,93,peer)];assert(link.rows==1&&link.ready);
 [link choose:3 done:done];last();assert(q.op==TML_SET&&q.rows==3&&q.caps==0&&Tmg7Accepts(wires.lastObject));[link consume:Event(q,3,0,0,peer)];assert(link.rows==3);
 /* The bit disappears while the layout is being read (other glasses, or a rollback to TMG7): the queued carousel write is dropped. */
 [wires removeAllObjects];[link choose:1 done:done];last();assert(q.op==TML_QUERY);caps=TD_CAPS_TMG6;[link consume:Event(q,3,0,94,peer)];
 assert(!link.busy&&wires.count==1&&!link.glassesReportTMG8Caps);
 caps=TD_CAPS_TMG8;peer=@"";assert(!link.glassesReportTMG8Caps); /* no connected peer */
 [link choose:7 done:done]; /* out-of-range values never reach the codec */
 puts("MenuLayout carousel PASS: layout 1 only for TMG8 peers, caps byte on the carousel SET alone, TMG7 peers receive only TMG7-valid records");
}}
int main(void){@autoreleasepool{
 __block NSString *peer=@"glasses-a";__block BOOL allowed=YES,submitted=YES;__block double now=100;__block NSData *sent;__block unsigned sends=0,done=0;
 TIOMenuLayoutLink *link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return peer;} allowed:^{return allowed;} clock:^{return now;} send:^BOOL(NSData *p){sent=p;sends++;return submitted;}];
 void(^callback)(void)=^{done++;};uint8_t raw[32];TMLCommand q;
 [link query:callback];assert(link.busy&&!link.ready&&!link.rows&&sends==1);
 assert(tml_uncarrier(sent.bytes,sent.length,raw,false)&&tml_decode(raw,32,&q)&&q.op==TML_QUERY);
 assert([link consume:Event(q,3,0,77,@"wrong")]&&link.busy);
 TMLCommand wrong=q;wrong.request++;assert([link consume:Event(wrong,3,0,77,peer)]&&link.busy);
 assert([link consume:Event(q,3,0,77,peer)]&&!link.busy&&link.ready&&link.rows==3&&done==1);
 [link choose:2 done:callback];assert(link.busy&&!link.ready&&sends==2);
 assert(tml_uncarrier(sent.bytes,sent.length,raw,false)&&tml_decode(raw,32,&q)&&q.op==TML_SET&&q.rows==2&&q.token==77&&q.generation==1);
 [link choose:3 done:nil];assert(sends==2); /* no queued toggles */
 assert([link consume:Event(q,2,0,0,peer)]&&!link.busy&&link.rows==2&&done==2);
 [link choose:3 done:callback];assert(sends==3);tml_uncarrier(sent.bytes,sent.length,raw,false);assert(tml_decode(raw,32,&q)&&q.op==TML_QUERY);
 allowed=NO;[link consume:Event(q,2,0,78,peer)];assert(!link.busy&&!link.ready&&!link.rows&&sends==3); /* no SET after background/OTA */
 allowed=YES;[link query:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);[link consume:Event(q,2,0,79,peer)];assert(link.ready);
 now+=111;assert(!link.ready);peer=@"glasses-b";assert(!link.rows);[link choose:2 done:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);assert(q.op==TML_QUERY);
 [link cancel];unsigned count=sends;[link consume:Event(q,2,0,80,peer)];assert(sends==count&&!link.busy&&!link.ready);
 [link query:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);[link consume:Event(q,3,TML_STORAGE,0,peer)];assert(!link.ready&&!link.rows);
 submitted=NO;[link choose:2 done:callback];assert(!link.busy&&!link.ready);
 assert(!TIOMenuLayoutIsReply(@{}));
 submitted=YES;[link query:callback];count=sends;NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+8;while(link.busy&&NSProcessInfo.processInfo.systemUptime<deadline)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(!link.busy&&!link.ready&&!link.rows&&sends==count);
 Carousel();
 puts("MenuLayout phone PASS: query-before-write, exact peer/request/op, ACK-not-submission, no queued writes, expiry, OTA/background cancel, timeout and no retry");
}}
