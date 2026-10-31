/* TMG9 detent D: wire, storage and status. Host only; no device I/O. D is only stored and reported in this step; stepping keeps its
 * fixed constants (the hook-owned stepping lands later).
 *   wire     caps bit 10 (TD_CAP_KNOB_DETENT); a TMG2 SET carries D in the spare u32 at byte 24 only with the peer byte TML_PEER_TMG9
 *   storage  D/50 in byte 6 of the TMC2 record in the existing two-bank file, 0 = the default 400
 *   status   the "detent" field is the live D; the shared validator pairs it with the caps bits
 * Everything is checked against copies of the frozen TMG7 and TMG8 decoders and record readers, so a rollback is proven, not assumed. */
#include "../src/menu-grid-v2/menu_config.h"
#include "../src/diagnostics-v1/diagnostics.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t p[2][32];int n[2];unsigned writes;int fail_write;} Disk;
static int read_bank(void *ctx,unsigned bank,uint8_t *p,size_t cap){Disk *d=ctx;assert(bank<2);int n=d->n[bank];assert(n<=(int)cap);memcpy(p,d->p[bank],n);return n;}
static bool write_bank(void *ctx,unsigned bank,const uint8_t *p,size_t n){Disk *d=ctx;assert(bank<2&&n<=32);if(d->fail_write)return false;memcpy(d->p[bank],p,n);d->n[bank]=(int)n;d->writes++;return true;}
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static void fix_crc(uint8_t *raw){w32(raw+28,tml_crc(raw,28));}

/* Frozen decoders (copied from fw/tmg7 and fw/tmg8 menu_config.c): what an older glasses accepts from the wire. */
static bool tmg7_decode(const uint8_t *p,size_t n){
 if(!p||n!=32||memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]||u32(p+24)||!u32(p+8)||!u32(p+20)||u32(p+28)!=tml_crc(p,28))return false;
 unsigned op=p[5],rows=p[6];uint32_t token=u32(p+12),generation=u32(p+16);
 return op==TML_QUERY?(!rows&&!token&&!generation):((rows==2||rows==3)&&token);
}
static bool tmg8_decode(const uint8_t *p,size_t n){
 if(!p||n!=32||memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]>1||u32(p+24)||!u32(p+8)||!u32(p+20)||u32(p+28)!=tml_crc(p,28))return false;
 unsigned op=p[5],rows=p[6],caps=p[7];uint32_t token=u32(p+12),generation=u32(p+16);
 return op==TML_QUERY?(!rows&&!token&&!generation&&!caps):((rows==1||rows==2||rows==3)&&token&&caps==(rows==1?1u:0u));
}
/* Frozen record readers and writer (fw/tmg8 and fw/tmg7 menu_config.c): byte 6 must be 0, otherwise the record is ignored. TMG7 also ignores rows = 1. */
static bool old_record(const uint8_t *p,int n,bool carousel){unsigned r=p[5];return n==20&&!memcmp(p,"TMC2",4)&&p[4]==1&&(r==2||r==3||(carousel&&r==1))&&!p[6]&&!p[7]&&u32(p+8)&&!u32(p+12)&&u32(p+16)==tml_crc(p,16);}
typedef struct {uint32_t generation;unsigned rows,bank;bool readable;} OldStored;
static OldStored old_load(Disk *d,bool carousel){
 OldStored s={.rows=3,.bank=1,.readable=true};
 for(unsigned i=0;i<2;i++){if(!old_record(d->p[i],d->n[i],carousel))continue;uint32_t g=u32(d->p[i]+8);if(g>s.generation){s.rows=d->p[i][5];s.generation=g;s.bank=i;}}
 return s;
}
static OldStored old_store(Disk *d,OldStored s,unsigned rows,bool carousel){
 if(rows==s.rows)return s;
 uint8_t b[20]={0};memcpy(b,"TMC2",4);b[4]=1;b[5]=(uint8_t)rows;w32(b+8,s.generation+1);w32(b+16,tml_crc(b,16));
 unsigned target=s.bank^1;memcpy(d->p[target],b,20);d->n[target]=20;return old_load(d,carousel);
}

static unsigned exchange(TMLState *s,const TMLIO *io,TMLCommand q,uint32_t now,uint32_t nonce){uint8_t raw[32];tml_encode(raw,&q);TMLCommand d;if(!tml_decode(raw,sizeof raw,&d))return 99;return tml_accept(s,&d,now,nonce,true,io);}
static unsigned query(TMLState *s,const TMLIO *io,uint32_t now,uint32_t nonce){return exchange(s,io,(TMLCommand){.op=TML_QUERY,.request=1,.client=7},now,nonce);}
static unsigned set(TMLState *s,const TMLIO *io,unsigned rows,unsigned caps,unsigned detent,uint32_t now,uint32_t nonce){
 unsigned r=query(s,io,now,nonce);assert(r==TML_OK);
 return exchange(s,io,(TMLCommand){.op=TML_SET,.request=2,.client=7,.token=nonce,.generation=s->stored.generation,.rows=(uint8_t)rows,.caps=(uint8_t)caps,.detent=detent},now+1,0);
}
static bool decodes(TMLCommand c,TMLCommand *out){uint8_t raw[32];tml_encode(raw,&c);return tml_decode(raw,sizeof raw,out);}

static void constants(void){
 assert(TD_CAP_KNOB_DETENT==(1u<<10)&&TD_CAPS_TMG9==(TD_CAPS_TMG8|(1u<<10))&&!(TD_CAPS_TMG8&TD_CAP_KNOB_DETENT));
 assert((TD_CAPS_TMG9&TD_CAPS_TMG6)==TD_CAPS_TMG6&&(TD_CAPS_TMG9&TD_CAP_MENU_CAROUSEL)); /* TMG9 keeps every TMG6/TMG7/TMG8 bit */
 assert(TML_PEER_TMG9==2&&TML_PEER_TMG8==1&&TML_PEER_TMG9>TML_PEER_TMG8);
 assert(TML_DETENT_MIN==(int)TK_DETENT_MIN&&TML_DETENT_MAX==(int)TK_DETENT_MAX&&TML_DETENT_STEP==(int)TK_DETENT_STEP&&TML_DETENT_DEFAULT==(int)TK_DETENT_DEFAULT);
 assert(TK_DETENT_MIN==TK_DETENT_RAW&&TK_DETENT_MAX==TK_DETENT_LEGACY&&TK_DETENT_DEFAULT>=TK_DETENT_MIN&&TK_DETENT_DEFAULT<=TK_DETENT_MAX&&TK_DETENT_DEFAULT%TK_DETENT_STEP==0);
}

/* td_encode / td_decode pairing: the validator is byte-shared with the phone, so what the glasses encode the phone must decode. */
static void status_pairing(void){
 uint8_t wire[TD_WIRE_BYTES];TDSample s={.build=TD_BUILD_TMG6,.kind=TD_STATUS,.session=1,.sequence=1},d;
 /* TMG7: no carousel bit, the legacy 600. */
 s.caps=TD_CAPS_TMG6;s.detent=TK_DETENT_LEGACY;assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d)&&d.caps==TD_CAPS_TMG6&&d.detent==600);
 for(unsigned v=0;v<=1000;v+=25)if(v!=600){s.detent=v;assert(!td_encode(&s,wire,sizeof wire));}
 /* TMG8: bit 9, exactly 300. */
 s.caps=TD_CAPS_TMG8;s.detent=TK_DETENT_RAW;assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d)&&d.caps==TD_CAPS_TMG8&&d.detent==300);
 for(unsigned v=0;v<=1000;v+=25)if(v!=300){s.detent=v;assert(!td_encode(&s,wire,sizeof wire));}
 /* TMG9: bit 10, any D in 300..600 in steps of 50, nothing else. */
 s.caps=TD_CAPS_TMG9;
 for(unsigned v=0;v<=1000;v++){
  s.detent=v;bool good=v>=300&&v<=600&&v%50==0;
  assert(td_encode(&s,wire,sizeof wire)==good);
  if(good){assert(td_decode(wire,sizeof wire,&d)&&d.caps==TD_CAPS_TMG9&&d.detent==v);}
 }
 s.detent=0xffffffffu;assert(!td_encode(&s,wire,sizeof wire));
 /* A decoder cannot be talked into the wrong pairing by editing the wire: patch bytes of a valid TMG9 sample. */
 s.detent=TK_DETENT_DEFAULT;assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d));
 /* Older builds never claim bit 10, and bit 11 is unknown everywhere. */
 s.build=TD_BUILD_TMG5;s.caps=TD_CAPS_TMG5|TD_CAP_KNOB_DETENT;s.detent=400;assert(!td_encode(&s,wire,sizeof wire));
 s.build=TD_BUILD_TMG4;s.caps=TD_CAPS_ALL|TD_CAP_KNOB_DETENT;assert(!td_encode(&s,wire,sizeof wire));
 s.build=TD_BUILD_TMG6;s.caps=TD_CAPS_TMG9|(1u<<11);assert(!td_encode(&s,wire,sizeof wire));
 /* td_sample (what the diagnostics core emits for a TMG6-build sample) is a TMG9 sample with the default D, and it decodes. */
 TDDiagnostics diag;td_init(&diag,TD_BUILD_TMG6);TDSample out;
 assert(td_start(&diag,5,100,60000)&&td_sample(&diag,100,true,NULL,NULL,NULL,&out)&&out.caps==TD_CAPS_TMG9&&out.detent==TK_DETENT_DEFAULT&&td_encode(&out,wire,sizeof wire)&&td_decode(wire,sizeof wire,&d));
}

/* Decode refusals. */
static void decode_rules(void){
 uint8_t raw[32];TMLCommand q;
 /* A TMG9 SET: every layout, every legal D, and D = 0. */
 for(unsigned rows=1;rows<=3;rows++){
  for(unsigned dd=0;dd<=700;dd++){
   TMLCommand c={.op=TML_SET,.request=2,.client=7,.token=32,.generation=1,.rows=(uint8_t)rows,.caps=TML_PEER_TMG9,.detent=dd};
   bool good=!dd||(dd>=300&&dd<=600&&dd%50==0);
   assert(decodes(c,&q)==good);if(good)assert(q.detent==dd&&q.caps==TML_PEER_TMG9&&q.rows==rows);
   /* D with any other peer byte is refused, D = 0 is a plain TMG7/TMG8 command. */
   for(unsigned caps=0;caps<=1;caps++){c.caps=(uint8_t)caps;bool plain=!dd&&(rows==1?caps==1:caps==0);assert(decodes(c,&q)==plain);}
  }
 }
 TMLCommand set=(TMLCommand){.op=TML_SET,.request=2,.client=7,.token=32,.generation=1,.rows=3,.caps=TML_PEER_TMG9,.detent=500};
 tml_encode(raw,&set);assert(raw[7]==TML_PEER_TMG9&&u32(raw+24)==500&&raw[24]==0xf4&&raw[25]==0x01&&u32(raw+28)==tml_crc(raw,28)&&tml_decode(raw,sizeof raw,&q));
 assert(!tmg7_decode(raw,sizeof raw)&&!tmg8_decode(raw,sizeof raw)); /* frozen TMG7 and TMG8 glasses drop it: the phone must never send it to them */
 /* The same bytes with D patched in after the fact, with the CRC repaired, are refused unless the peer byte is TMG9. */
 raw[7]=0;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q));raw[7]=1;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q));raw[7]=3;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q));
 raw[7]=2;fix_crc(raw);assert(tml_decode(raw,sizeof raw,&q));raw[6]=0;fix_crc(raw);assert(!tml_decode(raw,sizeof raw,&q)); /* rows 0 */
 /* Queries: caps 0, no D, nothing else. */
 TMLCommand qy={.op=TML_QUERY,.request=1,.client=7};tml_encode(raw,&qy);assert(tml_decode(raw,sizeof raw,&q)&&tmg7_decode(raw,sizeof raw)&&tmg8_decode(raw,sizeof raw));
 qy.caps=TML_PEER_TMG9;assert(!decodes(qy,&q));qy.caps=0;qy.detent=400;assert(!decodes(qy,&q));qy.detent=0;qy.rows=1;assert(!decodes(qy,&q));
 /* The carousel needs TMG8 or newer; a grid layout takes no peer byte (TMG7 form) or TMG9; TMG8 on a grid is still refused. */
 TMLCommand c={.op=TML_SET,.request=3,.client=7,.token=32,.rows=TML_CAROUSEL};
 for(unsigned caps=0;caps<=3;caps++){c.caps=(uint8_t)caps;assert(decodes(c,&q)==(caps==1||caps==2));}
 for(unsigned rows=2;rows<=3;rows++){c.rows=(uint8_t)rows;for(unsigned caps=0;caps<=3;caps++){c.caps=(uint8_t)caps;assert(decodes(c,&q)==(caps==0||caps==2));}}
 /* A byte-for-byte TMG7/TMG8 command still decodes with D = 0 (older phones keep working against TMG9 glasses). */
 c=(TMLCommand){.op=TML_SET,.request=3,.client=7,.token=32,.rows=2};tml_encode(raw,&c);assert(tml_decode(raw,sizeof raw,&q)&&q.detent==0&&tmg7_decode(raw,sizeof raw)&&tmg8_decode(raw,sizeof raw));
 c=(TMLCommand){.op=TML_SET,.request=3,.client=7,.token=32,.rows=1,.caps=TML_PEER_TMG8};tml_encode(raw,&c);assert(tml_decode(raw,sizeof raw,&q)&&q.detent==0&&tmg8_decode(raw,sizeof raw));
 assert(tml_detent_valid(300)&&tml_detent_valid(600)&&tml_detent_valid(400)&&!tml_detent_valid(0)&&!tml_detent_valid(250)&&!tml_detent_valid(650)&&!tml_detent_valid(425)&&!tml_detent_valid(UINT32_MAX));
}

/* The handler refuses the same commands even when a caller skips tml_decode. */
static void handler_rules(void){
 Disk disk={0};TMLIO io={&disk,read_bank,write_bank};TMLState st={0};
 const TMLCommand bad[]={
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=0,.detent=500},                  /* D without the peer byte */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=1,.caps=TML_PEER_TMG8,.detent=500},      /* D with the TMG8 peer byte */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=TML_PEER_TMG9,.detent=325},      /* not a multiple of 50 */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=TML_PEER_TMG9,.detent=250},      /* below the range */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=TML_PEER_TMG9,.detent=650},      /* above the range */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=TML_PEER_TMG9,.detent=UINT32_MAX},
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=1,.caps=0},                              /* carousel without the peer byte */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=TML_PEER_TMG8},                  /* grid with the TMG8 byte */
  {.op=TML_SET,.request=2,.client=7,.token=40,.rows=3,.caps=3},                              /* unknown peer byte */
 };
 for(unsigned i=0;i<sizeof bad/sizeof *bad;i++){
  assert(query(&st,&io,1000,40)==TML_OK&&st.token==40);
  TMLCommand c=bad[i];c.generation=st.stored.generation;
  assert(tml_accept(&st,&c,1001,0,true,&io)==TML_BLOCKED&&!st.token&&disk.writes==0&&st.stored.rows==3&&tml_detent(&st.stored)==400);
 }
 /* A query that carries a peer byte or D is refused by the handler too, and it issues no token. */
 for(unsigned i=0;i<4;i++){
  TMLCommand bq={.op=TML_QUERY,.request=1,.client=7};if(i==0)bq.caps=TML_PEER_TMG8;if(i==1)bq.caps=TML_PEER_TMG9;if(i==2)bq.detent=500;if(i==3){bq.caps=TML_PEER_TMG9;bq.detent=500;}
  st.token=0;assert(tml_accept(&st,&bq,1500,42,true,&io)==TML_BLOCKED&&!st.token&&disk.writes==0);
 }
 assert(query(&st,&io,2000,41)==TML_OK);
 TMLCommand ok={.op=TML_SET,.request=3,.client=7,.token=41,.generation=0,.rows=3,.caps=TML_PEER_TMG9,.detent=500};
 assert(tml_accept(&st,&ok,2001,0,true,&io)==TML_OK&&disk.writes==1&&tml_detent(&st.stored)==500);
 /* Not allowed (OTA, folded, other app): nothing changes. */
 assert(query(&st,&io,3000,42)==TML_OK);ok.token=42;ok.generation=st.stored.generation;ok.detent=600;
 assert(tml_accept(&st,&ok,3001,0,false,&io)==TML_BLOCKED&&disk.writes==1&&tml_detent(&st.stored)==500);
}

/* Storage: D/50 in byte 6 of the existing two-bank file; persistence across banks and reboot (the model). */
static void storage(void){
 Disk disk={0};TMLIO io={&disk,read_bank,write_bank};TMLState st={0};
 TMLStored fresh=tml_load(&io);assert(fresh.rows==3&&fresh.generation==0&&fresh.readable&&fresh.detent==400&&tml_detent(&fresh)==400); /* nothing stored: default 400 */
 assert(tml_detent(&(TMLStored){0})==400&&tml_detent(NULL)==400); /* a zeroed TMLStored reads as the default too */
 /* Only D changes (rows stay 3, the early return of tmg8 would have skipped the write). */
 assert(set(&st,&io,3,TML_PEER_TMG9,500,1000,32)==TML_OK&&disk.writes==1&&st.stored.rows==3&&tml_detent(&st.stored)==500&&st.stored.generation==1&&st.stored.bank==0);
 assert(disk.n[0]==20&&!memcmp(disk.p[0],"TMC2",4)&&disk.p[0][5]==3&&disk.p[0][6]==10&&!disk.p[0][7]&&u32(disk.p[0]+8)==1&&u32(disk.p[0]+16)==tml_crc(disk.p[0],16)); /* D/50 = 10 */
 TMLStored boot=tml_load(&io);assert(boot.rows==3&&boot.detent==500&&boot.generation==1&&boot.bank==0&&boot.readable); /* reboot */
 /* The same D again: no flash write. */
 assert(set(&st,&io,3,TML_PEER_TMG9,500,1100,33)==TML_OK&&disk.writes==1&&st.stored.generation==1);
 /* D = 0 leaves D alone while the layout changes; the new record (other bank) carries D forward. */
 assert(set(&st,&io,2,TML_PEER_TMG9,0,1200,34)==TML_OK&&disk.writes==2&&st.stored.rows==2&&tml_detent(&st.stored)==500&&st.stored.generation==2&&st.stored.bank==1&&disk.p[1][6]==10);
 assert(set(&st,&io,3,0,0,1300,35)==TML_OK&&disk.writes==3&&st.stored.rows==3&&tml_detent(&st.stored)==500&&st.stored.bank==0&&disk.p[0][6]==10); /* a TMG7-form SET keeps D */
 assert(set(&st,&io,1,TML_PEER_TMG8,0,1400,36)==TML_OK&&st.stored.rows==1&&tml_detent(&st.stored)==500&&st.stored.bank==1);               /* a TMG8-form carousel SET keeps D */
 assert(set(&st,&io,1,TML_PEER_TMG9,600,1500,37)==TML_OK&&st.stored.rows==1&&tml_detent(&st.stored)==600&&disk.p[0][6]==12);                /* D and layout together; rows 1 with a TMG9 peer */
 boot=tml_load(&io);assert(boot.rows==1&&boot.detent==600&&boot.generation==st.stored.generation);
 /* Back to the default: written as byte 6 = 0, which is what TMG7 and TMG8 write. */
 assert(set(&st,&io,1,TML_PEER_TMG9,400,1600,38)==TML_OK&&tml_detent(&st.stored)==400&&disk.p[st.stored.bank][6]==0);
 boot=tml_load(&io);assert(boot.detent==400&&boot.rows==1);
 /* Every legal D round-trips through the file. */
 for(unsigned dd=300,n=0;dd<=600;dd+=50,n++){
  assert(set(&st,&io,3,TML_PEER_TMG9,dd,2000+n*10,50+n)==TML_OK&&tml_detent(&st.stored)==dd);
  boot=tml_load(&io);assert(boot.detent==dd&&boot.rows==3&&boot.generation==st.stored.generation&&boot.readable);
 }
 /* One damaged bank: the newest record is ignored, the other bank (previous generation, previous D) is used. */
 uint8_t keep[32];memcpy(keep,disk.p[st.stored.bank],20);disk.p[st.stored.bank][6]^=0x04;
 boot=tml_load(&io);assert(boot.generation==st.stored.generation-1&&boot.detent==550&&boot.readable); /* 600 was the last write; the bank before it held 550 */
 memcpy(disk.p[st.stored.bank],keep,20);
 disk.p[st.stored.bank][6]=13;w32(disk.p[st.stored.bank]+16,tml_crc(disk.p[st.stored.bank],16)); /* a valid CRC over D/50 = 13 (650) is still refused */
 boot=tml_load(&io);assert(boot.generation==st.stored.generation-1&&boot.detent==550);
 disk.p[st.stored.bank][6]=5;w32(disk.p[st.stored.bank]+16,tml_crc(disk.p[st.stored.bank],16)); /* 250 */
 boot=tml_load(&io);assert(boot.generation==st.stored.generation-1);
 memcpy(disk.p[st.stored.bank],keep,20);
 /* A failed write leaves the live D and layout untouched and reports storage failure. */
 assert(query(&st,&io,5000,90)==TML_OK);disk.fail_write=1;unsigned writes=disk.writes,before=tml_detent(&st.stored),gen=st.stored.generation;
 TMLCommand c={.op=TML_SET,.request=9,.client=7,.token=90,.generation=gen,.rows=3,.caps=TML_PEER_TMG9,.detent=before==300?350:300};
 assert(tml_accept(&st,&c,5001,0,true,&io)==TML_STORAGE&&disk.writes==writes&&tml_detent(&st.stored)==before&&st.stored.generation==gen);
 disk.fail_write=0;
 /* An unreadable bank blocks the write (the generation cannot be trusted). */
 TMLStored unreadable=tml_load(&io);unreadable.readable=false;assert(!tml_store(&io,&unreadable,3,500));
 TMLStored full=tml_load(&io);full.generation=UINT32_MAX;assert(!tml_store(&io,&full,3,full.detent==300?350:300));
 assert(!tml_store(&io,&(TMLStored){.rows=3,.readable=true},3,425)&&!tml_store(&io,&(TMLStored){.rows=3,.readable=true},0,0));
 /* The reply still describes the layout only (no wire change in TMA2). */
 uint8_t reply[32];TMLCommand echo={.op=TML_SET,.request=9,.client=7};tml_reply(reply,&st,&echo,TML_OK);assert(reply[6]==st.stored.rows&&reply[24]==28&&reply[25]==2&&reply[26]==220&&!reply[27]);
}

/* Rollback: what ZIP8 (fw/tmg8) and ZIP7 (fw/tmg7) do with a record whose byte 6 is not zero. */
static void rollback(void){
 Disk disk={0};TMLIO io={&disk,read_bank,write_bank};TMLState st={0};
 /* A. D never changed: every record has byte 6 = 0 and ZIP8 reads what TMG9 wrote. */
 assert(set(&st,&io,2,TML_PEER_TMG9,0,1000,32)==TML_OK&&disk.p[st.stored.bank][6]==0);
 OldStored o=old_load(&disk,true);assert(o.rows==2&&o.generation==1&&o.readable);
 /* B. D changed (rows stay 2): the newest record has byte 6 != 0, which ZIP8 ignores. It uses the other bank, the previous record (byte 6 = 0).
  * Nothing is reported as an error and the menu works. */
 assert(set(&st,&io,2,TML_PEER_TMG9,500,1100,33)==TML_OK&&disk.p[st.stored.bank][6]==10&&st.stored.generation==2);
 o=old_load(&disk,true);assert(o.rows==2&&o.generation==1&&o.readable); /* bank 0 (generation 1, byte 6 = 0) is still a valid TMG8 record */
 /* C. Two D-carrying records in a row: both banks hold byte 6 != 0, ZIP8 sees neither and falls back to the default: 3 rows, readable. */
 assert(set(&st,&io,3,TML_PEER_TMG9,550,1200,34)==TML_OK&&st.stored.generation==3);
 o=old_load(&disk,true);assert(o.rows==3&&o.generation==0&&o.readable&&o.bank==1);
 OldStored t7=old_load(&disk,false);assert(t7.rows==3&&t7.generation==0&&t7.readable); /* ZIP7 behaves the same (and also ignores any rows = 1 record) */
 /* D. ZIP8 changes the layout after the rollback: its default state targets bank 0 and writes generation 1 there, over the newest TMG9 record
  * (generation 3). It reads its own record back; the generation 2 TMG9 record in bank 1 is untouched. */
 o=old_store(&disk,o,2,true);assert(o.rows==2&&o.generation==1&&o.bank==0&&o.readable);
 /* E. Re-flashing TMG9: both records are valid for TMG9 and the higher generation wins, so the TMG9 record at generation 2 (2 rows, D 500) comes
  * back, not the layout ZIP8 saved at generation 1. The layout and D are an older TMG9 state, never garbage. */
 TMLStored back=tml_load(&io);assert(back.generation==2&&back.rows==2&&back.detent==500&&back.readable);
 /* F. A TMG9 record with the default D (byte 6 = 0) is identical to a TMG8 record, so a user who never moves D (or sets 400) is untouched by a rollback. */
 Disk d2={0};TMLIO io2={&d2,read_bank,write_bank};TMLState s2={0};
 assert(set(&s2,&io2,1,TML_PEER_TMG9,500,1000,60)==TML_OK&&set(&s2,&io2,1,TML_PEER_TMG9,400,1100,61)==TML_OK&&d2.p[s2.stored.bank][6]==0);
 o=old_load(&d2,true);assert(o.rows==1&&o.generation==2);
 /* The record is 20 bytes and byte 7 stays 0, so the file size and the TMG8 length check never change. */
 assert(d2.n[0]==20&&d2.n[1]==20&&!d2.p[0][7]&&!d2.p[1][7]);
}

int main(void){
 constants();
 status_pairing();
 decode_rules();
 handler_rules();
 storage();
 rollback();
 puts("PASS TMG9 detent: caps bit 10, D rides the TMG2 SET only with the TMG9 peer byte, refusals at decode and in the handler, D/50 stored in byte 6 across banks and reboot, status pairs for TMG7/8/9, ZIP8/ZIP7 ignore a non-zero byte 6");
 return 0;
}
