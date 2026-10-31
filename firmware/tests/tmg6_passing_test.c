#include "../src/navigation-runtime-v1/nav_runtime.h"
#include "../src/navigation-runtime-v1/nav_map.h"
#include "../src/navigation-runtime-v1/nav_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void){
 uint8_t body[224]={1,0,0,0,19,0,0,0};memcpy(body+8,"Passing Oak Street",18);body[4]=18;body[200+7/8]|=1u<<(7%8);body[200+11/8]|=1u<<(11%8);body[200+18/8]|=1u<<(18%8);
 assert(tnr_body_valid(12,body,sizeof body));uint8_t packet[256];assert(tnr_wrap(packet,sizeof packet,12,1,2,body,sizeof body)==256);assert(tn_packet_valid(packet,sizeof packet));
 // Wrong generation cannot mutate a live text; malformed/reserved/UTF8/breaks fail closed.
 TNRState state={0};assert(!tnr_receive(&state,12,body,224,0));state.valid=true;state.scenes[0].generation=1;assert(tnr_receive(&state,12,body,224,0));assert(!strcmp(state.passing,"Passing Oak Street"));
 body[0]=2;assert(!tnr_receive(&state,12,body,224,0));assert(!strcmp(state.passing,"Passing Oak Street"));body[0]=1;
 for(unsigned len=0;len<256;len++)if(len!=224)assert(!tnr_body_valid(12,body,len));
 body[5]=1;assert(!tnr_body_valid(12,body,224));body[5]=0;body[8]=0xff;assert(!tnr_body_valid(12,body,224));body[8]='P';
 char out[244];tn_text_two_lines("The morning light is falling on the streets we used to know",366,24,out,sizeof out);assert(strchr(out,'\n')&&!strchr(strchr(out,'\n')+1,'\n'));
 tn_text_two_lines("沿着熟悉的街道慢慢走过每一个曾经相遇的地方",366,24,out,sizeof out);assert(strchr(out,'\n')&&!strchr(strchr(out,'\n')+1,'\n'));
 const char *name="Passing Oak Street";assert(tn_text_fit(name,18,body+200,524,out,sizeof out)==18&&!strcmp(out,name));
 unsigned seed=7;for(unsigned i=0;i<10000;i++){uint8_t fuzz[256];for(unsigned j=0;j<256;j++){seed=seed*1664525u+1013904223u;fuzz[j]=(uint8_t)(seed>>24);} (void)tnr_body_valid(12,fuzz,seed%257);}
 puts("PASS caps-extension packet accepted through real validation");return 0;
}
