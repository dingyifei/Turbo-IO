#ifndef TURBO_TILE_STATE_H
#define TURBO_TILE_STATE_H
/* TMG8 live tile state (LensMenuCarousel.dc.html status line, LensMenuGrid2.dc.html state dot).
 * Pure text and decisions over a TSLive snapshot, so the host tests can stub every global. Strings go through tio_text
 * (English and Chinese); the middle dot is added here because tio_text English stays ASCII.
 *   Pomodoro   running or paused      "<mm:ss> left"            (works without the phone: the timer is local)
 *   Music      playing, phone spoke   "Playing · <title>"       (last contact within 30 s, the same window as tm_expired)
 *   Navigation route, not stale       "<n> km to go"            ("<n> m to go" under 950 m)
 *   Camera     session open           "Live view"
 *   Music, Navigation, phone link down "Phone not connected"    (no dot: nothing is running)
 * Stock apps and every other tile: no line, no dot. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "tile_live.h"
#include "../common-v1/tio_text.h"
#include "../common-v1/tio_ui.h"
#include "../music-runtime-v1/menu_tiles.h"
#include "../music-runtime-v1/music_layout.h"
enum { TS_LINE_MAX=96, TS_MUSIC_FRESH_MS=30000, TS_TITLE_MAX=95 };
typedef struct {bool active,phone_off;char line[TS_LINE_MAX];} TSState;   /* active: live state (dot); phone_off: the "Phone not connected" line, no dot */
static inline char *ts_u32(char *p,uint32_t n){char v[10];unsigned k=0;do{v[k++]=(char)('0'+n%10);n/=10;}while(n);while(k)*p++=v[--k];return p;}
/* Replace the first "{}" in `pattern` with `value`; always NUL-terminated within cap. */
static inline void ts_pattern(char *out,size_t cap,const char *pattern,const char *value){
 size_t at=0;if(!cap)return;
 bool done=false;
 for(const char *p=pattern;*p&&at+1<cap;){if(!done&&p[0]=='{'&&p[1]=='}'){for(const char *v=value;*v&&at+1<cap;v++)out[at++]=*v;p+=2;done=true;}else out[at++]=*p++;}
 out[at]=0;
}
/* One line that fits the lens core at 16 px (the width estimate errs wide, and the label also clips). Text that does not fit is cut at a
 * character, not at a word (a title may be one long word), and ends with an ellipsis; bytes that are not valid UTF-8 are never shown. */
static inline void ts_fit(const char *raw,char *out,size_t cap){
 const size_t n=strlen(raw);if(!cap)return;
 if(n<cap&&tm_width(raw,n,TIO_FONT_MIN)<=TIO_CORE_W){memcpy(out,raw,n+1);return;}
 size_t at=0;unsigned w=0;
 while(at<n){uint32_t c;unsigned k=tn_text_unit(raw+at,n-at,&c);if(!k)break;w+=tm_advance(c,TIO_FONT_MIN);if(w+TIO_FONT_MIN>TIO_CORE_W||at+k+4>cap)break;at+=k;}
 while(at&&raw[at-1]==' ')at--;
 if(at+4>cap)at=cap>4?cap-4:0;
 memcpy(out,raw,at);memcpy(out+at,"\xe2\x80\xa6",4);
}
static inline void ts_time(char *out,uint32_t ms){uint32_t s=(ms+999)/1000;char *p=out;if(s/60<10)*p++='0';p=ts_u32(p,s/60);*p++=':';*p++=(char)('0'+s%60/10);*p++=(char)('0'+s%10);*p=0;}
/* Metres to a kilometre figure with one decimal ("1.2"), or whole kilometres from 100 km; under 950 m the figure is metres to 10 m. */
static inline bool ts_distance(char *out,uint32_t m){
 char *p=out;
 if(m>=950){uint32_t tenths=(m+50)/100;if(tenths>=1000){p=ts_u32(p,(m+500)/1000);}else{p=ts_u32(p,tenths/10);*p++='.';*p++=(char)('0'+tenths%10);}*p=0;return true;}
 uint32_t r=(m+5)/10*10;p=ts_u32(p,r<10?10:r);*p=0;return false;
}
static inline void ts_state(unsigned tile,const TSLive *in,unsigned lang,TSState *out){
 char raw[TS_LINE_MAX*2],value[16];memset(out,0,sizeof *out);if(!in)return;
 switch(tile){
 case TIO_TILE_FOCUS:
  if(!in->pomodoro)break;
  ts_time(value,in->pomodoro_ms);ts_pattern(raw,sizeof raw,tio_text(TT_STATE_TIME_LEFT,lang),value);ts_fit(raw,out->line,sizeof out->line);out->active=true;break;
 case TIO_TILE_MUSIC:
  if(!in->phone){ts_fit(tio_text(TT_STATE_PHONE_OFF,lang),out->line,sizeof out->line);out->phone_off=true;break;}
  if(in->music_playing&&in->music_age_ms<=TS_MUSIC_FRESH_MS){
   size_t at=0;const char *head=tio_text(TT_STATE_PLAYING,lang);while(head[at]&&at<sizeof raw-1){raw[at]=head[at];at++;}
   size_t n=0;if(in->music_title){while(n<TS_TITLE_MAX&&in->music_title[n])n++;
    if(in->music_title[n])while(n&&((uint8_t)in->music_title[n]&0xc0)==0x80)n--;}   /* cut at a character boundary */
   if(n&&at+4+n<sizeof raw){raw[at++]=' ';raw[at++]=(char)0xc2;raw[at++]=(char)0xb7;raw[at++]=' ';memcpy(raw+at,in->music_title,n);at+=n;}
   raw[at]=0;ts_fit(raw,out->line,sizeof out->line);out->active=true;
  }
  break;
 case TIO_TILE_NAVIGATION:
  if(!in->phone){ts_fit(tio_text(TT_STATE_PHONE_OFF,lang),out->line,sizeof out->line);out->phone_off=true;break;}
  if(in->nav_active&&!in->nav_stale&&in->nav_remaining_m){
   bool km=ts_distance(value,in->nav_remaining_m);ts_pattern(raw,sizeof raw,tio_text(km?TT_STATE_KM_TO_GO:TT_STATE_M_TO_GO,lang),value);ts_fit(raw,out->line,sizeof out->line);out->active=true;
  }
  break;
 case TIO_TILE_CAMERA:
  if(in->camera){ts_fit(tio_text(TT_CAM_LIVE,lang),out->line,sizeof out->line);out->active=true;}
  break;
 default:break;
 }
}
#endif
