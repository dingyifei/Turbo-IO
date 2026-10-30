/* STRIX 1.0.5.5 TMG4. Executed by LauncherThreadMsgHandler on the UI thread.
 * No button-driver simulation: that path blocks and includes reset/pair events.
 * Current native input interceptors retain ownership of global input policy.
 */
#include "remote.h"
#include "language_state.h"
#include "../diagnostics-v1/runtime_native.h"
extern void fm_language_changed(void),fm_sync(void *);
#include "../menu-grid-v2/menu_config.c"
#include "../menu-grid-v2/menu_files.inc"
#include "../menu-grid-v2/tile_native.h"
#include "../menu-grid-v2/tile_files.inc"
#include "lang_files.inc"
#include "../image-upload-test/native_file_bridge.h"
#include <string.h>
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_next(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void),tap_random(void);
extern void *nav_monitors(void),*nav_input(void *),*nav_link(void *);
extern void *fm_system(void *);
extern unsigned tgr_ota_status(void *);
extern bool nav_bonded(void *),nav_folded(void *),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern const char *nav_top_app(void);
extern void nav_screen_on(bool),native_report_activity(void);
extern void *tgr_indev_next(void *),*tgr_indev_group(void *),*tgr_indev_driver(void *);
extern unsigned tgr_indev_type(void *);
extern bool tgr_intercept(void *);
extern unsigned tgr_group_send(void *,uint32_t);
extern void tgr_raw_wheel(const void *),tgr_sim_wheel(int);
typedef struct {uint32_t magic;void *timer;TGRGate gate;TMLState menu;TLGLanguageState language;TTState tiles;TTVisible active;void *menu_app;bool settings_loaded,pending,applying;TKState knob;unsigned synthetic_depth;} Control;
static void tick(void *);
static bool allowed(void){
 void *m=nav_monitors(),*i=m?nav_input(m):NULL,*l=m?nav_link(m):NULL;
 void *sys=m?fm_system(m):NULL;
 if(!i||!l||!sys||tgr_ota_status(sys)!=0||!nav_bonded(l)||!nav_connection(0x80)||nav_folded(i))return false;
 const char *top=nav_top_app();if(!top)return false;
 /* Positive list. OTA, payment, factory/MMI and unknown native apps excluded.
  * Custom music/read/navigation/focus/app views share the launcher package. */
 static const char *const names[]={"com.rayneo.liteos.launcher","com.rayneo.liteos.recorder","com.rayneo.liteos.prompter","com.rayneo.liteos.aiSubtitle","com.rayneo.liteos.conversationAssist","com.rayneo.liteos.assistant","com.rayneo.liteos.todo","com.rayneo.liteos.notification"};
 for(unsigned j=0;j<sizeof names/sizeof *names;j++)if(!strcmp(top,names[j]))return true;
 return false;
}
static Control *control(void){
 void *t=NULL;for(unsigned j=0;j<512;j++){t=stream_timer_next(t);if(!t)break;if(*(void(**)(void*))((uint8_t*)t+8)==tick){Control *c=*(Control**)((uint8_t*)t+12);return c&&c->magic==0x54475231&&c->timer==t?c:NULL;}if(j==511)return NULL;}
 Control *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=0x54475231;c->timer=stream_timer_create(tick,1000,c);if(!c->timer){stream_free(c);return NULL;}c->menu.stored=(TMLStored){.rows=3,.bank=1,.readable=true};tt_default(&c->tiles.stored.config);c->tiles.stored.bank=1;c->tiles.stored.readable=true;tt_compact(&c->tiles.stored.config,&c->active);return c;
}
/* Read-only scan used by label renderers: never create a controller here. */
static Control *find(void){
 void *t=NULL;for(unsigned j=0;j<512;j++){t=stream_timer_next(t);if(!t)return NULL;
  if(*(void(**)(void*))((uint8_t*)t+8)==tick){Control *c=*(Control**)((uint8_t*)t+12);return c&&c->magic==0x54475231&&c->timer==t?c:NULL;}}
 return NULL;
}
unsigned tio_lang(void){Control *c=find();return c?c->language.lang:TLG_EN;}
unsigned fm_menu_rows(void){Control *c=control();if(c&&!c->settings_loaded){
 c->menu.stored=tml_load(&tml_io);c->tiles.stored=tt_load(&tt_io);if(tlg_state_load(&c->language,&tls_io))fm_language_changed();c->tiles.loaded=true;c->settings_loaded=true;c->pending=true;
 }return c?c->menu.stored.rows:3;} /* 1 carousel, 2 or 3 grid rows; tml_load only returns those */
void fm_tile_snapshot(TTVisible *out){Control *c=find();if(c){*out=c->active;return;}TTConfig defaults;tt_default(&defaults);(void)tt_compact(&defaults,out);}
unsigned fm_tile_count(void){Control *c=find();return c?c->active.count:13;}
unsigned fm_tile_id(unsigned rank){Control *c=find();if(c)return rank<c->active.count?c->active.ids[rank]:255;return rank<13?rank:255;}
unsigned fm_tile_rank(unsigned id){Control *c=find();if(c)return id<13?c->active.rank[id]:255;return id<13?id:255;}
bool fm_tiles_busy(void){Control *c=find();return c&&c->applying;}
extern void native_snap(void *);
bool fm_tiles_apply(void *app){
 Control *c=find();if(!c||!app||!c->settings_loaded||c->applying||(!c->pending&&c->menu_app==app))return false;
 TTVisible next;if(!tt_compact(&c->tiles.stored.config,&next))return false;
 unsigned selected=*(uint32_t *)((uint8_t *)app+0x88);unsigned id=selected<c->active.count?c->active.ids[selected]:12;
 c->applying=true;native_snap(app); /* old map/count: stop old motion first */
 unsigned rank=id<13?next.rank[id]:255;if(rank==255)rank=next.rank[12];
 c->active=next;c->menu_app=app;c->pending=false;
 *(uint32_t *)((uint8_t *)app+0xa0)=next.count;*(uint32_t *)((uint8_t *)app+0x88)=rank;*(uint32_t *)((uint8_t *)app+0x90)=UINT32_MAX;
 native_snap(app);c->applying=false;return true;
}
void fm_tiles_forget(void *app){Control *c=find();if(c&&c->menu_app==app){tk_cancel(&c->knob,stream_tick());c->menu_app=NULL;c->pending=true;TTConfig defaults;tt_default(&defaults);tt_compact(&defaults,&c->active);}}

extern bool fm_menu_plain(void *);
bool tgr_runtime_allowed(void){return allowed();}
unsigned tgr_knob_command(void *app,const TDCommand *q,uint32_t now){
 if(!q)return TK_UNAVAILABLE;bool ok=allowed()&&app&&fm_menu_plain(app);Control *c=control();if(!c)return TK_UNAVAILABLE;
 if(!ok){tk_cancel(&c->knob,now);return TK_BLOCKED;}if(c->menu_app!=app||!c->settings_loaded)return TK_UNAVAILABLE;
 if(q->op==TDQ_KNOB_START)return tk_start(&c->knob,q->session,q->sequence,q->lease_ms,now,true);
 if(q->op==TDQ_KNOB_STOP)return tk_stop(&c->knob,q->session,q->sequence,now,true);return TK_UNAVAILABLE;
}
/* Lifecycle hooks must not allocate or load settings before first show. */
void tgr_knob_cancel(void *app,uint32_t now){Control *c=find();if(c&&app&&c->menu_app==app)tk_cancel(&c->knob,now);}
void tgr_knob_observe(void *app,int32_t delta,uint32_t now){Control *c=find();if(!c||c->knob.state!=TK_ACTIVE)return;bool ok=c->menu_app==app&&allowed()&&fm_menu_plain(app);tk_observe(&c->knob,delta,now,ok,c->synthetic_depth!=0);}
void tgr_runtime_snapshot(TDSample *s){
 if(!s)return;s->caps=TD_CAPS_TMG8;s->detent=TK_DETENT_RAW;s->extension_valid&=TD_EXT_NAND;s->tile_generation=s->settings_flags=0;s->language=s->language_source=0;
 s->calibration_state=0;s->calibration_window=s->calibration_elapsed=s->calibration_samples=s->calibration_sequence=0;s->calibration_net=0;s->calibration_absolute=0;
 Control *c=find();if(!c)return;
 if(c->settings_loaded){s->extension_valid|=TD_EXT_TILES|TD_EXT_LANGUAGE;s->tile_generation=c->tiles.stored.generation;s->language=c->language.lang;s->language_source=c->language.source;s->settings_flags=(c->tiles.stored.readable?1u:0u)|(c->language.stored.readable?2u:0u)|(c->pending?4u:0u);}
 tk_poll(&c->knob,stream_tick(),allowed()&&c->menu_app&&fm_menu_plain(c->menu_app));
 if(c->knob.window){s->extension_valid|=TD_EXT_CALIBRATION;s->calibration_state=c->knob.state;s->calibration_window=c->knob.window;s->calibration_elapsed=c->knob.elapsed;s->calibration_samples=c->knob.samples;s->calibration_net=c->knob.net;s->calibration_absolute=c->knob.absolute;s->calibration_sequence=c->knob.sequence;}
}
static void tick(void *t){Control *c=*(Control**)((uint8_t*)t+12);if(c){bool ok=allowed();tk_poll(&c->knob,stream_tick(),ok&&c->menu_app&&fm_menu_plain(c->menu_app));if(!ok||(uint32_t)(stream_tick()-c->gate.seen)>15000)memset(&c->gate,0,sizeof c->gate);if(!ok||(uint32_t)(stream_tick()-c->menu.issued)>120000)c->menu.token=0;if(!ok||(uint32_t)(stream_tick()-c->tiles.issued)>120000)c->tiles.token=0;}}
static void *device(unsigned type){void *p=NULL;for(unsigned j=0;j<16;j++){p=tgr_indev_next(p);if(!p)return NULL;if(tgr_indev_type(p)==type)return p;}return NULL;}
static unsigned inject(unsigned op){
 if(!allowed())return TGR_BLOCKED;
 Control *c=find();if(c)tk_cancel(&c->knob,stream_tick());
 if(!focus_screen_on()){native_report_activity();nav_screen_on(true);return TGR_WAKE_ONLY;}
 if(op==TGR_PREVIOUS||op==TGR_NEXT){
  void *d=device(4);if(!d)return TGR_UNAVAILABLE;uint8_t *driver=tgr_indev_driver(d);if(!driver)return TGR_UNAVAILABLE;
  if(*(int16_t*)(driver+6))return TGR_BUSY; /* Never overwrite a pending step. */
  int step=op==TGR_NEXT?1:-1;
  /* Mirror hardware: raw listener first, then LVGL detent. Native raw input
   * struct is {int32 x,y; uint64 time_us}, seen in rayneo_wheel_read. */
  struct {int32_t x,y;uint64_t time;} raw={driver[9]?step*(int)TK_DETENT_RAW:-step*(int)TK_DETENT_RAW,0,(uint64_t)stream_tick()*1000};
  native_report_activity();if(c)c->synthetic_depth++;tgr_raw_wheel(&raw);tgr_sim_wheel(step);if(c)c->synthetic_depth--;return TGR_OK;
 }
 void *d=device(2),*group=d?tgr_indev_group(d):NULL;if(!group)return TGR_UNAVAILABLE;
 uint32_t key=op==TGR_PRESS?0x3a:0x3b;
 /* ABI copied from native rayneo_indev_keypad_proc, not a guessed LVGL type. */
 struct {void *current,*original;uint32_t code;void *user,*parameter,*previous;uint32_t flags;} event={0};
 _Static_assert(sizeof event==28,"32-bit pinned event ABI");event.code=14;event.parameter=&key;
 native_report_activity();if(!tgr_intercept(&event)){
  /* Interception can change pages/groups. Re-resolve instead of using stale. */
  d=device(2);group=d?tgr_indev_group(d):NULL;if(!group)return TGR_UNAVAILABLE;
  (void)tgr_group_send(group,key);
 }return TGR_OK;
}
void tgr_native_message(const TIONativeMessage *m){
 /* Preserve original handler + original payload disposal for EVERY message.
  * This function never takes ownership and never changes the message bytes. */
 if(!m||m->id!=1||m->bytes!=74||!m->data)return;
 uint8_t raw[32];TMLCommand layout;
 if(tml_uncarrier(m->data,m->bytes,raw,false)){
  if(!tml_decode(raw,sizeof raw,&layout))return;
  Control *c=control();if(!c)return;
  unsigned r=tml_accept(&c->menu,&layout,stream_tick(),layout.op==TML_QUERY?tap_random():0,allowed(),&tml_io);
  /* IO failure may have committed a valid inactive bank: reconcile actual state,
   * but never report success until flush/fsync/readback all passed. */
  fm_relayout(c->menu.stored.rows);
  uint8_t out[74];tml_reply(raw,&c->menu,&layout,r);tml_carrier(out,raw,true);
  (void)tdp_rnlink_send(15,out,sizeof out,NULL);return;
 }
 if(tt_uncarrier(m->data,m->bytes,raw,false)){
  TTCommand q;if(!tt_decode(raw,sizeof raw,&q))return;Control *c=control();if(!c)return;
  uint32_t generation=c->tiles.stored.generation;
  unsigned r=tt_accept(&c->tiles,&q,stream_tick(),q.op==TT_QUERY?tap_random():0,allowed(),&tt_io);
  if(c->tiles.stored.readable&&c->tiles.stored.generation!=generation)c->pending=true;
  if(c->menu_app)fm_sync(c->menu_app);
  uint8_t out[74];tt_reply(raw,&c->tiles,&q,r);tt_carrier(out,raw,true);(void)tdp_rnlink_send(15,out,sizeof out,NULL);return;
 }
 if(tlg_uncarrier(m->data,m->bytes,raw,false)){
  TLGCommand flag;if(!tlg_decode(raw,sizeof raw,&flag))return;
  Control *c=control();if(!c)return;TLGReply reply;
  if(tlg_state_accept(&c->language,&flag,allowed(),&tls_io,&reply))fm_language_changed();
  uint8_t out[74];tlg_reply_encode(raw,&reply);tlg_carrier(out,raw,true);
  (void)tdp_rnlink_send(15,out,sizeof out,NULL);return;
 }
 TGRCommand q;if(!tgr_uncarrier(m->data,m->bytes,raw,false)||!tgr_decode(raw,sizeof raw,&q))return;
 Control *c=control();if(!c)return;uint32_t now=stream_tick();
 unsigned r=tgr_accept(&c->gate,&q,now,q.op==TGR_HELLO?tap_random():0,allowed());
 if(r==TGR_OK&&q.op>=TGR_PREVIOUS&&q.op<=TGR_BACK)r=inject(q.op);
 uint8_t out[74];tgr_reply(raw,&c->gate,&q,r,stream_tick());tgr_carrier(out,raw,true);(void)tdp_rnlink_send(15,out,sizeof out,NULL);
}
