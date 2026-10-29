#ifndef TURBO_NAV_VIEW_H
#define TURBO_NAV_VIEW_H
#include "nav_visual.h"
#include "nav_map.h"
/* Native LVGL glue is injected so allocation failure / renderer ownership can
 * be tested without pretending that mock rendering is a hardware acceptance. */
typedef struct {
 void *ctx;
 bool (*idle)(void *);
 void *(*root)(void *,void *parent);
 void *(*canvas)(void *,void *parent);
 void *(*label)(void *,void *parent,unsigned font_px);
 void (*place)(void *,void *,int x,int y,int w,int h);
 void (*buffer)(void *,void *,const uint8_t *,unsigned w,unsigned h);
 void (*text_static)(void *,void *,const char *);
 void (*visible)(void *,void *,bool);
 void (*destroy)(void *,void *);
 void (*clip_text)(void *,void *);
 void (*color)(void *,void *,uint32_t rgb); /* optional; labels default to lens-full */
} TNWidgets;
/* LensNav (docs/design-system/screens/LensNav.dc.html, halved): turn glyph in band B at the left,
 * 64 px wide for the stream stride, 56 px high so it stays inside the band. */
#define TN_ICON_W 64u
#define TN_ICON_H 56u
#define TN_MAP_W 192u
#define TN_MAP_H 144u
typedef struct {
 char passing[196],scale[16];
 TNVisual visual;
 TNRLabelView names[TNR_MAX_LABELS];
 _Alignas(64) uint8_t icon[TN_ICON_W*TN_ICON_H];
 _Alignas(64) uint8_t map[TN_MAP_W*TN_MAP_H];
} TNViewFrame;
/* One label per stock font size a line may use; exactly one is visible (labels cannot change font). */
#define TN_TURN_SIZES 3u /* 24, 20, 16 */
#define TN_TRIP_SIZES 2u /* 20, 16 */
#define TN_PASS_SIZES 2u /* 18, 16 */
typedef struct {
 TNRState map_state;uint32_t map_now;
 TNWidgets api;
 void *root,*icon,*map,*distance,*turn[TN_TURN_SIZES],*road,*trip[TN_TRIP_SIZES],*pass[TN_PASS_SIZES],*scale;
 TNViewFrame frames[2];
 char trip_text[2][128],eta[64]; /* trip line = summary, middle dot, eta; the label keeps a pointer into trip_text */
 unsigned trip_bank,active;
 bool trip_shown,eta_stale;
 bool open,retiring;
} TNView;
bool tn_view_open(TNView *,const TNWidgets *,void *parent,const TNScene *);
bool tn_view_update(TNView *,const TNScene *,bool stale);
bool tn_view_clock(TNView *,int64_t local_epoch,int64_t eta_epoch,bool stale);
bool tn_view_map(TNView *,unsigned,const uint8_t *,size_t,uint32_t);
bool tn_view_map_tick(TNView *,uint32_t);
bool tn_view_close(TNView *); /* false means renderer busy; retry on UI timer */
#endif
