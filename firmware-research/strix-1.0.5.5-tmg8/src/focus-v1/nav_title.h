#ifndef TURBO_NAV_TITLE_H
#define TURBO_NAV_TITLE_H
/* TMG8 navigation title (OptionANavTitle.dc.html, option A). While a route is live and not stale, band T of the menu (carousel and grid) shows the
 * next turn centred: the manoeuvre arrow and "<distance> · <road>", 18 px, lens-high, e.g. "200 m · Market St".
 * Pure text, glyph and decisions over a TSLive snapshot so the host tests can stub every global. No wire change: nav_service already holds the
 * scene (icon, distance, road); tn_slot_live copies it read only.
 *   shown   phone linked, route session connected, not stale, a known manoeuvre. Anything else hides the title at once.
 *   text    "<d> m" under 950 m (to 10 m), else "<d.d> km"; the road follows after a middle dot, or nothing when the road is empty.
 *   fit     the text is cut so its estimated width (tm_advance, errs wide) fits NT_TEXT_W: at the last word boundary (a space, or after a CJK
 *           character) and ending in an ellipsis; a single word longer than the slot is cut at a character instead.
 *   arrow   the navigation page's glyph set (nav_glyph.h) scaled to 18 px with a 2 px anti-aliased stroke in lens-high.
 * The slot is x NT_X0..NT_X1, clear of the clock (x 40..104) and the battery (x 436..500); the group (arrow, 6 px gap, left-aligned text) is centred on x 270 inside it,
 * on 7/8 of the width estimate (the estimate errs wide; the text box keeps the full estimate so the label never clips). */
#include "tile_state.h"
#include "../navigation-runtime-v1/nav_glyph.h"
enum { NT_ARROW=18, NT_GAP=6, NT_STATUS_W=64,
 NT_X0=TIO_CORE_X0+NT_STATUS_W+4, NT_X1=TIO_CORE_X1-NT_STATUS_W-4,
 NT_TEXT_W=NT_X1-NT_X0-NT_ARROW-NT_GAP, NT_TEXT_MAX=112, NT_MIN_MS=1000 };
_Static_assert(NT_X0+NT_X1==540,"the title slot is centred on x 270");
_Static_assert(NT_ARROW<=TIO_FONT_LABEL,"the arrow is as high as the 18 px text");
typedef struct {bool on;uint8_t icon;unsigned width;char text[NT_TEXT_MAX];} NTTitle;   /* width: estimated text width in px (the label box) */
/* Distance as the nav page would say it, rounded to 10 m under 950 m so the text does not flicker, one decimal of km above. */
static inline char *nt_distance(char *p,uint32_t m){
 if(m<950){p=ts_u32(p,(m+5)/10*10);*p++=' ';*p++='m';}
 else{char v[16];(void)ts_distance(v,m);for(const char *q=v;*q;)*p++=*q++;*p++=' ';*p++='k';*p++='m';}
 *p=0;return p;
}
static inline void nt_title(const TSLive *in,NTTitle *out){
 enum { F=TIO_FONT_LABEL };
 memset(out,0,sizeof *out);
 if(!in||!in->phone||!in->nav_active||in->nav_stale||!in->nav_turn||in->nav_icon>=TN_ICON_COUNT)return;
 char *p=nt_distance(out->text,in->nav_turn_m);
 out->on=true;out->icon=in->nav_icon;
 size_t rn=0;while(rn<TS_ROAD_MAX&&in->nav_road[rn])rn++;
 const char *road=in->nav_road;size_t r0=0;while(r0<rn&&road[r0]==' ')r0++;
 if(r0<rn){
  static const char sep[]="\x20\xc2\xb7\x20";
  const unsigned ellipsis=tm_advance(0x2026,F);
  unsigned w=tm_width(out->text,(size_t)(p-out->text),F)+tm_width(sep,4,F);
  size_t i=r0,at_word=0,at_char=0;bool over=false;
  while(i<rn){
   uint32_t c;unsigned k=tn_text_unit(road+i,rn-i,&c);if(!k)break;   /* the runtime validated the text; stop at anything else */
   if(c==' '&&i>r0&&w+ellipsis<=(unsigned)NT_TEXT_W)at_word=i;   /* cut before a space */
   unsigned a=tm_advance(c,F);if(w+a>(unsigned)NT_TEXT_W){over=true;break;}
   w+=a;i+=k;
   if(c>=0x2e80&&w+ellipsis<=(unsigned)NT_TEXT_W)at_word=i;   /* CJK has no spaces: a break after any character */
   if(w+ellipsis<=(unsigned)NT_TEXT_W)at_char=i;
  }
  size_t end=i;bool cut=over;
  if(over){end=at_word>r0?at_word:at_char;}
  while(end>r0&&road[end-1]==' ')end--;
  if(end>r0){memcpy(p,sep,4);p+=4;memcpy(p,road+r0,end-r0);p+=end-r0;if(cut){memcpy(p,"\xe2\x80\xa6",3);p+=3;}}
  *p=0;
 }
 out->width=tm_width(out->text,strlen(out->text),F);
}
/* ---- The arrow ------------------------------------------------------------------------------------------------------ */
static inline unsigned nt_isqrt(unsigned n){unsigned r=0,b=1u<<30;while(b>n)b>>=2;while(b){if(n>=r+b){n-=r+b;r=(r>>1)+b;}else r>>=1;b>>=2;}return r;}
/* Squared distance, in 1/16 px squared, from (px,py) to the segment a-b. 32-bit only: the AP payload has no 64-bit divide. */
static inline unsigned nt_dist2(int px,int py,int ax,int ay,int bx,int by){
 int dx=bx-ax,dy=by-ay,len2=dx*dx+dy*dy,t=(px-ax)*dx+(py-ay)*dy,qx,qy;
 if(len2==0||t<=0){qx=ax;qy=ay;}else if(t>=len2){qx=bx;qy=by;}else{qx=ax+dx*t/len2;qy=ay+dy*t/len2;}
 dx=px-qx;dy=py-qy;return (unsigned)(dx*dx+dy*dy);
}
/* Glyph `icon` into an 18x18 canvas at brightness `gain` (the canvas gray level, 255 = full). The nav page's 96x84 box shrinks by 45/256 (about 0.18),
 * so a right turn is about 10x13 px like the board's arrow, drawn with a 2 px round stroke and one pixel of anti-aliasing. */
static inline void nt_glyph(uint8_t out[NT_ARROW*NT_ARROW],unsigned icon,unsigned gain){
 TNXY g[16];const unsigned n=tn_glyph(icon,g);int X[16],Y[16];
 for(unsigned i=0;i<n;i++){X[i]=NT_ARROW*8+(g[i].x-56)*45/16;Y[i]=NT_ARROW*8+(g[i].y-60)*45/16;}   /* 1/16 px, the box centre on the canvas centre */
 for(int y=0;y<NT_ARROW;y++)for(int x=0;x<NT_ARROW;x++){
  unsigned best=0xffffffffu;
  for(unsigned s=1;s<n;s++){unsigned d=nt_dist2(x*16+8,y*16+8,X[s-1],Y[s-1],X[s],Y[s]);if(d<best)best=d;}
  int cover=16+8-(int)nt_isqrt(best>0x7fffffffu?0x7fffffffu:best);   /* stroke radius 1 px: full inside 0.5 px, none beyond 1.5 px */
  if(cover<0)cover=0;if(cover>16)cover=16;
  out[y*NT_ARROW+x]=(uint8_t)((unsigned)cover*gain/16);
 }
}
#endif
