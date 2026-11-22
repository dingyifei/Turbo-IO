#ifndef TIO_LOCK_ANCHOR_H
#define TIO_LOCK_ANCHOR_H
/* Where the lock's heap state is found (the module has no .data or .bss).
 * - UI thread: the lock's own LVGL timer, found by scanning the timer list (the remote's pattern).
 * - Any thread: a pass-through node at the head of stock's input-interceptor list (RAM word tio_key_interceptors).
 *   Stock touches node bytes 0..0xf only (dispatch, register, unregister are the only users of the head) and never
 *   clears the head, so our fields from 0x10 survive. The node's handler always answers "not consumed".
 * build/re/ANCHOR.md holds the evidence. */
#include <stdbool.h>
#include <stdint.h>
void *lock_anchor_ui(void (*tick)(void *));   /* UI thread only */
void *lock_anchor_any(void);                  /* any thread; NULL when the head node is not ours */
void *lock_anchor_find(void);                 /* UI thread; our node anywhere in the list (bounded walk), else NULL */
bool lock_anchor_install(void *state);        /* UI thread; idempotent; false when the node could not be made */
bool lock_anchor_present(const void *state);  /* the head node is ours and points at state */
#endif
