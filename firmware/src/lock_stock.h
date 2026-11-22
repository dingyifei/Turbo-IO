#ifndef TIO_LOCK_STOCK_H
#define TIO_LOCK_STOCK_H
/* Stock 1.0.6.11 functions and data the PIN lock (lock-v1) calls or reads. Each name is a link.ld symbol that entered the
   tree through the rebase table (REVIEWED_UNIVERSE_CHANGES addLinkld in tools/rebase_derive.py, addedCode/addedRam in
   tests/rebase_independent_test.py). Behaviour notes come from the static lock RE (SYMBOLS.md, HOOKS.md); nothing here
   was checked on a device. The entry-trampoline gates (trampolines.S, lock_hook_*) call the lock_refuse_* and
   lock_on_factory_reset functions declared at the end; lock-v1 defines them. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Head word of stock's LVGL input interceptor list (RAM; NULL or the first node {const char *name, int (*handler)(void *),
   uint8_t last result, next}). The keypad read walks it from the head on the LVGL thread with no lock. */
extern void *volatile tio_key_interceptors;

/* SysStateMonitor helper: timegm() of the PMU RTC, UTC seconds; 0 when the read or the conversion fails. A failed PMU
   read can also give a far-future value (tm_year 63636), so callers bound the result. */
extern int64_t pmu_rtc_epoch(void);

/* AssistantService voice wakeup enable / disable (no result). Stock re-enables the wake word on every RUNNING entry. */
extern void kws_enable(void);
extern void kws_disable(void);

/* Frees every queued button event and clears the gesture press state, including the factory-reset prepare byte of a
   five-press in progress. Stock calls it once at app start. */
extern void key_queue_flush(void);

/* read(fd, buf, len) on a uORB topic fd (the rayneo wheel reader's sensor_ots subscription; 16-byte records). */
extern int ots_topic_read(int fd, void *buf, size_t len);

/* The RayNeo keypad and wheel read callbacks (LVGL indev read_cb, void f(lv_indev_t *, lv_indev_data_t *)) are
   entry-patched: every call, from the indev slot or chained by NavigationWheelCapture, enters lock_hook_key_read /
   lock_hook_wheel_read, which call stock_key_read / stock_wheel_read (trampolines.S) to run stock. */
void lock_hook_key_read(void *indev, void *data);
void lock_hook_wheel_read(void *indev, void *data);
extern void stock_key_read(void *indev, void *data);
extern void stock_wheel_read(void *indev, void *data);

/* Entry-trampoline gates (trampolines.S). Return true to refuse the stock call. */
bool lock_refuse_can_wakeup(void);
bool lock_refuse_open_remote_audio(void);
bool lock_refuse_open_recorder(void);
/* Runs with the screen controller mutex held: read lock state only, never call a screen or nav function. */
bool lock_refuse_screen(uint32_t new_state, uint32_t source);
/* Entry of the factory-reset worker (LVGL timer callback, UI thread). Stock arms it only after the ERPC reset reported
   success, past every refusal check; the five-press + hold reset reaches it. Not reached: the phone's clear-all-data
   reset (mode 2, applied after unbind) unless it goes through the same ERPC reset. */
void lock_on_factory_reset(void);

#endif
