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
/* What a frozen TMG8 glasses decoder accepts (FW8 menu_config.c): the proof that a TMG8 peer never receives the peer byte 2 or a D. */
static BOOL Tmg8Accepts(NSData *wire){
 uint8_t p[32];if(!tml_uncarrier(wire.bytes,wire.length,p,false))return NO;
 if(memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]>1||Le(p+24)||!Le(p+8)||!Le(p+20)||Le(p+28)!=tml_crc(p,28))return NO;
 return p[5]==TML_QUERY?(!p[6]&&!Le(p+12)&&!Le(p+16)&&!p[7]):((p[6]>=1&&p[6]<=3)&&Le(p+12)&&p[7]==(p[6]==1?1u:0u));
}
static void Detent(void){@autoreleasepool{
 __block uint32_t caps=TD_CAPS_TMG8;__block NSString *peer=@"glasses-9";__block double now=300;__block NSMutableArray<NSData *> *wires=[NSMutableArray new];__block unsigned finished=0;__block TMLCommand q;
 TIOMenuLayoutLink *link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return peer;} allowed:^{return YES;} clock:^{return now;} caps:^uint32_t{return caps;} send:^BOOL(NSData *p){[wires addObject:p];return YES;}];
 void(^done)(void)=^{finished++;};
 void(^last)(void)=^{uint8_t raw[32];assert(wires.count&&tml_uncarrier(wires.lastObject.bytes,wires.lastObject.length,raw,false)&&tml_decode(raw,32,&q));};
 /* A TMG8 peer (bit 9, no bit 10): a D-carrying SET is refused before anything is encoded or sent, whatever D is. */
 assert(link.glassesReportTMG8Caps&&!link.glassesReportTMG9DetentCaps);
 [link chooseDetent:500 done:done];assert(finished==1&&!wires.count&&!link.busy);
 [link query:done];last();assert(q.op==TML_QUERY&&q.caps==0&&q.detent==0);[link consume:Event(q,3,0,95,peer)];assert(link.ready&&link.rows==3&&finished==2);
 [link chooseDetent:500 done:done];assert(finished==3&&wires.count==1&&link.ready); /* refused with a ready token: still no write, token untouched */
 [link choose:1 done:done];last();assert(q.op==TML_SET&&q.rows==1&&q.caps==TML_PEER_TMG8&&q.detent==0);[link consume:Event(q,1,0,0,peer)];
 for(NSData *w in wires){assert(Tmg8Accepts(w));} /* everything the TMG8 peer received is TMG8-valid, none carries D */
 /* A TMG9 peer reports bit 10. */
 caps=TD_CAPS_TMG9;[wires removeAllObjects];assert(link.glassesReportTMG9DetentCaps&&link.glassesReportTMG8Caps);
 [link query:done];last();assert(q.caps==0&&q.detent==0&&Tmg8Accepts(wires.lastObject));[link consume:Event(q,2,0,96,peer)];assert(link.ready&&link.rows==2);
 /* Out-of-range and off-step values never reach the codec. */
 NSUInteger sent=wires.count;for(NSNumber *bad in @[@0,@250,@299,@325,@601,@650,@1000,@4294967296ull]){[link chooseDetent:bad.unsignedIntegerValue done:done];}
 assert(wires.count==sent&&!link.busy&&link.ready);
 /* A good D re-sends the confirmed layout with the TMG9 peer byte and D. */
 [link chooseDetent:500 done:done];last();
 assert(q.op==TML_SET&&q.rows==2&&q.caps==TML_PEER_TMG9&&q.detent==500&&q.token==96&&q.generation==1&&!Tmg8Accepts(wires.lastObject)&&!Tmg7Accepts(wires.lastObject));
 [link consume:Event(q,2,0,0,peer)];assert(!link.busy&&link.rows==2);
 for(NSNumber *d in @[@300,@350,@400,@450,@500,@550,@600]){
  [link query:done];last();[link consume:Event(q,2,0,97,peer)];[link chooseDetent:d.unsignedIntegerValue done:done];last();
  assert(q.op==TML_SET&&q.caps==TML_PEER_TMG9&&q.detent==d.unsignedIntegerValue&&q.rows==2);[link consume:Event(q,2,0,0,peer)];
 }
 /* chooseDetent reads the layout first when there is no ready token (it is the SET's layout), then writes. */
 [wires removeAllObjects];now+=200;assert(!link.ready);[link chooseDetent:450 done:done];last();assert(q.op==TML_QUERY&&q.detent==0&&q.caps==0);
 [link consume:Event(q,1,0,98,peer)];last();assert(q.op==TML_SET&&q.rows==1&&q.caps==TML_PEER_TMG9&&q.detent==450); /* carousel layout + D: the TMG9 byte covers both */
 [link consume:Event(q,1,0,0,peer)];
 /* Layout writes without D keep the old forms for a TMG9 peer too (D = 0 means unchanged on the glasses). */
 [link query:done];last();[link consume:Event(q,1,0,99,peer)];[link choose:3 done:done];last();assert(q.op==TML_SET&&q.rows==3&&q.caps==0&&q.detent==0&&Tmg7Accepts(wires.lastObject));[link consume:Event(q,3,0,0,peer)];
 [link query:done];last();[link consume:Event(q,3,0,100,peer)];[link choose:1 done:done];last();assert(q.caps==TML_PEER_TMG8&&q.detent==0&&Tmg8Accepts(wires.lastObject));[link consume:Event(q,1,0,0,peer)];
 /* The bit disappears while the layout is being read (a rollback to TMG8): the queued D write is dropped. */
 [wires removeAllObjects];now+=200;[link chooseDetent:350 done:done];last();assert(q.op==TML_QUERY);caps=TD_CAPS_TMG8;[link consume:Event(q,3,0,101,peer)];
 assert(!link.busy&&wires.count==1&&!link.glassesReportTMG9DetentCaps);
 caps=TD_CAPS_TMG9;peer=@"";assert(!link.glassesReportTMG9DetentCaps); /* no connected peer */
 puts("MenuLayout detent PASS: D only on a SET to a TMG9 peer with the TMG9 peer byte, never encoded for TMG7/TMG8, range checked, TMG8 forms unchanged");
}}

/* The knob step against a simulated TMG9 glasses: a real two-bank menu file, the real decoder and acceptance (menu_config.c, byte-shared with the
 * firmware), and a status "detent" that is only ever what the glasses stored. The phone's confirmation is the read-back, not the SET reply. */
typedef struct {uint8_t p[2][32];int n[2];unsigned writes;int fail_write;} KnobDisk;
static int KnobRead(void *ctx,unsigned bank,uint8_t *p,size_t cap){KnobDisk *d=ctx;int n=d->n[bank];assert(n<=(int)cap);memcpy(p,d->p[bank],n);return n;}
static bool KnobWrite(void *ctx,unsigned bank,const uint8_t *p,size_t n){KnobDisk *d=ctx;if(d->fail_write)return false;memcpy(d->p[bank],p,n);d->n[bank]=(int)n;d->writes++;return true;}
typedef struct {KnobDisk disk;TMLState state;uint32_t now,nonce;BOOL mute;unsigned sets;} KnobGlasses;
static KnobGlasses g; /* a global: the TMLIO below points into it, and a __block copy would move to the heap */
static void Knob(void){@autoreleasepool{
 memset(&g,0,sizeof g);g.nonce=41;TMLIO io={&g.disk,KnobRead,KnobWrite};
 __block uint32_t caps=TD_CAPS_TMG9;__block NSString *peer=@"glasses-9";__block double now=300;__block BOOL fresh=YES,statusMute=NO;__block unsigned queries=0;
 __block TIOMenuLayoutLink *link=nil;
 link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return peer;} allowed:^{return YES;} clock:^{return now;} caps:^uint32_t{return caps;} send:^BOOL(NSData *wire){
  uint8_t raw[32];TMLCommand q;if(!tml_uncarrier(wire.bytes,wire.length,raw,false)||!tml_decode(raw,32,&q))return NO;
  if(g.mute)return YES;
  g.now+=100;unsigned result=tml_accept(&g.state,&q,g.now,g.nonce++,true,&io);if(q.op==TML_SET&&result==TML_OK)g.sets++;
  uint8_t reply[32],carrier[74];tml_reply(reply,&g.state,&q,result);tml_carrier(carrier,reply,true);
  NSDictionary *event=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:carrier length:74]}};
  dispatch_async(dispatch_get_main_queue(),^{[link consume:event];}); /* the reply arrives after send returns, as on the device */
  return YES;
 }];
 /* The status "detent": the live D the glasses stored. A new sample arrives when the phone asks (refresh) and the status channel is not muted. */
 __block uint32_t sampleD=0;
 TMLStored boot=tml_load(&io);sampleD=tml_detent(&boot);assert(sampleD==400); /* nothing stored: the default */
 TIOKnobStep *step=[[TIOKnobStep alloc]initWithLink:link reported:^uint32_t{return fresh?sampleD:0;} refresh:^BOOL{queries++;if(statusMute)return NO;TMLStored s=tml_load(&io);sampleD=tml_detent(&s);return YES;} clock:^{return now;}];
 void(^spin)(BOOL(^)(void),double)=^(BOOL(^until)(void),double seconds){NSTimeInterval end=NSProcessInfo.processInfo.systemUptime+seconds;while(!until()&&NSProcessInfo.processInfo.systemUptime<end)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];};
 assert(step.enabled&&step.state==TIOKnobStepIdle);

 /* Refused before anything is sent: not 300..600 in steps of 50, already the reported value. */
 for(NSNumber *bad in @[@0,@250,@299,@325,@601,@650,@4294967296ull]){assert(![step apply:bad.unsignedIntegerValue]);}
 assert(![step apply:400]&&step.state==TIOKnobStepIdle&&!link.busy&&queries==0); /* 400 is what the glasses report */

 /* Apply 500: the link queries the layout, sends one D-carrying SET with the TMG9 peer byte, the glasses store D, the status reads 500 back. */
 assert([step apply:500]&&step.state==TIOKnobStepPending&&step.target==500);
 assert(![step apply:550]&&step.target==500); /* no second write while one is pending */
 spin(^BOOL{[step poll];return step.state!=TIOKnobStepPending;},5);
 assert(step.state==TIOKnobStepConfirmed&&sampleD==500&&g.sets==1&&queries>=1);
 TMLStored s500=tml_load(&io);assert(tml_detent(&s500)==500&&s500.rows==3); /* the layout it re-sent is the one that was stored */

 /* The stored byte 6 is D/50 = 10, and the record stays valid for the glasses decoder. */
 uint8_t bank=(uint8_t)s500.bank;assert(g.disk.n[bank]==20&&g.disk.p[bank][6]==10);

 /* Each valid D round-trips: 300, 350 ... 600 (400 is the default, stored as 0). */
 for(unsigned d=300;d<=600;d+=50){
  if(d==sampleD)continue;now+=1;[step reset];
  assert([step apply:d]);spin(^BOOL{[step poll];return step.state!=TIOKnobStepPending;},5);
  assert(step.state==TIOKnobStepConfirmed&&sampleD==d);
  TMLStored s=tml_load(&io);assert(tml_detent(&s)==d);uint8_t b=(uint8_t)s.bank;assert(g.disk.p[b][6]==(d==400?0:d/50));
 }

 /* The SET is acknowledged but the status never says D (status lost, or the glasses stored something else): Failed after the read-back window, with
  * no retry of the SET and no claim of a change. */
 now+=1;[step reset];unsigned setsBefore=g.sets;statusMute=YES;uint32_t before=sampleD;unsigned next=before==450?500:450;
 assert([step apply:next]);spin(^BOOL{return !link.busy;},5);[step poll];assert(step.state==TIOKnobStepPending); /* layout confirmed, waiting for the status */
 now+=TIOKnobStepReadbackSeconds-1;[step poll];assert(step.state==TIOKnobStepPending);
 now+=2;[step poll];assert(step.state==TIOKnobStepFailed&&g.sets==setsBefore+1);
 assert(sampleD==before); /* the phone still reports what the glasses reported */
 spin(^BOOL{return NO;},.2);assert(g.sets==setsBefore+1); /* no automatic retry */
 statusMute=NO;

 /* A stale sample cannot confirm: the reported value is 0 (unknown) until a fresh status arrives. */
 now+=1;[step reset];fresh=NO;assert([step apply:next]);spin(^BOOL{return !link.busy;},5);[step poll];assert(step.state==TIOKnobStepPending);
 fresh=YES;[step poll];assert(step.state==TIOKnobStepConfirmed&&sampleD==next);

 /* The glasses refuse the SET (storage failure): the layout reply is an error, so Failed at once and D is unchanged. */
 now+=1;[step reset];before=sampleD;next=before==350?300:350;g.disk.fail_write=1;
 assert([step apply:next]);spin(^BOOL{[step poll];return step.state!=TIOKnobStepPending;},5);
 assert(step.state==TIOKnobStepFailed&&sampleD==before&&tml_detent(&(TMLStored){0})==400);
 TMLStored kept=tml_load(&io);assert(tml_detent(&kept)==before);g.disk.fail_write=0;

 /* No reply from the glasses at all: the link gives up after 3 s (rows cleared), so Failed, nothing confirmed. */
 now+=1;[step reset];g.mute=YES;assert([step apply:next]);
 spin(^BOOL{[step poll];return step.state!=TIOKnobStepPending;},6);assert(step.state==TIOKnobStepFailed&&sampleD==before);g.mute=NO;

 /* The whole attempt has a deadline even when the layout never finishes. */
 [link cancel];now+=1;[step reset];g.mute=YES;assert([step apply:next]);now+=TIOKnobStepDeadlineSeconds+1;[step poll];assert(step.state==TIOKnobStepFailed);
 spin(^BOOL{return !link.busy;},6);g.mute=NO;assert(step.state==TIOKnobStepFailed); /* a late link completion does not revive it */

 /* TMG8 and older glasses: disabled, nothing encoded or sent. */
 for(NSNumber *old in @[@(TD_CAPS_TMG8),@(TD_CAPS_TMG6),@(TD_CAPS_ALL)]){
  caps=old.unsignedIntValue;now+=1;[step reset];unsigned sets=g.sets;assert(!step.enabled&&![step apply:450]&&step.state==TIOKnobStepIdle&&g.sets==sets&&!link.busy);
 }
 caps=0;assert(!step.enabled&&![step apply:450]); /* no status sample yet */
 caps=TD_CAPS_TMG9;peer=@"glasses-other";assert(step.enabled);[step reset];
 puts("MenuLayout knob step PASS: confirmed only by the status read-back, pending/failed states, deadlines and no retry, disabled below TMG9, every D round-trips through the real store");
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
 Detent();
 Knob();
 puts("MenuLayout phone PASS: query-before-write, exact peer/request/op, ACK-not-submission, no queued writes, expiry, OTA/background cancel, timeout and no retry");
}}
