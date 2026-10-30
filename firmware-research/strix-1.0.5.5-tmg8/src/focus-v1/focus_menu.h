#ifndef TURBO_FOCUS_MENU_H
#define TURBO_FOCUS_MENU_H
#include "../navigation-runtime-v1/nav_view.h"
#include "../music-runtime-v1/menu_tiles.h"
#include "../menu-grid-v2/tile_config.h"
/* TMG7 LensMenu (docs/design-system/screens/LensMenu.dc.html, halved): status in band T, the icon grid in band M,
 * the focused name once in band B. A 24x3 caret under the focused icon replaces the 52 px ring. */
enum { FM_ITEMS=TIO_MENU_ITEMS, FM_CELLS=9, FM_ICON=32, FM_CARET_W=24, FM_CARET_H=3 };
typedef struct {
 TTVisible tiles;TNWidgets api;void *root,*icons[FM_CELLS],*labels[FM_CELLS],*caret,*status,*battery,*name,*page;
 _Alignas(64) uint8_t pixels[2][FM_CELLS][FM_ICON*FM_ICON];
 _Alignas(64) uint8_t caret_px[FM_CARET_W*FM_CARET_H];
 _Alignas(64) uint8_t pager[2][36*4];
 char header[2][48];unsigned bank,header_bank,rows;
 int selected,caret_x,caret_y,from_x,from_y,page_offset;
 unsigned weights[FM_CELLS],from_weights[FM_CELLS];
 uint32_t started,last_draw;bool moving,page_motion;
} FMView;
bool fm_view_open(FMView *,const TNWidgets *,void *,bool (*)(void *,void *),void *);
bool fm_view_update(FMView *,int,int64_t,int,uint32_t);
bool fm_view_step(FMView *,uint32_t);
bool fm_view_rows(FMView *,unsigned);
bool fm_view_tiles(FMView *,const TTVisible *);
void fm_view_suspend(FMView *);
bool fm_view_close(FMView *);
void fm_show(void *app);
void fm_hide(void *app);
void fm_destroy(void *app);
void fm_sync(void *app);
/* Knob wrap (menu_wheel.h): the item to jump to, or -1 to let the stock carousel take the scaled delta. */
int fm_wheel_wrap(void *app,int index,int count,int delta,uint32_t now);
#endif
