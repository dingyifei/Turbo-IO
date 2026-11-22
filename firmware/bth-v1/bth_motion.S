@ Head-motion module for the Bluetooth core (nuttx_bth.bin, stock 1.0.6.11): the two entry stubs.
@ docs/lock-design.md §7. Appended at the stock image's end (bth_link.ld); reached only from the two patched sites.
#include "bth_state.h"
#include "lock_motion_wire.h"

.syntax unified
.thumb
.section .text.bth_entry,"ax"

@ Neck-monitor RPMsg receive switch (stock gap_0c0aa928, the "NECK_MONITOR_RPMSG_EPT_NAME" endpoint callback,
@ run by the BTH rptun thread). The B.W at 0x0c0aa958 replaces `ldrb r2,[r4]; cmp r2,#0x37` (bytes 22 78 37 2a).
@ State there: stock has checked data != NULL, received >= 8, msg->len <= 0x400 and msg->len + 8 <= received;
@ r4 = msg; the frame is push {r4,r5,lr} + sub sp,#0xc; the log call just before (bl 0x0c04aa34) left nothing live
@ in r0-r3. Any type but 0x08 takes the stock path with r2 and the flags exactly as stock leaves them.
.balign 4
.global bth_rx_hook
.type bth_rx_hook,%function
.thumb_func
bth_rx_hook:
    ldrb    r2, [r4]                    @ stock: the type's low byte
    cmp     r2, #TIO_MOTION_ON_TYPE
    beq     1f
    cmp     r2, #0x37                   @ stock: the switch bound; the B.W keeps these flags for stock's bhi
    b.w     bth_rx_resume               @ 0x0c0aa95c
1:  ldr     r3, [r4, #4]                @ msg->len (stock has bounded it: msg->len + 8 <= received)
    cmp     r3, #TIO_MOTION_ON_LEN
    bne     2f
    ldr     r3, [r4, #8]
    ldr     r1, =TIO_MOTION_ON_MAGIC
    cmp     r3, r1
    bne     2f
    ldr     r3, [r4, #12]               @ on
    cmp     r3, #0
    it      ne
    movne   r3, #1
    ldr     r1, =BTH_ENABLE
    str     r3, [r1]                    @ the one store; no call, no wait (the rptun thread serves every endpoint)
    movs    r0, #0                      @ consumed, as stock returns for a handled type
    b.w     bth_rx_done                 @ 0x0c0aa9a4: add sp,#0xc; pop {r4,r5,pc}
2:  b.w     bth_rx_unsupported          @ 0x0c0aa99a: stock logs "Unsupported ... type: %d" with r2 = 8, returns 0
.ltorg

@ Neck-monitor main loop (stock FUN_0c0bfa40): the BL at 0x0c0bfe30 to clock_gettime (bytes 74 f7 6e fc), the call
@ right after each window's batch read, now calls this. Entry: r0 = 1 (CLOCK_MONOTONIC), r1 = &ts, lr = 0x0c0bfe35,
@ sp 8-aligned at a call site. Off: tail-branch to clock_gettime with r0, r1, lr and sp untouched, so the call is
@ stock's (r2 is caller-saved and stock clobbers it in the call anyway). On: the body runs clock_gettime first and
@ returns its result; r2 carries the caller's sp (the window's batch is at caller sp + 0xf0).
.balign 4
.global bth_motion_hook
.type bth_motion_hook,%function
.thumb_func
bth_motion_hook:
    ldr     r2, =BTH_ENABLE
    ldr     r2, [r2]
    cbnz    r2, 1f
    b.w     bth_clock_gettime           @ 0x0c034710
1:  mov     r2, sp
    b.w     bth_motion_body
.ltorg
