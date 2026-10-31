/* TMG8 knob: one page/music step per 300 raw counts, wrap at both ends, lockouts 200 ms (pages) and 500 ms (music). The menu runs against the faithful stock model (TMG9). */
#include "../src/common-v1/wheel_input.h"
#include "../src/music-runtime-v1/music_input.h"
#include "../src/common-v1/menu_wheel.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* The stock main-menu carousel, transcribed from nuttx_ap.bin (see tmg9_wheel_hook_test.c for the full model):
 *   0x58e90c step: position += delta/600 (x0.8 after a one-item move), rubber band past the ends, round at .5, snap on change;
 *   0x4da820 native_snap -> 0x58e34c setIndex(app[0x88]): the carousel is re-seated from the SELECTED INDEX, not from the scroll position.
 * The hook's wrap therefore has to write the selected index (app[0x88]) before the snap, as remote_native.c does. The previous fake
 * set the index itself, which hid that. sel = app[0x88], idx = ctrl.idx, view = FMView.selected. */
typedef struct {int sel,idx,view,count;float pos;int gain_state;int changes;} Stock;
static float rb_model(float x){return 4.4f*x/(8.f+0.55f*x);}
static void stock_seat(Stock *s){s->idx=s->sel<0?0:s->sel>s->count-1?s->count-1:s->sel;s->pos=(float)s->idx;s->gain_state=0;s->view=s->sel;}   /* native_snap */
static void stock_wheel_model(Stock *s,int delta){
 if((uint32_t)delta+1u<=2u)return;
 float gain=s->gain_state==1?0.8f:1.f,p=s->pos+(float)delta*(1.f/600.f)*gain,top=(float)(s->count-1),q;
 if(p<0)q=-rb_model(-p);else if(p>top)q=rb_model(p-top)+top;else q=p;
 float c=q<0?0.f:q>top?top:q;int ni=(int)(c+0.5f);
 if(ni!=s->idx){int diff=abs(ni-s->idx);s->gain_state=s->gain_state?2:(diff==1?1:2);s->idx=ni;p=(float)ni;s->sel=ni;s->view=ni;s->changes++;}
 s->pos=p;
}
static Stock stock_at(int index,int count){Stock s={.sel=index,.count=count};stock_seat(&s);return s;}
static void menu_event(Stock *s,TIOMenuWrap *w,int delta,uint32_t now){
 int target=tio_menu_wheel_wrap(w,s->sel,s->count,delta,now);
 if(target>=0){s->sel=target;stock_seat(s);s->changes++;return;}   /* m8_hook_wheel: app[0x88]=target, native_snap */
 stock_wheel_model(s,tio_menu_wheel_scaled(delta));
}
static void in_step(const Stock *s){assert(s->sel==s->idx&&s->view==s->sel&&s->sel>=0&&s->sel<s->count);}

int main(void){
 /* One number everywhere. */
 assert(TIO_WHEEL_DETENT_RAW==300&&TK_DETENT_RAW==300u&&TIO_WHEEL_LOCK_PAGE_MS==200u&&TIO_WHEEL_LOCK_MUSIC_MS==500u);
 assert(TK_DETENT_LEGACY==600u);

 /* Pages: a step needs 300 counts, not 600. */
 WRInput w={0};
 assert(!wr_input_wheel(&w,100,1000)&&!wr_input_wheel(&w,100,1010)&&wr_input_wheel(&w,100,1020)==1);
 w=(WRInput){0};assert(wr_input_wheel(&w,300,1000)==1);
 w=(WRInput){0};assert(wr_input_wheel(&w,-300,1000)==-1);
 w=(WRInput){0};assert(wr_input_wheel(&w,INT_MAX,1000)==1);assert(!wr_input_wheel(&w,INT_MIN,1100));
 /* Page lockout 200 ms: a second detent at +199 ms is dropped, at +200 ms it counts. */
 w=(WRInput){0};assert(wr_input_wheel(&w,300,1000)==1);
 assert(!wr_input_wheel(&w,300,1199));assert(wr_input_wheel(&w,300,1450)==1);
 w=(WRInput){0};assert(wr_input_wheel(&w,300,1000)==1);assert(!wr_input_wheel(&w,300,1100));assert(wr_input_wheel(&w,300,1500)==1);
 /* A press locks the wheel for 200 ms, not 300. */
 w=(WRInput){0};assert(wr_input_press(&w,5000));assert(!wr_input_wheel(&w,300,5199));assert(wr_input_wheel(&w,300,5450)==1);
 w=(WRInput){0};assert(wr_input_press(&w,5000));assert(wr_input_wheel(&w,300,5201)==1);

 /* Music: 300 counts per skip, 500 ms lockout (was 900). */
 TMInput m={0};
 assert(!tm_input_wheel(&m,150,1000)&&tm_input_wheel(&m,150,1010)==1);
 assert(!tm_input_wheel(&m,300,1499));
 m=(TMInput){0};assert(tm_input_wheel(&m,300,1000)==1);assert(!tm_input_wheel(&m,300,1499));assert(tm_input_wheel(&m,300,1750)==1);
 m=(TMInput){0};assert(tm_input_wheel(&m,-300,1000)==-1);assert(!tm_input_wheel(&m,-300,1100));assert(tm_input_wheel(&m,-300,1600)==-1);
 m=(TMInput){0};assert(tm_input_wheel(&m,300,1000)==1);assert(tm_input_wheel(&m,300,1501)==1);

 /* Menu: the stock carousel sees 2x. */
 assert(tio_menu_wheel_scaled(300)==600&&tio_menu_wheel_scaled(-300)==-600&&tio_menu_wheel_scaled(INT_MAX)==INT_MAX&&tio_menu_wheel_scaled(INT_MIN)==INT_MIN&&tio_menu_wheel_scaled(0)==0);
 /* The stock step at the 2x scale: the first item moves at 150 raw counts (half an item, rounded), the next at about 190 (x0.8 gain after a one-item move). */
 for(int count=8;count<=13;count++){
  Stock s=stock_at(2,count);TIOMenuWrap wr={0};
  menu_event(&s,&wr,149,1000);assert(s.sel==2);menu_event(&s,&wr,1,1010);assert(s.sel==3);in_step(&s);
  Stock t=stock_at(2,count);wr=(TIOMenuWrap){0};
  menu_event(&t,&wr,300,1000);assert(t.sel>=3&&t.sel<=4);in_step(&t);menu_event(&t,&wr,-300,1300);in_step(&t);
 }
 /* Steady 50-count events: 3 or 4 events (150..200 counts) per item. */
 {Stock s=stock_at(0,13);TIOMenuWrap wr={0};uint32_t now=1000;int last=0,gap=0,gaps=0;
  for(int total=0;total<2000;total+=50){menu_event(&s,&wr,50,now);now+=5;gap++;in_step(&s);if(s.sel!=last){assert(s.sel==last+1);if(last>0){assert(gap>=3&&gap<=4);gaps++;}last=s.sel;gap=0;}}
  assert(gaps>=8&&s.sel>=9);}
 /* 13 items in about two turns at 2000 counts per turn: 50-count events every 5 ms from the first item reach the last item and wrap. */
 {Stock s=stock_at(0,13);TIOMenuWrap wr={0};uint32_t now=1000;int reached=0,wrapped=0;
  for(int total=0;total<4000;total+=50){menu_event(&s,&wr,50,now);now+=5;in_step(&s);if(s.sel==12)reached=1;if(reached&&s.sel==0)wrapped=1;}
  assert(reached&&wrapped);
 }
 /* Wrap both ends, every count 8..13. */
 for(int count=8;count<=13;count++){
  TIOMenuWrap wr={0};
  assert(tio_menu_wheel_wrap(&wr,count-1,count,150,1000)==-1);
  assert(tio_menu_wheel_wrap(&wr,count-1,count,150,1010)==0);          /* last -> first */
  wr=(TIOMenuWrap){0};
  assert(tio_menu_wheel_wrap(&wr,0,count,-150,2000)==-1);
  assert(tio_menu_wheel_wrap(&wr,0,count,-150,2010)==count-1);         /* first -> last */
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,count-1,count,300,3000)==0);
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,0,count,-300,3000)==count-1);
  /* Not at an end: never wraps, however hard the turn. */
  wr=(TIOMenuWrap){0};for(int i=1;i<count-1;i++)assert(tio_menu_wheel_wrap(&wr,i,count,INT_MAX,4000+i)==-1&&tio_menu_wheel_wrap(&wr,i,count,INT_MIN,4100+i)==-1);
  /* Pushing the wrong way at an end does not wrap: first item turned forward, last item turned back. */
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,0,count,300,5000)==-1);
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,count-1,count,-300,5000)==-1);
 }
 /* Counts build only inside a gesture: a pause, a reversal and jitter all reset. */
 {TIOMenuWrap wr={0};
  assert(tio_menu_wheel_wrap(&wr,12,13,200,1000)==-1);assert(tio_menu_wheel_wrap(&wr,12,13,200,1400)==-1);   /* >250 ms apart */
  assert(tio_menu_wheel_wrap(&wr,12,13,-200,1410)==-1);assert(tio_menu_wheel_wrap(&wr,12,13,200,1420)==-1);  /* reversal */
  assert(tio_menu_wheel_wrap(&wr,12,13,5,1430)==-1);assert(tio_menu_wheel_wrap(&wr,12,13,-8,1431)==-1);assert(tio_menu_wheel_wrap(&wr,12,13,0,1432)==-1);
  assert(tio_menu_wheel_wrap(&wr,12,13,100,1440)==0);                                                         /* 200 + 100 */
  assert(tio_menu_wheel_wrap(NULL,12,13,300,1)==-1&&tio_menu_wheel_wrap(&wr,0,1,300,1)==-1&&tio_menu_wheel_wrap(&wr,0,0,300,1)==-1);
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,12,13,INT_MAX,UINT_MAX-5)==0);                           /* saturates, tick wraps */
  wr=(TIOMenuWrap){0};assert(tio_menu_wheel_wrap(&wr,0,13,INT_MIN,10)==12);
 }
 /* Reverse: 4000 counts backwards from the first item reaches the first item's far end (the last) by wrapping. */
 {Stock s=stock_at(0,13);TIOMenuWrap wr={0};uint32_t now=1000;int wrapped=0;
  for(int total=0;total<4000;total+=50){menu_event(&s,&wr,-50,now);now+=5;in_step(&s);if(s.sel==12)wrapped=1;}
  assert(wrapped);
 }
 /* A wrap leaves the carousel seated on the target: the very next stock step starts from there, never from the old end. */
 for(int count=8;count<=13;count++){
  Stock s=stock_at(count-1,count);TIOMenuWrap wr={0};menu_event(&s,&wr,300,1000);assert(s.sel==0&&s.idx==0&&s.view==0);in_step(&s);
  menu_event(&s,&wr,200,1010);assert(s.sel==1);in_step(&s);
  s=stock_at(0,count);wr=(TIOMenuWrap){0};menu_event(&s,&wr,-300,1000);assert(s.sel==count-1&&s.idx==count-1&&s.view==count-1);in_step(&s);
  menu_event(&s,&wr,-200,1010);assert(s.sel==count-2);in_step(&s);
 }
 puts("PASS tmg8 wheel: 300-count page/music detent, 200/500 ms lockouts, 2x menu delta against the faithful stock model, wrap both ends, 13 items in two turns");
 return 0;
}
