#include "../src/music-runtime-v1/menu_tiles.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <math.h>
int main(void){
 assert(TIO_MENU_ITEMS==TT_ITEMS&&TIO_MENU_FRAME_MAX==30*TT_ITEMS-1);
#if defined(TD_STOCK_10611) && TD_STOCK_10611
 assert(TIO_STOCK_LAST_FRAME==225);   /* stock 1.0.6.11's rest frame for its last stock tile, Do Not Disturb (index 7) */
#else
 assert(TIO_STOCK_LAST_FRAME==195);   /* the 13-item model (1.0.5.12 pair): index 6 */
#endif
 /* The cross-fade itself starts at the stock rest frame: module glyph k gains weight exactly over the 30 frames after
  * TIO_STOCK_LAST_FRAME+30k, and no module glyph has any weight at the last stock tile's rest frame. The literal frame of
  * each model is checked too, so a frame typed into tio_tile_mix fails in at least one model. */
 for(unsigned k=0;k<6;k++){int at=TIO_STOCK_LAST_FRAME+30*(int)k;
  assert(tio_tile_mix(at,k)==0&&tio_tile_mix(at+1,k)==1&&tio_tile_mix(at+29,k)==29&&tio_tile_mix(at+30,k)==30);
  assert(tio_tile_weight(TIO_STOCK_LAST_FRAME,k)==0);}
 assert(tio_tile_weight(TIO_STOCK_LAST_FRAME+30,0)==30);
#if defined(TD_STOCK_10611) && TD_STOCK_10611
 assert(tio_tile_mix(225,0)==0&&tio_tile_mix(226,0)==1&&tio_tile_mix(255,0)==30&&tio_tile_mix(255,1)==0);
#else
 assert(tio_tile_mix(195,0)==0&&tio_tile_mix(196,0)==1&&tio_tile_mix(225,0)==30&&tio_tile_mix(225,1)==0);
#endif
 for(int frame=0;frame<=TIO_MENU_FRAME_MAX;frame++){
  int sum=30-tio_tile_mix(frame,0);
  for(unsigned k=0;k<6;k++){int w=tio_tile_weight(frame,k);assert(w>=0&&w<=30);sum+=w;}
  assert(sum==30);
 }
 for(int i=0;i<TIO_MENU_ITEMS;i++)assert(tio_frame_index(tio_frame_start(i))==i);
 assert(tio_frame_start(99)==tio_frame_start(TIO_MENU_LAST));
 assert(tio_frame_start(INT_MIN)==15&&tio_frame_start(INT_MAX)==15+30*TIO_MENU_LAST);
 assert(tio_frame_index(INT_MIN)==0&&tio_frame_index(INT_MAX)==TIO_MENU_LAST);
 assert(tio_tile_weight(TIO_MENU_FRAME_MAX,5)==30);
 for(unsigned count=TT_MIN_VISIBLE;count<=TIO_MENU_ITEMS;count++){
  assert(tio_slide_frame(NAN,count)==0&&tio_slide_frame(-INFINITY,count)==0&&tio_slide_frame(INFINITY,count)==30*(int)count-1);
  for(int i=-1000;i<=1000;i++){float value=(float)i/30;int frame=tio_slide_frame(value,count);assert(frame>=0&&frame<30*(int)count);if(i>=0&&i<30*(int)count-15)assert(frame==(int)(value*30.0f+15.5f));}
 }
 assert(tio_slide_frame(1000,0)==TIO_MENU_FRAME_MAX&&tio_slide_frame(-1000,UINT_MAX)==0);
 puts("PASS menu_tiles: all frame weights, bounded active counts, NaN/infinity slide conversion");
}
