#ifndef TIO_LOCK_OPTIONS_H
#define TIO_LOCK_OPTIONS_H
/* Test-only prototypes of a design-system lock screen (docs/design-system/screens/LensLock.dc.html, Options A, B and C).
 * Not part of the firmware build: build.py compiles only firmware/src, and this file lives under firmware/tests. The
 * shipped view (src/lock-v1/lock_view.c) is unchanged; these prototypes reuse its scene (TLVScene) and its text (they run
 * tlv_layout for the real EN and ZH strings) and draw through the same injected widget table (TNWidgets), so the host
 * layout gate renders them exactly as it renders every native page.
 *
 *  A  four slots in band B: the focused digit at lens-hero (48 px) with the caret under it, entered slots as dots,
 *     empty slots as lens-track bars.
 *  B  one digit in band B at lens-hero with its wheel neighbours at lens-primary in lens-mid, and a four-dot progress
 *     row at the bottom of band M (entered lens-high, current lens-full, empty lens-track).
 *  C  four slots as in A, but the focused digit is a drawn numeral (a 5 px stroke glyph, 34x50, like the turn arrows)
 *     instead of a font size, so it is as tall as band B allows with the caret under it.
 *
 * Every state other than PIN entry uses one layout in all three options: band M at lens-body / lens-high, band B at
 * lens-primary / lens-full, both centred. Band T of the PIN screen shows the time (left) and battery (right) at lens-mid;
 * the hint replaces them for 3 s (tio_hint.h, with its fade) after the screen opens and after every input.
 * All canvas buffers are 64-byte aligned (the stock draw buffer rounds the pointer up to 64). */
#include "../src/lock-v1/lock_view.h"
#include "../src/common-v1/tio_ui.h"
#include "../src/common-v1/tio_hint.h"
#include "../src/common-v1/tio_caret.h"
enum {LO_A,LO_B,LO_C,LO_OPTIONS};
/* Labels, then canvases. LO_DIGIT is the focused digit (A and B); LO_PREV and LO_NEXT are B's wheel neighbours. */
enum {LO_HINT,LO_TIME,LO_BATT,LO_M,LO_BTEXT,LO_DIGIT,LO_PREV,LO_NEXT,LO_LABELS};
enum {LO_CARET,LO_DOT0,LO_TRACK0=LO_DOT0+TLK_PIN_LEN,LO_GLYPH=LO_TRACK0+TLK_PIN_LEN,LO_CANVASES};
/* Geometry (px, 540x180 page). */
enum {
 LO_PITCH=80,LO_SLOT_W=48,                        /* A and C: slot pitch and slot box */
 LO_DIGIT_Y=114,                                  /* A and B: the 48 px digit box (box 52), caret 4 px under its baseline */
 LO_DOT=10,LO_DOT_B=12,LO_B_PITCH=28,LO_B_ROW_Y=90, /* entered dots (A, C) and B's progress dots */
 LO_NEIGHBOUR_DX=72,                              /* B: wheel neighbours either side of the digit */
 LO_GLYPH_W=34,LO_GLYPH_H=50,LO_GLYPH_Y=114,LO_GLYPH_STROKE=5,   /* C: the drawn numeral */
 LO_TRACK_W=TIO_CARET_W,LO_TRACK_H=TIO_CARET_H,
 LO_MSG_M_Y=80,LO_MSG_B_Y=126                     /* the other states: band M and band B rows */
};
typedef struct {
 TNWidgets api;void *root,*labels[LO_LABELS],*canvas[LO_CANVASES];
 unsigned option;TLKView text;TIOHint hint;TIOCaret caret;TLKState last;bool open;
 char digit[3][4];
 unsigned align[LO_LABELS];     /* what the native side would set with menu_text_align: 0 left, 1 centre, 2 right */
 int glyph_digit;
 _Alignas(64) uint8_t glyph[LO_GLYPH_W*LO_GLYPH_H];
} LOView;
bool lo_open(LOView *,unsigned option,const TNWidgets *,void *surface,void *parent);
/* Wheel turn or press on the PIN screen: re-shows the hint (TransientHint). */
void lo_input(LOView *,uint32_t now_ms);
bool lo_draw(LOView *,const TLVScene *,unsigned lang,uint32_t now_ms);
void lo_close(LOView *);
/* The drawn numeral's strokes in glyph pixels: up to 4 polylines of up to 24 points; returns the polyline count. */
typedef struct {unsigned n;float x[24],y[24];} LOLine;
unsigned lo_glyph_lines(unsigned digit,LOLine out[4]);
/* Slot centre x (A and C) and B's progress dot centre x. */
static inline int lo_slot_cx(unsigned i){return (TIO_PAGE_W-(TLK_PIN_LEN-1)*LO_PITCH)/2+(int)i*LO_PITCH;}
static inline int lo_row_cx(unsigned i){return (TIO_PAGE_W-(TLK_PIN_LEN-1)*LO_B_PITCH)/2+(int)i*LO_B_PITCH;}
#endif
