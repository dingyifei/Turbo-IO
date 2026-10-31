/* TMG9 knob: the REAL m8_hook_wheel body (sliced from menu10.c by tmg9_wheel_host_test.py into wheel_hook.inc) and the REAL tio_menu_wheel_step
 * (menu_wheel.h) against a stock model transcribed from nuttx_ap.bin, and the REAL FMView for the view side.
 *   0x4da6ae stock wheel -> 0x4da65c -> 0x58e90c step: position += delta/600, rubber band, round at .5, snap on change
 *   0x4da820 native_snap: re-seats the carousel from app[0x88] (0x58e34c setIndex, which clamps and zeroes the motion flags)
 *            unless nothing moved and the shown frame (app[0x90]) already is the one for app[0x88]
 *   0x4da148 frame hook / 0x4da42c label_frame hook: models of menu10.c m8_hook_frame / m8_hook_label_frame (they keep their
 *            state writes, 0x90 and 0x8c) that end in fm_sync: the FMView selects app[0x88] (focus_menu_native.c fm_sync).
 * The hook owns the stepping: one item per live D raw counts through app[0x88] + app[0x90] + native_snap, a step past either end is the wrap,
 * and the stock wheel (its 600-count rounding) never receives a delta while the menu has a controller. A hook that only moves the scroll
 * position (TMG8) or that still feeds stock a scaled delta fails this test: the driver proves it for both. */
#include "common-v1/menu_wheel.h"
#include "music-runtime-v1/menu_tiles.h"
#include "focus-v1/focus_menu.h"
#include "common-v1/tio_text.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int FAILS;
#define CHECK(c) do{if(!(c)){FAILS++;if(FAILS<=12)fprintf(stderr,"FAIL line %d: %s (%s)\n",__LINE__,#c,CASE);}}while(0)
static char CASE[160];
/* ---- the view side: a real FMView over a no-op renderer that rejects unaligned canvas buffers ---- */
static bool f_idle(void *c){(void)c;return true;}
static void *f_create(void *c,void *p){(void)p;static uintptr_t n;(void)c;return (void *)++n;}
static void *f_label(void *c,void *p,unsigned font){(void)font;return f_create(c,p);}
static void f_place(void *c,void *o,int x,int y,int w,int h){(void)c;(void)o;(void)x;(void)y;(void)w;(void)h;}
static void f_buffer(void *c,void *o,const uint8_t *p,unsigned w,unsigned h){(void)c;(void)o;(void)w;(void)h;assert(p&&((uintptr_t)p&63)==0);}
static void f_text(void *c,void *o,const char *s){(void)c;(void)o;(void)s;}
static void f_visible(void *c,void *o,bool v){(void)c;(void)o;(void)v;}
static void f_destroy(void *c,void *o){(void)c;(void)o;}
static bool f_attach(void *o,void *w){return o&&w;}
unsigned tio_lang(void){return 0;}
static FMView VIEW;static unsigned ROWS;
/* ---- the stock model ---- */
static uint8_t A[0x200];static int COUNT;static uint32_t NOW;static TIOMenuStep STEP;static unsigned DET=400;static bool NOCTRL;static int STOCK_CALLS,STOCK_LAST;static int DIRFLAG;static bool ELIGIBLE;static int SNAPS;
static uint32_t *word(void *app,unsigned off){return (uint32_t *)((uint8_t *)app+off);}
#define CB(o) (A[0xa0+(o)])
#define CI(o) (*(int32_t *)(A+0xa0+(o)))
#define CF(o) (*(float *)(A+0xa0+(o)))
typedef struct {void *page;} Tail;static Tail T;static Tail *tail(void *a){(void)a;return &T;}
static void *slot(void *a){(void)a;return NULL;}static void *focus(void *a){(void)a;return NULL;}static void *music(void *a){(void)a;return NULL;}
static void tgr_knob_observe(void *a,int d,uint32_t n){(void)a;(void)d;(void)n;}
static bool tc_native_visible(void *a){(void)a;return false;}static void tc_native_wheel(void *a,int d){(void)a;(void)d;}
static bool tap_service_visible(void *a){(void)a;return false;}static void tap_service_wheel(void *a,int d){(void)a;(void)d;}
static bool tf_slot_visible(void *a){(void)a;return false;}static void tf_slot_wheel(void *a,int d){(void)a;(void)d;}
static bool tm_slot_visible(void *a){(void)a;return false;}static void tm_slot_wheel(void *a,int d){(void)a;(void)d;}
static bool tn_slot_visible(void *a){(void)a;return false;}
static bool eligible(void *a){(void)a;return ELIGIBLE;}
static unsigned fm_tile_count(void){return (unsigned)COUNT;}
static uint32_t stream_tick(void){return NOW;}
unsigned tio_knob_detent(void){return DET;}
int fm_wheel_step(void *app,int index,int count,int delta,uint32_t now){(void)app;return NOCTRL?FM_STEP_NO_CONTROL:tio_menu_wheel_step(&STEP,index,count,delta,now,tio_knob_detent());}
void fm_sync(void *app){int i=(int)*word(app,0x88);if(i>=0&&i<COUNT)(void)fm_view_update(&VIEW,i,0,0,NOW);}
static bool m8_hook_frame(void *app,int frame){if(frame<0||frame>30*COUNT-1)return false;if((int)*word(app,0x90)==frame)return false;*word(app,0x90)=(uint32_t)frame;fm_sync(app);return true;}
static void m8_hook_label_frame(void *app,int frame){frame=tio_clampi(frame,0,30*COUNT-1);*word(app,0x8c)=(uint32_t)tio_frame_index(frame);fm_sync(app);}
static void m8_hook_label_index(void *app,int index){m8_hook_label_frame(app,tio_frame_start(index));}
static float rb(float x){return 4.4f*x/(8.f+0.55f*x);}                                                       /* 0x58e43c */
static void set_index(int idx){float f=(float)idx;int n=CI(0);int v=f<0?0:(f>(float)(n-1)?n-1:idx);CI(4)=v;CB(0xb)=0;CF(0x10)=CF(0x14)=CF(0x18)=(float)v;CB(0xc)=0;CB(0xd)=0;}   /* 0x58e34c */
static void native_snap(void *app){                                                                          /* 0x4da820 */
 SNAPS++;
 if(!CB(0xb)&&!CB(0xc)&&*word(app,0x90)==(uint32_t)tio_frame_start((int)*word(app,0x88)))return;
 set_index((int)*word(app,0x88));(void)m8_hook_frame(app,tio_frame_start((int)*word(app,0x88)));m8_hook_label_frame(app,(int)*word(app,0x90));
}
static void stock_wheel(void *app,int delta){                                                                /* 0x4da6ae -> 0x4da65c -> 0x58e90c */
 STOCK_CALLS++;STOCK_LAST=delta;
 CB(0xa)=(uint8_t)DIRFLAG;if((uint32_t)delta+1u<=2u)return;
 int d=CB(0xa)?delta:-delta;float gain=CB(0xd)==1?0.8f:1.f;float s10=CF(0x14)+(float)d*(1.f/600.f)*gain,s12=(float)(CI(0)-1),s11;
 if(s10<0)s11=-rb(-s10);else if(s10>s12)s11=rb(s10-s12)+s12;else s11=s10;                                    /* ctrl[8]=ctrl[9]=1: rubber band */
 float s15=s11<0?0.f:(s11>s12?s12:s11);int ni=(int)(s15+0.5f);
 if(ni!=CI(4)){int diff=abs(ni-CI(4));CB(0xd)=CB(0xd)?2:(diff==1?1:2);CI(4)=ni;s10=(float)ni;*word(app,0x88)=(uint32_t)ni;fm_sync(app);}   /* snap on change: the frame hooks end in fm_sync */
 CF(0x14)=s10;CB(0xb)=1;CB(0xc)=1;
}
#include "wheel_hook.inc"
static void reset(unsigned rows,int count,int start,int dir){
 TTConfig config;TTVisible tiles;assert(tt_unrank(0,((1u<<(13-count))-1u)<<7,&config)&&tt_compact(&config,&tiles)&&(int)tiles.count==count);
 memset(&VIEW,0,sizeof VIEW);
 TNWidgets api={NULL,f_idle,f_create,f_create,f_label,f_place,f_buffer,f_text,f_visible,f_destroy,NULL,NULL};
 assert(fm_view_open(&VIEW,&api,NULL,f_attach,&VIEW));assert(fm_view_tiles(&VIEW,&tiles)&&fm_view_rows(&VIEW,rows));
 ROWS=rows;memset(A,0,sizeof A);COUNT=count;DIRFLAG=dir;ELIGIBLE=true;SNAPS=0;NOCTRL=false;STOCK_CALLS=0;STOCK_LAST=0;
 CI(0)=count;CB(8)=1;CB(9)=1;*word(A,0x88)=(uint32_t)start;set_index(start);*word(A,0x90)=(uint32_t)tio_frame_start(start);*word(A,0x8c)=(uint32_t)start;
 STEP=(TIOMenuStep){0};NOW=1000;assert(fm_view_update(&VIEW,start,0,0,NOW));
}
static void turn(int raw){wheel_hook(A,raw);NOW+=5;}
static void settled(int target){   /* the three places the focus lives all agree */
 CHECK((int)*word(A,0x88)==target);CHECK(CI(4)==target);CHECK(VIEW.selected==target);
 CHECK((int)*word(A,0x8c)==target);CHECK((int)*word(A,0x90)==tio_frame_start(target));
}
static bool loop_ok(const int *seen,int start){for(int i=0;i<13;i++)if(seen[i]!=(i==start?2:1))return false;return true;}
static int mod(long v,int n){v%=n;return (int)(v<0?v+n:v);}
/* Where the focus must be after `counts` raw counts of one gesture (never paused 250 ms) at detent D: one item per D, the sign is the direction. */
static int expect(int start,int sign,long counts,int count,unsigned d){return mod(start+sign*(long)(counts/(long)d),count);}
static void in_step(void){CHECK((int)*word(A,0x88)==CI(4)&&VIEW.selected==(int)*word(A,0x88)&&(int)*word(A,0x88)>=0&&(int)*word(A,0x88)<COUNT);}
int main(void){
 const unsigned details[]={300,350,400,450,500,550,600};
 /* 1. One item per D, however the counts are cut: after every event the focus is exactly start + floor(counts so far / D) items, modulo the item
  * count (the step past the last item is the wrap). Carousel and 2 / 3 rows, 8..13 items, both signs, D = 300..600, 14 D of counts (a full
  * 13-item loop and one more), and the stock wheel never receives a delta. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++)for(unsigned rows=1;rows<=3;rows++)for(int count=8;count<=13;count++)for(int sign=-1;sign<=1;sign+=2)
  for(int cut=0;cut<5;cut++){
   unsigned d=details[di];int chunk=cut==0?50:cut==1?25:cut==2?(int)d:cut==3?(int)d/2+7:(int)d+(int)d/2;   /* 50, 25, exactly D, an odd cut below D, one and a half D */
   for(int start=0;start<count;start+=count/3+1){
    snprintf(CASE,sizeof CASE,"D=%u rows=%u count=%d sign=%d chunk=%d start=%d",d,rows,count,sign,chunk,start);
    reset(rows,count,start,1);DET=d;long total=0;
    for(int e=0;e<(int)(14*d)/chunk;e++){turn(sign*chunk);total+=chunk;CHECK((int)*word(A,0x88)==expect(start,sign,total,count,d));in_step();}
    CHECK(STOCK_CALLS==0);
   }
  }
 /* 2. A 13-item loop is 13 * D counts: every item is visited once, in order, and the focus is back where it started. Both signs, every start, D = 300 / 400 / 600
  * (and the rest), 50-count events 5 ms apart. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++)for(int sign=-1;sign<=1;sign+=2)for(int start=0;start<13;start++){
  unsigned d=details[di];snprintf(CASE,sizeof CASE,"loop D=%u sign=%d start=%d",d,sign,start);
  reset(2,13,start,1);DET=d;int seen[13]={0},moves=0,last=start;seen[start]=1;long total=0;
  while(total<13L*(long)d){int chunk=(int)d-(int)total%(int)d<50?(int)d-(int)total%(int)d:50;turn(sign*chunk);total+=chunk;
   int at=(int)*word(A,0x88);if(at!=last){moves++;CHECK(mod(last+sign,13)==at);seen[at]++;last=at;}in_step();}
  CHECK(moves==13&&loop_ok(seen,start)&&last==start&&(int)*word(A,0x88)==start);CHECK(STOCK_CALLS==0&&SNAPS==13);
 }
 /* 3. Wrap at both ends: the step past the last item goes to the first, past the first to the last, and the three places the focus lives agree. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++)for(unsigned rows=1;rows<=3;rows++)for(int count=8;count<=13;count++)for(int sign=-1;sign<=1;sign+=2){
  unsigned d=details[di];int start=sign<0?0:count-1,target=sign<0?count-1:0;
  snprintf(CASE,sizeof CASE,"wrap D=%u rows=%u count=%d sign=%d",d,rows,count,sign);
  reset(rows,count,start,1);DET=d;
  int events=0;while(events<40&&(int)*word(A,0x88)==start){turn(sign*50);events++;}
  CHECK(events==(int)((d+49)/50));settled(target);CHECK(SNAPS==1&&STOCK_CALLS==0);
  /* one burst of exactly D does the same, and 2 D from the end lands one item past the wrap */
  reset(rows,count,start,1);DET=d;turn(sign*(int)d);settled(target);
  reset(rows,count,start,1);DET=d;turn(sign*2*(int)d);settled(sign<0?count-2:1);
  /* Ping-pong: back the other way after a pause, the same wrap in reverse. */
  reset(rows,count,start,1);DET=d;for(unsigned i=0;i<(d+49)/50;i++)turn(sign*50);settled(target);NOW+=400;
  for(unsigned i=0;i<(d+49)/50;i++)turn(-sign*50);settled(start);
 }
 /* 4. A gesture is a run of counts: a pause over 250 ms or a reversal drops the remainder; jitter (8 counts or fewer) neither counts nor breaks the gesture. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++){
  unsigned d=details[di];int half=(int)d-50;snprintf(CASE,sizeof CASE,"gesture D=%u",d);
  reset(2,13,5,1);DET=d;turn(half);CHECK((int)*word(A,0x88)==5);NOW+=300;turn(50);CHECK((int)*word(A,0x88)==5);                      /* idle reset */
  reset(2,13,5,1);DET=d;turn(half);turn(-8);turn(8);turn(5);turn(0);CHECK((int)*word(A,0x88)==5);turn(50);CHECK((int)*word(A,0x88)==6);   /* jitter ignored, kept */
  reset(2,13,5,1);DET=d;turn(half);turn(-60);CHECK((int)*word(A,0x88)==5);turn(60);CHECK((int)*word(A,0x88)==5);                  /* reversal reset: -60 started a fresh backward run, +60 a fresh forward one */
  reset(2,13,5,1);DET=d;turn(half);turn(-60);turn(-(int)d);CHECK((int)*word(A,0x88)==4);                                          /* the fresh backward run steps at D */
  reset(2,13,5,1);DET=d;turn((int)d+(int)d/2);CHECK((int)*word(A,0x88)==6);turn((int)d/2);CHECK((int)*word(A,0x88)==7);          /* the remainder is carried into the next event */
  reset(2,13,5,1);DET=d;turn(INT_MAX);in_step();CHECK(STOCK_CALLS==0);reset(2,13,5,1);DET=d;turn(INT_MIN);in_step();CHECK(STOCK_CALLS==0);
  CHECK((int)*word(A,0x88)>=0);
 }
 /* 5. D is read at every event: the same gesture steps at the new value after the phone changed it. */
 reset(2,13,5,1);DET=300;turn(250);DET=600;turn(250);CHECK((int)*word(A,0x88)==5);turn(100);CHECK((int)*word(A,0x88)==6);   /* 600 now: 600 counts in one gesture */
 reset(2,13,5,1);DET=600;turn(550);CHECK((int)*word(A,0x88)==5);DET=300;turn(60);CHECK((int)*word(A,0x88)==7);                  /* 610 counts at 300: two items, 10 left */
 /* 6. Not eligible (stock state not safe to re-seat): nothing happens, nothing builds up: the hook writes no index, snaps nothing, and hands stock no delta. */
 for(int sign=-1;sign<=1;sign+=2){
  snprintf(CASE,sizeof CASE,"not eligible sign=%d",sign);
  reset(2,13,sign<0?0:12,1);DET=400;ELIGIBLE=false;
  for(int i=0;i<30;i++)turn(sign*50);                                                                                           /* 1500 counts: 3.75 items if they were kept */
  CHECK(SNAPS==0&&STOCK_CALLS==0&&(int)*word(A,0x88)==(sign<0?0:12));
  ELIGIBLE=true;turn(sign*100);CHECK(SNAPS==0&&(int)*word(A,0x88)==(sign<0?0:12));                                              /* eligible() runs before the remainder builds: 1500 + 100 would be 4 items */
 }
 /* 7. No menu controller at all (allocation failed): the stock menu keeps its own rate, so the delta goes to stock UNSCALED (never 2x) and the hook steps nothing. */
 for(int sign=-1;sign<=1;sign+=2)for(int delta=100;delta<=900;delta+=400){
  snprintf(CASE,sizeof CASE,"no controller sign=%d delta=%d",sign,delta);
  reset(2,13,5,1);NOCTRL=true;turn(sign*delta);CHECK(STOCK_CALLS==1&&STOCK_LAST==sign*delta&&SNAPS==0);
 }
 /* 8. The stock direction setting (0x24, ctrl[0xa]) does not reach the menu: the raw sign decides, whatever stock would have done with it. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++)for(int dir=0;dir<=1;dir++)for(int sign=-1;sign<=1;sign+=2){
  unsigned d=details[di];snprintf(CASE,sizeof CASE,"dir=%d D=%u sign=%d",dir,d,sign);
  reset(3,13,6,dir);DET=d;turn(sign*(int)d);CHECK((int)*word(A,0x88)==6+sign&&STOCK_CALLS==0);settled(6+sign);
 }
 /* 9. Remote: one injected step is D counts in the launcher (remote_native.c inject_counts): one item every time, either direction, at every D and every position. */
 for(unsigned di=0;di<sizeof details/sizeof *details;di++)for(int sign=-1;sign<=1;sign+=2)for(int start=0;start<13;start++){
  unsigned d=details[di];snprintf(CASE,sizeof CASE,"remote D=%u sign=%d start=%d",d,sign,start);
  reset(1,13,start,1);DET=d;turn(sign*(int)d);settled(mod(start+sign,13));turn(sign*(int)d);settled(mod(start+2*sign,13));turn(-sign*(int)d);settled(mod(start+sign,13));CHECK(STOCK_CALLS==0);
 }
 /* 10. The slide direction of a page change on a wrap (grid): last -> first slides forward, first -> last backward, plain steps by order. */
 for(unsigned rows=2;rows<=3;rows++){
  unsigned per=rows*3;
  snprintf(CASE,sizeof CASE,"slide rows=%u",rows);
  reset(rows,13,12,1);NOW=5000;CHECK(fm_view_update(&VIEW,0,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);   /* wrap forward */
  reset(rows,13,0,1);NOW=5000;CHECK(fm_view_update(&VIEW,12,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);  /* wrap backward */
  reset(rows,13,(int)per-1,1);NOW=5000;CHECK(fm_view_update(&VIEW,(int)per,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);
  reset(rows,13,(int)per,1);NOW=5000;CHECK(fm_view_update(&VIEW,(int)per-1,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);
  reset(rows,13,0,1);NOW=5000;CHECK(fm_view_update(&VIEW,1,0,0,NOW));CHECK(!VIEW.page_motion&&VIEW.page_offset==0);   /* same page: no slide */
  /* One event can wrap by more than one item: the slide still goes the way the knob turned (the short way round). */
  reset(rows,13,12,1);NOW=5000;CHECK(fm_view_update(&VIEW,1,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);    /* 12 -> 1, two items forward */
  reset(rows,13,11,1);NOW=5000;CHECK(fm_view_update(&VIEW,0,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);    /* 11 -> 0, two items forward */
  reset(rows,13,0,1);NOW=5000;CHECK(fm_view_update(&VIEW,11,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);   /* 0 -> 11, two items backward */
  reset(rows,13,1,1);NOW=5000;CHECK(fm_view_update(&VIEW,12,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);   /* 1 -> 12, two items backward */
 }
 if(FAILS){fprintf(stderr,"%d check(s) failed\n",FAILS);return 1;}
 puts("PASS tmg9 wheel hook: one item per D (300..600) through app[0x88] + native_snap, 13 items in 13 D, wrap at both ends, remote step = D, ctrl.idx/view.selected/label/frame agree for carousel and 2/3 rows, the stock wheel never sees a delta");
 return 0;
}
