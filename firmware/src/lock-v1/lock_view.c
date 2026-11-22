#include "lock_view.h"
#include "../common-v1/tio_text.h"
#include "../common-v1/tio_ui.h"
#include <string.h>
TIO_PAGES_CHECK;
#define SLOT_PITCH 64
#define SLOT_W 48
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
static void tries(char *d,unsigned n,unsigned lang){char t[12];num(t,n);fill(d,n==1?tio_text(TT_LOCK_TRY_ONE,lang):tio_text(TT_LOCK_TRIES,lang),t);}

void tlv_snapshot(TLVScene *s,TLK *t,uint32_t now_s,uint32_t now_ms){
 uint32_t left=t->state==TLK_WAITING?tlk_delay_left(t,now_s):0;
 *s=(TLVScene){.state=t->state,.slot=t->slot,.digit=t->digit,.notice=t->notice,.wrong=t->rec.wrong,.delay_left=left,.now_ms=now_ms};
}

static TIORect rect(unsigned i){
 const int x0=(TIO_PAGE_W-(TLK_PIN_LEN-1)*SLOT_PITCH-SLOT_W)/2;
 const int digit_y=TIO_PAGE_M1-TIO_LINE(TIO_FONT_HERO)/2;
 switch(i){
 case TLV_T:return (TIORect){TIO_CORE_X0,TIO_PAGE_T0,TIO_CORE_W,TIO_LINE(TIO_FONT_LABEL)};
 case TLV_M:return (TIORect){TIO_CORE_X0,TIO_PAGE_T1,TIO_CORE_W,TIO_LINE(TIO_FONT_BODY)};
 case TLV_B:return (TIORect){TIO_CORE_X0,TIO_PAGE_B1-TIO_LINE(TIO_FONT_PRIMARY),TIO_CORE_W,TIO_LINE(TIO_FONT_PRIMARY)};
 case TLV_CARET:return (TIORect){x0,digit_y+TIO_LINE(TIO_FONT_HERO),SLOT_W,TIO_LINE(TIO_FONT_BODY)};
 default:return (TIORect){x0+(int)(i-TLV_S0)*SLOT_PITCH,digit_y,SLOT_W,TIO_LINE(TIO_FONT_HERO)};
 }
}
static unsigned font(unsigned i){return i==TLV_T?TIO_FONT_LABEL:i==TLV_M||i==TLV_CARET?TIO_FONT_BODY:i==TLV_B?TIO_FONT_PRIMARY:TIO_FONT_HERO;}

bool tlv_open(TLKView *v,const TNWidgets *api,void *surface,void *parent){
 if(!v||!api||!api->root||!api->label||!api->place||!api->text_static)return false;
 memset(v,0,sizeof *v);v->api=*api;v->api.ctx=surface;
 v->root=api->root(surface,parent);if(!v->root)return false;
 api->place(surface,v->root,0,0,TIO_PAGE_W,TIO_PAGE_H);
 for(unsigned i=0;i<TLV_LABELS;i++){
  v->labels[i]=api->label(surface,v->root,font(i));
  if(!v->labels[i]){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}
  TIORect r=rect(i);api->place(surface,v->labels[i],r.x,r.y,r.w,r.h);if(api->clip_text)api->clip_text(surface,v->labels[i]);
 }
 if(api->visible)api->visible(surface,v->root,true);
 v->last_state=TLK_OFF;v->open=true;return true;
}

bool tlv_layout(TLKView *v,const TLVScene *s,unsigned lang){
 if(s->state==TLK_ENTRY&&v->last_state!=TLK_ENTRY)v->entry_ms=s->now_ms;   // the hint shows for 3 s after the PIN screen appears
 v->last_state=s->state;
 unsigned b=v->bank^1;memset(v->text[b],0,sizeof v->text[b]);uint32_t colors[TLV_LABELS]={0};
 char t[TLV_TEXT];
 switch(s->state){
 case TLK_ENTRY:{
  if((uint32_t)(s->now_ms-v->entry_ms)<TLV_HINT_MS)put(v->text[b][TLV_T],tio_text(TT_LOCK_HINT,lang));colors[TLV_T]=TIO_LENS_MID;
  for(unsigned i=0;i<TLK_PIN_LEN;i++){
   char *d=v->text[b][TLV_S0+i];
   if(i<s->slot){put(d,"\xc2\xb7");colors[TLV_S0+i]=TIO_LENS_HIGH;}                // entered: a dot
   else if(i==s->slot){d[0]=(char)('0'+s->digit);d[1]=0;colors[TLV_S0+i]=TIO_LENS_FULL;}  // focused digit
   else{put(d,"-");colors[TLV_S0+i]=TIO_LENS_TRACK;}                            // empty slot
  }
  put(v->text[b][TLV_CARET],"^");colors[TLV_CARET]=TIO_LENS_FULL;
  break;}
 case TLK_WRONG:put(v->text[b][TLV_B],tio_text(TT_LOCK_WRONG,lang));colors[TLV_B]=TIO_LENS_FULL;break;
 case TLK_WAITING:   // band M: the wrong-try count; band B: the countdown
  tries(v->text[b][TLV_M],s->wrong,lang);colors[TLV_M]=TIO_LENS_HIGH;
  // no valid clock: the delay cannot end on the glasses until the phone sets the time, so say how out instead of 0:00
  if(s->delay_left==UINT32_MAX)put(v->text[b][TLV_B],tio_text(TT_LOCK_USE_PHONE,lang));
  else{clock_text(t,s->delay_left);fill(v->text[b][TLV_B],tio_text(TT_LOCK_TRY_AGAIN,lang),t);}
  colors[TLV_B]=TIO_LENS_FULL;
  break;
 case TLK_USE_PHONE:put(v->text[b][TLV_B],tio_text(TT_LOCK_USE_PHONE,lang));colors[TLV_B]=TIO_LENS_FULL;break;
 case TLK_NOTICE:    // band M: "since last unlock"; band B: the count
  put(v->text[b][TLV_M],tio_text(TT_LOCK_SINCE,lang));colors[TLV_M]=TIO_LENS_HIGH;
  tries(v->text[b][TLV_B],s->notice,lang);colors[TLV_B]=TIO_LENS_FULL;
  break;
 default:break;
 }
 bool differs=memcmp(v->text[b],v->text[v->bank],sizeof v->text[b])||memcmp(colors,v->colors,sizeof colors)||!v->root;
 if(!differs)return false;
 memcpy(v->colors,colors,sizeof colors);v->bank=b;return true;
}

bool tlv_draw(TLKView *v,const TLVScene *s,unsigned lang){
 if(!v||!v->open||!v->root)return false;
 if(v->api.idle&&!v->api.idle(v->api.ctx))return false;
 if(!tlv_layout(v,s,lang))return true;
 for(unsigned i=0;i<TLV_LABELS;i++){
  v->api.text_static(v->api.ctx,v->labels[i],v->text[v->bank][i]);
  if(v->api.color&&v->colors[i])v->api.color(v->api.ctx,v->labels[i],v->colors[i]);
 }
 return true;
}
void tlv_close(TLKView *v){if(v&&v->open&&v->root)v->api.destroy(v->api.ctx,v->root);if(v)memset(v,0,sizeof *v);}
