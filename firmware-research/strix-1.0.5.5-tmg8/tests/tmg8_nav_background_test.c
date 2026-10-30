#include "../src/navigation-runtime-v1/nav_live.h"
#include "../src/focus-v1/nav_title.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* TMG8 background route state, end to end on the host: a route session whose page was closed (tn_detach) still gives the menu its band T title
 * and the Navigation tile line, through the same functions the firmware uses (tn_live_fill -> nt_title / ts_state), and clears them the moment
 * the route is stale, silent, disconnected, stopped or replaced. A mock UI counts every page and power call; nothing here is drawn. */
static unsigned lang_now;
unsigned tio_lang(void){return lang_now;}
typedef struct {unsigned enter,render,wake,release,sleep,leave;bool fail;} Mock;
static bool available(void *p){(void)p;return true;}
static bool enter(void *p,const TNScene *s){assert(s);Mock *m=p;if(m->fail)return false;m->enter++;return true;}
static bool render(void *p,const TNScene *s,bool stale){(void)stale;assert(s);((Mock *)p)->render++;return true;}
static bool power(void *p,enum TNPower a){Mock *m=p;if(a==TN_POWER_WAKE_HOLD)m->wake++;else if(a==TN_POWER_RELEASE)m->release++;else m->sleep++;return true;}
static void leave(void *p){((Mock *)p)->leave++;}
static TNUI api(Mock *m){return (TNUI){m,available,enter,render,power,leave};}
static TNScene scene(unsigned icon,uint32_t meters,uint32_t remaining,const char *road){
 TNScene s;memset(&s,0,sizeof s);s.icon=(uint8_t)icon;s.distance_m=meters;s.remaining_m=remaining;s.remaining_s=480;s.point_count=2;s.position=(TNPoint){500,500};
 s.points[0]=(TNPoint){500,1000};s.points[1]=(TNPoint){500,500};snprintf(s.road,sizeof s.road,"%s",road);strcpy(s.turn,"Turn");return s;}
static TNReply send(TNRuntime *r,TNUI *u,enum TNOp op,uint32_t sid,uint32_t seq,TNScene *s,uint32_t now){uint8_t b[512];size_t n=tn_encode(b,sizeof b,op,sid,seq,s);assert(n);return tn_receive(r,u,b,n,now,true);}
/* What the menu draws at one of its redraws: the title text (empty: hidden) and the Navigation tile line. */
typedef struct {bool title;char text[NT_TEXT_MAX];unsigned icon;bool dot;char line[TS_LINE_MAX];bool off;} Menu;
static Menu menu(const TNRuntime *r,uint32_t now,bool phone,unsigned lang){
 TSLive live;memset(&live,0,sizeof live);live.phone=phone;tn_live_fill(r,now,&live);lang_now=lang;
 NTTitle t;nt_title(&live,&t);TSState st;memset(&st,0,sizeof st);ts_state(TIO_TILE_NAVIGATION,&live,lang,&st);
 Menu m;memset(&m,0,sizeof m);m.title=t.on;m.icon=t.icon;memcpy(m.text,t.text,sizeof m.text);m.dot=st.active;memcpy(m.line,st.line,sizeof m.line);m.off=st.phone_off;return m;
}
static void shows(const Menu *m,const char *title,const char *line){
 if(!m->title||strcmp(m->text,title)||!m->dot||strcmp(m->line,line)){printf("title %d '%s' dot %d line '%s' (want '%s' / '%s')\n",m->title,m->text,m->dot,m->line,title,line);assert(0);}
}
static void clear(const Menu *m){if(m->title||m->dot||m->text[0]||(m->line[0]&&!m->off)){printf("not clear: title %d '%s' dot %d '%s'\n",m->title,m->text,m->dot,m->line);assert(0);}}
int main(void){
 Mock m={0};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene(TN_RIGHT,200,1200,"Market St");
 clear(&(Menu){0});
 assert(send(&r,&u,TN_START,1,1,&s,0).result==TN_OK);
 /* The page is open: the menu cannot be shown, but the same read works. */
 { Menu v=menu(&r,1000,true,0);shows(&v,"200 m \xc2\xb7 Market St","1.2 km to go");assert(v.icon==TN_RIGHT); }
 /* Leave the page with an active route: state kept, the menu shows the title and the tile line, the power hold is released. */
 assert(tn_detach(&r,&u)&&r.hidden&&!r.held&&m.release==1&&m.leave==1&&m.sleep==0);
 { Menu v=menu(&r,2000,true,0);shows(&v,"200 m \xc2\xb7 Market St","1.2 km to go");assert(v.icon==TN_RIGHT); }
 /* It follows the phone's updates (the turn, the distance, the road) with no render and no wake. */
 s=scene(TN_LEFT,640,800,"Mission St");assert(send(&r,&u,TN_UPDATE,1,2,&s,5000).result==TN_OK);
 { Menu v=menu(&r,5500,true,0);shows(&v,"640 m \xc2\xb7 Mission St","800 m to go");assert(v.icon==TN_LEFT); }
 s=scene(TN_ARRIVE,40,40,"");assert(send(&r,&u,TN_UPDATE,1,3,&s,9000).result==TN_OK);
 { Menu v=menu(&r,9500,true,0);shows(&v,"40 m","40 m to go");assert(v.icon==TN_ARRIVE); }
 /* Chinese. */
 { Menu v=menu(&r,9500,true,1);assert(v.title&&v.dot&&!strcmp(v.text,"40 m")&&!strcmp(v.line,"\xe5\x89\xa9\xe4\xbd\x99 40 \xe7\xb1\xb3")); }
 assert(m.render==0&&m.enter==1&&m.wake==1&&m.sleep==0);
 /* The phone link drops: no title, no dot, "Phone not connected" on the tile. */
 { Menu v=menu(&r,9500,false,0);assert(!v.title&&!v.dot&&v.off&&!strcmp(v.line,"Phone not connected")); }
 /* Stale: the title and the dot are gone the moment the limit passes, before the session's own tick has run. */
 for(unsigned i=0;i<6;i++)assert(send(&r,&u,TN_HEARTBEAT,1,4+i,NULL,20000+i*10000-(i==5?2000:0)).result==TN_OK);   /* the link stays up (last packet at 68000); the data does not */
 { Menu v=menu(&r,9000+TN_IDLE_MS-1,true,0);assert(v.title);v=menu(&r,9000+TN_IDLE_MS,true,0);clear(&v); }
 tn_tick(&r,&u,9000+TN_IDLE_MS);assert(!r.active);clear(&(Menu){0});{ Menu v=menu(&r,9000+TN_IDLE_MS,true,0);clear(&v); }
 /* Silent link: 30 s without any packet clears it too. */
 tn_init(&r);memset(&m,0,sizeof m);s=scene(TN_RIGHT,200,1200,"Market St");
 assert(send(&r,&u,TN_START,2,1,&s,0).result==TN_OK&&tn_detach(&r,&u));assert(send(&r,&u,TN_UPDATE,2,2,&s,1000).result==TN_OK);
 { Menu v=menu(&r,30999,true,0);assert(v.title);v=menu(&r,31000,true,0);clear(&v); }
 tn_tick(&r,&u,31000);assert(!r.active);
 /* Disconnect clears it. */
 tn_init(&r);memset(&m,0,sizeof m);assert(send(&r,&u,TN_START,3,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 { Menu v=menu(&r,100,true,0);shows(&v,"200 m \xc2\xb7 Market St","1.2 km to go"); }
 tn_disconnect(&r,&u);{ Menu v=menu(&r,200,true,0);clear(&v); }assert(!r.active&&m.render==0);
 /* Route end from the phone clears it. */
 tn_init(&r);memset(&m,0,sizeof m);assert(send(&r,&u,TN_START,4,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 assert(send(&r,&u,TN_STOP,4,2,NULL,500).result==TN_OK);{ Menu v=menu(&r,600,true,0);clear(&v); }
 /* A new route replaces it: the menu follows the new one. */
 tn_init(&r);memset(&m,0,sizeof m);assert(send(&r,&u,TN_START,5,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 { TNScene n=scene(TN_SLIGHT_RIGHT,90,3000,"Oak Ave");assert(send(&r,&u,TN_START,6,1,&n,1000).result==TN_OK);Menu v=menu(&r,1500,true,0);shows(&v,"90 m \xc2\xb7 Oak Ave","3.0 km to go"); }
 /* Reopening the page shows the live state: same session, no new handshake, the hold is back, the menu read is unchanged. */
 tn_init(&r);memset(&m,0,sizeof m);assert(send(&r,&u,TN_START,7,1,&s,0).result==TN_OK&&tn_detach(&r,&u));
 s=scene(TN_RIGHT,120,1000,"Market St");assert(send(&r,&u,TN_UPDATE,7,2,&s,4000).result==TN_OK);
 assert(tn_attach(&r,&u,6000)&&!r.hidden&&r.sid==7&&r.held&&m.enter==2&&r.scene.distance_m==120);
 { Menu v=menu(&r,6500,true,0);shows(&v,"120 m \xc2\xb7 Market St","1.0 km to go"); }
 s=scene(TN_RIGHT,100,980,"Market St");assert(send(&r,&u,TN_UPDATE,7,3,&s,7000).result==TN_OK&&m.render==1);
 /* A visible session that went stale is as before: connected but stale shows nothing. */
 for(unsigned i=1;i<=7;i++)(void)send(&r,&u,TN_HEARTBEAT,7,3+i,NULL,7000+i*8000);
 tn_tick(&r,&u,7000+TN_IDLE_MS);assert(r.stale);{ Menu v=menu(&r,7000+TN_IDLE_MS,true,0);clear(&v); }
 /* No leak: a thousand leave and reopen turns end with every page left, every hold released and the same session. */
 tn_init(&r);memset(&m,0,sizeof m);assert(send(&r,&u,TN_START,8,1,&s,0).result==TN_OK);uint32_t now=0,seq=1;
 for(unsigned i=0;i<1000;i++){assert(tn_detach(&r,&u));now+=2000;s=scene(TN_RIGHT,100+i,5000,"A St");assert(send(&r,&u,TN_UPDATE,8,++seq,&s,now).result==TN_OK);
  Menu v=menu(&r,now,true,0);assert(v.title&&v.dot);now+=2000;assert(tn_attach(&r,&u,now));now+=1000;assert(send(&r,&u,TN_UPDATE,8,++seq,&s,now).result==TN_OK);}
 assert(tn_detach(&r,&u)&&m.enter==1001&&m.leave==1001&&!r.held&&m.sleep==0);
 { Menu v=menu(&r,now,true,0);assert(v.title); }
 tn_local_exit(&r,&u);{ Menu v=menu(&r,now,true,0);clear(&v); }assert(m.enter==m.leave);
 printf("PASS tmg8 nav background (title and tile line from a page-less route; stale, silence, disconnect, stop, replace, reopen; 1000 leave/reopen turns)\n");return 0;
}
