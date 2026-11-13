#ifndef TDP_NATIVE_DISPLAY_PAGE_H
#define TDP_NATIVE_DISPLAY_PAGE_H
#include "display_runtime.h"
typedef struct TDPNativePage TDPNativePage;
/* UI executor only. Caller must authenticate/pin the paired source BEFORE
 * dispatching. No receive-thread access to this object is permitted. */
TDPNativePage *tdp_native_open(void *parent,uint32_t sid,TDPNativePage **owner);
void tdp_native_retire(TDPNativePage *);
TDPResult tdp_native_receive(TDPNativePage *,const uint8_t *,size_t);
/* Forward a knob wheel delta and/or press to the open page (UI executor). The first press opens the read-only Sensors screen. */
void tdp_native_knob(TDPNativePage *,int32_t delta,bool press);
/* Never call after retire; timer owns deferred destruction. */
#endif
