#include "../src/music-runtime-v1/menu_tiles.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
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
 puts("PASS menu_tiles");
}
