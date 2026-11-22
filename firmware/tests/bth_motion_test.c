// Host test for the Bluetooth-core head-motion body (bth-v1/bth_motion.c): which windows count as motion, the 30 s
// rate rule, the first message after boot, the NaN prime the rx hook writes at every "motion on" (review finding 1:
// a zero or stale previous sample made the first window count as motion), and a send that is not queued.
// The state words live in host memory here; the stock functions are stubs.
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static struct {uint64_t last_send;uint32_t enable;float prev[3];} st;
#define BTH_STATE_HOST 1
#define BTH_LAST_SEND ((uintptr_t)&st.last_send)
#define BTH_ENABLE ((uintptr_t)&st.enable)
#define BTH_PREV ((uintptr_t)st.prev)
#include "../bth-v1/bth_motion.c"

static int64_t now_us;static int clock_ret,sends,frees,allocs;static uint8_t msg[0x408];static int send_ret;
int bth_clock_gettime(int clk,struct bth_timespec *ts){assert(clk==1);ts->sec=now_us/1000000;ts->nsec=(int32_t)(now_us%1000000)*1000;return clock_ret;}
void *bth_neck_alloc(uint32_t size,uint32_t one){assert(size==0x408&&one==1);allocs++;memset(msg,0xa5,sizeof msg);return msg;}
void bth_free(void *p){assert(p==msg);frees++;}
int bth_neck_send(void *p){assert(p==msg);sends++;return send_ret;}

// The caller's frame: the window's batch at sp + 0xf0.
static uint8_t frame[0xf0+0xd8];
static void window(uint32_t count,const float first[3],const float last[3],float sigma){
 uint8_t *b=frame+0xf0;memcpy(b,&count,4);memcpy(b+0x18,first,12);memcpy(b+0x24,last,12);memcpy(b+0x60,&sigma,4);
}
static int run(void){struct bth_timespec ts;return bth_motion_body(1,&ts,frame);}
static void motion_on(void){uint32_t nan=BTH_PREV_NAN;for(int i=0;i<3;i++)memcpy(&st.prev[i],&nan,4);st.enable=1;}   // what bth_motion.S does

int main(void){
 const float g[3]={0.1f,0.2f,9.8f},tilt[3]={0.1f,0.9f,9.7f};
 assert(BTH_PREV_NAN==0x7fc00000u&&isnan(*(const float *)&(uint32_t){BTH_PREV_NAN}));
 // After boot the state is zero (stock's .bss clear). The first window after "on" with the head still: no message,
 // although the latest sample differs from the zero prev by gravity (finding 1).
 memset(&st,0,sizeof st);now_us=5000000;motion_on();window(5,g,g,0.01f);
 assert(run()==0&&sends==0&&allocs==0&&st.prev[0]==g[0]&&st.prev[2]==g[2]);
 // Still windows: nothing.
 for(int i=0;i<10;i++){now_us+=192000;window(5,g,g,0.01f);assert(run()==0);}assert(sends==0);
 // Moving inside a window, in the first 30 s of uptime: a message (none sent yet, finding 4).
 now_us+=192000;window(5,g,tilt,0.01f);assert(run()==0&&sends==1&&st.last_send==(uint64_t)now_us);
 {uint16_t ty,z;uint32_t len;uint64_t us;float sg;memcpy(&ty,msg,2);memcpy(&z,msg+2,2);memcpy(&len,msg+4,4);memcpy(&us,msg+8,8);memcpy(&sg,msg+16,4);
  assert(ty==2&&z==0&&len==12&&us==(uint64_t)now_us&&sg==0.01f);}
 // Moving again within 30 s: nothing; 30 s after the last message: the second message (stop, still, resume).
 uint64_t t1=st.last_send;now_us+=1000000;window(5,tilt,g,0.01f);assert(run()==0&&sends==1);
 now_us=(int64_t)t1+29999999;window(5,g,tilt,0.01f);run();assert(sends==1);
 for(int i=0;i<5;i++){now_us+=192000;window(5,tilt,tilt,0.01f);run();}assert(sends==1);   // still (prev = tilt)
 now_us=(int64_t)t1+30000000;window(5,tilt,g,0.01f);run();assert(sends==2&&st.last_send==t1+30000000);
 // Each trigger on its own: sigma above 0.05; drift from the previous window above 0.3 on one axis; and 0.3 exactly is not motion.
 now_us+=30000000;window(5,g,g,0.06f);run();assert(sends==3);
 now_us+=30000000;st.prev[0]=g[0];st.prev[1]=g[1];st.prev[2]=g[2]-0.31f;window(5,g,g,0.0f);run();assert(sends==4);
 now_us+=30000000;{float a[3]={1.0f,0,0},b[3]={1.25f,0,0};st.prev[0]=1.25f;st.prev[1]=0;st.prev[2]=0;window(5,a,b,0.05f);run();}assert(sends==4);
 // "on" again while on: prev primed again, so a stale prev never makes motion.
 now_us+=30000000;st.prev[0]=0;st.prev[1]=0;st.prev[2]=0;motion_on();window(5,g,g,0.0f);run();assert(sends==4);
 // A send that is not queued frees the message and keeps the last send time (retry on the next moving window).
 now_us+=30000000;send_ret=-1;uint64_t ls=st.last_send;window(5,g,tilt,0.0f);run();assert(sends==5&&frees==1&&st.last_send==ls);
 send_ret=0;now_us+=192000;window(5,tilt,g,0.0f);run();assert(sends==6&&frees==1);
 // clock_gettime failing, or an empty window: stock's result is returned and nothing else happens.
 int a0=allocs;clock_ret=-1;now_us+=60000000;window(5,g,tilt,1.0f);assert(run()==-1&&allocs==a0);clock_ret=0;
 window(0,g,tilt,1.0f);assert(run()==0&&allocs==a0);
 puts("PASS bth_motion: still windows send nothing, first window after motion on judged alone (NaN prime), first message in the first 30 s, 30 s rate, each trigger and its bar, failed send freed, clock fault and empty window pass stock's result");
 return 0;
}
