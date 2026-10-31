#include "../src/menu-grid-v2/tile_config.h"
#include "../src/menu-grid-v2/menu_config.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t p[2][32];int n[2];unsigned writes;} Disk;
static int read_bank(void *ctx,unsigned bank,uint8_t *p,size_t cap){Disk *d=ctx;assert(bank<2);int n=d->n[bank];assert(n<=(int)cap);memcpy(p,d->p[bank],n);return n;}
static bool write_bank(void *ctx,unsigned bank,const uint8_t *p,size_t n){Disk *d=ctx;assert(bank<2&&n<=32);memcpy(d->p[bank],p,n);d->n[bank]=(int)n;d->writes++;return true;}
int main(void){
 for(unsigned wrapped=0;wrapped<2;wrapped++)for(unsigned delta=119999;delta<=120001;delta++){
  uint32_t issued=wrapped?UINT32_MAX-31:100;Disk disk={0};TTIO io={&disk,read_bank,write_bank};TTState s={.loaded=true};TTCommand query={.op=TT_QUERY,.request=1,.client=7};assert(tt_accept(&s,&query,issued,31,true,&io)==TT_OK);
  TTCommand set={.op=TT_SET,.request=2,.client=7,.token=31,.rank=719,.hide=0xf80};unsigned result=tt_accept(&s,&set,issued+delta,0,true,&io);assert(result==(delta<=120000?TT_OK:TT_SESSION));assert(disk.writes==(delta<=120000?1:0));if(result==TT_OK)assert(tt_accept(&s,&set,issued+delta,0,true,&io)==TT_SESSION);
  disk=(Disk){0};TMLIO rows_io={&disk,read_bank,write_bank};TMLState rows={0};TMLCommand rq={.op=TML_QUERY,.request=1,.client=7};assert(tml_accept(&rows,&rq,issued,32,true,&rows_io)==TML_OK);TMLCommand rs={.op=TML_SET,.request=2,.client=7,.token=32,.rows=2};result=tml_accept(&rows,&rs,issued+delta,0,true,&rows_io);assert(result==(delta<=120000?TML_OK:TML_SESSION));assert(disk.writes==(delta<=120000?1:0));
 }
 puts("PASS token timer wrap: both menu/tile grants accept exactly120000ms and reject120001ms with no write");
}
