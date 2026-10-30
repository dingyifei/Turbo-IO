#include "focus-v1/focus_menu.h"
#include "common-v1/tio_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {void *quad;} TNNavSlot;
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
static void *nav_monitors(void){return NULL;}
static void *fm_system(void *p){return p;}
static void *fm_battery_monitor(void *p){return p;}
static int64_t fm_local_time(void *p){(void)p;return 0;}
static int fm_battery_level(void *p){(void)p;return -1;}
static void stream_timer_period(void *p,uint32_t ms){(void)p;assert(ms==16);}
unsigned tio_lang(void){return 0;}
#include "focus_native_sync.inc"
static FMControl control;
int main(void){
 TTConfig c;tt_default(&c);assert(tt_compact(&c,&active));assert(fm_view_open(&control.view,&widgets,&root,attach,&control));control.app=app;control.enabled=true;control.desired_rows=3;control.selection=-1;nav.quad=&control;*(uint32_t *)(app+0x88)=7;
 fm_sync(app);assert(control.selection==7&&control.view.selected==7&&!strcmp(texts[(uintptr_t)control.view.labels[7]],tio_text(TT_GRID_DISPLAY,0)));
 assert(tt_unrank(719,0xf80,&c)&&tt_compact(&c,&desired));pending=true;now++;fm_sync(app);
 assert(active.count==8&&control.view.selected==7&&control.selection==7);assert(!strcmp(texts[(uintptr_t)control.view.labels[7]],tio_text(TT_TILE_CAMERA,0)));assert(!shown[(uintptr_t)control.view.labels[8]]);
 control.desired_rows=FM_CAROUSEL;now+=1000;fm_sync(app);assert(control.view.rows==FM_CAROUSEL&&control.view.selected==7&&control.selection==7&&!shown[(uintptr_t)control.view.page]);   /* a stored layout 1 reaches the view */
 control.desired_rows=2;now+=1000;fm_sync(app);assert(control.view.rows==2&&shown[(uintptr_t)control.view.page]);
 puts("PASS native fm_sync: unchanged selected rank immediately redraws changed canonical tiles before dispatch");
}
