#include "focus-v1/focus_menu.h"
#include "focus-v1/tile_state.h"
#include "common-v1/tio_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {void *quad,*music,*focus,*camera;} TNNavSlot;
static TNNavSlot nav;
static uint8_t app[256];
static int root;
static uint32_t now=1000;
static TTVisible active,desired;
static bool pending;
static unsigned made;
static const char *texts[64];
static bool shown[64];
static bool idle(void *p){(void)p;return true;}
static void *create(void *p,void *parent){(void)p;(void)parent;return (void *)(uintptr_t)++made;}
static void *label(void *p,void *parent,unsigned font){assert(font==16||font==18||font==24);return create(p,parent);   /* TMG7 menu: names 16, status 18, focused name 24 */}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;(void)o;assert(x>=0&&y>=0&&x+w<=540&&y+h<=220);}
static void buffer(void *p,void *o,const uint8_t *b,unsigned w,unsigned h){(void)p;(void)o;assert(b&&w&&h);}
static void text(void *p,void *o,const char *s){(void)p;texts[(uintptr_t)o]=s;}
static void visible(void *p,void *o,bool b){(void)p;shown[(uintptr_t)o]=b;}
static void destroy(void *p,void *o){(void)p;(void)o;}
static bool attach(void *p,void *owner){return p&&owner;}
static void hidden(void *p,bool b){(void)p;(void)b;}
static const struct {void(*hidden)(void *,bool);} m8_native_api={hidden};
static TNWidgets widgets={NULL,idle,create,create,label,place,buffer,text,visible,destroy,NULL,NULL};
static TNNavSlot *slot(void *p){assert(p==app);return &nav;}
static bool detail(void *p){assert(p==app);return false;}
static void *ptr(void *p,unsigned off){assert(p==app);return off==4?&root:NULL;}
static void hide_legacy(void *p){assert(p==app);}
static TNWidgets tn_lvgl_widgets(void){return widgets;}
static bool native_has_flag(void *p,uint32_t flags){(void)p;(void)flags;return false;}
static bool focus_screen_on(void){return true;}
static bool fm_tiles_busy(void){return false;}
static bool fm_tiles_apply(void *p){assert(p==app);if(!pending)return false;active=desired;pending=false;*(uint32_t *)(app+0xa0)=active.count;return true;}
static void fm_tile_snapshot(TTVisible *out){*out=active;}
static unsigned fm_tile_count(void){return active.count;}
static void m8_refresh_tile_label(void *p,int id){(void)p;(void)id;}
static uint32_t stream_tick(void){return now;}
/* TMG8 live tile state: the services are stubbed with one fixture; the phone link goes through the same nav_* calls as the production code. */
static bool link_up;static unsigned lang_now;static TSLive fixture;static int monitor,music_slot,camera_slot;
static void *nav_monitors(void){return &monitor;}
static void *nav_link(void *m){return m;}
static bool nav_bonded(void *l){(void)l;return link_up;}
static int nav_connection(unsigned which){assert(which==0x80);return link_up?1:0;}
static void tf_live(uint32_t t,TSLive *o){(void)t;o->pomodoro=fixture.pomodoro;o->pomodoro_ms=fixture.pomodoro_ms;}
static void tm_slot_live(void *s,uint32_t t,TSLive *o){assert(s==&music_slot);(void)t;o->music_playing=fixture.music_playing;o->music_age_ms=fixture.music_age_ms;o->music_title=fixture.music_title;}
static void tn_slot_live(TNNavSlot *s,TSLive *o){assert(s==&nav);o->nav_active=fixture.nav_active;o->nav_stale=fixture.nav_stale;o->nav_remaining_m=fixture.nav_remaining_m;}
static void tc_slot_live(void *s,TSLive *o){assert(s==&camera_slot);o->camera=fixture.camera;}
static void *fm_system(void *p){return p;}
static void *fm_battery_monitor(void *p){return p;}
static int64_t fm_local_time(void *p){(void)p;return 0;}
static int fm_battery_level(void *p){(void)p;return -1;}
static void stream_timer_period(void *p,uint32_t ms){(void)p;assert(ms==16);}
unsigned tio_lang(void){return lang_now;}
#include "focus_native_sync.inc"
static FMControl control;
int main(void){
 nav.music=&music_slot;nav.camera=&camera_slot;
 TTConfig c;tt_default(&c);assert(tt_compact(&c,&active));assert(fm_view_open(&control.view,&widgets,&root,attach,&control));control.app=app;control.enabled=true;control.desired_rows=3;control.selection=-1;nav.quad=&control;*(uint32_t *)(app+0x88)=7;
 fm_sync(app);assert(control.selection==7&&control.view.selected==7&&!strcmp(texts[(uintptr_t)control.view.labels[7]],tio_text(TT_GRID_DISPLAY,0)));
 assert(tt_unrank(719,0xf80,&c)&&tt_compact(&c,&desired));pending=true;now++;fm_sync(app);
 assert(active.count==8&&control.view.selected==7&&control.selection==7);assert(!strcmp(texts[(uintptr_t)control.view.labels[7]],tio_text(TT_TILE_CAMERA,0)));assert(!shown[(uintptr_t)control.view.labels[8]]);
 control.desired_rows=FM_CAROUSEL;now+=1000;fm_sync(app);assert(control.view.rows==FM_CAROUSEL&&control.view.selected==7&&control.selection==7&&!shown[(uintptr_t)control.view.page]);   /* a stored layout 1 reaches the view */
 control.desired_rows=2;now+=1000;fm_sync(app);assert(control.view.rows==2&&shown[(uintptr_t)control.view.page]);

 /* TMG8 live tile state through the production fm_sync, with stubbed services: carousel status line for the focused tile, grid state dots. */
 {static const char song[]="Blinding Lights";
  tt_default(&c);assert(tt_compact(&c,&desired));pending=true;now+=1000;control.desired_rows=FM_CAROUSEL;fm_sync(app);assert(active.count==13);
  unsigned rank[13];for(unsigned r=0;r<13;r++)rank[active.ids[r]]=r;
  const uintptr_t line=(uintptr_t)control.view.line;
  #define GO(tile) do{*(uint32_t *)(app+0x88)=rank[tile];now+=1100;fm_sync(app);(void)fm_view_step(&control.view,now+400);assert(control.view.selected==(int)rank[tile]);}while(0)
  #define LINE(want) do{if(*(want)){assert(shown[line]&&!strcmp(texts[line],want));}else assert(!shown[line]||!*texts[line]);}while(0)
  /* the board's "something running": navigation 1.2 km, music playing, pomodoro 18:42 */
  link_up=true;fixture=(TSLive){.pomodoro=true,.pomodoro_ms=18*60000+42000,.music_playing=true,.music_age_ms=1000,.music_title=song,.nav_active=true,.nav_remaining_m=1200};
  GO(TIO_TILE_NAVIGATION);LINE("1.2 km to go");GO(TIO_TILE_MUSIC);LINE("Playing \xc2\xb7 Blinding Lights");GO(TIO_TILE_FOCUS);LINE("18:42 left");
  GO(TIO_TILE_CAMERA);LINE("");GO(TIO_TILE_APPS);LINE("");GO(TIO_TILE_DISPLAY);LINE("");GO(0);LINE("");
  /* updates while the focus stays: the 1 Hz refresh rewrites the line, an unchanged line is not rewritten */
  GO(TIO_TILE_FOCUS);fixture.pomodoro_ms=18*60000+41000;now+=1100;fm_sync(app);LINE("18:41 left");
  {const char *kept=texts[line];now+=1100;fm_sync(app);assert(texts[line]==kept);}
  /* Chinese follows the language switch on the next refresh */
  lang_now=1;control.relabel=true;now+=1100;fm_sync(app);LINE("\xe5\x89\xa9\xe4\xbd\x99 18:41");GO(TIO_TILE_MUSIC);LINE("\xe6\xad\xa3\xe5\x9c\xa8\xe6\x92\xad\xe6\x94\xbe \xc2\xb7 Blinding Lights");lang_now=0;control.relabel=true;now+=1100;fm_sync(app);LINE("Playing \xc2\xb7 Blinding Lights");
  /* nothing running */
  fixture=(TSLive){0};GO(TIO_TILE_NAVIGATION);LINE("");GO(TIO_TILE_MUSIC);LINE("");GO(TIO_TILE_FOCUS);LINE("");
  /* phone not connected: navigation and music say so, the pomodoro keeps counting */
  link_up=false;fixture=(TSLive){.pomodoro=true,.pomodoro_ms=18*60000+42000};
  GO(TIO_TILE_NAVIGATION);LINE("Phone not connected");GO(TIO_TILE_MUSIC);LINE("Phone not connected");GO(TIO_TILE_FOCUS);LINE("18:42 left");GO(TIO_TILE_CAMERA);LINE("");GO(TIO_TILE_APPS);LINE("");
  /* the grid: a dot on the tiles with a running state, none for "Phone not connected" and none for stock apps */
  #define DOTS() ({unsigned m=0;for(unsigned i=0;i<9;i++)if(shown[(uintptr_t)control.view.dots[i]]){unsigned at=(unsigned)control.view.selected/6*6+i;assert(at<13);m|=1u<<active.ids[at];}m;})
  control.desired_rows=2;link_up=true;fixture=(TSLive){.pomodoro=true,.pomodoro_ms=60000,.music_playing=true,.music_age_ms=1000,.music_title=song,.nav_active=true,.nav_remaining_m=300,.camera=true};
  GO(TIO_TILE_FOCUS);assert(control.view.rows==2&&control.view.live_mask==((1u<<TIO_TILE_NAVIGATION)|(1u<<TIO_TILE_MUSIC)|(1u<<TIO_TILE_FOCUS)|(1u<<TIO_TILE_CAMERA)));
  GO(TIO_TILE_NAVIGATION);assert(DOTS()==((1u<<TIO_TILE_NAVIGATION)|(1u<<TIO_TILE_MUSIC)|(1u<<TIO_TILE_FOCUS)));   /* page 2 of 2: navigation, music, pomodoro; camera is on the next page */
  GO(TIO_TILE_CAMERA);assert(DOTS()==((1u<<TIO_TILE_CAMERA)));
  link_up=false;fixture.camera=false;fixture.nav_active=false;GO(TIO_TILE_NAVIGATION);assert(control.view.live_mask==(1u<<TIO_TILE_FOCUS));assert(DOTS()==(1u<<TIO_TILE_FOCUS));
  fixture=(TSLive){0};link_up=true;GO(TIO_TILE_NAVIGATION);assert(control.view.live_mask==0&&DOTS()==0);
  /* a renderer that is busy leaves everything as it was and retries */
  fixture.pomodoro=true;fixture.pomodoro_ms=5000;control.desired_rows=FM_CAROUSEL;GO(TIO_TILE_FOCUS);
 }
 puts("PASS native fm_sync: unchanged selected rank immediately redraws changed canonical tiles before dispatch");
}
