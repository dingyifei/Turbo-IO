#ifndef TIO_MENU_TILES_H
#define TIO_MENU_TILES_H
enum {TIO_STOCK_ITEMS=7,TIO_TILE_DISPLAY=7,TIO_TILE_NAVIGATION=8,TIO_TILE_MUSIC=9,
      TIO_TILE_FOCUS=10,TIO_TILE_APPS=11,TIO_TILE_CAMERA=12,TIO_MENU_ITEMS=13,
      TIO_MENU_LAST=TIO_MENU_ITEMS-1,TIO_MENU_FRAME_MAX=30*TIO_MENU_ITEMS-1};
static inline int tio_clampi(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static inline int tio_frame_start(int i){return 15+30*tio_clampi(i,0,TIO_MENU_LAST);}
static inline int tio_frame_index(int f){return tio_clampi(f,0,TIO_MENU_FRAME_MAX)/30;}
static inline int tio_tile_mix(int f,unsigned k){return k<6?tio_clampi(tio_clampi(f,0,TIO_MENU_FRAME_MAX)-(195+30*(int)k),0,30):0;}
static inline int tio_tile_weight(int f,unsigned k){return k<6?tio_tile_mix(f,k)-(k+1<6?tio_tile_mix(f,k+1):0):0;}
#endif
