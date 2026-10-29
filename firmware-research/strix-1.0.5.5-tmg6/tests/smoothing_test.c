#include "navigation-runtime-v1/nav_map.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void put16(uint8_t *p,int v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void scene(TNRState *s){uint8_t b[44]={1,0,0,0,64,1,1,0,2,0};b[16]=2;b[18]=6;put16(b+24,-300);put16(b+26,-200);put16(b+28,-300);put16(b+30,400);b[32]=1;assert(tnr_receive(s,TNR_SCENE2,b,44,0));}
static void pose(TNRState *s,int x,int y,unsigned heading,unsigned speed,uint32_t now){uint8_t b[14]={1};put16(b+4,x);put16(b+6,y);put16(b+8,heading);put16(b+12,speed);assert(tnr_receive(s,TNR_POSE2,b,14,now));}
static TNRPose at(TNRState *s,uint32_t now){TNRPose p;assert(tnr_position(s,now,&p));return p;}
int main(void){
 TNRState s={.smooth=true};scene(&s);uint8_t raster[TNR_W*TNR_H];tnr_draw(&s,200,raster);unsigned width=0;for(unsigned x=20;x<80;x++)if(raster[60*TNR_W+x])width++;assert(width==5);
 pose(&s,0,0,90,6,1000);int last=at(&s,5000).p.x;pose(&s,8,0,90,6,5000);assert(at(&s,5000).p.x==last);
 for(uint32_t t=5000;t<=13000;t+=50){int x=at(&s,t).p.x;assert(x>=last);assert(x-last<=2);last=x;}
 pose(&s,1000,0,90,6,13000);int before=at(&s,13000).p.x;assert(before==last);assert(at(&s,13180).p.x-before<=5);assert(at(&s,14000).p.x-before<=23);
 assert(at(&s,21000).p.x==at(&s,22000).p.x);assert(at(&s,22000).p.x<=8192);
 pose(&s,at(&s,22000).p.x,0,180,6,22000);assert(at(&s,22180).heading<120&&at(&s,23000).heading==180);
 // Repeated corrections and uint32 timer wrap preserve monotonic movement.
 memset(&s,0,sizeof s);s.smooth=true;scene(&s);pose(&s,0,0,90,6,UINT32_MAX-3000);last=at(&s,500).p.x;pose(&s,5,0,90,6,500);for(unsigned t=500;t<2500;t+=50){int x=at(&s,t).p.x;assert(x>=last);last=x;}
 assert(tnr_receive(&s,TNR_CLEAR,NULL,0,3000)&&s.smooth&&!s.valid);
 // TMG4 mirror mode remains the legacy codec/math for a caps3 peer.
 memset(&s,0,sizeof s);scene(&s);pose(&s,0,0,90,6,1000);last=at(&s,5000).p.x;pose(&s,8,0,90,6,5000);assert(at(&s,5180).p.x<last);
 memset(&s,0,sizeof s);s.smooth=true;scene(&s);pose(&s,-8192,-8192,0,0,0);pose(&s,8192,8192,180,0,1000);tnr_presented(&s,1500);assert(tnr_needs_draw(&s,2000));for(unsigned t=1000;t<=9000;t+=33){TNRPose p=at(&s,t);assert(p.p.x>=-8192&&p.p.x<=8192&&p.p.y>=-8192&&p.p.y<=8192);}
 puts("PASS bounded smoothing: no reverse, bounded forward, heading, 8s/position clamps, wrap, caps3 legacy and vertical stroke");return 0;
}
