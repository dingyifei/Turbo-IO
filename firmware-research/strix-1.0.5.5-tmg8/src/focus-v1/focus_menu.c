#include "../common-v1/tio_text.h"
#include "../common-v1/tio_ui.h"
/* TMG7 LensMenu layout (docs/design-system/screens/LensMenu.dc.html, halved), same index math as TMG4:
 * band T (y 12-56): time left and battery right in lens-mid, the page dots centred between them;
 * band M (y 56-172): the icon grid, unfocused icons and 16 px names in lens-mid, the focused icon in lens-full
 *   with a 24x3 caret where its name would be (three-row mode keeps icons only: names do not fit the band);
 * band B (y 172-212): the focused name once, 24 px, lens-full, centred. No ring, no wordmark, nothing in the reserved rows.
 * TMG8 carousel (LensMenuCarousel.dc.html, rows==FM_CAROUSEL): the same bands. Clock and battery in T; one row of icons at cy 68 (no route) or
 * 92 (route): 80/48/36 px at dx 0/124/214 (route 64/40/32 at 0/118/206), lens-full / lens-mid / lens-track, the 24x3 caret at y 114 (127), the
 * focused tile's status line (16 px, lens-high) at y 146 (140), the name in band B. The focus is a fractional position: an item at signed
 * distance r from it is drawn at the geometry interpolated at |r| (knots 0..3, gone at 3), so a wheel step, a wrap and an interrupted step are
 * the same slide. The six visible items take canvas slots in order of |r| (the centre 80 px, the next at most 64, ...), which bounds retained pixels.
 * TMG8 navigation title (OptionANavTitle.dc.html): while a route is live the next turn (an 18 px arrow and "<distance> · <road>", lens-high) is centred in band T of both
 * layouts, in a fixed slot between the clock and the battery (nav_title.h); the grid's page dots (same band) are hidden meanwhile and the carousel row moves down (fm_view_route).
 * TMG4: bounded six/nine-cell renderer over the active tile map, no per-frame heap, bounded packed artwork.
 * All retained text and pixels live with the view. Write/swap only while idle.
 * Stock selection is authoritative; rapid input replaces, never queues, motion.
 */
#include "focus_menu.h"
#include "focus_menu_icons.h"
#include <string.h>
TIO_PAGES_CHECK;
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
/* State dot (LensMenuGrid2): 1 px right of the icon box and 4 px above it, i.e. (cx+17, cy-20) for the 32 px icon; never above band M. */
enum { FM_STATE_GAP=1, FM_STATE_RISE=4 };
static int state_top(const FMView *v,unsigned cell){int y=top(v,cell)-FM_STATE_RISE;return y<TIO_MENU_T1?TIO_MENU_T1:y;}
enum { FM_CAR_CX=270, FM_CAR_MAX=80, FM_MOVE_MS=160 };
static const unsigned car_side[FM_SLOTS]=FM_CAR_SIDES,car_at[FM_SLOTS]=FM_CAR_OFFSETS;
_Static_assert(36*36<=FM_CAR_BANK-15936&&15936%64==0&&FM_CAR_BANK%64==0,"carousel slots fit one 64-aligned bank");
_Static_assert(80*80<=6400&&64*64<=10496-6400&&48*48<=12800-10496&&42*42<=14592-12800&&36*36<=15936-14592&&36*36<=FM_CAR_BANK-15936,"carousel slot capacities");
/* Geometry knots by |r| = 0,1,2,3 items from the focus: [0] without a route, [1] with one (OptionA nav title in band T). */
static const int car_size[2][4]={{80,48,36,36},{64,40,32,32}},car_dx[2][4]={{0,124,214,300},{0,118,206,290}};
static const int car_cy[2]={68,92},car_caret_y[2]={114,127},car_line_y[2]={146,140};
static const int car_gain[4]={(int)FM_LEVEL(TIO_LENS_FULL),(int)FM_LEVEL(TIO_LENS_MID),(int)FM_LEVEL(TIO_LENS_TRACK),0};
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

/* Navigation title (nav_title.h): the group (arrow, gap, text) is centred on x 270 inside x NT_X0..NT_X1 and vertically on the clock's row. Needs a laid-out frame.
 * The text box is the width estimate (errs wide, so the label never clips) and the text is left-aligned in it, so the gap to the arrow is exactly NT_GAP; the group is
 * centred on 7/8 of the estimate, which is closer to the real glyph width. */
static void title_place(FMView *v){
 const bool on=v->title_on&&v->selected>=0;
 v->api.visible(v->api.ctx,v->title_arrow,on);v->api.visible(v->api.ctx,v->title_text,on);if(!on)return;
 const TIOSpan t=tio_band(TIO_SURFACE_MENU,TIO_BAND_T);const int row=t.y0+(t.y1-t.y0-(int)TIO_LINE(TIO_FONT_LABEL))/2;
 int w=(int)v->title_w;if(w>NT_TEXT_W)w=NT_TEXT_W;if(w<1)w=1;
 int x=TIO_PAGE_W/2-(NT_ARROW+NT_GAP+w*7/8)/2;if(x<NT_X0)x=NT_X0;if(x+NT_ARROW+NT_GAP+w>NT_X1)x=NT_X1-NT_ARROW-NT_GAP-w;
 v->api.place(v->api.ctx,v->title_arrow,x,row+((int)TIO_LINE(TIO_FONT_LABEL)-NT_ARROW)/2,NT_ARROW,NT_ARROW);
 v->api.place(v->api.ctx,v->title_text,x+NT_ARROW+NT_GAP,row,w,(int)TIO_LINE(TIO_FONT_LABEL));
}

/* ---- Carousel -------------------------------------------------------------------------------------------------------- */
typedef struct {unsigned idx,a;int r;} CarItem;
static int knot(const int *k,unsigned a){if(a>=768)return k[3];unsigned i=a>>8,f=a&255;return k[i]+(k[i+1]-k[i])*(int)f/256;}
static unsigned car_count(const FMView *v){return v->tiles.count?v->tiles.count:1;}
static int car_norm(const FMView *v,int p){int n=(int)car_count(v)*256;return ((p%n)+n)%n;}
/* The six items that can be on screen for position p (8.8 item units), nearest first. */
static void car_order(const FMView *v,int p,CarItem it[FM_SLOTS]){
 const int n=(int)car_count(v);p=car_norm(v,p);const int base=p>>8,frac=p&255;
 for(int j=0;j<FM_SLOTS;j++){int s=j-2,r=s*256-frac;it[j]=(CarItem){(unsigned)(((base+s)%n+n)%n),(unsigned)(r<0?-r:r),r};}
 for(int j=1;j<FM_SLOTS;j++){CarItem x=it[j];int k=j;while(k>0&&it[k-1].a>x.a){it[k]=it[k-1];k--;}it[k]=x;}
}
static void car_sample(FMView *v,uint32_t now){
 unsigned q=v->moving?ease((uint32_t)(now-v->started),FM_MOVE_MS):256;
 v->car_p=mix(v->car_from_p,v->car_to_p,q);v->car_w=(unsigned)mix((int)v->car_from_w,(int)v->car_to_w,q);
 v->caret_x=FM_CAR_CX-FM_CARET_W/2;v->caret_y=mix(car_caret_y[0],car_caret_y[1],v->car_w);
 if(q==256){v->moving=false;v->car_p=v->car_from_p=v->car_to_p=car_norm(v,v->car_to_p);v->car_w=v->car_from_w=v->car_to_w;}
}
/* Bilinear scale of the 48x48 4 bpp art to size x size (size <= 80) at brightness `gain` (255 = the art's own lens-full). */
static void car_icon(uint8_t *out,unsigned index,unsigned size,unsigned gain){
 if(size>FM_CAR_MAX)size=FM_CAR_MAX;if(!size)return;
 const unsigned char *packed=fm_icon4[index];uint8_t x0[FM_CAR_MAX],wx[FM_CAR_MAX];
 for(unsigned x=0;x<size;x++){int c=(int)((2*x+1)*6144/size)-128;if(c<0)c=0;if(c>47*256)c=47*256;x0[x]=(uint8_t)(c>>8);wx[x]=(uint8_t)(c&255);}
 for(unsigned y=0;y<size;y++){
  int c=(int)((2*y+1)*6144/size)-128;if(c<0)c=0;if(c>47*256)c=47*256;unsigned y0=(unsigned)c>>8,y1=y0<47?y0+1:47,wy=(unsigned)c&255;
  for(unsigned x=0;x<size;x++){
   unsigned xa=x0[x],xb=xa<47?xa+1:47,fx=wx[x];
   unsigned p00=y0*48+xa,p01=y0*48+xb,p10=y1*48+xa,p11=y1*48+xb;
   unsigned a=(packed[p00/2]>>(p00%2?0:4))&15,b=(packed[p01/2]>>(p01%2?0:4))&15,c2=(packed[p10/2]>>(p10%2?0:4))&15,d=(packed[p11/2]>>(p11%2?0:4))&15;
   unsigned sum=((a*(256-fx)+b*fx)*(256-wy)+(c2*(256-fx)+d*fx)*wy),level=(sum*17+32768)>>16;
   out[y*size+x]=(uint8_t)(level*gain/255);
  }
 }
}
static void car_retarget(FMView *v,int old,int selected,uint32_t now){
 const int N=(int)car_count(v)*256,target=selected*256;const unsigned w=v->route?256:0;
 if(old<0){v->car_p=v->car_from_p=v->car_to_p=target;v->car_w=v->car_from_w=v->car_to_w=w;v->moving=false;return;}
 car_sample(v,now);int cur=car_norm(v,v->car_p),d=target-cur;if(d>N/2)d-=N;if(d<=-N/2)d+=N;
 v->car_from_w=v->car_w;v->car_to_w=w;
 if(v->reduce_motion){v->car_p=v->car_from_p=v->car_to_p=target;v->car_w=v->car_from_w=v->car_to_w;v->moving=false;return;}   /* Reduce Motion: snap */
 v->car_from_p=cur;v->car_to_p=cur+d;v->started=now;v->moving=true;
}
static void render_car(FMView *v,uint32_t now){
 unsigned lang=tio_lang();car_sample(v,now);const unsigned bank=v->bank^1,w=v->car_w;CarItem it[FM_SLOTS];car_order(v,v->car_p,it);
 const int cy=mix(car_cy[0],car_cy[1],w);
 v->api.place(v->api.ctx,v->caret,v->caret_x,v->caret_y,FM_CARET_W,FM_CARET_H);
 for(unsigned k=0;k<FM_SLOTS;k++){
  unsigned size=(unsigned)mix(knot(car_size[0],it[k].a),knot(car_size[1],it[k].a),w);if(size>car_side[k])size=car_side[k];
  unsigned gain=(unsigned)knot(car_gain,it[k].a);int dx=mix(knot(car_dx[0],it[k].a),knot(car_dx[1],it[k].a),w);
  int x=FM_CAR_CX+(it[k].r<0?-dx:dx)-(int)size/2,y=cy-(int)size/2;
  /* Fully dim, or outside the side insets (the glyph zone): not drawn. Positions between knots are continuous, so this only trims the fade-out. */
  bool show=gain>0&&size>=8&&x>=TIO_INSET_X&&x+(int)size<=TIO_PAGE_W-TIO_INSET_X;
  v->api.visible(v->api.ctx,v->icons[k],show);if(!show)continue;
  uint8_t *out=v->cpixels[bank]+car_at[k];
  car_icon(out,v->tiles.ids[it[k].idx],size,gain);
  v->api.place(v->api.ctx,v->icons[k],x,y,size,size);v->api.buffer(v->api.ctx,v->icons[k],out,size,size);
 }
 for(unsigned i=FM_SLOTS;i<FM_CELLS;i++)v->api.visible(v->api.ctx,v->icons[i],false);
 for(unsigned i=0;i<FM_CELLS;i++){v->api.visible(v->api.ctx,v->labels[i],false);v->api.visible(v->api.ctx,v->dots[i],false);}   /* the status line replaces the grid's state dots */
 v->api.visible(v->api.ctx,v->page,false);title_place(v);
 v->api.place(v->api.ctx,v->line,TIO_CORE_X0,mix(car_line_y[0],car_line_y[1],w),TIO_CORE_W,(int)TIO_LINE(TIO_FONT_MIN));
 v->api.visible(v->api.ctx,v->line,v->line_text[v->line_bank][0]!=0);
 v->api.text_static(v->api.ctx,v->name,tio_text(names[v->tiles.ids[v->selected]],lang));
 v->api.visible(v->api.ctx,v->root,true);v->bank=bank;v->last_draw=now;v->dirty=false;
}
static void render_grid(FMView *v,uint32_t now){
 unsigned lang=tio_lang();
 sample(v,now);unsigned bank=v->bank^1;unsigned q=v->page_motion?ease(now-v->started,120):256;
 int offset=v->page_motion?mix(v->page_offset,0,q):0;unsigned fade=v->page_motion?192+q/4:256;
 unsigned size=icon_size(v),cells=per(v),cell=(unsigned)v->selected%cells;bool named=v->rows==2;
 v->api.place(v->api.ctx,v->caret,v->caret_x+offset,v->caret_y,FM_CARET_W,FM_CARET_H);
 for(unsigned i=0;i<FM_CELLS;i++){
  unsigned index=(unsigned)v->selected/cells*cells+i;bool show=i<cells&&index<v->tiles.count;
  v->api.visible(v->api.ctx,v->icons[i],show);v->api.visible(v->api.ctx,v->labels[i],show&&named&&i!=cell); /* the focused name lives in band B */
  bool dot=show&&(v->live_mask>>v->tiles.ids[index]&1);v->api.visible(v->api.ctx,v->dots[i],dot);
  if(!show)continue;
  if(dot)v->api.place(v->api.ctx,v->dots[i],center(i)+(int)size/2+FM_STATE_GAP+offset,state_top(v,i),FM_STATE_W,FM_STATE_H);
  icon(v->pixels[bank][i],v->tiles.ids[index],v->weights[i],fade,size);
  v->api.place(v->api.ctx,v->icons[i],center(i)-(int)size/2+offset,top(v,i),size,size);
  v->api.buffer(v->api.ctx,v->icons[i],v->pixels[bank][i],size,size);
  v->api.place(v->api.ctx,v->labels[i],center(i)-FM_CELL_W/2+offset,top(v,i)+(int)size+FM_LABEL_GAP,FM_CELL_W,FM_LABEL_H);
  v->api.text_static(v->api.ctx,v->labels[i],tio_text(names[v->tiles.ids[index]],lang));
 }
 v->api.text_static(v->api.ctx,v->name,tio_text(names[v->tiles.ids[v->selected]],lang));
 dots(v->pager[bank],(v->tiles.count+cells-1)/cells,(unsigned)v->selected/cells);
 v->api.buffer(v->api.ctx,v->page,v->pager[bank],FM_PAGER_W,FM_PAGER_H);v->api.visible(v->api.ctx,v->page,!v->title_on);v->api.visible(v->api.ctx,v->line,false);title_place(v);v->api.visible(v->api.ctx,v->root,true);
 v->bank=bank;v->last_draw=now;v->dirty=false;
}
static void render(FMView *v,uint32_t now){if(v->rows==FM_CAROUSEL)render_car(v,now);else render_grid(v,now);}
static void tint(FMView *v,void *label,uint32_t rgb){if(v->api.color)v->api.color(v->api.ctx,label,rgb);}
bool fm_view_open(FMView *v,const TNWidgets *api,void *parent,bool (*attach)(void *,void *),void *owner){
 if(!v||!api||!attach||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->selected=-1;TTConfig defaults;tt_default(&defaults);tt_compact(&defaults,&v->tiles);
 v->root=api->root(api->ctx,parent);if(!v->root)return false;
 if(!attach(v->root,owner)){api->destroy(api->ctx,v->root);v->root=NULL;return false;}
 api->place(api->ctx,v->root,0,0,540,220);v->rows=3;
 v->caret=api->canvas(api->ctx,v->root);v->status=api->label(api->ctx,v->root,TIO_FONT_LABEL);v->battery=api->label(api->ctx,v->root,TIO_FONT_LABEL);v->name=api->label(api->ctx,v->root,TIO_FONT_TITLE);v->page=api->canvas(api->ctx,v->root);v->line=api->label(api->ctx,v->root,TIO_FONT_MIN);
 v->title_arrow=api->canvas(api->ctx,v->root);v->title_text=api->label(api->ctx,v->root,TIO_FONT_LABEL);
 if(!v->caret||!v->status||!v->battery||!v->name||!v->page||!v->line||!v->title_arrow||!v->title_text)goto failed;
 const TIOSpan t=tio_band(TIO_SURFACE_MENU,TIO_BAND_T);int row=t.y0+(t.y1-t.y0-(int)TIO_LINE(TIO_FONT_LABEL))/2;
 api->place(api->ctx,v->caret,0,0,FM_CARET_W,FM_CARET_H);
 api->place(api->ctx,v->status,TIO_CORE_X0,row,NT_STATUS_W,(int)TIO_LINE(TIO_FONT_LABEL));tint(v,v->status,TIO_LENS_MID);   /* 64 px each: "10:00" and "100%" are about 50, and the title slot lies between the two boxes */
 api->place(api->ctx,v->battery,TIO_CORE_X1-NT_STATUS_W,row,NT_STATUS_W,(int)TIO_LINE(TIO_FONT_LABEL));tint(v,v->battery,TIO_LENS_MID);
 api->place(api->ctx,v->name,TIO_CORE_X0,TIO_MENU_B1-(int)TIO_LINE(TIO_FONT_TITLE)-3,TIO_CORE_W,(int)TIO_LINE(TIO_FONT_TITLE));
 api->place(api->ctx,v->line,TIO_CORE_X0,car_line_y[0],TIO_CORE_W,(int)TIO_LINE(TIO_FONT_MIN));tint(v,v->line,TIO_LENS_HIGH);if(api->clip_text)api->clip_text(api->ctx,v->line);api->visible(api->ctx,v->line,false);   /* carousel status line: 16 px, lens-high, band M under the focused icon */
 api->place(api->ctx,v->title_arrow,NT_X0,row,NT_ARROW,NT_ARROW);api->place(api->ctx,v->title_text,NT_X0+NT_ARROW+NT_GAP,row,NT_TEXT_W,(int)TIO_LINE(TIO_FONT_LABEL));tint(v,v->title_text,TIO_LENS_HIGH);if(api->clip_text)api->clip_text(api->ctx,v->title_text);
 api->visible(api->ctx,v->title_arrow,false);api->visible(api->ctx,v->title_text,false);   /* navigation title: lens-high 18 px, hidden until a route is live */
 api->place(api->ctx,v->page,(540-FM_PAGER_W)/2,row+(int)TIO_LINE(TIO_FONT_LABEL)/2-FM_PAGER_H-3,FM_PAGER_W,FM_PAGER_H);
 /* The state dot: a 5 px lens-mid disc, drawn once into one 8x5 buffer that all nine dot canvases show (hidden until a tile has live state). */
 for(unsigned y=0;y<FM_STATE_H;y++)for(unsigned x=0;x<FM_STATE_DOT;x++){bool corner=(y==0||y==FM_STATE_H-1)&&(x==0||x==FM_STATE_DOT-1);v->state_px[y*FM_STATE_W+x]=corner?0:(uint8_t)FM_LEVEL(TIO_LENS_MID);}
 for(unsigned i=0;i<FM_CELLS;i++){v->icons[i]=api->canvas(api->ctx,v->root);v->labels[i]=api->label(api->ctx,v->root,TIO_FONT_MIN);v->dots[i]=api->canvas(api->ctx,v->root);if(!v->icons[i]||!v->labels[i]||!v->dots[i])goto failed;tint(v,v->labels[i],TIO_LENS_MID);
  api->place(api->ctx,v->dots[i],0,0,FM_STATE_W,FM_STATE_H);api->buffer(api->ctx,v->dots[i],v->state_px,FM_STATE_W,FM_STATE_H);api->visible(api->ctx,v->dots[i],false);}
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
bool fm_view_rows(FMView *v,unsigned rows){   /* 1 carousel, 2 or 3 grid rows */
 if(!v||!v->root||rows<1||rows>3||!v->api.idle(v->api.ctx))return false;
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
  int old=v->selected;
  if(v->rows==FM_CAROUSEL){car_retarget(v,old,selected,now);v->selected=selected;render(v,now);return true;}
  bool page=old>=0&&(unsigned)old/per(v)!=(unsigned)selected/per(v);
  if(old>=0)sample(v,now);
  v->selected=selected;unsigned cell=(unsigned)selected%per(v);
  if(old<0||page){v->caret_x=caret_left(cell);v->caret_y=caret_top(v,cell);for(unsigned i=0;i<FM_CELLS;i++)v->weights[i]=i==cell?256:0;}
  v->from_x=v->caret_x;v->from_y=v->caret_y;for(unsigned i=0;i<FM_CELLS;i++)v->from_weights[i]=v->weights[i];
  v->page_motion=page&&!v->reduce_motion;v->page_offset=v->page_motion?(selected>old?10:-10):0;v->started=now;v->moving=old>=0&&!v->reduce_motion;
  render(v,now);
 }else if(v->moving||v->dirty){if((uint32_t)(now-v->last_draw)>=16)render(v,now);}
 else v->api.visible(v->api.ctx,v->root,true);
 return true;
}
bool fm_view_step(FMView *v,uint32_t now){if(!v||!v->root||v->selected<0||!(v->moving||v->dirty)||(uint32_t)(now-v->last_draw)<16||!v->api.idle(v->api.ctx))return false;render(v,now);return true;}
void fm_view_suspend(FMView *v){if(v){v->moving=false;v->page_motion=false;v->selected=-1;v->dirty=false;}}
/* Route hook (navigation title active): the carousel makes room in band T. Called from the UI thread at the 1 Hz nav refresh. */
bool fm_view_route(FMView *v,bool on,uint32_t now){
 if(!v||!v->root)return false;if(v->route==on)return true;v->route=on;
 if(v->rows!=FM_CAROUSEL||v->selected<0)return true;   /* picked up when the carousel is next laid out */
 car_sample(v,now);v->car_from_p=v->car_p;v->car_from_w=v->car_w;v->car_to_w=on?256:0;
 if(v->reduce_motion){v->car_p=v->car_from_p=v->car_to_p;v->car_w=v->car_from_w=v->car_to_w;v->moving=false;}else{v->started=now;v->moving=true;}
 v->dirty=true;return true;
}
/* Status line hook: the focused tile's live state. Cut at a UTF-8 character boundary, empty hides it. Needs an idle renderer. */
bool fm_view_line(FMView *v,const char *text){
 if(!v||!v->root)return false;if(!text)text="";
 size_t n=strlen(text);if(n>=FM_LINE_MAX){n=FM_LINE_MAX-1;while(n&&((uint8_t)text[n]&0xC0)==0x80)n--;}
 if(strlen(v->line_text[v->line_bank])==n&&!memcmp(v->line_text[v->line_bank],text,n))return true;
 if(!v->api.idle(v->api.ctx))return false;
 unsigned b=v->line_bank^1;memcpy(v->line_text[b],text,n);v->line_text[b][n]=0;
 v->api.text_static(v->api.ctx,v->line,v->line_text[b]);v->line_bank=b;if(v->rows==FM_CAROUSEL)v->dirty=true;return true;   /* the grid keeps the text but draws no line */
}
void fm_view_reduce_motion(FMView *v,bool on){if(v)v->reduce_motion=on;}
/* Navigation title hook. Hiding is immediate; a changed arrow or text waits for NT_MIN_MS since the last write (1 Hz at most, the next refresh retries).
 * The text is banked like the status line (the label keeps a pointer); the arrow is redrawn into the idle bank. Needs an idle renderer. */
bool fm_view_title(FMView *v,const NTTitle *t,uint32_t now){
 if(!v||!v->root||!t)return false;
 if(!t->on||t->icon>=TN_ICON_COUNT||!t->text[0]){if(v->title_on){v->title_on=false;v->dirty=true;}return true;}
 size_t n=0;while(n<NT_TEXT_MAX-1&&t->text[n])n++;
 if(v->title_on&&v->title_icon==t->icon&&strlen(v->title_line[v->title_bank])==n&&!memcmp(v->title_line[v->title_bank],t->text,n))return true;
 if(v->title_on&&(uint32_t)(now-v->title_at)<NT_MIN_MS)return true;
 if(!v->api.idle(v->api.ctx))return false;
 const unsigned b=v->title_bank^1;
 memcpy(v->title_line[b],t->text,n);v->title_line[b][n]=0;
 nt_glyph(v->title_px[b],t->icon,FM_LEVEL(TIO_LENS_HIGH));
 v->api.buffer(v->api.ctx,v->title_arrow,v->title_px[b],NT_ARROW,NT_ARROW);v->api.text_static(v->api.ctx,v->title_text,v->title_line[b]);
 v->title_bank=b;v->title_icon=t->icon;v->title_w=t->width;v->title_on=true;v->title_at=now;v->dirty=true;return true;
}
/* State dots (grid only; the carousel has the status line instead). Recorded in any layout, redrawn only when the set changes. */
bool fm_view_active(FMView *v,unsigned mask){
 if(!v||!v->root)return false;mask&=(1u<<FM_ITEMS)-1;if(v->live_mask==mask)return true;
 v->live_mask=mask;if(v->rows!=FM_CAROUSEL)v->dirty=true;return true;
}
bool fm_view_close(FMView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;v->root=NULL;v->moving=false;v->api.destroy(v->api.ctx,root);return true;}
