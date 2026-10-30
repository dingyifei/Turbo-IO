#ifndef TURBO_FOCUS_MENU_H
#define TURBO_FOCUS_MENU_H
#include "../navigation-runtime-v1/nav_view.h"
#include "../music-runtime-v1/menu_tiles.h"
#include "../menu-grid-v2/tile_config.h"
/* TMG7 LensMenu (docs/design-system/screens/LensMenu.dc.html, halved): status in band T, the icon grid in band M,
 * the focused name once in band B. A 24x3 caret under the focused icon replaces the 52 px ring.
 * TMG8 adds the carousel (rows == FM_CAROUSEL, LensMenuCarousel.dc.html): one row of 80/48/36 px icons that slide on the
 * wheel, a status line under the focused icon, the name in band B. It reuses the same widgets: icons[0..5] are the six
 * visible slots, ranked by distance from the focus, and the grid cell storage is a union with the carousel storage. */
enum { FM_ITEMS=TIO_MENU_ITEMS, FM_CELLS=9, FM_ICON=32, FM_CARET_W=24, FM_CARET_H=3, FM_CAROUSEL=1, FM_SLOTS=6, FM_LINE_MAX=96 };
/* Carousel canvas capacity per slot rank (side length in px, nearest to the focus first) and the byte offset of each slot in one
 * bank. Slot k is the k-th nearest item to the (fractional) focus: 80 px at the centre, at most 64 for the second, then 48, 42, 36, 36.
 * Offsets are 64 byte aligned like every other retained canvas. */
#define FM_CAR_SIDES {80,64,48,42,36,36}
#define FM_CAR_OFFSETS {0,6400,10496,12800,14592,15936}
#define FM_CAR_BANK 17280u
typedef struct {
 TTVisible tiles;TNWidgets api;void *root,*icons[FM_CELLS],*labels[FM_CELLS],*caret,*status,*battery,*name,*page,*line;
 union {_Alignas(64) uint8_t pixels[2][FM_CELLS][FM_ICON*FM_ICON];_Alignas(64) uint8_t cpixels[2][FM_CAR_BANK];};
 _Alignas(64) uint8_t caret_px[FM_CARET_W*FM_CARET_H];
 _Alignas(64) uint8_t pager[2][36*4];
 char header[2][48];unsigned bank,header_bank,rows;
 int selected,caret_x,caret_y,from_x,from_y,page_offset;
 unsigned weights[FM_CELLS],from_weights[FM_CELLS];
 uint32_t started,last_draw;bool moving,page_motion;
 /* Carousel state: position in item units (8.8 fixed point, unwrapped while a move runs), route weight (0 none .. 256 route). */
 int car_p,car_from_p,car_to_p;unsigned car_w,car_from_w,car_to_w;bool route,reduce_motion,dirty;
 char line_text[2][FM_LINE_MAX];unsigned line_bank;
} FMView;
bool fm_view_open(FMView *,const TNWidgets *,void *,bool (*)(void *,void *),void *);
bool fm_view_update(FMView *,int,int64_t,int,uint32_t);
bool fm_view_step(FMView *,uint32_t);
bool fm_view_rows(FMView *,unsigned);                /* 1 carousel, 2 or 3 grid rows */
/* Carousel hooks. A route (navigation title in band T) shrinks the icons to 64/40/32 px and moves the row down; the status
 * line is the focused tile's live state (UTF-8, cut at a character boundary to fit, empty hides it). Both animate in
 * lens-move-ms and snap under Reduce Motion. They only record state while another layout is shown. */
bool fm_view_route(FMView *,bool,uint32_t);
bool fm_view_line(FMView *,const char *);
void fm_view_reduce_motion(FMView *,bool);
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
