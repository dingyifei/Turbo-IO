#ifndef TURBO_MUSIC_LAYOUT_H
#define TURBO_MUSIC_LAYOUT_H
/* LensMusic (docs/design-system/screens/LensMusic.dc.html, components/LyricStack), TMG7.
 * Kept out of music.c, which is byte-shared with the phone, so no wire or shared-source change.
 * Band T: 36x36 artwork tile and the track in lens-mid, replaced by the transient control hint.
 * Band M: the next lyric, one line of lens-body in lens-high. Band B: the current lyric, up to two
 * lines of lens-title in lens-full. The previous line is dropped. Nothing else is drawn. */
#include "../common-v1/tio_ui.h"
#include "../navigation-runtime-v1/nav_text.h"
#define TM_ART 36 /* LyricStack: 36x36 ambient artwork (the 144 px cover is box-averaged 4x4) */
#define TM_ART_FRAME 2
#define TM_ART_LEVEL 0x77u /* artwork never brighter than lens-mid */
#define TM_ART_SRC 144
#define TM_NEXT_FONT TIO_FONT_BODY
#define TM_CUR_FONT TIO_FONT_TITLE
#define TM_TRACK_FONT TIO_FONT_LABEL
#define TM_ROW_GAP 12
static inline TIORect tm_art_rect(void){TIOSpan t=tio_band(TIO_SURFACE_PAGE,TIO_BAND_T);return (TIORect){TIO_CORE_X0,t.y0+(t.y1-t.y0-TM_ART)/2,TM_ART,TM_ART};}
/* The track label sits right of the tile on the tile's centre line; the hint takes the core row instead. */
static inline TIORect tm_track_rect(void){TIORect a=tm_art_rect();int h=TIO_LINE(TM_TRACK_FONT);int x=a.x+a.w+TM_ROW_GAP;return (TIORect){x,a.y+(a.h-h)/2,TIO_CORE_X1-x,h};}
static inline TIORect tm_next_rect(void){TIOSpan m=tio_band(TIO_SURFACE_PAGE,TIO_BAND_M);return (TIORect){TIO_CORE_X0,m.y0+20,TIO_CORE_W,TIO_LINE(TM_NEXT_FONT)};}   /* 76: the board's row */
/* Two lines of 24 px (28 each) fill band B. A one-line lyric is bottom-aligned on the band's edge, the line closest to the eye's
 * resting line of sight (LyricStack, PriorityBands): tm_cur_rect_for() sizes the box to the wrapped line count. */
_Static_assert(TIO_CORE_W==460,"the current-lyric label is the lens core wide");
static inline TIORect tm_cur_rect(void){TIOSpan b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);int h=2*TIO_LINE(TM_CUR_FONT);return (TIORect){TIO_CORE_X0,b.y1-h,TIO_CORE_W,h};}
static inline unsigned tm_lines(const char *wrapped){unsigned n=1;for(;*wrapped;wrapped++)if(*wrapped=='\n')n++;return n>2?2:n;}
static inline TIORect tm_cur_rect_for(const char *wrapped){TIOSpan b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);int h=(int)tm_lines(wrapped)*TIO_LINE(TM_CUR_FONT);return (TIORect){TIO_CORE_X0,b.y1-h,TIO_CORE_W,h};}
/* Lyric advance estimate. The nav bound (3/4 em for every Latin glyph) wraps a 28 character line at about 240 px
 * in a 460 px core; lyrics use a class-based estimate that still errs wide (the label clips at the core edge):
 * narrow glyphs 0.4 em, capitals 0.75 em, wide W M m w @ and all non-Latin 1 em, other Latin 0.6 em. */
static inline unsigned tm_advance(uint32_t c,unsigned font){
 if(c>=128||c=='W'||c=='M'||c=='w'||c=='m'||c=='@')return font;
 if(c==' '||c=='i'||c=='l'||c=='j'||c=='t'||c=='f'||c=='r'||c=='I'||c=='.'||c==','||c=='\''||c=='!'||c==':'||c==';'||c=='|')return (font*2+4)/5;
 if(c>='A'&&c<='Z')return (font*3+3)/4;
 return (font*3+4)/5;
}
/* Local copies of the nav_text.h wrap taking an advance callback (nav_text.h is byte-shared with the phone and stays as is). */
typedef unsigned (*TMAdvance)(uint32_t c,unsigned font);
static inline unsigned tm_width_with(const char *s,size_t n,unsigned font,TMAdvance adv){
 unsigned w=0;for(size_t i=0;i<n;){uint32_t c;unsigned k=tn_text_unit(s+i,n-i,&c);if(!k)return UINT32_MAX;w+=adv(c,font);i+=k;}return w;
}
static inline void tm_two_lines_with(const char *s,unsigned width,unsigned font,char *out,size_t cap,TMAdvance adv){
 size_t n=0;while(n<243&&s[n])n++;size_t at=0,used=0;if(!cap)return;out[0]=0;
 for(unsigned row=0;row<2&&at<n;row++){
  while(at<n&&s[at]==' ')at++;size_t end=at,last=at;unsigned w=0;
  while(end<n){uint32_t c;unsigned k=tn_text_unit(s+end,n-end,&c);if(!k)break;unsigned a=adv(c,font);if(w+a>width)break;w+=a;end+=k;if(c==' '||c>=0x2e80)last=end;}
  bool more=end<n;if(more&&last>at)end=last;
  if(row==1&&more){while(end>at&&tm_width_with(s+at,end-at,font,adv)+font>width){size_t prev=end-1;while(prev>at&&((uint8_t)s[prev]&192)==128)prev--;end=prev;}}
  while(end>at&&s[end-1]==' ')end--;size_t count=end-at;if(!count)break;
  if(used+count+5>cap)break;memcpy(out+used,s+at,count);used+=count;at=end;
  if(row==1&&more){memcpy(out+used,"\xe2\x80\xa6",3);used+=3;break;}
  if(at<n&&row==0)out[used++]='\n';
 }
 out[used]=0;
}
static inline unsigned tm_width(const char *s,size_t n,unsigned font){return tm_width_with(s,n,font,tm_advance);}
/* Up to two lines of the current lyric, wrapped against the label's own width (TIO_CORE_W); excess ends in an ellipsis. */
static inline void tm_two_lines(const char *raw,unsigned font,char *out,size_t cap){tm_two_lines_with(raw,TIO_CORE_W,font,out,cap,tm_advance);}
/* One line that fits `width`; text that does not fit ends with an ellipsis at a whole character. */
static inline void tm_one_line(const char *raw,unsigned width,unsigned font,char *out,size_t cap){
 char two[256];if(!cap)return;out[0]=0;tm_two_lines_with(raw,width,font,two,sizeof two,tm_advance);
 size_t n=0;while(two[n]&&two[n]!='\n')n++;const bool nl=two[n]=='\n';
 if(!nl&&tm_width(two,n,font)<=width){if(n>=cap)n=cap-1;memcpy(out,two,n);out[n]=0;return;}
 while(n&&tm_width(two,n,font)+font>width){size_t p=n-1;while(p&&((uint8_t)two[p]&192)==128)p--;n=p;}
 while(n&&two[n-1]==' ')n--;if(n+4>cap)n=cap>4?cap-4:0;memcpy(out,two,n);memcpy(out+n,"\xe2\x80\xa6",4);
}
/* 36x36 tile: 4x4 box average of the 144x144 cover scaled under lens-mid, inside a 2 px lens-mid frame.
 * `src` NULL (no cover yet) leaves the frame alone. */
static inline void tm_art_tile(const uint8_t *src,uint8_t *out){
 for(unsigned y=0;y<TM_ART;y++)for(unsigned x=0;x<TM_ART;x++){unsigned v=0;
  if(src){unsigned s=0;for(unsigned j=0;j<4;j++)for(unsigned i=0;i<4;i++)s+=src[(y*4+j)*TM_ART_SRC+x*4+i];v=s/16*TM_ART_LEVEL/255;}
  bool edge=x<TM_ART_FRAME||y<TM_ART_FRAME||x>=TM_ART-TM_ART_FRAME||y>=TM_ART-TM_ART_FRAME;out[y*TM_ART+x]=(uint8_t)(edge?TM_ART_LEVEL:v);}
}
#endif
