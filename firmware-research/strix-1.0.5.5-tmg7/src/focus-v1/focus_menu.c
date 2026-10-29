#include "../common-v1/tio_text.h"
#include "../common-v1/tio_ui.h"
/* TMG7 LensMenu layout (docs/design-system/screens/LensMenu.dc.html, halved), same index math as TMG4:
 * band T (y 12-56): time left and battery right in lens-mid, the page dots centred between them;
 * band M (y 56-172): the icon grid, unfocused icons and 16 px names in lens-mid, the focused icon in lens-full
 *   with a 24x3 caret where its name would be (three-row mode keeps icons only: names do not fit the band);
 * band B (y 172-212): the focused name once, 24 px, lens-full, centred. No ring, no wordmark, nothing in the reserved rows.
 * TMG4: bounded six/nine-cell renderer over the active tile map, no per-frame heap, bounded packed artwork.
 * All retained text and pixels live with the view. Write/swap only while idle.
 * Stock selection is authoritative; rapid input replaces, never queues, motion.
 */
#include "focus_menu.h"
#include "focus_menu_icons.h"
#include <string.h>
static const unsigned names[]={TT_GRID_0,TT_GRID_1,TT_GRID_2,TT_GRID_3,TT_GRID_4,TT_GRID_5,TT_GRID_6,TT_GRID_DISPLAY,TT_TILE_NAVIGATION,TT_TILE_MUSIC,TT_TILE_FOCUS,TT_TILE_APPS,TT_TILE_CAMERA};
_Static_assert(sizeof names/sizeof *names==FM_ITEMS,"labels match stock item count");
_Static_assert(sizeof fm_icon4==14976,"artwork budget");
#define FM_LEVEL(c) ((unsigned)((c)>>8&255u))  /* canvas gray level = green channel */
enum { FM_CELL_W=144, FM_LABEL_H=TIO_FONT_MIN+TIO_TEXT_PAD, FM_ICON2=32, FM_ICON3=28, FM_PITCH2=58, FM_PITCH3=36, FM_CARET_GAP=6, FM_LABEL_GAP=3,
 FM_DOT_ACTIVE=12, FM_DOT=4, FM_DOT_GAP=6, FM_PAGER_W=36, FM_PAGER_H=4 };
_Static_assert(FM_ICON2<=FM_ICON&&FM_ICON3<=FM_ICON,"icon canvases fit the retained pixels");
_Static_assert(TIO_MENU_T1+2+FM_PITCH2+FM_ICON2+FM_LABEL_GAP+FM_LABEL_H<=TIO_MENU_M1,"two-row grid with names fits band M; re-lay if TIO_PPD_X10 moves the bands");
_Static_assert(TIO_MENU_T1+2+2*FM_PITCH3+FM_ICON3+FM_CARET_GAP+FM_CARET_H<=TIO_MENU_M1,"three-row grid fits band M; re-lay if TIO_PPD_X10 moves the bands");
static unsigned per(const FMView *v){return v->rows*3;}
static unsigned icon_size(const FMView *v){return v->rows==3?FM_ICON3:FM_ICON2;}
static int center(unsigned cell){return 92+178*(int)(cell%3);}
static int top(const FMView *v,unsigned cell){return TIO_MENU_T1+2+(int)(cell/3)*(v->rows==3?FM_PITCH3:FM_PITCH2);}
static int caret_left(unsigned cell){return center(cell)-FM_CARET_W/2;}
static int caret_top(const FMView *v,unsigned cell){return top(v,cell)+(int)icon_size(v)+FM_CARET_GAP;}
static unsigned ease(uint32_t elapsed,unsigned duration){if(elapsed>=duration)return 256;unsigned t=(unsigned)(elapsed*256/duration),r=256-t;return 256-r*r*r/65536;}
static int mix(int a,int b,unsigned q){return a+(b-a)*(int)q/256;}
static void sample(FMView *v,uint32_t now){
 unsigned cell=(unsigned)v->selected%per(v),duration=v->page_motion?120:160;
 unsigned q=v->moving?ease((uint32_t)(now-v->started),duration):256;
 v->caret_x=mix(v->from_x,caret_left(cell),q);v->caret_y=mix(v->from_y,caret_top(v,cell),q);
 for(unsigned i=0;i<FM_CELLS;i++)v->weights[i]=(unsigned)mix((int)v->from_weights[i],i==cell?256:0,q);
 if(q==256){v->moving=false;v->page_motion=false;v->page_offset=0;}
}
static void icon(uint8_t *out,unsigned index,unsigned weight,unsigned fade,unsigned canvas){
 memset(out,0,FM_ICON*FM_ICON);unsigned size=canvas-2+2*weight/256,pad=(canvas-size)/2,gain=(FM_LEVEL(TIO_LENS_MID)+(255-FM_LEVEL(TIO_LENS_MID))*weight/256)*fade/256;
 const unsigned char *packed=fm_icon4[index];
 for(unsigned y=0;y<size;y++)for(unsigned x=0;x<size;x++){
  unsigned pos=(y*48/size)*48+x*48/size;unsigned g=(packed[pos/2]>>(pos%2?0:4))&15;
  out[(y+pad)*canvas+x+pad]=(uint8_t)(g*17*gain/255);
 }
}
static void dots(uint8_t *out,unsigned pages,unsigned page){
 memset(out,0,FM_PAGER_W*FM_PAGER_H);unsigned total=FM_DOT_ACTIVE+(pages-1)*(FM_DOT+FM_DOT_GAP);if(!pages||total>FM_PAGER_W)return;
 unsigned at=(FM_PAGER_W-total)/2;
 for(unsigned p=0;p<pages;p++){
  unsigned w=p==page?FM_DOT_ACTIVE:FM_DOT,level=p==page?FM_LEVEL(TIO_LENS_HIGH):FM_LEVEL(TIO_LENS_MID);
  for(unsigned y=0;y<FM_PAGER_H;y++)for(unsigned x=0;x<w;x++)if(!((y==0||y==FM_PAGER_H-1)&&(x==0||x==w-1)))out[y*FM_PAGER_W+at+x]=(uint8_t)level;
  at+=w+FM_DOT_GAP;
 }
}
static void render(FMView *v,uint32_t now){
 unsigned lang=tio_lang();
 sample(v,now);unsigned bank=v->bank^1;unsigned q=v->page_motion?ease(now-v->started,120):256;
 int offset=v->page_motion?mix(v->page_offset,0,q):0;unsigned fade=v->page_motion?192+q/4:256;
 unsigned size=icon_size(v),cells=per(v),cell=(unsigned)v->selected%cells;bool named=v->rows==2;
 v->api.place(v->api.ctx,v->caret,v->caret_x+offset,v->caret_y,FM_CARET_W,FM_CARET_H);
 for(unsigned i=0;i<FM_CELLS;i++){
  unsigned index=(unsigned)v->selected/cells*cells+i;bool show=i<cells&&index<v->tiles.count;
  v->api.visible(v->api.ctx,v->icons[i],show);v->api.visible(v->api.ctx,v->labels[i],show&&named&&i!=cell); /* the focused name lives in band B */
  if(!show)continue;
  icon(v->pixels[bank][i],v->tiles.ids[index],v->weights[i],fade,size);
  v->api.place(v->api.ctx,v->icons[i],center(i)-(int)size/2+offset,top(v,i),size,size);
  v->api.buffer(v->api.ctx,v->icons[i],v->pixels[bank][i],size,size);
  v->api.place(v->api.ctx,v->labels[i],center(i)-FM_CELL_W/2+offset,top(v,i)+(int)size+FM_LABEL_GAP,FM_CELL_W,FM_LABEL_H);
  v->api.text_static(v->api.ctx,v->labels[i],tio_text(names[v->tiles.ids[index]],lang));
 }
 v->api.text_static(v->api.ctx,v->name,tio_text(names[v->tiles.ids[v->selected]],lang));
 dots(v->pager[bank],(v->tiles.count+cells-1)/cells,(unsigned)v->selected/cells);
 v->api.buffer(v->api.ctx,v->page,v->pager[bank],FM_PAGER_W,FM_PAGER_H);v->api.visible(v->api.ctx,v->root,true);
 v->bank=bank;v->last_draw=now;
}
static void tint(FMView *v,void *label,uint32_t rgb){if(v->api.color)v->api.color(v->api.ctx,label,rgb);}
bool fm_view_open(FMView *v,const TNWidgets *api,void *parent,bool (*attach)(void *,void *),void *owner){
 if(!v||!api||!attach||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->selected=-1;TTConfig defaults;tt_default(&defaults);tt_compact(&defaults,&v->tiles);
 v->root=api->root(api->ctx,parent);if(!v->root)return false;
 if(!attach(v->root,owner)){api->destroy(api->ctx,v->root);v->root=NULL;return false;}
 api->place(api->ctx,v->root,0,0,540,220);v->rows=3;
 v->caret=api->canvas(api->ctx,v->root);v->status=api->label(api->ctx,v->root,TIO_FONT_LABEL);v->battery=api->label(api->ctx,v->root,TIO_FONT_LABEL);v->name=api->label(api->ctx,v->root,TIO_FONT_TITLE);v->page=api->canvas(api->ctx,v->root);
 if(!v->caret||!v->status||!v->battery||!v->name||!v->page)goto failed;
 const TIOSpan t=tio_band(TIO_SURFACE_MENU,TIO_BAND_T);int row=t.y0+(t.y1-t.y0-(int)TIO_LINE(TIO_FONT_LABEL))/2;
 api->place(api->ctx,v->caret,0,0,FM_CARET_W,FM_CARET_H);
 api->place(api->ctx,v->status,TIO_CORE_X0,row,100,(int)TIO_LINE(TIO_FONT_LABEL));tint(v,v->status,TIO_LENS_MID);
 api->place(api->ctx,v->battery,TIO_CORE_X1-100,row,100,(int)TIO_LINE(TIO_FONT_LABEL));tint(v,v->battery,TIO_LENS_MID);
 api->place(api->ctx,v->name,TIO_CORE_X0,TIO_MENU_B1-(int)TIO_LINE(TIO_FONT_TITLE)-3,TIO_CORE_W,(int)TIO_LINE(TIO_FONT_TITLE));
 api->place(api->ctx,v->page,(540-FM_PAGER_W)/2,row+(int)TIO_LINE(TIO_FONT_LABEL)/2-FM_PAGER_H-3,FM_PAGER_W,FM_PAGER_H);
 for(unsigned i=0;i<FM_CELLS;i++){v->icons[i]=api->canvas(api->ctx,v->root);v->labels[i]=api->label(api->ctx,v->root,TIO_FONT_MIN);if(!v->icons[i]||!v->labels[i])goto failed;tint(v,v->labels[i],TIO_LENS_MID);}
 v->rows=0;if(!fm_view_rows(v,3))goto failed;
 api->visible(api->ctx,v->root,false);return true;
failed:api->destroy(api->ctx,v->root);v->root=NULL;return false;
}
bool fm_view_tiles(FMView *v,const TTVisible *tiles){
 if(!v||!v->root||!tiles||tiles->count<8||tiles->count>13||!v->api.idle(v->api.ctx))return false;
 unsigned seen=0;for(unsigned i=0;i<tiles->count;i++){unsigned id=tiles->ids[i];if(id>=13||(seen&(1u<<id))||tiles->rank[id]!=i||(i<7&&id!=i))return false;seen|=1u<<id;}if(!(seen&(1u<<12)))return false;
 for(unsigned id=0;id<13;id++)if(!(seen&(1u<<id))&&tiles->rank[id]!=255)return false;
 if(v->tiles.count!=tiles->count||memcmp(v->tiles.ids,tiles->ids,13)){v->tiles=*tiles;fm_view_suspend(v);}return true;
}
bool fm_view_rows(FMView *v,unsigned rows){
 if(!v||!v->root||(rows!=2&&rows!=3)||!v->api.idle(v->api.ctx))return false;
 if(v->rows==rows)return true;
 v->rows=rows;fm_view_suspend(v);
 /* Renderer idle before touching retained caret/pixel memory. The 24x3 caret is lens-full with its four corner pixels cut (radius 2). */
 memset(v->caret_px,255,sizeof v->caret_px);
 for(unsigned y=0;y<FM_CARET_H;y+=FM_CARET_H-1)for(unsigned x=0;x<FM_CARET_W;x+=FM_CARET_W-1)v->caret_px[y*FM_CARET_W+x]=0;
 v->api.buffer(v->api.ctx,v->caret,v->caret_px,FM_CARET_W,FM_CARET_H);return true;
}
bool fm_view_update(FMView *v,int selected,int64_t local,int battery,uint32_t now){
 if(!v||!v->root||selected<0||selected>=v->tiles.count||!v->api.idle(v->api.ctx))return false;
 unsigned b=v->header_bank^1;char *h=v->header[b],*pct=h+24;memset(h,0,48);memcpy(h,"--:--",5);memcpy(pct,"--%",3);
 if(local>=946684800&&local<=4102444800LL){unsigned secs=(unsigned)((uint64_t)local%86400),hour=secs/3600,min=secs/60%60;h[0]='0'+hour/10;h[1]='0'+hour%10;h[3]='0'+min/10;h[4]='0'+min%10;}
 if(battery>=0&&battery<=100){unsigned at=0;if(battery==100)pct[at++]='1';if(battery>=10)pct[at++]='0'+battery/10%10;pct[at++]='0'+battery%10;pct[at++]='%';pct[at]=0;}
 v->api.text_static(v->api.ctx,v->status,h);v->api.text_static(v->api.ctx,v->battery,pct);v->header_bank=b;
 if(selected!=v->selected){
  int old=v->selected;bool page=old>=0&&(unsigned)old/per(v)!=(unsigned)selected/per(v);
  if(old>=0)sample(v,now);
  v->selected=selected;unsigned cell=(unsigned)selected%per(v);
  if(old<0||page){v->caret_x=caret_left(cell);v->caret_y=caret_top(v,cell);for(unsigned i=0;i<FM_CELLS;i++)v->weights[i]=i==cell?256:0;}
  v->from_x=v->caret_x;v->from_y=v->caret_y;for(unsigned i=0;i<FM_CELLS;i++)v->from_weights[i]=v->weights[i];
  v->page_motion=page;v->page_offset=page?(selected>old?10:-10):0;v->started=now;v->moving=old>=0;
  render(v,now);
 }else if(v->moving){if((uint32_t)(now-v->last_draw)>=16)render(v,now);}
 else v->api.visible(v->api.ctx,v->root,true);
 return true;
}
bool fm_view_step(FMView *v,uint32_t now){if(!v||!v->root||!v->moving||(uint32_t)(now-v->last_draw)<16||!v->api.idle(v->api.ctx))return false;render(v,now);return true;}
void fm_view_suspend(FMView *v){if(v){v->moving=false;v->page_motion=false;v->selected=-1;}}
bool fm_view_close(FMView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;v->root=NULL;v->moving=false;v->api.destroy(v->api.ctx,root);return true;}
