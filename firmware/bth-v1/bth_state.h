#ifndef TIO_BTH_STATE_H
#define TIO_BTH_STATE_H
/* The head-motion module's state on the Bluetooth core (nuttx_bth.bin, stock 1.0.6.11): 24 bytes of BTH RAM,
 * [0x2304e528, 0x2304e540), directly above stock's .bss. No stock code, pool or data word points into it
 * (re/M3-STATIC.md, Block E e2-img.md §2); the next referenced address is 0x2304e540. The build moves stock's
 * .bss clear-end literal from 0x2304e528 to 0x2304e540 (edit "Hook state cleared at boot"), so stock's own reset
 * path zeroes these words at every boot: the hook is off after every boot and nothing is ever stored. */
#ifndef BTH_STATE_HOST   /* the host test (tests/bth_motion_test.c) puts the state in its own memory */
#define BTH_STATE_START 0x2304e528
#define BTH_LAST_SEND 0x2304e528   /* u64: BTH CLOCK_MONOTONIC microseconds of the last "motion seen" sent; 0 = none yet */
#define BTH_ENABLE 0x2304e530      /* u32: 0 = off (stock behaviour), 1 = on; written only by the rx hook */
#define BTH_PREV 0x2304e534        /* 3 x f32: the previous window's latest accel sample; NaN = none (set at "on") */
#define BTH_PREV_1 0x2304e538
#define BTH_PREV_2 0x2304e53c
#define BTH_STATE_END 0x2304e540
#endif
#define BTH_PREV_NAN 0x7fc00000    /* the f32 quiet NaN the rx hook writes into BTH_PREV at every "on" */
#endif
