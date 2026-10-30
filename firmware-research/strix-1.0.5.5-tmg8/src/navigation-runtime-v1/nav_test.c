#include "nav_runtime.h"
#include "nav_visual.h"
unsigned tio_lang(void){return 1;} /* Chinese: the strings below are the ZH table */
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {unsigned enter,render,wake,release,sleep,leave;uint32_t shown;bool available,fail_enter,fail_render,fail_power;} Mock;
static bool available(void *p){return ((Mock *)p)->available;}
static bool enter(void *p,const TNScene *s){assert(s);Mock *m=p;if(m->fail_enter)return false;m->enter++;m->shown=s->distance_m;return true;}
static bool render(void *p,const TNScene *s,bool stale){(void)stale;assert(s);Mock *m=p;m->render++;if(!m->fail_render)m->shown=s->distance_m;return !m->fail_render;}
static bool power(void *p,enum TNPower a){Mock *m=p;if(a==TN_POWER_WAKE_HOLD)m->wake++;else if(a==TN_POWER_RELEASE)m->release++;else m->sleep++;return !m->fail_power;}
static void leave(void *p){((Mock *)p)->leave++;}
static TNUI api(Mock *m){return (TNUI){m,available,enter,render,power,leave};}
static TNScene scene(void){TNScene s={.distance_m=80,.remaining_m=1200,.remaining_s=480,.icon=TN_RIGHT,.point_count=3,.position={500,500}};
 strcpy(s.road,"测试道路");strcpy(s.turn,"前方右转");s.points[0]=(TNPoint){500,1000};s.points[1]=(TNPoint){500,500};s.points[2]=(TNPoint){1000,500};return s;}
static TNReply send(TNRuntime *r,TNUI *u,enum TNOp op,uint32_t sid,uint32_t seq,TNScene *s,uint32_t now){uint8_t b[512];size_t n=tn_encode(b,sizeof b,op,sid,seq,s);assert(n);return tn_receive(r,u,b,n,now,true);}
static void state_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();
 assert(send(&r,&u,TN_START,1,1,&s,0).result==TN_OK);assert(r.active&&r.awake&&m.enter==1);
 for(unsigned i=1;i<=6;i++)assert(send(&r,&u,TN_HEARTBEAT,1,i+1,NULL,i*10000).result==TN_OK);
 assert(r.stale&&!r.awake&&m.sleep==1&&m.release==1); // heartbeat cannot prevent sleep
 assert(tn_button_wake(&r,&u,61000));assert(r.stale&&r.awake);
 tn_tick(&r,&u,120999);assert(r.awake);tn_tick(&r,&u,121000);assert(!r.awake);
 assert(send(&r,&u,TN_UPDATE,1,8,&s,122000).result==TN_OK);assert(r.awake&&!r.stale&&r.connected);
 unsigned wakes=m.wake,renders=m.render;assert(send(&r,&u,TN_UPDATE,1,8,&s,123000).result==TN_OK);
 assert(m.wake==wakes&&m.render==renders&&r.last_update==122000); // exact retry has no side effects
 s.distance_m=40;assert(send(&r,&u,TN_UPDATE,1,8,&s,123000).result==TN_STALE);
 assert(send(&r,&u,TN_UPDATE,2,9,&s,123000).result==TN_NO_SESSION);
 assert(send(&r,&u,TN_UPDATE,1,9,&s,123000).result==TN_OK);assert(r.scene.distance_m==40);
 assert(send(&r,&u,TN_STOP,1,10,NULL,124000).result==TN_OK);assert(!r.active&&m.leave==1);
 assert(send(&r,&u,TN_STOP,1,10,NULL,125000).result==TN_OK);assert(m.leave==1);
 assert(send(&r,&u,TN_START,1,11,&s,125000).result==TN_STALE);
 assert(send(&r,&u,TN_UPDATE,1,11,&s,125000).result==TN_NO_SESSION);
 assert(send(&r,&u,TN_START,2,1,&s,126000).result==TN_OK);tn_local_exit(&r,&u);assert(!r.active&&m.leave==2);
 assert(send(&r,&u,TN_START,2,2,&s,127000).result==TN_STALE); // physical exit is not auto-reopened
 assert(send(&r,&u,TN_START,1,99,&s,127000).result==TN_STALE); // older completed session cannot reopen either
}
static void power_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();s.mode=TN_ALWAYS;
 assert(send(&r,&u,TN_START,50,1,&s,0).result==TN_OK);
 for(unsigned i=1;i<=12;i++)send(&r,&u,TN_HEARTBEAT,50,i+1,NULL,i*10000);
 assert(r.awake&&r.stale&&m.sleep==0); // explicit always-on, but visually stale
 tn_tick(&r,&u,150000);assert(!r.connected&&!r.awake&&m.sleep==1); // not held forever on dead phone
 assert(send(&r,&u,TN_HEARTBEAT,50,14,NULL,151000).result==TN_OK);assert(!r.awake); // cannot revive stale disconnected page
 assert(send(&r,&u,TN_UPDATE,50,15,&s,152000).result==TN_OK);assert(r.connected&&r.awake&&!r.stale);
 s.mode=TN_SMART;send(&r,&u,TN_MODE,50,16,&s,153000);assert(r.scene.mode==TN_SMART);
 tn_tick(&r,&u,212000);assert(!r.awake);assert(tn_button_wake(&r,&u,213000));tn_local_exit(&r,&u);assert(!tn_button_wake(&r,&u,214000));
 tn_init(&r);uint32_t start=UINT32_MAX-30000;send(&r,&u,TN_START,60,1,&s,start);
 tn_tick(&r,&u,start+59999u);assert(r.awake);tn_tick(&r,&u,start+60000u);assert(!r.awake); // tick wrap
}
static void reject_tests(void){
 Mock m={.available=false};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();uint8_t b[512];size_t n=tn_encode(b,sizeof b,TN_START,80,1,&s);
 assert(tn_receive(&r,&u,b,n,0,false).result==TN_UNAUTHORIZED&&m.enter==0);
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_BUSY&&m.enter==0);m.available=true;m.fail_enter=true;
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_UI_FAILED&&!r.active);m.fail_enter=false;
 b[n-1]^=1;assert(tn_receive(&r,&u,b,n,0,true).result==TN_BAD_PACKET&&!r.active);b[n-1]^=1;
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_OK);m.fail_render=true;
 s.distance_m=5;assert(send(&r,&u,TN_UPDATE,80,2,&s,1000).result==TN_UI_FAILED);assert(r.scene.distance_m==80&&r.sequence==1);
 m.fail_render=false;m.fail_power=true;assert(send(&r,&u,TN_UPDATE,80,2,&s,1000).result==TN_UI_FAILED);assert(!r.active);
 s.road[0]=(char)0xff;s.road[1]=0;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
 s=scene();s.point_count=33;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));s=scene();s.heading=360;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
 s=scene();memset(s.road,'x',sizeof s.road);assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
}

/* TMG8 background route state: leaving the page keeps the route's data session. Mock UI counts every page and power call. */
static void background_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();
 assert(send(&r,&u,TN_START,1,1,&s,0).result==TN_OK);assert(m.enter==1&&m.wake==1&&r.held&&r.awake&&!r.hidden);
 assert(!tn_detach(&r,&(TNUI){0}));   /* an unusable UI changes nothing */
 /* Leave the page: the route stays, the power hold goes, the page is left once. */
 assert(tn_detach(&r,&u));assert(r.active&&r.hidden&&r.connected&&!r.stale&&!r.held&&!r.awake&&m.release==1&&m.leave==1&&r.sid==1&&r.scene.distance_m==80);
 assert(!tn_detach(&r,&u)&&m.leave==1&&m.release==1);   /* already closed */
 assert(!tn_button_wake(&r,&u,5000)&&m.wake==1);   /* no page to wake */
 /* Updates, heartbeats, queries and mode changes are accepted with no render, no wake, no page and no screen request. */
 s.distance_m=40;strcpy(s.road,"Market St");
 TNReply q=send(&r,&u,TN_UPDATE,1,2,&s,10000);assert(q.result==TN_OK&&q.active&&!q.awake&&!q.stale);
 assert(r.scene.distance_m==40&&!strcmp(r.scene.road,"Market St")&&r.last_update==10000&&r.sequence==2);
 assert(send(&r,&u,TN_HEARTBEAT,1,3,NULL,20000).result==TN_OK&&r.last_link==20000&&r.last_update==10000);   /* liveness only */
 assert(send(&r,&u,TN_QUERY,1,4,NULL,21000).result==TN_OK);
 s.mode=TN_ALWAYS;assert(send(&r,&u,TN_MODE,1,5,&s,22000).result==TN_OK&&r.scene.mode==TN_ALWAYS);
 assert(send(&r,&u,TN_UPDATE,1,5,&s,23000).result==TN_STALE);   /* sequence rules are unchanged */
 assert(send(&r,&u,TN_UPDATE,2,6,&s,23000).result==TN_NO_SESSION);
 assert(m.enter==1&&m.render==0&&m.wake==1&&m.sleep==0&&m.release==1&&m.leave==1&&!r.held&&!r.awake);
 /* Ticks never wake or sleep the panel while hidden, even in always-on mode, until the silence limit. */
 tn_tick(&r,&u,30000);tn_tick(&r,&u,51999);assert(r.active&&r.hidden&&m.wake==1&&m.sleep==0&&m.release==1);
 for(unsigned i=0;i<4;i++)assert(send(&r,&u,TN_HEARTBEAT,1,6+i,NULL,40000+i*10000-(i==3?1000:0)).result==TN_OK);   /* link kept up to 69000 */
 tn_tick(&r,&u,69999);assert(r.active&&r.hidden&&m.wake==1&&m.sleep==0&&m.release==1);
 /* Stale ends the session: 60 s after the last update. Nothing is left or released: there was no page and no hold. */
 tn_tick(&r,&u,70000);assert(!r.active&&!r.hidden&&!r.connected&&r.last_sid==1&&m.leave==1&&m.release==1&&m.sleep==0);
 assert(send(&r,&u,TN_UPDATE,1,10,&s,70500).result==TN_NO_SESSION);
 assert(send(&r,&u,TN_START,1,11,&s,71000).result==TN_STALE);   /* the ended route's sid cannot come back */
 /* Silence on the link: 30 s without any packet. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;s=scene();
 assert(send(&r,&u,TN_START,3,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 assert(send(&r,&u,TN_UPDATE,3,2,&s,1000).result==TN_OK);tn_tick(&r,&u,30999);assert(r.active);tn_tick(&r,&u,31000);assert(!r.active&&m.leave==1);
 /* A heartbeat keeps the link but not the data: the route still goes stale at 60 s. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;
 assert(send(&r,&u,TN_START,4,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 for(unsigned i=1;i<=5;i++){assert(send(&r,&u,TN_HEARTBEAT,4,i+1,NULL,i*10000).result==TN_OK);assert(r.active);}
 tn_tick(&r,&u,59999);assert(r.active);tn_tick(&r,&u,60000);assert(!r.active);
 /* Phone disconnect (pairing lost) and STOP clear it. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;
 assert(send(&r,&u,TN_START,5,1,&s,0).result==TN_OK&&tn_detach(&r,&u));tn_disconnect(&r,&u);assert(!r.active&&!r.connected&&!r.hidden&&m.leave==1&&m.render==0);
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;
 assert(send(&r,&u,TN_START,6,1,&s,0).result==TN_OK&&tn_detach(&r,&u));assert(send(&r,&u,TN_STOP,6,2,NULL,5000).result==TN_OK);assert(!r.active&&!r.hidden&&m.leave==1);
 assert(send(&r,&u,TN_STOP,6,2,NULL,5001).result==TN_OK&&m.leave==1);   /* the retry is idempotent */
 /* A new route replaces the kept one; an older or equal one does not. A failed new start leaves the kept route alone. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;s.distance_m=70;
 assert(send(&r,&u,TN_START,10,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 s.distance_m=500;assert(send(&r,&u,TN_START,10,9,&s,1000).result==TN_STALE&&r.hidden&&r.scene.distance_m==70);
 assert(send(&r,&u,TN_START,9,1,&s,1000).result==TN_STALE&&r.hidden&&r.sid==10);
 m.available=false;assert(send(&r,&u,TN_START,11,1,&s,1000).result==TN_BUSY&&r.hidden&&r.sid==10);m.available=true;
 m.fail_enter=true;assert(send(&r,&u,TN_START,11,1,&s,1000).result==TN_UI_FAILED&&r.hidden&&r.sid==10&&r.scene.distance_m==70);m.fail_enter=false;
 assert(send(&r,&u,TN_START,11,1,&s,2000).result==TN_OK);
 assert(r.active&&!r.hidden&&r.sid==11&&r.scene.distance_m==500&&r.held&&r.last_sid==10&&m.enter==2&&m.leave==1);   /* the old data session had no page to leave */
 assert(send(&r,&u,TN_UPDATE,10,2,&s,2500).result==TN_NO_SESSION);
 /* Only a live, fresh route can be kept; anything else is exited normally by the caller. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;
 assert(!tn_detach(&r,&u));   /* no session */
 assert(send(&r,&u,TN_START,12,1,&s,0).result==TN_OK);for(unsigned i=1;i<=6;i++)send(&r,&u,TN_HEARTBEAT,12,i+1,NULL,i*10000);assert(r.stale&&!tn_detach(&r,&u)&&!r.hidden&&r.active);
 tn_tick(&r,&u,70001);tn_disconnect(&r,&u);assert(!r.connected&&r.stale);
 /* Reopening the page: the kept scene is shown, no new handshake, the hold is back, the usual 60 s of manual hold. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;s=scene();
 assert(send(&r,&u,TN_START,20,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 s.distance_m=33;assert(send(&r,&u,TN_UPDATE,20,2,&s,10000).result==TN_OK);
 assert(tn_attach(&r,&u,20000));
 assert(!r.hidden&&r.held&&r.awake&&m.enter==2&&m.shown==33&&m.wake==2&&r.sid==20&&r.sequence==2&&r.button_valid&&r.last_button==20000);
 assert(!tn_attach(&r,&u,21000));   /* not hidden: nothing to do */
 s.distance_m=25;assert(send(&r,&u,TN_UPDATE,20,3,&s,22000).result==TN_OK&&m.render==1&&m.shown==25&&r.held);   /* a visible session renders again */
 assert(tn_detach(&r,&u)&&m.release==2&&m.leave==2);
 /* A page that cannot open stays closed and the route stays kept; a wake that fails closes the page again. */
 m.fail_enter=true;assert(!tn_attach(&r,&u,23000)&&r.hidden&&r.active&&m.enter==2&&m.leave==2);m.fail_enter=false;
 m.fail_power=true;assert(!tn_attach(&r,&u,24000)&&r.hidden&&r.active&&m.enter==3&&m.leave==3&&!r.held);m.fail_power=false;
 assert(tn_attach(&r,&u,25000)&&!r.hidden&&m.enter==4);
 /* Reopening after the route went stale or silent finds nothing to resume. */
 assert(tn_detach(&r,&u));assert(!tn_attach(&r,&u,25000+60000)&&!r.active&&!r.hidden);
 /* No leak across repeated leave and reopen: every page entered is left, every hold released, the data intact. */
 tn_init(&r);memset(&m,0,sizeof m);m.available=true;s=scene();uint32_t now=0;
 assert(send(&r,&u,TN_START,30,1,&s,now).result==TN_OK);unsigned seq=1;
 for(unsigned i=0;i<2000;i++){
  assert(tn_detach(&r,&u));now+=1000;s.distance_m=1000-i%900;assert(send(&r,&u,TN_UPDATE,30,++seq,&s,now).result==TN_OK);
  assert(m.enter==m.leave&&m.release==i+1&&!r.held&&r.hidden);   /* a hold is released at every leave */
  now+=1000;assert(tn_attach(&r,&u,now));assert(m.enter==m.leave+1&&r.held&&m.shown==s.distance_m);
  now+=1000;assert(send(&r,&u,TN_UPDATE,30,++seq,&s,now).result==TN_OK);
 }
 assert(r.sid==30&&r.active&&m.sleep==0&&m.enter==2001&&m.leave==2000);
 tn_local_exit(&r,&u);assert(m.enter==m.leave&&m.release==2001&&!r.held&&!r.active);
}
static uint32_t random_state=7392;
static uint32_t rnd(void){random_state^=random_state<<13;random_state^=random_state>>17;random_state^=random_state<<5;return random_state;}
static void fuzz(void){
 TNRuntime r;tn_init(&r);Mock m={.available=true};TNUI u=api(&m);uint8_t p[512];
 for(unsigned i=0;i<50000;i++){size_t n=rnd()%513;for(size_t j=0;j<n;j++)p[j]=(uint8_t)rnd();tn_receive(&r,&u,p,n,rnd(),true);}
 assert(!m.enter);
 for(unsigned i=0;i<5000;i++){TNScene s=scene();s.icon=(uint8_t)(rnd()%TN_ICON_COUNT);s.mode=(uint8_t)(rnd()%2);s.point_count=(uint8_t)(rnd()%33);s.distance_m=rnd()%1000001;
 for(unsigned j=0;j<s.point_count;j++)s.points[j]=(TNPoint){rnd()%1024,rnd()%1024};
 size_t n=tn_encode(p,sizeof p,TN_START,i+1,1,&s);assert(n&&n<=328);tn_init(&r);assert(tn_receive(&r,&u,p,n,0,true).result==TN_OK);assert(r.scene.distance_m==s.distance_m);
 TNVisual v;assert(tn_visual(&r.scene,false,&v));assert(v.route_count==s.point_count);tn_local_exit(&r,&u);
 }
}
static void metrics_tests(void){
 TNScene s=scene();TNVisual v;assert(tn_visual(&s,false,&v));assert(!strcmp(v.summary,"1.2 km \xc2\xb7 8分钟"));
 s.remaining_s=3661;s.remaining_m=10000000;assert(tn_visual(&s,false,&v));assert(!strcmp(v.summary,"10000.0 km \xc2\xb7 1小时2分钟"));
 s.remaining_s=604800;assert(tn_visual(&s,false,&v));assert(strlen(v.summary)<sizeof v.summary);
 struct {char text[64];char canary;} guarded={.canary='X'};int64_t midnight=946684800;
 tn_clock_text(guarded.text,midnight+23*3600+59*60,midnight+86460,false);assert(!strcmp(guarded.text,"明日 00:01"));
 tn_clock_text(guarded.text,midnight,midnight+604800,false);assert(!strcmp(guarded.text,"7天后 00:00"));
 tn_clock_text(guarded.text,0,0,false);assert(!strcmp(guarded.text,"到达时间待更新"));
 tn_clock_text(guarded.text,midnight,midnight-1,false);assert(!strcmp(guarded.text,"到达时间待更新"));
 tn_clock_text(guarded.text,midnight,midnight+604801,false);assert(!strcmp(guarded.text,"到达时间待更新"));
 tn_clock_text(guarded.text,INT64_MAX,INT64_MAX,false);assert(!strcmp(guarded.text,"到达时间待更新"));
 tn_clock_text(guarded.text,midnight+3600,midnight+3600+600,false);assert(!strcmp(guarded.text,"01:10"));
 tn_clock_text(guarded.text,midnight,midnight+120,true);assert(strstr(guarded.text,"过期"));assert(guarded.canary=='X');
}
int main(void){state_tests();power_tests();reject_tests();background_tests();fuzz();metrics_tests();
 printf("PASS navigation codec, background route state (leave/reopen/stale/silence/replace), 60s inactivity, always-on/disconnect, button wake, physical exit, retry/sequence, UTF-8/bounds, tick wrap, 50000 malformed + 5000 valid scenes; runtime=%zu visual=%zu bytes. No native hardware.\n",sizeof(TNRuntime),sizeof(TNVisual));return 0;}
