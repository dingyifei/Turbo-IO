#include "music-runtime-v1/menu_tiles.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
typedef struct {void *camera,*apps,*focus,*music;} Slot;
typedef struct {void *row,*label,*icon,*dot,*page,*navigation;uint32_t last_session;} M8NativeTail;
static Slot nav;
static M8NativeTail storage;
static uint32_t words[128];
static bool calibrated;
static unsigned canceled;
void tgr_knob_cancel(void *app,uint32_t now){assert(app==words&&now==100);calibrated=false;canceled++;}
static uint32_t stream_tick(void){return 100;}
static void *camera_slot(void *p){(void)p;return NULL;}
static void *focus(void *p){(void)p;return NULL;}
static void *music(void *p){(void)p;return NULL;}
static void *apps(void *p){(void)p;return NULL;}
static Slot *slot(void *p){(void)p;return &nav;}
static M8NativeTail *tail(void *p){(void)p;return &storage;}
#define NOOP(name) static void name(void *p){(void)p;}
NOOP(tc_slot_hidden) NOOP(tap_service_hidden) NOOP(fm_hide) NOOP(native_unregister_wheel) NOOP(retire) NOOP(tf_slot_hidden) NOOP(tm_slot_hidden) NOOP(tn_slot_hidden) NOOP(stock_hide) NOOP(tc_slot_destroy) NOOP(fm_destroy) NOOP(tap_menu_destroy) NOOP(tf_slot_destroy) NOOP(tm_slot_destroy) NOOP(td_slot_destroy) NOOP(tn_slot_destroy) NOOP(fm_tiles_forget) NOOP(stock_destroy) NOOP(native_snap)
static unsigned native_event_code(void *p){(void)p;return 0xe;}
static unsigned native_event_key(void *p){(void)p;return 0x3a;}
static bool stock_event(void *p,void *e){(void)p;(void)e;return true;}
static bool tc_native_visible(void *p){(void)p;return false;}
static bool tap_service_visible(void *p){(void)p;return false;}
static bool tm_slot_visible(void *p){(void)p;return false;}
static bool tf_back_blocked(void *p,uint32_t now){(void)p;(void)now;return false;}
static uint32_t *word(void *p,unsigned off){return (uint32_t *)((uint8_t *)p+off);}
static bool eligible(void *p){(void)p;return true;}
static unsigned fm_tile_count(void){return 13;}
static unsigned fm_tile_id(unsigned id){return id;}
static void trace(unsigned op,unsigned result){(void)op;(void)result;}
static unsigned tc_slot_open(void *p){(void)p;return 1;}
static unsigned tap_service_open(void *p){(void)p;return 1;}
static unsigned tf_slot_open(void *p){(void)p;return 1;}
static unsigned tm_slot_open(void *p){(void)p;return 1;}
static unsigned tn_slot_open(void *p){(void)p;return 1;}
static void *ptr(void *p,unsigned off){(void)p;(void)off;return words;}
static void *m8_page_open(void *p,uint32_t sid,void **out){(void)p;(void)sid;(void)out;return words;}
static void native_report_activity(void){}
#include "menu_lifecycle.inc"
int main(void){
 calibrated=true;m8_hook_hide(words);assert(!calibrated&&canceled==1);calibrated=true;m8_hook_destroy(words);assert(!calibrated&&canceled==2);
 for(unsigned id=0;id<13;id++){*word(words,0x88)=id;calibrated=true;unsigned before=canceled;assert(m8_hook_event(words,NULL));assert(!calibrated&&canceled==before+1);}
 puts("PASS native menu lifecycle: hide/destroy and every activation cancel before rapid leave-return can stitch a measurement");
}
