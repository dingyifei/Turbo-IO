#ifndef TIO_UI_HEADER
#define TIO_UI_HEADER
/* TMG7 glasses design tokens: docs/design-system/tokens.json ("lens") and
 * components/{PriorityBands,LensType}. Header-only, integer-only, freestanding.
 *
 * Every size is authored as an angle and converted with ONE number, TIO_PPD_X10.
 * 24.8 px/deg is an UNVERIFIED estimate (23.5 deg diagonal over the 540x220 window);
 * measure it on the device and change only TIO_PPD_X10. Angles are integer thousandths
 * of a degree (mdeg) so no floating point is needed. At 24.8 each angle converts back to
 * exactly the pixel value written beside it; tests/tmg7_ui_test.c pins that.
 * The 540x180 / 540x220 canvases are hardware, so derived edges clamp to them and keep the
 * bottom reserve; the layout is meant for ppd 22..26 and tests/tmg7_host_test.py checks that range.
 */
#include <stdbool.h>
#include <stdint.h>
#ifndef TIO_PPD_X10
#define TIO_PPD_X10 248 /* UNVERIFIED: 24.8 px per degree */
#endif
#define TIO_PX(mdeg) ((int)(((long long)(mdeg)*TIO_PPD_X10+5000)/10000))
#define TIO_EDGE(mdeg,limit) (TIO_PX(mdeg)>(limit)?(limit):TIO_PX(mdeg))

/* Hardware canvases (px): app page and menu. */
#define TIO_PAGE_W 540
#define TIO_PAGE_H 180
#define TIO_MENU_H 220

/* Reserved strips stay empty for the display-height and depth shift. */
#define TIO_RESERVE_TOP TIO_EDGE(484,TIO_PAGE_H)      /* 12 px: y 0..12 on pages and menu */
/* App page bands (540x180). Priority rises toward the bottom. */
#define TIO_RESERVE_BOTTOM TIO_PX(322)                /* 8 px: y 172..180 on pages, 212..220 on the menu */
#define TIO_PAGE_T0 TIO_RESERVE_TOP
#define TIO_PAGE_T1 TIO_EDGE(2258,TIO_PAGE_H-TIO_RESERVE_BOTTOM)  /* 56  */
#define TIO_PAGE_M1 TIO_EDGE(4516,TIO_PAGE_H-TIO_RESERVE_BOTTOM)  /* 112 */
#define TIO_PAGE_B1 TIO_EDGE(6935,TIO_PAGE_H-TIO_RESERVE_BOTTOM)  /* 172 */
/* Menu bands (540x220): status T, icon grid M, focused label B. */
#define TIO_MENU_T0 TIO_RESERVE_TOP
#define TIO_MENU_T1 TIO_EDGE(2258,TIO_MENU_H-TIO_RESERVE_BOTTOM)  /* 56  */
#define TIO_MENU_M1 TIO_EDGE(6935,TIO_MENU_H-TIO_RESERVE_BOTTOM)  /* 172 */
#define TIO_MENU_B1 TIO_EDGE(8548,TIO_MENU_H-TIO_RESERVE_BOTTOM)  /* 212 */

/* Horizontal zones. Primary text stays inside the core (binocular overlap). */
#define TIO_INSET_X TIO_PX(645)                       /* 16: glyph and ambient side inset */
#define TIO_CORE_X0 TIO_PX(1613)                      /* 40 */
#define TIO_CORE_X1 TIO_EDGE(20161,TIO_PAGE_W)        /* 500 */
#define TIO_CORE_W (TIO_CORE_X1-TIO_CORE_X0)          /* 460 */

/* Intensity ramp (green only; black is see-through). Track is never text. */
#define TIO_LENS_FULL  0x00ff00u /* band B, focused item, caret */
#define TIO_LENS_HIGH  0x00b000u /* band M, transient hint */
#define TIO_LENS_MID   0x007700u /* band T, unfocused items (18 px or larger only) */
#define TIO_LENS_TRACK 0x003800u /* tracks and dividers */

/* Type roles: angle (arcmin) -> px -> nearest stock vector font size already used by the
 * firmware (native menu_font: 16 18 20 24 32 48; TAP1 app.c accepts 16 18 20 24). 14 is retired. */
#define TIO_SNAP_FONT(px) ((px)<17?16:(px)<19?18:(px)<22?20:(px)<28?24:(px)<40?32:48)
#define TIO_FONT_HERO    TIO_SNAP_FONT(TIO_PX(1933)) /* 116' = 48 */
#define TIO_FONT_PRIMARY TIO_SNAP_FONT(TIO_PX(1283)) /* 77'  = 32 */
#define TIO_FONT_TITLE   TIO_SNAP_FONT(TIO_PX(967))  /* 58'  = 24 */
#define TIO_FONT_BODY    TIO_SNAP_FONT(TIO_PX(800))  /* 48'  = 20 */
#define TIO_FONT_LABEL   TIO_SNAP_FONT(TIO_PX(733))  /* 44'  = 18 */
#define TIO_FONT_MIN     TIO_SNAP_FONT(TIO_PX(650))  /* 39'  = 16: the floor */
#define TIO_TEXT_PAD 4                                /* text box = font + 4 (app.c rule) */
#define TIO_LINE(font) ((font)+TIO_TEXT_PAD)

/* Focus caret, progress track, motion. */
#define TIO_CARET_W TIO_PX(968)                       /* 24 */
#define TIO_CARET_H TIO_PX(121)                       /* 3  */
#define TIO_CARET_GAP TIO_PX(161)                     /* 4 px below the baseline */
#define TIO_RADIUS_XS TIO_PX(81)                      /* 2 */
#define TIO_TRACK_H TIO_PX(161)                       /* 4 */
#define TIO_GLYPH_MIN TIO_PX(968)                     /* 24: no pictogram smaller (about 1 deg) */
#define TIO_HINT_MS 3000u                             /* transient hint lifetime */
#define TIO_HINT_FADE_MS 300u                         /* fade-out, inside the 3000 */
#define TIO_MOVE_MS 160u                              /* focus and caret move (cubic ease-out) */
#define TIO_PAGE_MOVE_MS 120u                         /* page change */
#define TIO_MAP_BLEND_MS 180u
#define TIO_FOCUS_MAX 5u                              /* focusable items per page */

typedef enum {TIO_SURFACE_PAGE,TIO_SURFACE_MENU} TIOSurface;
typedef enum {TIO_RESERVED_TOP,TIO_BAND_T,TIO_BAND_M,TIO_BAND_B,TIO_RESERVED_BOTTOM} TIOBand;
typedef struct {int y0,y1;} TIOSpan; /* [y0,y1) */
typedef struct {int x,y,w,h;} TIORect;

static inline int tio_surface_h(TIOSurface s){return s==TIO_SURFACE_MENU?TIO_MENU_H:TIO_PAGE_H;}
static inline TIOSpan tio_band(TIOSurface s,TIOBand b){
 const bool menu=s==TIO_SURFACE_MENU;
 const int t1=menu?TIO_MENU_T1:TIO_PAGE_T1,m1=menu?TIO_MENU_M1:TIO_PAGE_M1,b1=menu?TIO_MENU_B1:TIO_PAGE_B1;
 switch(b){
  case TIO_RESERVED_TOP:return (TIOSpan){0,TIO_RESERVE_TOP};
  case TIO_BAND_T:return (TIOSpan){TIO_RESERVE_TOP,t1};
  case TIO_BAND_M:return (TIOSpan){t1,m1};
  case TIO_BAND_B:return (TIOSpan){m1,b1};
  default:return (TIOSpan){b1,tio_surface_h(s)};
 }
}
/* Band the vertical interval [y,y+h) lies wholly inside, or -1 if it straddles a boundary. */
static inline int tio_band_of(TIOSurface s,int y,int h){
 for(int b=TIO_RESERVED_TOP;b<=TIO_RESERVED_BOTTOM;b++){TIOSpan p=tio_band(s,(TIOBand)b);if(y>=p.y0&&y+h<=p.y1)return b;}
 return -1;
}
static inline bool tio_rect_in_band(TIOSurface s,TIOBand b,TIORect r){
 TIOSpan p=tio_band(s,b);return r.w>0&&r.h>0&&r.y>=p.y0&&r.y+r.h<=p.y1&&r.x>=0&&r.x+r.w<=TIO_PAGE_W;
}
static inline bool tio_rect_in_reserved(TIOSurface s,TIORect r){
 TIOSpan a=tio_band(s,TIO_RESERVED_TOP),z=tio_band(s,TIO_RESERVED_BOTTOM);
 return r.y<a.y1||r.y+r.h>z.y0;
}
static inline bool tio_rect_in_core(TIORect r){return r.x>=TIO_CORE_X0&&r.x+r.w<=TIO_CORE_X1;}
static inline bool tio_font_native(unsigned px){return px==16||px==18||px==20||px==24||px==32||px==48;}
static inline bool tio_font_tap(unsigned px){return px==16||px==18||px==20||px==24;}
/* Scale a green-only ramp color by alpha/255 (fades toward see-through black). */
static inline uint32_t tio_ui_scale(uint32_t color,unsigned alpha){
 unsigned g=(color>>8)&255u;return ((uint32_t)(g*(alpha>255u?255u:alpha)/255u))<<8;
}
#endif
