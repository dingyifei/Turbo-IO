#ifndef TIO_LOCK_VIEW_H
#define TIO_LOCK_VIEW_H
/* The glasses lock screens (docs/lock-design.md §3; board docs/design-system/screens/LensLock.dc.html): PIN entry, wrong
 * PIN, waiting, use phone, failure notice, Unlocked. Drawn through the injected widget table, so it is host-tested with a
 * fake one and rendered by the layout gate (firmware/tests/tmg7_layout_preview.m, Lock) exactly as on the glasses.
 *
 * PIN entry (TMG16): four slots in band B, 80 px apart and centred on the page. The focused slot shows the digit as a
 * drawn numeral (34x50 px, 5 px round strokes, lens-full; tables in lock_glyphs.h, made by tools/lock_glyphs.py), as tall
 * as band B allows above the system caret (tio_caret.h, 24x3, lens-full, 4 px under the glyph). Entered slots are 10 px
 * lens-high dots at the glyph's middle; empty slots are 24x3 lens-track bars on the caret's row. Shapes, never text.
 * Band T: the time (left) and battery (right) at lens-label in lens-mid; the transient hint (tio_hint.h, lens-high, with
 * its fade) replaces them for 3 s after the screen opens and after every wheel step or press (a new digit or slot).
 * Every other state: band M one line of lens-body in lens-high, band B one line of lens-primary in lens-full, centred.
 *
 * Every canvas buffer below is 64-byte aligned: the stock draw rounds a canvas buffer pointer up to 64 (tio_bank.h), so the
 * owner of a TLKView must allocate it 64-byte aligned (stream_memalign(64, ...)). */
#include "lock_core.h"
#include "../common-v1/tio_ui.h"
#include "../common-v1/tio_hint.h"
#include "../common-v1/tio_caret.h"
#include "../navigation-runtime-v1/nav_view.h"
/* Labels, then canvases. A dot and a track bar per slot; one glyph (the focused slot). */
enum {TLV_HINT,TLV_TIME,TLV_BATT,TLV_M,TLV_B,TLV_LABELS};
enum {TLV_CARET,TLV_DOT0,TLV_TRACK0=TLV_DOT0+TLK_PIN_LEN,TLV_GLYPH=TLV_TRACK0+TLK_PIN_LEN,TLV_CANVASES};
enum {TLV_TEXT=48,TLV_STATUS_W=64};
/* Geometry (px on the 540x180 page). */
enum {
 TLV_PITCH=80,                                        /* slot centre to slot centre */
 TLV_GLYPH_W=34,TLV_GLYPH_H=50,TLV_GLYPH_STROKE=5,     /* the drawn numeral */
 TLV_GLYPH_Y=114,                                     /* glyph top: band B starts at 112 */
 TLV_CARET_Y=TLV_GLYPH_Y+TLV_GLYPH_H+TIO_CARET_GAP,   /* 168: caret and empty-slot bars, bottom row 170 < 172 */
 TLV_DOT=10,TLV_DOT_CY=TLV_GLYPH_Y+TLV_GLYPH_H/2,      /* entered dot and its centre row */
 TLV_MSG_M_Y=80,TLV_MSG_B_Y=126                       /* the other states: band M and band B rows */
};
_Static_assert(TLV_CARET_Y+TIO_CARET_H<=TIO_PAGE_B1&&TLV_GLYPH_Y>=TIO_PAGE_M1,"the PIN slots fit band B");
/* Slot i's centre x. */
static inline int tlv_slot_cx(unsigned i){return (TIO_PAGE_W-(TLK_PIN_LEN-1)*TLV_PITCH)/2+(int)i*TLV_PITCH;}
/* One drawn state: label text and colour, canvas place and visibility, the glyph's digit (-1 none). */
typedef struct {
 char text[TLV_LABELS][TLV_TEXT];uint32_t color[TLV_LABELS];
 int16_t x[TLV_CANVASES],y[TLV_CANVASES];bool on[TLV_CANVASES];
 int8_t digit;
} TLVFrame;
typedef struct {
 _Alignas(64) uint8_t glyph[TLV_GLYPH_W*TLV_GLYPH_H];          /* the focused digit, decoded from lock_glyphs.h */
 _Alignas(64) uint8_t caret_px[TIO_CARET_W*TIO_CARET_H];       /* lens-full */
 _Alignas(64) uint8_t track_px[TIO_CARET_W*TIO_CARET_H];       /* lens-track */
 _Alignas(64) uint8_t dot_px[TLV_DOT*TLV_DOT];                 /* lens-high, anti-aliased disc */
 TNWidgets api;void *root,*labels[TLV_LABELS],*canvas[TLV_CANVASES];
 TLVFrame shown,next;   /* labels point into shown.text; next is what tlv_layout computed */
 bool drawn;            /* shown has been applied once */
 TIOHint hint;TIOCaret caret;
 TLKState last_state;uint8_t last_slot,last_digit;
 int8_t glyph_digit;    /* the digit decoded into glyph (-1 none); kept while the glyph is hidden */
 bool open;
} TLKView;
// What the view shows; filled from the lock state by tlv_snapshot.
// local: local time in seconds (stock's system monitor; shown when 2000..2100, else --:--); battery: 0..100, else --%.
typedef struct {TLKState state;uint8_t slot,digit,notice,wrong;uint32_t delay_left,now_ms;int64_t local;int battery;} TLVScene;
// Fills the lock part; time and battery are unknown (0 and -1) until the caller sets them.
void tlv_snapshot(TLVScene *,TLK *,uint32_t now_s,uint32_t now_ms);
// Needs every widget call the canvases use (canvas, buffer, visible); false if any is missing or a widget cannot be made.
bool tlv_open(TLKView *,const TNWidgets *,void *surface,void *parent);
// Computes the next frame for a scene into v->next (no widget calls; advances the hint and caret state); returns true if
// anything differs from what is shown.
bool tlv_layout(TLKView *,const TLVScene *,unsigned lang);
bool tlv_draw(TLKView *,const TLVScene *,unsigned lang);
void tlv_close(TLKView *);
/* The canvas buffers, for the alignment checks of the host tests. */
static inline const uint8_t *tlv_canvas_pixels(const TLKView *v,unsigned i){
 return i==TLV_CARET?v->caret_px:i==TLV_GLYPH?v->glyph:i<TLV_TRACK0?v->dot_px:v->track_px;
}
#endif
