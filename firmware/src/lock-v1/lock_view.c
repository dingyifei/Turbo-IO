#include "lock_view.h"
#include "lock_glyphs.h"
#include "../common-v1/tio_text.h"
#include <string.h>
TIO_PAGES_CHECK;
_Static_assert(_Alignof(TLKView)>=64,"the canvas buffers are 64-byte aligned");
#define LEVEL(c) ((uint8_t)((c)>>8&255u))
static void put(char *d,const char *s){size_t n=0;while(n<TLV_TEXT-1&&s[n])n++;memcpy(d,s,n);d[n]=0;}
// "{}" in a catalog string is replaced by arg.
static void fill(char *d,const char *fmt,const char *arg){
 char out[TLV_TEXT];size_t o=0;
 for(const char *p=fmt;*p&&o<TLV_TEXT-1;p++){
  if(p[0]=='{'&&p[1]=='}'){for(const char *a=arg;*a&&o<TLV_TEXT-1;a++)out[o++]=*a;p++;}else out[o++]=*p;
 }
 out[o]=0;put(d,out);
}
static void num(char *d,unsigned n){char t[12];unsigned i=0;do{t[i++]=(char)('0'+n%10);n/=10;}while(n&&i<11);unsigned j=0;while(i)d[j++]=t[--i];d[j]=0;}
static void clock_text(char *d,uint32_t s){unsigned m=s/60,x=s%60;char t[12];num(t,m);size_t n=strlen(t);memcpy(d,t,n);d[n++]=':';d[n++]=(char)('0'+x/10);d[n++]=(char)('0'+x%10);d[n]=0;}
// The launcher menu's band T format (focus_menu.c fm_view_update): HH:MM and N%, or --:-- and --% when unknown.
static void hhmm(char *d,int64_t local){
 put(d,"--:--");if(local<946684800||local>4102444800LL)return;
 unsigned secs=(unsigned)((uint64_t)local%86400),h=secs/3600,m=secs/60%60;d[0]=(char)('0'+h/10);d[1]=(char)('0'+h%10);d[3]=(char)('0'+m/10);d[4]=(char)('0'+m%10);
}
static void percent(char *d,int battery){if(battery<0||battery>100){put(d,"--%");return;}num(d,(unsigned)battery);size_t n=strlen(d);d[n]='%';d[n+1]=0;}
static void tries(char *d,unsigned n,unsigned lang){char t[12];num(t,n);fill(d,n==1?tio_text(TT_LOCK_TRY_ONE,lang):tio_text(TT_LOCK_TRIES,lang),t);}

void tlv_snapshot(TLVScene *s,TLK *t,uint32_t now_s,uint32_t now_ms){
 uint32_t left=t->state==TLK_WAITING?tlk_delay_left(t,now_s):0;
 *s=(TLVScene){.state=t->state,.slot=t->slot,.digit=t->digit,.notice=t->notice,.wrong=t->rec.wrong,.delay_left=left,.now_ms=now_ms,.local=0,.battery=-1};
}

/* Label boxes and fonts. */
static const unsigned kFont[TLV_LABELS]={[TLV_HINT]=TIO_HINT_FONT,[TLV_TIME]=TIO_FONT_LABEL,[TLV_BATT]=TIO_FONT_LABEL,[TLV_M]=TIO_FONT_BODY,[TLV_B]=TIO_FONT_PRIMARY};
static TIORect label_rect(unsigned i){
 const TIORect h=tio_hint_rect(TIO_SURFACE_PAGE);
 switch(i){
 case TLV_HINT:return h;
 case TLV_TIME:return (TIORect){TIO_CORE_X0,h.y,TLV_STATUS_W,h.h};
 case TLV_BATT:return (TIORect){TIO_CORE_X1-TLV_STATUS_W,h.y,TLV_STATUS_W,h.h};   // right-aligned by the native side
 case TLV_M:return (TIORect){TIO_CORE_X0,TLV_MSG_M_Y,TIO_CORE_W,TIO_LINE(TIO_FONT_BODY)};   // centred by the native side
 default:return (TIORect){TIO_CORE_X0,TLV_MSG_B_Y,TIO_CORE_W,TIO_LINE(TIO_FONT_PRIMARY)};  // centred by the native side
 }
}
static void canvas_size(unsigned i,int *w,int *h){
 if(i==TLV_GLYPH){*w=TLV_GLYPH_W;*h=TLV_GLYPH_H;}else if(i>=TLV_DOT0&&i<TLV_TRACK0){*w=*h=TLV_DOT;}else{*w=TIO_CARET_W;*h=TIO_CARET_H;}
}
/* An anti-aliased round dot of n px at a level: 4x4 samples per pixel, exact in integers (coordinates in eighths of a pixel). */
static void disc(uint8_t *d,int n,uint8_t level){
 for(int y=0;y<n;y++)for(int x=0;x<n;x++){
  int in=0;for(int sy=0;sy<4;sy++)for(int sx=0;sx<4;sx++){int X=8*x+2*sx+1-4*n,Y=8*y+2*sy+1-4*n;in+=X*X+Y*Y<=16*n*n;}
  d[y*n+x]=(uint8_t)(level*in/16);
 }
}
/* Digit d from the 4 bpp table into the glyph buffer (an even pixel is the high nibble; level = nibble * 17). */
static void glyph_decode(uint8_t *out,unsigned d){
 const unsigned char *p=tlv_glyph4[d%10];
 for(unsigned i=0;i<TLV_GLYPH_W*TLV_GLYPH_H;i++)out[i]=(uint8_t)(((p[i/2]>>(i%2?0:4))&15u)*17u);
}

bool tlv_open(TLKView *v,const TNWidgets *api,void *surface,void *parent){
 if(!v||((uintptr_t)v&63u)||!api||!api->root||!api->label||!api->place||!api->text_static||!api->canvas||!api->buffer||!api->visible||!api->destroy)return false;
 memset(v,0,sizeof *v);v->api=*api;v->api.ctx=surface;
 memset(v->caret_px,LEVEL(TIO_LENS_FULL),sizeof v->caret_px);memset(v->track_px,LEVEL(TIO_LENS_TRACK),sizeof v->track_px);
 disc(v->dot_px,TLV_DOT,LEVEL(TIO_LENS_HIGH));
 v->root=api->root(surface,parent);if(!v->root)return false;
 api->place(surface,v->root,0,0,TIO_PAGE_W,TIO_PAGE_H);
 for(unsigned i=0;i<TLV_LABELS;i++){
  if(!(v->labels[i]=api->label(surface,v->root,kFont[i]))){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}
  TIORect r=label_rect(i);api->place(surface,v->labels[i],r.x,r.y,r.w,r.h);if(api->clip_text)api->clip_text(surface,v->labels[i]);
  api->visible(surface,v->labels[i],false);
 }
 for(unsigned i=0;i<TLV_CANVASES;i++){
  if(!(v->canvas[i]=api->canvas(surface,v->root))){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}
  int w,h;canvas_size(i,&w,&h);api->place(surface,v->canvas[i],0,0,w,h);
  if(i!=TLV_GLYPH)api->buffer(surface,v->canvas[i],tlv_canvas_pixels(v,i),(unsigned)w,(unsigned)h);   // the glyph gets its buffer with its first digit
  api->visible(surface,v->canvas[i],false);
 }
 tio_hint_init(&v->hint);tio_caret_init(&v->caret);v->caret.reduce_motion=true;   // the lock screen has no animation timer: the caret snaps
 v->shown.digit=v->glyph_digit=-1;
 api->visible(surface,v->root,true);
 v->last_state=TLK_OFF;v->open=true;return true;
}

static void canvas_at(TLVFrame *f,unsigned i,int x,int y){f->on[i]=true;f->x[i]=(int16_t)x;f->y[i]=(int16_t)y;}
bool tlv_layout(TLKView *v,const TLVScene *s,unsigned lang){
 const uint32_t now=s->now_ms;
 if(s->state==TLK_ENTRY){
  // The hint shows when the PIN screen appears and again after every input (a wheel step changes the digit, a press the slot).
  if(v->last_state!=TLK_ENTRY){tio_hint_enter(&v->hint,now);tio_caret_init(&v->caret);v->caret.reduce_motion=true;}
  else if(s->slot!=v->last_slot||s->digit!=v->last_digit)tio_hint_input(&v->hint,now);
  v->last_slot=s->slot;v->last_digit=s->digit;
 }
 v->last_state=s->state;
 TLVFrame *f=&v->next;memset(f,0,sizeof *f);f->digit=-1;
 char t[TLV_TEXT];
 switch(s->state){
 case TLK_ENTRY:{
  if(tio_hint_visible(&v->hint,now)){put(f->text[TLV_HINT],tio_text(TT_LOCK_HINT,lang));f->color[TLV_HINT]=tio_hint_color(&v->hint,now);}
  else{hhmm(f->text[TLV_TIME],s->local);f->color[TLV_TIME]=TIO_LENS_MID;percent(f->text[TLV_BATT],s->battery);f->color[TLV_BATT]=TIO_LENS_MID;}
  const unsigned slot=s->slot<TLK_PIN_LEN?s->slot:TLK_PIN_LEN-1;
  for(unsigned i=0;i<TLK_PIN_LEN;i++){
   const int cx=tlv_slot_cx(i);
   if(i<slot)canvas_at(f,TLV_DOT0+i,cx-TLV_DOT/2,TLV_DOT_CY-TLV_DOT/2);                      // entered: a dot
   else if(i>slot)canvas_at(f,TLV_TRACK0+i,cx-TIO_CARET_W/2,TLV_CARET_Y);                    // empty: a track bar
  }
  const int cx=tlv_slot_cx(slot);
  canvas_at(f,TLV_GLYPH,cx-TLV_GLYPH_W/2,TLV_GLYPH_Y);f->digit=(int8_t)(s->digit%10);         // the focused digit, drawn
  tio_caret_to(&v->caret,tio_caret_centered(cx),TLV_CARET_Y,now,false);TIORect c=tio_caret_rect(&v->caret,now);
  canvas_at(f,TLV_CARET,c.x,c.y);
  break;}
 case TLK_WRONG:put(f->text[TLV_B],tio_text(TT_LOCK_WRONG,lang));break;
 case TLK_WAITING:   // band M: the wrong-try count; band B: the countdown
  tries(f->text[TLV_M],s->wrong,lang);
  // no valid clock: the delay cannot end on the glasses until the phone sets the time, so say how out instead of 0:00
  if(s->delay_left==UINT32_MAX)put(f->text[TLV_B],tio_text(TT_LOCK_USE_PHONE,lang));
  else{clock_text(t,s->delay_left);fill(f->text[TLV_B],tio_text(TT_LOCK_TRY_AGAIN,lang),t);}
  break;
 case TLK_USE_PHONE:put(f->text[TLV_B],tio_text(TT_LOCK_USE_PHONE,lang));break;
 case TLK_UNLOCKED_MSG:put(f->text[TLV_B],tio_text(TT_LOCK_UNLOCKED,lang));break;   // phone unlock
 case TLK_NOTICE:    // band M: "since last unlock"; band B: the count
  put(f->text[TLV_M],tio_text(TT_LOCK_SINCE,lang));tries(f->text[TLV_B],s->notice,lang);
  break;
 default:break;
 }
 if(s->state!=TLK_ENTRY){if(*f->text[TLV_M])f->color[TLV_M]=TIO_LENS_HIGH;if(*f->text[TLV_B])f->color[TLV_B]=TIO_LENS_FULL;}
 return !v->drawn||memcmp(f,&v->shown,sizeof *f)!=0;
}

bool tlv_draw(TLKView *v,const TLVScene *s,unsigned lang){
 if(!v||!v->open||!v->root)return false;
 if(v->api.idle&&!v->api.idle(v->api.ctx))return false;
 if(!tlv_layout(v,s,lang))return true;
 const TNWidgets *a=&v->api;TLVFrame *n=&v->next,*o=&v->shown;const bool all=!v->drawn;
 // The glyph first: a new digit is decoded into its buffer, which is handed to the canvas again (that redraws it).
 if(n->digit>=0&&n->digit!=v->glyph_digit){glyph_decode(v->glyph,(unsigned)n->digit);a->buffer(a->ctx,v->canvas[TLV_GLYPH],v->glyph,TLV_GLYPH_W,TLV_GLYPH_H);v->glyph_digit=n->digit;}
 o->digit=n->digit;
 for(unsigned i=0;i<TLV_CANVASES;i++){
  if(n->on[i]&&(all||!o->on[i]||n->x[i]!=o->x[i]||n->y[i]!=o->y[i])){int w,h;canvas_size(i,&w,&h);a->place(a->ctx,v->canvas[i],n->x[i],n->y[i],w,h);o->x[i]=n->x[i];o->y[i]=n->y[i];}
  if(all||n->on[i]!=o->on[i]){a->visible(a->ctx,v->canvas[i],n->on[i]);o->on[i]=n->on[i];}
 }
 for(unsigned i=0;i<TLV_LABELS;i++){
  const bool text=all||strcmp(n->text[i],o->text[i])!=0,color=all||n->color[i]!=o->color[i];
  if(text){memcpy(o->text[i],n->text[i],TLV_TEXT);a->text_static(a->ctx,v->labels[i],o->text[i]);}
  if((text||color)&&a->color&&n->color[i])a->color(a->ctx,v->labels[i],n->color[i]);
  o->color[i]=n->color[i];
  if(text)a->visible(a->ctx,v->labels[i],o->text[i][0]!=0);
 }
 v->drawn=true;return true;
}
void tlv_close(TLKView *v){if(v&&v->open&&v->root)v->api.destroy(v->api.ctx,v->root);if(v)memset(v,0,sizeof *v);}
