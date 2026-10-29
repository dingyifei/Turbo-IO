#ifndef TURBO_APP_SHELF_H
#define TURBO_APP_SHELF_H
#include "app_runner.h"
// Reuses the single runner's buffers. Never allocates a second 33 KiB view.
// Caller scans the store first. Shelf buttons emit component 1..4 => slot 0..3.
bool tap_shelf_open(TAPRunner *);
/* The generated TAP1 document (also used by the layout gate); returns its byte count. */
size_t tap_shelf_wire(uint8_t *,const TAPStore *,unsigned lang);
#endif
