#if defined(TD_STOCK_10611) && TD_STOCK_10611
#error not ported to 1.0.6.11 yet: LVGL pool capacity has one witness (F4)
#endif
/* TDG1 offline candidate provider; requires verified UI-owner binding.
 * This first provider never calls mallinfo/lv_mem_monitor/logger_log, walks
 * blocks, takes locks, allocates, reads arbitrary memory, or writes NAND. */
#include "native_light.h"
#include "stock_abi.h"
/* current/peak are the LVGL global plus TIO_STOCK_LVGL_MEM_USED / TIO_STOCK_LVGL_MEM_PEAK. tests/stock_layout_test.py
 * proves both offsets from two stock functions each and checks that the rebase table's native_light_current and
 * native_light_peak values equal the LVGL global (table value display_unit) plus them; tools/rebase_apply.py writes
 * the addresses. The pool capacity below has one witness only, which is why the guard above stays (F4). */
extern int td_gettid(void); /* Native gettid, hash-pinned by candidate builder. */
void td_stock_light(void *context,TDDiagnostics *d){
 TDLightOwner *owner=context;
 td_metric(d,TD_LV_TOTAL,0,false);td_metric(d,TD_LV_USED,0,false);td_metric(d,TD_LV_PEAK,0,false);
 if(!owner||owner->owner_tid<0||td_gettid()!=owner->owner_tid)return;
 const volatile uint32_t *current=(const volatile uint32_t *)(uintptr_t)0x1850cfd8;
 const volatile uint32_t *peak=(const volatile uint32_t *)(uintptr_t)0x1850cfdc;
 uint32_t a=*current,b=*peak;
 if(a>b||b>0x1000000u)return; /* fail closed; no capacity guesses */
 td_metric(d,TD_LV_TOTAL,0x1000000u,true); /* configured capacity, not free */
 td_metric(d,TD_LV_USED,a,true);td_metric(d,TD_LV_PEAK,b,true);
 /* System heap/free/largest block/CPU/boot count intentionally unavailable. */
}
