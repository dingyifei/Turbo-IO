/* TDG1 offline candidate provider; requires verified UI-owner binding.
 * This first provider never calls mallinfo/lv_mem_monitor/logger_log, walks
 * blocks, takes locks, allocates, reads arbitrary memory, or writes NAND. */
#include "native_light.h"
#include "stock_abi.h"
#if !(defined(TD_STOCK_1055) && TD_STOCK_1055) && !(defined(TD_STOCK_10512) && TD_STOCK_10512)
#error Native provider requires a hash-pinned Strix profile (1.0.5.5 or 1.0.5.12)
#endif
/* current/peak are display unit + 0x1bc / + 0x1c0 on both bases (rebase table: the same stock ldr/str sites use
 * those offsets from the base literal); tools/rebase_apply.py writes the base's addresses. */
extern int td_gettid(void); /* Native gettid, hash-pinned by candidate builder. */
void td_stock_light(void *context,TDDiagnostics *d){
 TDLightOwner *owner=context;
 td_metric(d,TD_LV_TOTAL,0,false);td_metric(d,TD_LV_USED,0,false);td_metric(d,TD_LV_PEAK,0,false);
 if(!owner||owner->owner_tid<0||td_gettid()!=owner->owner_tid)return;
 const volatile uint32_t *current=(const volatile uint32_t *)(uintptr_t)0x184ec540;
 const volatile uint32_t *peak=(const volatile uint32_t *)(uintptr_t)0x184ec544;
 uint32_t a=*current,b=*peak;
 if(a>b||b>0x1000000u)return; /* fail closed; no capacity guesses */
 td_metric(d,TD_LV_TOTAL,0x1000000u,true); /* configured capacity, not free */
 td_metric(d,TD_LV_USED,a,true);td_metric(d,TD_LV_PEAK,b,true);
 /* System heap/free/largest block/CPU/boot count intentionally unavailable. */
}
