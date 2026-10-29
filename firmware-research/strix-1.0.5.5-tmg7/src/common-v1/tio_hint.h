#ifndef TIO_HINT_HEADER
#define TIO_HINT_HEADER
/* TransientHint (docs/design-system/components/TransientHint): a one-line control hint in
 * band T at lens-high. Shown when a page opens and on every wheel or press input, hidden
 * TIO_HINT_MS (3000 ms) after the latest of those. The last TIO_HINT_FADE_MS are an eight-step
 * fade (inside the 3000, so nothing is lit at 3000 ms). It replaces the fixed footers at
 * {16,~150,508,24}; it never occupies band B. While shown it replaces any ambient band-T text,
 * which returns afterwards (tio_hint_ambient). Pure state: the page timer calls tio_hint_poll()
 * and updates its label only when it returns true. Wrap-safe (unsigned 32-bit milliseconds). */
#include "tio_ui.h"
#define TIO_HINT_STEPS 8u
#define TIO_HINT_FONT TIO_FONT_LABEL
#define TIO_HINT_MAX_WORDS_EN 7u
typedef struct {uint32_t since,color;bool armed,entry_only,reduce_motion;} TIOHint;
static inline void tio_hint_init(TIOHint *h){h->since=0;h->color=0;h->armed=false;h->entry_only=false;h->reduce_motion=false;}
/* Page opened. */
static inline void tio_hint_enter(TIOHint *h,uint32_t now){h->since=now;h->armed=true;}
/* Wheel or press. After the wearer has seen the hint three times the phone sets entry_only
 * (phone-side counter, no wire change) and input no longer re-shows it. */
static inline void tio_hint_input(TIOHint *h,uint32_t now){if(!h->entry_only){h->since=now;h->armed=true;}}
/* Alpha 0..255 at `now`: 255 until the fade starts, then eight steps down, 0 from 3000 ms. */
static inline unsigned tio_hint_alpha(const TIOHint *h,uint32_t now){
 if(!h->armed)return 0;
 uint32_t e=now-h->since;
 if(e>=TIO_HINT_MS)return 0;
 if(h->reduce_motion||e<TIO_HINT_MS-TIO_HINT_FADE_MS)return 255;
 unsigned step=(unsigned)((e-(TIO_HINT_MS-TIO_HINT_FADE_MS))*TIO_HINT_STEPS/TIO_HINT_FADE_MS);
 return 255u*(TIO_HINT_STEPS-step)/TIO_HINT_STEPS;
}
static inline bool tio_hint_visible(const TIOHint *h,uint32_t now){return tio_hint_alpha(h,now)!=0;}
/* True when the ambient band-T text should show (the hint is not covering it). */
static inline bool tio_hint_ambient(const TIOHint *h,uint32_t now){return !tio_hint_visible(h,now);}
static inline uint32_t tio_hint_color(const TIOHint *h,uint32_t now){return tio_ui_scale(TIO_LENS_HIGH,tio_hint_alpha(h,now));}
/* Timer hook: true when the label color changed since the last poll (update the widget then). */
static inline bool tio_hint_poll(TIOHint *h,uint32_t now,uint32_t *color){
 uint32_t c=tio_hint_color(h,now);if(c==h->color)return false;h->color=c;if(color)*color=c;
 if(!c)h->armed=false;return true;
}
/* One line of lens-label in band T, across the core zone. */
static inline TIORect tio_hint_rect(TIOSurface s){
 TIOSpan t=tio_band(s,TIO_BAND_T);int h=TIO_LINE(TIO_HINT_FONT);
 return (TIORect){TIO_CORE_X0,t.y0+(t.y1-t.y0-h)/2,TIO_CORE_W,h};
}
#endif
