#include "knob_calibration.h"
#include <limits.h>
#include <string.h>
static void elapsed(TKState *s,uint32_t now){uint32_t d=now-s->started;s->elapsed=d>s->lease_ms?s->lease_ms:d;}
void tk_cancel(TKState *s,uint32_t now){if(s&&s->state==TK_ACTIVE){elapsed(s,now);s->state=TK_CANCELED;}}
void tk_poll(TKState *s,uint32_t now,bool allowed){if(!s||s->state!=TK_ACTIVE)return;elapsed(s,now);if(!allowed)s->state=TK_CANCELED;else if((uint32_t)(now-s->started)>=s->lease_ms)s->state=TK_EXPIRED;}
unsigned tk_start(TKState *s,uint32_t window,uint32_t sequence,uint32_t lease,uint32_t now,bool allowed){
 if(!s||!window||!sequence||!lease||lease>TK_MAX_LEASE_MS)return TK_UNAVAILABLE;tk_poll(s,now,allowed);if(!allowed)return TK_BLOCKED;
 if(window==s->window)return sequence==s->start_sequence&&lease==s->lease_ms?(s->state==TK_OVERFLOW?TK_OVERFLOW_RESULT:TK_OK):TK_SESSION;
 if(s->state==TK_ACTIVE)return TK_BUSY;memset(s,0,sizeof *s);s->window=window;s->sequence=s->start_sequence=sequence;s->started=now;s->lease_ms=lease;s->state=TK_ACTIVE;return TK_OK;
}
unsigned tk_stop(TKState *s,uint32_t window,uint32_t sequence,uint32_t now,bool allowed){
 if(!s)return TK_UNAVAILABLE;tk_poll(s,now,allowed);if(!allowed)return TK_BLOCKED;if(!window||window!=s->window||!sequence)return TK_SESSION;
 if(sequence==s->sequence&&s->state!=TK_ACTIVE)return s->state==TK_OVERFLOW?TK_OVERFLOW_RESULT:TK_OK;
 if(sequence<=s->sequence||(uint32_t)(sequence-s->sequence)>=0x80000000u)return TK_SESSION;
 s->sequence=sequence;if(s->state==TK_ACTIVE){elapsed(s,now);s->state=TK_FINISHED;}return s->state==TK_OVERFLOW?TK_OVERFLOW_RESULT:TK_OK;
}
void tk_observe(TKState *s,int32_t delta,uint32_t now,bool allowed,bool synthetic){
 if(synthetic){tk_cancel(s,now);return;}tk_poll(s,now,allowed);if(!s||s->state!=TK_ACTIVE||!delta)return;
 int64_t d=delta;uint64_t magnitude=d<0?(uint64_t)-d:(uint64_t)d;
 if((d>0&&s->net>INT64_MAX-d)||(d<0&&s->net<INT64_MIN-d)||UINT64_MAX-s->absolute<magnitude){s->state=TK_OVERFLOW;return;}
 s->net+=d;s->absolute+=magnitude;if(s->samples<UINT32_MAX)s->samples++;
}
/* Divide a full-width sum by ten with 32 bounded low-word steps. Keep the
 * freestanding ARM image independent of an unprovided 64-bit divide ABI. */
static uint64_t tenth(uint64_t n){
 uint32_t high=(uint32_t)(n>>32),low=(uint32_t)n,quotient=0,remainder=high%10;
 for(unsigned i=32;i>0;i--){remainder=(remainder<<1)|((low>>(i-1))&1u);quotient<<=1;if(remainder>=10){remainder-=10;quotient|=1;}}
 return ((uint64_t)(high/10)<<32)|quotient;
}
bool tk_estimate(const TKState *s,uint64_t *out){
 if(!s||!out||s->state!=TK_FINISHED||!s->samples)return false;uint64_t net=s->net<0?0u-(uint64_t)s->net:(uint64_t)s->net;
 if(!net||s->absolute<net||net<s->absolute-tenth(s->absolute))return false;*out=net;return true;
}
