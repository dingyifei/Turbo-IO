#ifndef TURBO_FOCUS_VIEW_H
#define TURBO_FOCUS_VIEW_H
#include "focus.h"
#include "../navigation-runtime-v1/nav_view.h"
#include "../common-v1/tio_ui.h"
#include "../common-v1/tio_hint.h"
/* LensFocus (docs/design-system/screens/LensFocus.dc.html, halved), primary information lowest:
 * band T  phase title (lens-mid, 18 px), "n / 4" at the right, 4 px progress track under them;
 *         the control hint replaces the title and the count for TIO_HINT_MS after entry and input
 * band M  what comes next, or the paused / done / ready state (lens-high, 20 px)
 * band B  the remaining time (lens-full, 48 px)
 * No icon, no fixed footer. Geometry derives from tio_ui.h. */
#define TF_LABELS 4u
enum {TF_L_TITLE,TF_L_COUNT,TF_L_STATUS,TF_L_TIME};
#define TF_BAR_W TIO_CORE_W
#define TF_BAR_H TIO_TRACK_H
#define TF_TRACK_LEVEL (TIO_LENS_TRACK>>8&255u) /* canvas gray level = green channel */
#define TF_FILL_LEVEL (TIO_LENS_FULL>>8&255u)
typedef struct {TNWidgets api;void *root,*labels[TF_LABELS],*bar;char text[2][TF_LABELS][112];_Alignas(64) uint8_t bar_px[2][TF_BAR_W*TF_BAR_H];unsigned bank;bool open;TIOHint hint;uint32_t title_color;} TFView;
TIORect tf_title_rect(void);
TIORect tf_count_rect(void);
TIORect tf_bar_rect(void);
TIORect tf_status_rect(void);
TIORect tf_time_rect(void);
bool tf_view_open(TFView *,const TNWidgets *,void *,void *);
/* Page opened or re-shown, or a wheel / press happened: (re)start the 3 s control hint. */
void tf_view_enter(TFView *,uint32_t now);
void tf_view_input(TFView *,uint32_t now);
/* True when the hint colour changed since the last draw (the 250 ms tick redraws then). */
/* True while the control hint is lit or fading. */
bool tf_view_hint(const TFView *,uint32_t now);
bool tf_view_due(const TFView *,uint32_t now,bool compact);
bool tf_view_draw(TFView *,const TFocus *,bool compact,uint32_t now);
bool tf_view_close(TFView *);
#endif
