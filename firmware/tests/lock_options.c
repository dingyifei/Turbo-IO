// Test-only lock-screen prototypes (see lock_options.h). Host only: uses float maths for the drawn numeral.
#include "lock_options.h"
#include "../src/common-v1/tio_text.h"
#include <math.h>
#include <string.h>

/* Canvas buffers, 64-byte aligned (the stock draw buffer rounds the pointer up to 64). Levels: the caret is lens-full,
 * empty slots lens-track, entered dots lens-high (B: the current position lens-full). */
#define LEVEL(c) ((uint8_t)((c)>>8&255u))
static _Alignas(64) uint8_t caret_bar[LO_TRACK_W*LO_TRACK_H],track_bar[LO_TRACK_W*LO_TRACK_H];
static _Alignas(64) uint8_t dot_high[LO_DOT*LO_DOT];
static _Alignas(64) uint8_t row_high[LO_DOT_B*LO_DOT_B];
static _Alignas(64) uint8_t row_full[LO_DOT_B*LO_DOT_B];
static _Alignas(64) uint8_t row_track[LO_DOT_B*LO_DOT_B];
static void disc(uint8_t *d,int n,uint8_t level){   // anti-aliased round dot, 4x4 supersampled
 for(int y=0;y<n;y++)for(int x=0;x<n;x++){int in=0;for(int sy=0;sy<4;sy++)for(int sx=0;sx<4;sx++){float fx=x+(sx+.5f)/4-n/2.f,fy=y+(sy+.5f)/4-n/2.f;in+=fx*fx+fy*fy<=n*n/4.f;}
  d[y*n+x]=(uint8_t)(level*in/16);}
}
static void buffers(void){
 static bool ready;if(ready)return;ready=true;
 memset(caret_bar,LEVEL(TIO_LENS_FULL),sizeof caret_bar);memset(track_bar,LEVEL(TIO_LENS_TRACK),sizeof track_bar);
 disc(dot_high,LO_DOT,LEVEL(TIO_LENS_HIGH));disc(row_high,LO_DOT_B,LEVEL(TIO_LENS_HIGH));disc(row_full,LO_DOT_B,LEVEL(TIO_LENS_FULL));disc(row_track,LO_DOT_B,LEVEL(TIO_LENS_TRACK));
}

/* ---- The drawn numeral (Option C): polylines on a unit box, round caps and joins, scaled into 32x50 ---- */
typedef struct {unsigned n;float x[24],y[24];} Poly;
static void pt(Poly *p,float x,float y){if(p->n<24){p->x[p->n]=x;p->y[p->n]=y;p->n++;}}
// Arc of an ellipse (y down: 0 deg = right, 90 = down, 180 = left, 270 = up) from a0 to a1 degrees in `steps` pieces.
static void arc(Poly *p,float cx,float cy,float rx,float ry,float a0,float a1,unsigned steps){
 for(unsigned i=0;i<=steps;i++){float a=(a0+(a1-a0)*i/steps)*(float)M_PI/180;pt(p,cx+rx*cosf(a),cy+ry*sinf(a));}
}
static unsigned unit_lines(unsigned d,Poly o[4]){
 memset(o,0,4*sizeof *o);
 switch(d%10){
 case 0:arc(&o[0],.5f,.3f,.5f,.3f,180,360,10);arc(&o[0],.5f,.7f,.5f,.3f,0,180,10);pt(&o[0],0,.3f);return 1;
 case 1:pt(&o[0],.18f,.2f);pt(&o[0],.56f,0);pt(&o[0],.56f,1);return 1;
 case 2:arc(&o[0],.5f,.28f,.5f,.28f,195,395,12);pt(&o[0],0,1);pt(&o[0],1,1);return 1;
 case 3:arc(&o[0],.48f,.25f,.46f,.25f,200,450,12);arc(&o[1],.5f,.74f,.5f,.26f,270,520,12);return 2;
 case 4:pt(&o[0],.72f,1);pt(&o[0],.72f,0);pt(&o[0],0,.7f);pt(&o[0],1,.7f);return 1;
 case 5:pt(&o[0],.92f,0);pt(&o[0],.1f,0);pt(&o[0],.05f,.46f);arc(&o[0],.5f,.68f,.5f,.32f,215,520,14);return 1;
 case 6:arc(&o[0],.5f,.7f,.5f,.3f,0,360,16);pt(&o[1],0,.7f);arc(&o[1],.55f,.45f,.55f,.45f,180,305,8);return 2;
 case 7:pt(&o[0],0,0);pt(&o[0],1,0);pt(&o[0],.36f,1);return 1;
 case 8:arc(&o[0],.5f,.24f,.42f,.24f,0,360,16);arc(&o[1],.5f,.73f,.5f,.27f,0,360,16);return 2;
 default:{unsigned n=unit_lines(6,o);for(unsigned k=0;k<n;k++)for(unsigned i=0;i<o[k].n;i++){o[k].x[i]=1-o[k].x[i];o[k].y[i]=1-o[k].y[i];}return n;}   // 9: the 6 turned half round
 }
}
unsigned lo_glyph_lines(unsigned digit,LOLine out[4]){
 Poly u[4];unsigned n=unit_lines(digit,u);const float pad=LO_GLYPH_STROKE/2.f+.5f;
 for(unsigned k=0;k<n;k++){out[k].n=u[k].n;for(unsigned i=0;i<u[k].n;i++){out[k].x[i]=pad+u[k].x[i]*(LO_GLYPH_W-2*pad);out[k].y[i]=pad+u[k].y[i]*(LO_GLYPH_H-2*pad);}}
 return n;
}
static float seg_dist(float px,float py,float ax,float ay,float bx,float by){
 float dx=bx-ax,dy=by-ay,l=dx*dx+dy*dy,t=l>0?((px-ax)*dx+(py-ay)*dy)/l:0;if(t<0)t=0;if(t>1)t=1;
 float x=ax+t*dx-px,y=ay+t*dy-py;return sqrtf(x*x+y*y);
}
static void glyph_render(uint8_t *g,unsigned digit){
 LOLine l[4];unsigned n=lo_glyph_lines(digit,l);const float r=LO_GLYPH_STROKE/2.f;
 for(int y=0;y<LO_GLYPH_H;y++)for(int x=0;x<LO_GLYPH_W;x++){
  float d=1e9f;for(unsigned k=0;k<n;k++)for(unsigned i=0;i+1<l[k].n;i++){float e=seg_dist(x+.5f,y+.5f,l[k].x[i],l[k].y[i],l[k].x[i+1],l[k].y[i+1]);if(e<d)d=e;}
  float c=r+.5f-d;if(c<0)c=0;if(c>1)c=1;g[y*LO_GLYPH_W+x]=(uint8_t)lrintf(c*LEVEL(TIO_LENS_FULL));
 }
}

/* ---- The view ---- */
static const unsigned kFont[LO_LABELS]={[LO_HINT]=TIO_HINT_FONT,[LO_TIME]=TIO_FONT_LABEL,[LO_BATT]=TIO_FONT_LABEL,[LO_M]=TIO_FONT_BODY,
 [LO_BTEXT]=TIO_FONT_PRIMARY,[LO_DIGIT]=TIO_FONT_HERO,[LO_PREV]=TIO_FONT_PRIMARY,[LO_NEXT]=TIO_FONT_PRIMARY};
static TIORect label_rect(unsigned i){
 const TIORect h=tio_hint_rect(TIO_SURFACE_PAGE);
 switch(i){
 case LO_HINT:return h;
 case LO_TIME:return (TIORect){TIO_CORE_X0,h.y,TLV_STATUS_W,h.h};
 case LO_BATT:return (TIORect){TIO_CORE_X1-TLV_STATUS_W,h.y,TLV_STATUS_W,h.h};
 case LO_M:return (TIORect){TIO_CORE_X0,LO_MSG_M_Y,TIO_CORE_W,TIO_LINE(TIO_FONT_BODY)};
 case LO_BTEXT:return (TIORect){TIO_CORE_X0,LO_MSG_B_Y,TIO_CORE_W,TIO_LINE(TIO_FONT_PRIMARY)};
 case LO_DIGIT:return (TIORect){TIO_PAGE_W/2-LO_SLOT_W/2,LO_DIGIT_Y,LO_SLOT_W,TIO_LINE(TIO_FONT_HERO)};
 default:{   // B's neighbours: 32 px boxes on the hero digit's baseline
  const int base=tio_text_baseline(LO_DIGIT_Y,TIO_FONT_HERO),w=40,cx=TIO_PAGE_W/2+(i==LO_PREV?-LO_NEIGHBOUR_DX:LO_NEIGHBOUR_DX);
  return (TIORect){cx-w/2,base-(int)TIO_FONT_PRIMARY-1,w,TIO_LINE(TIO_FONT_PRIMARY)};}
 }
}
static void put_canvas(LOView *v,unsigned i,const uint8_t *px,int x,int y,int w,int h){
 v->api.place(v->api.ctx,v->canvas[i],x,y,w,h);v->api.buffer(v->api.ctx,v->canvas[i],px,(unsigned)w,(unsigned)h);v->api.visible(v->api.ctx,v->canvas[i],true);
}
static void show_text(LOView *v,unsigned i,const char *s,uint32_t c){
 v->api.text_static(v->api.ctx,v->labels[i],s);if(v->api.color)v->api.color(v->api.ctx,v->labels[i],c);v->api.visible(v->api.ctx,v->labels[i],s&&*s);
}
bool lo_open(LOView *v,unsigned option,const TNWidgets *api,void *surface,void *parent){
 if(!v||option>=LO_OPTIONS||!api||!api->root||!api->label||!api->place||!api->text_static||!api->canvas||!api->buffer||!api->visible)return false;
 buffers();memset(v,0,sizeof *v);v->api=*api;v->api.ctx=surface;v->option=option;v->glyph_digit=-1;
 v->root=api->root(surface,parent);if(!v->root)return false;
 api->place(surface,v->root,0,0,TIO_PAGE_W,TIO_PAGE_H);
 for(unsigned i=0;i<LO_LABELS;i++){
  if(!(v->labels[i]=api->label(surface,v->root,kFont[i]))){api->destroy(surface,v->root);return false;}
  TIORect r=label_rect(i);api->place(surface,v->labels[i],r.x,r.y,r.w,r.h);if(api->clip_text)api->clip_text(surface,v->labels[i]);
  api->visible(surface,v->labels[i],false);
  v->align[i]=i==LO_HINT||i==LO_TIME?0:i==LO_BATT?2:1;
 }
 for(unsigned i=0;i<LO_CANVASES;i++){if(!(v->canvas[i]=api->canvas(surface,v->root))){api->destroy(surface,v->root);return false;}api->visible(surface,v->canvas[i],false);}
 tio_hint_init(&v->hint);tio_caret_init(&v->caret);v->last=TLK_OFF;v->open=true;return true;
}
void lo_input(LOView *v,uint32_t now_ms){tio_hint_input(&v->hint,now_ms);}
bool lo_draw(LOView *v,const TLVScene *s,unsigned lang,uint32_t now){
 if(!v||!v->open)return false;
 tlv_layout(&v->text,s,lang);const char (*tb)[TLV_TEXT]=v->text.text[v->text.bank];   // the shipped view's strings
 if(s->state!=v->last){if(s->state==TLK_ENTRY){tio_hint_enter(&v->hint,now);tio_caret_init(&v->caret);}v->last=s->state;}
 for(unsigned i=0;i<LO_LABELS;i++)v->api.visible(v->api.ctx,v->labels[i],false);
 for(unsigned i=0;i<LO_CANVASES;i++)v->api.visible(v->api.ctx,v->canvas[i],false);
 if(s->state!=TLK_ENTRY){
  if(*tb[TLV_M])show_text(v,LO_M,tb[TLV_M],TIO_LENS_HIGH);
  if(*tb[TLV_B])show_text(v,LO_BTEXT,tb[TLV_B],TIO_LENS_FULL);
  return true;
 }
 // Band T: the hint (lens-high, fading) replaces the time and battery while it is shown.
 if(tio_hint_visible(&v->hint,now))show_text(v,LO_HINT,tio_text(TT_LOCK_HINT,lang),tio_hint_color(&v->hint,now));
 else{show_text(v,LO_TIME,tb[TLV_TIME],TIO_LENS_MID);show_text(v,LO_BATT,tb[TLV_BATT],TIO_LENS_MID);}
 const unsigned slot=s->slot<TLK_PIN_LEN?s->slot:TLK_PIN_LEN-1,d=s->digit%10;
 v->digit[0][0]=(char)('0'+d);v->digit[1][0]=(char)('0'+(d+9)%10);v->digit[2][0]=(char)('0'+(d+1)%10);
 int cx,cy;
 if(v->option==LO_B){
  TIORect r=label_rect(LO_DIGIT);show_text(v,LO_DIGIT,v->digit[0],TIO_LENS_FULL);
  show_text(v,LO_PREV,v->digit[1],TIO_LENS_MID);show_text(v,LO_NEXT,v->digit[2],TIO_LENS_MID);
  for(unsigned i=0;i<TLK_PIN_LEN;i++)put_canvas(v,LO_DOT0+i,i<slot?row_high:i==slot?row_full:row_track,lo_row_cx(i)-LO_DOT_B/2,LO_B_ROW_Y,LO_DOT_B,LO_DOT_B);
  cx=tio_caret_centered(r.x+r.w/2);cy=tio_caret_top(r.y,TIO_FONT_HERO);
 }else{
  const bool glyph=v->option==LO_C;const int top=glyph?LO_GLYPH_Y:LO_DIGIT_Y;
  const int bar=glyph?LO_GLYPH_Y+LO_GLYPH_H+TIO_CARET_GAP:tio_caret_top(LO_DIGIT_Y,TIO_FONT_HERO);
  const int mid=glyph?LO_GLYPH_Y+LO_GLYPH_H/2:tio_text_baseline(LO_DIGIT_Y,TIO_FONT_HERO)-17;   // dot centre: middle of the digit's ink
  for(unsigned i=0;i<TLK_PIN_LEN;i++){
   if(i<slot)put_canvas(v,LO_DOT0+i,dot_high,lo_slot_cx(i)-LO_DOT/2,mid-LO_DOT/2,LO_DOT,LO_DOT);
   else if(i>slot)put_canvas(v,LO_TRACK0+i,track_bar,lo_slot_cx(i)-LO_TRACK_W/2,bar,LO_TRACK_W,LO_TRACK_H);
  }
  if(glyph){
   if(v->glyph_digit!=(int)d){glyph_render(v->glyph,d);v->glyph_digit=(int)d;}
   put_canvas(v,LO_GLYPH,v->glyph,lo_slot_cx(slot)-LO_GLYPH_W/2,top,LO_GLYPH_W,LO_GLYPH_H);
  }else{
   v->api.place(v->api.ctx,v->labels[LO_DIGIT],lo_slot_cx(slot)-LO_SLOT_W/2,LO_DIGIT_Y,LO_SLOT_W,TIO_LINE(TIO_FONT_HERO));
   show_text(v,LO_DIGIT,v->digit[0],TIO_LENS_FULL);
  }
  cx=tio_caret_centered(lo_slot_cx(slot));cy=bar;
 }
 tio_caret_to(&v->caret,cx,cy,now,false);TIORect c=tio_caret_rect(&v->caret,now);
 put_canvas(v,LO_CARET,caret_bar,c.x,c.y,c.w,c.h);
 return true;
}
void lo_close(LOView *v){if(v&&v->open&&v->root)v->api.destroy(v->api.ctx,v->root);if(v)memset(v,0,sizeof *v);}
