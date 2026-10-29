#include "../common-v1/tio_text.h"
#include "focus_view.h"
#include <string.h>
static void copy(char *d,const char *s){size_t n=0;while(n<111&&s[n])n++;memcpy(d,s,n);d[n]=0;}
static void clock_text(char *s,uint32_t seconds){unsigned m=seconds/60,n=seconds%60;unsigned at=0;if(m>=100)s[at++]='0'+m/100;s[at++]='0'+m/10%10;s[at++]='0'+m%10;s[at++]=':';s[at++]='0'+n/10;s[at++]='0'+n%10;s[at]=0;}
/* n of 4 focus sessions in the long-break cycle. */
static unsigned session(const TFocus *s){return s->phase==0&&s->status!=TF_DONE?s->completed%4+1:s->completed?(s->completed+3)%4+1:1;}
static void count_text(char *t,const TFocus *s){t[0]='0'+session(s);t[1]=' ';t[2]='/';t[3]=' ';t[4]='4';t[5]=0;}
TIORect tf_title_rect(void){return (TIORect){TIO_CORE_X0,TIO_PAGE_T0+6,TIO_CORE_W-60,TIO_LINE(TIO_FONT_LABEL)};}
TIORect tf_count_rect(void){return (TIORect){TIO_CORE_X1-48,TIO_PAGE_T0+6,48,TIO_LINE(TIO_FONT_LABEL)};}
TIORect tf_bar_rect(void){return (TIORect){TIO_CORE_X0,TIO_PAGE_T1-12,TF_BAR_W,TF_BAR_H};}
TIORect tf_status_rect(void){return (TIORect){TIO_CORE_X0,TIO_PAGE_T1+24,TIO_CORE_W,TIO_LINE(TIO_FONT_BODY)};}
TIORect tf_time_rect(void){return (TIORect){TIO_CORE_X0,TIO_PAGE_B1-TIO_LINE(TIO_FONT_HERO),TIO_CORE_W,TIO_LINE(TIO_FONT_HERO)};}
static void bar(uint8_t *p,const TFocus *s){uint32_t total=(s->duration_s>TF_MAX_SECONDS?TF_MAX_SECONDS:s->duration_s)*1000u,left=s->remaining_ms>total?total:s->remaining_ms;unsigned fill=total?(total-left)*TF_BAR_W/total:0;
 for(unsigned x=0;x<TF_BAR_W;x++)for(unsigned y=0;y<TF_BAR_H;y++)p[y*TF_BAR_W+x]=x<fill?TF_FILL_LEVEL:TF_TRACK_LEVEL;}
bool tf_view_open(TFView *v,const TNWidgets *api,void *surface,void *parent){if(!v||!api||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->api.ctx=surface;
 v->root=api->root(surface,parent);if(!v->root)return false;api->place(surface,v->root,0,0,TIO_PAGE_W,TIO_PAGE_H);
 const unsigned fonts[TF_LABELS]={TIO_FONT_LABEL,TIO_FONT_LABEL,TIO_FONT_BODY,TIO_FONT_HERO};const uint32_t colors[TF_LABELS]={TIO_LENS_MID,TIO_LENS_MID,TIO_LENS_HIGH,TIO_LENS_FULL};
 const TIORect rects[TF_LABELS]={tf_title_rect(),tf_count_rect(),tf_status_rect(),tf_time_rect()};
 for(unsigned i=0;i<TF_LABELS;i++){v->labels[i]=api->label(surface,v->root,fonts[i]);if(!v->labels[i]){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}
  api->place(surface,v->labels[i],rects[i].x,rects[i].y,rects[i].w,rects[i].h);if(api->clip_text)api->clip_text(surface,v->labels[i]);if(api->color)api->color(surface,v->labels[i],colors[i]);}
 v->bar=api->canvas(surface,v->root);if(!v->bar){api->destroy(surface,v->root);memset(v,0,sizeof *v);return false;}
 {TIORect b=tf_bar_rect();api->place(surface,v->bar,b.x,b.y,b.w,b.h);}
 tio_hint_init(&v->hint);v->title_color=TIO_LENS_MID;v->open=true;return true;
}
void tf_view_enter(TFView *v,uint32_t now){if(v)tio_hint_enter(&v->hint,now);}
void tf_view_input(TFView *v,uint32_t now){if(v)tio_hint_input(&v->hint,now);}
static uint32_t title_color(const TFView *v,uint32_t now,bool compact){return !compact&&tio_hint_visible(&v->hint,now)?tio_hint_color(&v->hint,now):TIO_LENS_MID;}
bool tf_view_due(const TFView *v,uint32_t now,bool compact){return v&&v->open&&title_color(v,now,compact)!=v->title_color;}
bool tf_view_draw(TFView *v,const TFocus *s,bool compact,uint32_t now){unsigned lang=tio_lang();if(!v||!v->open||!v->root||!v->api.idle(v->api.ctx))return false;unsigned b=v->bank^1;memset(v->text[b],0,sizeof v->text[b]);
 const bool hint=!compact&&tio_hint_visible(&v->hint,now);
 const char *phase=s->phase==0?tio_text(TT_FOCUS_T_FOCUS,lang):s->phase==1?tio_text(TT_FOCUS_T_SHORT,lang):tio_text(TT_FOCUS_T_LONG,lang);
 const char *hints=s->status==TF_RUNNING?tio_text(TT_FOCUS_H_RUN,lang):s->status==TF_PAUSED?tio_text(TT_FOCUS_H_PAUSED,lang):s->status==TF_DONE?tio_text(TT_FOCUS_H_DONE,lang):tio_text(TT_FOCUS_H_IDLE,lang);
 const char *next=s->phase?tio_text(TT_FOCUS_NEXT_FOCUS,lang):(s->completed+1)%4==0?tio_text(TT_FOCUS_NEXT_LONG,lang):tio_text(TT_FOCUS_NEXT_SHORT,lang);
 copy(v->text[b][TF_L_TITLE],hint?hints:compact?tio_text(TT_FOCUS_RUNNING,lang):phase);
 count_text(v->text[b][TF_L_COUNT],s);
 copy(v->text[b][TF_L_STATUS],s->status==TF_DONE?tio_text(TT_FOCUS_DONE,lang):s->status==TF_PAUSED?tio_text(TT_FOCUS_PAUSED,lang):s->status==TF_RUNNING?next:tio_text(TT_FOCUS_READY,lang));
 clock_text(v->text[b][TF_L_TIME],(s->remaining_ms+999)/1000);
 for(unsigned i=0;i<TF_LABELS;i++){v->api.text_static(v->api.ctx,v->labels[i],v->text[b][i]);v->api.visible(v->api.ctx,v->labels[i],i==TF_L_TITLE||!compact);}
 v->api.visible(v->api.ctx,v->labels[TF_L_COUNT],!compact&&!hint);
 uint32_t color=title_color(v,now,compact);if(v->api.color&&color!=v->title_color)v->api.color(v->api.ctx,v->labels[TF_L_TITLE],color);v->title_color=color;
 bar(v->bar_px[b],s);v->api.buffer(v->api.ctx,v->bar,v->bar_px[b],TF_BAR_W,TF_BAR_H);v->api.visible(v->api.ctx,v->bar,!compact);v->api.visible(v->api.ctx,v->root,true);v->bank=b;return true;
}
bool tf_view_close(TFView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;v->open=false;void *root=v->root;v->root=NULL;v->api.destroy(v->api.ctx,root);memset(v->labels,0,sizeof v->labels);v->bar=NULL;return true;}
