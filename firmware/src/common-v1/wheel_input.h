#ifndef TURBO_READER_INPUT_H
#define TURBO_READER_INPUT_H
#include <stdint.h>
#include <stdbool.h>
#include "tio_ui.h"
/* One step per TIO_WHEEL_DETENT_RAW (300) raw counts; the step lockout is TIO_WHEEL_LOCK_PAGE_MS (200 ms).
 * Touch jitter is not a detent. Values are a conservative starting point and
 * require hardware validation, not a claim that every touch delta is known. */
typedef struct {int32_t accumulated;uint32_t motion,step,press;bool moved,stepped,pressed,confirmed;} WRInput;
static inline int wr_input_wheel(WRInput *s,int delta,uint32_t now){
 if(!s||s->confirmed||delta==0)return 0;
 int64_t d=delta;if(d>=-8&&d<=8)return 0;
 if(!s->moved||(uint32_t)(now-s->motion)>250||((s->accumulated>0)!=(d>0)))s->accumulated=0;
 s->motion=now;s->moved=true;
 if(s->stepped&&(uint32_t)(now-s->step)<TIO_WHEEL_LOCK_PAGE_MS){s->accumulated=0;return 0;}
 if(s->pressed&&(uint32_t)(now-s->press)<TIO_WHEEL_LOCK_PAGE_MS){s->accumulated=0;return 0;}
 int64_t total=(int64_t)s->accumulated+d;
 s->accumulated=(int32_t)(total>TIO_WHEEL_DETENT_RAW?TIO_WHEEL_DETENT_RAW:total< -TIO_WHEEL_DETENT_RAW?-TIO_WHEEL_DETENT_RAW:total);
 if(s->accumulated<TIO_WHEEL_DETENT_RAW&&s->accumulated> -TIO_WHEEL_DETENT_RAW)return 0;
 int step=s->accumulated>0?1:-1;s->accumulated=0;s->step=now;s->stepped=true;return step;
}
static inline bool wr_input_press(WRInput *s,uint32_t now){
 if(!s||s->confirmed||(s->moved&&(uint32_t)(now-s->motion)<300)||(s->pressed&&(uint32_t)(now-s->press)<450))return false;
 s->press=now;s->pressed=true;s->accumulated=0;return true;
}
#endif
