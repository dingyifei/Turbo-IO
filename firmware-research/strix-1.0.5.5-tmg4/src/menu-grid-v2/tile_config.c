#include "tile_config.h"
#include <string.h>
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static unsigned get16(const uint8_t *p){return p[0]|(unsigned)p[1]<<8;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void put16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static bool equal(const TTConfig *a,const TTConfig *b){return a->hide==b->hide&&!memcmp(a->order,b->order,TT_ITEMS);}
void tt_default(TTConfig *c){if(!c)return;memset(c,0,sizeof *c);for(unsigned i=0;i<TT_ITEMS;i++)c->order[i]=(uint8_t)i;}
bool tt_valid(const TTConfig *c){
 if(!c||(c->hide&~0x0f80u))return false;unsigned used=0;
 for(unsigned i=0;i<TT_ITEMS;i++){unsigned id=c->order[i];if(id>=TT_ITEMS||(used&(1u<<id))||(i<7&&id!=i))return false;used|=1u<<id;}return used==0x1fff;
}
bool tt_compact(const TTConfig *c,TTVisible *out){
 if(!out||!tt_valid(c))return false;TTVisible v;memset(&v,0,sizeof v);memset(v.rank,255,sizeof v.rank);
 for(unsigned i=0;i<TT_ITEMS;i++){unsigned id=c->order[i];if(c->hide&(1u<<id))continue;v.rank[id]=v.count;v.ids[v.count++]=(uint8_t)id;}
 *out=v;return true;
}
bool tt_rank(const TTConfig *c,uint16_t *out){
 if(!out||!tt_valid(c))return false;unsigned rank=0;static const unsigned factorial[]={120,24,6,2,1,1};
 for(unsigned i=0;i<6;i++){unsigned less=0;for(unsigned j=i+1;j<6;j++)less+=c->order[j+7]<c->order[i+7];rank+=less*factorial[i];}
 *out=(uint16_t)rank;return true;
}
bool tt_unrank(unsigned rank,unsigned hide,TTConfig *out){
 if(!out||rank>=720||(hide&~0x0f80u))return false;TTConfig c;tt_default(&c);c.hide=(uint16_t)hide;uint8_t ids[]={7,8,9,10,11,12};static const unsigned factorial[]={120,24,6,2,1,1};
 for(unsigned i=0;i<6;i++){unsigned at=rank/factorial[i];rank%=factorial[i];if(at>=6-i)return false;c.order[i+7]=ids[at];for(unsigned j=at+1;j<6-i;j++)ids[j-1]=ids[j];}
 *out=c;return true;
}
uint32_t tt_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
static bool base(const uint8_t *p,size_t n,const char *magic){return p&&n==32&&!memcmp(p,magic,4)&&p[4]==1&&p[5]<=TT_SET&&get32(p+8)&&get32(p+20)&&get32(p+28)==tt_crc(p,28);}
void tt_encode(uint8_t *p,const TTCommand *q){if(!p||!q)return;memset(p,0,32);memcpy(p,"TTL1",4);p[4]=1;p[5]=q->op;put32(p+8,q->request);put32(p+12,q->token);put32(p+16,q->generation);put32(p+20,q->client);put16(p+24,q->rank);put16(p+26,q->hide);put32(p+28,tt_crc(p,28));}
bool tt_decode(const uint8_t *p,size_t n,TTCommand *out){
 if(!out||!base(p,n,"TTL1")||p[6]||p[7])return false;
 TTCommand q={.request=get32(p+8),.token=get32(p+12),.generation=get32(p+16),.client=get32(p+20),.rank=(uint16_t)get16(p+24),.hide=(uint16_t)get16(p+26),.op=p[5]};TTConfig c;
 if(q.op==TT_QUERY?(q.token||q.generation||q.rank||q.hide):(!q.token||!tt_unrank(q.rank,q.hide,&c)))return false;*out=q;return true;
}
void tt_reply_encode(uint8_t *p,const TTReply *q){if(!p||!q)return;memset(p,0,32);memcpy(p,"TTA1",4);p[4]=1;p[5]=q->op;p[6]=q->count;p[7]=q->result;put32(p+8,q->request);put32(p+12,q->token);put32(p+16,q->generation);put32(p+20,q->client);put16(p+24,q->rank);put16(p+26,q->hide);put32(p+28,tt_crc(p,28));}
bool tt_reply_decode(const uint8_t *p,size_t n,TTReply *out){
 if(!out||!base(p,n,"TTA1")||p[7]>TT_UNAVAILABLE||p[6]<8||p[6]>13)return false;
 TTReply q={.request=get32(p+8),.token=get32(p+12),.generation=get32(p+16),.client=get32(p+20),.rank=(uint16_t)get16(p+24),.hide=(uint16_t)get16(p+26),.op=p[5],.count=p[6],.result=p[7]};TTConfig c;TTVisible v;
 if(!tt_unrank(q.rank,q.hide,&c)||!tt_compact(&c,&v)||v.count!=q.count||((q.op==TT_QUERY&&q.result==TT_OK)?!q.token:q.token!=0))return false;*out=q;return true;
}
size_t tt_carrier(uint8_t *p,const uint8_t *raw,bool reply){if(!p||!raw)return 0;static const char hex[]="0123456789abcdef";const uint8_t head[]={8,1,16,127,26,68};memcpy(p,head,6);memcpy(p+6,reply?"TTA:":"TTL:",4);for(unsigned i=0;i<32;i++){p[10+2*i]=hex[raw[i]>>4];p[11+2*i]=hex[raw[i]&15];}return 74;}
static int hex(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
bool tt_uncarrier(const uint8_t *p,size_t n,uint8_t *out,bool reply){const uint8_t head[]={8,1,16,127,26,68};if(!p||!out||n!=74||memcmp(p,head,6)||memcmp(p+6,reply?"TTA:":"TTL:",4))return false;uint8_t raw[32];for(unsigned i=0;i<32;i++){int a=hex(p[10+2*i]),b=hex(p[11+2*i]);if(a<0||b<0)return false;raw[i]=(uint8_t)(a*16+b);}memcpy(out,raw,32);return true;}
void tt_file_encode(uint8_t *p,const TTConfig *c,uint32_t generation){if(!p||!c)return;memset(p,0,32);memcpy(p,"TTC1",4);p[4]=1;p[5]=13;put16(p+6,c->hide);put32(p+8,generation);memcpy(p+12,c->order,13);put32(p+28,tt_crc(p,28));}
bool tt_file_decode(const uint8_t *p,int n,TTStored *out){
 if(!out||!p||n!=32||memcmp(p,"TTC1",4)||p[4]!=1||p[5]!=13||!get32(p+8)||p[25]||p[26]||p[27]||get32(p+28)!=tt_crc(p,28))return false;
 TTStored s={.generation=get32(p+8),.readable=true};s.config.hide=(uint16_t)get16(p+6);memcpy(s.config.order,p+12,13);if(!tt_valid(&s.config))return false;*out=s;return true;
}
TTStored tt_load(const TTIO *io){
 TTStored result={.bank=1,.readable=true};tt_default(&result.config);if(!io||!io->read){result.readable=false;return result;}
 TTStored banks[2];bool valid[2]={false,false};uint8_t raw[33];
 for(unsigned b=0;b<2;b++){int n=io->read(io->ctx,b,raw,sizeof raw);if(n<0)result.readable=false;valid[b]=tt_file_decode(raw,n,&banks[b]);if(valid[b])banks[b].bank=b;}
 unsigned chosen=valid[0]?0:1;if(!valid[chosen])return result;
 if(valid[0]&&valid[1]){uint32_t d=banks[0].generation-banks[1].generation;if(d==0){if(!equal(&banks[0].config,&banks[1].config)){result.readable=false;return result;}chosen=0;}else if(d==0x80000000u){result.readable=false;return result;}else chosen=d<0x80000000u?0:1;}
 bool readable=result.readable;result=banks[chosen];result.readable=readable;return result;
}
bool tt_store(const TTIO *io,TTStored *s,const TTConfig *c){
 if(!io||!io->write||!s||!s->readable||!tt_valid(c))return false;if(s->generation&&equal(&s->config,c))return true;
 uint32_t generation=s->generation+1;if(!generation)generation=1;unsigned bank=s->bank^1u;if(bank>1)return false;uint8_t raw[32];tt_file_encode(raw,c,generation);
 bool wrote=io->write(io->ctx,bank,raw,sizeof raw);TTStored latest=tt_load(io);
 /* A failed reread cannot replace the last verified presentation state. */
 if(!latest.readable){s->readable=false;return false;}*s=latest;return wrote&&s->generation==generation&&s->bank==bank&&equal(&s->config,c);
}
unsigned tt_accept(TTState *s,const TTCommand *q,uint32_t now,uint32_t nonce,bool allowed,const TTIO *io){
 if(!s||!q)return TT_UNAVAILABLE;if(!allowed){s->token=0;return TT_BLOCKED;}if(!s->loaded){s->token=0;return TT_UNAVAILABLE;}
 if(q->op==TT_QUERY){TTStored latest=tt_load(io);s->token=0;if(!latest.readable){s->stored.readable=false;return TT_STORAGE;}s->stored=latest;if(!nonce)return TT_UNAVAILABLE;s->token=nonce;s->client=q->client;s->issued=now;return TT_OK;}
 if(q->op!=TT_SET||!s->token||q->token!=s->token||q->client!=s->client||q->generation!=s->stored.generation||(uint32_t)(now-s->issued)>120000)return TT_SESSION;
 s->token=0;TTConfig c;if(!tt_unrank(q->rank,q->hide,&c))return TT_UNAVAILABLE;return tt_store(io,&s->stored,&c)?TT_OK:TT_STORAGE;
}
void tt_reply(uint8_t *raw,const TTState *s,const TTCommand *q,unsigned result){TTVisible v;uint16_t rank=0;(void)tt_compact(&s->stored.config,&v);(void)tt_rank(&s->stored.config,&rank);TTReply reply={.request=q->request,.client=q->client,.token=result==TT_OK&&q->op==TT_QUERY?s->token:0,.generation=s->stored.generation,.rank=rank,.hide=s->stored.config.hide,.op=q->op,.count=v.count,.result=(uint8_t)result};tt_reply_encode(raw,&reply);}
