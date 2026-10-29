#ifndef TURBO_APP_VIEW_H
#define TURBO_APP_VIEW_H
#include "app.h"
// UI-thread-only adapter contract. Native glue must copy label text synchronously,
// create a hidden root, and destroy all children before returning from destroy.
typedef struct {
 void *ctx;
 bool (*idle)(void *);
 void *(*root)(void *,void *);
 void *(*text)(void *,void *,const char *,unsigned);
 void *(*rect)(void *,void *,uint32_t,bool outline); // outline: kind 5 frames only; focus no longer uses it
 void *(*image)(void *,void *,const uint8_t *,unsigned,unsigned);
 void (*place)(void *,void *,unsigned,unsigned,unsigned,unsigned);
 void (*visible)(void *,void *,bool);
 void (*destroy)(void *,void *);
 void (*tint)(void *,void *,uint32_t); // recolor a text label (lens ramp level); same UI-thread rules as place
} TAPWidgets;
// TMG7 FocusCaret (docs/design-system/components/FocusCaret): kind 2 buttons are text focus items, the focused one in
// lens-full with a 24x3 caret under its baseline, the others lens-mid (lens-high below 18 px). No outline, no fill.
#define TAP_CARET_W 24
#define TAP_CARET_H 3
typedef struct {
 TAPWidgets api;void *root,*focus; // focus: the caret canvas (hidden when the page has no button)
 void *buttons[12]; // kind 2 labels of the open page in wire order
 const TAPDocument *document;unsigned page,used,selected;
 bool retiring; // external parent destruction; pixels retained until render idle
 // Align absolute buffer addresses, not the struct: ordinary malloc on AP
 // is not guaranteed to return a 64-byte-aligned object.
 uint8_t pixels[32768+12*63+63];
 uint8_t caret[TAP_CARET_W*TAP_CARET_H+63]; // 64-byte aligned inside, outside the page image budget
} TAPView;
// Caller zero-initializes and owns TAPView. Input document/wire stay live.
// No hidden global instance, timers or allocations. Do not stack-allocate on AP.
bool tap_view_open(TAPView *,const TAPWidgets *,void *,const TAPDocument *,unsigned);
bool tap_view_focus(TAPView *,unsigned);
// Text size actually drawn for a wire size: 14 px is retired (decodes as before, draws at the 16 px floor).
unsigned tap_view_font(unsigned wire_font);
bool tap_view_close(TAPView *); // false: renderer busy, keep owner+pixels alive
// Native root DELETE callback, UI thread only. Do not free the owner here.
void tap_view_detached(TAPView *);
#endif
