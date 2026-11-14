#ifndef TIO_MENU_TILES_H
#define TIO_MENU_TILES_H
#include "../menu-grid-v2/tile_config.h"
enum {TIO_STOCK_ITEMS=TT_STOCK,TIO_TILE_DISPLAY=TT_STOCK,TIO_TILE_NAVIGATION=TT_STOCK+1,TIO_TILE_MUSIC=TT_STOCK+2,
      TIO_TILE_FOCUS=TT_STOCK+3,TIO_TILE_APPS=TT_STOCK+4,TIO_TILE_CAMERA=TT_CAMERA,TIO_MENU_ITEMS=TT_ITEMS,
      TIO_STOCK_LAST_FRAME=15+30*(TIO_STOCK_ITEMS-1),   /* stock's own rest frame for its last stock tile */
      TIO_MENU_LAST=TIO_MENU_ITEMS-1,TIO_MENU_FRAME_MAX=30*TIO_MENU_ITEMS-1};
_Static_assert(TIO_TILE_APPS+1==TIO_TILE_CAMERA,"the camera tile is the last module tile, right after My Apps");
static inline int tio_clampi(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static inline int tio_frame_start(int i){return 15+30*tio_clampi(i,0,TIO_MENU_LAST);}
static inline int tio_frame_index(int f){return tio_clampi(f,0,TIO_MENU_FRAME_MAX)/30;}
static inline int tio_tile_mix(int f,unsigned k){return k<6?tio_clampi(tio_clampi(f,0,TIO_MENU_FRAME_MAX)-(TIO_STOCK_LAST_FRAME+30*(int)k),0,30):0;}
static inline int tio_tile_weight(int f,unsigned k){return k<6?tio_tile_mix(f,k)-(k+1<6?tio_tile_mix(f,k+1):0):0;}
/* Clamp before float-to-int conversion, including NaN and infinities. */
static inline int tio_slide_frame(float value,unsigned count){
 if(count<TT_MIN_VISIBLE||count>TIO_MENU_ITEMS)count=TIO_MENU_ITEMS;
 if(!(value>=-1.0f))value=-1.0f;
 if(value>(float)count)value=(float)count;
 return tio_clampi((int)(value*30.0f+15.5f),0,30*(int)count-1);
}
#endif
