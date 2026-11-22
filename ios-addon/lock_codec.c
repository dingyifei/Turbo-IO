#include "lock_codec.h"
#include <string.h>
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
uint32_t tlk_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned b=0;b<8;b++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
static bool minutes(unsigned m){return m>=1&&m<=240;}
void tlk_encode(uint8_t *p,const TLKCommand *q){
 memset(p,0,32);memcpy(p,"TLK1",4);p[4]=1;p[5]=q->op;w32(p+8,q->request);w32(p+12,q->token);w32(p+16,q->client);
 if(q->op==TLK_OP_SET_TIME){p[20]=q->fold_min;p[21]=q->idle_min;}
 if(q->op==TLK_OP_SET_PIN){p[22]=(uint8_t)(q->pin[0]<<4|q->pin[1]);p[23]=(uint8_t)(q->pin[2]<<4|q->pin[3]);}
 w32(p+28,tlk_crc(p,28));
}
bool tlk_decode(const uint8_t *p,size_t n,TLKCommand *q){
 if(!p||!q||n!=32||memcmp(p,"TLK1",4)||p[4]!=1||p[5]<TLK_OP_QUERY||p[5]>TLK_OP_LAST||p[6]||p[7]||!u32(p+8)||!u32(p+16)||u32(p+28)!=tlk_crc(p,28))return false;
 for(unsigned i=24;i<28;i++)if(p[i])return false;
 TLKCommand c={.request=u32(p+8),.token=u32(p+12),.client=u32(p+16),.op=p[5]};
 if((c.op==TLK_OP_QUERY)!=(c.token==0))return false;   // a QUERY carries no token; everything else must
 if(c.op==TLK_OP_SET_TIME){if(!minutes(p[20])||!minutes(p[21]))return false;c.fold_min=p[20];c.idle_min=p[21];}
 else if(p[20]||p[21])return false;
 if(c.op==TLK_OP_SET_PIN){uint8_t d[4]={p[22]>>4,p[22]&15,p[23]>>4,p[23]&15};for(unsigned i=0;i<4;i++){if(d[i]>9)return false;c.pin[i]=d[i];}}
 else if(p[22]||p[23])return false;
 *q=c;return true;
}
void tlk_reply_encode(uint8_t *p,const TLKReply *q){
 memset(p,0,32);memcpy(p,"TKA1",4);p[4]=1;p[5]=q->op;p[6]=q->result;p[7]=q->flags;w32(p+8,q->request);w32(p+12,q->token);w32(p+16,q->client);
 p[20]=q->fold_min;p[21]=q->idle_min;p[22]=q->wrong;p[23]=q->unacked;w32(p+24,q->delay_left);w32(p+28,tlk_crc(p,28));
}
bool tlk_reply_decode(const uint8_t *p,size_t n,TLKReply *q){
 if(!p||!q||n!=32||memcmp(p,"TKA1",4)||p[4]!=1||p[5]<TLK_OP_QUERY||p[5]>TLK_OP_LAST||p[6]>TLK_R_REFUSED||p[7]>31||!u32(p+8)||u32(p+28)!=tlk_crc(p,28))return false;
 *q=(TLKReply){.request=u32(p+8),.token=u32(p+12),.client=u32(p+16),.delay_left=u32(p+24),.op=p[5],.result=p[6],.flags=p[7],.fold_min=p[20],.idle_min=p[21],.wrong=p[22],.unacked=p[23]};
 return true;
}
size_t tlk_carrier(uint8_t *p,const uint8_t *raw,bool reply){static const char h[]="0123456789abcdef";const uint8_t head[]={8,1,16,127,26,68};memcpy(p,head,6);memcpy(p+6,reply?"TKA:":"TLK:",4);for(unsigned i=0;i<32;i++){p[10+2*i]=h[raw[i]>>4];p[11+2*i]=h[raw[i]&15];}return 74;}
static int hex(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
bool tlk_uncarrier(const uint8_t *p,size_t n,uint8_t *raw,bool reply){
 const uint8_t head[]={8,1,16,127,26,68};if(!p||!raw||n!=74||memcmp(p,head,6)||memcmp(p+6,reply?"TKA:":"TLK:",4))return false;
 uint8_t d[32];for(unsigned i=0;i<32;i++){int a=hex(p[10+2*i]),b=hex(p[11+2*i]);if(a<0||b<0)return false;d[i]=(uint8_t)(a*16+b);}memcpy(raw,d,32);return true;
}
unsigned tlk_session(TLKSession *s,const TLKCommand *q,uint32_t now_ms,uint32_t nonce){
 if(q->op==TLK_OP_QUERY){s->token=0;if(!nonce)return TLK_R_UNAVAILABLE;s->token=nonce;s->client=q->client;s->issued=now_ms;return TLK_R_OK;}
 bool ok=s->token&&q->token==s->token&&q->client==s->client&&(uint32_t)(now_ms-s->issued)<=TLK_TOKEN_MS;
 s->token=0;   // used once, also when refused
 return ok?TLK_R_OK:TLK_R_SESSION;
}
