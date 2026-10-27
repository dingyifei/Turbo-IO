#include "lang_flag.h"
#include <string.h>
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
uint32_t tlg_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned b=0;b<8;b++)c=(c>>1)^(0xedb88320u&-(c&1));}return ~c;}
static bool base(const uint8_t *p,size_t n,const char *magic){return p&&n==32&&!memcmp(p,magic,4)&&p[4]==1&&p[5]<=TLG_SET&&p[6]<=TLG_ZH&&u32(p+8)&&u32(p+28)==tlg_crc(p,28);}
bool tlg_decode(const uint8_t *p,size_t n,TLGCommand *q){
 if(!q||!base(p,n,"TLG1")||p[7]||(p[5]==TLG_QUERY&&p[6]!=TLG_EN))return false;
 for(unsigned i=12;i<28;i++)if(p[i])return false;
 *q=(TLGCommand){u32(p+8),p[5],p[6]};return true;
}
void tlg_encode(uint8_t *p,const TLGCommand *q){memset(p,0,32);memcpy(p,"TLG1",4);p[4]=1;p[5]=q->op;p[6]=q->lang;w32(p+8,q->request);w32(p+28,tlg_crc(p,28));}
bool tlg_reply_decode(const uint8_t *p,size_t n,TLGReply *q){
 if(!q||!base(p,n,"TLA1")||p[7]>TLG_INVALID||p[12]>TLG_SOURCE_PERSISTED)return false;
 for(unsigned i=13;i<28;i++)if(p[i])return false;
 *q=(TLGReply){u32(p+8),p[5],p[6],p[7],p[12]};return true;
}
void tlg_reply_encode(uint8_t *p,const TLGReply *q){memset(p,0,32);memcpy(p,"TLA1",4);p[4]=1;p[5]=q->op;p[6]=q->lang;p[7]=q->result;w32(p+8,q->request);p[12]=q->source;w32(p+28,tlg_crc(p,28));}
size_t tlg_carrier(uint8_t *p,const uint8_t *raw,bool reply){static const char hex[]="0123456789abcdef";const uint8_t head[]={8,1,16,127,26,68};memcpy(p,head,6);memcpy(p+6,reply?"TLA:":"TLG:",4);for(unsigned i=0;i<32;i++){p[10+2*i]=hex[raw[i]>>4];p[11+2*i]=hex[raw[i]&15];}return 74;}
static int hex(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
bool tlg_uncarrier(const uint8_t *p,size_t n,uint8_t *raw,bool reply){
 const uint8_t head[]={8,1,16,127,26,68};if(!p||!raw||n!=74||memcmp(p,head,6)||memcmp(p+6,reply?"TLA:":"TLG:",4))return false;
 uint8_t decoded[32];for(unsigned i=0;i<32;i++){int a=hex(p[10+2*i]),b=hex(p[11+2*i]);if(a<0||b<0)return false;decoded[i]=(uint8_t)(a*16+b);}memcpy(raw,decoded,32);return true;
}
