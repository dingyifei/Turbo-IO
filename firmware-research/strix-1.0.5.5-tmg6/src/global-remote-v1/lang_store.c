#include "lang_store.h"
#include <string.h>
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
uint32_t tls_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
void tls_file_encode(uint8_t *p,unsigned lang,uint32_t generation){if(!p)return;memset(p,0,20);memcpy(p,"TLC1",4);p[4]=1;p[5]=(uint8_t)lang;put32(p+8,generation);put32(p+16,tls_crc(p,16));}
bool tls_file_decode(const uint8_t *p,int n,TLSStored *out){
 if(!p||!out||n!=20||memcmp(p,"TLC1",4)||p[4]!=1||p[5]>TLG_ZH||p[6]||p[7]||!get32(p+8)||get32(p+12)||get32(p+16)!=tls_crc(p,16))return false;
 TLSStored s={.generation=get32(p+8),.readable=true,.lang=p[5]};*out=s;return true;
}
TLSStored tls_load(const TLSIO *io){
 TLSStored s={.bank=1,.readable=true,.lang=TLG_EN};if(!io||!io->read){s.readable=false;return s;}TLSStored banks[2];bool valid[2]={false,false};uint8_t raw[21];
 for(unsigned b=0;b<2;b++){int n=io->read(io->ctx,b,raw,sizeof raw);if(n<0)s.readable=false;valid[b]=tls_file_decode(raw,n,&banks[b]);if(valid[b])banks[b].bank=b;}
 unsigned chosen=valid[0]?0:1;if(!valid[chosen])return s;
 if(valid[0]&&valid[1]){uint32_t d=banks[0].generation-banks[1].generation;if(d==0){if(banks[0].lang!=banks[1].lang){s.readable=false;return s;}chosen=0;}else if(d==0x80000000u){s.readable=false;return s;}else chosen=d<0x80000000u?0:1;}
 bool readable=s.readable;s=banks[chosen];s.readable=readable;return s;
}
bool tls_store(const TLSIO *io,TLSStored *s,unsigned lang){
 if(!io||!io->write||!s||!s->readable||lang>TLG_ZH)return false;if(s->generation&&s->lang==lang)return true;
 uint32_t generation=s->generation+1;if(!generation)generation=1;unsigned bank=s->bank^1u;if(bank>1)return false;uint8_t raw[20];tls_file_encode(raw,lang,generation);
 bool wrote=io->write(io->ctx,bank,raw,sizeof raw);TLSStored latest=tls_load(io);if(!latest.readable){s->readable=false;return false;}*s=latest;return wrote&&s->generation==generation&&s->bank==bank&&s->lang==lang;
}
