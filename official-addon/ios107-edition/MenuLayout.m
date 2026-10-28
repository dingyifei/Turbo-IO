#import "MenuLayout.h"
#import "TIOLanguage.h"
#include "menu_config.h"
static uint32_t U32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static NSData *Reply(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"deviceId"]isKindOfClass:NSString.class]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *wire=m[@"payload"];uint8_t p[32];
 if(!tml_uncarrier(wire.bytes,wire.length,p,true)||memcmp(p,"TMA2",4)||p[4]!=1||p[5]>1||(p[6]!=2&&p[6]!=3)||p[7]>TML_UNAVAILABLE||!U32(p+8)||!U32(p+20)||p[24]!=28||p[25]!=2||p[26]!=220||p[27]||U32(p+28)!=tml_crc(p,28))return nil;
 return [NSData dataWithBytes:p length:32];
}
BOOL TIOMenuLayoutIsReply(NSDictionary *e){return Reply(e)!=nil||TIOTileLayoutIsReply(e);}
@implementation TIOMenuLayoutLink {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);double(^_clock)(void);BOOL(^_send)(NSData *);
 NSString *_peer,*_note;uint32_t _token,_generation,_client,_request;NSUInteger _rows,_op,_target,_epoch;
 double _confirmedAt;void(^_done)(void);
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_send=[send copy];_note=TIOText(@"读取眼镜布局后可切换；需 TMG4 固件");}return self;
}
- (BOOL)busy{return _done!=nil;}
- (BOOL)ready{return _token&&[_peer isEqual:_peerNow()]&&_allowed()&&_clock()-_confirmedAt<110&&_clock()>=_confirmedAt;}
- (NSUInteger)rows{return [_peer isEqual:_peerNow()]?_rows:0;}
- (NSString *)note{return _note;}
- (void)finish:(NSString *)note{_note=note;void(^d)(void)=_done;_done=nil;_request=0;_epoch++;if(d)d();}
- (void)cancel{_token=0;_rows=0;[self finish:TIOText(@"操作已取消；重新读取眼镜布局，不补发旧设置")];}
- (void)send:(TMLCommand)q done:(void(^)(void))done{
 NSAssert(NSThread.isMainThread,@"main only");
 if(self.busy){if(done)done();return;}
 if(!_allowed()||!_peer.length||![_peer isEqual:_peerNow()]){_token=0;_note=TIOText(@"请连接眼镜、保持 App 前台并结束升级保护");if(done)done();return;}
 uint8_t raw[32],wire[74];tml_encode(raw,&q);TMLCommand verify;
 if(!tml_decode(raw,32,&verify)){_note=TIOText(@"布局请求校验失败");if(done)done();return;}
 tml_carrier(wire,raw,false);_request=q.request;_op=q.op;_target=q.rows;_done=done?[done copy]:[^(void){} copy];NSUInteger epoch=++_epoch;
 _note=q.op==TML_QUERY?TIOText(@"正在读取眼镜布局…"):TIOText(@"等待眼镜保存布局…");
 if(!_send([NSData dataWithBytes:wire length:74])){_token=0;[self finish:TIOText(@"发送未确认，请重新读取；没有自动重试")];return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_epoch==epoch&&self.busy){self->_token=0;self->_rows=0;[self finish:TIOText(@"眼镜未回执；需 TMG4 固件。结果未知，请重新读取，不自动重试")];}});
}
- (void)query:(void(^)(void))done{
 if(self.busy){if(done)done();return;}_peer=[_peerNow() copy];_token=0;_rows=0;_client=arc4random_uniform(UINT32_MAX-1)+1;
 TMLCommand q={.op=TML_QUERY,.request=arc4random_uniform(UINT32_MAX-1)+1,.client=_client};[self send:q done:done];
}
- (void)choose:(NSUInteger)rows done:(void(^)(void))done{
 if(rows!=2&&rows!=3){if(done)done();return;}
 if(self.busy){if(done)done();return;}
 if(!self.ready){__weak typeof(self) w=self;[self query:^{typeof(self) s=w;if(s.ready)[s choose:rows done:done];else if(done)done();}];return;}
 TMLCommand q={.op=TML_SET,.rows=(uint8_t)rows,.request=arc4random_uniform(UINT32_MAX-1)+1,.token=_token,.generation=_generation,.client=_client};
 _token=0;[self send:q done:done];
}
- (BOOL)consume:(NSDictionary *)e{
 NSData *d=Reply(e);if(!d)return NO;const uint8_t *p=d.bytes;
 if(!self.busy||![_peer isEqual:_peerNow()]||![e[@"message"][@"deviceId"]isEqual:_peer]||U32(p+8)!=_request||U32(p+20)!=_client||p[5]!=_op)return YES;
 if(!_allowed()){[self cancel];return YES;}
 _token=0;_rows=0;
 if(p[7]!=TML_OK){[self finish:p[7]==TML_STORAGE?TIOText(@"眼镜保存/读取失败，未确认修改；请重新读取"):p[7]==TML_SESSION?TIOText(@"设置凭证已过期，请重新读取"):TIOText(@"眼镜当前不允许修改布局（升级、折叠或非支持页面）")];return YES;}
 if((_op==TML_QUERY&&!U32(p+12))||(_op==TML_SET&&(U32(p+12)||p[6]!=_target))){[self finish:TIOText(@"布局回执不一致，请重新读取")];return YES;}
 _rows=p[6];_generation=U32(p+16);_confirmedAt=_clock();if(_op==TML_QUERY)_token=U32(p+12);
 [self finish:[NSString stringWithFormat:TIOText(@"眼镜已确认：%@排 · 每页%@项%@"),@(_rows),@(_rows*3),_op==TML_SET?TIOText(@" · 已保存"):@""]];return YES;
}
@end

#include "tile_config.h"
static BOOL TileReply(NSDictionary *e,TTReply *reply){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"deviceId"]isKindOfClass:NSString.class]||![m[@"deviceId"]length]||![m[@"payload"]isKindOfClass:NSData.class])return NO;
 NSData *wire=m[@"payload"];uint8_t raw[32];TTReply r;if(!tt_uncarrier(wire.bytes,wire.length,raw,true)||!tt_reply_decode(raw,32,&r))return NO;if(reply)*reply=r;return YES;
}
BOOL TIOTileLayoutIsReply(NSDictionary *e){return TileReply(e,NULL);}
@implementation TIOTileLayoutLink {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);double(^_clock)(void);BOOL(^_send)(NSData *);
 NSString *_peer,*_note;NSArray<NSNumber *> *_order;NSUInteger _hide,_epoch;uint32_t _request,_client,_token,_generation,_expectedGeneration;uint16_t _rank,_targetRank,_targetHide;uint8_t _op;
 double _confirmedAt,_sentAt;void(^_done)(void);
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_send=[send copy];_note=TIOText(@"tmg4.tiles.readFirst");}return self;
}
- (BOOL)busy{return _done!=nil;}
- (BOOL)ready{double now=_clock();return _token&&[_peer isEqual:_peerNow()]&&_allowed()&&now>=_confirmedAt&&now-_confirmedAt<110;}
- (NSArray<NSNumber *> *)order{return [_peer isEqual:_peerNow()]?_order:nil;}
- (NSUInteger)hide{return [_peer isEqual:_peerNow()]?_hide:0;}
- (NSString *)note{return _note;}
- (void)finishTile:(NSString *)note{_note=note;_request=0;_epoch++;void(^done)(void)=_done;_done=nil;if(done)done();}
- (void)cancel{_token=0;_order=nil;[self finishTile:TIOText(@"tmg4.tiles.canceled")];}
- (void)sendTile:(TTCommand)q done:(void(^)(void))done{
 NSAssert(NSThread.isMainThread,@"main only");if(self.busy){if(done)done();return;}
 if(!_allowed()||!_peer.length||![_peer isEqual:_peerNow()]){_token=0;_note=TIOText(@"tmg4.tiles.connect");if(done)done();return;}
 uint8_t raw[32],wire[74];TTCommand verify;tt_encode(raw,&q);if(!tt_decode(raw,32,&verify)){_note=TIOText(@"tmg4.tiles.invalid");if(done)done();return;}tt_carrier(wire,raw,false);
 _request=q.request;_client=q.client;_op=q.op;_targetRank=q.rank;_targetHide=q.hide;_sentAt=_clock();_done=done?[done copy]:[^(void){} copy];NSUInteger epoch=++_epoch;
 _note=TIOText(q.op==TT_QUERY?@"tmg4.tiles.reading":@"tmg4.tiles.saving");
 BOOL sent=_send([NSData dataWithBytes:wire length:74]);if(_epoch!=epoch||!self.busy)return;
 if(!sent){_token=0;[self finishTile:TIOText(@"tmg4.tiles.uncertain")];return;}
 __weak typeof(self) weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{typeof(self) s=weak;if(s&&s->_epoch==epoch&&s.busy){s->_token=0;[s finishTile:TIOText(@"tmg4.tiles.uncertain")];}});
}
- (void)query:(void(^)(void))done{
 if(self.busy){if(done)done();return;}_peer=[_peerNow() copy];_token=0;_client=arc4random_uniform(UINT32_MAX-1)+1;
 TTCommand q={.op=TT_QUERY,.request=arc4random_uniform(UINT32_MAX-1)+1,.client=_client};[self sendTile:q done:done];
}
- (void)saveOrder:(NSArray<NSNumber *> *)order hide:(NSUInteger)hide done:(void(^)(void))done{
 if(self.busy){if(done)done();return;}
 if(!self.ready){_token=0;_note=TIOText(@"tmg4.tiles.expired");if(done)done();return;}
 TTConfig c;tt_default(&c);if(![order isKindOfClass:NSArray.class]||order.count!=13||hide>UINT16_MAX){_note=TIOText(@"tmg4.tiles.invalid");if(done)done();return;}
 for(NSUInteger i=0;i<13;i++){id value=order[i];if(![value isKindOfClass:NSNumber.class]||[value doubleValue]!=[value unsignedIntegerValue]||[value unsignedIntegerValue]>=13){_note=TIOText(@"tmg4.tiles.invalid");if(done)done();return;}c.order[i]=[value unsignedCharValue];}c.hide=(uint16_t)hide;uint16_t rank;
 if(!tt_rank(&c,&rank)){_note=TIOText(@"tmg4.tiles.invalid");if(done)done();return;}
 _expectedGeneration=(_generation&&rank==_rank&&hide==_hide)?_generation:_generation+1;if(!_expectedGeneration)_expectedGeneration=1;
 TTCommand q={.op=TT_SET,.request=arc4random_uniform(UINT32_MAX-1)+1,.client=_client,.token=_token,.generation=_generation,.rank=rank,.hide=(uint16_t)hide};_token=0;[self sendTile:q done:done];
}
- (BOOL)consume:(NSDictionary *)event{
 TTReply r;if(!TileReply(event,&r))return NO;
 if(!self.busy||![_peer isEqual:_peerNow()]||![event[@"message"][@"deviceId"]isEqual:_peer]||r.request!=_request||r.client!=_client||r.op!=_op)return YES;
 double now=_clock();if(!_allowed()||now<_sentAt||now-_sentAt>=3){[self cancel];return YES;}_token=0;
 if(r.result!=TT_OK){[self finishTile:TIOText(r.result==TT_STORAGE?@"tmg4.tiles.storage":r.result==TT_SESSION?@"tmg4.tiles.expired":r.result==TT_UNAVAILABLE?@"tmg4.tiles.unavailable":@"tmg4.tiles.blocked")];return YES;}
 if(_op==TT_SET&&(r.rank!=_targetRank||r.hide!=_targetHide||r.generation!=_expectedGeneration)){[self finishTile:TIOText(@"tmg4.tiles.uncertain")];return YES;}
 TTConfig c;if(!tt_unrank(r.rank,r.hide,&c)){[self finishTile:TIOText(@"tmg4.tiles.invalid")];return YES;}
 NSMutableArray *order=[NSMutableArray arrayWithCapacity:13];for(unsigned i=0;i<13;i++)[order addObject:@(c.order[i])];_order=[order copy];_rank=r.rank;_hide=r.hide;_generation=r.generation;_confirmedAt=now;if(_op==TT_QUERY)_token=r.token;
 [self finishTile:TIOText(_op==TT_SET?@"tmg4.tiles.saved":@"tmg4.tiles.loaded")];return YES;
}
@end
