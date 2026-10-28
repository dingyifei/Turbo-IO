#import "LanguageFlag.h"
#include "lang_flag.h"
static BOOL Reply(NSDictionary *e,TLGReply *out){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"deviceId"]isKindOfClass:NSString.class]||![m[@"deviceId"]length]||![m[@"payload"]isKindOfClass:NSData.class])return NO;
 NSData *wire=m[@"payload"];uint8_t raw[32];TLGReply reply;
 if(!tlg_uncarrier(wire.bytes,wire.length,raw,true)||!tlg_reply_decode(raw,32,&reply))return NO;
 if(out)*out=reply;return YES;
}
BOOL TIOLanguageFlagIsReply(NSDictionary *e){return Reply(e,NULL);}
@implementation TIOLanguageFlagLink {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);double(^_clock)(void);BOOL(^_send)(NSData *);
 NSString *_peer,*_state;uint32_t _sequence,_request;NSUInteger _epoch;
 uint8_t _target,_lang,_source,_pendingLang,_ackLang;BOOL _pending,_hasAck,_ackUsable,_unsupported;
 double _sentAt,_ackAt;
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_send=[send copy];_state=@"idle";_sequence=arc4random();}return self;
}
- (void)finish:(NSString *)state{_request=0;_pending=NO;_epoch++;_state=state;}
- (void)refresh{
 NSAssert(NSThread.isMainThread,@"main only");
 NSString *peer=_peerNow();if(!peer.length)peer=nil;
 if(!(_peer==peer||[_peer isEqual:peer])){[self finish:@"idle"];_peer=[peer copy];_unsupported=NO;_hasAck=NO;_ackUsable=NO;_lang=TLG_EN;_source=TLG_SOURCE_DEFAULT;}
 if(_request&&!_allowed()){[self finish:@"idle"];return;}
 if(_request&&_clock()-_sentAt>=3){_unsupported=YES;[self finish:@"unsupported"];}
}
- (BOOL)busy{[self refresh];return _request!=0;}
- (NSDictionary *)status{
 [self refresh];double age=_hasAck?_clock()-_ackAt:-1;
 return @{@"state":_state,@"lang":@(_lang),@"source":@(_source),@"lastAckAge":@(age>=0?age:-1)};
}
- (void)cancel{[self refresh];[self finish:_unsupported?@"unsupported":@"idle"];}
- (void)pushLanguage:(uint8_t)lang{
 [self refresh];if(lang>TLG_ZH||!_allowed()||!_peer.length||_unsupported)return;
 if(_request){_pending=YES;_pendingLang=lang;return;}
 double now=_clock();if(_ackUsable&&lang==_ackLang&&now>=_ackAt&&now-_ackAt<30)return;
 if(++_sequence==0)++_sequence;
 TLGCommand q={_sequence,TLG_SET,lang};uint8_t raw[32],wire[74];tlg_encode(raw,&q);tlg_carrier(wire,raw,false);
 _ackUsable=NO;_request=q.request;_target=lang;_lang=lang;_sentAt=now;_state=@"sending";NSUInteger epoch=++_epoch;
 // Arm the transaction before calling the transport: a test or host can reply synchronously.
 BOOL sent=_send([NSData dataWithBytes:wire length:74]);
 if(_epoch!=epoch||!_request)return;
 if(!sent){[self finish:@"failed"];return;}
 __weak typeof(self) weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  typeof(self) strong=weak;if(strong&&strong->_epoch==epoch)[strong refresh];
 });
}
- (void)syncLanguage:(uint8_t)lang{[self refresh];if(self.busy)return;_unsupported=NO;_ackUsable=NO;[self pushLanguage:lang];}
- (BOOL)consume:(NSDictionary *)e{
 TLGReply r;if(!Reply(e,&r))return NO;
 [self refresh];if(!_request||![e[@"message"][@"deviceId"]isEqual:_peer]||r.request!=_request||r.op!=TLG_SET)return YES;
 _lang=r.lang;_source=r.source;
 if(r.result!=TLG_OK){[self finish:r.result==TLG_BLOCKED?@"blocked":r.result==TLG_STORAGE?@"storage":r.result==TLG_UNAVAILABLE?@"unavailable":@"failed"];return YES;}
 if(r.lang!=_target||r.source!=TLG_SOURCE_PERSISTED){[self finish:@"failed"];return YES;}
 BOOL pending=_pending;uint8_t latest=_pendingLang;
 _hasAck=YES;_ackUsable=YES;_ackAt=_clock();_ackLang=r.lang;[self finish:@"acked"];
 if(pending&&latest!=r.lang)[self pushLanguage:latest];return YES;
}
@end
