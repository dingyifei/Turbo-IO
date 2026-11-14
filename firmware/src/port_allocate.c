#include <stddef.h>
#include "menu8-native-carousel.h"
extern void *port_stock_new(size_t);
/* Replaces exactly mov.w r0,#stock_size (4 bytes on 1.0.6.11) + BL operator new. The caller resumes
 * before mov r6,r0, preserving its allocation-failure and constructor paths. */
void *port_allocate_menu(void){
    return port_stock_new(TIO_STOCK_MENU_BYTES+sizeof(M8NativeTail));
}
