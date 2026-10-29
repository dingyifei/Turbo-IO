#include "app_view.h"
#include "../common-v1/tio_caret.h"
#include <string.h>
TIO_PAGES_CHECK;
// 14 px text is retired (TIO_FONT_MIN floor). The wire still carries 14; it is drawn at the next accepted size.
unsigned tap_view_font(unsigned font){return font<TIO_FONT_MIN?TIO_FONT_MIN:font;}
// Unfocused action labels sit one step below the focused lens-full; below 18 px lens-mid is too dim, so use lens-high.
static uint32_t idle_color(unsigned font){return font>=TIO_FONT_LABEL?TIO_LENS_MID:TIO_LENS_HIGH;}
static void place(TAPView *v,void *o,const TAPItem *q){v->api.place(v->api.ctx,o,q->x,q->y,q->w,q->h);}
// Text boxes grow to font + 4 when a retired size is drawn larger, never past the 540x180 canvas.
static void place_text(TAPView *v,void *o,const TAPItem *q){
 unsigned h=q->h,need=tap_view_font(q->font)+TIO_TEXT_PAD;if(h<need)h=need;if(q->y+h>TIO_PAGE_H)h=TIO_PAGE_H-q->y;
 v->api.place(v->api.ctx,o,q->x,q->y,q->w,h);
}
static void clear(TAPView *v){v->root=NULL;v->focus=NULL;memset(v->buttons,0,sizeof v->buttons);v->selected=0;}
void tap_view_detached(TAPView *v){if(!v)return;clear(v);v->document=NULL;v->retiring=true;}
bool tap_view_close(TAPView *v){
 if(!v)return false;if(!v->root&&!v->retiring)return true;if(!v->api.idle(v->api.ctx))return false;
 if(v->root)v->api.destroy(v->api.ctx,v->root);clear(v);v->document=NULL;v->used=0;v->retiring=false;return true;
}
// Wheel focus: the selected button goes lens-full, the others drop to their idle level, and the 24x3 caret sits
// TIO_CARET_GAP under the selected label's baseline. The caret snaps; the page has no animation tick.
bool tap_view_focus(TAPView *v,unsigned selected){
 if(!v||!v->root||!v->api.idle(v->api.ctx))return false;
 const TAPDocument *d=v->document;unsigned count=0;const TAPItem *on=NULL;
 for(unsigned i=d->first[v->page];i<d->first[v->page]+d->size[v->page];i++){
  const TAPItem *q=&d->items[i];if(q->kind!=2)continue;
  if(count>=12||!v->buttons[count])break;
  bool now=count==selected;if(now)on=q;
  v->api.tint(v->api.ctx,v->buttons[count],now?TIO_LENS_FULL:idle_color(tap_view_font(q->font)));count++;
 }
 if(!on){v->api.visible(v->api.ctx,v->focus,false);return false;}
 int y=tio_caret_top((int)on->y,tap_view_font(on->font));if(y>TIO_PAGE_H-TAP_CARET_H)y=TIO_PAGE_H-TAP_CARET_H;
 v->api.place(v->api.ctx,v->focus,on->x,(unsigned)y,TAP_CARET_W,TAP_CARET_H);v->api.visible(v->api.ctx,v->focus,true);v->selected=selected;return true;
}
bool tap_view_open(TAPView *v,const TAPWidgets *a,void *parent,const TAPDocument *d,unsigned page){
 if(!v||v->root||v->retiring||!a||!a->idle||!a->root||!a->text||!a->rect||!a->image||!a->place||!a->visible||!a->destroy||!a->tint||!d||page>=d->pages||!a->idle(a->ctx))return false;
 v->api=*a;v->document=d;v->page=page;v->used=0;memset(v->buttons,0,sizeof v->buttons);v->selected=0;
 v->root=a->root(a->ctx,parent);if(!v->root)return false;
 a->place(a->ctx,v->root,0,0,540,180);unsigned buttons=0;
 for(unsigned i=d->first[page];i<d->first[page]+d->size[page];i++){
  const TAPItem *q=&d->items[i];void *o=NULL;
  if(q->kind==1||q->kind==2){
   char text[97];memcpy(text,q->data,q->length);text[q->length]=0;o=a->text(a->ctx,v->root,text,tap_view_font(q->font));if(!o)goto failed;
   place_text(v,o,q);if(q->kind==2){a->tint(a->ctx,o,idle_color(tap_view_font(q->font)));v->buttons[buttons++]=o;}continue;
  }else if(q->kind==3){
   o=a->rect(a->ctx,v->root,0x003800,false);if(!o)goto failed;place(v,o,q);
   unsigned fill=(q->w*q->param+50)/100;
   if(fill){o=a->rect(a->ctx,v->root,0x00ff00,false);if(!o)goto failed;a->place(a->ctx,o,q->x,q->y,fill,q->h);}continue;
  }else if(q->kind==4){
   uintptr_t base=(uintptr_t)v->pixels;unsigned offset=(unsigned)(((base+v->used+63)&~(uintptr_t)63)-base),bytes=q->w*q->h;if(offset+bytes>sizeof v->pixels)goto failed;
   uint8_t *pixels=v->pixels+offset;for(unsigned b=0;b<bytes;b++)pixels[b]=(q->data[b/8]&(128>>(b%8)))?255:0;
   v->used=offset+bytes;o=a->image(a->ctx,v->root,pixels,q->w,q->h);
  }else if(q->kind==5)o=a->rect(a->ctx,v->root,0x007700,true); // authored frame; the focus ring is gone
  if(!o)goto failed;place(v,o,q);
 }
 {
  // Caret: lens-full 24x3 with the four corner pixels cut (radius 2), as the menu caret. Own aligned buffer.
  uint8_t *c=(uint8_t *)(((uintptr_t)v->caret+63)&~(uintptr_t)63);memset(c,255,TAP_CARET_W*TAP_CARET_H);
  for(unsigned y=0;y<TAP_CARET_H;y+=TAP_CARET_H-1)for(unsigned x=0;x<TAP_CARET_W;x+=TAP_CARET_W-1)c[y*TAP_CARET_W+x]=0;
  v->focus=a->image(a->ctx,v->root,c,TAP_CARET_W,TAP_CARET_H);if(!v->focus)goto failed;
 }
 tap_view_focus(v,0);a->visible(a->ctx,v->root,true);return true;
failed:
 // Hidden root was never submitted to renderer. Native callbacks must not
 // submit/re-enter rendering while building this subtree.
 a->destroy(a->ctx,v->root);clear(v);v->document=NULL;v->used=0;v->retiring=false;return false;
}
