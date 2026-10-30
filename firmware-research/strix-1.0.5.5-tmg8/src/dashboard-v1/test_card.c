#include "card.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Round 2 card: layout checked against spec/card/proposed.svg, wire compatibility, allocation failure, fuzz. */
typedef struct {int x,y,w,h;unsigned size,color;char s[48];} Text;
typedef struct {int x,y,w;unsigned pct;} Bar;
static int calls,fail_at,live;
static Text texts[16];static unsigned ntext;static Bar bars[8];static unsigned nbar;
static bool step(void){calls++;return calls!=fail_at;}
static void *root(void *p){assert(p);if(!step())return NULL;live++;ntext=nbar=0;return (void *)2;}
static bool text(void *p,int x,int y,int w,int h,unsigned f,unsigned c,const char *s){
 assert(p&&strlen(s)<sizeof texts->s);
 /* the 6 px safe area on every side, the 16 px floor, and only the lens ladder's three text intensities */
 assert(x>=DC_SAFE&&y>=DC_SAFE&&x+w<=DC_W-DC_SAFE&&y+h<=DC_H-DC_SAFE&&f>=16&&(c==DC_MID||c==DC_HIGH||c==DC_FULL));
 if(!step())return false;
 assert(ntext<16);texts[ntext++]=(Text){x,y,w,h,f,c,{0}};strcpy(texts[ntext-1].s,s);return true;
}
static bool bar(void *p,int x,int y,int w,unsigned v){
 assert(p&&v<=100&&x>=DC_SAFE&&x+w<=DC_W-DC_SAFE&&y>=DC_SAFE&&y+DC_BAR_H<=DC_H-DC_SAFE&&w==DC_BAR_W);
 if(!step())return false;
 assert(nbar<8);bars[nbar++]=(Bar){x,y,w,v};return true;
}
static void destroy(void *p){assert(p&&live==1);live--;}
static const DCAPI api={root,text,bar,destroy};
static const Text *find(const char *s){for(unsigned i=0;i<ntext;i++)if(!strcmp(texts[i].s,s))return &texts[i];return NULL;}
static void render(const char *wire){DCValues v;assert(dc_parse(wire,strlen(wire),&v));assert(dc_render(&api,(void *)1,&v));}
static void forget(void){destroy((void *)2);}
int main(void){
 DCValues v,old;memset(&old,0xa5,sizeof old);v=old;
 const char *s="TDC1;99;90;85;375;1280;1400;2000;0;1;2";
 assert(dc_parse(s,strlen(s),&v)&&v.ramFree==375&&v.weekly==99&&v.icons[1]==1&&v.icons[2]==2);
 /* The board's numbers, EN only: the strings, sizes, intensities and positions of spec/card/proposed.svg (box top = baseline - 0.92 size). */
 render(s);
 assert(ntext==9&&nbar==3&&live==1);
 const Text *t;
 assert((t=find("MacBook Pro \xc2\xb7 M5 Max"))&&t->x==6&&t->y==10&&t->size==16&&t->color==DC_MID);
 assert((t=find("RAM 37.5 of 128 GB free"))&&t->x==6&&t->y==32&&t->size==16&&t->color==DC_HIGH);
 assert((t=find("SSD 1.4 of 2 TB free"))&&t->x==6&&t->y==52&&t->size==16&&t->color==DC_HIGH);
 const char *label[3]={"Codex 7d","Claude 5h","Claude 7d"},*num[3]={"99%","90%","85%"};const int col[3]={6,89,172};const unsigned pct[3]={99,90,85};
 for(unsigned k=0;k<3;k++){
  assert((t=find(label[k]))&&t->x==col[k]&&t->y==108&&t->size==16&&t->color==DC_MID);
  assert((t=find(num[k]))&&t->x==col[k]&&t->y==128&&t->size==32&&t->color==DC_FULL);
  assert(bars[k].x==col[k]&&bars[k].y==172&&bars[k].w==70&&bars[k].pct==pct[k]);
 }
 /* The number boxes do not overlap, and each number sits between its label and its bar. */
 for(unsigned k=0;k<3;k++){const Text *l=find(label[k]),*n=find(num[k]);assert(l->y+l->h<=n->y+2&&n->y+n->h<=bars[k].y);if(k<2)assert(n->x+n->w<=find(num[k+1])->x);}
 /* No plan name, no "left" or "used" anywhere, and the old rows are gone. */
 for(unsigned i=0;i<ntext;i++){const char *x=texts[i].s;assert(!strstr(x,"left")&&!strstr(x,"used")&&!strstr(x,"Pro 20")&&!strstr(x,"Max 20")&&!strstr(x,"Weekly")&&!strstr(x,"Week ")&&!strstr(x," / "));}
 forget();
 /* Number formatting at the edges: whole numbers lose the decimal, tenths truncate as before. */
 render("TDC1;100;0;5;1;10;100;1000;0;0;0");assert(find("RAM 0.1 of 1 GB free")&&find("SSD 0.1 of 1 TB free")&&find("100%")&&find("0%")&&find("5%"));forget();
 render("TDC1;0;0;0;99999;99999;99999;99999;2;2;2");assert(find("RAM 9999.9 of 9999.9 GB free")&&find("SSD 99.9 of 99.9 TB free")&&bars[0].pct==0);forget();
 /* "100%" is about 81 px at 32 px: in the last column it starts 4 px left so it ends inside the safe area; the other columns and labels do not move. */
 render("TDC1;100;100;100;375;1280;1400;2000;0;0;0");
 assert((t=find("100%"))&&t->x==6&&t->w==83);{unsigned seen=0;for(unsigned i=0;i<ntext;i++)if(!strcmp(texts[i].s,"100%")){seen++;if(seen==3)assert(texts[i].x==168&&texts[i].x+texts[i].w==250&&texts[i].y==128);if(seen==2)assert(texts[i].x==89&&texts[i].w==83);}assert(seen==3);}
 assert(bars[2].x==172&&bars[2].pct==100);forget();
 render("TDC1;99;99;99;375;1280;1400;2000;0;0;0");{unsigned seen=0;for(unsigned i=0;i<ntext;i++)if(!strcmp(texts[i].s,"99%")){seen++;if(seen==3)assert(texts[i].x==172&&texts[i].w==78);}assert(seen==3);}forget();
 /* A bar fill is a share of the 70 px track, rounded: 99% 69, 90% 63, 85% 60 (the board's rects). */
 assert((DC_BAR_W*99+50)/100==69&&(DC_BAR_W*90+50)/100==63&&(DC_BAR_W*85+50)/100==60);
 /* icons[] stays on the wire and the parser still checks it, but the renderer ignores it: any value draws the same card. */
 {Text first[16];unsigned count;
  render("TDC1;99;90;85;375;1280;1400;2000;0;0;0");count=ntext;memcpy(first,texts,sizeof first);forget();
  render("TDC1;99;90;85;375;1280;1400;2000;2;2;2");assert(ntext==count&&!memcmp(first,texts,sizeof first));forget();
  DCValues z;assert(dc_parse(s,strlen(s),&z));z.icons[0]=77;assert(dc_render(&api,(void *)1,&z));assert(ntext==count);forget();}
 /* Allocation failure at every step leaves nothing behind. */
 assert(dc_parse(s,strlen(s),&v));calls=0;fail_at=0;assert(dc_render(&api,(void *)1,&v));int count=calls;forget();
 assert(count==1+9+3);   /* root, nine texts, three bars */
 for(fail_at=1;fail_at<=count;fail_at++){calls=0;assert(!dc_render(&api,(void *)1,&v));assert(!live);}
 fail_at=0;
 /* Every usage value, inside the boxes above (the asserts in text and bar). */
 for(unsigned x=0;x<=100;x++){v.weekly=x;v.claude5h=100-x;v.claudeWeek=(x*7)%101;calls=0;assert(dc_render(&api,(void *)1,&v));assert(bars[0].pct==x);forget();}
 /* The renderer's own refusals are the TMG7 ones. */
 assert(!dc_render(&api,(void *)1,&(DCValues){101,0,0,1,1,1,1,{0}}));assert(!dc_render(&api,(void *)1,&(DCValues){1,1,1,2,1,1,1,{0}}));assert(!dc_render(&api,(void *)1,&(DCValues){1,1,1,1,1,0,0,{0}}));assert(!dc_render(NULL,(void *)1,&v));assert(!dc_render(&api,NULL,&v));
 /* The parser is unchanged: the same refusals as the TMG7 card. */
 const char *bad[]={"","TDC1;101;90;85;375;1280;1400;2000;0;1;2","TDC1;99;90;85;1281;1280;1400;2000;0;1;2","TDC1;99;90;85;375;0;1400;2000;0;1;2","TDC1;99;90;85;375;1280;1400;2000;0;1;3","TDC1;99;90;85;375;1280;1400;2000;0;1;2;","TDC1;-1;90;85;375;1280;1400;2000;0;1;2"};
 for(unsigned i=0;i<sizeof bad/sizeof *bad;i++){v=old;assert(!dc_parse(bad[i],strlen(bad[i]),&v));assert(!memcmp(&v,&old,sizeof v));}
 for(size_t n=0;n<strlen(s);n++){v=old;assert(!dc_parse(s,n,&v));}
 srand(7392);for(int n=0;n<100000;n++){char b[256];size_t z=rand()%256;for(size_t i=0;i<z;i++)b[i]=(char)rand();dc_parse(b,z,&v);}
 puts("dashboard parser/layout/allocation-failure/fuzz: PASS");
}
