#include "../common-v1/tio_text.h"
#include "../common-v1/tio_ui.h"
#include "app_shelf.h"
#include <string.h>
static void w16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static size_t item(uint8_t *p,bool button,unsigned font,unsigned x,unsigned y,unsigned w,unsigned h,const char *text){
 size_t n=strlen(text);if(n>96)return 0;memset(p,0,16);p[0]=button?2:1;p[1]=(uint8_t)font;p[2]=button?2:0;w16(p+4,x);w16(p+6,y);w16(p+8,w);w16(p+10,h);w16(p+14,(unsigned)n);memcpy(p+16,text,n);return 16+n;
}
/* The shelf follows the bands (PriorityBands, FocusCaret): the title is one line of ambient text in band T; the four apps are
 * caret focus items in 20 px, two in band M (y 76, the LensApp board's action row) and two in band B (y 132), each with its
 * caret inside its band. The two columns are 222 px wide with a 16 px gutter (x 40..262 and 278..500). Empty slots are
 * plain text on the same rows. TAP1 has no intensity, so tap_shelf_open re-tints the title and the empty slots to lens-mid
 * after the view opens (tap_shelf_style): the ambient title in band T and a placeholder never outshine a focused app. */
#define SHELF_COLUMN_W 222
#define SHELF_COLUMN_STEP 238
size_t tap_shelf_wire(uint8_t *p,const TAPStore *store,unsigned lang){
 memset(p,0,16);memcpy(p,"TAP1",4);p[4]=1;w16(p+6,5);w16(p+14,5);size_t n=16;
 n+=item(p+n,false,TIO_FONT_LABEL,TIO_CORE_X0,TIO_PAGE_T0+((TIO_PAGE_T1-TIO_PAGE_T0)-TIO_LINE(TIO_FONT_LABEL))/2,TIO_CORE_W,TIO_LINE(TIO_FONT_LABEL),tio_text(TT_SHELF_TITLE,lang));
 for(unsigned i=0;i<4;i++){
  const TAPSlot *s=&store->slots[i];bool installed=s->present&&!s->tombstone;
  n+=item(p+n,installed,TIO_FONT_BODY,TIO_CORE_X0+SHELF_COLUMN_STEP*(i%2),(i/2?TIO_PAGE_M1:TIO_PAGE_T1)+20,SHELF_COLUMN_W,TIO_LINE(TIO_FONT_BODY),installed?s->name:tio_text(TT_SHELF_EMPTY,lang));
 }
 for(unsigned i=0;i<4;i++)p[8+i]=(uint8_t)(n>>(8*i));
 return n;
}
bool tap_shelf_style(TAPView *v){
 if(!v)return false;bool ok=tap_view_tint_plain(v,0,TIO_LENS_MID);   // title; every other plain label is an empty slot
 for(unsigned i=1;i<v->plain_count;i++)ok&=tap_view_tint_plain(v,i,TIO_LENS_MID);
 return ok;
}
bool tap_shelf_open(TAPRunner *r){unsigned lang=tio_lang();
 if(!r||!r->store||r->view.root||r->view.retiring||r->closing||r->state.active||r->slot!=-1)return false;
 // The generated document follows the same decoder and resource checks as ZIP.
 uint8_t *p=r->wire;size_t n=tap_shelf_wire(p,r->store,lang);
 if(!tap_parse(p,n,&r->document)||!tap_view_open(&r->view,&r->widgets,r->parent,&r->document,0))return false;
 (void)tap_shelf_style(&r->view);   // a failed re-tint leaves lens-full text, never a missing shelf
 return tap_start(&r->state,&r->document);
}
