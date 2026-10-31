#include "../src/global-remote-v1/lang_store.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
typedef struct {uint8_t bytes[2][24];int n[2],error[2],fail;unsigned reads,writes;} Disk;
static int read_bank(void *ctx,unsigned b,uint8_t *p,size_t cap){Disk *d=ctx;assert(b<2&&cap==21);d->reads++;if(d->error[b])return -1;size_t n=(unsigned)d->n[b];if(n>cap)n=cap;memcpy(p,d->bytes[b],n);return (int)n;}
static bool write_bank(void *ctx,unsigned b,const uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==20);d->writes++;if(d->fail==1)return false;memcpy(d->bytes[b],p,n);d->n[b]=(int)n;if(d->fail==2)d->bytes[b][19]^=1;return d->fail!=3;}
static void bank(Disk *d,unsigned b,unsigned lang,uint32_t gen){tls_file_encode(d->bytes[b],lang,gen);d->n[b]=20;}
int main(void){
 Disk d={0};TLSIO io={&d,read_bank,write_bank};TLSStored s=tls_load(&io);assert(s.readable&&s.lang==TLG_EN&&s.generation==0&&s.bank==1&&d.writes==0);
 // Explicit EN is a first durable setting, despite matching the default.
 assert(tls_store(&io,&s,TLG_EN)&&s.generation==1&&d.writes==1);unsigned writes=d.writes;assert(tls_store(&io,&s,TLG_EN)&&d.writes==writes);assert(tls_store(&io,&s,TLG_ZH)&&s.generation==2&&s.bank==1);
 for(unsigned n=0;n<=21;n++)if(n!=20){Disk x={0};bank(&x,0,TLG_ZH,1);x.n[0]=(int)n;TLSIO xi={&x,read_bank,write_bank};assert(tls_load(&xi).generation==0);}
 for(unsigned i=0;i<20;i++)for(unsigned bit=0;bit<8;bit++){Disk x={0};bank(&x,0,TLG_ZH,1);x.bytes[0][i]^=1u<<bit;TLSIO xi={&x,read_bank,write_bank};assert(tls_load(&xi).generation==0);}
 d=(Disk){0};bank(&d,0,TLG_EN,UINT32_MAX-1);s=tls_load(&io);assert(tls_store(&io,&s,TLG_ZH)&&s.generation==UINT32_MAX);assert(tls_store(&io,&s,TLG_EN)&&s.generation==1&&s.bank==0);assert(tls_load(&io).generation==1);
 d=(Disk){0};bank(&d,0,TLG_EN,UINT32_MAX);bank(&d,1,TLG_ZH,1);assert(tls_load(&io).bank==1);uint8_t tmp[24];memcpy(tmp,d.bytes[0],24);memcpy(d.bytes[0],d.bytes[1],24);memcpy(d.bytes[1],tmp,24);assert(tls_load(&io).bank==0);
 d=(Disk){0};bank(&d,0,TLG_EN,9);bank(&d,1,TLG_EN,9);assert(tls_load(&io).readable&&tls_load(&io).bank==0);bank(&d,1,TLG_ZH,9);assert(!tls_load(&io).readable);bank(&d,1,TLG_ZH,9u+0x80000000u);assert(!tls_load(&io).readable);
 d=(Disk){0};bank(&d,0,TLG_ZH,4);d.error[1]=1;s=tls_load(&io);assert(!s.readable&&s.lang==TLG_ZH&&!tls_store(&io,&s,TLG_EN));
 for(int fail=1;fail<=3;fail++){d=(Disk){.fail=fail};bank(&d,0,TLG_EN,4);s=tls_load(&io);assert(!tls_store(&io,&s,TLG_ZH));assert(s.generation==(fail==3?5:4));}
 d=(Disk){0};bank(&d,0,TLG_EN,UINT32_MAX);s=tls_load(&io);assert(tls_store(&io,&s,TLG_EN)&&d.writes==0);assert(!tls_store(&io,&s,2));
 uint32_t seed=21;for(unsigned i=0;i<50000;i++){uint8_t raw[24];for(unsigned j=0;j<24;j++){seed=seed*1664525u+1013904223u;raw[j]=(uint8_t)(seed>>24);}TLSStored out;memset(&out,0x5a,sizeof out);TLSStored before=out;if(!tls_file_decode(raw,(int)(i%25),&out))assert(!memcmp(&before,&out,sizeof out));}
 assert(!tls_load(NULL).readable&&!tls_file_decode(NULL,20,&s));puts("PASS lang_store: explicit EN, reboot banks, CRC/bounds fuzz, faults, serial wrap and ambiguous generation rejection");
}
