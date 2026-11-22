#ifndef TIO_LOCK_MOTION_WIRE_H
#define TIO_LOCK_MOTION_WIRE_H
/* The two neck-monitor messages the head-motion signal adds (docs/lock-design.md §7). Shared by the AP module
 * (lock-v1) and the Bluetooth-core module (bth-v1). Both ride stock's neck-monitor RPMsg envelope:
 * u16 type at +0, u16 zero at +2, u32 payload length at +4, payload at +8 (stock allocates 0x408 bytes).
 * Stock switches on the low byte of the type only; both types are free in both directions on 1.0.6.11
 * (re/M3-STATIC.md Q4: BTH rx table, AP rx table).
 *
 * AP to BTH, "motion on": type 0x0008, length 8, payload u32 magic + u32 on (0 or 1). Sent fire-and-forget after
 * the phone's MOTION_ON; the BTH stores on != 0 in its enable word and replies nothing. A message of this type with
 * any other length or magic goes to stock's "unsupported type" path, as it does on stock.
 * BTH to AP, "motion seen": type 0x0002, length 12, payload u64 BTH monotonic microseconds + f32 sigma. At most one
 * per 30 s, only while moving and only while enabled. */
#define TIO_MOTION_ON_TYPE 0x0008
#define TIO_MOTION_ON_LEN 8
#define TIO_MOTION_ON_MAGIC 0x314f4d54   /* "TMO1" */
#define TIO_MOTION_SEEN_TYPE 0x0002
#define TIO_MOTION_SEEN_LEN 12
#define TIO_NECK_MSG_BYTES 0x408         /* stock's envelope allocation */
#endif
