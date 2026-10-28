
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/navigation-runtime-v1/nav_runtime.c"
static void pp(uint8_t *p,int v){p[0]=v;p[1]=(unsigned)v>>8;}
static void replay(unsigned heading,unsigned speed,int x,int y,int target_x,int target_y,uint32_t began){
 TNRState s={.smooth=true};uint8_t scene[44]={1,0,0,0,180,0,1,0,2,0};scene[16]=2;scene[18]=6;pp(scene+24,-400);pp(scene+26,-400);pp(scene+28,400);pp(scene+30,400);scene[32]=1;pp(scene+36,x);pp(scene+38,y);pp(scene+40,heading);assert(tnr_receive(&s,TNR_SCENE2,scene,sizeof scene,began-1000));
 uint8_t pose[14]={1};pp(pose+4,target_x);pp(pose+6,target_y);pp(pose+8,heading);pp(pose+12,speed);assert(tnr_receive(&s,TNR_POSE2,pose,sizeof pose,began));
 TNRPose previous;assert(tnr_position(&s,began,&previous));
 for(unsigned elapsed=1;elapsed<=8100;elapsed+=33){TNRPose current;assert(tnr_position(&s,began+elapsed,&current));assert(current.precise&&current.heading==heading);assert(current.rotated_y>=previous.rotated_y);assert(ab(current.fine_x)<=8192*16384&&ab(current.fine_y)<=8192*16384);TNRPoint a=screen((TNRPoint){-313,-99},&previous,180),b=screen((TNRPoint){-313,-99},&current,180);assert(b.y>=a.y);previous=current;}
 TNRPose a,b;assert(tnr_position(&s,began+8000,&a)&&tnr_position(&s,began+9000,&b));assert(a.fine_x==b.fine_x&&a.fine_y==b.fine_y);
}
int main(void){
 TNRState s={.smooth=true};
 uint8_t scene[44]={1,0,0,0,180,0,1,0,2,0};scene[16]=2;scene[18]=6;pp(scene+24,-400);pp(scene+26,-400);pp(scene+28,400);pp(scene+30,400);scene[32]=1;pp(scene+40,144);
 assert(tnr_receive(&s,TNR_SCENE2,scene,sizeof scene,0));
 uint8_t pose[14]={1};pp(pose+4,45);pp(pose+6,47);pp(pose+8,144);pp(pose+12,6);
 assert(tnr_receive(&s,TNR_POSE2,pose,sizeof pose,1000));
 TNRPose a,b;assert(tnr_position(&s,1297,&a)&&tnr_position(&s,1330,&b));
 printf("precise forward move=%.6f qm; coarse diagnostic coordinates=(%d,%d)->(%d,%d); blend=%u ms\n",(b.rotated_y-a.rotated_y)/16384.0,a.p.x,a.p.y,b.p.x,b.p.y,s.blend_ms);
 TNRPoint pa=screen((TNRPoint){-313,-99},&a,180),pb=screen((TNRPoint){-313,-99},&b,180);assert(pb.y>=pa.y);
 for(int64_t n=-500000000000LL;n<=500000000000LL;n+=100000003LL)assert(fine_div(n,1234567)==n/1234567);
 for(unsigned h=0;h<360;h+=3)for(unsigned k=0;k<3;k++){unsigned speed=(unsigned[]){1,6,200}[k];replay(h,speed,0,0,45,47,1000);replay(h,speed,0,0,-45,47,UINT32_MAX-1200);replay(h,speed,0,0,8192,-8192,1000);replay(h,speed,8192,0,8192,-1000,1000);replay(h,speed,0,-8192,1000,-8192,1000);}
 replay(60,6,8192,0,8192,-1000,1000);replay(60,1,8190,0,8192,-1000,1000);replay(240,6,-8192,0,-8192,1000,1000);
 puts("PASS diagonal correction does not reverse the raster");return 0;
}
