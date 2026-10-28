#include "../src/global-remote-v1/language_state.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void crc(uint8_t p[32]){uint32_t c=tlg_crc(p,28);for(unsigned i=0;i<4;i++)p[28+i]=(uint8_t)(c>>(8*i));}
int main(void){
 TLGLanguageState state={0};TLGCommand q={1,TLG_QUERY,TLG_EN},got;TLGReply reply,decoded;
 assert(!tlg_state_accept(&state,&q,true,&reply));assert(reply.lang==TLG_EN&&reply.source==TLG_SOURCE_DEFAULT);
 q=(TLGCommand){2,TLG_SET,TLG_ZH};assert(tlg_state_accept(&state,&q,true,&reply));
 assert(state.lang==TLG_ZH&&reply.source==TLG_SOURCE_PHONE);
 assert(!tlg_state_accept(&state,&q,true,&reply));
 q=(TLGCommand){3,TLG_SET,TLG_EN};assert(!tlg_state_accept(&state,&q,false,&reply));assert(reply.result==TLG_BLOCKED&&state.lang==TLG_ZH);
 q.op=TLG_QUERY;q.lang=TLG_EN;assert(!tlg_state_accept(&state,&q,true,&reply));assert(reply.lang==TLG_ZH&&reply.source==TLG_SOURCE_PHONE);
 uint8_t raw[32],wire[75],back[32];tlg_reply_encode(raw,&reply);assert(tlg_reply_decode(raw,32,&decoded));assert(decoded.source<=1);
 tlg_carrier(wire,raw,true);assert(tlg_uncarrier(wire,74,back,true)&&!memcmp(raw,back,32));
 for(unsigned n=0;n<80;n++)if(n!=74)assert(!tlg_uncarrier(wire,n,back,true));
 q=(TLGCommand){4,TLG_SET,TLG_EN};tlg_encode(raw,&q);assert(tlg_decode(raw,32,&got));
 tlg_carrier(wire,raw,false);assert(tlg_uncarrier(wire,74,back,false)&&tlg_decode(back,32,&got));
 for(unsigned n=0;n<40;n++)if(n!=32)assert(!tlg_decode(raw,n,&got));
 for(unsigned i=0;i<32;i++){uint8_t bad[32];memcpy(bad,raw,32);bad[i]^=1;assert(!tlg_decode(bad,32,&got));}
 for(unsigned i=12;i<28;i++){uint8_t bad[32];memcpy(bad,raw,32);bad[i]=1;crc(bad);assert(!tlg_decode(bad,32,&got));}
 raw[6]=2;crc(raw);assert(!tlg_decode(raw,32,&got));raw[6]=0;raw[5]=TLG_QUERY;raw[6]=TLG_ZH;crc(raw);assert(!tlg_decode(raw,32,&got));
 wire[10]='g';assert(!tlg_uncarrier(wire,74,back,false));
 // A new RAM controller always starts in English; no persisted source exists.
 state=(TLGLanguageState){0};q=(TLGCommand){5,TLG_QUERY,TLG_EN};assert(!tlg_state_accept(&state,&q,true,&reply));assert(reply.lang==TLG_EN&&reply.source==0);
 puts("PASS TLG1 parse bounds, RAM state, blocked SET, source 0/1");
}
