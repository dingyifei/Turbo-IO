#ifndef TIO_KNOB_CALIBRATION_H
#define TIO_KNOB_CALIBRATION_H
#include <stdint.h>
#include <stdbool.h>
enum {TK_ABSENT=0,TK_ACTIVE=1,TK_FINISHED=2,TK_EXPIRED=3,TK_CANCELED=4,TK_OVERFLOW=5};
enum {TK_OK=0,TK_BLOCKED=1,TK_SESSION=2,TK_BUSY=3,TK_UNAVAILABLE=4,TK_OVERFLOW_RESULT=5};
#define TK_MAX_LEASE_MS 30000u
#define TK_DETENT_RAW 600u
typedef struct {uint32_t window,sequence,start_sequence,started,lease_ms,elapsed,samples;int64_t net;uint64_t absolute;uint8_t state;} TKState;
unsigned tk_start(TKState *,uint32_t,uint32_t,uint32_t,uint32_t,bool);
unsigned tk_stop(TKState *,uint32_t,uint32_t,uint32_t,bool);
void tk_cancel(TKState *,uint32_t);
void tk_poll(TKState *,uint32_t,bool);
void tk_observe(TKState *,int32_t,uint32_t,bool,bool);
bool tk_estimate(const TKState *,uint64_t *);
#endif
