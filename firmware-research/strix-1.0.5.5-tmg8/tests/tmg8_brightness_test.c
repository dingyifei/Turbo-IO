// TMG8 brightness metric unit test (lens_brightness.h): closed forms and the file mode used by tmg8_brightness_test.py.
//   tmg8_brightness_test                -> self-checks, prints PASS
//   tmg8_brightness_test IMAGE.pgm ...  -> one line per binary PGM: lit_pct light peak peak_x peak_y center_y (for the cross-check)
#include "lens_brightness.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t *pgm(const char *path,int *w,int *h){
 FILE *f=fopen(path,"rb");assert(f);int max=0;assert(fscanf(f,"P5 %d %d %d",w,h,&max)==3&&max==255);assert(fgetc(f)=='\n');
 uint8_t *d=malloc((size_t)*w*(size_t)*h);assert(d&&fread(d,1,(size_t)*w*(size_t)*h,f)==(size_t)*w*(size_t)*h);fclose(f);return d;}
int main(int argc,char **argv){
 if(argc>1){for(int i=1;i<argc;i++){int w,h;uint8_t *d=pgm(argv[i],&w,&h);LBMetrics m;lb_metrics(d,w,h,&m);
   printf("%.12f %.12f %.12f %d %d %.12f\n",m.lit_pct,m.light,m.peak,m.peak_x,m.peak_y,m.center_y);free(d);}return 0;}
 static uint8_t img[60*40];LBMetrics m;
 memset(img,255,sizeof img);lb_metrics(img,60,40,&m);assert(fabs(m.peak-1)<1e-12&&fabs(m.light-1)<1e-12&&m.lit_pct==100&&m.peak_x==0&&m.peak_y==0);   // full green everywhere
 memset(img,0,sizeof img);lb_metrics(img,60,40,&m);assert(m.peak==0&&m.light==0&&m.lit_pct==0&&m.center_y==-1);
 memset(img,0,sizeof img);for(int y=10;y<20;y++)for(int x=30;x<40;x++)img[y*60+x]=255;lb_metrics(img,60,40,&m);   // a 10x10 full block lies fully inside one window
 assert(fabs(m.peak-100.0/625)<1e-12&&m.peak_y==0&&m.peak_x==15&&fabs(m.center_y-15)<1e-12&&fabs(m.lit_pct-100*100.0/2400)<1e-9);   // first window in raster order that holds it
 memset(img,0,sizeof img);memset(img+39*60,0x77,60);lb_metrics(img,60,40,&m);assert(fabs(m.peak-pow(0x77/255.0,2.2)/25)<1e-12&&m.peak_y==15&&fabs(m.center_y-39.5)<1e-9);   // one lit bottom row
 // The limits are ordered and unchanged from tokens.json v2.
 assert(LB_PEAK_MAX==0.45&&LB_PEAK_MAX_PRIMARY==0.65&&LB_PEAK_MAX_UNFOCUSED==0.20&&LB_WINDOW==25);
 // The mid level used for all capped art stays under the unfocused limit and the 0x38 track far below it.
 assert(pow(0x77/255.0,2.2)<LB_PEAK_MAX_UNFOCUSED&&pow(0x38/255.0,2.2)<0.05);
 printf("PASS tmg8 brightness metric\n");return 0;
}
