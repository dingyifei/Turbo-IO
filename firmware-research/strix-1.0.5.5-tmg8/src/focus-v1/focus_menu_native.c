#include "../camera-v1/camera_native.h"
#include "../app-runtime-v1/app_service.h"
/* UI-thread-only launcher decoration. Allocation failure retains native menu.
 * Detach before app destruction, retire after renderer idle, no flash writes. */
#include "focus_menu.h"
#include "../menu-grid-v2/menu_config.h"
#include "../menu-grid-v2/tile_native.h"
#include "focus_service.h"
#include "tile_state.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../menu8-renderer.h"
#include "../common-v1/menu_wheel.h"
#include <string.h>
extern const M8RenderAPI m8_native_api;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),stream_timer_delete(void *);
extern void *stream_timer_next(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void stream_timer_period(void *,uint32_t),menu_text_align(void *,int,uint32_t);
extern bool focus_screen_on(void);
extern bool native_has_flag(void *,uint32_t);
extern void *nav_monitors(void),*fm_system(void *),*fm_battery_monitor(void *),*nav_link(void *);
extern bool nav_bonded(void *);
extern int nav_connection(unsigned);
extern int64_t fm_local_time(void *);
extern int fm_battery_level(void *);
typedef struct {FMView view;void *app,*timer;uint32_t refreshed;int selection;unsigned desired_rows;bool enabled,closing,relabel;TIOMenuWrap wrap;} FMControl;
_Static_assert(TS_LINE_MAX==FM_LINE_MAX,"the tile status line fits the view line buffer");
_Static_assert(sizeof(FMControl)<=40960,"menu retained storage (nine grid cells or six carousel slots, two banks) capped at 40 KiB");
_Static_assert(offsetof(TNNavSlot,quad)==44,"never overlap existing slot fields");
_Static_assert(sizeof(TNNavSlot)==68,"quad extends only separately allocated slot");
static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}
static TNNavSlot *slot(void *a){return a?((M8NativeTail *)((uint8_t *)a+TIO_STOCK_MENU_BYTES))->navigation:NULL;}
static bool detail(void *app){TNNavSlot *s=slot(app);return tc_native_visible(app)||tap_service_visible(app)||(s&&(tn_slot_visible(s)||tm_slot_visible(s->music)||tf_slot_visible(s->focus)||((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->page));}
bool fm_menu_plain(void *app){void *parent=ptr(app,4);return app&&parent&&!native_has_flag(parent,1)&&!detail(app)&&focus_screen_on();}
static void hide_legacy(void *app){
 M8NativeTail *t=(M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES);TNNavSlot *s=slot(app);TMMusicSlot *music=s?s->music:NULL;TFSlot *focus=s?s->focus:NULL;
 TCSlot *camera=s?s->camera:NULL;
 void *old[]={camera?camera->row:NULL,camera?camera->icon:NULL,ptr(app,8),t->row,t->icon,s?s->row:NULL,s?s->icon:NULL,music?music->row:NULL,music?music->icon:NULL,focus?focus->row:NULL,focus?focus->icon:NULL,s&&s->apps?((TAPMenu *)s->apps)->row:NULL,s&&s->apps?((TAPMenu *)s->apps)->icon:NULL};
 for(unsigned i=0;i<7;i++){void *row=ptr(app,0xc+4*i);if(row)m8_native_api.hidden(row,true);}
 for(unsigned i=0;i<sizeof old/sizeof *old;i++)if(old[i])m8_native_api.hidden(old[i],true);
}
static void deleted(void *e){FMControl *c=stream_event_user(e);if(c){TNNavSlot *s=slot(c->app);if(s&&s->quad==c)s->quad=NULL;c->app=NULL;c->view.root=NULL;c->closing=true;}}
static bool attach_deleted(void *root,void *owner){return stream_add_event(root,deleted,0x24,owner)!=NULL;}
static bool dispose(FMControl *c){if(!c->view.api.idle(c->view.api.ctx)||!fm_view_close(&c->view))return false;stream_timer_delete(c->timer);stream_free(c);return true;}
static void tick(void *t){FMControl *c=ptr(t,12);if(!c)return;
 if(c->closing||!c->app){(void)dispose(c);return;}
 fm_sync(c->app);stream_timer_period(c->timer,c->enabled&&!detail(c->app)&&focus_screen_on()?(c->view.moving?16:100):1000);
}
/* At most one menu controller, including deferred retirees. A new native menu
 * cannot accumulate another frame buffer before the previous one is safe. */
static bool room(void){void *t=NULL;for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)return true;void (*cb)(void *)=*(void (**)(void *))((uint8_t *)t+8);if(cb==tick){FMControl *c=ptr(t,12);return c&&c->timer==t&&c->closing&&!c->app&&dispose(c);}}return false;}
/* Live tile state (read only). One snapshot of what the services already keep, then the text for the focused tile (carousel line) and the
 * mask of tiles with a running state (grid dots). Runs on the 1 Hz refresh and whenever the focus moves, never per frame. */
static bool phone_linked(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static void tile_live(void *app,uint32_t now,TSLive *live){
 memset(live,0,sizeof *live);live->phone=phone_linked();tf_live(now,live);
 TNNavSlot *s=slot(app);if(!s)return;
 tm_slot_live(s->music,now,live);tn_slot_live(s,live);tc_slot_live(s->camera,live);
}
static bool live_sync(FMControl *c,void *app,int index,uint32_t now){
 if(index<0||(unsigned)index>=c->view.tiles.count)return false;
 TSLive live;TSState st;tile_live(app,now,&live);const unsigned lang=tio_lang();unsigned mask=0;
 for(unsigned r=0;r<c->view.tiles.count;r++){unsigned id=c->view.tiles.ids[r];ts_state(id,&live,lang,&st);if(st.active)mask|=1u<<id;}
 (void)fm_view_active(&c->view,mask);
 ts_state(c->view.tiles.ids[index],&live,lang,&st);return fm_view_line(&c->view,st.line);
}
void fm_relayout(unsigned rows){
 if(rows<1||rows>3)return;   /* 1 carousel, 2 or 3 grid rows */void *t=NULL;
 for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)return;if(*(void (**)(void *))((uint8_t *)t+8)==tick){FMControl *c=ptr(t,12);if(c&&c->timer==t&&!c->closing)c->desired_rows=rows;return;}}
 /* No active launcher: the persisted value is loaded when it next opens. */
}
extern void m8_refresh_tile_label(void *,int);
void fm_language_changed(void){
 void *t=NULL;for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)return;
  if(*(void(**)(void*))((uint8_t*)t+8)==tick){FMControl *c=ptr(t,12);if(c&&c->timer==t&&!c->closing)c->relabel=true;return;}}
}
void fm_sync(void *app){if(fm_tiles_busy())return;TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;bool inside=detail(app);void *dots=ptr(app,0x60);
 if(dots)m8_native_api.hidden(dots,inside||(c&&c->view.root&&!c->closing));
 if(c&&c->view.root&&!c->closing)hide_legacy(app);
 void *visible_parent=ptr(app,4);TNWidgets widgets=tn_lvgl_widgets();
 bool safe=visible_parent&&!native_has_flag(visible_parent,1)&&!inside&&focus_screen_on()&&widgets.idle(widgets.ctx);
 if(safe){(void)fm_tiles_apply(app);if(c&&!c->closing&&c->view.root){TTVisible active;fm_tile_snapshot(&active);if(!fm_view_tiles(&c->view,&active))return;if(c->view.selected<0)c->selection=-1;}}
 if(!c||c->closing||!c->view.root)return;
 if(c->relabel){c->relabel=false;c->selection=-1;fm_view_suspend(&c->view);for(int i=TIO_STOCK_ITEMS;i<TIO_MENU_ITEMS;i++)m8_refresh_tile_label(app,i);}
 void *parent=ptr(app,4);bool show=c->enabled&&parent&&!native_has_flag(parent,1)&&!inside;
 if(!show){c->view.api.visible(c->view.api.ctx,c->view.root,false);c->selection=-1;fm_view_suspend(&c->view);return;}
 if(!focus_screen_on())return; /* Never repaint or wake a sleeping panel. */
 if(c->view.rows!=c->desired_rows){if(!fm_view_rows(&c->view,c->desired_rows))return;c->selection=-1;}
 int index=(int)*(uint32_t *)((uint8_t *)app+0x88);if(index<0||index>=(int)fm_tile_count())return;uint32_t now=stream_tick();
 if(index==c->selection&&(uint32_t)(now-c->refreshed)<1000){(void)fm_view_step(&c->view,now);return;}
 void *mon=nav_monitors(),*sys=mon?fm_system(mon):NULL,*battery=mon?fm_battery_monitor(mon):NULL;
 int64_t local=sys?fm_local_time(sys):0;int level=battery?fm_battery_level(battery):-1;
 if(!live_sync(c,app,index,now))return;   /* before the redraw, so the line and the focus change in one frame */
 if(fm_view_update(&c->view,index,local,level,now)){c->selection=index;c->refreshed=now;if(c->view.moving)stream_timer_period(c->timer,16);}
}
void fm_show(void *app){TNNavSlot *s=slot(app);if(!s)return;FMControl *c=s->quad;
 if(!c){TNWidgets api=tn_lvgl_widgets();if(!api.idle(NULL)||!room())return;c=stream_memalign(64,sizeof *c);if(!c)return;memset(c,0,sizeof *c);c->app=app;c->selection=-1;
  if(!fm_view_open(&c->view,&api,ptr(app,4),attach_deleted,c)){stream_free(c);return;}
  c->desired_rows=fm_menu_rows();TTVisible active;fm_tile_snapshot(&active);(void)fm_view_tiles(&c->view,&active);
  for(unsigned i=0;i<FM_CELLS;i++)menu_text_align(c->view.labels[i],2,0);
  menu_text_align(c->view.line,2,0);menu_text_align(c->view.battery,3,0);menu_text_align(c->view.name,2,0); /* battery right-aligned to the core edge, focused name centred in band B */
  c->timer=stream_timer_create(tick,100,c);if(!c->timer){fm_view_close(&c->view);stream_free(c);return;}
  s->quad=c;
 }
 c->enabled=true;fm_sync(app);
}
void fm_hide(void *app){TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;if(c){c->enabled=false;c->selection=-1;fm_view_suspend(&c->view);if(c->view.root)c->view.api.visible(c->view.api.ctx,c->view.root,false);}}
void fm_destroy(void *app){TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;if(!c)return;s->quad=NULL;c->app=NULL;c->closing=true;c->enabled=false;(void)dispose(c);/* idle: remove our child now; busy: parent callback + deferred retirement */}
/* Knob wrap state lives in the heap controller (the owner tail and .bss are fixed). No controller, no wrap. */
int fm_wheel_wrap(void *app,int index,int count,int delta,uint32_t now){TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;return c&&!c->closing?tio_menu_wheel_wrap(&c->wrap,index,count,delta,now):-1;}
