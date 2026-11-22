#ifndef TIO_LOCK_VIEW_H
#define TIO_LOCK_VIEW_H
// The glasses lock screens (docs/lock-design.md §3): PIN entry, wrong PIN, waiting, use phone, failure notice.
// Pure: drawn through the injected widget table, so it is host-tested with a fake one.
#include "lock_core.h"
#include "../navigation-runtime-v1/nav_view.h"
enum {TLV_T,TLV_M,TLV_B,TLV_S0,TLV_S1,TLV_S2,TLV_S3,TLV_CARET,TLV_LABELS};
enum {TLV_TEXT=48,TLV_HINT_MS=3000};
typedef struct {
 TNWidgets api;void *root,*labels[TLV_LABELS];
 char text[2][TLV_LABELS][TLV_TEXT];unsigned bank;
 uint32_t colors[TLV_LABELS];
 uint32_t entry_ms;TLKState last_state;bool open;
} TLKView;
// What the view shows; filled from the lock state by tlv_snapshot.
typedef struct {TLKState state;uint8_t slot,digit,notice,wrong;uint32_t delay_left,now_ms;} TLVScene;
void tlv_snapshot(TLVScene *,TLK *,uint32_t now_s,uint32_t now_ms);
bool tlv_open(TLKView *,const TNWidgets *,void *surface,void *parent);
// Fills text and colors for a scene (pure, no widget calls); returns true if anything differs from what is shown.
bool tlv_layout(TLKView *,const TLVScene *,unsigned lang);
bool tlv_draw(TLKView *,const TLVScene *,unsigned lang);
void tlv_close(TLKView *);
#endif
