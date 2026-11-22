#import "GlassesLock.h"
#import "TIOLanguage.h"
#include "diagnostics.h"

const double TIOLockReplySeconds=3,TIOLockTokenUseSeconds=110,TIOLockEarlyDropSeconds=60;

TIOLockModel TIOLockModelFromReply(const TLKReply *r){
 TIOLockModel m={0};if(!r)return m;
 BOOL enabled=(r->flags&TLK_F_ENABLED)!=0,locked=(r->flags&TLK_F_LOCKED)!=0;
 m.phase=locked?TIOLockPhaseLocked:enabled?TIOLockPhaseUnlocked:TIOLockPhaseOff;
 m.lockOn=enabled;m.damaged=(r->flags&TLK_F_DAMAGED)!=0;
 m.showUnlock=m.phase==TIOLockPhaseLocked;m.showLockNow=m.phase==TIOLockPhaseUnlocked;
 m.wrong=r->unacked;
 m.foldMin=r->fold_min>=1&&r->fold_min<=240?r->fold_min:5;m.idleMin=r->idle_min>=1&&r->idle_min<=240?r->idle_min:5;
 m.motionSupported=(r->flags&TLK_F_MOTION_SUPPORTED)!=0;m.motionOn=(r->flags&TLK_F_MOTION)!=0;
 return m;
}
NSString *TIOLockPhaseTextId(TIOLockPhase phase){
 switch(phase){case TIOLockPhaseOff:return @"lock.state.off";case TIOLockPhaseUnlocked:return @"lock.state.unlocked";case TIOLockPhaseLocked:return @"lock.state.locked";default:return nil;}
}
BOOL TIOLockCapsSupported(uint32_t caps){return (caps&TD_CAP_PIN_LOCK)!=0;}
BOOL TIOLockParsePin(NSString *text,uint8_t pin[4]){
 if(![text isKindOfClass:NSString.class]||text.length!=4)return NO;
 uint8_t d[4];for(NSUInteger i=0;i<4;i++){unichar c=[text characterAtIndex:i];if(c<'0'||c>'9')return NO;d[i]=(uint8_t)(c-'0');}
 if(pin)memcpy(pin,d,4);return YES;
}
static BOOL Reply(NSDictionary *e,TLKReply *out){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"deviceId"]isKindOfClass:NSString.class]||![m[@"deviceId"]length]||![m[@"payload"]isKindOfClass:NSData.class])return NO;
 NSData *wire=m[@"payload"];uint8_t raw[32];TLKReply r;if(!tlk_uncarrier(wire.bytes,wire.length,raw,true)||!tlk_reply_decode(raw,32,&r))return NO;
 if(out)*out=r;return YES;
}
BOOL TIOGlassesLockIsReply(NSDictionary *e){return Reply(e,NULL);}
static uint32_t Nonzero(void){return arc4random_uniform(UINT32_MAX-1)+1;}
static NSString *ResultNote(unsigned op,unsigned result){
 switch(result){
  case TLK_R_BLOCKED:return TIOText(@"lock.note.blocked");
  case TLK_R_INVALID:return TIOText(@"lock.note.invalid");
  case TLK_R_STORAGE:return TIOText(@"lock.note.storage");
  case TLK_R_UNAVAILABLE:return TIOText(@"lock.note.unavailable");
  case TLK_R_SESSION:return TIOText(@"lock.note.session");
  case TLK_R_REFUSED:return TIOText(op==TLK_OP_MOTION_ON?@"lock.note.motionRefused":@"lock.note.refused");
  default:return nil;
 }
}

@implementation TIOGlassesLockLink {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);double(^_clock)(void);uint32_t(^_caps)(void);BOOL(^_send)(NSData *);
 NSString *_peer,*_note;BOOL _known;TLKReply _state;uint32_t _token,_client,_request;uint8_t _op;unsigned _lastOp,_lastResult;
 double _tokenAt,_sentAt;NSUInteger _epoch;void(^_done)(void);
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock caps:(uint32_t(^)(void))caps send:(BOOL(^)(NSData *))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_caps=[caps copy];_send=[send copy];_lastResult=TIOLockResultNotSent;}return self;
}
- (BOOL)busy{return _done!=nil;}
- (void)remember:(NSString *)peer on:(BOOL)on{
 if(!_seen||!peer.length)return;NSArray *now=[_seen arrayForKey:@"lockPeers"]?:@[];if([now containsObject:peer]==on)return;
 NSMutableArray *next=[now mutableCopy];if(on)[next addObject:peer];else [next removeObject:peer];[_seen setObject:next forKey:@"lockPeers"];
}
- (BOOL)connected{return [_peerNow() length]>0;}
- (BOOL)supported{
 NSString *peer=_peerNow();if(!peer.length||!_caps)return NO;uint32_t caps=_caps();
 if(TIOLockCapsSupported(caps)){[self remember:peer on:YES];return YES;}
 if(caps){[self remember:peer on:NO];return NO;}   /* a fresh sample without the bit: other firmware */
 return [[_seen arrayForKey:@"lockPeers"]containsObject:peer];   /* no sample (stale, refused while locked) */
}
- (BOOL)known{return _known&&[_peer isEqual:_peerNow()];}
- (TLKReply)state{return self.known?_state:(TLKReply){0};}
- (TIOLockModel)model{TLKReply r=_state;return TIOLockModelFromReply(self.known?&r:NULL);}
- (NSString *)note{return _note;}
- (unsigned)lastOp{return _lastOp;}
- (unsigned)lastResult{return _lastResult;}
- (BOOL)ready{double now=_clock();return _token&&[_peer isEqual:_peerNow()]&&_allowed()&&now>=_tokenAt&&now-_tokenAt<TIOLockTokenUseSeconds;}
- (void)finish:(NSString *)note result:(unsigned)result{
 _note=note;_lastOp=_op;_lastResult=result;_request=0;_epoch++;void(^done)(void)=_done;_done=nil;if(done)done();
}
- (void)refuse:(NSString *)note op:(unsigned)op done:(void(^)(void))done{_note=note;_lastOp=op;_lastResult=TIOLockResultNotSent;if(done)done();}
- (void)cancel{_token=0;if(self.busy)[self finish:TIOText(@"lock.note.canceled") result:TIOLockResultNoReply];}
- (void)send:(TLKCommand)q done:(void(^)(void))done{
 NSAssert(NSThread.isMainThread,@"main only");
 if(self.busy){if(done)done();return;}
 if(!_allowed()||!_peer.length||![_peer isEqual:_peerNow()]){_token=0;[self refuse:TIOText(@"lock.note.connect") op:q.op done:done];return;}
 if(!self.supported){_token=0;[self refuse:TIOText(@"lock.note.unsupported") op:q.op done:done];return;}
 /* The one place a TLK: record is encoded, and only a record the glasses' own decoder accepts leaves the phone. */
 uint8_t raw[32],wire[74];TLKCommand verify;tlk_encode(raw,&q);
 if(!tlk_decode(raw,32,&verify)){[self refuse:TIOText(@"lock.note.invalid") op:q.op done:done];return;}
 tlk_carrier(wire,raw,false);
 _request=q.request;_client=q.client;_op=q.op;_sentAt=_clock();_done=done?[done copy]:[^{} copy];NSUInteger epoch=++_epoch;
 _note=TIOText(q.op==TLK_OP_QUERY?@"lock.note.reading":@"lock.note.sending");
 BOOL sent=_send([NSData dataWithBytes:wire length:74]);if(_epoch!=epoch||!self.busy)return;
 if(!sent){_token=0;[self finish:TIOText(@"lock.note.noReply") result:TIOLockResultNotSent];return;}
 __weak typeof(self) weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(TIOLockReplySeconds*NSEC_PER_SEC)),dispatch_get_main_queue(),^{typeof(self) s=weak;if(s&&s->_epoch==epoch&&s.busy){s->_token=0;[s finish:TIOText(@"lock.note.noReply") result:TIOLockResultNoReply];}});
}
- (void)query:(void(^)(void))done{
 if(self.busy){if(done)done();return;}
 NSString *peer=[_peerNow() copy];if(![peer isEqual:_peer])_known=NO;_peer=peer;_token=0;_client=Nonzero();
 [self send:(TLKCommand){.op=TLK_OP_QUERY,.request=Nonzero(),.client=_client} done:done];
}
- (void)perform:(TLKCommand)q done:(void(^)(void))done{
 if(self.busy){if(done)done();return;}
 if(!self.supported){[self refuse:TIOText(@"lock.note.unsupported") op:q.op done:done];return;}
 if(!self.ready){__weak typeof(self) weak=self;[self query:^{typeof(self) s=weak;if(s.ready)[s perform:q done:done];else if(done)done();}];return;}
 q.request=Nonzero();q.client=_client;q.token=_token;_token=0;[self send:q done:done];
}
- (void)unlock:(void(^)(void))done{[self perform:(TLKCommand){.op=TLK_OP_UNLOCK} done:done];}
- (void)lockNow:(void(^)(void))done{[self perform:(TLKCommand){.op=TLK_OP_LOCK_NOW} done:done];}
- (void)disable:(void(^)(void))done{[self perform:(TLKCommand){.op=TLK_OP_DISABLE} done:done];}
- (void)acknowledgeFailures:(void(^)(void))done{[self perform:(TLKCommand){.op=TLK_OP_ACK_FAILURES} done:done];}
- (void)setPin:(NSString *)digits done:(void(^)(void))done{
 TLKCommand q={.op=TLK_OP_SET_PIN};if(!TIOLockParsePin(digits,q.pin)){[self refuse:TIOText(@"lock.pin.mismatch") op:TLK_OP_SET_PIN done:done];return;}
 [self perform:q done:done];
}
- (void)setFold:(NSUInteger)fold idle:(NSUInteger)idle done:(void(^)(void))done{
 if(fold<1||fold>240||idle<1||idle>240){[self refuse:TIOText(@"lock.note.invalid") op:TLK_OP_SET_TIME done:done];return;}
 [self perform:(TLKCommand){.op=TLK_OP_SET_TIME,.fold_min=(uint8_t)fold,.idle_min=(uint8_t)idle} done:done];
}
- (void)motionOn:(void(^)(void))done{
 if(self.busy){if(done)done();return;}
 if(!self.supported){[self refuse:TIOText(@"lock.note.unsupported") op:TLK_OP_MOTION_ON done:done];return;}
 if(!self.ready){__weak typeof(self) weak=self;[self query:^{typeof(self) s=weak;if(s.ready)[s motionOn:done];else if(done)done();}];return;}
 /* The firmware answers "refused" until it carries the motion hook (milestone 3); a fresh QUERY that does not report
  * "motion supported" ends here, as refused, with nothing more sent. */
 if(!(_state.flags&TLK_F_MOTION_SUPPORTED)){_token=0;_note=TIOText(@"lock.note.motionRefused");_lastOp=TLK_OP_MOTION_ON;_lastResult=TLK_R_REFUSED;if(done)done();return;}
 [self perform:(TLKCommand){.op=TLK_OP_MOTION_ON} done:done];
}
- (BOOL)consume:(NSDictionary *)event{
 TLKReply r;if(!Reply(event,&r))return NO;
 if(!self.busy||![_peer isEqual:_peerNow()]||![event[@"message"][@"deviceId"]isEqual:_peer]||r.request!=_request||r.client!=_client||r.op!=_op)return YES;
 double now=_clock();if(!_allowed()||now<_sentAt||now-_sentAt>=TIOLockReplySeconds){[self cancel];return YES;}
 _token=0;
 /* A QUERY that succeeded carries the token; nothing else ever does. */
 if((r.op==TLK_OP_QUERY&&r.result==TLK_R_OK&&!r.token)||(r.op!=TLK_OP_QUERY&&r.token)){[self finish:TIOText(@"lock.note.noReply") result:TIOLockResultNoReply];return YES;}
 /* Every reply carries the whole state, whatever the result. */
 _state=r;_known=YES;[self remember:_peer on:YES];
 if(r.op==TLK_OP_QUERY&&r.result==TLK_R_OK){_token=r.token;_tokenAt=now;}
 [self finish:ResultNote(r.op,r.result) result:r.result];return YES;
}
@end

@implementation TIOLockMotion {NSUserDefaults *_defaults;double(^_clock)(void);double _acceptedAt;}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults clock:(double(^)(void))clock{if((self=[super init])){_defaults=defaults;_clock=[clock copy];}return self;}
- (BOOL)wanted{return [_defaults boolForKey:@"stayUnlockedWorn"];}
- (void)setWanted:(BOOL)wanted{[_defaults setBool:wanted forKey:@"stayUnlockedWorn"];[_defaults setInteger:0 forKey:@"earlyDrops"];[_defaults setBool:NO forKey:@"offAfterDrops"];_acceptedAt=0;}
- (NSUInteger)earlyDrops{return (NSUInteger)MAX(0,[_defaults integerForKey:@"earlyDrops"]);}
- (BOOL)offAfterDrops{return [_defaults boolForKey:@"offAfterDrops"];}
- (void)motionAccepted{[self linkSurvived];_acceptedAt=_clock();}
- (void)linkSurvived{if(_acceptedAt>0&&_clock()-_acceptedAt>=TIOLockEarlyDropSeconds){[_defaults setInteger:0 forKey:@"earlyDrops"];_acceptedAt=0;}}
- (void)linkDropped{
 if(_acceptedAt<=0)return;
 double now=_clock();NSUInteger drops=now>=_acceptedAt&&now-_acceptedAt<TIOLockEarlyDropSeconds?self.earlyDrops+1:0;_acceptedAt=0;
 [_defaults setInteger:(NSInteger)drops forKey:@"earlyDrops"];
 if(drops>=2&&self.wanted){[_defaults setBool:NO forKey:@"stayUnlockedWorn"];[_defaults setBool:YES forKey:@"offAfterDrops"];[_defaults setInteger:0 forKey:@"earlyDrops"];}
}
@end
