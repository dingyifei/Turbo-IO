#include "focus-v1/focus_menu.h"
#include "focus-v1/tile_state.h"
#include "common-v1/tio_text.h"
#include "navigation-runtime-v1/menu9.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Stand-ins for the module slots: hide_legacy reads only their row and icon. */
typedef struct {void *row,*label,*icon,*dot;} SlotObjects;
typedef SlotObjects TMMusicSlot;typedef SlotObjects TFSlot;typedef SlotObjects TCSlot;typedef SlotObjects TAPMenu;
typedef struct {void *quad;TMMusicSlot *music;TFSlot *focus;TCSlot *camera;void *row,*icon;TAPMenu *apps;} TNNavSlot;
static TNNavSlot nav;
/* the stock menu object plus the module tail, as port_allocate_menu allocates it */
_Alignas(16) static uint8_t app[TIO_TAIL_END];
static int root;
/* hide_legacy (sliced from focus_menu_native.c) reaches the module objects through tail() and slot(); stock's rows, lottie and dots
 * parent through ptr(). Every object it may hide is a distinct address here, and m8_native_api.hidden counts the hides. */
static M8NativeTail tail_storage;static bool unarmed;
static M8NativeTail *tail(void *p){assert(p==app);return unarmed?NULL:&tail_storage;}
static int rows[TIO_STOCK_MENU_TILES+1],lottie,dots_parent,module_objects[12];
static unsigned row_hides[TIO_STOCK_MENU_TILES+1],module_hides[12],lottie_hides,hidden_calls;static bool dots_hidden;
static uint32_t now=1000;
static TTVisible active,desired;
static bool pending;
static unsigned made;
static const char *texts[64];
static bool shown[64];
static bool busy;   /* the renderer refuses every draw while set */
/* fm_show tests: the timer period, and the period when fm_sync first asks the renderer (0 until then). */
static bool showing;static uint32_t period,seen;
static bool idle(void *p){(void)p;if(showing&&!seen)seen=period;return !busy;}
static void *create(void *p,void *parent){(void)p;(void)parent;return (void *)(uintptr_t)++made;}
static void *label(void *p,void *parent,unsigned font){assert(font==16||font==18||font==24);return create(p,parent);   /* TMG7 menu: names 16, status 18, focused name 24 */}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;(void)o;assert(x>=0&&y>=0&&x+w<=540&&y+h<=220);}
/* TMG9: the stock draw buffer rounds the pointer up to 64 (align_pointer_cb at 0x104610f9), so a canvas buffer that is not 64 byte aligned is drawn from the next boundary. */
static void buffer(void *p,void *o,const uint8_t *b,unsigned w,unsigned h){(void)p;(void)o;assert(b&&w&&h);if(((uintptr_t)b&63)!=0){fprintf(stderr,"UNALIGNED canvas buffer w=%u h=%u mod64=%u\n",w,h,(unsigned)((uintptr_t)b&63));abort();}}
static void text(void *p,void *o,const char *s){(void)p;texts[(uintptr_t)o]=s;}
static void visible(void *p,void *o,bool b){(void)p;shown[(uintptr_t)o]=b;}
static void destroy(void *p,void *o){(void)p;(void)o;}
static bool attach(void *p,void *owner){return p&&owner;}
static void hidden(void *p,bool b){hidden_calls++;
 for(unsigned i=0;i<=TIO_STOCK_MENU_TILES;i++)if(p==&rows[i]&&b)row_hides[i]++;
 for(unsigned i=0;i<12;i++)if(p==&module_objects[i]&&b)module_hides[i]++;
 if(p==&lottie&&b)lottie_hides++;if(p==&dots_parent)dots_hidden=b;}
static const struct {void(*hidden)(void *,bool);} m8_native_api={hidden};
static TNWidgets widgets={NULL,idle,create,create,label,place,buffer,text,visible,destroy,NULL,NULL};
/* slot(), detail() and fm_menu_plain() are the production bodies (sliced); they see the services through these. */
static bool camera_up,apps_up,nav_up,music_up,focus_up;
static bool tc_native_visible(void *p){assert(p==app);return camera_up;}
static bool tap_service_visible(void *p){assert(p==app);return apps_up;}
static bool tn_slot_visible(TNNavSlot *s){assert(s==&nav);return nav_up;}
static bool tm_slot_visible(TMMusicSlot *s){(void)s;return music_up;}
static bool tf_slot_visible(TFSlot *s){(void)s;return focus_up;}
static void *ptr(void *p,unsigned off){assert(p==app);
 if(off==TIO_STOCK_MENU_ROOT)return &root;if(off==TIO_STOCK_MENU_LOTTIE)return &lottie;if(off==TIO_STOCK_MENU_DOTS_PARENT)return &dots_parent;
 for(unsigned i=0;i<=TIO_STOCK_MENU_TILES;i++)if(off==TIO_STOCK_MENU_ROWS+sizeof(uint32_t)*i)return &rows[i];   /* one past stock's rows too: never hidden */
 return NULL;}
static TNWidgets tn_lvgl_widgets(void){return widgets;}
static bool native_has_flag(void *p,uint32_t flags){(void)p;(void)flags;return false;}
static bool focus_screen_on(void){return true;}
static bool fm_tiles_busy(void){return false;}
static unsigned applies;
static bool fm_tiles_apply(void *p){assert(p==app);applies++;if(!pending)return false;active=desired;pending=false;*(uint32_t *)(app+TIO_STOCK_MENU_MOTION+TIO_STOCK_MOTION_COUNT)=active.count;return true;}
static void fm_tile_snapshot(TTVisible *out){*out=active;}
static unsigned fm_tile_count(void){return active.count;}
static void m8_refresh_tile_label(void *p,int id){(void)p;(void)id;}
static uint32_t stream_tick(void){return now;}
/* TMG8 live tile state: the services are stubbed with one fixture; the phone link goes through the same nav_* calls as the production code. */
static bool link_up;static unsigned lang_now;static TSLive fixture;static int monitor;static TMMusicSlot music_slot;static TCSlot camera_slot;static TFSlot focus_slot;static TAPMenu apps_menu;
static void *nav_monitors(void){return &monitor;}
static void *nav_link(void *m){return m;}
static bool nav_bonded(void *l){(void)l;return link_up;}
static int nav_connection(unsigned which){assert(which==0x80);return link_up?1:0;}
static void tf_live(uint32_t t,TSLive *o){(void)t;o->pomodoro=fixture.pomodoro;o->pomodoro_ms=fixture.pomodoro_ms;}
static void tm_slot_live(void *s,uint32_t t,TSLive *o){assert(s==&music_slot);(void)t;o->music_playing=fixture.music_playing;o->music_age_ms=fixture.music_age_ms;o->music_title=fixture.music_title;}
static void tn_slot_live(TNNavSlot *s,TSLive *o){assert(s==&nav);o->nav_active=fixture.nav_active;o->nav_stale=fixture.nav_stale;o->nav_remaining_m=fixture.nav_remaining_m;o->nav_turn=fixture.nav_turn;o->nav_icon=fixture.nav_icon;o->nav_turn_m=fixture.nav_turn_m;memcpy(o->nav_road,fixture.nav_road,sizeof o->nav_road);}
static void tc_slot_live(void *s,TSLive *o){assert(s==&camera_slot);o->camera=fixture.camera;}
static void *fm_system(void *p){return p;}
static void *fm_battery_monitor(void *p){return p;}
static int64_t fm_local_time(void *p){(void)p;return 0;}
static int fm_battery_level(void *p){(void)p;return -1;}
/* fm_sync only ever speeds the timer up to 16 ms; fm_show puts it back to the active rate. */
static int timer_token;
static void stream_timer_period(void *p,uint32_t ms){assert(ms==16||(showing&&ms==100));if(p==&timer_token)period=ms;}
/* fm_show creates a controller only when it has none; the cases below always give it one, so these are never reached. */
static bool room(void){abort();}
static void *stream_memalign(size_t a,size_t n){(void)a;(void)n;abort();}
static void stream_free(void *p){(void)p;abort();}
static void *stream_timer_create(void (*f)(void *),uint32_t ms,void *u){(void)f;(void)ms;(void)u;abort();}
static unsigned fm_menu_rows(void){abort();}
static void menu_text_align(void *o,int a,uint32_t st){(void)o;(void)a;(void)st;abort();}
static bool attach_deleted(void *root,void *owner){(void)root;(void)owner;abort();}
static void tick(void *t){(void)t;abort();}
unsigned tio_lang(void){return lang_now;}
#include "focus_native_sync.inc"
static FMControl control;
int main(void){
 nav.music=&music_slot;nav.camera=&camera_slot;nav.focus=&focus_slot;nav.apps=&apps_menu;
 void **objects[12]={&camera_slot.row,&camera_slot.icon,&tail_storage.row,&tail_storage.icon,&nav.row,&nav.icon,&music_slot.row,&music_slot.icon,&focus_slot.row,&focus_slot.icon,&apps_menu.row,&apps_menu.icon};
 for(unsigned i=0;i<12;i++)*objects[i]=&module_objects[i];
 tail_storage.navigation=&nav;
 /* An unarmed menu counts as busy, so it is never plain: the remote's knob grants and accepts nothing for it. */
 unarmed=true;assert(!slot(app)&&detail(app)&&!fm_menu_plain(app));unarmed=false;
 /* Armed with nothing open: plain. Any open module page, service or tail page makes it busy. */
 assert(slot(app)==&nav&&!detail(app)&&fm_menu_plain(app));
 {bool *open[]={&camera_up,&apps_up,&nav_up,&music_up,&focus_up};
  for(unsigned i=0;i<sizeof open/sizeof *open;i++){*open[i]=true;assert(detail(app)&&!fm_menu_plain(app));*open[i]=false;}
  static _Alignas(16) uint8_t page[64];tail_storage.page=(M8Page *)page;   /* detail() only tests the pointer */assert(detail(app)&&!fm_menu_plain(app));tail_storage.page=NULL;assert(fm_menu_plain(app));}
 /* An unarmed menu: fm_sync does nothing at all (no hide, no tile apply, no view change). */
 {TTConfig d;tt_default(&d);assert(tt_compact(&d,&active));unarmed=true;pending=true;fm_sync(app);assert(hidden_calls==0&&applies==0&&pending);unarmed=false;pending=false;}
 TTConfig c;tt_default(&c);assert(tt_compact(&c,&active));assert(fm_view_open(&control.view,&widgets,&root,attach,&control));control.app=app;control.enabled=true;control.desired_rows=3;control.selection=-1;nav.quad=&control;*(uint32_t *)(app+TIO_STOCK_MENU_SELECTED)=TIO_TILE_DISPLAY;
 fm_sync(app);assert(control.selection==TIO_TILE_DISPLAY&&control.view.selected==TIO_TILE_DISPLAY&&!strcmp(texts[(uintptr_t)control.view.labels[TIO_TILE_DISPLAY]],tio_text(TT_GRID_DISPLAY,0)));
 assert(!strcmp(texts[(uintptr_t)control.view.labels[4]],tio_text(TT_GRID_NAVIGATION,0)));   /* stock Navigation at id 4 on 1.0.6.11 */
 /* The module view is up: hide_legacy hid each of stock's TIO_STOCK_MENU_TILES rows once (and no row past them), the lottie and every module
  * row and icon; fm_sync hid the stock dots parent. */
 for(unsigned i=0;i<TIO_STOCK_MENU_TILES;i++)assert(row_hides[i]==1);assert(row_hides[TIO_STOCK_MENU_TILES]==0&&lottie_hides==1&&dots_hidden);
 for(unsigned i=0;i<12;i++)assert(module_hides[i]==1);
 assert(tt_unrank(719,TT_HIDEABLE,&c)&&tt_compact(&c,&desired));pending=true;now++;fm_sync(app);
 assert(active.count==TT_MIN_VISIBLE&&control.view.selected==TIO_TILE_DISPLAY&&control.selection==TIO_TILE_DISPLAY);assert(!strcmp(texts[(uintptr_t)control.view.labels[TIO_TILE_DISPLAY]],tio_text(TT_TILE_CAMERA,0)));assert(!shown[(uintptr_t)control.view.labels[TIO_TILE_DISPLAY]]);
 control.desired_rows=FM_CAROUSEL;now+=1000;fm_sync(app);assert(control.view.rows==FM_CAROUSEL&&control.view.selected==TIO_TILE_DISPLAY&&control.selection==TIO_TILE_DISPLAY&&!shown[(uintptr_t)control.view.page]);   /* a stored layout 1 reaches the view */
 control.desired_rows=2;now+=1000;fm_sync(app);assert(control.view.rows==2&&shown[(uintptr_t)control.view.page]);

 /* TMG8 live tile state through the production fm_sync, with stubbed services: carousel status line for the focused tile, grid state dots. */
 {static const char song[]="Blinding Lights";
  tt_default(&c);assert(tt_compact(&c,&desired));pending=true;now+=1000;control.desired_rows=FM_CAROUSEL;fm_sync(app);assert(active.count==TT_ITEMS);
  unsigned rank[TT_ITEMS];for(unsigned r=0;r<TT_ITEMS;r++)rank[active.ids[r]]=r;
  const uintptr_t line=(uintptr_t)control.view.line;
  #define GO(tile) do{*(uint32_t *)(app+TIO_STOCK_MENU_SELECTED)=rank[tile];now+=1100;fm_sync(app);(void)fm_view_step(&control.view,now+400);assert(control.view.selected==(int)rank[tile]);}while(0)
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
  #define DOTS() ({unsigned m=0;for(unsigned i=0;i<9;i++)if(shown[(uintptr_t)control.view.dots[i]]){unsigned at=(unsigned)control.view.selected/6*6+i;assert(at<TT_ITEMS);m|=1u<<active.ids[at];}m;})
  control.desired_rows=2;link_up=true;fixture=(TSLive){.pomodoro=true,.pomodoro_ms=60000,.music_playing=true,.music_age_ms=1000,.music_title=song,.nav_active=true,.nav_remaining_m=300,.camera=true};
  GO(TIO_TILE_FOCUS);assert(control.view.rows==2&&control.view.live_mask==((1u<<TIO_TILE_NAVIGATION)|(1u<<TIO_TILE_MUSIC)|(1u<<TIO_TILE_FOCUS)|(1u<<TIO_TILE_CAMERA)));
  GO(TIO_TILE_NAVIGATION);assert(DOTS()==((1u<<TIO_TILE_NAVIGATION)|(1u<<TIO_TILE_MUSIC)|(1u<<TIO_TILE_FOCUS)));   /* page 2 of 3: navigation, music, pomodoro; camera is on the next page */
  GO(TIO_TILE_CAMERA);assert(DOTS()==((1u<<TIO_TILE_CAMERA)));
  link_up=false;fixture.camera=false;fixture.nav_active=false;GO(TIO_TILE_NAVIGATION);assert(control.view.live_mask==(1u<<TIO_TILE_FOCUS));assert(DOTS()==(1u<<TIO_TILE_FOCUS));
  fixture=(TSLive){0};link_up=true;GO(TIO_TILE_NAVIGATION);assert(control.view.live_mask==0&&DOTS()==0);
  /* TMG8 navigation title (OptionANavTitle): the production live_sync turns the stubbed nav_service turn into the band T title and the carousel route flag. */
  {const uintptr_t tt=(uintptr_t)control.view.title_text,ta=(uintptr_t)control.view.title_arrow,pg=(uintptr_t)control.view.page;
   #define TITLE(want) do{if(*(want)){assert(control.view.title_on&&shown[tt]&&shown[ta]&&!strcmp(texts[tt],want));}else assert(!control.view.title_on&&!shown[tt]&&!shown[ta]);}while(0)
   link_up=true;fixture=(TSLive){.nav_active=true,.nav_turn=true,.nav_icon=TN_LEFT,.nav_turn_m=200};strcpy(fixture.nav_road,"Market St");
   control.desired_rows=FM_CAROUSEL;GO(TIO_TILE_MUSIC);TITLE("200 m \xc2\xb7 Market St");assert(control.view.route);   /* shown on any tile, the row makes room */
   fixture.nav_turn_m=150;GO(TIO_TILE_MUSIC);TITLE("150 m \xc2\xb7 Market St");                                      /* the next 1 Hz refresh rewrites it */
   {const char *kept=texts[tt];fixture.nav_turn_m=149;now+=300;fm_sync(app);assert(texts[tt]==kept);now+=1000;fm_sync(app);assert(texts[tt]==kept&&!strcmp(kept,"150 m \xc2\xb7 Market St"));}   /* 149 m rounds to 150 m: unchanged, never rewritten */
   fixture.nav_turn_m=1500;strcpy(fixture.nav_road,"Martin Luther King Jr. Boulevard South Extension");GO(TIO_TILE_FOCUS);assert(control.view.title_on&&control.view.title_w<=NT_TEXT_W&&strstr(texts[tt],"1.5 km")&&strstr(texts[tt],"\xe2\x80\xa6"));
   fixture.nav_turn_m=200;strcpy(fixture.nav_road,"Market St");GO(TIO_TILE_NAVIGATION);TITLE("200 m \xc2\xb7 Market St");
   /* the grid shows it too and gives up the page dots */
   control.desired_rows=2;GO(TIO_TILE_NAVIGATION);TITLE("200 m \xc2\xb7 Market St");assert(control.view.rows==2&&!shown[pg]);
   /* stale, no route, no phone: hidden at once and the carousel row returns */
   fixture.nav_stale=true;GO(TIO_TILE_NAVIGATION);TITLE("");assert(shown[pg]);fixture.nav_stale=false;GO(TIO_TILE_NAVIGATION);TITLE("200 m \xc2\xb7 Market St");
   fixture.nav_turn=false;GO(TIO_TILE_NAVIGATION);TITLE("");
   fixture.nav_turn=true;now+=1100;GO(TIO_TILE_NAVIGATION);TITLE("200 m \xc2\xb7 Market St");link_up=false;GO(TIO_TILE_NAVIGATION);TITLE("");
   link_up=true;fixture.nav_active=false;GO(TIO_TILE_NAVIGATION);TITLE("");
   control.desired_rows=FM_CAROUSEL;fixture.nav_active=true;GO(TIO_TILE_NAVIGATION);TITLE("200 m \xc2\xb7 Market St");assert(control.view.route);fixture.nav_active=false;GO(TIO_TILE_NAVIGATION);TITLE("");assert(!control.view.route);
   fixture=(TSLive){0};
  }
  /* a renderer that is busy leaves everything as it was and retries */
  fixture.pomodoro=true;fixture.pomodoro_ms=5000;control.desired_rows=FM_CAROUSEL;GO(TIO_TILE_FOCUS);
 }
 /* Show after hide with a busy renderer: while hidden the controller's timer ran at 1000 ms. fm_show puts it back to the
  * active rate before its first draw, so when that draw is refused the retry comes 100 ms later, not up to a second. */
 control.timer=&timer_token;control.enabled=false;control.selection=-1;period=1000;control.view.moving=false;
 busy=true;showing=true;seen=0;fm_show(app);showing=false;
 assert(control.enabled&&control.selection==-1&&period==100&&seen==100);   /* the draw was refused; the retry runs at the active rate, set before the draw */
 busy=false;now+=100;fm_sync(app);assert(control.selection>=0);   /* the next tick's fm_sync draws */
 /* The same with the view still moving when it was hidden: fm_show picks the moving rate, 16 ms, as tick() does. */
 control.enabled=false;control.selection=-1;period=1000;control.view.moving=true;
 busy=true;showing=true;seen=0;fm_show(app);showing=false;
 assert(control.enabled&&control.selection==-1&&period==16&&seen==16);
 busy=false;control.view.moving=false;
 puts("PASS native fm_sync: unchanged selected rank immediately redraws changed canonical tiles before dispatch");
}
