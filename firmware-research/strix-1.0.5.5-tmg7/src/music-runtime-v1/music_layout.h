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
/* Two lines of 24 px (28 each) fill band B, bottom-aligned on its edge. */
static inline TIORect tm_cur_rect(void){TIOSpan b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);int h=2*TIO_LINE(TM_CUR_FONT);return (TIORect){TIO_CORE_X0,b.y1-h,TIO_CORE_W,h};}
/* One line that fits `width`; text that does not fit ends with an ellipsis at a whole character. */
static inline void tm_one_line(const char *raw,unsigned width,unsigned font,char *out,size_t cap){
 char two[256];if(!cap)return;out[0]=0;tn_text_two_lines(raw,width,font,two,sizeof two);
 size_t n=0;while(two[n]&&two[n]!='\n')n++;const bool nl=two[n]=='\n';
 if(!nl&&tn_text_width(two,n,font)<=width){if(n>=cap)n=cap-1;memcpy(out,two,n);out[n]=0;return;}
 while(n&&tn_text_width(two,n,font)+font>width){size_t p=n-1;while(p&&((uint8_t)two[p]&192)==128)p--;n=p;}
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
