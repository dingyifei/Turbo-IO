/* The phone side of the glasses PIN lock (docs/lock-design.md §4, §5): commands go out through the shared codec
 * (lock_codec.c, byte-identical with the firmware), replies are matched to the exact peer, request, client and op, every
 * change reads a fresh token first, nothing is resent, the caps bit gates every send, MOTION_ON refused is handled, and
 * the page model follows the reply. The simulated glasses use the same codec and the firmware's own token session. */
#import "GlassesLock.h"
#import "TIOLanguage.h"
#include "lock_codec.h"
#include "diagnostics.h"
#include <assert.h>

typedef struct {TLKSession session;uint8_t flags,fold,idle,wrong,unacked;uint8_t pin[4];BOOL motionSupported,motionOn,refuseMotion,blocked,mute;uint32_t nonce,delay;unsigned commands;TLKCommand last;} Glasses;
static NSDictionary *Event(TLKReply r,NSString *peer){
 uint8_t raw[32],wire[74];tlk_reply_encode(raw,&r);tlk_carrier(wire,raw,true);
 return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:wire length:74]}};
}
/* What the glasses would answer, built with the firmware's session rules (tlk_session) and reply encoder. */
static TLKReply Answer(Glasses *g,NSData *wire,double now){
 uint8_t raw[32];TLKCommand q;assert(wire.length==74&&!memcmp((const uint8_t *)wire.bytes+6,"TLK:",4));
 assert(tlk_uncarrier(wire.bytes,wire.length,raw,false)&&tlk_decode(raw,32,&q));g->commands++;g->last=q;
 unsigned r=g->blocked?TLK_R_BLOCKED:tlk_session(&g->session,&q,(uint32_t)(now*1000),++g->nonce);
 if(r==TLK_R_OK)switch(q.op){
  case TLK_OP_UNLOCK:g->flags&=~TLK_F_LOCKED;g->wrong=0;g->delay=0;break;
  case TLK_OP_LOCK_NOW:if(g->flags&TLK_F_ENABLED)g->flags|=TLK_F_LOCKED;else r=TLK_R_REFUSED;break;
  case TLK_OP_SET_PIN:g->flags|=TLK_F_ENABLED;memcpy(g->pin,q.pin,4);g->wrong=0;break;
  case TLK_OP_SET_TIME:g->fold=q.fold_min;g->idle=q.idle_min;break;
  case TLK_OP_DISABLE:g->flags&=~(TLK_F_ENABLED|TLK_F_LOCKED);break;
  case TLK_OP_ACK_FAILURES:g->unacked=0;break;
  case TLK_OP_MOTION_ON:if(!g->motionSupported||g->refuseMotion)r=TLK_R_REFUSED;else g->motionOn=YES;break;
 }
 if(g->blocked)g->session.token=0;
 uint8_t flags=g->flags|(g->motionOn?TLK_F_MOTION:0)|(g->motionSupported?TLK_F_MOTION_SUPPORTED:0);
 return (TLKReply){.request=q.request,.client=q.client,.op=q.op,.result=(uint8_t)r,.flags=flags,.token=q.op==TLK_OP_QUERY&&r==TLK_R_OK?g->session.token:0,
  .fold_min=g->fold,.idle_min=g->idle,.wrong=g->wrong,.unacked=g->unacked,.delay_left=g->delay};
}
@interface Fixture:NSObject
@property(nonatomic,strong) TIOGlassesLockLink *link;
@property(nonatomic,copy) NSString *peer;
@property(nonatomic) double now;
@property(nonatomic) uint32_t caps;
@property(nonatomic) BOOL allowed;
@property(nonatomic,strong) NSMutableArray<NSData *> *wires;
@property(nonatomic) unsigned done;
@end
@implementation Fixture {@public Glasses g;}
- (instancetype)init{
 if((self=[super init])){
  _peer=@"glasses-13";_now=1000;_caps=TD_CAPS_TMG13;_allowed=YES;_wires=[NSMutableArray new];
  g.fold=5;g.idle=5;__weak Fixture *w=self;
  _link=[[TIOGlassesLockLink alloc]initWithPeer:^{return w.peer;} allowed:^BOOL{return w.allowed;} clock:^{return w.now;} caps:^uint32_t{return w.caps;} send:^BOOL(NSData *d){
   Fixture *f=w;[f.wires addObject:d];if(f->g.mute)return YES;TLKReply r=Answer(&f->g,d,f.now);[f.link consume:Event(r,f.peer)];return YES;}];
 }
 return self;
}
- (void(^)(void))cb{__weak Fixture *w=self;return ^{w.done++;};}
@end

static void Codec(void){@autoreleasepool{
 /* The phone's records are the glasses' records: each one the link sends decodes with the shared decoder, with the PIN as BCD. */
 Fixture *f=[Fixture new];[f.link setPin:@"9007" done:f.cb];
 assert(f.done==1&&f.wires.count==2&&f->g.commands==2);
 uint8_t raw[32];TLKCommand q;assert(tlk_uncarrier(f.wires[1].bytes,74,raw,false)&&tlk_decode(raw,32,&q));
 assert(q.op==TLK_OP_SET_PIN&&raw[22]==0x90&&raw[23]==0x07&&q.token&&q.client&&q.request&&!raw[20]&&!raw[21]);
 assert(tlk_uncarrier(f.wires[0].bytes,74,raw,false)&&tlk_decode(raw,32,&q)&&q.op==TLK_OP_QUERY&&!q.token);
 assert(!memcmp(f->g.pin,(uint8_t[]){9,0,0,7},4)&&(f->g.flags&TLK_F_ENABLED)&&f.link.lastResult==TLK_R_OK&&f.link.model.phase==TIOLockPhaseUnlocked);
 /* SET_TIME carries both minutes; 0 and 241 never leave the phone. */
 [f.wires removeAllObjects];[f.link setFold:1 idle:240 done:f.cb];
 assert(tlk_uncarrier(f.wires.lastObject.bytes,74,raw,false)&&tlk_decode(raw,32,&q)&&q.op==TLK_OP_SET_TIME&&q.fold_min==1&&q.idle_min==240);
 assert(f.link.model.foldMin==1&&f.link.model.idleMin==240);
 unsigned n=(unsigned)f.wires.count;[f.link setFold:0 idle:5 done:f.cb];[f.link setFold:5 idle:241 done:f.cb];assert(f.wires.count==n&&f.link.lastResult==TIOLockResultNotSent);
 /* PINs: exactly four ASCII digits. */
 uint8_t pin[4];assert(TIOLockParsePin(@"0000",pin)&&TIOLockParsePin(@"1234",pin)&&pin[0]==1&&pin[3]==4);
 for(NSString *bad in @[@"123",@"12345",@"12a4",@"１２３４",@" 123",@""])assert(!TIOLockParsePin(bad,pin));
 [f.link setPin:@"12a4" done:f.cb];assert(f.wires.count==n&&f.link.lastOp==TLK_OP_SET_PIN&&f.link.lastResult==TIOLockResultNotSent);
}}

static void Exchange(void){@autoreleasepool{
 Fixture *f=[Fixture new];f->g.flags=TLK_F_ENABLED|TLK_F_LOCKED;f->g.unacked=3;f->g.wrong=3;f->g.delay=30;
 /* QUERY: the state and the token; read-only. */
 [f.link query:f.cb];assert(f.done==1&&f.link.known&&f.link.lastOp==TLK_OP_QUERY&&f.link.lastResult==TLK_R_OK&&!f.link.note);
 TIOLockModel m=f.link.model;assert(m.phase==TIOLockPhaseLocked&&m.lockOn&&m.showUnlock&&!m.showLockNow&&m.wrong==3&&f.link.state.delay_left==30);
 /* Within the token's life the change uses it directly (one command), and the token is spent. */
 f.now+=50;[f.link unlock:f.cb];assert(f.wires.count==2&&f->g.last.op==TLK_OP_UNLOCK&&f.link.lastResult==TLK_R_OK&&f.link.model.phase==TIOLockPhaseUnlocked&&f.link.model.wrong==3);
 /* The next change reads a fresh token first: QUERY then the command. */
 [f.link acknowledgeFailures:f.cb];assert(f.wires.count==4&&f->g.last.op==TLK_OP_ACK_FAILURES&&f.link.model.wrong==0);
 /* A token older than the phone's use window is not used: the phone reads again. */
 [f.link query:f.cb];f.now+=TIOLockTokenUseSeconds;unsigned before=(unsigned)f.wires.count;[f.link lockNow:f.cb];
 assert(f.wires.count==before+2&&f->g.last.op==TLK_OP_LOCK_NOW&&f.link.model.phase==TIOLockPhaseLocked&&f.link.model.showUnlock);
 /* DISABLE turns the lock off from any state. */
 [f.link disable:f.cb];assert(f.link.model.phase==TIOLockPhaseOff&&!f.link.model.lockOn&&!f.link.model.showUnlock&&!f.link.model.showLockNow);
 /* A refused or expired change is reported and never resent. */
 before=(unsigned)f.wires.count;[f.link lockNow:f.cb];assert(f.wires.count==before+2&&f.link.lastResult==TLK_R_REFUSED&&[f.link.note isEqual:TIOText(@"lock.note.refused")]);
 f->g.blocked=YES;before=(unsigned)f.wires.count;[f.link unlock:f.cb];assert(f.wires.count==before+1&&f.link.lastOp==TLK_OP_QUERY&&f.link.lastResult==TLK_R_BLOCKED&&[f.link.note isEqual:TIOText(@"lock.note.blocked")]);
 f->g.blocked=NO;
 /* The glasses spent the token (refused session): SESSION, no retry. */
 [f.link query:f.cb];f->g.session.token^=1;before=(unsigned)f.wires.count;[f.link unlock:f.cb];assert(f.wires.count==before+1&&f.link.lastResult==TLK_R_SESSION&&[f.link.note isEqual:TIOText(@"lock.note.session")]);
 for(NSString *key in @[@"lock.note.refused",@"lock.note.blocked",@"lock.note.session",@"lock.note.motionRefused",@"lock.note.noReply",@"lock.note.unsupported",@"lock.note.connect"])assert(![TIOText(key) isEqual:key]);
}}

static void Matching(void){@autoreleasepool{
 Fixture *f=[Fixture new];f->g.mute=YES;f->g.flags=TLK_F_ENABLED;
 [f.link query:f.cb];assert(f.link.busy&&f.wires.count==1);
 TLKReply r=Answer(&f->g,f.wires[0],f.now);
 assert(TIOGlassesLockIsReply(Event(r,f.peer)));
 /* Another peer, request, client or op is owned (it is a TKA: record) but changes nothing. */
 assert([f.link consume:Event(r,@"other")]&&f.link.busy);
 TLKReply x=r;x.request++;assert([f.link consume:Event(x,f.peer)]&&f.link.busy);
 x=r;x.client++;assert([f.link consume:Event(x,f.peer)]&&f.link.busy);
 x=r;x.op=TLK_OP_UNLOCK;x.token=0;assert([f.link consume:Event(x,f.peer)]&&f.link.busy);
 /* A successful QUERY without a token is not a state. */
 x=r;x.token=0;assert([f.link consume:Event(x,f.peer)]&&!f.link.busy&&!f.link.known&&f.link.lastResult==TIOLockResultNoReply);
 [f.link query:f.cb];r=Answer(&f->g,f.wires.lastObject,f.now);
 /* A late reply (at or after the reply window) cancels instead of counting. */
 f.now+=TIOLockReplySeconds;assert([f.link consume:Event(r,f.peer)]&&!f.link.busy&&!f.link.known);
 [f.link query:f.cb];r=Answer(&f->g,f.wires.lastObject,f.now);assert([f.link consume:Event(r,f.peer)]&&f.link.known);
 /* Not TKA: records: other families, other businesses, junk. */
 assert(!TIOGlassesLockIsReply(@{})&&![f.link consume:@{}]);
 NSMutableDictionary *e=[Event(r,f.peer) mutableCopy];NSMutableDictionary *msg=[e[@"message"] mutableCopy];msg[@"businessId"]=@14;e[@"message"]=msg;assert(!TIOGlassesLockIsReply(e));
 msg[@"businessId"]=@15;msg[@"deviceId"]=@"";e[@"message"]=msg;assert(!TIOGlassesLockIsReply(e));
 uint8_t raw[32],wire[74];tlk_reply_encode(raw,&r);tlk_carrier(wire,raw,true);memcpy(wire+6,"TLA:",4);msg[@"deviceId"]=f.peer;msg[@"payload"]=[NSData dataWithBytes:wire length:74];e[@"message"]=msg;assert(!TIOGlassesLockIsReply(e));
 tlk_carrier(wire,raw,false);msg[@"payload"]=[NSData dataWithBytes:wire length:74];e[@"message"]=msg;assert(!TIOGlassesLockIsReply(e)); /* a TLK: command echoed back */
 /* The peer changes: the old state is not shown for the new glasses. */
 f.peer=@"glasses-other";assert(!f.link.known&&f.link.model.phase==TIOLockPhaseUnknown);
 /* No reply at all: the command ends as unknown after the window, and nothing is resent. */
 f.peer=@"glasses-13";[f.link query:f.cb];unsigned count=(unsigned)f.wires.count;
 NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+TIOLockReplySeconds+5;
 while(f.link.busy&&NSProcessInfo.processInfo.systemUptime<deadline)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(!f.link.busy&&f.link.lastResult==TIOLockResultNoReply&&f.wires.count==count&&[f.link.note isEqual:TIOText(@"lock.note.noReply")]);
 /* Background or an update running: nothing leaves the phone. */
 f->g.mute=NO;f.allowed=NO;[f.link query:f.cb];assert(f.wires.count==count&&f.link.lastResult==TIOLockResultNotSent&&[f.link.note isEqual:TIOText(@"lock.note.connect")]);
 /* Cancel while waiting: a reply that arrives later does nothing. */
 f.allowed=YES;f->g.mute=YES;[f.link query:f.cb];r=Answer(&f->g,f.wires.lastObject,f.now);[f.link cancel];assert(!f.link.busy);assert([f.link consume:Event(r,f.peer)]&&f.link.lastResult==TIOLockResultNoReply);
}}

static void Caps(void){@autoreleasepool{
 /* Only glasses that report TD_CAP_PIN_LOCK (bit 11) are ever sent a TLK: record. */
 assert(TD_CAP_PIN_LOCK==(1u<<11)&&TD_CAPS_TMG13==(TD_CAPS_TMG9|TD_CAP_PIN_LOCK));
 assert(TIOLockCapsSupported(TD_CAPS_TMG13)&&TIOLockCapsSupported(TD_CAP_PIN_LOCK));
 for(NSNumber *old in @[@0,@(TD_CAPS_ALL),@(TD_CAPS_TMG6),@(TD_CAPS_TMG8),@(TD_CAPS_TMG9)])assert(!TIOLockCapsSupported(old.unsignedIntValue));
 Fixture *f=[Fixture new];f.caps=TD_CAPS_TMG9;
 assert(!f.link.supported);[f.link query:f.cb];[f.link unlock:f.cb];[f.link setPin:@"1234" done:f.cb];[f.link motionOn:f.cb];
 assert(f.done==4&&!f.wires.count&&f.link.lastResult==TIOLockResultNotSent&&[f.link.note isEqual:TIOText(@"lock.note.unsupported")]);
 f.caps=TD_CAPS_TMG13;f.peer=@"";assert(!f.link.supported); /* no connected glasses */
 f.peer=@"glasses-13";assert(f.link.supported);[f.link query:f.cb];assert(f.wires.count==1&&f.link.known);
 /* The caps bit goes away (another firmware, a stale sample): the state stays readable, nothing more is sent. */
 f.caps=0;[f.link lockNow:f.cb];assert(f.wires.count==1&&f.link.lastResult==TIOLockResultNotSent);
}}

static void Motion(void){@autoreleasepool{
 /* Glasses without the motion hook (milestone 2): a fresh QUERY, then refused on the phone; MOTION_ON is never sent. */
 Fixture *f=[Fixture new];f->g.flags=TLK_F_ENABLED;
 [f.link motionOn:f.cb];assert(f.done==1&&f.wires.count==1&&f->g.last.op==TLK_OP_QUERY&&f.link.lastOp==TLK_OP_MOTION_ON&&f.link.lastResult==TLK_R_REFUSED);
 assert([f.link.note isEqual:TIOText(@"lock.note.motionRefused")]&&!f.link.model.motionSupported&&!f.link.model.motionOn&&f.link.model.phase==TIOLockPhaseUnlocked);
 /* The token of that QUERY is not left for anything else. */
 [f.link lockNow:f.cb];assert(f.wires.count==3);
 /* Glasses that report support but refuse (lock off, or a firmware that says no): the reply is refused, handled, not resent. */
 f->g.motionSupported=YES;f->g.refuseMotion=YES;unsigned n=(unsigned)f.wires.count;
 [f.link motionOn:f.cb];assert(f.wires.count==n+2&&f->g.last.op==TLK_OP_MOTION_ON&&f.link.lastResult==TLK_R_REFUSED&&[f.link.note isEqual:TIOText(@"lock.note.motionRefused")]&&!f.link.model.motionOn);
 f->g.refuseMotion=NO;[f.link motionOn:f.cb];assert(f.link.lastResult==TLK_R_OK&&f.link.model.motionOn&&f.link.model.motionSupported);

 /* The phone's switch and its early-drop counter (§7). */
 NSString *suite=@"turboio.test.lock-motion";NSUserDefaults *d=[[NSUserDefaults alloc]initWithSuiteName:suite];[d removePersistentDomainForName:suite];
 __block double now=100;TIOLockMotion *mo=[[TIOLockMotion alloc]initWithDefaults:d clock:^{return now;}];
 assert(!mo.wanted&&!mo.earlyDrops&&!mo.offAfterDrops);
 mo.wanted=YES;[mo linkDropped];assert(mo.earlyDrops==0); /* no MOTION_ON accepted yet: a drop does not count */
 [mo motionAccepted];now+=10;[mo linkDropped];assert(mo.earlyDrops==1&&mo.wanted);
 [mo motionAccepted];now+=TIOLockEarlyDropSeconds;[mo linkDropped];assert(mo.earlyDrops==0&&mo.wanted); /* a link that lasted 60 s starts over */
 [mo motionAccepted];now+=59;[mo linkDropped];[mo motionAccepted];now+=1;[mo linkDropped];assert(!mo.wanted&&mo.offAfterDrops&&mo.earlyDrops==0);
 mo.wanted=YES;assert(mo.wanted&&!mo.offAfterDrops&&!mo.earlyDrops);
 [mo motionAccepted];now+=5;[mo linkDropped];[mo motionAccepted];now+=TIOLockEarlyDropSeconds;[mo linkSurvived];assert(mo.earlyDrops==0);
 [mo motionAccepted];now+=1;[mo linkDropped];assert(mo.earlyDrops==1&&mo.wanted);
 mo.wanted=NO;assert(!mo.offAfterDrops&&!mo.earlyDrops);
 /* Stored on the phone, in its own suite: a second reader sees the same switch. */
 mo.wanted=YES;assert([[TIOLockMotion alloc]initWithDefaults:d clock:^{return now;}].wanted);
 [d removePersistentDomainForName:suite];
}}

static void Model(void){@autoreleasepool{
 TIOLockModel m=TIOLockModelFromReply(NULL);assert(m.phase==TIOLockPhaseUnknown&&!m.lockOn&&!m.showUnlock&&!m.showLockNow&&!TIOLockPhaseTextId(m.phase));
 /* The four preview fixtures: off, unlocked, locked, locked with wrong tries. */
 TLKReply r={.op=TLK_OP_QUERY,.fold_min=5,.idle_min=5};m=TIOLockModelFromReply(&r);
 assert(m.phase==TIOLockPhaseOff&&!m.lockOn&&!m.showUnlock&&!m.showLockNow&&!m.wrong&&m.foldMin==5&&m.idleMin==5&&[TIOLockPhaseTextId(m.phase) isEqual:@"lock.state.off"]);
 r.flags=TLK_F_ENABLED;r.fold_min=10;r.idle_min=30;m=TIOLockModelFromReply(&r);
 assert(m.phase==TIOLockPhaseUnlocked&&m.lockOn&&!m.showUnlock&&m.showLockNow&&m.foldMin==10&&m.idleMin==30&&[TIOLockPhaseTextId(m.phase) isEqual:@"lock.state.unlocked"]);
 r.flags=TLK_F_ENABLED|TLK_F_LOCKED;m=TIOLockModelFromReply(&r);assert(m.phase==TIOLockPhaseLocked&&m.showUnlock&&!m.showLockNow&&!m.wrong&&[TIOLockPhaseTextId(m.phase) isEqual:@"lock.state.locked"]);
 r.wrong=4;r.unacked=4;m=TIOLockModelFromReply(&r);assert(m.wrong==4&&m.phase==TIOLockPhaseLocked);
 /* Unlocked after wrong tries: the warning stays until it is dismissed on the phone, whatever the knob counter says. */
 r.flags=TLK_F_ENABLED;r.wrong=0;m=TIOLockModelFromReply(&r);assert(m.wrong==4&&m.phase==TIOLockPhaseUnlocked);
 /* Damaged record: fail closed, the phone can unlock and set a new PIN. */
 r=(TLKReply){.op=TLK_OP_QUERY,.flags=TLK_F_LOCKED|TLK_F_DAMAGED,.fold_min=5,.idle_min=5};m=TIOLockModelFromReply(&r);assert(m.damaged&&m.phase==TIOLockPhaseLocked&&m.showUnlock&&!m.lockOn);
 /* Out-of-range minutes from a bad record show the defaults. */
 r.fold_min=0;r.idle_min=241;m=TIOLockModelFromReply(&r);assert(m.foldMin==5&&m.idleMin==5);
 r.flags=TLK_F_ENABLED|TLK_F_MOTION|TLK_F_MOTION_SUPPORTED;m=TIOLockModelFromReply(&r);assert(m.motionOn&&m.motionSupported);
 for(NSString *key in @[@"lock.state.off",@"lock.state.unlocked",@"lock.state.locked",@"hub.row.glassesLock"]){
  TIOSetUILanguageOverride(@"en");NSString *en=TIOText(key);TIOSetUILanguageOverride(@"zh");NSString *zh=TIOText(key);
  assert(![en isEqual:key]&&![zh isEqual:key]&&![en isEqual:zh]);
 }
 TIOSetUILanguageOverride(@"auto");
}}

int main(void){@autoreleasepool{
 Codec();
 Exchange();
 Matching();
 Caps();
 Motion();
 Model();
 puts("GlassesLock phone PASS: shared codec records, query-then-change with a fresh token, exact reply matching, no resend, caps bit 11 gate, MOTION_ON refused, early-drop counter, state to page model");
}return 0;}
