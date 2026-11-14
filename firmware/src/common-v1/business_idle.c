#if defined(TD_STOCK_10611) && TD_STOCK_10611
#error not ported to 1.0.6.11 yet: launcher +0x3c
#endif
#include "business_idle.h"
#include "../camera-v1/camera_native.h"
#include <stdint.h>
extern bool ce_extension_idle(void);
static void *ptr(void *p,unsigned offset){return p?*(void **)((uint8_t *)p+offset):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x199595d4,0x3c);}
bool tio_business_idle(void){return ce_extension_idle()&&!tc_native_visible(ptr(manager(),0x10));}
