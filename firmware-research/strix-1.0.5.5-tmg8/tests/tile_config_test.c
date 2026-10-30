#include "../src/menu-grid-v2/tile_config.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
typedef struct {uint8_t bytes[2][40];int n[2],error[2];unsigned writes,reads;int fail;} Disk;
static int read_bank(void *ctx,unsigned bank,uint8_t *p,size_t cap){Disk *d=ctx;assert(bank<2&&cap==33);d->reads++;if(d->error[bank])return -1;size_t n=(unsigned)d->n[bank];if(n>cap)n=cap;memcpy(p,d->bytes[bank],n);return (int)n;}
static bool write_bank(void *ctx,unsigned bank,const uint8_t *p,size_t n){Disk *d=ctx;assert(bank<2&&n==32);d->writes++;if(d->fail==1)return false;memcpy(d->bytes[bank],p,n);d->n[bank]=(int)n;if(d->fail==2)d->bytes[bank][31]^=1;return d->fail!=3;}
static bool same(const TTConfig *a,const TTConfig *b){return a->hide==b->hide&&!memcmp(a->order,b->order,13);}
static void permutation(void){
 TTConfig c;tt_default(&c);assert(tt_valid(&c));TTVisible map;assert(tt_compact(&c,&map)&&map.count==13);
 for(unsigned r=0;r<720;r++)for(unsigned mask=0;mask<32;mask++){
  TTConfig q;assert(tt_unrank(r,mask<<7,&q));uint16_t rank=999;assert(tt_rank(&q,&rank)&&rank==r);assert(tt_compact(&q,&map));
  unsigned hidden=0;for(unsigned k=0;k<5;k++)hidden+=(mask>>k)&1u;assert(map.count==13-hidden&&map.count>=8);bool seen[13]={0};
  for(unsigned i=0;i<map.count;i++){unsigned id=map.ids[i];assert(id<13&&!seen[id]&&map.rank[id]==i);seen[id]=true;if(i<7)assert(id==i);}
  assert(seen[12]);for(unsigned id=0;id<13;id++)assert(seen[id]||map.rank[id]==255);
  for(unsigned rows=2;rows<=3;rows++)for(unsigned i=0;i<map.count;i++){unsigned cells=rows*3,page=i/cells,cell=i%cells;assert(page<(map.count+cells-1)/cells&&cell<9);}
 }
 assert(!tt_unrank(720,0,&c)&&!tt_unrank(0,1,&c)&&!tt_unrank(0,1u<<12,&c));
 tt_default(&c);c.order[0]=1;assert(!tt_valid(&c));tt_default(&c);c.order[8]=7;assert(!tt_valid(&c));tt_default(&c);c.order[12]=13;assert(!tt_valid(&c));assert(!tt_valid(NULL));
}
static void packets(void){
 TTCommand q={.request=1,.client=2,.op=TT_QUERY},out;uint8_t raw[32],wire[74];tt_encode(raw,&q);assert(tt_decode(raw,32,&out)&&out.client==2);assert(tt_carrier(wire,raw,false)==74);uint8_t decoded[32];assert(tt_uncarrier(wire,74,decoded,false)&&!memcmp(decoded,raw,32));
 for(unsigned n=0;n<40;n++)if(n!=32)assert(!tt_decode(raw,n,&out));assert(!tt_decode(NULL,32,&out)&&!tt_decode(raw,32,NULL));
 for(unsigned i=0;i<32;i++)for(unsigned b=0;b<8;b++){raw[i]^=1u<<b;assert(!tt_decode(raw,32,&out));raw[i]^=1u<<b;}
 uint8_t original[32];memset(original,0x5a,32);for(unsigned n=0;n<80;n++)if(n!=74){memcpy(decoded,original,32);assert(!tt_uncarrier(wire,n,decoded,false)&&!memcmp(decoded,original,32));}
 wire[10]='A';assert(!tt_uncarrier(wire,74,decoded,false));
 q=(TTCommand){.request=1,.client=2,.token=3,.generation=UINT32_MAX,.op=TT_SET,.rank=719,.hide=0xf80};tt_encode(raw,&q);assert(tt_decode(raw,32,&out)&&out.rank==719&&out.generation==UINT32_MAX);
 q.rank=720;tt_encode(raw,&q);assert(!tt_decode(raw,32,&out));q.rank=0;q.hide=0x1000;tt_encode(raw,&q);assert(!tt_decode(raw,32,&out));
 TTReply a={.request=1,.client=2,.token=3,.op=TT_QUERY,.count=13},reply;tt_reply_encode(raw,&a);assert(tt_reply_decode(raw,32,&reply)&&reply.count==13);a.count=12;tt_reply_encode(raw,&a);assert(!tt_reply_decode(raw,32,&reply));
 uint32_t seed=7;for(unsigned i=0;i<50000;i++){for(unsigned k=0;k<32;k++){seed=seed*1664525u+1013904223u;raw[k]=(uint8_t)(seed>>24);}size_t n=i%40;memset(&out,0x5a,sizeof out);TTCommand save=out;bool ok=tt_decode(raw,n,&out);if(!ok)assert(!memcmp(&out,&save,sizeof out));(void)tt_reply_decode(raw,n,&reply);TTStored stored;(void)tt_file_decode(raw,(int)n,&stored);}
}
static void bank(Disk *d,unsigned b,const TTConfig *c,uint32_t gen){tt_file_encode(d->bytes[b],c,gen);d->n[b]=32;}
static void storage(void){
 Disk d={0};TTIO io={&d,read_bank,write_bank};TTConfig c,other;tt_default(&c);assert(tt_unrank(719,0xf80,&other));TTStored s=tt_load(&io);assert(s.readable&&!s.generation&&s.bank==1&&same(&s.config,&c)&&d.writes==0);
 assert(tt_store(&io,&s,&other)&&s.generation==1&&s.bank==0&&same(&s.config,&other));unsigned writes=d.writes;assert(tt_store(&io,&s,&other)&&writes==d.writes);
 for(unsigned len=0;len<=33;len++)if(len!=32){Disk x={0};bank(&x,0,&c,1);x.n[0]=(int)len;TTIO xi={&x,read_bank,write_bank};assert(tt_load(&xi).generation==0);}
 for(unsigned i=0;i<32;i++)for(unsigned b=0;b<8;b++){Disk x={0};bank(&x,0,&c,1);x.bytes[0][i]^=1u<<b;TTIO xi={&x,read_bank,write_bank};assert(tt_load(&xi).generation==0);}
 d=(Disk){0};bank(&d,0,&c,UINT32_MAX-1);s=tt_load(&io);assert(tt_store(&io,&s,&other)&&s.generation==UINT32_MAX);assert(tt_store(&io,&s,&c)&&s.generation==1&&s.bank==0);assert(tt_load(&io).generation==1);
 d=(Disk){0};bank(&d,0,&c,UINT32_MAX);bank(&d,1,&other,1);s=tt_load(&io);assert(s.generation==1&&s.bank==1);uint8_t tmp[40];memcpy(tmp,d.bytes[0],40);memcpy(d.bytes[0],d.bytes[1],40);memcpy(d.bytes[1],tmp,40);assert(tt_load(&io).bank==0);
 d=(Disk){0};bank(&d,0,&c,8);bank(&d,1,&c,8);s=tt_load(&io);assert(s.readable&&s.bank==0);bank(&d,1,&other,8);assert(!tt_load(&io).readable);bank(&d,1,&other,8u+0x80000000u);assert(!tt_load(&io).readable);
 d=(Disk){0};bank(&d,0,&c,4);d.error[1]=1;s=tt_load(&io);assert(!s.readable&&s.generation==4&&!tt_store(&io,&s,&other));
 for(int fail=1;fail<=3;fail++){d=(Disk){.fail=fail};bank(&d,0,&c,4);s=tt_load(&io);assert(!tt_store(&io,&s,&other));assert(s.generation==(fail==3?5:4));}
 assert(!tt_load(NULL).readable);
}
static void transactions(void){
 Disk d={0};TTIO io={&d,read_bank,write_bank};TTState s={0};tt_default(&s.stored.config);s.stored.readable=true;s.stored.bank=1;TTCommand q={.op=TT_QUERY,.request=1,.client=2};
 assert(tt_accept(&s,&q,0,7,true,&io)==TT_UNAVAILABLE&&d.reads==0);s.loaded=true;assert(tt_accept(&s,&q,UINT32_MAX-100,7,true,&io)==TT_OK&&s.token==7);
 q=(TTCommand){.op=TT_SET,.request=2,.client=2,.token=7,.rank=719,.hide=0xf80};assert(tt_accept(&s,&q,99,0,true,&io)==TT_OK&&s.stored.generation==1&&!s.token);assert(tt_accept(&s,&q,99,0,true,&io)==TT_SESSION);
 q=(TTCommand){.op=TT_QUERY,.request=3,.client=2};assert(tt_accept(&s,&q,1,8,true,&io)==TT_OK);q=(TTCommand){.op=TT_SET,.request=4,.client=2,.token=8,.generation=1};assert(tt_accept(&s,&q,120002,0,true,&io)==TT_SESSION);
 q=(TTCommand){.op=TT_QUERY,.request=3,.client=2};assert(tt_accept(&s,&q,3,8,true,&io)==TT_OK);assert(tt_accept(&s,&q,3,9,false,&io)==TT_BLOCKED&&!s.token);
 bank(&d,0,&s.stored.config,UINT32_MAX);d.n[1]=0;q=(TTCommand){.op=TT_QUERY,.request=5,.client=2};assert(tt_accept(&s,&q,10,99,true,&io)==TT_OK&&s.stored.generation==UINT32_MAX);q=(TTCommand){.op=TT_SET,.request=6,.client=2,.token=99,.generation=UINT32_MAX,.rank=1};assert(tt_accept(&s,&q,11,0,true,&io)==TT_OK&&s.stored.generation==1);
 q.token=99;q.generation=UINT32_MAX;assert(tt_accept(&s,&q,12,0,true,&io)==TT_SESSION);
}
int main(void){permutation();packets();storage();transactions();puts("PASS tile_config: exhaustive order/visibility, wire fuzz/CRC, A/B corruption/faults/wrap and gated single-use transactions");}
