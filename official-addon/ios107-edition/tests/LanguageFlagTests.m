#import <Foundation/Foundation.h>
#import "LanguageFlag.h"
#include "lang_flag.h"
#include <assert.h>
#include <string.h>
static unsigned Checks;
#define CHECK(x) do { Checks++; if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);abort();} } while(0)
static NSString *Hex(const uint8_t *p,size_t n){NSMutableString *s=[NSMutableString new];for(size_t i=0;i<n;i++)[s appendFormat:@"%02x",p[i]];return s;}
static void CRC(uint8_t p[32]){uint32_t c=tlg_crc(p,28);for(int i=0;i<4;i++)p[28+i]=(uint8_t)(c>>(8*i));}
static void Codec(void){
 const char *vectors[]={"544c4731010100000403020100000000000000000000000000000000ada4d3d5","544c47310101010004030201000000000000000000000000000000006dc0fbc2","544c4731010000000d0c0b0a00000000000000000000000000000000b4390ab8"};
 TLGCommand qs[]={{0x01020304,TLG_SET,TLG_EN},{0x01020304,TLG_SET,TLG_ZH},{0x0a0b0c0d,TLG_QUERY,TLG_EN}};
 CHECK(tlg_crc((const uint8_t *)"123456789",9)==0xcbf43926u);
 for(int i=0;i<3;i++){
  uint8_t raw[32],wire[75],back[32];TLGCommand q={0};tlg_encode(raw,&qs[i]);
  CHECK([Hex(raw,32) isEqual:@(vectors[i])]);CHECK(tlg_decode(raw,32,&q));CHECK(q.request==qs[i].request&&q.op==qs[i].op&&q.lang==qs[i].lang);
  memset(wire,0xcc,sizeof wire);CHECK(tlg_carrier(wire,raw,false)==74);CHECK(wire[74]==0xcc);CHECK([Hex(wire,10) isEqual:@"0801107f1a44544c473a"]);CHECK(tlg_uncarrier(wire,74,back,false));CHECK(!memcmp(raw,back,32));
  CHECK(!tlg_uncarrier(wire,73,back,false));CHECK(!tlg_uncarrier(wire,75,back,false));CHECK(!tlg_uncarrier(wire,74,back,true));
  wire[0]^=1;CHECK(!tlg_uncarrier(wire,74,back,false));wire[0]^=1;
  wire[7]='X';CHECK(!tlg_uncarrier(wire,74,back,false));wire[7]='L';
  wire[10]='A';CHECK(!tlg_uncarrier(wire,74,back,false));wire[10]='g';CHECK(!tlg_uncarrier(wire,74,back,false));
  CHECK(!tlg_decode(raw,31,&q));CHECK(!tlg_decode(raw,33,&q));CHECK(!tlg_decode(NULL,32,&q));CHECK(!tlg_decode(raw,32,NULL));
  uint8_t bad[32];memcpy(bad,raw,32);bad[31]^=1;CHECK(!tlg_decode(bad,32,&q));
  const int indexes[]={0,4,5,6,7,8,12,27};const uint8_t values[]={0,2,2,2,1,0,1,1};
  for(int j=0;j<8;j++){memcpy(bad,raw,32);bad[indexes[j]]=values[j];if(indexes[j]==8)memset(bad+8,0,4);CRC(bad);CHECK(!tlg_decode(bad,32,&q));}
  memcpy(bad,raw,32);bad[5]=TLG_QUERY;bad[6]=TLG_ZH;CRC(bad);CHECK(!tlg_decode(bad,32,&q));
 }
 TLGReply r={0x01020304,TLG_SET,TLG_ZH,TLG_OK,TLG_SOURCE_PHONE},got={0};uint8_t raw[32],wire[74],back[32];tlg_reply_encode(raw,&r);
 CHECK([Hex(raw,32) isEqual:@"544c41310101010004030201010000000000000000000000000000004d8c4d53"]);CHECK(tlg_reply_decode(raw,32,&got));CHECK(got.request==r.request&&got.op==r.op&&got.lang==r.lang&&got.result==r.result&&got.source==r.source);
 CHECK(tlg_carrier(wire,raw,true)==74);CHECK([Hex(wire,10) isEqual:@"0801107f1a44544c413a"]);CHECK(tlg_uncarrier(wire,74,back,true));CHECK(!memcmp(raw,back,32));CHECK(!tlg_uncarrier(wire,74,back,false));
 const int indexes[]={0,4,5,6,7,8,12,13,27};const uint8_t values[]={0,2,2,2,3,0,3,1,1};
 for(int j=0;j<9;j++){uint8_t bad[32];memcpy(bad,raw,32);bad[indexes[j]]=values[j];if(indexes[j]==8)memset(bad+8,0,4);CRC(bad);CHECK(!tlg_reply_decode(bad,32,&got));}
 raw[31]^=1;CHECK(!tlg_reply_decode(raw,32,&got));raw[31]^=1;
 CHECK(!tlg_reply_decode(raw,31,&got));CHECK(!tlg_reply_decode(raw,33,&got));CHECK(!tlg_reply_decode(NULL,32,&got));CHECK(!tlg_reply_decode(raw,32,NULL));
 // A QUERY reply reports the actual current language, including zh.
 r.op=TLG_QUERY;tlg_reply_encode(raw,&r);CHECK(tlg_reply_decode(raw,32,&got));CHECK(got.lang==TLG_ZH);
 CHECK(!tlg_uncarrier(NULL,74,back,false));CHECK(!tlg_uncarrier(wire,74,NULL,true));
}
@interface Fixture:NSObject
@property NSString *peer;
@property BOOL allowed,submit;
@property double now;
@property NSMutableArray<NSData *> *sent;
@property TIOLanguageFlagLink *link;
@end
@implementation Fixture
- (instancetype)init{if((self=[super init])){_peer=@"peer-a";_allowed=YES;_submit=YES;_now=100;_sent=[NSMutableArray new];__weak Fixture *w=self;_link=[[TIOLanguageFlagLink alloc]initWithPeer:^{return w.peer;} allowed:^BOOL{return w.allowed;} clock:^{return w.now;} send:^BOOL(NSData *p){[w.sent addObject:p];return w.submit;}];}return self;}
@end
static TLGCommand Sent(Fixture *f){uint8_t raw[32];TLGCommand q={0};CHECK(tlg_uncarrier(f.sent.lastObject.bytes,f.sent.lastObject.length,raw,false));CHECK(tlg_decode(raw,32,&q));return q;}
static NSDictionary *Event(NSString *peer,TLGCommand q,uint8_t lang,uint8_t result){TLGReply r={q.request,q.op,lang,result,TLG_SOURCE_PHONE};uint8_t raw[32],wire[74];tlg_reply_encode(raw,&r);tlg_carrier(wire,raw,true);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":peer,@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}};}
static void Ack(Fixture *f,uint8_t lang){CHECK([f.link consume:Event(f.peer,Sent(f),lang,TLG_OK)]);}
static BOOL State(Fixture *f,NSString *s){return [f.link.status[@"state"]isEqual:s];}
static void Link(void){
 Fixture *f=[Fixture new];CHECK(State(f,@"idle"));[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==1&&f.link.busy&&State(f,@"sending"));TLGCommand first=Sent(f);CHECK(first.op==TLG_SET&&first.lang==TLG_ZH&&first.request);Ack(f,TLG_ZH);CHECK(State(f,@"acked")&&!f.link.busy);CHECK([f.link.status[@"lang"]isEqual:@1]);CHECK([f.link.status[@"source"]isEqual:@1]);CHECK([f.link.status[@"lastAckAge"]doubleValue]==0);
 CHECK([NSSet setWithArray:f.link.status.allKeys].count==4);CHECK(f.link.status[@"deviceId"]==nil);CHECK([[f.link.status description]rangeOfString:f.peer].location==NSNotFound);
 [f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==1);f.now+=29.999;[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==1);f.now+=.001;[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==2);Ack(f,TLG_ZH);
 // Latest wins, including changing back to the in-flight value.
 f=[Fixture new];[f.link pushLanguage:TLG_EN];[f.link pushLanguage:TLG_ZH];[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==1);Ack(f,TLG_EN);CHECK(f.sent.count==1);
 f=[Fixture new];[f.link pushLanguage:TLG_EN];TLGCommand old=Sent(f);[f.link pushLanguage:TLG_ZH];[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==1);Ack(f,TLG_EN);CHECK(f.sent.count==2&&f.link.busy);TLGCommand next=Sent(f);CHECK(next.lang==TLG_ZH&&next.request!=old.request);Ack(f,TLG_ZH);CHECK(f.sent.count==2&&State(f,@"acked"));
 // Wrong-device/request/op frames are recognized but cannot complete a send.
 f=[Fixture new];[f.link pushLanguage:TLG_ZH];first=Sent(f);CHECK(TIOLanguageFlagIsReply(Event(f.peer,first,TLG_ZH,TLG_OK)));CHECK([f.link consume:Event(@"other",first,TLG_ZH,TLG_OK)]);CHECK(f.link.busy);TLGCommand wrong=first;wrong.request++;CHECK([f.link consume:Event(f.peer,wrong,TLG_ZH,TLG_OK)]);CHECK(f.link.busy);wrong=first;wrong.op=TLG_QUERY;CHECK([f.link consume:Event(f.peer,wrong,TLG_ZH,TLG_OK)]);CHECK(f.link.busy);Ack(f,TLG_ZH);
 CHECK(!TIOLanguageFlagIsReply(@{}));CHECK(![f.link consume:@{}]);NSMutableDictionary *event=[Event(f.peer,first,TLG_ZH,TLG_OK) mutableCopy];event[@"eventType"]=@"other";CHECK(!TIOLanguageFlagIsReply(event));NSMutableDictionary *msg=[event[@"message"] mutableCopy];msg[@"businessId"]=@14;event[@"message"]=msg;event[@"eventType"]=@"messageReceived";CHECK(!TIOLanguageFlagIsReply(event));msg[@"businessId"]=@15;msg[@"deviceId"]=@1;CHECK(!TIOLanguageFlagIsReply(event));msg[@"deviceId"]=@"peer-a";msg[@"payload"]=@"text";CHECK(!TIOLanguageFlagIsReply(event));
 // Clock-driven expiry and wall timer use the same deadline. No retries.
 f=[Fixture new];[f.link pushLanguage:TLG_EN];first=Sent(f);[f.link pushLanguage:TLG_ZH];f.now+=3;CHECK(State(f,@"unsupported")&&!f.link.busy);[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==1);CHECK([f.link consume:Event(f.peer,first,TLG_EN,TLG_OK)]);CHECK(State(f,@"unsupported"));f.peer=@"peer-b";[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==2&&f.link.busy);Ack(f,TLG_ZH);
 f=[Fixture new];f.allowed=NO;[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==0);f.allowed=YES;f.peer=nil;[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==0);f.peer=@"peer-a";[f.link pushLanguage:2];CHECK(f.sent.count==0);[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==1);
 // Losing the gate while waiting cancels, and discards queued language.
 [f.link pushLanguage:TLG_ZH];f.allowed=NO;CHECK(!f.link.busy);f.allowed=YES;CHECK(f.sent.count==1);[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==2);[f.link cancel];f.now+=10;CHECK(State(f,@"idle")&&!f.link.busy);CHECK(f.sent.count==2);[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==3);
 f=[Fixture new];[f.link pushLanguage:TLG_EN];first=Sent(f);[f.link pushLanguage:TLG_ZH];[f.link cancel];CHECK([f.link consume:Event(f.peer,first,TLG_EN,TLG_OK)]);CHECK(State(f,@"idle")&&f.sent.count==1);
 f=[Fixture new];[f.link pushLanguage:TLG_EN];first=Sent(f);f.peer=@"peer-b";CHECK([f.link consume:Event(@"peer-a",first,TLG_EN,TLG_OK)]);CHECK(State(f,@"idle"));[f.link pushLanguage:TLG_ZH];CHECK(f.sent.count==2);Ack(f,TLG_ZH);
 // Negative completion never drains a queued value.
 for(int result=TLG_BLOCKED;result<=TLG_INVALID;result++){f=[Fixture new];[f.link pushLanguage:TLG_EN];[f.link pushLanguage:TLG_ZH];CHECK([f.link consume:Event(f.peer,Sent(f),TLG_EN,result)]);CHECK(State(f,result==TLG_BLOCKED?@"blocked":@"failed"));CHECK(!f.link.busy&&f.sent.count==1);}
 f=[Fixture new];f.submit=NO;[f.link pushLanguage:TLG_EN];CHECK(State(f,@"failed")&&!f.link.busy);CHECK(f.sent.count==1);f.now+=5;CHECK(State(f,@"failed"));
 f=[Fixture new];[f.link pushLanguage:TLG_ZH];CHECK([f.link consume:Event(f.peer,Sent(f),TLG_EN,TLG_OK)]);CHECK(State(f,@"failed")&&!f.link.busy);
 // An uncertain intervening SET invalidates suppression based on an older ACK.
 f=[Fixture new];[f.link pushLanguage:TLG_EN];Ack(f,TLG_EN);[f.link pushLanguage:TLG_ZH];[f.link cancel];[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==3&&f.link.busy);
 // Reconnecting through nil clears unsupported; unchanged peer does not.
 f=[Fixture new];[f.link pushLanguage:TLG_EN];f.now+=3;CHECK(State(f,@"unsupported"));f.peer=nil;CHECK(State(f,@"idle"));f.peer=@"peer-a";[f.link pushLanguage:TLG_EN];CHECK(f.sent.count==2);
}
int main(void){@autoreleasepool{Codec();Link();printf("language-flag: PASS (%u checks)\n",Checks);}return 0;}
