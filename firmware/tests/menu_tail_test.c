/* Runtime size check and tail canary (menu9.h, menu10.c m8_hook_ctor, port_allocate.c), host model.
 *
 * The whole of menu10.c and port_allocate.c is linked against the stubs below; tests/menu_tail_host_test.py compiles it
 * with the tree's base flags and MENU_TAIL_COUNT_EDIT, the immediate of the carousel count edit in build-inputs.json.
 * port_stock_new mallocs exactly the size it is asked for, so AddressSanitizer catches any access past the module's
 * allocation. The model constructor writes exactly TIO_STOCK_MENU_BYTES bytes (label index -1, motion count
 * max(N,1) as stock's motion init does), and variants of it overrun, move the label index or keep another count, alone or
 * in any combination.
 * Host only: no device, no stock bytes. */
#include "common-v1/tio_text.h"
#include "music-runtime-v1/menu_tiles.h"
#include "common-v1/menu_wheel.h"
#include "menu-grid-v2/tile_native.h"
#include "diagnostics-v1/runtime_native.h"
#include "menu-grid-v2/menu_config.h"
#include "camera-v1/camera_native.h"
#include "app-runtime-v1/app_service.h"
#include "navigation-runtime-v1/menu9.h"
#include "menu8-renderer.h"
#include "music-runtime-v1/music_service.h"
#include "focus-v1/focus_service.h"
#include "focus-v1/focus_menu.h"
#include "diagnostics-v1/diagnostics_service.h"
#if TIO_DISPLAY_RUNTIME
#include "display-runtime-v1/native_display_file.h"
#endif
#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef MENU_TAIL_COUNT_EDIT
#error "compile with -DMENU_TAIL_COUNT_EDIT=<the carousel count edit's movs immediate> (menu_tail_host_test.py)"
#endif
_Static_assert(MENU_TAIL_COUNT_EDIT==TIO_MENU_ITEMS,"the carousel count edit writes the module's item count");
#if !TIO_DISPLAY_RUNTIME
#error "the firmware build sets TIO_DISPLAY_RUNTIME=1; compile this model the same way"
#endif

/* ---- call counters ---------------------------------------------------------------------------------------------- */
enum { S_CTOR, S_SHOW, S_HIDE, S_DESTROY, S_WHEEL, S_EVENT, S_NAMES, S_DOTS, S_DELETE_DOTS, S_LOTTIE, S_APP_ID,
       S_REFRESH_LABEL, S_MESSAGE, S_COUNT };
static unsigned stock_calls[S_COUNT];
static unsigned ui_calls;                /* every LVGL, lottie and menu_* call, and the render API */
static unsigned module_calls;            /* slot creation and teardown, page and service work */
static unsigned trace_event,trace_result,traces;
static unsigned broken_shows;            /* trace lines with event 142: a broken canary seen at a menu show */
static int wheel_delta;
static size_t requested;
static uint8_t *app;
enum { FAIL_FILL=1u, FAIL_LABEL=2u, FAIL_COUNT=4u };   /* the constructor check's failure bits (m8_hook_ctor) */
static unsigned ctor_mode;               /* 0 in bounds, or FAIL_* bits: overrun by 4 bytes, label index moved, motion count 13 */
static uint8_t after_ctor[0x200];        /* the allocation as stock_ctor left it */
static unsigned destroy_probe;           /* 1: stock_destroy checks the menu reads as unarmed from inside it */
static unsigned page_seen;               /* 1 when tdp_native_dispatch got a NULL page */

static void ui(void){ui_calls++;}
static unsigned stock_total(void){unsigned n=0;for(unsigned i=0;i<S_COUNT;i++)n+=stock_calls[i];return n;}
static uint32_t *word_at(unsigned off){return (uint32_t *)(app+off);}
/* A pointer field of the 32-bit stock layout, written the way the driver's host_ptr reads it (unaligned on a 64-bit host). */
static void put_ptr(unsigned off,void *v){memcpy(app+off,&v,sizeof v);}

/* ---- the allocation and the model constructor ---------------------------------------------------------------- */
void *port_stock_new(size_t n){requested=n;return malloc(n);}
void *stock_ctor(void *p){
  stock_calls[S_CTOR]++;assert(p==app);
  unsigned bytes=TIO_STOCK_MENU_BYTES+(ctor_mode&FAIL_FILL?4u:0u);
  memset(p,0x11,bytes);
  *word_at(TIO_STOCK_MENU_LABEL_INDEX)=ctor_mode&FAIL_LABEL?0u:UINT32_MAX;
  unsigned n=ctor_mode&FAIL_COUNT?13u:(unsigned)MENU_TAIL_COUNT_EDIT;*word_at(TIO_STOCK_MENU_MOTION+TIO_STOCK_MOTION_COUNT)=n?n:1u;
  assert(requested<=sizeof after_ctor);memcpy(after_ctor,p,requested);
  return p;
}

/* ---- stock trampolines ------------------------------------------------------------------------------------------- */
void stock_show(void *p){assert(p==app);stock_calls[S_SHOW]++;}
void stock_hide(void *p){assert(p==app);stock_calls[S_HIDE]++;}
void stock_destroy(void *p){
  assert(p==app);stock_calls[S_DESTROY]++;
  if(destroy_probe){   /* a hook stock's destructor reaches sees an unarmed menu and touches nothing */
    assert(!m8_tail(app));uint8_t before[0x200];memcpy(before,app,requested);unsigned u=ui_calls;
    assert(!m8_hook_frame(app,100));m8_hook_label_frame(app,100);m8_hook_indicator(app,100,0);
    assert(!memcmp(before,app,requested)&&ui_calls==u);
  }
}
void stock_wheel(void *p,int delta){assert(p==app);stock_calls[S_WHEEL]++;wheel_delta=delta;}
bool stock_event(void *p,void *e){assert(p==app);(void)e;stock_calls[S_EVENT]++;return true;}
void stock_names(void *p){assert(p==app);stock_calls[S_NAMES]++;}
void stock_dots(void *p){assert(p==app);stock_calls[S_DOTS]++;}
void stock_delete_dots(void *p){assert(p==app);stock_calls[S_DELETE_DOTS]++;}
void stock_lottie(void *p){assert(p==app);stock_calls[S_LOTTIE]++;}
/* Stock's lookup bounds the index itself and answers for any int; each index here gets its own answer, so a test can
 * tell which index stock was asked about. */
static const char stock_ids[TIO_MENU_ITEMS+2][3];static int stock_id_asked;
static const char *stock_id(int i){return i>=0&&i<TIO_MENU_ITEMS+2?stock_ids[i]:"stock";}
const char *stock_app_id(int i){stock_calls[S_APP_ID]++;stock_id_asked=i;return stock_id(i);}
void stock_refresh_label(void *p,int i){assert(p==app&&i>=0&&i<(int)TIO_STOCK_MENU_TILES);stock_calls[S_REFRESH_LABEL]++;}
void stock_message(void *h,const TIONativeMessage *m){(void)h;(void)m;stock_calls[S_MESSAGE]++;}
extern int m8_impl_frame_start(int),m8_impl_frame_index(int);
int m8_hook_frame_start(int index){return m8_impl_frame_start(index);}   /* the assembler shims of trampolines.S */
int m8_hook_frame_index(int frame){return m8_impl_frame_index(frame);}

/* ---- stock natives, LVGL, lottie and menu_* ----------------------------------------------------------------------- */
void native_unregister_wheel(void *p){(void)p;module_calls++;}
void native_snap(void *p){(void)p;ui();}
void native_report_activity(void){module_calls++;}
bool native_wake_overlay(void){return false;}
bool native_has_flag(void *p,uint32_t f){(void)p;(void)f;return false;}
static unsigned event_code=TIO_STOCK_EVENT_KEY,event_key=TIO_STOCK_KEY_CONFIRM;
unsigned native_event_code(void *e){(void)e;return event_code;}
unsigned native_event_key(void *e){(void)e;return event_key;}
static int objects[64];static unsigned next_object;
static void *object(void){ui();return &objects[next_object++%64];}
void *native_label_create(void *p){(void)p;return object();}
void native_label_text(void *o,const char *s){(void)o;(void)s;ui();}
void native_text_color(void *o,uint32_t a,uint32_t b){(void)o;(void)a;(void)b;ui();}
void native_align(void *o,int a,int x,int y){(void)o;(void)a;(void)x;(void)y;ui();}
void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *f,...){
  (void)a;(void)b;(void)c;(void)d;assert(!strcmp(f,"[TurboMenu8] event=%u result=%u"));
  va_list v;va_start(v,f);trace_event=va_arg(v,unsigned);trace_result=va_arg(v,unsigned);va_end(v);traces++;
  if(trace_event==142){assert(trace_result==0);broken_shows++;}
}
void *tio_lv_obj_create_ex(void *p,uint32_t f){(void)p;(void)f;return object();}
void tio_lv_obj_delete(void *o){(void)o;ui();}
void tio_lv_obj_set_size(void *o,int w,int h){(void)o;(void)w;(void)h;ui();}
void tio_lv_obj_add_flag(void *o,uint32_t f){(void)o;(void)f;ui();}
void tio_lv_obj_remove_flag(void *o,uint32_t f){(void)o;(void)f;ui();}
void tio_lv_obj_set_style_bg_color(void *o,uint32_t c,uint32_t s){(void)o;(void)c;(void)s;ui();}
void tio_lv_obj_set_style_bg_opa(void *o,uint8_t a,uint32_t s){(void)o;(void)a;(void)s;ui();}
void menu_remove_styles(void *o){(void)o;ui();}
void menu_opa(void *o,uint8_t a,uint32_t s){(void)o;(void)a;(void)s;ui();}
void menu_translate(void *o,int x,uint32_t s){(void)o;(void)x;(void)s;ui();}
void menu_lottie_frame(void *o,int f){(void)o;(void)f;ui();}
void *menu_font(int a,int b){(void)a;(void)b;ui();return NULL;}
void menu_text_font(void *o,void *f,uint32_t s){(void)o;(void)f;(void)s;ui();}
void menu_text_align(void *o,int a,uint32_t s){(void)o;(void)a;(void)s;ui();}
static void api_hidden(void *o,bool h){(void)o;(void)h;ui();}
const M8RenderAPI m8_native_api={.hidden=api_hidden};
static uint32_t clock_ms=1000;
uint32_t stream_tick(void){return clock_ms;}
int stream_queue_send(unsigned q,const TIONativeMessage *m){(void)q;(void)m;return 0;}
unsigned tio_lang(void){return 0;}
const char *tio_text(unsigned key,unsigned lang){(void)key;(void)lang;return "x";}
/* The launcher chain the message hook follows to find the menu: launcher -> manager -> menu. */
_Alignas(16) static uint8_t manager_bytes[TIO_STOCK_MANAGER_MENU+sizeof(void *)];
_Alignas(16) static uint8_t launcher_bytes[TIO_STOCK_LAUNCHER_MANAGER+sizeof(void *)];
void *tio_launcher_global=launcher_bytes;

/* ---- module services: slots, pages, files and messages ------------------------------------------------------------ */
static TNNavSlot *made_slot;
TNNavSlot *tn_slot_create(void *p){assert(p==app);module_calls++;made_slot=calloc(1,sizeof *made_slot);return made_slot;}
void tn_slot_destroy(TNNavSlot *s){module_calls++;if(s){assert(s==made_slot);free(s);made_slot=NULL;}}
void tn_slot_hidden(TNNavSlot *s){(void)s;module_calls++;}
bool tn_slot_visible(TNNavSlot *s){(void)s;return false;}
bool tn_slot_open(TNNavSlot *s){(void)s;module_calls++;return true;}
static TMMusicSlot music_slot;static TFSlot focus_slot;static TAPMenu apps_menu;static TCSlot camera;
TMMusicSlot *tm_slot_create(void *p){(void)p;module_calls++;return &music_slot;}
void tm_slot_destroy(TMMusicSlot *s){(void)s;module_calls++;}
void tm_slot_hidden(TMMusicSlot *s){(void)s;module_calls++;}
void tm_slot_wheel(TMMusicSlot *s,int d){(void)s;(void)d;module_calls++;}
bool tm_slot_visible(TMMusicSlot *s){(void)s;return false;}
bool tm_slot_open(TMMusicSlot *s){(void)s;module_calls++;return true;}
TFSlot *tf_slot_create(void *p){(void)p;module_calls++;return &focus_slot;}
void tf_slot_destroy(TFSlot *s){(void)s;module_calls++;}
void tf_slot_hidden(TFSlot *s){(void)s;module_calls++;}
void tf_slot_wheel(TFSlot *s,int d){(void)s;(void)d;module_calls++;}
bool tf_slot_visible(TFSlot *s){(void)s;return false;}
bool tf_slot_open(TFSlot *s){(void)s;module_calls++;return true;}
TAPMenu *tap_menu_create(void *p){(void)p;module_calls++;return &apps_menu;}
void tap_menu_destroy(TAPMenu *m){(void)m;module_calls++;}
void tap_service_hidden(void *p){(void)p;module_calls++;}
bool tap_service_visible(void *p){(void)p;return false;}
void tap_service_wheel(void *p,int d){(void)p;(void)d;module_calls++;}
bool tap_service_open(void *p){(void)p;module_calls++;return true;}
TCSlot *tc_slot_create(void *p){(void)p;module_calls++;return &camera;}
void tc_slot_destroy(TCSlot *s){(void)s;module_calls++;}
void tc_slot_hidden(TCSlot *s){(void)s;module_calls++;}
bool tc_slot_open(TCSlot *s){(void)s;module_calls++;return true;}
bool tc_native_visible(void *p){(void)p;return false;}
void tc_native_wheel(void *p,int d){(void)p;(void)d;module_calls++;}
void td_slot_destroy(TNNavSlot *s){(void)s;module_calls++;}
void tgr_knob_cancel(void *p,uint32_t now){(void)p;(void)now;}
void tgr_knob_observe(void *p,int32_t d,uint32_t now){(void)p;(void)d;(void)now;}
void fm_show(void *p){(void)p;module_calls++;}
void fm_hide(void *p){(void)p;module_calls++;}
void fm_sync(void *p){(void)p;module_calls++;}
void fm_destroy(void *p){(void)p;module_calls++;}
unsigned fm_menu_rows(void){return 1;}
unsigned fm_tile_count(void){return TIO_MENU_ITEMS;}
static bool remapped;   /* a non-default active tile map: rank r shows tile TIO_MENU_LAST-r */
unsigned fm_tile_id(unsigned rank){return remapped&&rank<TIO_MENU_ITEMS?TIO_MENU_LAST-rank:rank;}
unsigned fm_tile_rank(unsigned id){return id<TIO_MENU_ITEMS?id:255u;}
static unsigned forgets;
void fm_tiles_forget(void *p){assert(p==app);forgets++;}
int fm_wheel_step(void *p,int index,int count,int delta,uint32_t now){(void)p;(void)index;(void)count;(void)delta;(void)now;module_calls++;return FM_STEP_NO_CONTROL;}
TDPNativePage *tdp_native_open(void *parent,uint32_t sid,TDPNativePage **owner){(void)parent;(void)sid;(void)owner;module_calls++;return NULL;}
void tdp_native_retire(TDPNativePage *p){(void)p;module_calls++;}
void tdp_native_knob(TDPNativePage *p,int32_t d,bool press){(void)p;(void)d;(void)press;module_calls++;}
static bool display_ours;
bool tdp_native_message_is_ours(const TIONativeMessage *m){(void)m;return display_ours;}
TDPResult tdp_native_dispatch(TDPNativePage *p,const TIONativeMessage *m){(void)m;page_seen=p==NULL;return (TDPResult)0;}
TIOImageResult tdp_native_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
TIOImageResult tap_service_file(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
TIOImageResult tf_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
TIOImageResult td_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
TIOImageResult tm_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
TIOImageResult tn_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){(void)f;(void)q;return TIO_FOREIGN;}
void tc_native_message(const TIONativeMessage *m){(void)m;}
void tgr_native_message(const TIONativeMessage *m){(void)m;}
bool tap_service_ours(const TIONativeMessage *m){(void)m;return false;}
void tap_service_message(const TIONativeMessage *m){(void)m;module_calls++;}
bool tf_message_is_ours(const TIONativeMessage *m){(void)m;return false;}
void tf_message_dispatch(const TIONativeMessage *m){(void)m;module_calls++;}
bool td_message_is_ours(const TIONativeMessage *m){(void)m;return false;}
void td_message_dispatch(const TIONativeMessage *m){(void)m;module_calls++;}
bool tm_message_is_ours(const TIONativeMessage *m){(void)m;return false;}
void tm_message_dispatch(const TIONativeMessage *m){(void)m;module_calls++;}
bool tn_message_is_ours(const TIONativeMessage *m){(void)m;return false;}
void tn_message_dispatch(const TIONativeMessage *m){(void)m;module_calls++;}

extern void *port_allocate_menu(void);
extern void *m8_hook_ctor(void *);
extern void m8_hook_show(void *),m8_hook_hide(void *),m8_hook_destroy(void *),m8_hook_wheel(void *,int);
extern bool m8_hook_event(void *,void *);
extern void m8_hook_render_slide(void *);
extern void m8_hook_message(void *,const TIONativeMessage *);

/* ---- helpers ------------------------------------------------------------------------------------------------------ */
static void reset_counts(void){memset(stock_calls,0,sizeof stock_calls);ui_calls=module_calls=traces=forgets=0;wheel_delta=0;page_seen=0;}
/* A new menu the way stock makes one: the allocation edit (port_allocate_menu), then the constructor edit. */
static void construct(unsigned mode){
  ctor_mode=mode;reset_counts();app=port_allocate_menu();assert(app);assert(requested==TIO_TAIL_END);
  /* the pre-fill covers every word from the end of the stock object to the end of the allocation */
  for(uint32_t off=TIO_STOCK_MENU_BYTES;off+4u<=TIO_TAIL_END;off+=4u)assert(*word_at(off)==TIO_TAIL_FILL);
  assert(m8_hook_ctor(app)==app&&stock_calls[S_CTOR]==1&&traces==1);
}
static void dispose(void){
  if(made_slot){free(made_slot);made_slot=NULL;}free(app);app=NULL;
  void *none=NULL;memcpy(manager_bytes+TIO_STOCK_MANAGER_MENU,&none,sizeof none);   /* the manager holds no freed menu */
}
/* Point the launcher chain at the manager, and the manager at menu. */
static void manager_holds(void *menu){
  void *v=manager_bytes;memcpy(launcher_bytes+TIO_STOCK_LAUNCHER_MANAGER,&v,sizeof v);memcpy(manager_bytes+TIO_STOCK_MANAGER_MENU,&menu,sizeof menu);
}
/* Case 6: on an unarmed menu every stock-backed hook calls its stub exactly once (and nothing of the module), and every
 * replacement hook leaves the whole allocation byte-identical and calls no LVGL, lottie or menu_* function.
 * broken: the canary word was overwritten, so the one show prints event 142 once (and no other line); no other hook
 * prints event 142. */
static void unarmed_hooks(bool destroyed,bool broken){
  assert(!m8_tail(app));
  unsigned lines=traces,b=broken_shows;
  manager_holds(app);   /* the menu stock's app id caller and the message hook find */
  uint8_t before[0x200];
  #define SAME(call) do{memcpy(before,app,requested);unsigned u=ui_calls,s=stock_total(),mc=module_calls;call;\
    assert(!memcmp(before,app,requested)&&ui_calls==u&&stock_total()==s&&module_calls==mc);}while(0)
  #define ONCE(which,call) do{unsigned s=stock_total(),mc=module_calls,u=ui_calls;unsigned w=stock_calls[which];call;\
    assert(stock_calls[which]==w+1&&stock_total()==s+1&&module_calls==mc&&ui_calls==u);}while(0)
  for(int f=-5;f<=30*TIO_MENU_ITEMS+5;f+=37){
    SAME(m8_hook_label_frame(app,f));SAME(m8_hook_indicator(app,f,f-30));SAME(assert(!m8_hook_frame(app,f)));
  }
  for(int i=-1;i<=TIO_MENU_ITEMS;i++)SAME(m8_hook_label_index(app,i));
  *(float *)(app+TIO_MENU_SCROLL_POSITION_OFFSET)=3.5f;memcpy(before,app,requested);
  SAME(m8_hook_render_slide(app));
  for(int i=0;i<(int)TIO_STOCK_MENU_TILES;i++)assert(m8_hook_frame_start(i)==(int)(TIO_STOCK_MENU_FIRST_FRAME+TIO_STOCK_MENU_FRAMES_PER_TILE*(unsigned)i)&&m8_hook_frame_index(m8_hook_frame_start(i))==i);
  ONCE(S_SHOW,m8_hook_show(app));assert(broken_shows==b+broken&&traces==lines+broken);
  ONCE(S_NAMES,m8_hook_names(app));ONCE(S_DOTS,m8_hook_dots(app));
  ONCE(S_DELETE_DOTS,m8_hook_delete_dots(app));ONCE(S_LOTTIE,m8_hook_lottie(app));
  ONCE(S_EVENT,assert(m8_hook_event(app,NULL)));
  for(int r=0;r<(int)TIO_STOCK_MENU_TILES;r++)ONCE(S_REFRESH_LABEL,m8_hook_refresh_label(app,r));
  SAME(m8_hook_refresh_label(app,TIO_STOCK_MENU_TILES));SAME(m8_hook_refresh_label(app,TIO_MENU_LAST));SAME(m8_hook_refresh_label(app,-1));
  ONCE(S_HIDE,m8_hook_hide(app));
  ONCE(S_WHEEL,m8_hook_wheel(app,-37));assert(wheel_delta==-37);   /* the unscaled delta */
  /* app id: stock's own answer for every index, with no tile map applied, even while a non-default map is active.
   * A negative index goes to stock too: stock's lookup bounds it and gives its default id, never the module's "". */
  static const int negative[]={-1,-2,INT_MIN};
  for(int r=0;r<2;r++){remapped=r;
    for(int i=0;i<(int)TIO_MENU_ITEMS;i++)ONCE(S_APP_ID,assert(m8_hook_app_id(i)==stock_id(i)&&stock_id_asked==i));
    for(unsigned n=0;n<sizeof negative/sizeof *negative;n++){int i=negative[n];stock_id_asked=0;
      ONCE(S_APP_ID,assert(m8_hook_app_id(i)==stock_id(i)&&stock_id_asked==i));}
  }
  remapped=false;
  /* message: dispatched as today; the module's page lookup finds no armed menu */
  TIONativeMessage m;memset(&m,0,sizeof m);
  display_ours=false;ONCE(S_MESSAGE,m8_hook_message(NULL,&m));
  display_ours=true;page_seen=0;SAME(m8_hook_message(NULL,&m));assert(page_seen==1);display_ours=false;
  if(!destroyed){   /* destroy last: the module teardown does not run, stock's destructor does, once */
    unsigned f=forgets;ONCE(S_DESTROY,m8_hook_destroy(app));assert(forgets==f+1);
  }
  assert(broken_shows==b+broken);   /* only the show printed event 142, and only when broken (the message hook's event 21 is its own) */
  #undef SAME
  #undef ONCE
}

int main(void){
  /* 7. port_allocate.c and menu10.c agree on the tail through menu9.h: the request is the tail's end, and the armed
   *    tail ends inside it (the malloc is exact, so ASan sees any access past it). */
  _Static_assert(TIO_TAIL_OFFSET>=TIO_STOCK_MENU_BYTES&&TIO_TAIL_OFFSET%_Alignof(M8NativeTail)==0,"host tail aligned after the object");

  /* 1. normal: armed, slots created, trace 140/0, and the hooks work */
  construct(0);
  assert(m8_tail(app)==m8_tail_at(app)&&m8_tail(app)->navigation==made_slot&&made_slot&&made_slot->music==&music_slot&&made_slot->camera==&camera);
  assert(trace_event==140&&trace_result==0);
  assert((uint8_t *)m8_tail(app)+sizeof(M8NativeTail)<=app+requested);
  {static int lottie;put_ptr(TIO_STOCK_MENU_LOTTIE,&lottie);*word_at(TIO_STOCK_MENU_FRAME)=0;unsigned u=ui_calls;
   assert(m8_hook_frame(app,100)&&*word_at(TIO_STOCK_MENU_FRAME)==100&&ui_calls>u);
   m8_hook_label_frame(app,100);assert(*word_at(TIO_STOCK_MENU_LABEL_INDEX)==3);}
  /* app id on the armed menu the manager holds: the module's ids past stock's tiles, through the active tile map */
  manager_holds(app);reset_counts();
  for(int i=0;i<(int)TIO_STOCK_ITEMS;i++)assert(m8_hook_app_id(i)==stock_id(i)&&stock_id_asked==i);
  assert(!strcmp(m8_hook_app_id(TIO_TILE_DISPLAY),"TurboDisplay")&&!strcmp(m8_hook_app_id(TIO_TILE_CAMERA),"TurboCamera"));
  remapped=true;assert(!strcmp(m8_hook_app_id(0),"TurboCamera")&&m8_hook_app_id(TIO_MENU_LAST)==stock_id(0));remapped=false;
  assert(stock_calls[S_APP_ID]==TIO_STOCK_ITEMS+1);
  /* the same armed menu, but the chain names no menu: the module still answers, map and all, as it did before the
   * unarmed check existed (an armed menu must not depend on the chain) */
  manager_holds(NULL);reset_counts();
  for(int i=0;i<(int)TIO_STOCK_ITEMS;i++)assert(m8_hook_app_id(i)==stock_id(i)&&stock_id_asked==i);
  assert(!strcmp(m8_hook_app_id(TIO_TILE_DISPLAY),"TurboDisplay")&&!strcmp(m8_hook_app_id(TIO_TILE_CAMERA),"TurboCamera"));
  remapped=true;assert(!strcmp(m8_hook_app_id(0),"TurboCamera")&&m8_hook_app_id(TIO_MENU_LAST)==stock_id(0));remapped=false;
  assert(stock_calls[S_APP_ID]==TIO_STOCK_ITEMS+1);
  manager_holds(app);
  /* an armed show prints no line */
  {unsigned lines=traces,b=broken_shows;m8_hook_show(app);assert(m8_tail(app)&&broken_shows==b&&traces==lines);}
  /* 5. destroy tears the module down, clears the canary, and a hook reached from inside stock_destroy sees an unarmed menu */
  reset_counts();destroy_probe=1;m8_hook_destroy(app);destroy_probe=0;
  assert(stock_calls[S_DESTROY]==1&&forgets==1&&!made_slot&&module_calls>0&&!m8_tail(app)&&m8_tail_at(app)->canary==0);
  unarmed_hooks(true,false);dispose();

  /* 2, 3. every failing combination of the three checks (an overrun past the stock object, a moved label index, a motion
   *    count of 13): not armed, trace 141 with the failed bits, and the one write is stock's own motion count, made only
   *    when the motion-count check passed (its count proves where the count is), whatever the other two checks say. */
  for(unsigned mode=1;mode<8;mode++){
    construct(mode);assert(!m8_tail(app)&&!made_slot&&trace_event==141&&trace_result==mode);
    uint32_t count;memcpy(&count,app+TIO_STOCK_MENU_MOTION+TIO_STOCK_MOTION_COUNT,4);
    assert(count==(mode&FAIL_COUNT?13u:(uint32_t)TIO_STOCK_MENU_TILES));
    if(!(mode&FAIL_COUNT)){uint32_t want=TIO_STOCK_MENU_TILES;memcpy(after_ctor+TIO_STOCK_MENU_MOTION+TIO_STOCK_MOTION_COUNT,&want,4);}
    assert(!memcmp(after_ctor,app,requested));
    unarmed_hooks(false,false);assert(!m8_tail(app));dispose();
  }

  /* 4. canary smashed after arming: unarmed from then on (the slots it made stay allocated: a leak, never a write) */
  construct(0);assert(m8_tail(app));m8_tail_at(app)->canary^=1u;assert(!m8_tail(app));
  /* each show of it prints one event 142 (no "reported once" state), and writes nothing to the menu */
  for(int n=0;n<2;n++){uint8_t before[0x200];memcpy(before,app,requested);unsigned lines=traces,b=broken_shows,s=stock_calls[S_SHOW];
    m8_hook_show(app);assert(broken_shows==b+1&&traces==lines+1&&stock_calls[S_SHOW]==s+1&&!memcmp(before,app,requested));}
  unarmed_hooks(false,true);dispose();

  printf("PASS menu tail: host model tail %zu bytes at 0x%zx (the 32-bit target's 36 bytes at 0x10c, allocation 0x130, are menu9.h's compile-time assert), "
         "count edit movs r1,#%d equals the module's %d items; armed after an in-bounds constructor; refused for all 7 combinations of an overrun, "
         "a moved label index and a wrong motion count (stock's count restored only when the count check passed), a smashed canary (event 142 once per show, from no other hook) and after destroy (no 142, nor when refused or armed); "
         "stock-backed hooks call their stub once, replacement hooks touch nothing and the app id is stock's for every index on an unarmed menu\n",
         sizeof(M8NativeTail),(size_t)TIO_TAIL_OFFSET,MENU_TAIL_COUNT_EDIT,(int)TIO_MENU_ITEMS);
  return 0;
}
