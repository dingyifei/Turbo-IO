// Host test for the TLK:/TKA: codec, the token session and the command service (docs/lock-design.md §5).
#include "../src/lock-v1/lock_service.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t bytes[2][TLR_BYTES+1];int n[2];bool fail;} Disk;
static int rd(void *ctx,unsigned b,uint8_t *p,size_t cap){Disk *d=ctx;(void)cap;if(d->n[b]<0)return 0;memcpy(p,d->bytes[b],(size_t)d->n[b]);return d->n[b];}
static bool wr(void *ctx,unsigned b,const uint8_t *p,size_t n){Disk *d=ctx;if(d->fail)return false;memcpy(d->bytes[b],p,n);d->n[b]=(int)n;return true;}
static const uint8_t SALT[8]={1,2,3,4,5,6,7,8};
static uint32_t req=1;
static unsigned cmd(TLKService *s,const TLRIO *io,uint8_t op,uint32_t token,uint32_t client,uint32_t ms,TLKReply *r,const TLKCommand *extra,bool allowed){
 TLKCommand q={0};if(extra)q=*extra;q.op=op;q.token=token;q.client=client;q.request=req++;
 // Round-trip through the wire form, as the phone would send it.
 uint8_t raw[32],wire[74],back[32];tlk_encode(raw,&q);assert(tlk_carrier(wire,raw,false)==74&&tlk_uncarrier(wire,74,back,false)&&!memcmp(raw,back,32));
 TLKCommand d;assert(tlk_decode(back,32,&d));
 unsigned res=tlk_service_command(s,&d,r,ms,1000000+ms/1000,0xabcd0000u+ms,SALT,allowed,io);
 uint8_t rr[32],rw[74],rb[32];tlk_reply_encode(rr,r);tlk_carrier(rw,rr,true);assert(tlk_uncarrier(rw,74,rb,true));TLKReply rd2;assert(tlk_reply_decode(rb,32,&rd2)&&!memcmp(&rd2,r,sizeof rd2));
 assert(r->result==res&&r->request==q.request);return res;
}
static uint32_t query(TLKService *s,const TLRIO *io,uint32_t client,uint32_t ms,TLKReply *r){assert(cmd(s,io,TLK_OP_QUERY,0,client,ms,r,NULL,true)==TLK_R_OK&&r->token);return r->token;}
int main(void){
 // Codec bounds.
 uint8_t raw[32],wire[74];TLKCommand q={.op=TLK_OP_SET_PIN,.request=1,.token=5,.client=9,.pin={9,0,0,7}},o;tlk_encode(raw,&q);assert(raw[22]==0x90&&raw[23]==0x07&&tlk_decode(raw,32,&o)&&o.pin[0]==9&&o.pin[3]==7);
 for(unsigned i=0;i<32;i++)for(unsigned b=0;b<8;b++){uint8_t x[32];memcpy(x,raw,32);x[i]^=1u<<b;assert(!tlk_decode(x,32,&o));}
 raw[22]=0xa0;raw[28]=0;{uint32_t c=tlk_crc(raw,28);for(unsigned i=0;i<4;i++)raw[28+i]=(uint8_t)(c>>(8*i));}assert(!tlk_decode(raw,32,&o));  // BCD digit > 9
 TLKCommand bad={.op=TLK_OP_QUERY,.request=1,.token=3,.client=9};tlk_encode(raw,&bad);assert(!tlk_decode(raw,32,&o));      // QUERY with a token
 bad=(TLKCommand){.op=TLK_OP_UNLOCK,.request=1,.client=9};tlk_encode(raw,&bad);assert(!tlk_decode(raw,32,&o));             // op without a token
 bad=(TLKCommand){.op=TLK_OP_SET_TIME,.request=1,.token=1,.client=9,.fold_min=0,.idle_min=5};tlk_encode(raw,&bad);assert(!tlk_decode(raw,32,&o));
 bad.fold_min=241;tlk_encode(raw,&bad);assert(!tlk_decode(raw,32,&o));bad.fold_min=240;tlk_encode(raw,&bad);assert(tlk_decode(raw,32,&o));
 bad=(TLKCommand){.op=TLK_OP_LAST+1,.request=1,.token=1,.client=9};tlk_encode(raw,&bad);assert(!tlk_decode(raw,32,&o));
 // Carrier: tags are TLK:/TKA:, never the language family's TLG:/TLA:.
 tlk_encode(raw,&q);tlk_carrier(wire,raw,false);assert(!memcmp(wire+6,"TLK:",4));uint8_t back[32];assert(!tlk_uncarrier(wire,74,back,true));
 tlk_carrier(wire,raw,true);assert(!memcmp(wire+6,"TKA:",4));memcpy(wire+6,"TLA:",4);assert(!tlk_uncarrier(wire,74,back,true));
 tlk_carrier(wire,raw,false);wire[20]='G';assert(!tlk_uncarrier(wire,74,back,false));assert(!tlk_uncarrier(wire,73,back,false));
 // Service: start with no file (Off).
 Disk d={.n={-1,-1}};TLRIO io={&d,rd,wr};TLKService s;tlk_service_boot(&s,&io);assert(s.lock.state==TLK_OFF);TLKReply r;
 uint32_t tok=query(&s,&io,77,1000,&r);assert(r.flags==0&&r.fold_min==5&&r.idle_min==5);
 // Good token: SET_PIN enables the lock and writes the record.
 TLKCommand pin={.pin={1,2,3,4}};assert(cmd(&s,&io,TLK_OP_SET_PIN,tok,77,2000,&r,&pin,true)==TLK_R_OK&&(r.flags&TLK_F_ENABLED)&&!(r.flags&TLK_F_LOCKED)&&d.n[0]==TLR_BYTES);
 // Replayed token (used once), wrong client, expired token (>120 s), wrong token: SESSION.
 assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok,77,3000,&r,NULL,true)==TLK_R_SESSION&&!(r.flags&TLK_F_LOCKED));
 tok=query(&s,&io,77,4000,&r);assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok,78,5000,&r,NULL,true)==TLK_R_SESSION);
 tok=query(&s,&io,77,6000,&r);assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok,77,6000+TLK_TOKEN_MS+1,&r,NULL,true)==TLK_R_SESSION);
 tok=query(&s,&io,77,7000,&r);assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok+1,77,7001,&r,NULL,true)==TLK_R_SESSION);
 assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok,77,7002,&r,NULL,true)==TLK_R_SESSION);   // a refused try also spends the token
 tok=query(&s,&io,77,8000,&r);assert(cmd(&s,&io,TLK_OP_LOCK_NOW,tok,77,8000+TLK_TOKEN_MS,&r,NULL,true)==TLK_R_OK&&(r.flags&TLK_F_LOCKED));
 // Gate closed (OTA running, not bonded or not connected): BLOCKED, and an issued token dies.
 tok=query(&s,&io,77,9000,&r);assert(cmd(&s,&io,TLK_OP_QUERY,0,77,9100,&r,NULL,false)==TLK_R_BLOCKED);assert(cmd(&s,&io,TLK_OP_UNLOCK,tok,77,9200,&r,NULL,true)==TLK_R_SESSION);
 // Unlock, wrong tries reported, ACK clears the phone count.
 s.lock.rec.wrong=3;s.lock.rec.unacked=3;s.lock.rec.delay_until=0;
 tok=query(&s,&io,77,10000,&r);assert(r.wrong==3&&r.unacked==3&&r.delay_left==30&&(r.flags&TLK_F_LOCKED));
 assert(cmd(&s,&io,TLK_OP_UNLOCK,tok,77,10100,&r,NULL,true)==TLK_R_OK&&!(r.flags&TLK_F_LOCKED)&&r.wrong==0&&r.unacked==3&&r.delay_left==0&&s.lock.state==TLK_NOTICE);
 tok=query(&s,&io,77,11000,&r);assert(cmd(&s,&io,TLK_OP_ACK_FAILURES,tok,77,11100,&r,NULL,true)==TLK_R_OK&&r.unacked==0);
 // SET_TIME, then the record survives a reboot.
 TLKCommand tm={.fold_min=1,.idle_min=240};tok=query(&s,&io,77,12000,&r);assert(cmd(&s,&io,TLK_OP_SET_TIME,tok,77,12100,&r,&tm,true)==TLK_R_OK&&r.fold_min==1&&r.idle_min==240);
 tlk_service_boot(&s,&io);assert(s.lock.state==TLK_DARK&&s.lock.rec.fold_min==1&&s.lock.rec.idle_min==240&&s.lock.rec.unacked==0);
 // MOTION_ON is refused until the Bluetooth-image hook exists (milestone 3).
 tok=query(&s,&io,77,13000,&r);assert(!(r.flags&TLK_F_MOTION_SUPPORTED));assert(cmd(&s,&io,TLK_OP_MOTION_ON,tok,77,13100,&r,NULL,true)==TLK_R_REFUSED&&!(r.flags&TLK_F_MOTION));
 // Storage failure is reported; the next successful write catches up.
 d.fail=true;tok=query(&s,&io,77,14000,&r);assert(cmd(&s,&io,TLK_OP_SET_TIME,tok,77,14100,&r,&(TLKCommand){.fold_min=7,.idle_min=7},true)==TLK_R_STORAGE&&s.lock.dirty);
 d.fail=false;assert(tlk_service_persist(&s,&io)&&!s.lock.dirty);tlk_service_boot(&s,&io);assert(s.lock.rec.fold_min==7);
 // DISABLE: Off, record kept with enabled=0; a reboot stays Off.
 tok=query(&s,&io,77,15000,&r);assert(cmd(&s,&io,TLK_OP_DISABLE,tok,77,15100,&r,NULL,true)==TLK_R_OK&&r.flags==0);tlk_service_boot(&s,&io);assert(s.lock.state==TLK_OFF&&d.n[0]>0&&d.n[1]>0);
 // UNLOCK / LOCK_NOW while Off: refused.
 tok=query(&s,&io,77,16000,&r);assert(cmd(&s,&io,TLK_OP_UNLOCK,tok,77,16100,&r,NULL,true)==TLK_R_REFUSED);
 // Damaged record: locked, flagged, phone unlock works, SET_TIME refused, SET_PIN repairs.
 d.bytes[0][9]^=1;d.bytes[1][9]^=1;tlk_service_boot(&s,&io);assert(s.lock.state==TLK_DARK&&s.lock.damaged);
 tok=query(&s,&io,77,17000,&r);assert((r.flags&TLK_F_DAMAGED)&&(r.flags&TLK_F_LOCKED));
 assert(cmd(&s,&io,TLK_OP_SET_TIME,tok,77,17100,&r,&tm,true)==TLK_R_REFUSED);
 tok=query(&s,&io,77,18000,&r);assert(cmd(&s,&io,TLK_OP_UNLOCK,tok,77,18100,&r,NULL,true)==TLK_R_OK&&!(r.flags&TLK_F_LOCKED));
 tok=query(&s,&io,77,19000,&r);assert(cmd(&s,&io,TLK_OP_SET_PIN,tok,77,19100,&r,&pin,true)==TLK_R_OK&&!(r.flags&TLK_F_DAMAGED));
 tlk_service_boot(&s,&io);assert(s.lock.state==TLK_DARK&&!s.lock.damaged);
 // A nonce source failure: UNAVAILABLE and no token.
 TLKCommand qq={.op=TLK_OP_QUERY,.request=5,.client=1};assert(tlk_service_command(&s,&qq,&r,1,1,0,SALT,true,&io)==TLK_R_UNAVAILABLE&&!r.token);
 puts("PASS lock_codec: TLK:/TKA: wire bounds and tags, good/replayed/expired/foreign tokens, gate, every op, damaged record, storage faults");
}
