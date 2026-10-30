// TMG8 lens brightness metric (docs/design-system lens-peak-max). Host only; the same numbers as ds2/tools/lens_metrics.py.
//
// A render is a green plane of device pixels, level L = green/255 (black is see-through).
//   lit_pct    percentage of pixels with L > 0
//   light      sum(L^2.2) / pixel count: mean linear light (gamma 2.2)
//   peak       the brightest 25x25 device-px window (1 degree at 24.8 px/deg), window value = mean of L^2.2 over its 625 px;
//              the window lies fully inside the image; peak_x/peak_y is its top-left, first maximum in raster order
//   center_y   light-weighted vertical centre sum((y+0.5)*L^2.2)/sum(L^2.2) in px from the top, -1 when the image has no light
//
// Limits (tokens.json v2): 0.45 everywhere (lens-peak-max); 0.65 for the band-B primary readout (lens-peak-max-primary: the
// navigation arrow, the focus hero timer); 0.20 for unfocused menu icons (lens-peak-max-unfocused). A widget belongs to the
// primary class only when it also lies wholly in band B; where it sits decides, not which file draws it.
#ifndef TMG8_LENS_BRIGHTNESS_H
#define TMG8_LENS_BRIGHTNESS_H
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#define LB_WINDOW 25
#define LB_GAMMA 2.2
#define LB_PEAK_MAX 0.45
#define LB_PEAK_MAX_PRIMARY 0.65
#define LB_PEAK_MAX_UNFOCUSED 0.20
typedef struct {double lit_pct,light,peak,center_y;int peak_x,peak_y;} LBMetrics;
static inline double lb_lin(uint8_t g){static double lut[256];static int ready;if(!ready){for(int i=0;i<256;i++)lut[i]=pow(i/255.0,LB_GAMMA);ready=1;}return lut[g];}
static inline void lb_metrics(const uint8_t *green,int w,int h,LBMetrics *m){
 *m=(LBMetrics){0};if(w<=0||h<=0)return;
 int n=LB_WINDOW;if(w<n||h<n)n=w<h?w:h;
 double *S=calloc((size_t)(w+1)*(size_t)(h+1),sizeof *S);if(!S){return;}
 double total=0,moment=0;long lit=0;
 for(int y=0;y<h;y++){double run=0;for(int x=0;x<w;x++){uint8_t g=green[y*w+x];double l=lb_lin(g);run+=l;total+=l;moment+=(y+0.5)*l;lit+=g>0;S[(size_t)(y+1)*(w+1)+x+1]=S[(size_t)y*(w+1)+x+1]+run;}}
 double best=-1;int bx=0,by=0;
 for(int y=0;y+n<=h;y++)for(int x=0;x+n<=w;x++){
  double s=S[(size_t)(y+n)*(w+1)+x+n]-S[(size_t)y*(w+1)+x+n]-S[(size_t)(y+n)*(w+1)+x]+S[(size_t)y*(w+1)+x];
  if(s>best+1e-9){best=s;bx=x;by=y;}}
 free(S);
 m->lit_pct=100.0*(double)lit/((double)w*h);m->light=total/((double)w*h);m->peak=best/((double)n*n);m->peak_x=bx;m->peak_y=by;m->center_y=total>0?moment/total:-1;
}
#endif
