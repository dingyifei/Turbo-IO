#ifndef TIO_MENU9_H
#define TIO_MENU9_H
#include <stdint.h>
#include <stdbool.h>
#include "../image-upload-test/native_page.h"
#if TIO_DISPLAY_RUNTIME
#include "../display-runtime-v1/native_display_page.h"
typedef TDPNativePage M8Page;
#else
typedef TIONativePage M8Page;
#endif
/* The module's tail: its own fields right after stock's launcher menu object (TIO_STOCK_MENU_BYTES). The module has no
 * RAM of its own (link.ld asserts .data and .bss are empty), so all per-menu state lives here. On 1.0.6.11 stock's row,
 * label and dot arrays have TIO_STOCK_MENU_TILES entries, so the tail's row, label, icon and dot are the Turbo Display
 * tile's objects (id 8). The canary comes first, so an overrun from the stock object hits it first. */
typedef struct {
  uint32_t canary;              /* TIO_TAIL_MAGIC ^ the menu's address once armed; anything else means unarmed */
  void *row, *label, *icon, *dot;
  M8Page *page;
  uint32_t last_session, errors;
  void *navigation;
} M8NativeTail;
/* Where the tail starts: right after the stock object, rounded up to the tail's alignment. On the 32-bit target the
 * alignment is 4 and 0x10c is already a multiple of 4, so the tail starts at 0x10c and the allocation is 0x130. On a
 * 64-bit host the struct holds 8-byte pointers (64 bytes, alignment 8), so a host test model places it at 0x110 and
 * allocates 0x150: the same expression, evaluated for the host, which keeps every host tail access aligned. */
#define TIO_TAIL_OFFSET ((TIO_STOCK_MENU_BYTES+_Alignof(M8NativeTail)-1u)&~(_Alignof(M8NativeTail)-1u))
#define TIO_TAIL_END    (TIO_TAIL_OFFSET+sizeof(M8NativeTail))
#if UINTPTR_MAX==0xffffffffu
_Static_assert(TIO_TAIL_OFFSET==TIO_STOCK_MENU_BYTES&&sizeof(M8NativeTail)==36&&TIO_TAIL_END==0x130,
               "32-bit target: 36-byte tail right after the 0x10c-byte stock object, allocation 0x130");
#endif
#define TIO_TAIL_MAGIC 0x54494f54u  /* "TIOT" */
#define TIO_TAIL_FILL  0x5a17e11du  /* pre-fill written by port_allocate_menu; never a canary the check accepts by design */
_Static_assert(TIO_STOCK_MENU_BYTES%4u==0u,"the fill and its check walk 32-bit words from the end of the stock object");
/* The tail's address whether or not it is armed. Only port_allocate.c, m8_tail_arm and the constructor's check use it. */
static inline M8NativeTail *m8_tail_at(void *app){return (M8NativeTail *)((uint8_t *)app+TIO_TAIL_OFFSET);}
static inline uint32_t m8_tail_key(void *app){return TIO_TAIL_MAGIC^(uint32_t)(uintptr_t)app;}
/* The armed tail, or NULL: for a NULL menu, before the constructor's check armed it, after a failed check, after the
 * canary was overwritten and once the destructor has started. Every module access to the tail goes through this. */
static inline M8NativeTail *m8_tail(void *app){
  if(!app)return NULL;M8NativeTail *t=m8_tail_at(app);return t->canary==m8_tail_key(app)?t:NULL;
}
/* True when the canary word of a menu holds none of the values the module writes there: not the armed key, not zero
 * (the destructor disarmed it) and not TIO_TAIL_FILL (never armed, fill intact). Then something else overwrote it. It
 * reads the same word as m8_tail and writes nothing. */
static inline bool m8_tail_canary_broken(void *app){
  if(!app)return false;uint32_t c=m8_tail_at(app)->canary;return c!=m8_tail_key(app)&&c!=0u&&c!=TIO_TAIL_FILL;
}
/* True when the module menu cannot take a page now: unarmed, or a Display page is open. */
static inline bool m8_tail_busy(void *app){M8NativeTail *t=m8_tail(app);return !t||t->page;}
/* Zero the tail, then set the canary. */
static inline void m8_tail_arm(void *app){
  M8NativeTail *t=m8_tail_at(app);
  for(unsigned i=0;i<sizeof *t;i++)((volatile uint8_t *)t)[i]=0;
  t->canary=m8_tail_key(app);
}
/* Every 32-bit word from the end of the stock object to the end of the allocation (on a 64-bit host this includes the
 * alignment gap before the tail, so an overrun into it is seen too). */
static inline void m8_tail_fill(void *app){
  for(uint32_t off=TIO_STOCK_MENU_BYTES;off+4u<=TIO_TAIL_END;off+=4u)*(volatile uint32_t *)((uint8_t *)app+off)=TIO_TAIL_FILL;
}
static inline bool m8_tail_fill_intact(void *app){
  for(uint32_t off=TIO_STOCK_MENU_BYTES;off+4u<=TIO_TAIL_END;off+=4u)if(*(volatile uint32_t *)((uint8_t *)app+off)!=TIO_TAIL_FILL)return false;
  return true;
}
int m8_hook_frame_start(int index);
int m8_hook_frame_index(int frame);
void m8_hook_names(void *app);
void m8_hook_dots(void *app);
void m8_hook_delete_dots(void *app);
void m8_hook_lottie(void *app);
void m8_hook_label_frame(void *app,int frame);
void m8_hook_label_index(void *app,int index);
void m8_hook_indicator(void *app,int frame,int previous);
bool m8_hook_frame(void *app,int frame);
const char *m8_hook_app_id(int index);
void m8_hook_refresh_label(void *app,int index);
#endif
