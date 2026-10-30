#include "../src/focus-v1/nav_title.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* TMG8 navigation title (OptionANavTitle.dc.html, option A): when it shows, what it says, how a long road is cut, and the arrow glyph, over a stubbed
 * TSLive snapshot. The widget hook (fm_view_title) is covered by focus_grid_test.c, the stubbed services by native_ui_test.c. */
unsigned tio_lang(void){return 0;}
static bool utf8(const char *s){const unsigned char *p=(const unsigned char *)s;
 while(*p){unsigned a=*p++,n;if(a<128)continue;if(a>=0xc2&&a<=0xdf)n=1;else if(a>=0xe0&&a<=0xef)n=2;else if(a>=0xf0&&a<=0xf4)n=3;else return false;
  for(unsigned j=0;j<n;j++)if((*p++&0xc0)!=0x80)return false;}return true;}
static TSLive route(unsigned icon,uint32_t m,const char *road){TSLive l;memset(&l,0,sizeof l);l.phone=true;l.nav_active=true;l.nav_turn=true;l.nav_icon=(uint8_t)icon;l.nav_turn_m=m;snprintf(l.nav_road,sizeof l.nav_road,"%s",road);return l;}
static NTTitle title(const TSLive *l){NTTitle t;memset(&t,0x5a,sizeof t);nt_title(l,&t);assert(memchr(t.text,0,sizeof t.text));return t;}
static void says(const TSLive *l,const char *want){
 NTTitle t=title(l);if(!t.on||strcmp(t.text,want)){printf("got on=%d '%s', want '%s'\n",t.on,t.text,want);assert(0);}
 assert(utf8(t.text)&&strlen(t.text)<NT_TEXT_MAX&&t.width==tm_width(t.text,strlen(t.text),TIO_FONT_LABEL)&&t.width<=NT_TEXT_W);
}
static void hidden(const TSLive *l){NTTitle t=title(l);assert(!t.on&&!t.text[0]&&!t.width);}
int main(void){
 /* The slot sits between the clock and the battery, centred on the window. */
 assert(NT_X0==108&&NT_X1==432&&NT_ARROW==18&&NT_TEXT_W==300&&NT_X0>=TIO_CORE_X0+NT_STATUS_W&&NT_X1<=TIO_CORE_X1-NT_STATUS_W);
 /* The board: 200 m onto Market St. */
 TSLive l=route(TN_RIGHT,200,"Market St");says(&l,"200 m \xc2\xb7 Market St");
 { NTTitle t=title(&l);assert(t.icon==TN_RIGHT&&t.on); }
 /* Distance: to 10 m under 950 m, one decimal of km above, whole km from 100 km. */
 l=route(TN_LEFT,0,"A St");says(&l,"0 m \xc2\xb7 A St");
 l=route(TN_LEFT,4,"A St");says(&l,"0 m \xc2\xb7 A St");l=route(TN_LEFT,5,"A St");says(&l,"10 m \xc2\xb7 A St");
 l=route(TN_LEFT,203,"A St");says(&l,"200 m \xc2\xb7 A St");l=route(TN_LEFT,948,"A St");says(&l,"950 m \xc2\xb7 A St");
 l=route(TN_LEFT,949,"A St");says(&l,"950 m \xc2\xb7 A St");l=route(TN_LEFT,950,"A St");says(&l,"1.0 km \xc2\xb7 A St");
 l=route(TN_LEFT,1234,"A St");says(&l,"1.2 km \xc2\xb7 A St");l=route(TN_LEFT,25049,"A St");says(&l,"25.0 km \xc2\xb7 A St");
 l=route(TN_LEFT,123456,"A St");says(&l,"123 km \xc2\xb7 A St");
 /* An empty road says the distance alone. */
 l=route(TN_STRAIGHT,300,"");says(&l,"300 m");l=route(TN_STRAIGHT,300,"   ");says(&l,"300 m");
 /* Only a live, connected, fresh route with a known manoeuvre shows. */
 l=route(TN_RIGHT,200,"Market St");l.nav_stale=true;hidden(&l);
 l=route(TN_RIGHT,200,"Market St");l.nav_active=false;hidden(&l);
 l=route(TN_RIGHT,200,"Market St");l.phone=false;hidden(&l);
 l=route(TN_RIGHT,200,"Market St");l.nav_turn=false;hidden(&l);
 l=route(TN_ICON_COUNT,200,"Market St");hidden(&l);
 {NTTitle t;nt_title(NULL,&t);assert(!t.on);}
 /* Long roads: whole when they fit, else cut at the last word boundary and ended with an ellipsis, never wider than the slot. */
 l=route(TN_RIGHT,200,"Martin Luther King Jr. Boulevard South Extension");
 { NTTitle t=title(&l);size_t n=strlen(t.text);assert(t.on&&t.width<=NT_TEXT_W&&n>6&&!strcmp(t.text+n-3,"\xe2\x80\xa6"));
   assert(!memcmp(t.text,"200 m \xc2\xb7 Martin Luther",22));assert(t.text[n-4]!=' ');
   /* word boundary: what is kept is a whole-word prefix of the road */
   char kept[NT_TEXT_MAX];memcpy(kept,t.text+9,n-9-3);kept[n-9-3]=0;const char *road="Martin Luther King Jr. Boulevard South Extension";
   assert(!strncmp(road,kept,strlen(kept))&&(road[strlen(kept)]==' '));
   /* one more word would not have fitted */
   char more[NT_TEXT_MAX];const char *sp=strchr(road+strlen(kept)+1,' ');size_t take=sp?(size_t)(sp-road):strlen(road);snprintf(more,sizeof more,"200 m \xc2\xb7 %.*s\xe2\x80\xa6",(int)take,road);
   assert(tm_width(more,strlen(more),TIO_FONT_LABEL)>NT_TEXT_W);}
 /* One word longer than the slot is cut at a character. */
 l=route(TN_RIGHT,200,"Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch");
 { NTTitle t=title(&l);size_t n=strlen(t.text);assert(t.on&&t.width<=NT_TEXT_W&&!strcmp(t.text+n-3,"\xe2\x80\xa6")&&n>12);}
 /* A road that just fits is kept whole; one more character is cut. */
 { char road[97];size_t k;for(k=1;k<60;k++){memset(road,'m',k);road[k]=0;l=route(TN_RIGHT,200,road);NTTitle t=title(&l);
    size_t n=strlen(t.text);bool cut=!strcmp(t.text+n-3,"\xe2\x80\xa6");
    assert(t.width<=NT_TEXT_W);
    if(!cut)assert(n==9+k&&!memcmp(t.text+9,road,k)); else {assert(k>=8);break;}
 } assert(k<60); }
 /* Chinese: no spaces, so a break falls after any character; the road is never split inside a character. */
 l=route(TN_LEFT,350,"\xe4\xba\xba\xe6\xb0\x91\xe5\xa4\xa7\xe9\x81\x93\xe4\xb8\x8e\xe4\xb8\xad\xe5\xb1\xb1\xe4\xb8\x9c\xe8\xb7\xaf\xe4\xba\xa4\xe5\x8f\x89\xe5\x8f\xa3\xe5\x8d\x97\xe4\xbe\xa7\xe8\xbe\x85\xe8\xb7\xaf");
 { NTTitle t=title(&l);size_t n=strlen(t.text);assert(t.on&&utf8(t.text)&&t.width<=NT_TEXT_W&&!strcmp(t.text+n-3,"\xe2\x80\xa6")&&!memcmp(t.text,"350 m \xc2\xb7 \xe4\xba\xba\xe6\xb0\x91",12));}
 l=route(TN_LEFT,350,"\xe4\xba\xba\xe6\xb0\x91\xe8\xb7\xaf");says(&l,"350 m \xc2\xb7 \xe4\xba\xba\xe6\xb0\x91\xe8\xb7\xaf");
 /* Mixed text with a trailing run of spaces before the cut is trimmed; invalid bytes end the road. */
 l=route(TN_RIGHT,200,"Market   Street     Extension Road Number Seven Hundred And Fifty");
 { NTTitle t=title(&l);size_t n=strlen(t.text);assert(t.on&&t.text[n-4]!=' '&&t.width<=NT_TEXT_W);}
 l=route(TN_RIGHT,200,"Ab\xff" "cd");says(&l,"200 m \xc2\xb7 Ab");
 /* Every length and every road shape stays inside the slot and valid UTF-8 (a sweep over mixed alphabets). */
 { static const char *alpha[]={"M","i","W","\xe7\x95\x8c"," ","\xc3\xa9","."};unsigned seed=12345;
   for(unsigned round=0;round<3000;round++){char road[97];size_t n=0;unsigned len=1+round%48;
    while(len--){seed=seed*1103515245u+12345u;const char *a=alpha[(seed>>16)%7];size_t k=strlen(a);if(n+k>=sizeof road)break;memcpy(road+n,a,k);n+=k;}road[n]=0;
    l=route(1+round%10,round*37%200000,road);NTTitle t=title(&l);assert(t.on&&utf8(t.text)&&strlen(t.text)<NT_TEXT_MAX&&t.width<=NT_TEXT_W);
    assert(t.width==tm_width(t.text,strlen(t.text),TIO_FONT_LABEL));}}
 /* The full 96 byte road (Chinese, 32 characters) fits the buffer. */
 { char road[97]="";for(unsigned i=0;i<32;i++)strcat(road,"\xe7\x95\x8c");l=route(TN_UTURN,99999,road);NTTitle t=title(&l);assert(t.on&&utf8(t.text)&&strlen(t.text)<NT_TEXT_MAX&&t.width<=NT_TEXT_W);}

 /* ---- The arrow: the nav page's glyph set at 18 px ------------------------------------------------------------------ */
 for(unsigned icon=0;icon<TN_ICON_COUNT;icon++){
  uint8_t px[NT_ARROW*NT_ARROW];memset(px,0x5a,sizeof px);nt_glyph(px,icon,0xb0);
  unsigned lit=0,peak=0,x0=99,y0=99,x1=0,y1=0;
  for(unsigned y=0;y<NT_ARROW;y++)for(unsigned x=0;x<NT_ARROW;x++){unsigned g=px[y*NT_ARROW+x];if(g>peak)peak=g;if(g>16){lit++;if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}}
  assert(peak==0xb0);                                      /* lens-high at the stroke centre, never brighter */
  assert(lit>=14&&lit<=NT_ARROW*NT_ARROW/2);               /* a line drawing, not a block */
  assert(x1>=x0+6&&y1>=y0+7);                              /* big enough to read: at least 7 x 8 px of ink */
  assert(x0>=1&&y0>=1&&x1<=NT_ARROW-2&&y1<=NT_ARROW-2);    /* a pixel of margin all round */
  for(unsigned i=0;i<NT_ARROW;i++)assert(px[i]<=0x40&&px[(NT_ARROW-1)*NT_ARROW+i]<=0x40&&px[i*NT_ARROW]<=0x40&&px[i*NT_ARROW+NT_ARROW-1]<=0x40);   /* the border is nearly dark */
 }
 /* Left and right turns are mirror images. */
 { static const struct {unsigned l,r;} pairs[]={{TN_LEFT,TN_RIGHT},{TN_SLIGHT_LEFT,TN_SLIGHT_RIGHT},{TN_SHARP_LEFT,TN_SHARP_RIGHT}};
   for(unsigned i=0;i<3;i++){uint8_t a[NT_ARROW*NT_ARROW],b[NT_ARROW*NT_ARROW];nt_glyph(a,pairs[i].l,0xb0);nt_glyph(b,pairs[i].r,0xb0);
    int diff=0;for(unsigned y=0;y<NT_ARROW;y++)for(unsigned x=0;x<NT_ARROW;x++){int d=(int)a[y*NT_ARROW+x]-(int)b[y*NT_ARROW+NT_ARROW-1-x];if(d<0)d=-d;if(d>diff)diff=d;}
    assert(diff<=64);}}   /* the box centre is at 56 but the mirror is about 52+4: allow the sub-pixel offset */
 /* Different manoeuvres draw different arrows. */
 { uint8_t a[NT_ARROW*NT_ARROW],b[NT_ARROW*NT_ARROW];for(unsigned i=1;i<TN_ICON_COUNT;i++)for(unsigned j=i+1;j<TN_ICON_COUNT;j++){nt_glyph(a,i,0xb0);nt_glyph(b,j,0xb0);assert(memcmp(a,b,sizeof a));}}
 /* The gain scales every pixel. */
 { uint8_t a[NT_ARROW*NT_ARROW],b[NT_ARROW*NT_ARROW];nt_glyph(a,TN_RIGHT,0xb0);nt_glyph(b,TN_RIGHT,0x58);for(unsigned i=0;i<sizeof a;i++)assert(b[i]==a[i]/2||b[i]+1==a[i]/2||b[i]==a[i]/2+1);}
 puts("PASS tmg8 navigation title: board text, distance rounding, visibility rules, word-boundary/CJK/character cuts inside 300 px, 11 glyphs at 18 px");
 return 0;
}
