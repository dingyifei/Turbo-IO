#include "../src/music-runtime-v1/menu_tiles.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <math.h>
int main(void){
 assert(TIO_MENU_ITEMS==13&&TIO_MENU_FRAME_MAX==389);
 for(int frame=0;frame<=TIO_MENU_FRAME_MAX;frame++){
  int sum=30-tio_tile_mix(frame,0);
  for(unsigned k=0;k<6;k++){int w=tio_tile_weight(frame,k);assert(w>=0&&w<=30);sum+=w;}
  assert(sum==30);
 }
 for(int i=0;i<TIO_MENU_ITEMS;i++)assert(tio_frame_index(tio_frame_start(i))==i);
 assert(tio_frame_start(99)==tio_frame_start(12));
 assert(tio_frame_start(INT_MIN)==15&&tio_frame_start(INT_MAX)==375);
 assert(tio_frame_index(INT_MIN)==0&&tio_frame_index(INT_MAX)==12);
 assert(tio_tile_weight(389,5)==30);
 for(unsigned count=8;count<=13;count++){
  assert(tio_slide_frame(NAN,count)==0&&tio_slide_frame(-INFINITY,count)==0&&tio_slide_frame(INFINITY,count)==30*(int)count-1);
  for(int i=-1000;i<=1000;i++){float value=(float)i/30;int frame=tio_slide_frame(value,count);assert(frame>=0&&frame<30*(int)count);if(i>=0&&i<30*(int)count-15)assert(frame==(int)(value*30.0f+15.5f));}
 }
 assert(tio_slide_frame(1000,0)==389&&tio_slide_frame(-1000,UINT_MAX)==0);
 puts("PASS menu_tiles: all frame weights, bounded active counts, NaN/infinity slide conversion");
}
