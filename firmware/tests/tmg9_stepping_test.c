/* TMG9 knob stepping: one page step, one music skip and one menu item per D raw counts, D being the live detent (300..600 in steps of 50, 400 by
 * default) read from the single accessor tio_knob_detent() (knob_detent.h). The lockouts stay time based (200 ms pages, 500 ms music) and do not
 * depend on D. The menu half is tio_menu_wheel_step (menu_wheel.h) on its own; tmg9_wheel_hook_test.c runs the real m8_hook_wheel against the
 * faithful stock model, and native_remote_test.c the remote's injected step and the stored-D read. */
#include "../src/common-v1/wheel_input.h"
#include "../src/music-runtime-v1/music_input.h"
#include "../src/common-v1/menu_wheel.h"
#include "../src/menu-grid-v2/menu_config.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned DET=400;
unsigned tio_knob_detent(void){return DET;}   /* the host stand-in for the live D */
static const unsigned DS[]={300,350,400,450,500,550,600};
static int mod(long v,int n){v%=n;return (int)(v<0?v+n:v);}
/* Feed `total` counts in events of `chunk`, 5 ms apart from `now`; follows the steps in *index and returns how many there were. */
static int menu_run(TIOMenuStep *s,int *index,int count,int sign,long total,int chunk,uint32_t *now,unsigned d){
 int moves=0;for(long fed=0;fed<total;fed+=chunk){int t=tio_menu_wheel_step(s,*index,count,sign*chunk,*now,d);*now+=5;if(t>=0){assert(t<count&&t!=*index);*index=t;moves++;}}return moves;
}

int main(void){
 /* One set of numbers everywhere: the menu and page constants, the phone-shared TK_* copies, the wire and storage TML_* copies. */
 assert(TIO_WHEEL_DETENT_MIN==300&&TIO_WHEEL_DETENT_MAX==600&&TIO_WHEEL_DETENT_STEP==50&&TIO_WHEEL_DETENT_DEFAULT==400);
 assert(TK_DETENT_MIN==300u&&TK_DETENT_MAX==600u&&TK_DETENT_STEP==50u&&TK_DETENT_DEFAULT==400u&&TK_DETENT_RAW==300u&&TK_DETENT_LEGACY==600u);
 assert(TML_DETENT_MIN==TIO_WHEEL_DETENT_MIN&&TML_DETENT_MAX==TIO_WHEEL_DETENT_MAX&&TML_DETENT_STEP==TIO_WHEEL_DETENT_STEP&&TML_DETENT_DEFAULT==TIO_WHEEL_DETENT_DEFAULT);
 assert(TIO_WHEEL_LOCK_PAGE_MS==200u&&TIO_WHEEL_LOCK_MUSIC_MS==500u);

 /* Pages: one step per D, whatever D is. Events of 50 counts, 5 ms apart: the step lands on the event that reaches D, never before. */
 for(unsigned di=0;di<sizeof DS/sizeof *DS;di++){
  DET=DS[di];int d=(int)DET,events=(d+49)/50;
  for(int sign=-1;sign<=1;sign+=2){
   WRInput w={0};int steps=0,at=0;for(int e=1;e<=events;e++){int r=wr_input_wheel(&w,sign*50,1000+5*(unsigned)e);if(r){steps++;at=e;assert(r==sign);}}
   assert(steps==1&&at==events);                                                       /* D/50 events (rounded up), then exactly one step */
   w=(WRInput){0};assert(wr_input_wheel(&w,sign*(d-1),1000)==0);assert(wr_input_wheel(&w,sign*1,1010)==0);   /* D-1 then jitter-sized 1: still short (1 is jitter) */
   assert(wr_input_wheel(&w,sign*9,1020)==sign);                                          /* D-1 + 9 reaches it */
   w=(WRInput){0};assert(wr_input_wheel(&w,sign*d,1000)==sign);                           /* an injected step of exactly D: one step */
   w=(WRInput){0};assert(wr_input_wheel(&w,sign*INT_MAX,1000)==sign);                     /* one step per call at most, however hard */
  }
  /* Lockout 200 ms, independent of D: a second D at +199 ms is dropped (and clears what it carried), at +200 ms it counts. */
  WRInput w={0};assert(wr_input_wheel(&w,d,1000)==1);assert(!wr_input_wheel(&w,d,1199));assert(wr_input_wheel(&w,d,1450)==1);
  w=(WRInput){0};assert(wr_input_wheel(&w,d,1000)==1);assert(!wr_input_wheel(&w,d,1100));assert(wr_input_wheel(&w,d,1500)==1);
  w=(WRInput){0};assert(wr_input_press(&w,5000));assert(!wr_input_wheel(&w,d,5199));assert(wr_input_wheel(&w,d,5450)==1);
  w=(WRInput){0};assert(wr_input_press(&w,5000));assert(wr_input_wheel(&w,d,5201)==1);
  /* A pause over 250 ms and a reversal drop the carried counts. */
  w=(WRInput){0};assert(!wr_input_wheel(&w,d-60,1000));assert(!wr_input_wheel(&w,60,1300));
  w=(WRInput){0};assert(!wr_input_wheel(&w,d-60,1000));assert(!wr_input_wheel(&w,-60,1010));assert(!wr_input_wheel(&w,60,1020));
  assert(!wr_input_wheel(NULL,d,1)&&!wr_input_wheel(&w,0,1));
 }
 /* D is read at every event: the phone changed it in the middle of a gesture. */
 {WRInput w={0};DET=300;assert(!wr_input_wheel(&w,250,1000));DET=600;assert(!wr_input_wheel(&w,250,1010));assert(wr_input_wheel(&w,100,1020)==1);}
 {WRInput w={0};DET=600;assert(!wr_input_wheel(&w,550,1000));DET=300;assert(wr_input_wheel(&w,60,1010)==1);}   /* the carried 610 clamps to the new D: one step */

 /* Music: one skip per D, 500 ms lockout whatever D is. */
 for(unsigned di=0;di<sizeof DS/sizeof *DS;di++){
  DET=DS[di];int d=(int)DET,events=(d+49)/50;
  for(int sign=-1;sign<=1;sign+=2){
   TMInput m={0};int steps=0,at=0;for(int e=1;e<=events;e++){int r=tm_input_wheel(&m,sign*50,1000+5*(unsigned)e);if(r){steps++;at=e;assert(r==sign);}}
   assert(steps==1&&at==events);
   m=(TMInput){0};assert(tm_input_wheel(&m,sign*d,1000)==sign);assert(!tm_input_wheel(&m,sign*d,1499));assert(tm_input_wheel(&m,sign*d,1750)==sign);
   m=(TMInput){0};assert(tm_input_wheel(&m,sign*d,1000)==sign);assert(tm_input_wheel(&m,sign*d,1501)==sign);
   m=(TMInput){0};assert(tm_input_wheel(&m,sign*INT_MAX,1000)==sign);
  }
  TMInput m={0};assert(!tm_input_wheel(&m,d-60,1000));assert(!tm_input_wheel(&m,60,1300));          /* idle reset */
  m=(TMInput){0};assert(!tm_input_wheel(&m,d-1,1000));assert(!tm_input_wheel(&m,-60,1010));assert(!tm_input_wheel(&m,60,1020));   /* reversal reset */
 }
 {TMInput m={0};DET=300;assert(!tm_input_wheel(&m,250,1000));DET=600;assert(!tm_input_wheel(&m,250,1010));assert(tm_input_wheel(&m,100,1020)==1);}

 /* Menu: tio_menu_wheel_step. One item per D, from any item, wrapping past either end; 13 items take 13 * D counts. */
 for(unsigned di=0;di<sizeof DS/sizeof *DS;di++){
  unsigned d=DS[di];
  for(int count=8;count<=13;count++)for(int sign=-1;sign<=1;sign+=2)for(int start=0;start<count;start++){
   TIOMenuStep s={0};int index=start;uint32_t now=1000;
   /* 50-count events: the item changes exactly once per D counts, to the neighbour in the turn's direction (the wrap past the end). */
   for(long fed=0,steps=0;fed<(long)count*(long)d;fed+=50){
    int t=tio_menu_wheel_step(&s,index,count,sign*50,now,d);now+=5;
    long after=(fed+50)/(long)d;if(after>steps){assert(t==mod(index+sign,count));index=t;steps=after;}else assert(t==-1);
   }
   assert(index==start);                                                               /* count * D counts: all the way round, back where it started */
  }
  /* The wrap is the step past the end, at the same D as any other step. */
  for(int count=8;count<=13;count++){
   TIOMenuStep s={0};assert(tio_menu_wheel_step(&s,count-1,count,(int)d,1000,d)==0);                        /* last -> first */
   s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,0,count,-(int)d,1000,d)==count-1);                      /* first -> last */
   s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,count-1,count,(int)d-1,1000,d)==-1);                    /* one count short: nothing */
   s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,0,count,(int)d,1000,d)==1&&tio_menu_wheel_step(&s,1,count,-(int)d,1100,d)==0);   /* turning back is an ordinary step */
  }
  /* Items per turn at ~2000 counts per turn: 6.7 / 5.0 / 4.4 / 3.3 at D = 300 / 400 / 450 / 600 (whole items fed in 50-count events). */
  {TIOMenuStep s={0};int index=0;uint32_t now=1000;int moves=menu_run(&s,&index,13,1,2000,50,&now,d);assert(moves==(int)(2000/d));}
  {TIOMenuStep s={0};int index=5;uint32_t now=1000;int moves=menu_run(&s,&index,13,-1,2000,50,&now,d);assert(moves==(int)(2000/d));assert(index==mod(5-(int)(2000/d),13));}
 }
 assert(2000/300==6&&2000/400==5&&2000/450==4&&2000/600==3);   /* whole items per turn; the fractions 6.7 / 5.0 / 4.4 / 3.3 are the remainders carried into the next turn */

 /* A gesture is a run of counts less than 250 ms apart in one direction: a pause or a reversal drops the remainder, jitter (8 counts or fewer) is
  * ignored without breaking the run, and an event can carry a remainder over. */
 {unsigned d=400;TIOMenuStep s={0};
  assert(tio_menu_wheel_step(&s,5,13,350,1000,d)==-1&&tio_menu_wheel_step(&s,5,13,50,1010,d)==6);                          /* 350 + 50 */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,350,1000,d)==-1&&tio_menu_wheel_step(&s,5,13,50,1300,d)==-1);       /* pause: the 350 is gone */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,350,1000,d)==-1&&tio_menu_wheel_step(&s,5,13,-60,1010,d)==-1&&tio_menu_wheel_step(&s,5,13,60,1020,d)==-1);   /* reversal: fresh runs */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,350,1000,d)==-1);
  assert(tio_menu_wheel_step(&s,5,13,8,1010,d)==-1&&tio_menu_wheel_step(&s,5,13,-8,1011,d)==-1&&tio_menu_wheel_step(&s,5,13,0,1012,d)==-1&&tio_menu_wheel_step(&s,5,13,1,1013,d)==-1);
  assert(tio_menu_wheel_step(&s,5,13,50,1020,d)==6);                                                                       /* jitter neither counted nor broke the run */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,600,1000,d)==6&&s.remainder==200);                                 /* 600 = one item + 200 carried */
  assert(tio_menu_wheel_step(&s,6,13,200,1010,d)==7&&s.remainder==0);
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,-600,1000,d)==4&&s.remainder==-200);                               /* the remainder keeps the sign of the gesture */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,1000,1000,d)==7&&s.remainder==200);                                /* 2.5 D in one event: two items */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,13*400,1000,d)==-1&&s.remainder==0);                               /* a full lap lands where it started: no step */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,12,13,2*400,1000,d)==1);                                                /* two items from the last: first, second */
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,0,13,-2*400,1000,d)==11);
 }
 /* Guards: no state, fewer than two items, no delta, an invalid D (back to the default 400), an index outside the list, a saturated delta and tick. */
 {TIOMenuStep s={0};assert(tio_menu_wheel_step(NULL,5,13,400,1000,400)==-1&&tio_menu_wheel_step(&s,0,1,400,1000,400)==-1&&tio_menu_wheel_step(&s,0,0,400,1000,400)==-1&&tio_menu_wheel_step(&s,5,13,0,1000,400)==-1);
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,400,1000,0)==6);
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,400,1000,425)==6);s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,400,1000,700)==6);s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,5,13,400,1000,50)==6);
  s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,-3,13,400,1000,400)==1);s=(TIOMenuStep){0};assert(tio_menu_wheel_step(&s,40,13,400,1000,400)==0);   /* clamped into the list first */
  for(int sign=-1;sign<=1;sign+=2)for(int i=0;i<13;i++){s=(TIOMenuStep){0};int t=tio_menu_wheel_step(&s,i,13,sign>0?INT_MAX:INT_MIN,UINT_MAX-5,400);assert(t>=-1&&t<13&&t!=i);assert(s.remainder>-400&&s.remainder<400);}
 }
 puts("PASS tmg9 stepping: one page step, music skip and menu item per D (300..600), D read at every event, 200/500 ms lockouts independent of D, wrap is the step past the end, 13 items in 13 D");
 return 0;
}
