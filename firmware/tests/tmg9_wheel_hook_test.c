/* TMG9 bug 1: the REAL m8_hook_wheel body (sliced from menu10.c by tmg9_wheel_host_test.py into wheel_hook.inc) against a
 * stock model transcribed from nuttx_ap.bin, and the REAL FMView for the view side.
 *   0x4da6ae stock wheel -> 0x4da65c -> 0x58e90c step: position += delta/600, rubber band, round at .5, snap on change
 *   0x4da820 native_snap: re-seats the carousel from app[0x88] (0x58e34c setIndex, which clamps and zeroes the motion flags)
 *            unless nothing moved and the shown frame (app[0x90]) already is the one for app[0x88]
 *   0x4da148 frame hook / 0x4da42c label_frame hook: models of menu10.c m8_hook_frame / m8_hook_label_frame (they keep their
 *            state writes, 0x90 and 0x8c) that end in fm_sync: the FMView selects app[0x88] (focus_menu_native.c fm_sync).
 * Stock native_snap overwrites whatever the hook put in the scroll position with app[0x88], so a hook that only moves the
 * scroll position (TMG8) leaves the focus where it was: this test fails for that body (the driver proves it). */
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
static uint8_t A[0x200];static int COUNT;static uint32_t NOW;static TIOMenuWrap WRAP;static int DIRFLAG;static bool ELIGIBLE;static int SNAPS;
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
int fm_wheel_wrap(void *app,int index,int count,int delta,uint32_t now){(void)app;return tio_menu_wheel_wrap(&WRAP,index,count,delta,now);}
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
 ROWS=rows;memset(A,0,sizeof A);COUNT=count;DIRFLAG=dir;ELIGIBLE=true;SNAPS=0;
 CI(0)=count;CB(8)=1;CB(9)=1;*word(A,0x88)=(uint32_t)start;set_index(start);*word(A,0x90)=(uint32_t)tio_frame_start(start);*word(A,0x8c)=(uint32_t)start;
 WRAP=(TIOMenuWrap){0};NOW=1000;assert(fm_view_update(&VIEW,start,0,0,NOW));
}
static void turn(int raw){wheel_hook(A,raw);NOW+=5;}
static void settled(int target){   /* the three places the focus lives all agree */
 CHECK((int)*word(A,0x88)==target);CHECK(CI(4)==target);CHECK(VIEW.selected==target);
 CHECK((int)*word(A,0x8c)==target);CHECK((int)*word(A,0x90)==tio_frame_start(target));
}
int main(void){
 /* 1. Wrap at both ends, both signs of the raw count, carousel and 2 / 3 rows, 8..13 items (setting 0x24 == 1: raw + is forward). */
 for(unsigned rows=1;rows<=3;rows++)for(int count=8;count<=13;count++){
  for(int sign=-1;sign<=1;sign+=2){
   int start=sign<0?0:count-1,target=sign<0?count-1:0;
   snprintf(CASE,sizeof CASE,"rows=%u count=%d sign=%d",rows,count,sign);
   reset(rows,count,start,1);
   int events=0;while(events<30&&(int)*word(A,0x88)==start){turn(sign*50);events++;}
   CHECK(events==6);   /* 300 counts built against the end, in 50-count events 5 ms apart */
   settled(target);
   /* The gesture goes on: the carousel carries on from the wrapped item like any other step, and the three places stay in step. */
   for(int more=0;more<12;more++){turn(sign*50);int at=(int)*word(A,0x88);CHECK(at>=0&&at<count&&CI(4)==at&&VIEW.selected==at);}
   {int k=((int)*word(A,0x88)-target)*sign;CHECK(k>=2&&k<=4);}   /* 600 more counts: the stock step takes 150-190 raw counts per item, so it walks on from the wrap point */
   /* Ping-pong: turned back the other way a fresh 300 counts against the new end wraps again, to where it started. */
   reset(rows,count,start,1);for(int i=0;i<6;i++)turn(sign*50);settled(target);NOW+=400;
   for(int i=0;i<6;i++)turn(-sign*50);
   settled(start);
  }
 }
 /* 2. Not at an end: one turn, however hard, never wraps. It goes to the stock rule (and stops at the end); the hook does not snap. */
 for(unsigned rows=1;rows<=3;rows++)for(int count=8;count<=13;count++)for(int start=1;start<count-1;start++)for(int sign=-1;sign<=1;sign+=2){
  snprintf(CASE,sizeof CASE,"mid rows=%u count=%d start=%d sign=%d",rows,count,start,sign);
  reset(rows,count,start,1);turn(sign*100);
  CHECK(SNAPS==0);CHECK(abs((int)*word(A,0x88)-start)<=1&&CI(4)==(int)*word(A,0x88)&&VIEW.selected==(int)*word(A,0x88));
  reset(rows,count,start,1);turn(sign==1?INT_MAX:INT_MIN);
  CHECK(SNAPS==0);CHECK((int)*word(A,0x88)==(sign>0?count-1:0));CHECK(CI(4)==(int)*word(A,0x88)&&VIEW.selected==(int)*word(A,0x88));
 }
 /* 3. Not eligible (stock state not safe to re-seat): the hook never writes the index or snaps, the stock path runs. */
 for(int sign=-1;sign<=1;sign+=2){
  snprintf(CASE,sizeof CASE,"not eligible sign=%d",sign);
  reset(2,13,sign<0?0:12,1);ELIGIBLE=false;
  for(int i=0;i<8;i++)turn(sign*50);
  CHECK(SNAPS==0);CHECK((int)*word(A,0x88)==(sign<0?0:12));
 }
 /* 4. A full 4000 count sweep each way from the first item changes the focus 13 times (twelve steps and a wrap) at 300 counts: 13 items in two turns. */
 for(int sign=-1;sign<=1;sign+=2){
  snprintf(CASE,sizeof CASE,"sweep sign=%d",sign);
  reset(2,13,0,1);int last=0,changes=0;
  for(int total=0;total<4000;total+=50){turn(sign*50);int at=(int)*word(A,0x88);if(at!=last){changes++;last=at;}CHECK((int)*word(A,0x88)==CI(4)&&VIEW.selected==at);}
  CHECK(changes>=12&&CI(4)==(int)*word(A,0x88)&&VIEW.selected==(int)*word(A,0x88));
 }
 /* 5. Slide direction of the page change on a wrap (grid): last -> first slides forward, first -> last backward, plain steps by order. */
 for(unsigned rows=2;rows<=3;rows++){
  unsigned per=rows*3;
  snprintf(CASE,sizeof CASE,"slide rows=%u",rows);
  reset(rows,13,12,1);NOW=5000;CHECK(fm_view_update(&VIEW,0,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);   /* wrap forward */
  reset(rows,13,0,1);NOW=5000;CHECK(fm_view_update(&VIEW,12,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);  /* wrap backward */
  reset(rows,13,(int)per-1,1);NOW=5000;CHECK(fm_view_update(&VIEW,(int)per,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==10);
  reset(rows,13,(int)per,1);NOW=5000;CHECK(fm_view_update(&VIEW,(int)per-1,0,0,NOW));CHECK(VIEW.page_motion&&VIEW.page_offset==-10);
  reset(rows,13,0,1);NOW=5000;CHECK(fm_view_update(&VIEW,1,0,0,NOW));CHECK(!VIEW.page_motion&&VIEW.page_offset==0);   /* same page: no slide */
 }
 /* 7. Glasses setting 0x24 != 1 (stock reverses the delta). The hook's wrap follows the raw sign like every page input, so raw + at the last item
  * wraps (in a slow 50-count gesture the reversed stock carousel leaves the end first: the open item below); the three focus places must stay in step whichever way the stock carousel was told to go. Whether raw + is "forward" on the
  * hardware is the device check (README, TMG9 checklist: log one turn's sign). */
 for(unsigned rows=1;rows<=3;rows++)for(int count=8;count<=13;count++){
  snprintf(CASE,sizeof CASE,"dir=0 rows=%u count=%d",rows,count);
  reset(rows,count,count-1,0);turn(300);settled(0);   /* one burst of a full detent: the stock reversal has no time to move the focus off the end first */
  reset(rows,count,3,0);for(int i=0;i<60;i++){turn(i<30?50:-50);CHECK((int)*word(A,0x88)==CI(4)&&VIEW.selected==(int)*word(A,0x88));}
 }
 if(FAILS){fprintf(stderr,"%d check(s) failed\n",FAILS);return 1;}
 puts("PASS tmg9 wheel hook: wrap writes app[0x88] and snaps, ctrl.idx/view.selected/label/frame agree for carousel and 2/3 rows, 8..13 items, both signs; grid slide follows the turn");
 return 0;
}
