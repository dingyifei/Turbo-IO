#ifndef TIO_FIRMWARE_1055_PROFILE_H
#define TIO_FIRMWARE_1055_PROFILE_H
/* Confirmed from stock allocation callsites and constructors. This header
 * describes source layout only; it does not approve function bindings. */
#if defined(TD_STOCK_10611) && TD_STOCK_10611
#define TIO_STOCK_MENU_BYTES tio_not_ported_to_10611_menu_bytes
#else
#define TIO_STOCK_MENU_BYTES 0xfcu
#endif
#define TIO_STOCK_HEAD_BYTES 0x68u
#if defined(TD_STOCK_10611) && TD_STOCK_10611
#define TIO_MENU_SCROLL_POSITION_OFFSET tio_not_ported_to_10611_scroll_position
#define TIO_MENU_EXTERNAL_ACTION_OFFSET tio_not_ported_to_10611_external_action
#else
#define TIO_MENU_SCROLL_POSITION_OFFSET 0xb0u
#define TIO_MENU_EXTERNAL_ACTION_OFFSET 0xf0u
#endif
#define TIO_SYS_TIMEZONE_OFFSET 0x10u
#endif
