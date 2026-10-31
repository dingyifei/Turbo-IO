#ifndef TIO_MENU_WHEEL_H
#define TIO_MENU_WHEEL_H
/* Main-menu knob (DS2 rule 9). Header-only and host-testable; menu10.c m8_hook_wheel is the only caller.
 *
 * The stock carousel needs 600 raw units per item. The hook hands it 2x the delta, so one item takes
 * TIO_WHEEL_DETENT_RAW (300) counts, about 6.7 items per ~2000-count turn. At either end the stock carousel
 * clamps, so the hook watches the raw counts itself and wraps last <-> first once a full detent has built up
 * against the end. Positive delta is forward (next item), as on every page. Direction against the hardware is
 * unverified until the device check. */
#include <stdbool.h>
#include <stdint.h>
#include "tio_ui.h"
#include "../diagnostics-v1/knob_calibration.h"
_Static_assert(TIO_WHEEL_DETENT_RAW==(int)TK_DETENT_RAW,"TK_DETENT_RAW (shared with the phone) must equal TIO_WHEEL_DETENT_RAW");

typedef struct {int32_t pressed;uint32_t motion;bool moved;} TIOMenuWrap;

/* The delta stock_wheel receives: doubled, saturating. */
static inline int tio_menu_wheel_scaled(int delta){
 int64_t d=(int64_t)delta*2;return d>INT32_MAX?INT32_MAX:d<INT32_MIN?INT32_MIN:(int)d;
}
/* Returns the item to jump to (wrap), or -1 to hand the scaled delta to the stock carousel.
 * index is the focused item, count the number of visible items. Touch jitter (|delta| <= 8) is ignored. */
static inline int tio_menu_wheel_wrap(TIOMenuWrap *s,int index,int count,int delta,uint32_t now){
 if(!s||count<2||delta==0)return -1;
 int64_t d=delta;if(d>=-8&&d<=8)return -1;
 bool fwd=d>0,edge=fwd?index>=count-1:index<=0;
 if(!s->moved||(uint32_t)(now-s->motion)>250||((s->pressed>0)!=fwd))s->pressed=0;
 s->motion=now;s->moved=true;
 if(!edge){s->pressed=0;return -1;}
 int64_t total=(int64_t)s->pressed+d;
 if(total>=TIO_WHEEL_DETENT_RAW||total<=-TIO_WHEEL_DETENT_RAW){s->pressed=0;return fwd?0:count-1;}
 s->pressed=(int32_t)total;return -1;
}
#endif
