/* TMG8 caps bit and the carousel layout value. Host only; no device I/O.
 * Firmware side: layout value 1 is accepted only from a peer whose command carries the TMG8 caps byte, and only on a
 * SET. Grid values 2 and 3 and every query stay byte-for-byte what TMG7 accepts, so older phones keep working.
 * Status side: TMG8 reports TD_CAP_MENU_CAROUSEL; TMG6/TMG7 caps stay valid and carry no carousel bit. */
#include "../src/menu-grid-v2/menu_config.h"
#include "../src/diagnostics-v1/diagnostics.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t p[2][32];int n[2];unsigned writes;} Disk;
static int read_bank(void *ctx,unsigned bank,uint8_t *p,size_t cap){Disk *d=ctx;assert(bank<2);int n=d->n[bank];assert(n<=(int)cap);memcpy(p,d->p[bank],n);return n;}
static bool write_bank(void *ctx,unsigned bank,const uint8_t *p,size_t n){Disk *d=ctx;assert(bank<2&&n<=32);memcpy(d->p[bank],p,n);d->n[bank]=(int)n;d->writes++;return true;}
static void fix_crc(uint8_t *raw){uint32_t c=tml_crc(raw,28);for(unsigned i=0;i<4;i++)raw[28+i]=(uint8_t)(c>>(8*i));}
/* What a frozen TMG7 glasses decoder accepts (copied from FW7 menu_config.c): the old rules, for the compatibility proof. */
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static bool tmg7_decode(const uint8_t *p,size_t n){
 if(!p||n!=32||memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]||u32(p+24)||!u32(p+8)||!u32(p+20)||u32(p+28)!=tml_crc(p,28))return false;
 unsigned op=p[5],rows=p[6];uint32_t token=u32(p+12),generation=u32(p+16);
 return op==TML_QUERY?(!rows&&!token&&!generation):((rows==2||rows==3)&&token);
}
static unsigned exchange(TMLState *s,const TMLIO *io,TMLCommand q,uint32_t now,uint32_t nonce){uint8_t raw[32];tml_encode(raw,&q);TMLCommand d;if(!tml_decode(raw,sizeof raw,&d))return 99;return tml_accept(s,&d,now,nonce,true,io);}
int main(void){
 /* Caps constants. */
 assert(TD_CAP_MENU_CAROUSEL==(1u<<9)&&!(TD_CAPS_TMG6&TD_CAP_MENU_CAROUSEL)&&TD_CAPS_TMG8==(TD_CAPS_TMG6|TD_CAP_MENU_CAROUSEL));
 assert((TD_CAPS_TMG6&TD_CAP_NAV_PASSING)&&(TD_CAPS_TMG8&TD_CAP_NAV_PASSING)); /* TMG8 keeps every TMG6/TMG7 bit */
 TDSample s={.build=TD_BUILD_TMG6,.kind=TD_STATUS,.session=1,.sequence=1,.caps=TD_CAPS_TMG8,.detent=TK_DETENT_RAW},d;uint8_t wire[TD_WIRE_BYTES];
 assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d)&&d.caps==TD_CAPS_TMG8&&(d.caps&TD_CAP_MENU_CAROUSEL));
 s.caps=TD_CAPS_TMG6;assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d)&&!(d.caps&TD_CAP_MENU_CAROUSEL)); /* a TMG7 status still decodes */
 s.caps=TD_CAPS_TMG8|(1u<<10);assert(!td_encode(&s,wire,sizeof wire)); /* nothing beyond the TMG8 bit */
 s.build=TD_BUILD_TMG5;s.caps=TD_CAPS_TMG5|TD_CAP_MENU_CAROUSEL;assert(!td_encode(&s,wire,sizeof wire)); /* older builds never claim it */
 TDDiagnostics diag;td_init(&diag,TD_BUILD_TMG6);TDSample sample;assert(td_start(&diag,5,100,60000)&&td_sample(&diag,100,true,NULL,NULL,NULL,&sample)&&sample.caps==TD_CAPS_TMG8);

 /* Command codec: the caps byte is wire byte 7. */
 uint8_t raw[32];TMLCommand q,set1={.op=TML_SET,.request=2,.client=7,.token=32,.rows=TML_CAROUSEL,.caps=TML_PEER_TMG8};
 tml_encode(raw,&set1);assert(raw[7]==TML_PEER_TMG8&&tml_decode(raw,sizeof raw,&q)&&q.rows==1&&q.caps==TML_PEER_TMG8);
 assert(!tmg7_decode(raw,sizeof raw)); /* TMG7 glasses drop it: the phone must never send it to them */
 raw[7]=0;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q)); /* value 1 without the caps byte is rejected */
 raw[7]=2;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q)); /* any other caps byte is rejected */
 for(unsigned rows=2;rows<=3;rows++){
  TMLCommand g={.op=TML_SET,.request=3,.client=7,.token=32,.rows=(uint8_t)rows};tml_encode(raw,&g);
  assert(tml_decode(raw,sizeof raw,&q)&&q.caps==0&&tmg7_decode(raw,sizeof raw)); /* grid SETs are byte-for-byte TMG7 */
  g.caps=TML_PEER_TMG8;tml_encode(raw,&g);assert(!tml_decode(raw,sizeof raw,&q)); /* the caps byte rides only the carousel */
 }
 TMLCommand query={.op=TML_QUERY,.request=1,.client=7};tml_encode(raw,&query);assert(tml_decode(raw,sizeof raw,&q)&&tmg7_decode(raw,sizeof raw));
 query.caps=TML_PEER_TMG8;tml_encode(raw,&query);assert(!tml_decode(raw,sizeof raw,&q)); /* queries never carry it */
 TMLCommand bad={.op=TML_SET,.request=2,.client=7,.token=32,.rows=0};tml_encode(raw,&bad);assert(!tml_decode(raw,sizeof raw,&q));
 bad.rows=4;tml_encode(raw,&bad);assert(!tml_decode(raw,sizeof raw,&q));

 /* Glasses state machine: value 1 is stored only with the caps byte; grid values behave as before. */
 Disk disk={0};TMLIO io={&disk,read_bank,write_bank};TMLState st={0};
 assert(exchange(&st,&io,(TMLCommand){.op=TML_QUERY,.request=1,.client=7},1000,32)==TML_OK&&st.stored.rows==3&&st.stored.generation==0);
 TMLCommand no_caps=set1;no_caps.caps=0;
 assert(tml_accept(&st,&no_caps,1001,0,true,&io)==TML_BLOCKED&&disk.writes==0&&!st.token); /* accept() refuses it even if a caller skips decode */
 assert(exchange(&st,&io,(TMLCommand){.op=TML_QUERY,.request=1,.client=7},1002,32)==TML_OK);
 assert(exchange(&st,&io,set1,1003,0)==TML_OK&&disk.writes==1&&st.stored.rows==1&&st.stored.generation==1);
 TMLStored loaded=tml_load(&io);assert(loaded.rows==1&&loaded.generation==1&&loaded.readable); /* the record survives a reboot */
 assert(tml_grid_rows(1)==2&&tml_grid_rows(2)==2&&tml_grid_rows(3)==3); /* until the carousel is drawn, 1 shows the 2-row grid */
 uint8_t reply[32];TMLCommand echo=set1;tml_reply(reply,&st,&echo,TML_OK);assert(reply[6]==1&&reply[7]==TML_OK);
 assert(exchange(&st,&io,(TMLCommand){.op=TML_QUERY,.request=4,.client=7},1004,33)==TML_OK);
 assert(exchange(&st,&io,(TMLCommand){.op=TML_SET,.request=5,.client=7,.token=33,.generation=1,.rows=3},1005,0)==TML_OK&&tml_load(&io).rows==3); /* back to a grid */

 /* A carousel record written by an earlier build is not possible, but a corrupt record still falls back to the default. */
 Disk empty={0};TMLIO eio={&empty,read_bank,write_bank};loaded=tml_load(&eio);assert(loaded.rows==3&&loaded.readable);
 puts("PASS TMG8 caps bit and carousel layout value: TMG8 reports bit 9, value 1 needs the caps byte on a SET, grid values and queries are TMG7-exact");
 return 0;
}
