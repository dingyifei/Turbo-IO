#ifndef TURBO_MUSIC_LAYOUT_H
#define TURBO_MUSIC_LAYOUT_H
/* LensMusic (docs/design-system/screens/LensMusic.dc.html, components/LyricStack), TMG7; TMG8 never truncates the current lyric.
 * Kept out of music.c, which is byte-shared with the phone, so no wire or shared-source change.
 * Band T: 36x36 artwork tile and the track in lens-mid, replaced by the transient control hint.
 * Band M: the next lyric, one line of lens-body in lens-high. Band B: the current lyric in lens-full, bottom-aligned on y 172.
 * The current lyric fits in this order (tm_fit_current): 1) up to 2 lines of 24 px in band B with the next lyric shown;
 * 2) up to 4 lines of 24 px growing up into band M (top y 60) with the next lyric hidden; 3) 4 lines of 20 px;
 * 4) 5 lines of 16 px. Only text that still does not fit at step 4 ends in an ellipsis. The previous line is dropped.
 * Nothing else is drawn. */
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
/* The current lyric is bottom-aligned on band B's bottom edge (LyricStack, PriorityBands): the line closest to the eye's resting line of
 * sight. Its box is sized to the wrapped line count at the fitted font; TMFit says which. */
_Static_assert(TIO_CORE_W==460,"the current-lyric label is the lens core wide");
#define TM_CUR_SLOTS 3u   /* one label per font: the stock label API has no font setter (nav_view does the same) */
/* The widest text that can still fit step 4 is 140 four-byte glyphs (28 per 16 px row, 5 rows) = 560 bytes; a narrow Latin run is at most
 * 328. So 575 source bytes never hide a lyric that would have fit, and anything longer ends in the ellipsis anyway. */
#define TM_CUR_RAW 576u   /* source buffer for the current lyric, NUL included */
#define TM_CUR_CAP 576u   /* wrapped output: at most 560 glyph bytes + 4 row breaks + the 3 byte ellipsis + NUL */
#define TM_CUR_MAX_ROWS 5u
static inline unsigned tm_cur_slot_font(unsigned slot){return slot==0?TIO_FONT_TITLE:slot==1?TIO_FONT_BODY:TIO_FONT_MIN;}
static inline unsigned tm_cur_slot_rows(unsigned slot){return slot==2?5u:4u;}
static inline unsigned tm_cur_slot(unsigned font){return font==TIO_FONT_TITLE?0u:font==TIO_FONT_BODY?1u:2u;}
/* The label's largest box (its creation rect): the most rows its font may take, ending at band B's bottom edge. */
static inline TIORect tm_cur_rect(unsigned slot){TIOSpan b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);int h=(int)tm_cur_slot_rows(slot)*TIO_LINE(tm_cur_slot_font(slot));return (TIORect){TIO_CORE_X0,b.y1-h,TIO_CORE_W,h};}
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
/* Lyric sources come from LRC files: a CR, a tab or a zero width space would stop the wrap at that byte and silently drop the rest of the
 * line (tn_text_unit refuses it). Tabs and line feeds become a space; every other unreadable byte is dropped, in place. */
static inline void tm_clean(char *s){
 size_t n=0,o=0;while(s[n])n++;for(size_t i=0;i<n;){uint32_t c;unsigned k=tn_text_unit(s+i,n-i,&c);
  if(k){for(unsigned j=0;j<k;j++)s[o+j]=s[i+j];o+=k;i+=k;}else{if(s[i]=='\t'||s[i]=='\n')s[o++]=' ';i++;}}   /* o <= i: the copy never overruns */
 s[o]=0;
}
/* Wrap `s` (at most TM_CUR_RAW-1 bytes) onto at most `rows` rows of `width`. Returns true when all of it fits. Without `ellipsis` a text that does not
 * fit returns false (out holds the rows that did); with it the last row is cut at a whole character and ends in an ellipsis. */
static inline bool tm_rows_with(const char *s,unsigned width,unsigned font,unsigned rows,bool ellipsis,char *out,size_t cap,TMAdvance adv){
 size_t n=0;while(n<TM_CUR_RAW-1&&s[n])n++;size_t at=0,used=0;if(!cap)return false;out[0]=0;bool fits=true;
 for(unsigned row=0;row<rows&&at<n;row++){
  while(at<n&&s[at]==' ')at++;size_t end=at,last=at;unsigned w=0;
  while(end<n){uint32_t c;unsigned k=tn_text_unit(s+end,n-end,&c);if(!k)break;unsigned a=adv(c,font);if(w+a>width)break;w+=a;end+=k;if(c==' '||c>=0x2e80)last=end;}
  bool more=end<n;if(more&&last>at)end=last;
  if(row==rows-1&&more){if(!ellipsis){fits=false;}else while(end>at&&tm_width_with(s+at,end-at,font,adv)+font>width){size_t prev=end-1;while(prev>at&&((uint8_t)s[prev]&192)==128)prev--;end=prev;}}
  while(end>at&&s[end-1]==' ')end--;size_t count=end-at;if(!count)break;
  if(used+count+5>cap){fits=false;break;}memcpy(out+used,s+at,count);used+=count;at=end;while(at<n&&s[at]==' ')at++;   /* spaces after a row are not a row */
  if(row==rows-1&&more){if(ellipsis){memcpy(out+used,"\xe2\x80\xa6",3);used+=3;}break;}
  if(at<n&&row<rows-1)out[used++]='\n';
 }
 if(used&&out[used-1]=='\n')used--;   /* a tail that cannot be read (bad UTF-8) leaves no empty row */
 out[used]=0;return fits;
}
static inline void tm_two_lines_with(const char *s,unsigned width,unsigned font,char *out,size_t cap,TMAdvance adv){(void)tm_rows_with(s,width,font,2,true,out,cap,adv);}
static inline unsigned tm_width(const char *s,size_t n,unsigned font){return tm_width_with(s,n,font,tm_advance);}
/* The current lyric's fit. `step` is 1..4 (see the header); `next` says whether the next lyric's row is shown, which is exactly when the
 * lyric fits band B (step 1, at most two lines). */
typedef struct {unsigned step,font,lines;bool next;} TMFit;
static inline unsigned tm_count_lines(const char *wrapped){unsigned n=1;for(;*wrapped;wrapped++)if(*wrapped=='\n')n++;return n;}
/* Wrap the current lyric against the label's own width (TIO_CORE_W) into `out` (TM_CUR_CAP bytes). Below step 4 nothing is cut and no
 * ellipsis is added: the first step whose font and row count hold the whole text wins. */
static inline TMFit tm_fit_current(const char *raw,char *out,size_t cap){
 static const struct {unsigned font,rows;} steps[4]={{TIO_FONT_TITLE,2},{TIO_FONT_TITLE,4},{TIO_FONT_BODY,4},{TIO_FONT_MIN,5}};
 TMFit f={4,TIO_FONT_MIN,1,false};
 for(unsigned i=0;i<4;i++){bool last=i==3;
  if(tm_rows_with(raw,TIO_CORE_W,steps[i].font,steps[i].rows,last,out,cap,tm_advance)||last){f.step=i+1;f.font=steps[i].font;f.lines=tm_count_lines(out);f.next=i==0;return f;}}
 return f;
}
/* The box of the fitted lyric: its lines at the fitted font, ending on band B's bottom edge (a one-line lyric sits on the bottom row). */
static inline TIORect tm_cur_rect_for(const TMFit *f){TIOSpan b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);int h=(int)f->lines*TIO_LINE(f->font);return (TIORect){TIO_CORE_X0,b.y1-h,TIO_CORE_W,h};}
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
