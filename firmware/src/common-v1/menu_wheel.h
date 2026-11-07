#ifndef TIO_MENU_WHEEL_H
#define TIO_MENU_WHEEL_H
/* Main-menu knob (DS2 rule 9, TMG9). Header-only and host-testable; menu10.c m8_hook_wheel is the only caller.
 *
 * The hook owns the stepping. It adds the raw counts of a gesture into a signed remainder and moves exactly one item per D counts (D is the
 * live detent, knob_detent.h: 300..600 in steps of 50, 400 by default). Nothing is scaled into the stock carousel any more: the stock step
 * (position += delta/600, round at .5) is never fed a wheel delta, so D alone decides how far the knob goes, in every layout and at either end.
 * The step goes through the same path as remote_native.c: write the selected index (app+0x88), invalidate the shown frame (app+0x90), call
 * stock native_snap. A step past either end is the wrap (last <-> first), the same step as any other: the target is the index plus the steps,
 * modulo the item count.
 *
 * Direction: a positive count is forward (the next item), as on every page, and it is the raw sign: the stock direction setting (0x24, which
 * stock_wheel used to apply by negating the delta when it is not 1) no longer reaches the menu, as it never reached the pages. Whether positive
 * is forward on the hardware is the device check (README, TMG9 checklist: log one turn's sign).
 *
 * A gesture is a run of counts less than 250 ms apart in one direction; a pause or a reversal drops the remainder, as does touch jitter
 * (|delta| <= 8, ignored without touching the gesture). */
#include <stdbool.h>
#include <stdint.h>
#include "tio_ui.h"
#include "knob_detent.h"
#include "../diagnostics-v1/knob_calibration.h"
_Static_assert(TIO_WHEEL_DETENT_MIN==(int)TK_DETENT_MIN&&TIO_WHEEL_DETENT_MAX==(int)TK_DETENT_MAX&&TIO_WHEEL_DETENT_STEP==(int)TK_DETENT_STEP&&TIO_WHEEL_DETENT_DEFAULT==(int)TK_DETENT_DEFAULT,
 "TK_DETENT_* (shared with the phone) must equal TIO_WHEEL_DETENT_*");

typedef struct {int32_t remainder;uint32_t motion;bool moved;} TIOMenuStep;

/* Returns the item to select, or -1 when this delta does not complete a step. index is the focused item (clamped into 0..count-1), count the
 * number of visible items, detent the live D (an invalid value falls back to the default). One call can complete several steps when one delta
 * spans several D; they all land in the target, modulo count. A full lap lands on the item it started from, which is no step. */
static inline int tio_menu_wheel_step(TIOMenuStep *s,int index,int count,int delta,uint32_t now,unsigned detent){
 if(!s||count<2||delta==0)return -1;
 int64_t d=delta;if(d>=-8&&d<=8)return -1;
 if(detent<TK_DETENT_MIN||detent>TK_DETENT_MAX||detent%TK_DETENT_STEP)detent=TK_DETENT_DEFAULT;
 bool fwd=d>0;
 if(!s->moved||(uint32_t)(now-s->motion)>250||(s->remainder>0&&!fwd)||(s->remainder<0&&fwd))s->remainder=0;
 s->motion=now;s->moved=true;
 /* 32-bit division only: the firmware links without a 64-bit divide. |total| < 2^31 + D always fits an unsigned 32-bit magnitude. */
 int64_t total=(int64_t)s->remainder+d;bool back=total<0;uint32_t mag=(uint32_t)(back?-total:total);
 uint32_t steps=mag/detent,left=mag%detent;                          /* whole detents and what is carried to the next event */
 s->remainder=back?-(int32_t)left:(int32_t)left;                     /* the remainder keeps the sign of the gesture */
 if(!steps)return -1;
 if(index<0)index=0;else if(index>count-1)index=count-1;
 uint32_t move=steps%(uint32_t)count;                                /* a whole lap lands where it started */
 int target=back?index-(int)move:index+(int)move;if(target<0)target+=count;else if(target>=count)target-=count;
 return target==index?-1:target;
}
#endif
