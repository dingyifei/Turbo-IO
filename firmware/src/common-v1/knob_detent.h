#ifndef TIO_KNOB_DETENT_H
#define TIO_KNOB_DETENT_H
/* The one accessor for the live knob detent D (TMG9): raw counts per item, 300..600 in steps of 50 (TIO_WHEEL_DETENT_*, tio_ui.h).
 * The main menu hook, the page input (wheel_input.h), the music input (music_input.h) and the remote's injected step all read it here, so
 * a change from the phone moves every list at once. It is 400 (TIO_WHEEL_DETENT_DEFAULT) when no menu record is stored or the control state
 * does not exist yet, and otherwise the D stored in the menu file (TMC2 byte 6, menu-grid-v2/menu_config.h tml_detent). The result is always
 * a valid D. Defined in global-remote-v1/remote_native.c; host tests define their own. */
unsigned tio_knob_detent(void);
#endif
