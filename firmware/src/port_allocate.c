#include <stddef.h>
#include "navigation-runtime-v1/menu9.h"
extern void *port_stock_new(size_t);
/* Replaces exactly mov.w r0,#stock_size (4 bytes on 1.0.6.11) + BL operator new. The caller resumes
 * before mov r6,r0, preserving its allocation-failure and constructor paths. The block is the stock object plus the
 * module's tail; the words past the stock object are pre-filled so m8_hook_ctor can see whether the real constructor
 * wrote past TIO_STOCK_MENU_BYTES before it arms the tail (menu9.h). NULL passes through. */
void *port_allocate_menu(void){
    void *app=port_stock_new(TIO_TAIL_END);
    if(app)m8_tail_fill(app);
    return app;
}
