/* Head-motion module for the Bluetooth core (nuttx_bth.bin, stock 1.0.6.11): the per-window motion check.
 * docs/lock-design.md §7. Runs only when the enable word is 1 (bth_motion.S checks it first), in the neck-monitor
 * thread, once per window of samples (about 192 ms).
 *
 * The window's statistics are stock's own, in the 0xd8-byte batch buffer at the caller's sp + 0xf0 (writer
 * FUN_0c0be69c; Block E e1e3-bth.md): +0x00 record count, +0x18 first accel sample (3 x f32, m/s^2), +0x24 latest
 * accel sample, +0x60 sigma of |accel|. Both calls of the batch reader reach the patched BL with the same frame
 * (re/M3-STATIC.md Q3). A window counts as moving when any axis moved more than 0.3 m/s^2 inside it or since the
 * previous window, or sigma is above 0.05 m/s^2 (rotation keeps |accel| constant, so the per-axis test is the main
 * one). Moving, and 30 s or more after the last "motion seen", one message goes to the AP; nothing while still.
 * Bars are provisional (device calibration). */
#include "bth_state.h"
#include "lock_motion_wire.h"
#include <stdint.h>

struct bth_timespec {int64_t sec;int32_t nsec;};   /* NuttX on this core: 64-bit tv_sec, 32-bit tv_nsec at +8 */
struct motion_seen {uint16_t type,zero;uint32_t len;uint64_t us;float sigma;} __attribute__((packed));

/* Stock 1.0.6.11 BTH functions (bth_link.ld; each address's first bytes are pinned in build-inputs.json). */
int bth_clock_gettime(int clk,struct bth_timespec *ts);
void *bth_neck_alloc(uint32_t size,uint32_t one);   /* stock's senders call it as (0x408, 1) */
void bth_free(void *p);
int bth_neck_send(void *msg);                      /* queues msg for the AP; 0 = queued (ownership passes), else not */
int bth_motion_body(int clk,struct bth_timespec *ts,const uint8_t *caller_sp);

#define BATCH 0xf0
#define BATCH_COUNT 0x00
#define BATCH_FIRST 0x18
#define BATCH_LAST 0x24
#define BATCH_SIGMA 0x60
#define BAR_AXIS 0.3f
#define BAR_SIGMA 0.05f
#define RATE_US 30000000ull

static int moved(const float *a,const volatile float *b){
 for(int i=0;i<3;i++){float d=a[i]-b[i];if(d>BAR_AXIS||d<-BAR_AXIS)return 1;}
 return 0;
}

int bth_motion_body(int clk,struct bth_timespec *ts,const uint8_t *caller_sp){
 int ret=bth_clock_gettime(clk,ts);   /* stock's call, first and unchanged */
 const uint8_t *batch=caller_sp+BATCH;
 volatile uint64_t *last_send=(volatile uint64_t *)BTH_LAST_SEND;
 volatile float *prev=(volatile float *)BTH_PREV;
 const float *first=(const float *)(batch+BATCH_FIRST),*last=(const float *)(batch+BATCH_LAST);
 if(ret!=0||*(const uint32_t *)(batch+BATCH_COUNT)==0)return ret;
 /* prev is NaN after each "on" (bth_motion.S): every compare with it is false, so that window is judged on its own. */
 int moving=moved(last,first)||*(const float *)(batch+BATCH_SIGMA)>BAR_SIGMA||moved(last,prev);
 prev[0]=last[0];prev[1]=last[1];prev[2]=last[2];
 if(!moving)return ret;
 uint64_t now=(uint64_t)ts->sec*1000000ull+(uint64_t)(ts->nsec/1000);
 if(*last_send&&now-*last_send<RATE_US)return ret;   /* none sent yet: no wait (review finding 4) */
 struct motion_seen *m=bth_neck_alloc(TIO_NECK_MSG_BYTES,1);
 if(!m)return ret;
 m->type=TIO_MOTION_SEEN_TYPE;m->zero=0;m->len=TIO_MOTION_SEEN_LEN;m->us=now;m->sigma=*(const float *)(batch+BATCH_SIGMA);
 if(bth_neck_send(m)==0)*last_send=now;else bth_free(m);
 return ret;
}
