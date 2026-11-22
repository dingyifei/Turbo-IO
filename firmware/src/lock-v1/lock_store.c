#include "lock_store.h"
#include <string.h>
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
uint32_t tlr_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
/* Layout (little-endian): 0 "TLR1" | 4 version 1 | 5 flags (bit 0 enabled) | 6 fold min | 7 idle min | 8 generation (nonzero)
 * | 12 salt[8] | 20 hash[8] | 28 wrong | 29 unacked | 30..31 zero | 32 delay_until | 36..43 zero | 44 CRC-32 of 0..43 */
void tlr_encode(uint8_t *p,const TLKRecord *r,uint32_t generation){
 memset(p,0,TLR_BYTES);memcpy(p,"TLR1",4);p[4]=1;p[5]=r->enabled?1:0;p[6]=r->fold_min;p[7]=r->idle_min;put32(p+8,generation);
 memcpy(p+12,r->salt,TLK_SALT_LEN);memcpy(p+20,r->hash,TLK_HASH_LEN);p[28]=r->wrong;p[29]=r->unacked;put32(p+32,r->delay_until);put32(p+44,tlr_crc(p,44));
}
static bool minutes(unsigned m){return m>=TLK_MINUTES_MIN&&m<=TLK_MINUTES_MAX;}
bool tlr_decode(const uint8_t *p,int n,TLKRecord *out,uint32_t *generation){
 if(!p||!out||!generation||n!=TLR_BYTES||memcmp(p,"TLR1",4)||p[4]!=1||p[5]>1||!minutes(p[6])||!minutes(p[7])||!get32(p+8)||p[30]||p[31])return false;
 for(unsigned i=36;i<44;i++)if(p[i])return false;
 if(get32(p+44)!=tlr_crc(p,44))return false;
 TLKRecord r;tlk_record_default(&r);r.enabled=p[5];r.fold_min=p[6];r.idle_min=p[7];memcpy(r.salt,p+12,TLK_SALT_LEN);memcpy(r.hash,p+20,TLK_HASH_LEN);
 r.wrong=p[28];r.unacked=p[29];r.delay_until=get32(p+32);*out=r;*generation=get32(p+8);return true;
}
TLKLoad tlr_load(const TLRIO *io,TLKRecord *out,TLRStored *st){
 TLRStored s={0,1};if(st)*st=s;if(!io||!io->read||!out)return TLK_LOAD_DAMAGED;
 TLKRecord rec[2];uint32_t gen[2]={0,0};bool valid[2]={false,false},missing[2]={false,false};uint8_t raw[TLR_BYTES+1];
 for(unsigned b=0;b<2;b++){int n=io->read(io->ctx,b,raw,sizeof raw);missing[b]=n==0;valid[b]=n>0&&tlr_decode(raw,n,&rec[b],&gen[b]);}
 if(missing[0]&&missing[1])return TLK_LOAD_NONE;   // no file: an upgrade from a release without the lock
 unsigned chosen;
 if(valid[0]&&valid[1]){
  uint32_t d=gen[0]-gen[1];
  if(d==0){uint8_t a[TLR_BYTES],b[TLR_BYTES];tlr_encode(a,&rec[0],gen[0]);tlr_encode(b,&rec[1],gen[1]);if(memcmp(a,b,TLR_BYTES))return TLK_LOAD_DAMAGED;chosen=0;}
  else if(d==0x80000000u)return TLK_LOAD_DAMAGED;
  else chosen=d<0x80000000u?0:1;
 }else if(valid[0])chosen=0;else if(valid[1])chosen=1;else return TLK_LOAD_DAMAGED;
 *out=rec[chosen];if(st){st->generation=gen[chosen];st->bank=chosen;}return TLK_LOAD_GOOD;
}
bool tlr_store(const TLRIO *io,TLRStored *s,const TLKRecord *r){
 if(!io||!io->write||!io->read||!s||!r)return false;
 uint8_t raw[TLR_BYTES];
 if(s->generation){TLKRecord cur;TLRStored cs;if(tlr_load(io,&cur,&cs)==TLK_LOAD_GOOD&&cs.generation==s->generation){uint8_t a[TLR_BYTES];tlr_encode(a,&cur,1);tlr_encode(raw,r,1);if(!memcmp(a,raw,TLR_BYTES))return true;}}
 uint32_t generation=s->generation+1;if(!generation)generation=1;unsigned bank=s->bank^1u;if(bank>1)return false;
 tlr_encode(raw,r,generation);bool wrote=io->write(io->ctx,bank,raw,sizeof raw);
 TLKRecord back;TLRStored bs;if(tlr_load(io,&back,&bs)!=TLK_LOAD_GOOD)return false;
 *s=bs;uint8_t a[TLR_BYTES];tlr_encode(a,&back,generation);return wrote&&bs.generation==generation&&bs.bank==bank&&!memcmp(a,raw,TLR_BYTES);
}
