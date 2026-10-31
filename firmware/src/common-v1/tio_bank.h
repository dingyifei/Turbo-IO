#ifndef TIO_BANK_HEADER
#define TIO_BANK_HEADER
/* TMG9 canvas bank padding. The stock lv_init replaces the draw-buffer align_pointer_cb with "round up to 64" (0x10427cd1), and
 * lv_draw_buf_init draws from roundup64(buffer). A double-buffered canvas whose bank size is not a multiple of 64 therefore draws
 * bank 1 from the next 64 byte boundary, i.e. shifted (and wrapped) by 64 - size%64 bytes. Declare every banked canvas buffer as
 * _Alignas(64) uint8_t name[2][FM_BANK64(bytes)] and the pointer handed to the canvas is its own roundup64. */
#define FM_BANK64(n) ((((n)+63u)/64u)*64u)
#endif
