/* Head-motion module for the Bluetooth core (nuttx_bth.bin, stock 1.0.6.11). build.py links it at the stock image's
 * end minus its 8-byte trailer (code view 0x0c131620; build-inputs.json bth.moduleVA) and checks the first bytes at
 * every stock address below against build-inputs.json bth.stockSymbols. Code addresses carry the Thumb bit.
 * The module has no writable data: its state is the fixed BTH RAM in bth_state.h. */
bth_clock_gettime = 0x0c034711;     /* clock_gettime(clk, ts) */
bth_neck_alloc = 0x0c04bbb9;        /* the allocator stock's neck senders call with (0x408, 1) */
bth_free = 0x0c04bbe1;              /* the free stock's neck senders call when a send fails */
bth_neck_send = 0x0c0aac1d;         /* neck-monitor send to the AP: queue the message, 0 when queued */
bth_rx_resume = 0x0c0aa95d;         /* rx switch: the bhi after cmp r2,#0x37 */
bth_rx_unsupported = 0x0c0aa99b;    /* rx switch: log "Unsupported ... type: %d" (r2), return 0 */
bth_rx_done = 0x0c0aa9a5;           /* rx switch: the common epilogue (add sp,#0xc; pop {r4,r5,pc}) */

SECTIONS {
 .text BTH_MODULE_VA : {
  __bth_module_start = .;
  *(.text.bth_entry) *(.text*) *(.rodata*)
  . = ALIGN(4);
  __bth_module_end = .;
 }
 .data : { *(.data*) }
 .bss : { *(.bss*) *(COMMON) }
 /DISCARD/ : { *(.comment) *(.ARM.attributes) *(.ARM.exidx*) *(.ARM.extab*) }
}
ASSERT(SIZEOF(.data) == 0 && SIZEOF(.bss) == 0, "the BTH module has no writable data")
