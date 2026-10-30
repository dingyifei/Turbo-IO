#include "../common-v1/tio_text.h"
#include "../common-v1/business_idle.h"
#include "../app-runtime-v1/app_service.h"
#include "music_service.h"
#include "music.h"
#include "../navigation-runtime-v1/nav_text.h"
#include "music_input.h"
#include "music_layout.h"
#include "../common-v1/tio_hint.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include <string.h>
#include "../focus-v1/focus_service.h"
#define TM_MESSAGE 0x544d5531u
#define TM_CURRENT 0u
#define TM_NEXT 1u
#define TM_TRACK 2u
#define TM_CURRENT20 3u   /* the current lyric's other two fonts: one label per font, only the fitted one is shown */
#define TM_CURRENT16 4u
#define TM_LABELS 5u
typedef struct {
 _Alignas(64) uint8_t pixels[TM_ART*TM_ART];
 char track[184],current[TM_CUR_CAP],next[244];
} Frame;
typedef struct {
 char raw[TM_CUR_RAW];TMMusic music;TNWidgets api;TMMusicSlot *slot;void *app,*timer,*root,*canvas,*labels[TM_LABELS],*bar;
 Frame frames[2];unsigned front;uint32_t token,last_frame,last_check,last_event,last_wheel;
 uint32_t request_id,track_color;TIOHint hint;uint8_t event,event_tries,shown_slot;bool shown_ok,shown_next,retired,closing,waiting,focus_transition;TMInput input;
} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned);
extern const char *nav_top_app(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern bool nav_bonded(void *),nav_folded(void *),tio_business_idle(void);
extern int nav_connection(unsigned),nav_force_off(void),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void nav_stop_event(void *),native_text_color(void *,uint32_t,uint32_t),menu_opa(void *,uint8_t,uint32_t);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static bool same(const char *a,const char *b){if(!a)return false;for(unsigned i=0;i<96;i++){if(a[i]!=b[i])return false;if(!b[i])return true;}return false;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19971594,0x3c);}
static TNNavSlot *navslot(void *app){return app?((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation:NULL;}
static TMMusicSlot *slot_of(void *app){TNNavSlot *n=navslot(app);return n?n->music:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){void *m=nav_monitors(),*i=m?nav_input(m):NULL;return same(nav_top_app(),"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&tio_business_idle();}
static bool owns(Control *c){return !c->retired&&c->slot&&c->app&&ptr(manager(),0x10)==c->app&&home();}
static void release(Control *c){if(c->token){nav_release_always_on("turbo_music_v1",c->token);c->token=0;}}
static bool wake(Control *c){if(!owns(c))return false;if(!c->token)c->token=nav_always_on("turbo_music_v1");if(!c->token)return false;nav_screen_on(true);c->music.awake=true;c->music.wake_tick=stream_tick();return true;}
static void put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static void emit(Control *c,unsigned event,unsigned result,uint32_t sid,uint32_t gen,uint32_t seq){
 uint8_t raw[32]={ 'T','M','A','1',1,0,0,0 },out[220];raw[5]=event;raw[6]=result;
 if(c){raw[7]=(c->music.active?1:0)|(c->music.awake?2:0)|4;put(raw+20,c->request_id);put(raw+24,tm_position(&c->music,stream_tick()));}
 put(raw+8,sid);put(raw+12,gen);put(raw+16,seq);put(raw+28,tm_crc(raw,28));
 static const char prefix[]="{\"cmd\":\"turbo_music_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 unsigned len=sizeof prefix-1+64+sizeof suffix-1,pos=0;out[pos++]=8;out[pos++]=1;out[pos++]=16;out[pos++]=6;out[pos++]=26;if(len>=128){out[pos++]=(len&127)|128;out[pos++]=len>>7;}else out[pos++]=len;
 memcpy(out+pos,prefix,sizeof prefix-1);pos+=sizeof prefix-1;for(unsigned i=0;i<32;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}memcpy(out+pos,suffix,sizeof suffix-1);pos+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,pos,NULL);
}
static void request(Control *c,unsigned event){if(!c)return;c->request_id++;if(!c->request_id)c->request_id=1;c->event=event;c->event_tries=0;c->last_event=0;}
static void close_view(Control *c,bool notify){if(!c)return;release(c);c->music.active=c->music.awake=false;c->waiting=false;if(c->root)c->closing=true;if(notify)request(c,TM_VIEW_CLOSED);}
static void deleted(void *e){Control *c=stream_event_user(e);if(!c)return;c->root=NULL;c->canvas=NULL;for(unsigned i=0;i<TM_LABELS;i++)c->labels[i]=NULL;close_view(c,false);c->closing=false;}
static void copy_text(char *out,size_t cap,const char *text){size_t n=strlen(text);if(n>=cap)n=cap-1;memcpy(out,text,n);out[n]=0;}
static bool render(Control *c,uint32_t now){unsigned lang=tio_lang();if(!c->root||c->closing||!c->api.idle(NULL))return false;
 Frame *f=&c->frames[1-c->front];
 /* LensMusic: current line (band B) and the line after it (band M); the previous line is dropped.
  * The artwork tile, label pointers and colours switch together only while DMA is idle. */
 char *cur=c->raw;char next[244]={0};cur[0]=0;
 if(c->waiting){copy_text(cur,TM_CUR_RAW,tio_text(TT_MUSIC_PICK,lang));}
 else {int line=tm_line(&c->music,now);tm_text(&c->music,line,cur,TM_CUR_RAW);tm_text(&c->music,line+1,next,sizeof next);
  if(!c->music.lyrics_ready)copy_text(cur,TM_CUR_RAW,tio_text(TT_MUSIC_LYRICS,lang));}
 tm_clean(cur);tm_clean(next);TMFit fit=tm_fit_current(cur,f->current,sizeof f->current);tm_one_line(next,TIO_CORE_W,TM_NEXT_FONT,f->next,sizeof f->next);
 /* Band T: the control hint (lens-high, fading) for TIO_HINT_MS after entry and every input, else the track in lens-mid. */
 bool hint=tio_hint_visible(&c->hint,now);uint32_t color=hint?tio_hint_color(&c->hint,now):TIO_LENS_MID;
 if(hint)copy_text(f->track,sizeof f->track,tio_text(c->music.playing?TT_MUSIC_CONTROLS_PAUSE:TT_MUSIC_CONTROLS_PLAY,lang));
 else {const char *title=c->waiting?tio_text(TT_MUSIC_TITLE,lang):c->music.title;size_t n=0;while(n<sizeof f->track-1&&title[n]&&n<95){f->track[n]=title[n];n++;}
  if(!c->waiting&&c->music.artist[0]&&n+8<sizeof f->track){f->track[n++]=' ';f->track[n++]=(char)0xc2;f->track[n++]=(char)0xb7;f->track[n++]=' ';for(unsigned k=0;k<80&&c->music.artist[k]&&n<sizeof f->track-1;k++)f->track[n++]=c->music.artist[k];}
  f->track[n]=0;}
 tm_art_tile(c->music.cover_ready?c->music.cover:NULL,f->pixels);
 c->api.buffer(NULL,c->canvas,f->pixels,TM_ART,TM_ART);
 /* The current lyric is never truncated (LyricStack): the label of the fitted font takes the box, bottom-aligned on band B, growing up into
  * band M past two lines; the others are hidden and emptied. The next lyric's row is hidden whenever the lyric needs more than two lines. */
 {static const unsigned cur_label[TM_CUR_SLOTS]={TM_CURRENT,TM_CURRENT20,TM_CURRENT16};const unsigned on=tm_cur_slot(fit.font);TIORect r=tm_cur_rect_for(&fit);
  /* Visibility is only written when the fit changes (this runs every 33 ms); hidden labels get an empty text so they never point at a retired frame. */
  if(!c->shown_ok||c->shown_slot!=on||c->shown_next!=fit.next){
   for(unsigned i=0;i<TM_CUR_SLOTS;i++){void *l=c->labels[cur_label[i]];if(i!=on)c->api.text_static(NULL,l,"");c->api.visible(NULL,l,i==on);}
   if(!fit.next)c->api.text_static(NULL,c->labels[TM_NEXT],"");c->api.visible(NULL,c->labels[TM_NEXT],fit.next);
   c->shown_slot=(uint8_t)on;c->shown_next=fit.next;c->shown_ok=true;}
  c->api.place(NULL,c->labels[cur_label[on]],r.x,r.y,r.w,r.h);c->api.text_static(NULL,c->labels[cur_label[on]],f->current);}
 if(fit.next)c->api.text_static(NULL,c->labels[TM_NEXT],f->next);c->api.text_static(NULL,c->labels[TM_TRACK],f->track);
 if(c->api.color&&color!=c->track_color){c->api.color(NULL,c->labels[TM_TRACK],color);c->track_color=color;}
 c->front=1-c->front;c->last_frame=now;return true;
}
static bool enter(Control *c){if(!owns(c)||!paired()||c->closing)return false;
 if(c->root)return wake(c);TNNavSlot *n=navslot(c->app);if(!n||tap_service_visible(c->app)||tf_slot_visible(n->focus)||tn_slot_visible(n)||((M8NativeTail *)((uint8_t *)c->app+TIO_STOCK_MENU_BYTES))->page)return false;
 /* setState synchronously hides the previous launcher/menu view. At this
  * point we own no music widgets yet: that hide is not a user music exit.
  * Keep the just-accepted OPEN state through this one focus transition;
  * all later hide/destroy/button events still retire the session normally. */
 c->focus_transition=true;nav_set_state(manager(),1);c->focus_transition=false;
 if(!owns(c)||c->closing||!paired()||!c->api.idle(NULL))return false;c->root=c->api.root(NULL,ptr(c->app,4));if(!c->root)return false;
 c->api.place(NULL,c->root,0,0,540,180);c->canvas=c->api.canvas(NULL,c->root);if(!c->canvas)goto fail;
 {TIORect a=tm_art_rect();c->api.place(NULL,c->canvas,a.x,a.y,a.w,a.h);}
 {const unsigned fonts[TM_LABELS]={TM_CUR_FONT,TM_NEXT_FONT,TM_TRACK_FONT,TIO_FONT_BODY,TIO_FONT_MIN};
  const TIORect rects[TM_LABELS]={tm_cur_rect(0),tm_next_rect(),tm_track_rect(),tm_cur_rect(1),tm_cur_rect(2)};
  const uint32_t colors[TM_LABELS]={TIO_LENS_FULL,TIO_LENS_HIGH,TIO_LENS_MID,TIO_LENS_FULL,TIO_LENS_FULL};
  for(unsigned i=0;i<TM_LABELS;i++){c->labels[i]=c->api.label(NULL,c->root,fonts[i]);if(!c->labels[i])goto fail;
   c->api.place(NULL,c->labels[i],rects[i].x,rects[i].y,rects[i].w,rects[i].h);if(c->api.clip_text)c->api.clip_text(NULL,c->labels[i]);
   if(c->api.color)c->api.color(NULL,c->labels[i],colors[i]);}}
 c->shown_ok=false;c->track_color=TIO_LENS_MID;tio_hint_init(&c->hint);tio_hint_enter(&c->hint,stream_tick());
 if(!stream_add_event(c->root,deleted,0x24,c))goto fail;
 if(!render(c,stream_tick()))goto fail;c->api.visible(NULL,c->root,true);if(!wake(c))goto fail;return true;
 fail:c->api.destroy(NULL,c->root);c->root=NULL;release(c);return false;
}
static void tick(void *timer){Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;uint32_t now=stream_tick();
 if(c->root&&!c->closing&&(uint32_t)(now-c->last_check)>=1000){c->last_check=now;if(!owns(c)||!paired())close_view(c,false);}
 if(c->root&&!c->closing){if(c->music.awake&&((c->waiting&&(uint32_t)(now-c->music.wake_tick)>30000)||(!c->waiting&&tm_expired(&c->music,now)))){release(c);if(owns(c))(void)nav_force_off();c->music.awake=false;}
  if(c->music.awake&&(uint32_t)(now-c->last_frame)>=33)(void)render(c,now);
 }
 if(c->closing&&c->api.idle(NULL)){if(c->root)c->api.destroy(NULL,c->root);c->root=NULL;c->closing=false;}
 if(c->event&&c->music.event_ack==c->request_id)c->event=0;
 if(c->event&&c->event_tries<10&&(!c->last_event||(uint32_t)(now-c->last_event)>=1000)&&paired()){emit(c,c->event,TM_OK,c->music.sid,c->music.generation,c->music.sequence);c->last_event=now;c->event_tries++;}
 if(c->retired&&!c->root&&c->api.idle(NULL)){stream_timer_delete(timer);stream_free(c);}
}
static Control *control(TMMusicSlot *s){if(!s||!s->app)return NULL;if(s->control)return s->control;Control *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->api=tn_lvgl_widgets();c->app=s->app;c->slot=s;c->request_id=stream_tick();c->timer=stream_timer_create(tick,33,c);if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;}
TMMusicSlot *tm_slot_create(void *app){TMMusicSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tm_slot_hidden(TMMusicSlot *s){if(s&&s->control){Control *c=s->control;if(c->focus_transition&&!c->root&&!c->retired)return;close_view(c,false);}}
void tm_slot_destroy(TMMusicSlot *s){if(!s)return;Control *c=s->control;if(c){close_view(c,false);c->retired=true;c->slot=NULL;c->app=NULL;}stream_free(s);}
bool tm_slot_visible(TMMusicSlot *s){Control *c=s?s->control:NULL;return c&&c->root;}
/* Tile state: the last playing flag and title the phone sent, and how long ago it last spoke. Read only. */
void tm_slot_live(TMMusicSlot *s,uint32_t now,TSLive *out){Control *c=s?s->control:NULL;if(!c||!out)return;out->music_playing=c->music.playing;out->music_age_ms=(uint32_t)(now-c->music.last_contact);out->music_title=c->music.title;}
bool tm_slot_open(TMMusicSlot *s){Control *c=control(s);if(!c)return false;c->waiting=!c->music.active;if(!enter(c))return false;request(c,TM_RESUME);return true;}
void tm_slot_wheel(TMMusicSlot *s,int delta){Control *c=s?s->control:NULL;if(!c||!c->root||c->closing)return;tio_hint_input(&c->hint,stream_tick());int step=tm_input_wheel(&c->input,delta,stream_tick());if(step)request(c,step>0?TM_NEXT:TM_PREV);}
bool tm_handle_event(void *e){void *vm=stream_event_user(e);TMMusicSlot *s=slot_of(ptr(vm,0x10));Control *c=s?s->control:NULL;if(!c||!c->root||!owns(c)||native_event_code(e)!=0xe)return false;unsigned key=native_event_key(e);
 if(key==0x3b)close_view(c,true);else if(key==0x3a){tio_hint_input(&c->hint,stream_tick());if(tm_input_press(&c->input,stream_tick())){if(!c->music.awake){(void)wake(c);request(c,TM_RESUME);}else request(c,c->music.playing?TM_PAUSE:TM_PLAY);}}else return false;nav_stop_event(e);return true;}
TIOImageResult tm_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){static const char name[]="turbo-music.tmu";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;TMPacket p;if(f->complete!=1||f->received!=f->declared||!tm_decode(f->data,f->received,&p))return TIO_BAD_SIZE;if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TM_MESSAGE,.data=f->data,.bytes=f->received};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;}
bool tm_message_is_ours(const TIONativeMessage *m){return m&&m->id==TM_MESSAGE;}
void tm_message_dispatch(const TIONativeMessage *m){TMPacket q;if(!tm_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!tm_decode(m->data,m->bytes,&q))return;
 void *vm=manager(),*app=ptr(vm,0x10);if(!app&&home())app=nav_ensure_menu(vm);Control *c=control(slot_of(app));if(!c){emit(NULL,TM_ACK,TM_BUSY,q.sid,q.generation,q.sequence);return;}
 enum TMResult r=TM_OK;if(q.op==TM_OPEN&&(!home()||c->closing||tn_slot_visible(navslot(app))||((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->page))r=TM_BUSY;
 bool duplicate=q.sid==c->music.sid&&q.sequence==c->music.sequence&&q.crc==c->music.last_crc;
 if(r==TM_OK){r=tm_receive(&c->music,&q,stream_tick());if(r==TM_OK&&!duplicate){if(q.op==TM_OPEN){c->waiting=false;if(!enter(c)){close_view(c,false);r=TM_BUSY;}}else if(q.op==TM_CLOSE)close_view(c,false);}}
 emit(c,TM_ACK,r,q.sid,q.generation,q.sequence);
}
