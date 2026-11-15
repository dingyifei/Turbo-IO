/* The unarmed-menu path of four module services (app, camera, focus, music), host model.
 *
 * tests/unarmed_services_host_test.py compiles app_service.c, camera_native.c, focus_service.c and music_service.c whole
 * (only their 32-bit timer and pointer-field loads adapted for the host), with their protocol units (app_command.c,
 * camera.c, focus.c, music.c, tio_text.c), against the stubs below, under AddressSanitizer and UBSan.
 *
 * "Unarmed" is menu9.h's m8_tail returning NULL for the launcher's menu. Two shapes are modelled:
 *   FILL     the constructor's check failed (event 141): the tail still holds port_allocate_menu's fill;
 *   SMASHED  the menu was armed and its slots made, then the canary word was overwritten (event 142): the tail still
 *            points at a complete set of module slots from the armed life. A service that read the tail without the
 *            canary check would find them, so a skipped check shows up as a changed outcome, not only as a crash.
 * Both shapes also run with the launcher's manager holding no menu, where a service that asks stock to make one
 * (nav_ensure_menu) gets back a menu that comes out unarmed.
 *   LIVE     SMASHED with the music or the camera page open: the armed life opened it through the service's own open
 *            function, so a live controller (root, power hold, timer) sits in the slot. In SMASHED the slots hold no
 *            controller and a lookup that skipped or weakened the canary check would find nothing to act on; here it
 *            would find the open page, so every tail lookup must leave that controller byte for byte as it was.
 *
 * On an unarmed menu every entry point that stock or the menu hooks can reach must leave the menu object (and the stale
 * slots) byte for byte as they were, take no power hold, change no launcher state, create no widget, and answer a phone
 * message with the refusal the code defines. The app and focus services keep one menu-independent singleton (found
 * through the timer list, not the menu); a phone message creates it whatever the menu's state, and the test pins that
 * exact cost (allocations and one timer) and that it is paid once.
 * Host only: no device, no stock bytes. */
#include "navigation-runtime-v1/menu9.h"
#include "navigation-runtime-v1/nav_service.h"
#include "navigation-runtime-v1/nav_lvgl.h"
#include "app-runtime-v1/app_service.h"
#include "app-runtime-v1/app_command.h"
#include "app-runtime-v1/app_files.h"
#include "app-runtime-v1/app_lvgl.h"
#include "app-runtime-v1/app_shelf.h"
#include "camera-v1/camera_native.h"
#include "camera-v1/camera.h"
#include "focus-v1/focus_service.h"
#include "focus-v1/focus_view.h"
#include "focus-v1/focus.h"
#include "music-runtime-v1/music_service.h"
#include "music-runtime-v1/music.h"
#include "menu8-renderer.h"
#include "common-v1/knob_detent.h"
#include "common-v1/business_idle.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- what the services did ----------------------------------------------------------------------------------------- */
typedef struct {
  unsigned allocs,frees,timers,timer_deletes,holds,releases,set_state,screen,force_off,ensure,widgets,activity,stops,
           events_added,fm_syncs,replies,logs,runner_starts,runner_installs,runner_removes,runner_closes,shelf_opens,
           runner_events,enqueues;
} Counts;
static Counts n;

/* ---- the menu, the launcher chain and the stale slots ------------------------------------------------------------- */
_Alignas(16) static uint8_t menu[TIO_TAIL_END];
_Alignas(16) static uint8_t manager_bytes[TIO_STOCK_MANAGER_STATE+sizeof(uint32_t)+TIO_STOCK_MANAGER_MENU+sizeof(void *)];
_Alignas(16) static uint8_t launcher_bytes[TIO_STOCK_LAUNCHER_MANAGER+sizeof(void *)];
void *tio_launcher_global=launcher_bytes;
static int menu_root;   /* stock's root object of the menu: a skipped check would build widgets under it */
static TNNavSlot stale;static TMMusicSlot stale_music;static TFSlot stale_focus;static TCSlot stale_camera;static TAPMenu stale_apps;
static bool manager_empty;   /* the manager holds no menu until nav_ensure_menu makes one */
static void set_manager_menu(void *p){memcpy(manager_bytes+TIO_STOCK_MANAGER_MENU,&p,sizeof p);}
void *nav_ensure_menu(void *vm){assert(vm==manager_bytes);n.ensure++;set_manager_menu(menu);return menu;}

/* ---- heap: every block is tracked so a reset can return it ------------------------------------------------------- */
static void *blocks[64];static size_t block_size[64];
void *stream_memalign(size_t align,size_t size){
  n.allocs++;void *p=NULL;assert(posix_memalign(&p,align<sizeof(void *)?sizeof(void *):align,size)==0);
  for(unsigned i=0;i<64;i++)if(!blocks[i]){blocks[i]=p;block_size[i]=size;return p;}
  abort();
}
void stream_free(void *p){if(!p)return;n.frees++;for(unsigned i=0;i<64;i++)if(blocks[i]==p){blocks[i]=NULL;free(p);return;}abort();}
/* Every live block byte for byte (the services memset what they allocate): a live controller left alone stays equal. */
typedef struct {void *p[64];size_t size[64];uint8_t *copy[64];} Heap;
static void heap_snap(Heap *h){
  for(unsigned i=0;i<64;i++){h->p[i]=blocks[i];h->size[i]=block_size[i];h->copy[i]=NULL;
    if(blocks[i]){h->copy[i]=malloc(block_size[i]);assert(h->copy[i]);memcpy(h->copy[i],blocks[i],block_size[i]);}}
}
static bool heap_same(Heap *h){
  bool ok=true;
  for(unsigned i=0;i<64;i++){
    if(h->p[i]!=blocks[i]||(blocks[i]&&(h->size[i]!=block_size[i]||memcmp(h->copy[i],blocks[i],block_size[i]))))ok=false;
    free(h->copy[i]);}
  return ok;
}

/* ---- timers: the host keeps callback and user apart (the 32-bit target packs them at TIO_STOCK_TIMER_CB/_USER) ---- */
typedef struct {void (*cb)(void *);void *user;uint32_t period;bool live;} HostTimer;
static HostTimer timers[8];
void *stream_timer_create(void (*cb)(void *),uint32_t ms,void *user){
  n.timers++;for(unsigned i=0;i<8;i++)if(!timers[i].live){timers[i]=(HostTimer){cb,user,ms,true};return &timers[i];}
  abort();
}
void stream_timer_delete(void *t){n.timer_deletes++;((HostTimer *)t)->live=false;}
void stream_timer_period(void *t,uint32_t ms){((HostTimer *)t)->period=ms;}
void *stream_timer_next(void *t){
  unsigned i=t?(unsigned)((HostTimer *)t-timers)+1u:0u;
  for(;i<8;i++)if(timers[i].live)return &timers[i];
  return NULL;
}
void *host_timer_user(void *t){return ((HostTimer *)t)->user;}
void (*host_timer_cb(void *t))(void *){return ((HostTimer *)t)->cb;}
static void run_timers(void){for(unsigned i=0;i<8;i++)if(timers[i].live)timers[i].cb(&timers[i]);}

/* ---- events: key events (code, key) and the view manager's events (user = the manager) -------------------------- */
typedef struct {unsigned code,key;void *user;} HostEvent;
unsigned native_event_code(void *e){return ((HostEvent *)e)->code;}
unsigned native_event_key(void *e){return ((HostEvent *)e)->key;}
void *stream_event_user(void *e){return ((HostEvent *)e)->user;}
void *stream_add_event(void *o,void (*cb)(void *),uint32_t code,void *user){(void)o;(void)cb;(void)code;(void)user;n.events_added++;return o;}
void nav_stop_event(void *e){(void)e;n.stops++;}

/* ---- the environment: home, paired, unfolded, idle, screen on -------------------------------------------------- */
static uint32_t clock_ms=100000;
uint32_t stream_tick(void){return clock_ms;}
static int monitors,link_object,input_object;
void *nav_monitors(void){return &monitors;}
void *nav_link(void *m){assert(m==&monitors);return &link_object;}
void *nav_input(void *m){assert(m==&monitors);return &input_object;}
bool nav_bonded(void *l){assert(l==&link_object);return true;}
int nav_connection(unsigned which){(void)which;return 1;}
bool nav_folded(void *i){assert(i==&input_object);return false;}
static bool screen_on=true;
bool focus_screen_on(void){return screen_on;}
bool tio_business_idle(void){return true;}
bool ce_extension_idle(void){return true;}
const char *nav_top_app(void){return "com.rayneo.liteos.launcher";}
unsigned tio_lang(void){return 0;}
unsigned tio_knob_detent(void){return 400;}
uint32_t tap_random(void){return 0x13572468u;}
uint32_t nav_always_on(const char *who){(void)who;n.holds++;return 7;}
void nav_release_always_on(const char *who,uint32_t token){(void)who;(void)token;n.releases++;}
void nav_set_state(void *vm,unsigned state){(void)vm;(void)state;n.set_state++;}
void nav_screen_on(bool on){(void)on;n.screen++;}
int nav_force_off(void){n.force_off++;return 0;}
void native_report_activity(void){n.activity++;}
void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *f,...){(void)a;(void)b;(void)c;(void)d;(void)f;n.logs++;}
void fm_sync(void *app){(void)app;n.fm_syncs++;}
bool tn_slot_visible(TNNavSlot *s){(void)s;return false;}

/* ---- widgets: any call but the idle query counts ----------------------------------------------------------------- */
static int widget_objects[8];
static bool w_idle(void *c){(void)c;return true;}
static void *w_make(void *c,void *parent){(void)c;(void)parent;n.widgets++;return &widget_objects[0];}
static void *w_label(void *c,void *parent,unsigned px){(void)c;(void)parent;(void)px;n.widgets++;return &widget_objects[1];}
static void w_place(void *c,void *o,int x,int y,int w,int h){(void)c;(void)o;(void)x;(void)y;(void)w;(void)h;n.widgets++;}
static void w_buffer(void *c,void *o,const uint8_t *b,unsigned w,unsigned h){(void)c;(void)o;(void)b;(void)w;(void)h;n.widgets++;}
static void w_text(void *c,void *o,const char *s){(void)c;(void)o;(void)s;n.widgets++;}
static void w_visible(void *c,void *o,bool v){(void)c;(void)o;(void)v;n.widgets++;}
static void w_destroy(void *c,void *o){(void)c;(void)o;n.widgets++;}
static void w_clip(void *c,void *o){(void)c;(void)o;n.widgets++;}
static void w_color(void *c,void *o,uint32_t rgb){(void)c;(void)o;(void)rgb;n.widgets++;}
TNWidgets tn_lvgl_widgets(void){return (TNWidgets){NULL,w_idle,w_make,w_make,w_label,w_place,w_buffer,w_text,w_visible,w_destroy,w_clip,w_color};}
void dc_text_mode(void *o,int mode){(void)o;(void)mode;n.widgets++;}
void native_label_text(void *o,const char *s){(void)o;(void)s;n.widgets++;}
void native_text_color(void *o,uint32_t a,uint32_t b){(void)o;(void)a;(void)b;n.widgets++;}
static void *r_create(void *parent){(void)parent;n.widgets++;return &widget_objects[2];}
static void r_delete(void *o){(void)o;n.widgets++;}
static void r_hidden(void *o,bool h){(void)o;(void)h;n.widgets++;}
static bool r_configure(void *o,void *parent){(void)o;(void)parent;n.widgets++;return true;}
const M8RenderAPI m8_native_api={.create_root=r_create,.delete_root=r_delete,.hidden=r_hidden,.configure_root=r_configure};
bool tf_view_open(TFView *v,const TNWidgets *api,void *a,void *b){(void)v;(void)api;(void)a;(void)b;n.widgets++;return false;}
void tf_view_enter(TFView *v,uint32_t now){(void)v;(void)now;n.widgets++;}
void tf_view_input(TFView *v,uint32_t now){(void)v;(void)now;n.widgets++;}
bool tf_view_hint(const TFView *v,uint32_t now){(void)v;(void)now;return false;}
bool tf_view_due(const TFView *v,uint32_t now,bool compact){(void)v;(void)now;(void)compact;return false;}
bool tf_view_draw(TFView *v,const TFocus *s,bool compact,uint32_t now){(void)v;(void)s;(void)compact;(void)now;n.widgets++;return false;}
bool tf_view_close(TFView *v){(void)v;n.widgets++;return true;}

/* ---- the app runtime below the service: one installed app in slot 0 ---------------------------------------------- */
#define APP_ID "demo"
int tap_store_scan(TAPStore *s){memset(s->slots,0,sizeof s->slots);s->slots[0].present=true;s->slots[0].version=1;strcpy(s->slots[0].id,APP_ID);return TAP_STORE_OK;}
bool tap_files_native_bind(TAPFiles *f,TAPStoreIO *io){(void)f;(void)io;return true;}
bool tap_lvgl_bind(TAPLVGL *l,TAPView *v,TAPWidgets *api){(void)l;(void)v;(void)api;return true;}
void tap_runner_init(TAPRunner *r,TAPStore *s,const TAPWidgets *api,void *parent){(void)api;r->store=s;r->parent=parent;r->slot=-1;}
int tap_runner_start(TAPRunner *r,unsigned slot){(void)r;(void)slot;n.runner_starts++;return TAP_STORE_OK;}
bool tap_runner_close(TAPRunner *r){(void)r;n.runner_closes++;return true;}
bool tap_runner_poll(TAPRunner *r){(void)r;return true;}
TAPEvent tap_runner_event(TAPRunner *r,unsigned key,uint32_t now){(void)r;(void)key;(void)now;n.runner_events++;return (TAPEvent){TAP_NO_EVENT,0};}
int tap_runner_install(TAPRunner *r,const char *id,const char *name,uint16_t v,const uint8_t *w,size_t len,unsigned *slot){
  (void)r;(void)id;(void)name;(void)v;(void)w;(void)len;n.runner_installs++;*slot=1;return TAP_STORE_OK;}
int tap_runner_remove(TAPRunner *r,unsigned slot){(void)r;(void)slot;n.runner_removes++;return TAP_STORE_OK;}
bool tap_shelf_open(TAPRunner *r){(void)r;n.shelf_opens++;return true;}

/* ---- the phone link: every reply is kept ------------------------------------------------------------------------- */
static uint8_t reply_wire[1024];static unsigned reply_bytes;
int tdp_rnlink_send(unsigned business,const uint8_t *p,unsigned bytes,void *ctx){
  assert(business==15&&!ctx&&bytes<=sizeof reply_wire);memcpy(reply_wire,p,bytes);reply_bytes=bytes;n.replies++;return 0;}
static unsigned nibble(uint8_t c){assert((c>='0'&&c<='9')||(c>='a'&&c<='f'));return c<='9'?c-'0':c-'a'+10u;}
/* The data bytes of the last JSON reply (app, focus, music): the hex string after "data":" */
static size_t reply_data(uint8_t *out,size_t cap){
  static const char key[]="\"data\":\"";const uint8_t *p=reply_wire,*end=reply_wire+reply_bytes;size_t k=sizeof key-1;
  while(p+k<=end&&memcmp(p,key,k))p++;
  assert(p+k<=end);p+=k;size_t got=0;
  while(p+1<end&&*p!='"'){assert(got<cap);out[got++]=(uint8_t)(16u*nibble(p[0])+nibble(p[1]));p+=2;}
  return got;
}
static TCPacket camera_reply(void){
  static uint8_t raw[TC_RAW_MAX];size_t got=tc_unwrap(reply_wire,reply_bytes,raw,sizeof raw,true);assert(got);
  TCPacket q;assert(tc_decode(raw,got,&q,true));return q;}

/* ---- phone messages, made through each service's own file path (the queue message it posts) ------------------- */
static TIONativeMessage queued;static uint8_t queued_data[TAP_COMMAND_MAX];
static int enqueue(unsigned queue,const TIONativeMessage *m){
  assert(queue==TIO_STOCK_QUEUE_LAUNCHER&&m->bytes<=sizeof queued_data);n.enqueues++;
  queued=*m;memcpy(queued_data,m->data,m->bytes);queued.data=queued_data;return 0;}
static TIONativeMessage via_file(const char *name,const uint8_t *data,size_t bytes,TIOImageResult (*receive)(const TIONativeFile *,TIOCopyEnqueue)){
  static TIONativeFile f;memset(&f,0,sizeof f);f.data=data;f.declared=f.received=(uint32_t)bytes;f.complete=1;strcpy(f.filename,name);
  unsigned before=n.enqueues;assert(receive(&f,enqueue)==TIO_OK&&n.enqueues==before+1);return queued;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static uint32_t tax_crc(const uint8_t *p,size_t len){uint32_t v=~0u;for(size_t i=0;i<len;i++){v^=i>=20&&i<24?0:p[i];for(unsigned k=0;k<8;k++)v=(v>>1)^(0xedb88320u&-(v&1u));}return ~v;}
static TIONativeMessage app_message(unsigned op,uint32_t request,uint32_t session){
  static uint8_t p[96];memset(p,0,sizeof p);memcpy(p,"TAX1",4);p[4]=(uint8_t)op;size_t len=24;
  const char *name=op==TAP_INSTALL?"Demo":"";unsigned id=op==TAP_QUERY?0u:(unsigned)strlen(APP_ID),nm=(unsigned)strlen(name),wire=op==TAP_INSTALL?4u:0u;
  p[5]=op==TAP_QUERY||op==TAP_INSTALL?255:0;p[6]=(uint8_t)id;p[7]=(uint8_t)nm;w32(p+8,request);w32(p+12,op==TAP_QUERY?0:session);
  p[16]=op==TAP_QUERY?0:1;p[18]=(uint8_t)wire;memcpy(p+len,APP_ID,id);len+=id;memcpy(p+len,name,nm);len+=nm;memset(p+len,0x41,wire);len+=wire;
  w32(p+20,tax_crc(p,len));return via_file("turbo-app.tax",p,len,tap_service_file);}
static TIONativeMessage focus_message(unsigned op,uint32_t sid,uint32_t seq,uint32_t revision){
  static uint8_t p[TF_BYTES];TFCommand c={.op=op,.sid=sid,.seq=seq,.revision=revision,.seconds=op==TF_START?1500u:0u};
  assert(tf_encode(p,sizeof p,&c)==TF_BYTES);return via_file("turbo-focus.tfp",p,sizeof p,tf_file_receive);}
static TIONativeMessage music_message(unsigned op,uint32_t seq){
  static uint8_t p[32+TM_STATE_BYTES];static const uint8_t state[TM_STATE_BYTES];
  size_t len=tm_encode(p,sizeof p,op,0,9,1,seq,0,op==TM_OPEN||op==TM_CLOCK?state:NULL,op==TM_OPEN||op==TM_CLOCK?sizeof state:0);
  assert(len);return via_file("turbo-music.tmu",p,len,tm_file_receive);}
static TIONativeMessage camera_message(unsigned op,uint32_t sid,uint32_t seq,uint32_t a){
  static uint8_t raw[TC_RAW_MAX],wire[TC_WIRE_MAX];TCPacket q={.op=(uint8_t)op,.sid=sid,.seq=seq,.a=a};
  size_t len=tc_packet(raw,sizeof raw,&q,false);assert(len);len=tc_wrap(wire,sizeof wire,raw,len,false);assert(len);
  return (TIONativeMessage){.id=TIO_STOCK_MESSAGE_RNLINK,.data=wire,.bytes=(uint32_t)len};}

/* ---- the unarmed menus ------------------------------------------------------------------------------------------- */
/* LIVE_MUSIC and LIVE_CAMERA are SMASHED with that service's page open: the armed life opened it through the service's
 * own open function (and, for the camera, a phone session), so its controller is live in the slot, with a root, a power
 * hold and a timer, when the canary is overwritten. */
enum Shape {FILL,SMASHED,LIVE_MUSIC,LIVE_CAMERA};
static void open_music_page(void),open_camera_page(void);
static void reset(enum Shape shape,bool empty){
  for(unsigned i=0;i<64;i++)if(blocks[i]){free(blocks[i]);blocks[i]=NULL;}
  memset(timers,0,sizeof timers);memset(&n,0,sizeof n);clock_ms+=100000;screen_on=true;reply_bytes=0;
  memset(menu,0x11,sizeof menu);
  {void *root=&menu_root;memcpy(menu+TIO_STOCK_MENU_ROOT,&root,sizeof root);}
  memset(manager_bytes,0,sizeof manager_bytes);memset(launcher_bytes,0,sizeof launcher_bytes);
  {void *vm=manager_bytes;memcpy(launcher_bytes+TIO_STOCK_LAUNCHER_MANAGER,&vm,sizeof vm);}
  set_manager_menu(menu);   /* the armed life's menu is the manager's */
  if(shape==FILL)m8_tail_fill(menu);
  else{
    stale_music=(TMMusicSlot){.app=menu};stale_focus=(TFSlot){.app=menu};stale_camera=(TCSlot){.app=menu};stale_apps=(TAPMenu){.app=menu};
    stale=(TNNavSlot){.app=menu,.music=&stale_music,.focus=&stale_focus,.camera=&stale_camera,.apps=&stale_apps};
    m8_tail_arm(menu);m8_tail(menu)->navigation=&stale;
    if(shape==LIVE_MUSIC)open_music_page();
    if(shape==LIVE_CAMERA)open_camera_page();
    m8_tail_at(menu)->canary^=1u;
  }
  assert(!m8_tail(menu));
  assert(!empty||shape==FILL||shape==SMASHED);
  manager_empty=empty;set_manager_menu(empty?NULL:menu);
  memset(&n,0,sizeof n);reply_bytes=0;   /* only what happens on the unarmed menu is counted */
}
/* The menu and the stale slots, byte for byte. */
typedef struct {uint8_t menu[TIO_TAIL_END];TNNavSlot nav;TMMusicSlot music;TFSlot focus;TCSlot camera;TAPMenu apps;} Snapshot;
static void snap(Snapshot *s){memcpy(s->menu,menu,sizeof menu);s->nav=stale;s->music=stale_music;s->focus=stale_focus;s->camera=stale_camera;s->apps=stale_apps;}
static bool same(const Snapshot *s){
  return !memcmp(s->menu,menu,sizeof menu)&&!memcmp(&s->nav,&stale,sizeof stale)&&!memcmp(&s->music,&stale_music,sizeof stale_music)&&
         !memcmp(&s->focus,&stale_focus,sizeof stale_focus)&&!memcmp(&s->camera,&stale_camera,sizeof stale_camera)&&!memcmp(&s->apps,&stale_apps,sizeof stale_apps);}
/* The call leaves the menu and the stale slots as they were and does nothing a service does only for an armed menu:
 * no power hold, no launcher state change, no screen wake, no widget, no activity report, no tile resync, no runner
 * start or shelf. allocs/timers: what the call may add (only the app and focus singletons, once). */
#define UNARMED(allocs_added,timers_added,call) do{Snapshot s_;snap(&s_);Counts c_=n;call;assert(same(&s_));\
  assert(n.holds==c_.holds&&n.set_state==c_.set_state&&n.screen==c_.screen&&n.force_off==c_.force_off&&n.widgets==c_.widgets);\
  assert(n.activity==c_.activity&&n.fm_syncs==c_.fm_syncs&&n.runner_starts==c_.runner_starts&&n.shelf_opens==c_.shelf_opens&&n.events_added==c_.events_added);\
  assert(n.allocs==c_.allocs+(allocs_added)&&n.timers==c_.timers+(timers_added)&&n.timer_deletes==c_.timer_deletes);}while(0)

static HostEvent key(unsigned k){return (HostEvent){TIO_STOCK_EVENT_KEY,k,manager_bytes};}
static void keys(void){
  const unsigned ks[]={TIO_STOCK_KEY_CONFIRM,TIO_STOCK_KEY_BACK};
  for(unsigned i=0;i<2;i++){HostEvent e=key(ks[i]);
    UNARMED(0,0,assert(!tc_native_event(&e)));UNARMED(0,0,assert(!tap_service_event(&e)));
    UNARMED(0,0,assert(!tf_handle_event(&e)));UNARMED(0,0,assert(!tm_handle_event(&e)));}
  assert(n.stops==0);
}

/* ---- app ---------------------------------------------------------------------------------------------------------- */
static void app_case(enum Shape shape,bool empty){
  reset(shape,empty);
  /* the hooks' entry points (reached only for an armed menu; driven here on the unarmed one all the same) */
  UNARMED(0,0,assert(!tap_service_visible(menu)));UNARMED(0,0,tap_service_hidden(menu));UNARMED(0,0,tap_service_destroy(menu));
  UNARMED(0,0,tap_service_wheel(menu,400));UNARMED(0,0,tap_menu_destroy(NULL));
  keys();
  /* a query creates the singleton (control, store, runner and one timer, as with any menu) and is answered */
  UNARMED(0,0,tap_service_message(&(TIONativeMessage){0}));assert(n.replies==0);   /* not ours: nothing at all */
  TIONativeMessage m=app_message(TAP_QUERY,1,0);
  UNARMED(3,1,tap_service_message(&m));
  uint8_t r[TAP_REPLY_BYTES];assert(n.replies==1&&reply_data(r,sizeof r)==TAP_REPLY_BYTES&&!memcmp(r,"TAR1",4)&&r[4]==TAP_STORE_OK);
  uint32_t nonce=(uint32_t)r[12]|(uint32_t)r[13]<<8|(uint32_t)r[14]<<16|(uint32_t)r[15]<<24;assert(nonce==tap_random());
  /* launch with a fresh request on the current session: refused with TAP_DENIED, before any launcher state change;
   * with no menu, stock is asked for one once and the menu it makes is refused the same way */
  m=app_message(TAP_LAUNCH,2,nonce);
  UNARMED(0,0,tap_service_message(&m));
  assert(n.replies==2&&reply_data(r,sizeof r)==TAP_REPLY_BYTES&&r[4]==TAP_DENIED&&n.ensure==(empty?1u:0u)&&n.runner_starts==0);
  /* install is not tied to the menu: with no armed menu there is no module page to protect, so it is permitted */
  m=app_message(TAP_INSTALL,3,nonce);
  UNARMED(0,0,tap_service_message(&m));
  assert(n.replies==3&&reply_data(r,sizeof r)==TAP_REPLY_BYTES&&r[4]==TAP_STORE_OK&&n.runner_installs==1);
  /* stop needs no menu either; there is no view to close */
  m=app_message(TAP_STOP,4,nonce);
  UNARMED(0,0,tap_service_message(&m));assert(n.replies==4&&reply_data(r,sizeof r)==TAP_REPLY_BYTES&&r[4]==TAP_STORE_OK);
  /* remove takes install's permission */
  m=app_message(TAP_REMOVE,5,nonce);
  UNARMED(0,0,tap_service_message(&m));assert(n.replies==5&&reply_data(r,sizeof r)==TAP_REPLY_BYTES&&r[4]==TAP_STORE_OK&&n.runner_removes==1);
  /* the singleton now exists: every entry point again, then its timer */
  UNARMED(0,0,assert(!tap_service_visible(menu)));UNARMED(0,0,tap_service_hidden(menu));UNARMED(0,0,tap_service_destroy(menu));
  UNARMED(0,0,tap_service_wheel(menu,-400));keys();
  UNARMED(0,0,run_timers());clock_ms+=31000;UNARMED(0,0,run_timers());
  /* open is reached only from an armed menu's confirm; on an unarmed one it refuses (the singleton already exists) */
  UNARMED(0,0,assert(!tap_service_open(menu)));
  assert(n.runner_events==0&&n.allocs==3&&n.timers==1);
}

/* ---- focus -------------------------------------------------------------------------------------------------------- */
static void focus_case(enum Shape shape,bool empty){
  reset(shape,empty);
  TFSlot *none=NULL;   /* focus(app) for an unarmed menu */
  UNARMED(0,0,assert(!tf_slot_visible(none)));UNARMED(0,0,tf_slot_hidden(none));UNARMED(0,0,tf_slot_wheel(none,400));UNARMED(0,0,tf_slot_destroy(none));
  {TSLive live;memset(&live,0,sizeof live);UNARMED(0,0,tf_live(clock_ms,&live));assert(!live.pomodoro);}
  keys();
  /* a start creates the singleton (one block, one timer: the focus timer runs whichever page is up) and is accepted;
   * the page is not entered: no hold, no state change, no view. With no menu, stock is asked for one once. */
  TIONativeMessage m=focus_message(TF_START,5,1,0);
  UNARMED(1,1,tf_message_dispatch(&m));
  uint8_t r[TF_BYTES];assert(n.replies==1&&reply_data(r,sizeof r)==TF_BYTES&&!memcmp(r,"TFA1",4)&&r[5]==TF_OK&&r[6]==TF_RUNNING&&n.ensure==(empty?1u:0u));
  /* a peek asks for the page explicitly: accepted, still no page */
  m=focus_message(TF_PEEK,5,2,1);
  UNARMED(0,0,tf_message_dispatch(&m));assert(n.replies==2&&reply_data(r,sizeof r)==TF_BYTES&&r[5]==TF_OK);
  m=focus_message(TF_QUERY,5,3,0);
  UNARMED(0,0,tf_message_dispatch(&m));assert(n.replies==3&&reply_data(r,sizeof r)==TF_BYTES&&r[5]==TF_OK);
  {TSLive live;memset(&live,0,sizeof live);UNARMED(0,0,tf_live(clock_ms,&live));assert(live.pomodoro);}
  /* the timer: a screen that comes back on while running, then the end of the period (a due reminder asks for the page) */
  UNARMED(0,0,run_timers());screen_on=false;UNARMED(0,0,run_timers());screen_on=true;UNARMED(0,0,run_timers());
  clock_ms+=1500u*1000u+1000u;UNARMED(0,0,run_timers());clock_ms+=6000;UNARMED(0,0,run_timers());
  assert(n.replies>=4);   /* the running and pending state is still reported to the phone every 5 s */
  UNARMED(0,0,assert(!tf_slot_visible(none)));UNARMED(0,0,tf_slot_hidden(none));UNARMED(0,0,tf_slot_wheel(none,-400));keys();
  /* open is reached only from an armed menu's confirm (with that menu's slot); with no slot it refuses */
  UNARMED(0,0,assert(!tf_slot_open(none)));
  m=focus_message(TF_STOP,5,4,2);
  UNARMED(0,0,tf_message_dispatch(&m));assert(reply_data(r,sizeof r)==TF_BYTES&&r[5]==TF_OK);UNARMED(0,0,run_timers());
  assert(n.allocs==1&&n.timers==1);
}

/* ---- music -------------------------------------------------------------------------------------------------------- */
static void music_case(enum Shape shape,bool empty){
  reset(shape,empty);
  TMMusicSlot *none=NULL;   /* music(app) for an unarmed menu */
  UNARMED(0,0,assert(!tm_slot_visible(none)));UNARMED(0,0,tm_slot_hidden(none));UNARMED(0,0,tm_slot_wheel(none,400));
  UNARMED(0,0,assert(!tm_slot_open(none)));UNARMED(0,0,tm_slot_destroy(none));
  {TSLive live;memset(&live,0,sizeof live);UNARMED(0,0,tm_slot_live(none,clock_ms,&live));assert(!live.music_playing);}
  keys();
  /* every phone message is refused with TM_BUSY and creates nothing: the controller lives in the menu's slot */
  static const unsigned ops[]={TM_OPEN,TM_CLOCK,TM_QUERY,TM_CLOSE};
  for(unsigned i=0;i<4;i++){TIONativeMessage m=music_message(ops[i],i+1);unsigned e=n.ensure;
    UNARMED(0,0,tm_message_dispatch(&m));
    uint8_t r[32];assert(n.replies==i+1&&reply_data(r,sizeof r)==32&&!memcmp(r,"TMA1",4)&&r[5]==TM_ACK&&r[6]==TM_BUSY&&r[7]==0);
    assert(n.ensure==e+(empty&&i==0?1u:0u));}   /* with no menu, only the first message finds none: stock makes one */
  UNARMED(0,0,run_timers());
  assert(n.allocs==0&&n.timers==0);
}

/* ---- camera ------------------------------------------------------------------------------------------------------- */
static void camera_case(enum Shape shape,bool empty){
  reset(shape,empty);
  TCSlot *none=NULL;   /* camera_slot(app) for an unarmed menu */
  UNARMED(0,0,assert(!tc_native_visible(menu)));UNARMED(0,0,tc_slot_hidden(none));UNARMED(0,0,tc_native_wheel(menu,400));
  UNARMED(0,0,assert(!tc_slot_open(none)));UNARMED(0,0,tc_slot_destroy(none));
  {TSLive live;memset(&live,0,sizeof live);UNARMED(0,0,tc_slot_live(none,&live));assert(!live.camera);}
  keys();
  /* hello is answered with the frame size whatever the menu; open is refused with TC_BUSY (with no menu, after stock
   * made one); every session message is refused with TC_SESSION */
  TIONativeMessage m=camera_message(TC_HELLO,0,1,0);
  UNARMED(0,0,tc_native_message(&m));
  {TCPacket q=camera_reply();assert(n.replies==1&&q.op==TC_HELLO&&q.result==TC_OK&&q.a==TC_WIDTH&&q.b==TC_HEIGHT);}
  m=camera_message(TC_OPEN,3,2,clock_ms);
  UNARMED(0,0,tc_native_message(&m));
  {TCPacket q=camera_reply();assert(n.replies==2&&q.op==TC_OPEN&&q.result==TC_BUSY&&q.sid==3&&n.ensure==(empty?1u:0u));}
  static const unsigned ops[]={TC_STATE,TC_PING,TC_CLOSE,TC_BEGIN,TC_CHUNK,TC_COMMIT,TC_ABORT};
  for(unsigned i=0;i<sizeof ops/sizeof *ops;i++){m=camera_message(ops[i],3,3+i,0);
    UNARMED(0,0,tc_native_message(&m));TCPacket q=camera_reply();assert(n.replies==3+i&&q.op==ops[i]&&q.result==TC_SESSION);}
  m=camera_message(TC_OPEN,0,20,clock_ms);
  UNARMED(0,0,tc_native_message(&m));{TCPacket q=camera_reply();assert(q.op==TC_OPEN&&q.result==TC_SESSION);}
  UNARMED(0,0,run_timers());
  assert(n.allocs==0&&n.timers==0);
}

/* ---- a live page when the canary is overwritten ------------------------------------------------------------------ */
/* Opened on the armed menu, the way the menu's confirm and the phone open it. Each page also answers its input while
 * the menu is armed, so the same input on the smashed menu below is known to reach a controller that would act. */
static void open_music_page(void){
  assert(tm_slot_open(&stale_music)&&tm_slot_visible(&stale_music));
  HostEvent e=key(TIO_STOCK_KEY_CONFIRM);unsigned stops=n.stops;assert(tm_handle_event(&e)&&n.stops==stops+1);
}
static void open_camera_page(void){
  assert(tc_slot_open(&stale_camera)&&tc_native_visible(menu));
  TIONativeMessage m=camera_message(TC_OPEN,3,1,clock_ms);tc_native_message(&m);
  {TCPacket q=camera_reply();assert(q.op==TC_OPEN&&q.result==TC_OK);}
  TSLive live;memset(&live,0,sizeof live);tc_slot_live(&stale_camera,&live);assert(live.camera);
  unsigned replies=n.replies;tc_native_wheel(menu,400);assert(n.replies==replies+1);   /* a zoom event to the phone */
}
/* The call leaves every live block (the controller and what it owns) as it was, besides all that UNARMED checks. */
#define LIVE(call) do{Heap h_;heap_snap(&h_);UNARMED(0,0,call);assert(heap_same(&h_));}while(0)
static void live_case(enum Shape shape){
  reset(shape,false);
  assert(shape==LIVE_MUSIC?stale_music.control&&!stale_camera.control:stale_camera.control&&!stale_music.control);
  /* the entry points that reach a slot through the menu's tail: key events, the camera's visible and wheel, the app's
   * hooks, and every phone message that looks the slot up */
  const unsigned ks[]={TIO_STOCK_KEY_CONFIRM,TIO_STOCK_KEY_BACK};
  for(unsigned i=0;i<2;i++){HostEvent e=key(ks[i]);
    LIVE(assert(!tm_handle_event(&e)));LIVE(assert(!tc_native_event(&e)));LIVE(assert(!tap_service_event(&e)));LIVE(assert(!tf_handle_event(&e)));}
  LIVE(assert(!tc_native_visible(menu)));LIVE(tc_native_wheel(menu,400));LIVE(tc_native_wheel(menu,-400));
  LIVE(assert(!tap_service_visible(menu)));LIVE(tap_service_wheel(menu,400));LIVE(tap_service_hidden(menu));LIVE(tap_service_destroy(menu));
  static const unsigned music_ops[]={TM_OPEN,TM_CLOCK,TM_QUERY,TM_CLOSE};
  for(unsigned i=0;i<4;i++){TIONativeMessage m=music_message(music_ops[i],100+i);
    LIVE(tm_message_dispatch(&m));uint8_t r[32];assert(reply_data(r,sizeof r)==32&&r[5]==TM_ACK&&r[6]==TM_BUSY);}
  TIONativeMessage m=camera_message(TC_HELLO,0,50,0);
  LIVE(tc_native_message(&m));{TCPacket q=camera_reply();assert(q.op==TC_HELLO&&q.result==TC_OK);}
  m=camera_message(TC_OPEN,3,51,clock_ms);
  LIVE(tc_native_message(&m));{TCPacket q=camera_reply();assert(q.op==TC_OPEN&&q.result==TC_BUSY);}
  static const unsigned camera_ops[]={TC_STATE,TC_PING,TC_CLOSE,TC_BEGIN,TC_CHUNK,TC_COMMIT,TC_ABORT};
  for(unsigned i=0;i<sizeof camera_ops/sizeof *camera_ops;i++){m=camera_message(camera_ops[i],3,52+i,0);
    LIVE(tc_native_message(&m));TCPacket q=camera_reply();assert(q.op==camera_ops[i]&&q.result==TC_SESSION);}
  assert(n.stops==0&&n.holds==0&&n.releases==0&&n.allocs==0&&n.timers==0);
  /* The page's own timer reads no tail and is not a menu entry point: it may act on its own page, but it leaves the menu
   * and the slots as they were and allocates nothing. */
  {Snapshot s;snap(&s);unsigned allocs=n.allocs,timers_made=n.timers;run_timers();assert(same(&s)&&n.allocs==allocs&&n.timers==timers_made);}
}

int main(void){
  unsigned runs=0;
  /* SMASHED first: there a skipped canary check finds live slots and fails an assertion; in FILL it would follow the fill
   * word as a pointer and fault (ASan reports it, which fails the run as well). */
  static const enum Shape shapes[]={SMASHED,FILL};
  for(unsigned k=0;k<2;k++)for(int empty=0;empty<2;empty++){
    enum Shape shape=shapes[k];
    app_case(shape,empty);focus_case(shape,empty);music_case(shape,empty);camera_case(shape,empty);runs++;
  }
  live_case(LIVE_MUSIC);live_case(LIVE_CAMERA);runs+=2;
  reset(FILL,false);
  printf("PASS unarmed services: app, camera, focus and music on %u unarmed menus (fill intact or canary smashed with stale slots, "
         "menu held or made by stock, and canary smashed under an open music or camera page): menu and stale slots byte-identical, "
         "a live page controller untouched by every tail lookup, no power hold, launcher state, screen wake, widget or tile resync; "
         "app launch TAP_DENIED (query, install, remove and stop answered), music every op TM_BUSY, camera open TC_BUSY and session ops TC_SESSION (hello answered), "
         "focus start/peek accepted with no page; only the app and focus singletons allocate, once\n",runs);
  return 0;
}
