#ifndef TIO_FIRMWARE_PROFILE_H
#define TIO_FIRMWARE_PROFILE_H
/* Seen by every firmware compile (build.py force-includes this file). Stock layout facts live in stock_layout.h. */
#include "stock_layout.h"
/* Stock LauncherService object pointer, a RAM global named in link.ld (rebase table linkld row). */
#ifndef __ASSEMBLER__
extern void *tio_launcher_global;
#endif
#endif
