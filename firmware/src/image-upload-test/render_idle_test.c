#include "render_idle.h"
#include <assert.h>
#include <stdio.h>
static uint32_t gpu=0,sw=0,task=0,gpu_dispatch=0x10462225;
static bool cycle_unit,cycle_layer,cycle_display,fail_read;
static bool read(uint32_t p,uint32_t *v){
 if(fail_read)return false;
 switch(p){
 /* The unit list head render_idle.c reads: the LVGL global (rebase table value display_unit) plus
  * TIO_STOCK_LVGL_DRAW_UNITS. The other keys are fake draw units, a display and a layer at not-stock bases plus the
  * stock_layout.h field names render_idle.c reads. */
 case 0x1850ce1c+TIO_STOCK_LVGL_DRAW_UNITS:*v=0x19000000;return true;
 case 0x19000000+TIO_STOCK_DRAW_UNIT_NEXT:*v=0x19000100;return true;
 case 0x19000000+TIO_STOCK_DRAW_UNIT_DISPATCH:*v=gpu_dispatch;return true;
 case 0x19000000+TIO_STOCK_DRAW_UNIT_TASK:*v=gpu;return true;
 case 0x19000100+TIO_STOCK_DRAW_UNIT_NEXT:*v=cycle_unit?0x19000000:0;return true;
 case 0x19000100+TIO_STOCK_DRAW_UNIT_DISPATCH:*v=0x105700ef;return true;
 case 0x19000100+TIO_STOCK_DRAW_UNIT_TASK:*v=sw;return true;
 case 0x19100000+TIO_STOCK_DISPLAY_LAYERS:*v=0x19200000;return true;
 case 0x19200000+TIO_STOCK_LAYER_TASKS:*v=task;return true;
 case 0x19200000+TIO_STOCK_LAYER_NEXT:*v=cycle_layer?0x19200000:0;return true;
 default:return false;
 }
}
static uint32_t next(uint32_t p){return !p||cycle_display?0x19100000:0;}
int main(void){
 assert(tio_render_graph_idle(read,next));
 gpu=1;assert(!tio_render_graph_idle(read,next));gpu=0;
 sw=1;assert(!tio_render_graph_idle(read,next));sw=0;
 task=1;assert(!tio_render_graph_idle(read,next));task=0;
 gpu_dispatch=123;assert(!tio_render_graph_idle(read,next));gpu_dispatch=0x10462225;
 cycle_unit=true;assert(!tio_render_graph_idle(read,next));cycle_unit=false;
 cycle_layer=true;assert(!tio_render_graph_idle(read,next));cycle_layer=false;
 cycle_display=true;assert(!tio_render_graph_idle(read,next));cycle_display=false;
 fail_read=true;assert(!tio_render_graph_idle(read,next));fail_read=false;
 assert(tio_render_graph_idle(read,next));
 puts("PASS conservative renderer graph: GPU/SW active, pending tasks, unknown units, failed reads and cycles reject");
}
