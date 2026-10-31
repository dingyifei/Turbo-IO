/* Only this exact A2UI surface/root uses the TDC1 template. Stock Text remains
 * the fallback. The stock A2UI owner destroys the completed root with children.
 * All labels copy their strings. The Round 2 card has no images and no divider lines.
 * No timers, mutable globals, power hold, file access or independent BLE path. */
#include "card.h"
#include "../common-v1/tio_ui.h"
#include <string.h>
extern int stock_dc_text(void *);
extern int dc_resolve(void *,void *,void *,const char *,char *,size_t);
extern void dc_hints(void *,void *),dc_weight(void *,void *);
extern void *tio_lv_obj_create_ex(void *,uint32_t),*native_label_create(void *),*menu_font(int,int);
extern void tio_lv_obj_delete(void *),tio_lv_obj_remove_flag(void *,uint32_t);
extern void tio_lv_obj_set_size(void *,int,int),native_align(void *,int,int,int),native_label_text(void *,const char *),menu_text_font(void *,void *,uint32_t),native_text_color(void *,uint32_t,uint32_t);
extern void dc_text_mode(void *,int),dc_remove_style(void *);
extern void tio_lv_obj_set_style_bg_color(void *,uint32_t,uint32_t),tio_lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t),tio_lv_obj_set_style_radius(void *,int,uint32_t);
static bool equal(const char *a,const char *b,size_t cap){for(size_t i=0;i<cap;i++){if(a[i]!=b[i])return false;if(!b[i])return true;}return false;}
static void place(void *o,int x,int y,int w,int h){tio_lv_obj_set_size(o,w,h);native_align(o,1,x,y);}
static void *box(void *parent,int x,int y,int w,int h,uint32_t color,int radius){
 void *o=tio_lv_obj_create_ex(parent,0);if(!o)return NULL;dc_remove_style(o);tio_lv_obj_remove_flag(o,2|16);
 place(o,x,y,w,h);tio_lv_obj_set_style_bg_color(o,color,0);tio_lv_obj_set_style_bg_opa(o,255,0);tio_lv_obj_set_style_radius(o,radius,0);return o;
}
_Static_assert(DC_MID==TIO_LENS_MID&&DC_HIGH==TIO_LENS_HIGH&&DC_FULL==TIO_LENS_FULL&&DC_TRACK==TIO_LENS_TRACK,"card intensities follow the lens ladder");
static void *root(void *p){return box(p,0,0,DC_W,DC_H,0,0);}
static bool text(void *p,int x,int y,int w,int h,unsigned sz,unsigned color,const char *s){
 void *f=menu_font((int)sz,0);if(!f)return false;void *o=native_label_create(p);if(!o)return false;
 dc_remove_style(o);menu_text_font(o,f,0);native_text_color(o,color,0);dc_text_mode(o,4); /* clip, never scroll */
 native_label_text(o,s);place(o,x,y,w,h);return true;
}
static bool bar(void *p,int x,int y,int w,unsigned pct){
 if(pct>100||!box(p,x,y,w,DC_BAR_H,DC_TRACK,1))return false;
 int fill=(w*(int)pct+50)/100;return !fill||box(p,x,y,fill,DC_BAR_H,DC_HIGH,1)!=NULL;
}
extern bool tce_owns(void *);
extern int tce_native(void *);
int m8_hook_dc_text(void *raw){
 if(tce_owns(raw))return tce_native(raw);
 void **ctx=raw;
 if(!ctx||!ctx[0]||!ctx[1]||!ctx[3])return -1;
 if(!equal((const char *)ctx[0]+4,DC_SURFACE,64)||!equal((const char *)ctx[1]+4,DC_COMPONENT,64))return stock_dc_text(raw);
 char data[128];memset(data,0,sizeof data);
 if(dc_resolve(ctx[1],(uint8_t *)ctx[0]+0x1658,ctx[2],"text",data,sizeof data))return -1;
 size_t n=0;while(n<sizeof data&&data[n])n++;DCValues v;if(!dc_parse(data,n,&v))return -1;
 const DCAPI api={root,text,bar,tio_lv_obj_delete};void *o=dc_render(&api,ctx[3],&v);if(!o)return -1;
 *(void **)((uint8_t *)ctx[1]+0xa8)=o;dc_hints(ctx,o);dc_weight(ctx[1],o);return 0;
}
