#include "../src/navigation-runtime-v1/nav_map.h"
#include "../src/navigation-runtime-v1/nav_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void u16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void u32(uint8_t *p,unsigned v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void pose(uint8_t p[14],unsigned gen,int x,int y,unsigned h,unsigned speed){memset(p,0,14);u32(p,gen);u16(p+4,(unsigned)x);u16(p+6,(unsigned)y);u16(p+8,h);u16(p+12,speed);}
static void scene(uint8_t p[44],unsigned gen){memset(p,0,44);u32(p,gen);u16(p+4,300);u16(p+6,1);u16(p+8,2);u16(p+16,2);p[18]=6;u16(p+28,100);u16(p+30,100);}
static TNRState state;
static void setup(unsigned op,unsigned speed,unsigned heading){uint8_t s[44],p[14];memset(&state,0,sizeof state);scene(s,1);assert(tnr_receive(&state,TNR_SCENE,s,32,0));pose(p,1,0,0,heading,speed);assert(tnr_receive(&state,op,p,op==TNR_POSE2?14:12,0));}
int main(void){
 uint8_t p[14],s[44],wire[64];TNRPose at,a,b;
 setup(TNR_POSE,0,90);pose(p,1,100,0,90,0);assert(tnr_receive(&state,TNR_POSE,p,12,100));
 assert(tnr_position(&state,190,&at)&&at.p.x==50);assert(tnr_position(&state,280,&at)&&at.p.x==100);assert(tnr_position(&state,2000,&at)&&at.p.x==100);
 assert(!tnr_stale(&state,5099)&&tnr_stale(&state,5100));
 setup(TNR_POSE2,8,90);assert(tnr_position(&state,1000,&at)&&abs(at.p.x-8)<=1&&at.p.y==0);
 assert(tnr_position(&state,8000,&a)&&tnr_position(&state,9000,&b)&&a.p.x==b.p.x&&a.p.y==b.p.y);
 assert(!tnr_stale(&state,9999)&&tnr_stale(&state,10000));
 pose(p,1,12,0,90,8);assert(tnr_receive(&state,TNR_POSE2,p,14,1000));assert(tnr_position(&state,1000,&at)&&at.p.x==8);
 setup(TNR_POSE2,8,0);assert(tnr_position(&state,1000,&at)&&at.p.x==0&&abs(at.p.y-8)<=1);
 setup(TNR_POSE2,0,0);assert(!tnr_stale(&state,4999)&&tnr_stale(&state,5000));
 setup(TNR_POSE2,200,90);pose(p,1,8190,0,90,200);assert(tnr_receive(&state,TNR_POSE2,p,14,0));assert(tnr_position(&state,8000,&at)&&at.p.x==8192);
 setup(TNR_POSE2,8,90);scene(s,2);pose(p,2,50,60,180,0);memcpy(s+32,p,12);assert(tnr_receive(&state,TNR_SCENE2,s,44,1000));assert(state.target.speed==0&&state.located&&!state.pending&&state.target.p.x==50);
 pose(p,2,0,0,90,8);assert(!tnr_body_valid(TNR_POSE2,p,12)&&!tnr_body_valid(TNR_POSE2,p,13)&&!tnr_body_valid(TNR_POSE2,p,15));
 u16(p+12,201);assert(!tnr_body_valid(TNR_POSE2,p,14));u16(p+12,200);
 size_t n=tnr_wrap(wire,sizeof wire,TNR_POSE2,1,1,p,14);assert(n==46&&tn_packet_valid(wire,n));
 setup(TNR_POSE2,8,90);tnr_presented(&state,200);assert(!tnr_needs_draw(&state,250)&&tnr_needs_draw(&state,300));
 puts("PASS pose_prediction: legacy pose, prediction bounds, stale limits, correction and op11 validation");
}
