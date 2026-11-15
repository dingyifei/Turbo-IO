/* Executes the production navigation service (navigation-runtime-v1/nav_service.c) on the host, with the real
 * nav_runtime.c (and the nav_map.c it includes), nav_view.c, nav_visual.c and nav_lvgl.c. Only stock functions, the
 * other services' visibility and event hooks, and tio_lang are stubbed. The runner (nav_service_host_test.py) adapts
 * the two pinned 32-bit pointer reads for a 64-bit host and passes the app names it reads from remote_native.c (the
 * Navigation name is input_allowed's literal, which tests/remote_app_name_test.py checks against the stock image).
 * The menu object is TIO_TAIL_END bytes, armed with m8_tail_arm as the constructor check would.
 *
 * Owner decision O6: stock Navigation on top ends the module's own route at the service's one-second check (event 42,
 * result 1 for a kept route, 2 for a visible one). Every case checks the state after the tick, the replies the phone
 * gets, the trace lines, allocations and frees, and the power hold; each case ends with the slot destroyed and no
 * block, hold or timer left. */
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
static void *host_ptr(void *,unsigned),*host_timer_user(void *);
#include "nav_service_host.inc"
#include "menu8-renderer.h"
#include "image-upload-test/render_idle.h"
static const char *const apps[]={TN_TEST_APPS};   /* remote_native.c's list: the launcher first, then other stock apps */
#define LAUNCHER (apps[0])
#define NAVIGATION TN_TEST_NAVIGATION
_Static_assert(sizeof apps/sizeof *apps>=6,"the remote's app list has the launcher and at least five other apps");

/* ---- stock and runtime stubs ---------------------------------------------------------------------------------- */
typedef struct {void (*callback)(void *);void *user;uint32_t period;} HostTimer;
typedef struct {void *user;} HostEvent;
static HostTimer timer;
static uint32_t now_ms;
static const char *top;
static bool linked,render_idle;
static unsigned stock_events,stops,holds,releases,sleeps,timers_created,timers_deleted;
static uint32_t held_token,token_seq,event_code,event_key;
void *tio_launcher_global;
_Alignas(16) static uint8_t app[TIO_TAIL_END],vm[64],launcher_object[TIO_STOCK_LAUNCHER_MANAGER+sizeof(void *)],monitors[16],menu_root[16];
_Static_assert(TIO_STOCK_MANAGER_MENU+sizeof(void *)<=sizeof vm&&TIO_STOCK_MANAGER_STATE+sizeof(uint32_t)<=sizeof vm,"view manager model");
static void *host_ptr(void *p,unsigned off){void *v=NULL;if(p)memcpy(&v,(uint8_t *)p+off,sizeof v);return v;}
static void *host_timer_user(void *p){return ((HostTimer *)p)->user;}
static void put_ptr(uint8_t *at,void *p){memcpy(at,&p,sizeof p);}
static void put_word(uint8_t *at,uint32_t v){memcpy(at,&v,sizeof v);}
static uint32_t get_word(const uint8_t *at){uint32_t v;memcpy(&v,at,sizeof v);return v;}

/* Heap: every live block is listed, so a leak, a double free or a free of a foreign pointer fails. */
#define BLOCKS 64
static void *live[BLOCKS];static size_t live_size[BLOCKS];
static unsigned allocations,frees;
void *stream_memalign(size_t alignment,size_t n){
 allocations++;void *p=NULL;assert(!posix_memalign(&p,alignment<sizeof(void *)?sizeof(void *):alignment,n)&&p);
 for(unsigned i=0;i<BLOCKS;i++)if(!live[i]){live[i]=p;live_size[i]=n;return p;}
 assert(!"block table full");return NULL;
}
void stream_free(void *p){assert(p);frees++;for(unsigned i=0;i<BLOCKS;i++)if(live[i]==p){live[i]=NULL;free(p);return;}assert(!"free of a block that is not live");}
static bool is_live(const void *p){for(unsigned i=0;i<BLOCKS;i++)if(p&&live[i]==p)return true;return false;}
static unsigned live_count(void){unsigned n=0;for(unsigned i=0;i<BLOCKS;i++)n+=live[i]!=NULL;return n;}
static size_t size_of(const void *p){for(unsigned i=0;i<BLOCKS;i++)if(p&&live[i]==p)return live_size[i];return 0;}
void *stream_timer_create(void (*cb)(void *),uint32_t period,void *user){assert(!timer.callback&&cb&&user);timer=(HostTimer){cb,user,period};timers_created++;return &timer;}
void stream_timer_delete(void *p){assert(p==&timer);timer=(HostTimer){0};timers_deleted++;}
void stream_timer_period(void *p,uint32_t ms){assert(p==&timer);timer.period=ms;}
uint32_t stream_tick(void){return now_ms;}
void *stream_event_user(void *e){return ((HostEvent *)e)->user;}

/* Widgets through the real nav_lvgl.c: each object records its delete callback; deleting a root fires it at once, as
 * the stock delete event would (nav_runtime.c sets hidden before leave for that reason). */
typedef struct {void (*on_delete)(void *);void *user;bool root,deleted;} Obj;
static Obj objects[512];static unsigned object_count,roots_created,roots_deleted;
static Obj *new_object(void *parent,bool root){assert(parent);assert(object_count<sizeof objects/sizeof *objects);Obj *o=&objects[object_count++];*o=(Obj){0};o->root=root;roots_created+=root;return o;}
static void *create_root(void *parent){return new_object(parent,true);}
static void delete_root(void *p){Obj *o=p;assert(o&&o->root&&!o->deleted);o->deleted=true;roots_deleted++;if(o->on_delete){HostEvent e={o->user};o->on_delete(&e);}}
static void hidden(void *p,bool yes){(void)yes;assert(p);}
static bool configure_root(void *p,void *parent){return p&&parent;}
const M8RenderAPI m8_native_api={.create_root=create_root,.delete_root=delete_root,.hidden=hidden,.configure_root=configure_root};
void *stream_add_event(void *obj,void (*cb)(void *),uint32_t code,void *user){(void)code;Obj *o=obj;assert(o&&o->root&&cb&&!o->on_delete);o->on_delete=cb;o->user=user;return o;}
void *stream_canvas_create(void *parent){return new_object(parent,false);}
void *native_label_create(void *parent){return new_object(parent,false);}
void *menu_font(int size,int style){static uint8_t font[4];(void)style;assert(size>0);return font;}
void stream_canvas_set_buffer(void *o,void *data,int32_t w,int32_t h,uint8_t cf){(void)cf;assert(o&&data&&w>0&&h>0);}
uint32_t stream_stride(uint32_t w,uint8_t cf){(void)cf;return w;}
void *stream_display_next(void *p){(void)p;return NULL;}
void stream_invalidate(void *o){assert(o);}
void native_align(void *o,int a,int x,int y){(void)a;(void)x;(void)y;assert(o);}
void tio_lv_obj_set_size(void *o,int w,int h){(void)w;(void)h;assert(o);}
void native_text_color(void *o,uint32_t rgb,uint32_t part){(void)rgb;(void)part;assert(o);}
void menu_text_font(void *o,void *font,uint32_t part){(void)part;assert(o&&font);}
void nav_label_static(void *o,const char *s){assert(o&&s);}
void dc_text_mode(void *o,unsigned mode){(void)mode;assert(o);}
bool tio_render_graph_idle(TIOReadWord read,TIONextDisplay next){assert(read&&next);return render_idle;}
uint32_t nav_always_on(const char *owner){assert(!strcmp(owner,"turbo_nav_v1")&&!held_token);holds++;held_token=++token_seq;return held_token;}
void nav_release_always_on(const char *owner,uint32_t token){assert(!strcmp(owner,"turbo_nav_v1")&&token&&token==held_token);releases++;held_token=0;}
void nav_screen_on(bool on){(void)on;}
int nav_force_off(void){sleeps++;return 0;}

/* Launcher, phone link and input. */
void *nav_ensure_menu(void *p){assert(p==vm);put_ptr(vm+TIO_STOCK_MANAGER_MENU,app);return app;}
void nav_set_state(void *p,unsigned state){assert(p==vm);put_word(vm+TIO_STOCK_MANAGER_STATE,state);}
void stock_vm_event(void *e){assert(e);stock_events++;}
const char *nav_top_app(void){return top;}
void *nav_monitors(void){return monitors;}
void *nav_link(void *m){return linked?m:NULL;}
void *nav_input(void *m){return m;}
bool nav_bonded(void *l){return l!=NULL;}
bool nav_folded(void *i){(void)i;return false;}
bool tio_business_idle(void){return true;}
int nav_connection(unsigned which){(void)which;return linked?1:0;}
unsigned native_event_code(void *e){(void)e;return event_code;}
unsigned native_event_key(void *e){(void)e;return event_key;}
void nav_stop_event(void *e){assert(e);stops++;}
void *fm_system(void *m){(void)m;return NULL;}
int64_t fm_local_time(void *s){(void)s;return 0;}
bool focus_screen_on(void){return true;}
unsigned tio_lang(void){return 0;}
/* The other services (music, focus, apps, camera): never visible, never take an event. */
bool tap_service_visible(void *p){(void)p;return false;}
bool tm_slot_visible(TMMusicSlot *s){(void)s;return false;}
bool tf_slot_visible(TFSlot *s){(void)s;return false;}
bool tc_native_event(void *e){(void)e;return false;}
bool tap_service_event(void *e){(void)e;return false;}
bool tf_handle_event(void *e){(void)e;return false;}
bool tm_handle_event(void *e){(void)e;return false;}

/* Trace lines: the format must be the module's existing one. */
typedef struct {unsigned event,result;} Trace;
static Trace traces[16];static unsigned trace_count;
void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *format,...){
 assert(a==1&&!b&&!c&&!d&&format&&!strcmp(format,"[TurboMenu8] event=%u result=%u"));
 va_list v;va_start(v,format);unsigned e=va_arg(v,unsigned),r=va_arg(v,unsigned);va_end(v);
 assert(trace_count<sizeof traces/sizeof *traces);traces[trace_count++]=(Trace){e,r};
}
static unsigned events_42(unsigned result){unsigned n=0;for(unsigned i=0;i<trace_count;i++)n+=traces[i].event==42&&traces[i].result==result;return n;}

/* Replies: the TNA1 record decoded from the JSON command the service sends on channel 15. */
typedef struct {unsigned result;bool active,awake;uint32_t sid,seq;} Reply;
static Reply last;static unsigned replies;
static unsigned nibble(uint8_t ch){assert((ch>='0'&&ch<='9')||(ch>='a'&&ch<='f'));return ch<='9'?ch-'0':ch-'a'+10u;}
static uint32_t le32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
int tdp_rnlink_send(unsigned business,const uint8_t *p,unsigned n,void *ctx){
 static const char key[]="\"data\":\"";const size_t k=sizeof key-1;size_t at=0;bool found=false;
 assert(business==15&&p&&!ctx);
 for(size_t i=0;i+k<=n;i++)if(!memcmp(p+i,key,k)){at=i+k;found=true;break;}
 assert(found&&at+64<=n);uint8_t raw[32];
 for(unsigned i=0;i<32;i++)raw[i]=(uint8_t)(16*nibble(p[at+2*i])+nibble(p[at+2*i+1]));
 assert(!memcmp(raw,"TNA1",4)&&tn_crc(raw,28)==le32(raw+28));
 last=(Reply){raw[5],(raw[6]&1)!=0,(raw[6]&2)!=0,le32(raw+8),le32(raw+12)};replies++;return 0;
}

/* ---- harness -------------------------------------------------------------------------------------------------- */
static TNNavSlot *slot;
static Control *ctl(void){return slot?slot->control:NULL;}
static void reset(void){
 assert(!slot&&!timer.callback&&live_count()==0);
 now_ms=5000;top=LAUNCHER;linked=render_idle=true;stock_events=stops=holds=releases=sleeps=timers_created=timers_deleted=0;
 held_token=0;event_code=TIO_STOCK_EVENT_KEY;event_key=TIO_STOCK_KEY_BACK;object_count=roots_created=roots_deleted=0;trace_count=0;replies=0;
 memset(&last,0,sizeof last);memset(vm,0,sizeof vm);memset(launcher_object,0,sizeof launcher_object);memset(app,0,sizeof app);
 put_ptr(app+TIO_STOCK_MENU_ROOT,menu_root);m8_tail_arm(app);
 put_ptr(launcher_object+TIO_STOCK_LAUNCHER_MANAGER,vm);tio_launcher_global=launcher_object;
 put_ptr(vm+TIO_STOCK_MANAGER_MENU,app);put_word(vm+TIO_STOCK_MANAGER_STATE,1);
 slot=tn_slot_create(app);assert(slot);m8_tail(app)->navigation=slot;allocations=frees=0;
}
/* The slot destroyed as the menu's destructor does; the service's timer then frees the controller and any page. */
static void finish(void){
 render_idle=true;tn_slot_destroy(slot);slot=NULL;
 for(unsigned i=0;i<4&&timer.callback;i++){now_ms+=250;timer.callback(&timer);}
 assert(!timer.callback&&live_count()==0&&held_token==0&&roots_deleted==roots_created);
}
static void run_tick(void){assert(timer.callback);timer.callback(&timer);}
/* A tick at which the one-second ownership check is due (exactly 1000 ms after the last one, or later). */
static void run_check(void){Control *c=ctl();assert(c);uint32_t due=c->last_check+1000;if((int32_t)(now_ms-due)<0)now_ms=due;run_tick();}
static TNScene scene(uint32_t metres){
 TNScene s;memset(&s,0,sizeof s);s.icon=TN_RIGHT;s.distance_m=metres;s.remaining_m=1200;s.remaining_s=480;s.point_count=2;s.position=(TNPoint){500,500};
 s.points[0]=(TNPoint){500,1000};s.points[1]=(TNPoint){500,500};strcpy(s.road,"Market St");strcpy(s.turn,"Turn right");return s;
}
/* One phone message, at least 100 ms after the last (dispatch drops a message while a reply is pending), and exactly
 * one reply for it. TNR_CLEAR stands for every map message (it is the one with an empty body). */
static Reply send(unsigned op,uint32_t sid,uint32_t seq){
 uint8_t b[512];size_t n;
 if(op==TNR_CLEAR)n=tnr_wrap(b,sizeof b,op,sid,seq,NULL,0);else{TNScene s=scene(100+seq);n=tn_encode(b,sizeof b,(enum TNOp)op,sid,seq,&s);}
 assert(n);now_ms+=150;TIONativeMessage m={.id=TN_MESSAGE_ID,.data=b,.bytes=(uint32_t)n};
 unsigned before=replies;tn_message_dispatch(&m);assert(replies==before+1&&last.sid==sid&&last.seq==seq);return last;
}
static void back_key(void){HostEvent e={vm};m8_hook_vm_event(&e);}
/* A visible route: START accepted, the page open and owned, the hold taken. */
static void start_visible(uint32_t sid){
 Reply r=send(TN_START,sid,1);Control *c=ctl();
 assert(r.result==TN_OK&&r.active&&c&&c->runtime.active&&!c->runtime.hidden&&c->view&&c->view->open&&held_token);
 assert(send(TN_UPDATE,sid,2).result==TN_OK);
}
/* A kept route: the page closed by the Back key with the route live (TMG8); the map copy made, the hold released. */
static void keep_by_back(void){
 Control *c=ctl();unsigned s=stops;back_key();
 assert(stops==s+1&&c->runtime.active&&c->runtime.hidden&&c->stash&&is_live(c->stash)&&size_of(c->stash)==sizeof(TNRState)&&!held_token);
 run_tick();assert(!c->view&&c->runtime.hidden);   /* the closed page is reaped by the idle renderer */
}

int main(void){
 const char *other1=apps[1],*other2=apps[5];
 assert(strcmp(other1,NAVIGATION)&&strcmp(other2,NAVIGATION)&&strcmp(other1,LAUNCHER)&&strcmp(other2,LAUNCHER)&&strcmp(other1,other2));

 /* 1. A kept route, then stock Navigation on top: ended at the one-second check, event 42 result 1 once; later route
  * messages get NO_SESSION, a START is BUSY while stock Navigation is on top and accepted (newer sid) after. */
 {reset();start_visible(11);assert(send(TNR_CLEAR,11,3).result==TN_OK);keep_by_back();Control *c=ctl();
  assert(send(TN_UPDATE,11,4).result==TN_OK&&last.active);run_check();assert(c->runtime.hidden&&trace_count==0);
  TNRState *stash=c->stash;unsigned f=frees,h=holds;top=NAVIGATION;run_check();
  assert(!c->runtime.active&&!c->runtime.hidden&&!c->stash&&!is_live(stash)&&frees==f+1&&!held_token&&holds==h);
  assert(trace_count==1&&events_42(1)==1);
  for(unsigned i=0;i<5;i++)run_check();assert(trace_count==1);
  Reply r=send(TN_UPDATE,11,5);assert(r.result==TN_NO_SESSION&&!r.active);
  r=send(TNR_CLEAR,11,6);assert(r.result==TN_NO_SESSION&&!r.active&&!c->stash);
  r=send(TN_STOP,11,7);assert(r.result==TN_NO_SESSION&&!r.active);
  r=send(TN_START,12,1);assert(r.result==TN_BUSY&&!r.active&&!c->runtime.active&&!c->view);
  run_check();assert(trace_count==1&&live_count()==2&&is_live(slot)&&is_live(c));   /* only the slot and the controller are left */
  top=LAUNCHER;r=send(TN_START,13,1);assert(r.result==TN_OK&&r.active&&c->runtime.active&&c->view&&c->view->open&&held_token);
  assert(trace_count==1);finish();}

 /* 2. A kept route under other stock apps: kept through many checks with fresh UPDATEs, no event 42; back at the
  * launcher the tile reopens the route from the kept data. */
 {reset();start_visible(21);keep_by_back();Control *c=ctl();TNRState *stash=c->stash;uint32_t seq=3;
  for(unsigned i=0;i<60;i++){top=i<30?other1:other2;if(i%5==0)assert(send(TN_UPDATE,21,seq++).result==TN_OK&&last.active);run_check();
   assert(c->runtime.active&&c->runtime.hidden&&c->stash==stash&&is_live(stash));}
  assert(trace_count==0);top=LAUNCHER;unsigned f=frees;
  assert(tn_slot_open(slot)&&c->runtime.active&&!c->runtime.hidden&&c->view&&c->view->open&&c->view->map_state.dirty&&held_token);
  assert(!c->stash&&!is_live(stash)&&frees==f+1&&trace_count==0);
  assert(send(TN_UPDATE,21,seq++).result==TN_OK&&last.active);finish();}

 /* 3. A visible page, stock Navigation on top with no hide call: ended, hold released, page closed and reaped, event 42
  * result 2. */
 {reset();start_visible(31);Control *c=ctl();TNView *view=c->view;unsigned r0=releases;top=NAVIGATION;run_check();
  assert(!c->runtime.active&&!c->runtime.hidden&&!c->stash&&!held_token&&releases==r0+1&&roots_deleted==1&&!c->view&&!is_live(view));
  assert(trace_count==1&&events_42(2)==1);
  Reply r=send(TN_UPDATE,31,3);assert(r.result==TN_NO_SESSION&&!r.active);finish();}
 /* 3b. The launcher hides first while it is still the top app (the route is kept), then stock Navigation: result 1. */
 {reset();start_visible(32);Control *c=ctl();tn_slot_hidden(slot);assert(c->runtime.hidden&&c->stash&&!held_token);run_tick();
  TNRState *stash=c->stash;unsigned f=frees,h=holds,r0=releases;assert(!c->view&&roots_deleted==1);top=NAVIGATION;run_check();
  assert(!c->runtime.active&&!c->runtime.hidden&&!c->stash&&!is_live(stash)&&frees==f+1&&!held_token&&holds==h&&releases==r0);
  assert(trace_count==1&&events_42(1)==1);finish();}
 /* 3c. The renderer is busy at the check: the session ends, but the page is not freed while busy; it is reaped once idle. */
 {reset();start_visible(33);Control *c=ctl();TNView *view=c->view;render_idle=false;top=NAVIGATION;run_check();
  assert(!c->runtime.active&&!held_token&&c->view==view&&is_live(view)&&!view->open&&roots_deleted==0&&trace_count==1&&events_42(2)==1);
  run_check();assert(c->view==view&&roots_deleted==0);
  render_idle=true;run_tick();assert(!c->view&&!is_live(view)&&roots_deleted==1&&trace_count==1);finish();}

 /* 4. A waiting page (no route) and stock Navigation: today's path (page closed, hold released), no event 42. */
 {reset();assert(tn_slot_open(slot));Control *c=ctl();assert(c->waiting&&c->view&&held_token&&!c->runtime.active);
  top=NAVIGATION;run_check();assert(!c->waiting&&!held_token&&roots_deleted==1&&!c->view&&trace_count==0);finish();}

 /* 5. A controller with no session (the waiting page left by the Back key): stock Navigation changes nothing. */
 {reset();assert(tn_slot_open(slot));Control *c=ctl();back_key();run_tick();assert(!c->waiting&&!c->view&&!held_token);
  unsigned a=allocations,f=frees,h=holds,r=releases;top=NAVIGATION;
  for(unsigned i=0;i<8;i++){now_ms+=1000;run_tick();}
  assert(!c->runtime.active&&!c->waiting&&allocations==a&&frees==f&&holds==h&&releases==r&&trace_count==0&&timer.period==250);finish();}

 /* 6. An unarmed menu (canary overwritten, a stale slot pointer left in the tail): no controller, no timer, no
  * allocation; a phone START gets the code's refusal (BUSY, not active); the Back key goes to stock; the menu
  * object is not written. */
 {reset();m8_tail_at(app)->canary^=1u;assert(!m8_tail(app));static uint8_t held[sizeof app];memcpy(held,app,sizeof app);
  Reply r=send(TN_START,61,1);assert(r.result==TN_BUSY&&!r.active&&!slot->control&&!timer.callback&&allocations==0);
  back_key();assert(stock_events==1&&stops==0&&!slot->control);
  top=NAVIGATION;r=send(TN_START,62,1);assert(r.result==TN_BUSY&&!slot->control&&allocations==0&&trace_count==0);
  assert(!memcmp(held,app,sizeof app)&&get_word(vm+TIO_STOCK_MANAGER_STATE)==1);finish();}

 /* 7. Near-miss names (one character added, one dropped), no top app and an empty page stack: the route is kept. */
 {char plus[96],minus[96];snprintf(plus,sizeof plus,"%sx",NAVIGATION);snprintf(minus,sizeof minus,"%s",NAVIGATION);minus[strlen(minus)-1]=0;
  const char *const near[]={plus,minus,NULL,"EMPTY_PAGE",""};
  reset();start_visible(71);keep_by_back();Control *c=ctl();uint32_t seq=3;
  for(unsigned i=0;i<sizeof near/sizeof *near;i++){top=near[i];assert(send(TN_UPDATE,71,seq++).result==TN_OK&&last.active);run_check();run_check();
   assert(c->runtime.active&&c->runtime.hidden&&c->stash&&trace_count==0);}
  top=NAVIGATION;run_check();assert(!c->runtime.active&&events_42(1)==1);finish();}

 /* 8. The gate: 999 ms after the previous check nothing ends; at 1000 ms it ends. */
 {reset();start_visible(81);keep_by_back();Control *c=ctl();run_check();uint32_t at=c->last_check;
  assert(send(TN_UPDATE,81,3).result==TN_OK);top=NAVIGATION;
  now_ms=at+999;run_tick();assert(c->runtime.active&&c->runtime.hidden&&c->last_check==at&&trace_count==0);
  now_ms=at+1000;run_tick();assert(!c->runtime.active&&c->last_check==at+1000&&trace_count==1&&events_42(1)==1);finish();}

 printf("PASS nav_service host (O6: kept and visible routes end under stock Navigation, event 42 results 1 and 2; other apps, "
        "near-miss names, waiting page, no session and unarmed menu unchanged; 1000 ms gate; no leak)\n");
 return 0;
}
