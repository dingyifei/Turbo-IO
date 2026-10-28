#import "MusicBridge.h"
#import "music.h"
#include <assert.h>
id TIOProtocolPlugin(void){return nil;} NSString *TIOProtocolDevice(void){return @"fixture";}
void TDPDiagConfigure(NSURL *url){(void)url;}
static void Put(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static NSDictionary *Reply(unsigned flags,unsigned event){uint8_t raw[32]={'T','M','A','1',1};raw[5]=event;raw[7]=flags;Put(raw+28,tm_crc(raw,28));NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<32;i++)[hex appendFormat:@"%02x",raw[i]];
 NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_music_v1",@"payload":@{@"data":hex}} options:0 error:nil];NSMutableData *data=[NSMutableData dataWithBytes:(uint8_t[]){8,1,16,6,26} length:5];NSUInteger n=json.length;do{uint8_t v=n&127;n>>=7;if(n)v|=128;[data appendBytes:&v length:1];}while(n);[data appendData:json];return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"payload":data}};}
int main(void){@autoreleasepool{NSDictionary *q;for(unsigned event=TM_ACK;event<=TM_VIEW_CLOSED;event++){assert(TMMusicReply(Reply(3,event),&q)&&![q[@"staticControls"]boolValue]);assert(TMMusicReply(Reply(7,event),&q)&&[q[@"staticControls"]boolValue]);assert(!TMMusicReply(Reply(8,event),&q));}
 puts("PASS TMG4/TMG5 music replies, existing controls, unknown flags rejected");}return 0;}
