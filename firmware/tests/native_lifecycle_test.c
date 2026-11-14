#include "music-runtime-v1/menu_tiles.h"
#include "navigation-runtime-v1/menu9.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
typedef struct {void *camera,*apps,*focus,*music;} Slot;
static Slot nav;
static M8NativeTail storage;
static bool unarmed;   /* tail() is NULL: the menu's size check failed, its canary was overwritten, or it is being destroyed */
/* the stock menu object plus the module tail, as port_allocate_menu allocates it */
_Alignas(16) static uint32_t words[TIO_TAIL_END/sizeof(uint32_t)];
static bool calibrated;
static unsigned canceled;
void tgr_knob_cancel(void *app,uint32_t now){assert(app==words&&now==100);calibrated=false;canceled++;}
static uint32_t stream_tick(void){return 100;}
static void *camera_slot(void *p){(void)p;return NULL;}
static void *focus(void *p){(void)p;return NULL;}
static void *music(void *p){(void)p;return NULL;}
static void *apps(void *p){(void)p;return NULL;}
static Slot *slot(void *p){(void)p;return unarmed?NULL:&nav;}
static M8NativeTail *tail(void *p){(void)p;return unarmed?NULL:&storage;}
/* every module call the hooks make, and the stock trampolines they reach, counted */
static unsigned module,stock_hides,stock_destroys,forgets;
#define NOOP(name) static void name(void *p){(void)p;module++;}
NOOP(tc_slot_hidden) NOOP(tap_service_hidden) NOOP(fm_hide) NOOP(native_unregister_wheel) NOOP(retire) NOOP(tf_slot_hidden) NOOP(tm_slot_hidden) NOOP(tn_slot_hidden) NOOP(tc_slot_destroy) NOOP(fm_destroy) NOOP(tap_menu_destroy) NOOP(tf_slot_destroy) NOOP(tm_slot_destroy) NOOP(td_slot_destroy) NOOP(tn_slot_destroy) NOOP(native_snap)
static void stock_hide(void *p){assert(p==words);stock_hides++;}
static void stock_destroy(void *p){assert(p==words);stock_destroys++;}
static void fm_tiles_forget(void *p){assert(p==words);forgets++;}
static unsigned native_event_code(void *p){(void)p;return TIO_STOCK_EVENT_KEY;}
static unsigned native_event_key(void *p){(void)p;return TIO_STOCK_KEY_CONFIRM;}
/* which route the press took: stock (stock_event) or one module tile (its open function) */
static unsigned stock_events,opened,opens;
static bool stock_event(void *p,void *e){(void)p;(void)e;stock_events++;return true;}
static bool tc_native_visible(void *p){(void)p;return false;}
static bool tap_service_visible(void *p){(void)p;return false;}
static bool tm_slot_visible(void *p){(void)p;return false;}
static bool tf_back_blocked(void *p,uint32_t now){(void)p;(void)now;return false;}
static uint32_t *word(void *p,unsigned off){return (uint32_t *)((uint8_t *)p+off);}
static bool eligible(void *p){(void)p;return true;}
static unsigned fm_tile_count(void){return TIO_MENU_ITEMS;}
static unsigned fm_tile_id(unsigned id){return id;}
static void trace(unsigned op,unsigned result){(void)op;(void)result;}
static unsigned tc_slot_open(void *p){(void)p;opened=TIO_TILE_CAMERA;opens++;return 1;}
static unsigned tap_service_open(void *p){(void)p;opened=TIO_TILE_APPS;opens++;return 1;}
static unsigned tf_slot_open(void *p){(void)p;opened=TIO_TILE_FOCUS;opens++;return 1;}
static unsigned tm_slot_open(void *p){(void)p;opened=TIO_TILE_MUSIC;opens++;return 1;}
static unsigned tn_slot_open(void *p){(void)p;opened=TIO_TILE_NAVIGATION;opens++;return 1;}
static void *ptr(void *p,unsigned off){(void)p;(void)off;return words;}
static void *m8_page_open(void *p,uint32_t sid,M8Page **out){(void)p;(void)sid;(void)out;opened=TIO_TILE_DISPLAY;opens++;return words;}
static void native_report_activity(void){}
static unsigned knob_presses,knob_wheels;static void *knob_page;
static void m8_page_knob(void *page,int32_t delta,bool press){knob_page=page;if(press)knob_presses++;else if(delta)knob_wheels++;}
#include "menu_lifecycle.inc"
int main(void){
 storage.canary=1u;   /* any value: this model's tail() decides armed or not; an armed destroy must clear it */
 calibrated=true;m8_hook_hide(words);assert(!calibrated&&canceled==1&&stock_hides==1);
 calibrated=true;unsigned before_module=module;m8_hook_destroy(words);assert(!calibrated&&canceled==2&&stock_destroys==1&&forgets==1&&module>before_module);
 assert(storage.canary==0);   /* armed destroy: the module teardown ran, then the canary was cleared before stock_destroy */
 /* The launch target comes from the selected index: the label index holds a different item each time, so a hook
    that read it instead would route at least one press to the wrong tile or to stock. */
 for(unsigned id=0;id<TIO_MENU_ITEMS;id++){*word(words,TIO_STOCK_MENU_SELECTED)=id;*word(words,TIO_STOCK_MENU_LABEL_INDEX)=(id+6u)%TIO_MENU_ITEMS;calibrated=true;unsigned before=canceled,stock_before=stock_events,opens_before=opens;opened=UINT32_MAX;assert(m8_hook_event(words,NULL));assert(!calibrated&&canceled==before+1);
  if(id<TIO_STOCK_ITEMS)assert(stock_events==stock_before+1&&opens==opens_before&&opened==UINT32_MAX);
  else assert(stock_events==stock_before&&opens==opens_before+1&&opened==id);}
 /* On 1.0.6.11 rank 7 is stock's eighth tile (Do Not Disturb) and rank 8 the module's first (Turbo Display). */
 {unsigned s=stock_events,o=opens;*word(words,TIO_STOCK_MENU_SELECTED)=7;opened=UINT32_MAX;assert(m8_hook_event(words,NULL));assert(stock_events==s+1&&opens==o&&opened==UINT32_MAX);}
 {unsigned s=stock_events,o=opens;*word(words,TIO_STOCK_MENU_SELECTED)=8;opened=UINT32_MAX;assert(m8_hook_event(words,NULL));assert(stock_events==s&&opens==o+1&&opened==TIO_TILE_DISPLAY);}
 /* TMG11: with a page open the press is still swallowed (the hook returns true) and goes to that page. */
 storage.page=(void *)words;*word(words,TIO_STOCK_MENU_SELECTED)=0;calibrated=true;assert(m8_hook_event(words,NULL));assert(knob_presses==1&&knob_wheels==0&&knob_page==words);storage.page=NULL;
 /* F4: an unarmed menu is stock's. Each hook calls its stock trampoline once and nothing of the module; hide and destroy
    still cancel the knob, and destroy forgets the menu's tile references, which read no tail. */
 unarmed=true;
 {unsigned m=module,h=stock_hides,c=canceled;m8_hook_hide(words);assert(stock_hides==h+1&&module==m&&canceled==c+1);}
 {unsigned m=module,d=stock_destroys,f=forgets,c=canceled;m8_hook_destroy(words);assert(stock_destroys==d+1&&forgets==f+1&&module==m&&canceled==c+1);}
 for(unsigned id=0;id<TIO_MENU_ITEMS;id++){unsigned m=module,s=stock_events,o=opens,c=canceled;*word(words,TIO_STOCK_MENU_SELECTED)=id;
  assert(m8_hook_event(words,NULL));assert(stock_events==s+1&&opens==o&&module==m&&canceled==c);}
 unarmed=false;
 puts("PASS native menu lifecycle: hide/destroy and every activation cancel before rapid leave-return can stitch a measurement; an open page gets the press");
}
