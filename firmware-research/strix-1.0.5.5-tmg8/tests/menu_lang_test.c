#include "../src/global-remote-v1/language_state.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t bytes[2][21];int n[2];unsigned reads,writes;bool fail;} Disk;
static int read_bank(void *ctx,unsigned b,uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==21);d->reads++;memcpy(p,d->bytes[b],(size_t)d->n[b]);return d->n[b];}
static bool write_bank(void *ctx,unsigned b,const uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==20);d->writes++;if(d->fail)return false;memcpy(d->bytes[b],p,n);d->n[b]=(int)n;return true;}
int main(void){
 Disk d={0};TLSIO io={&d,read_bank,write_bank};TLGLanguageState s={0};TLGReply r,out;TLGCommand q={1,TLG_SET,TLG_ZH};
 assert(!tlg_state_accept(&s,&q,true,&io,&r)&&r.result==TLG_UNAVAILABLE&&d.reads==0&&d.writes==0&&s.lang==TLG_EN);
 assert(!tlg_state_load(&s,&io)&&d.reads==2&&s.lang==TLG_EN&&s.source==0);q=(TLGCommand){2,TLG_SET,TLG_EN};assert(!tlg_state_accept(&s,&q,true,&io,&r)&&r.result==TLG_OK&&r.source==2&&d.writes==1);
 q=(TLGCommand){3,TLG_SET,TLG_ZH};assert(tlg_state_accept(&s,&q,true,&io,&r)&&r.result==TLG_OK&&r.source==2);unsigned writes=d.writes,reads=d.reads;assert(!tlg_state_accept(&s,&q,true,&io,&r)&&d.writes==writes);
 q=(TLGCommand){4,TLG_QUERY,TLG_EN};assert(!tlg_state_accept(&s,&q,true,&io,&r)&&r.lang==TLG_ZH&&r.source==2);assert(d.reads>=reads);reads=d.reads;assert(!tlg_state_accept(&s,&q,true,&io,&r)&&d.reads==reads);
 TLGLanguageState reboot={0};assert(tlg_state_load(&reboot,&io)&&reboot.lang==TLG_ZH&&reboot.source==2);
 q=(TLGCommand){5,TLG_SET,TLG_EN};assert(!tlg_state_accept(&reboot,&q,false,&io,&r)&&r.result==TLG_BLOCKED&&reboot.lang==TLG_ZH);d.fail=true;assert(!tlg_state_accept(&reboot,&q,true,&io,&r)&&r.result==TLG_STORAGE&&reboot.lang==TLG_ZH);
 uint8_t raw[32],wire[74],back[32];tlg_reply_encode(raw,&r);assert(tlg_reply_decode(raw,32,&out)&&out.source==2&&out.result==TLG_STORAGE);tlg_carrier(wire,raw,true);assert(tlg_uncarrier(wire,74,back,true)&&!memcmp(raw,back,32));
 for(unsigned n=0;n<80;n++)if(n!=74)assert(!tlg_uncarrier(wire,n,back,true));for(unsigned n=0;n<40;n++)if(n!=32)assert(!tlg_reply_decode(raw,n,&out));for(unsigned i=0;i<32;i++){raw[i]^=1;assert(!tlg_reply_decode(raw,32,&out));raw[i]^=1;}
 puts("PASS durable TLG1: pre-show refusal, explicit EN, ZH reboot source2, no query reads and no success after storage failure");
}
