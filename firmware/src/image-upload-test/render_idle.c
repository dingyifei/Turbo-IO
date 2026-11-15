#include "render_idle.h"
/* Stock addresses on the tree's base, each a value of the active rebase table or read from the image, and each checked
 * by tests/stock_layout_test.py: the LVGL global (table display_unit), the dispatch callbacks of stock's two draw
 * units (table render_dispatch_gpu and render_dispatch_sw), and the RAM bounds (the .data copy destination and the
 * end of stock's heap region). */
#define IDLE_LVGL_GLOBAL 0x1850ce1c
#define IDLE_DISPATCH_GPU 0x10462225
#define IDLE_DISPATCH_SW 0x105700ef
#define IDLE_RAM_START 0x18000000
#define IDLE_RAM_END 0x1b600000
static bool ram(uint32_t p,uint32_t extent){
 return !(p&3)&&p>=IDLE_RAM_START&&p<=IDLE_RAM_END-extent;
}
bool tio_render_graph_idle(TIOReadWord read,TIONextDisplay next){
 uint32_t unit=0;unsigned count=0;
 if(!read||!next||!read(IDLE_LVGL_GLOBAL+TIO_STOCK_LVGL_DRAW_UNITS,&unit)||!unit)return false;
 while(unit){
  uint32_t dispatch=0,active=0,n=0;
  if(++count>8||!ram(unit,TIO_STOCK_DRAW_UNIT_BYTES)||!read(unit+TIO_STOCK_DRAW_UNIT_DISPATCH,&dispatch)||
     (dispatch!=IDLE_DISPATCH_GPU&&dispatch!=IDLE_DISPATCH_SW)||
     !read(unit+TIO_STOCK_DRAW_UNIT_TASK,&active)||active||!read(unit+TIO_STOCK_DRAW_UNIT_NEXT,&n))return false;
  unit=n;
 }
 uint32_t display=next(0);count=0;
 if(!display)return false;
 while(display){
  uint32_t layer=0;unsigned layers=0;
  if(++count>4||!ram(display,TIO_STOCK_DISPLAY_LAYERS+sizeof(uint32_t))||!read(display+TIO_STOCK_DISPLAY_LAYERS,&layer))return false;
  while(layer){
   uint32_t tasks=0,n=0;
   if(++layers>32||!ram(layer,TIO_STOCK_LAYER_NEXT+sizeof(uint32_t))||!read(layer+TIO_STOCK_LAYER_TASKS,&tasks)||tasks||
      !read(layer+TIO_STOCK_LAYER_NEXT,&n))return false;
   layer=n;
  }
  display=next(display);
 }
 return true;
}
