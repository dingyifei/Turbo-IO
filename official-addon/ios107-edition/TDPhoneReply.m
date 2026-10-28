#import "TDPhoneReply.h"
#import "diagnostics.h"
NSData *TDPhoneReply(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *d=m[@"payload"];const uint8_t head[]={8,1,16,6,26,0xb4,4};if(d.length!=571||memcmp(d.bytes,head,sizeof head))return nil;
 id j=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:NSMakeRange(7,564)] options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_diagnostics_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return nil;
 id hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||[hex length]!=2*TD_WIRE_BYTES)return nil;uint8_t raw[TD_WIRE_BYTES];
 for(unsigned i=0;i<TD_WIRE_BYTES;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return nil;v=v*16+n;}raw[i]=(uint8_t)v;}
 TDSample sample;if(!td_decode(raw,sizeof raw,&sample))return nil;return [NSData dataWithBytes:raw length:sizeof raw];
}
