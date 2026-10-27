#ifndef TURBO_MUSIC_CLOCK_H
#define TURBO_MUSIC_CLOCK_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

// Glasses drop the view after 30 s without any accepted packet
// (music.c:51 sets last_contact; music.c:56 tm_expired).
#define TM_CLOCK_KEEPALIVE_S 20.0
#define TM_CLOCK_DRIFT_MS 2000.0
typedef struct{bool playing;uint32_t position_ms,duration_ms;double at;} TMClockSample;
static inline bool TMClockDue(double last,double now){return now-last>=TM_CLOCK_KEEPALIVE_S;}
static inline bool TMClockDrifted(TMClockSample a,TMClockSample b){
 if(a.playing!=b.playing)return true;
 if(fabs((double)a.duration_ms-(double)b.duration_ms)>1000.0)return true;
 double expect=(double)a.position_ms+(a.playing?(b.at-a.at)*1000.0:0.0);
 if(a.duration_ms&&expect>(double)a.duration_ms)expect=(double)a.duration_ms;
 return fabs((double)b.position_ms-expect)>TM_CLOCK_DRIFT_MS;
}
#endif
