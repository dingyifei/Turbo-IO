/* TMG8 knob: one item per 300 raw counts, wrap at both ends, lockouts 200 ms (pages) and 500 ms (music). */
#include "../src/common-v1/wheel_input.h"
#include "../src/music-runtime-v1/music_input.h"
#include "../src/common-v1/menu_wheel.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>

/* A model of the stock carousel: 600 raw units per item, clamped at both ends. */
typedef struct {int index,count;int32_t acc;int changes;} Stock;
static void stock_wheel_model(Stock *s,int delta){
 s->acc+=delta;
 while(s->acc>=600){s->acc-=600;if(s->index<s->count-1){s->index++;s->changes++;}else s->acc=0;}
 while(s->acc<=-600){s->acc+=600;if(s->index>0){s->index--;s->changes++;}else s->acc=0;}
}
static void menu_event(Stock *s,TIOMenuWrap *w,int delta,uint32_t now){
 int target=tio_menu_wheel_wrap(w,s->index,s->count,delta,now);
 if(target>=0){s->index=target;s->acc=0;s->changes++;return;}
 stock_wheel_model(s,tio_menu_wheel_scaled(delta));
}

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
 /* One item per 300 counts. */
 for(int count=8;count<=13;count++){
  Stock s={.index=2,.count=count};TIOMenuWrap wr={0};
  menu_event(&s,&wr,299,1000);assert(s.index==2);menu_event(&s,&wr,299,1010);assert(s.index==3);
  Stock t={.index=2,.count=count};wr=(TIOMenuWrap){0};
  menu_event(&t,&wr,300,1000);assert(t.index==3);menu_event(&t,&wr,300,1300);assert(t.index==4);menu_event(&t,&wr,-300,1600);assert(t.index==3);
 }
 /* 13 items in about 2 turns at 2000 counts per turn: 50-count events every 5 ms. */
 {Stock s={.index=0,.count=13};TIOMenuWrap wr={0};uint32_t now=1000;
  for(int total=0;total<4000;total+=50){menu_event(&s,&wr,50,now);now+=5;}
  assert(s.changes==13&&s.index==0); /* 12 steps, the wrap, then 0.3 of the next */
 }
 {Stock s={.index=0,.count=13};TIOMenuWrap wr={0};uint32_t now=1000;
  for(int total=0;total<3000;total+=50){menu_event(&s,&wr,50,now);now+=5;}
  assert(s.changes==10&&s.index==10);
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
 /* Reverse: 4000 counts backwards from the first item wraps to the last on the way. */
 {Stock s={.index=0,.count=13};TIOMenuWrap wr={0};uint32_t now=1000;
  for(int total=0;total<4000;total+=50){menu_event(&s,&wr,-50,now);now+=5;}
  assert(s.changes==13&&s.index==0);
 }
 puts("PASS tmg8 wheel: 300-count detent, 200/500 ms lockouts, 2x menu delta, wrap both ends, 13 items in two turns");
 return 0;
}
