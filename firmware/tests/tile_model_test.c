/* The tile model for whichever base the define selects: ids, ranks, masks, padding, and refusal of the other version. */
#include "../src/menu-grid-v2/tile_config.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
int main(void){
 TTConfig c;tt_default(&c);TTVisible map;assert(tt_valid(&c)&&tt_compact(&c,&map)&&map.count==TT_ITEMS);
 unsigned seen_counts=0;
 for(unsigned r=0;r<720;r++)for(unsigned mask=0;mask<32;mask++){
  TTConfig q;assert(tt_unrank(r,mask<<TT_STOCK,&q));uint16_t rank=999;assert(tt_rank(&q,&rank)&&rank==r&&tt_compact(&q,&map));
  unsigned hidden=0;for(unsigned k=0;k<5;k++)hidden+=(mask>>k)&1u;assert(map.count==TT_ITEMS-hidden&&map.count>=TT_MIN_VISIBLE);seen_counts|=1u<<map.count;
  for(unsigned i=0;i<map.count;i++){unsigned id=map.ids[i];assert(id<TT_ITEMS&&map.rank[id]==i);if(i<TT_STOCK)assert(id==i);}
  assert(map.rank[TT_CAMERA]!=255);
 }
 assert(seen_counts==(((1u<<(TT_ITEMS+1))-1u)&~((1u<<TT_MIN_VISIBLE)-1u)));
 assert(!tt_unrank(0,1u<<TT_CAMERA,&c)&&!tt_unrank(0,1u<<(TT_STOCK-1),&c)&&!tt_unrank(720,0,&c));
 /* a version-1 file (the 13-item layout, as the 1.0.5.12 tree writes it) and a version-2 one */
 uint8_t f[32]={0};memcpy(f,"TTC1",4);f[4]=1;f[5]=13;put32(f+8,5);for(unsigned i=0;i<13;i++)f[12+i]=(uint8_t)i;put32(f+28,tt_crc(f,28));TTStored s;
 assert(tt_file_decode(f,32,&s)==(TT_VERSION==1));
 tt_default(&c);tt_file_encode(f,&c,5);assert(tt_file_decode(f,32,&s)&&f[4]==TT_VERSION&&f[5]==TT_ITEMS);
 f[4]=(uint8_t)(3-TT_VERSION);put32(f+28,tt_crc(f,28));assert(!tt_file_decode(f,32,&s));
 /* every padding byte after the order must be zero */
 for(unsigned i=12+TT_ITEMS;i<28;i++){uint8_t g[32];tt_default(&c);tt_file_encode(g,&c,7);g[i]=1;put32(g+28,tt_crc(g,28));assert(!tt_file_decode(g,32,&s));}
 /* a version-1 wire command */
 TTCommand q={.request=1,.client=2,.op=TT_QUERY},o;uint8_t raw[32];tt_encode(raw,&q);assert(raw[4]==TT_VERSION&&tt_decode(raw,32,&o));
 raw[4]=(uint8_t)(3-TT_VERSION);put32(raw+28,tt_crc(raw,28));assert(!tt_decode(raw,32,&o));
 /* a SET frame that this model accepts (rank 0, hide 0, nonzero token) is refused once only its version byte names the other model */
 TTCommand st={.request=1,.client=2,.token=9,.op=TT_SET},so;tt_encode(raw,&st);assert(tt_decode(raw,32,&so));
 raw[4]=(uint8_t)(3-TT_VERSION);put32(raw+28,tt_crc(raw,28));assert(!tt_decode(raw,32,&so));
 TTReply a={.request=1,.client=2,.token=3,.op=TT_QUERY,.count=TT_ITEMS},b;tt_reply_encode(raw,&a);assert(tt_reply_decode(raw,32,&b));
 a.count=TT_ITEMS+1;tt_reply_encode(raw,&a);assert(!tt_reply_decode(raw,32,&b));
 printf("PASS tile model %u stock + %u module = %u items, hideable 0x%04x, all 0x%04x, camera %u, visible %u..%u, version %u refuses version %u\n",
  (unsigned)TT_STOCK,(unsigned)TT_MODULE,(unsigned)TT_ITEMS,TT_HIDEABLE,TT_ALL,(unsigned)TT_CAMERA,(unsigned)TT_MIN_VISIBLE,(unsigned)TT_ITEMS,(unsigned)TT_VERSION,3u-TT_VERSION);
}
