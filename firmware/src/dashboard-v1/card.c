#include "card.h"
#include <string.h>
bool dc_parse(const char *p,size_t n,DCValues *out){
 if(!p||!out||n<5||n>120||memcmp(p,"TDC1;",5))return false;
 unsigned v[10];memset(v,0,sizeof v);size_t i=5;
 for(unsigned k=0;k<10;k++){
  unsigned digits=0;
  while(i<n&&p[i]>='0'&&p[i]<='9'){
   if(++digits>6)return false;v[k]=v[k]*10+(unsigned)(p[i++]-'0');
  }
  if(!digits||(k<9?(i>=n||p[i++]!=';'):i!=n))return false;
 }
 if(v[0]>100||v[1]>100||v[2]>100||!v[4]||v[4]>99999||v[3]>v[4]||!v[6]||v[6]>99999||v[5]>v[6])return false;
 for(unsigned k=7;k<10;k++)if(v[k]>2)return false;
 *out=(DCValues){v[0],v[1],v[2],v[3],v[4],v[5],v[6],{v[7],v[8],v[9]}};return true;
}
static char *literal(char *p,const char *s){while(*s)*p++=*s++;*p=0;return p;}
static char *number(char *p,unsigned n){char t[6];unsigned c=0;do{t[c++]='0'+n%10;n/=10;}while(n);while(c)*p++=t[--c];*p=0;return p;}
static char *decimal(char *p,unsigned n,unsigned unit){p=number(p,n/unit);unsigned d=n%unit;if(d){*p++='.';p=number(p,d/(unit/10));}return p;}
static void memory(char *b,const DCValues *v){char *p=literal(b,"RAM ");p=decimal(p,v->ramFree,10);p=literal(p," of ");p=decimal(p,v->ramTotal,10);literal(p," GB free");}
static void disk(char *b,const DCValues *v){char *p=literal(b,"SSD ");p=decimal(p,v->diskFree,1000);p=literal(p," of ");p=decimal(p,v->diskTotal,1000);literal(p," TB free");}
/* Layout, from spec/card/proposed.svg (a text box's top is its baseline minus 0.92 of the size): the machine line, RAM and SSD at the top,
 * the three usage columns at the bottom (label, number, bar). Every box lies inside the 6 px safe area. */
void *dc_render(const DCAPI *a,void *parent,const DCValues *v){
 if(!a||!parent||!v||!a->root||!a->text||!a->bar||!a->destroy)return NULL;
 /* Defensive for callers other than the parser. icons[] is accepted on the wire and ignored. */
 if(v->weekly>100||v->claude5h>100||v->claudeWeek>100||v->ramTotal>99999||v->diskTotal>99999||!v->ramTotal||!v->diskTotal||v->ramFree>v->ramTotal||v->diskFree>v->diskTotal)return NULL;
 void *r=a->root(parent);if(!r)return NULL;char b[48];
#define TEXT(x,y,w,h,f,c,s) do{if(!a->text(r,x,y,w,h,f,c,s))goto fail;}while(0)
 TEXT(6,10,244,22,16,DC_MID,"MacBook Pro · M5 Max");
 memory(b,v);TEXT(6,32,244,22,16,DC_HIGH,b);
 disk(b,v);TEXT(6,52,244,22,16,DC_HIGH,b);
 static const char *const label[3]={"Codex 7d","Claude 5h","Claude 7d"};
 static const int column[3]={6,89,172},width[3]={83,83,78};
 const unsigned pct[3]={v->weekly,v->claude5h,v->claudeWeek};
 for(unsigned k=0;k<3;k++){
  TEXT(column[k],108,DC_W-DC_SAFE-column[k],22,16,DC_MID,label[k]);   /* a label may run to the safe edge: the next label starts after it ends */
  /* "100%" at 32 px is about 81 px wide, 3 px more than the last column has before the safe edge: that one number starts 4 px left (x 168). */
  int nx=column[k]-(k==2&&pct[k]>=100?4:0);
  literal(number(b,pct[k]),"%");TEXT(nx,128,column[k]+width[k]-nx,40,32,DC_FULL,b);
  if(!a->bar(r,column[k],172,DC_BAR_W,pct[k]))goto fail;
 }
#undef TEXT
 return r;
 fail:a->destroy(r);return NULL;
}
