// Host test for the lock record: the start-up table (docs/lock-design.md §8), bank choice, faults and fuzz.
#include "../src/lock-v1/lock_store.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
// n = -2 means the file does not exist (the IO returns 0), -1 a read error, 0 an existing empty file (the IO returns -1).
typedef struct {uint8_t bytes[2][TLR_BYTES+4];int n[2];int fail;unsigned writes;} Disk;
static int rd(void *ctx,unsigned b,uint8_t *p,size_t cap){Disk *d=ctx;assert(b<2&&cap==TLR_BYTES+1);if(d->n[b]==-2)return 0;if(d->n[b]<=0)return -1;size_t n=(size_t)d->n[b];if(n>cap)n=cap;memcpy(p,d->bytes[b],n);return (int)n;}
static bool wr(void *ctx,unsigned b,const uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==TLR_BYTES);d->writes++;if(d->fail==1)return false;memcpy(d->bytes[b],p,n);d->n[b]=(int)n;if(d->fail==2)d->bytes[b][5]^=1;return d->fail!=3;}
static TLKRecord rec(bool enabled){TLKRecord r;tlk_record_default(&r);r.enabled=enabled;memset(r.salt,7,8);memset(r.hash,9,8);r.wrong=4;r.unacked=6;r.delay_until=123456;r.fold_min=10;r.idle_min=240;return r;}
static void put(Disk *d,unsigned b,const TLKRecord *r,uint32_t g){tlr_encode(d->bytes[b],r,g);d->n[b]=TLR_BYTES;}
static Disk empty(void){Disk d={0};d.n[0]=d.n[1]=-2;return d;}
int main(void){
 TLKRecord r=rec(true),out;TLRStored st;Disk d=empty();TLRIO io={&d,rd,wr};
 // Start-up table.
 assert(tlr_load(&io,&out,&st)==TLK_LOAD_NONE&&st.generation==0);                     // no file: Off
 put(&d,0,&r,1);assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&out.enabled&&st.bank==0&&st.generation==1);
 assert(!memcmp(out.salt,r.salt,8)&&!memcmp(out.hash,r.hash,8)&&out.wrong==4&&out.unacked==6&&out.delay_until==123456&&out.fold_min==10&&out.idle_min==240);
 TLKRecord off=rec(false);put(&d,1,&off,2);assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&!out.enabled&&st.bank==1);   // newest wins
 // Both damaged, one damaged + one missing, read errors, an existing empty file: all fail closed.
 d=empty();put(&d,0,&r,1);d.bytes[0][40]^=1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 put(&d,1,&r,1);d.bytes[1][44]^=1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 d=empty();d.n[0]=-1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 d=empty();d.n[0]=0;d.n[1]=0;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 d=empty();d.n[1]=-1;d.n[0]=-1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 // One good bank survives a damaged or unreadable other bank.
 d=empty();put(&d,0,&r,5);d.n[1]=-1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&st.generation==5);
 put(&d,1,&r,6);d.bytes[1][3]='X';assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&st.bank==0);
 // Same generation, different content, and the ambiguous half-range gap: damaged.
 d=empty();put(&d,0,&r,9);put(&d,1,&off,9);assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 put(&d,1,&r,9);assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD);
 put(&d,1,&off,9u+0x80000000u);assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);
 // Generation wrap: UINT32_MAX then 1.
 d=empty();put(&d,0,&r,UINT32_MAX);put(&d,1,&off,1);assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&st.bank==1);
 // Field bounds: minutes 0 / 241, flags > 1, nonzero padding, zero generation, wrong length, every single-bit flip.
 uint8_t raw[TLR_BYTES];uint32_t g;tlr_encode(raw,&r,3);assert(tlr_decode(raw,TLR_BYTES,&out,&g)&&g==3);
 for(unsigned i=0;i<TLR_BYTES;i++)for(unsigned bit=0;bit<8;bit++){uint8_t x[TLR_BYTES];memcpy(x,raw,sizeof x);x[i]^=1u<<bit;TLKRecord o;assert(!tlr_decode(x,TLR_BYTES,&o,&g));}
 for(int n=0;n<=TLR_BYTES+1;n++)if(n!=TLR_BYTES)assert(!tlr_decode(raw,n,&out,&g));
 TLKRecord bad=r;bad.fold_min=0;tlr_encode(raw,&bad,3);assert(!tlr_decode(raw,TLR_BYTES,&out,&g));
 bad=r;bad.idle_min=241;tlr_encode(raw,&bad,3);assert(!tlr_decode(raw,TLR_BYTES,&out,&g));
 tlr_encode(raw,&r,0);assert(!tlr_decode(raw,TLR_BYTES,&out,&g));
 // Store: first write goes to bank 0 at generation 1, then alternates; unchanged records are skipped.
 d=empty();st=(TLRStored){0,1};assert(tlr_store(&io,&st,&r)&&st.bank==0&&st.generation==1&&d.writes==1);
 assert(tlr_store(&io,&st,&r)&&d.writes==1);
 assert(tlr_store(&io,&st,&off)&&st.bank==1&&st.generation==2&&tlr_load(&io,&out,&st)==TLK_LOAD_GOOD&&!out.enabled);
 // Disabling writes enabled=0; it never removes a file, so "no file" cannot come from normal use.
 assert(d.n[0]==TLR_BYTES&&d.n[1]==TLR_BYTES);
 // A damaged pair is replaced by the first good write (SET_PIN / DISABLE from the phone).
 d=empty();d.n[0]=0;d.n[1]=-1;assert(tlr_load(&io,&out,&st)==TLK_LOAD_DAMAGED);assert(tlr_store(&io,&st,&r)&&tlr_load(&io,&out,&st)==TLK_LOAD_GOOD);
 // Write faults: refused write, corrupted write, write that reports failure; the older bank keeps the old record.
 for(int f=1;f<=3;f++){d=empty();put(&d,0,&r,4);d.fail=f;tlr_load(&io,&out,&st);assert(!tlr_store(&io,&st,&off));d.fail=0;assert(tlr_load(&io,&out,&st)==TLK_LOAD_GOOD);assert(f==3?!out.enabled:out.enabled);}
 // Fuzz: random bytes never decode with side effects.
 uint32_t seed=13;for(unsigned i=0;i<50000;i++){uint8_t x[TLR_BYTES];for(unsigned j=0;j<TLR_BYTES;j++){seed=seed*1664525u+1013904223u;x[j]=(uint8_t)(seed>>24);}TLKRecord o;memset(&o,0x5a,sizeof o);TLKRecord before=o;if(!tlr_decode(x,TLR_BYTES,&o,&g))assert(!memcmp(&before,&o,sizeof o));}
 assert(tlr_load(NULL,&out,&st)==TLK_LOAD_DAMAGED);
 puts("PASS lock_store: start-up table (none/good/damaged), bank choice and wrap, ambiguous generations, bounds and bit flips, store faults, fuzz");
}
