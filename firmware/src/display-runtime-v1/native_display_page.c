/* 1.0.4.12-only adapter under OFFLINE TEST. Not linked into N8W or any OTA.
 * Owns one LVGL subtree, two pixel buffers, and one retirement timer.
 * Native symbols must be bound by a SHA-pinned linker, not guessed addresses. */
#include "native_display_page.h"
#include "display_carrier.h"
#include "display_memory.h"
#include "../menu8-renderer.h"
#include "../image-upload-test/render_idle.h"
#include "../diagnostics-v1/native_light.h"
#ifdef TIO_ANIMATION_EXPERIMENT
#include "../animation-runtime-v1/animation.h"
extern const uint8_t ta_asset[TA_BYTES*TA_FRAMES];
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
extern void stream_timer_period(void *,uint32_t);
#endif
/* Read-only Sensors screen: 1.0.5.12 AP byte tio_imu_family (link.ld; 0 unknown, 1 none, 2 ST, 3 TDK), the stock light
 * current/peak (td_stock_light), the hinge Hall state and the knob counters forwarded by menu10. It never writes the
 * PMU, a sensor, a setting or flash, and starts no sensor report or handler. */
extern volatile uint8_t tio_imu_family;
extern int td_gettid(void);
extern void *nav_monitors(void),*nav_input(void *);
extern bool nav_folded(void *);
struct TDPNativePage {
 TDPRuntime runtime;
 void *parent,*root,*canvas,*label,*timer;
 TDPNativePage **owner;
 uint32_t last_activity,last_reply;
 bool retired,sent_reply,closing_notified,reply_pending;
 TDPReply pending_reply;
#ifdef TIO_ANIMATION_EXPERIMENT
 TAPlayer animation;
 bool animation_mode;
#endif
 bool sensor_mode;
 int32_t knob_delta;uint32_t knob_press;
 TDDiagnostics light;
 char shown[120];
};
extern const M8RenderAPI m8_native_api;
extern void *stream_memalign(size_t,size_t);
extern void stream_free(void *);
extern uint32_t stream_tick(void);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*stream_timer_next(void *),*stream_event_user(void *);
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern void *stream_canvas_create(void *);
extern void stream_canvas_set_buffer(void *,void *,int32_t,int32_t,uint8_t);
extern uint32_t stream_stride(uint32_t,uint8_t);
extern void *stream_display_next(void *);
extern void stream_invalidate(void *),native_report_activity(void);
extern int32_t tio_lv_obj_get_width(void *),tio_lv_obj_get_height(void *);
extern void tio_lv_obj_set_size(void *,int32_t,int32_t);
extern void *native_label_create(void *);
extern void native_label_text(void *,const char *),native_text_color(void *,uint32_t,uint32_t);
extern void native_align(void *,int,int,int);
/* C ABI inferred and ARM-tested: business, payload, uint16 length, callback.
 * It synchronously copies before enqueue; nonzero can still mean queued. */
extern int tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
static bool read_word(uint32_t address,uint32_t *out){
#ifdef TDP_NATIVE_HOST_TEST
 extern bool tdp_test_read_word(uint32_t,uint32_t *);
 return tdp_test_read_word(address,out);
#else
 if((address&3)||address<0x18000000||address>0x1b600000-4)return false;
 *out=*(volatile uint32_t *)(uintptr_t)address;return true;
#endif
}
static uint32_t next_display(uint32_t p){return (uint32_t)(uintptr_t)stream_display_next((void *)(uintptr_t)p);}
static bool idle(void *ctx){(void)ctx;return tio_render_graph_idle(read_word,next_display);}
static void unlink_owner(TDPNativePage *p){if(p->owner){if(*p->owner==p)*p->owner=NULL;p->owner=NULL;}}
static void deleted(void *event){
 TDPNativePage *p=stream_event_user(event);if(!p)return;
 p->root=p->canvas=p->label=NULL;p->retired=true;unlink_owner(p);
}
static bool submit(void *ctx,const uint8_t *pixels,unsigned w,unsigned h){
 TDPNativePage *p=ctx;
 if(!pixels){
  if(p->root)m8_native_api.delete_root(p->root);
  p->root=p->canvas=p->label=NULL;return true;
 }
 if(p->retired||!p->root||!p->canvas||w!=512||h!=128)return false;
#ifdef TIO_ANIMATION_EXPERIMENT
 ta_stop(&p->animation);p->animation_mode=false;
 if(p->timer)stream_timer_period(p->timer,100);
 p->sensor_mode=false;m8_native_api.hidden(p->canvas,false);
 tio_lv_obj_set_size(p->canvas,512,128);native_align(p->canvas,5,0,0);
 tio_lv_obj_set_size(p->label,512,44);native_align(p->label,2,0,0);
#endif
 stream_canvas_set_buffer(p->canvas,(void *)pixels,w,h,6);stream_invalidate(p->canvas);return true;
}
static TDPUI ui(TDPNativePage *p){return (TDPUI){p,idle,submit};}
static char *number(char *s,uint32_t n){char b[10];unsigned k=0;do{b[k++]=(char)('0'+n%10);n/=10;}while(n);while(k)*s++=b[--k];return s;}
static void status(TDPNativePage *p){
 if(!p->label)return;char text[64]="Turbo Display SID ";char *s=text+sizeof("Turbo Display SID ")-1;
 s=number(s,p->runtime.sid);*s++=' ';*s++='#';s=number(s,p->runtime.revision);*s=0;native_label_text(p->label,text);
}
#ifdef TIO_ANIMATION_EXPERIMENT
static bool animation_submit(void *ctx,const uint8_t *pixels,unsigned w,unsigned h){
 TDPNativePage *p=ctx;
 if(p->retired||!p->root||!p->canvas||w!=TA_WIDTH||h!=TA_HEIGHT)return false;
 stream_canvas_set_buffer(p->canvas,(void *)pixels,w,h,6);stream_invalidate(p->canvas);return true;
}
static void animation_status(TDPNativePage *p){
 if(!p->label)return;
 char text[120];
 memcpy(text,"Turbo Display 192x176\n1 still image\nsent ",sizeof("Turbo Display 192x176\n1 still image\nsent ")-1);
 char *s=text+sizeof("Turbo Display 192x176\n1 still image\nsent ")-1;
 s=number(s,p->animation.submitted);*s++=' ';*s++='/';*s++=' ';
 s=number(s,p->animation.skipped);*s++='\n';*s++='g';*s++='a';*s++='p';*s++=' ';
 s=number(s,p->animation.max_gap);*s++='m';*s++='s';*s++='\n';
 const char *state=p->animation.stalled?"STALL STOP":p->animation.failed?"ERROR STOP":p->animation.running?"WAIT":"STILL";
 while(*state)*s++=*state++;*s=0;native_label_text(p->label,text);
}
static void animation_step(TDPNativePage *p,uint32_t now){
 TAUI a={p,idle,animation_submit};
 bool was_running=p->animation.running;
 (void)ta_step(&p->animation,&a,now);p->runtime.active=(uint8_t)p->animation.active;
 if(was_running&&!p->animation.running)stream_timer_period(p->timer,100);
}
#endif
static char *text_add(char *s,const char *t){while(*t)*s++=*t++;return s;}
static char *signed_number(char *s,int32_t n){if(n<0){*s++='-';return number(s,0u-(uint32_t)n);}*s++='+';return number(s,(uint32_t)n);}
static void sensors_text(TDPNativePage *p){
 if(!p->label)return;
 char text[120];char *s=text_add(text,"Sensors (read only)\nIMU ");
 uint32_t imu=tio_imu_family;
 s=text_add(s,imu==2?"ST":imu==3?"TDK":imu==1?"none":"unknown");*s++=' ';*s++='(';s=number(s,imu);*s++=')';
 s=text_add(s,"\nLight ");
 TDDiagnostics *d=&p->light;TDLightOwner owner={td_gettid()};td_init(d,0);td_stock_light(&owner,d);
 if(d->valid&(1u<<TD_LV_USED)){s=number(s,d->values[TD_LV_USED]);s=text_add(s," pk ");s=number(s,d->values[TD_LV_PEAK]);}
 else s=text_add(s,"n/a");
 s=text_add(s,"\nFold ");
 void *m=nav_monitors(),*i=m?nav_input(m):NULL;
 s=text_add(s,i?(nav_folded(i)?"closed":"open"):"n/a");
 s=text_add(s,"\nKnob ");s=signed_number(s,p->knob_delta);s=text_add(s," press ");s=number(s,p->knob_press);*s=0;
 if(!memcmp(text,p->shown,(size_t)(s-text)+1))return;
 memcpy(p->shown,text,(size_t)(s-text)+1);native_label_text(p->label,text);
}
void tdp_native_knob(TDPNativePage *p,int32_t delta,bool press){
 if(!p||p->retired||!p->root||!p->label||!p->canvas)return;
 if(!p->sensor_mode){
  if(!press)return;
  /* First press leaves the display screen for the Sensors screen. */
#ifdef TIO_ANIMATION_EXPERIMENT
  ta_stop(&p->animation);p->animation_mode=false;
#endif
  p->sensor_mode=true;m8_native_api.hidden(p->canvas,true);
  tio_lv_obj_set_size(p->label,512,164);native_align(p->label,2,0,0);
  p->runtime.deadline=stream_tick()+300000u;p->shown[0]=0;sensors_text(p);return;
 }
 p->knob_delta+=delta;if(press)p->knob_press++;
 sensors_text(p);
}
static void emit(TDPReply result){
 result.max_rect_bytes=TDP_NATIVE_PIXELS_MAX;
 uint8_t bytes[TDP_UPLINK_MAX];size_t n=tdp_carrier_reply(&result,bytes,sizeof bytes);
 if(!n)return;
 /* A nonzero return may still mean queued. Offer exactly once, no blind retry. */
 (void)tdp_rnlink_send(TDP_UPLINK_BUSINESS,bytes,(unsigned)n,NULL);
}
static void flush_reply(TDPNativePage *p){
 uint32_t now=stream_tick();
 if(!p->reply_pending||(p->sent_reply&&(uint32_t)(now-p->last_reply)<100u))return;
 TDPReply value=p->pending_reply;p->reply_pending=false;p->sent_reply=true;p->last_reply=now;emit(value);
}
static void reply(TDPNativePage *p,TDPReply result){
 /* One fixed pending slot; preserve a normal ACK. Physical CLOSED has priority.
  * The timer delays a too-early reply instead of silently dropping it. */
 if(p->reply_pending&&result.result!=TDP_CLOSED)return;
 p->pending_reply=result;p->reply_pending=true;flush_reply(p);
}
static void notify_closed(TDPNativePage *p){
 if(p->closing_notified)return;p->closing_notified=true;
 /* request=0 denotes an unsolicited event; retain SID until this offer. */
 reply(p,(TDPReply){TDP_CLOSED,p->runtime.sid,0,p->runtime.revision,512,128,472,120000});
}
static void tick(void *timer){
#ifdef TDP_NATIVE_HOST_TEST
 extern void *tdp_test_timer_user(void *);
 TDPNativePage *p=tdp_test_timer_user(timer);
#else
 TDPNativePage *p=*(TDPNativePage **)((uint8_t *)timer+12);
#endif
 if(!p)return;TDPUI callbacks=ui(p);uint32_t now=stream_tick();
 if(p->retired||!p->runtime.open||(int32_t)(now-p->runtime.deadline)>=0){
  notify_closed(p);p->retired=true;unlink_owner(p);
  if(p->root)m8_native_api.hidden(p->root,true);
  if(tdp_close(&p->runtime,&callbacks)!=TDP_CLOSED)return;
  flush_reply(p);if(p->reply_pending)return; /* keep one small ACK until due */
  stream_timer_delete(timer);stream_free(p);return;
 }
 flush_reply(p);
 if(p->sensor_mode)sensors_text(p);
 (void)tdp_tick(&p->runtime,&callbacks,now);
#ifdef TIO_ANIMATION_EXPERIMENT
 if(p->animation_mode)animation_step(p,now);
#endif
 if((uint32_t)(now-p->last_activity)>=1000u){p->last_activity=now;native_report_activity();
#ifdef TIO_ANIMATION_EXPERIMENT
  if(p->animation_mode){
   animation_status(p);
   native_log(1,0,0,0,"[TurboAnim60] elapsed=%u sent=%u skip=%u busy=%u gap=%u fail=%u running=%u",
    now-p->animation.start,p->animation.submitted,p->animation.skipped,p->animation.busy_polls,
    p->animation.max_gap,p->animation.failed,p->animation.running);
  }
#endif
 }
}
TDPNativePage *tdp_native_open(void *parent,uint32_t sid,TDPNativePage **owner){
 if(!parent||!sid||!owner||*owner)return NULL;
 unsigned visited=0;for(void *t=stream_timer_next(NULL);t;t=stream_timer_next(t)){
  if(++visited>512)return NULL;
#ifdef TDP_NATIVE_HOST_TEST
  extern bool tdp_test_timer_callback(void *,void (*)(void *));
  if(tdp_test_timer_callback(t,tick))return NULL;
#else
  if(*(void (**)(void *))((uint8_t *)t+8)==tick)return NULL;
#endif
 }
 if(!idle(NULL)||stream_stride(512,6)!=512||tio_lv_obj_get_width(parent)<540||tio_lv_obj_get_height(parent)<180)return NULL;
 TDPNativePage *p=stream_memalign(64,sizeof *p);if(!p)return NULL;memset(p,0,sizeof *p);p->parent=parent;p->owner=owner;
 if(!tdp_open(&p->runtime,sid,stream_tick())){stream_free(p);return NULL;}
#ifdef TIO_ANIMATION_EXPERIMENT
 if(stream_stride(TA_WIDTH,6)!=TA_WIDTH){stream_free(p);return NULL;}
 p->timer=stream_timer_create(tick,100,p);
#else
 p->timer=stream_timer_create(tick,100,p);
#endif
 if(!p->timer){stream_free(p);return NULL;}
 p->root=m8_native_api.create_root(parent);
 if(p->root){
  m8_native_api.hidden(p->root,true);
  if(!m8_native_api.configure_root(p->root,parent))goto fail;
  tio_lv_obj_set_size(p->root,540,180);native_align(p->root,9,0,0);
  if(!stream_add_event(p->root,deleted,0x24,p))goto fail;
  p->canvas=stream_canvas_create(p->root);p->label=native_label_create(p->root);
  if(!p->canvas||!p->label)goto fail;
  tio_lv_obj_set_size(p->canvas,512,128);native_align(p->canvas,5,0,0);
  tio_lv_obj_set_size(p->label,512,44);native_align(p->label,2,0,0);native_text_color(p->label,0x00ffffff,0);
  stream_canvas_set_buffer(p->canvas,p->runtime.pixels[0],512,128,6);
  status(p);
#ifdef TIO_ANIMATION_EXPERIMENT
  if(!ta_start(&p->animation,ta_asset,sizeof ta_asset,p->runtime.pixels[0],p->runtime.pixels[1],
    TDP_PIXELS,stream_tick(),p->runtime.active))goto fail;
  p->animation_mode=true;p->runtime.deadline=stream_tick()+60000u;
  tio_lv_obj_set_size(p->canvas,TA_WIDTH,TA_HEIGHT);native_align(p->canvas,7,8,0);
  tio_lv_obj_set_size(p->label,300,164);native_align(p->label,8,-8,0);
  animation_step(p,stream_tick());animation_status(p);
#endif
  *owner=p;m8_native_api.hidden(p->root,false);native_report_activity();
  reply(p,(TDPReply){TDP_CAPS,sid,0,0,512,128,472,120000});return p;
 }
fail:
 if(p->root)m8_native_api.delete_root(p->root);
 stream_timer_delete(p->timer);stream_free(p);return NULL;
}
void tdp_native_retire(TDPNativePage *p){
 if(!p)return;notify_closed(p);p->retired=true;unlink_owner(p);
 if(p->root)m8_native_api.hidden(p->root,true);
}
TDPResult tdp_native_receive(TDPNativePage *p,const uint8_t *bytes,size_t n){
 if(!p||p->retired||!p->root){
  /* Called only after native_display_file validated the owned outer envelope.
   * Still revalidate it here; no SID guessing and no page allocation. */
  if(!bytes||n<32||n>512||memcmp(bytes,"TDP1",4)||bytes[4]!=1||bytes[6]||bytes[7]||bytes[5]<TDP_QUERY||bytes[5]>TDP_FRAME_ABORT)return TDP_BAD_PACKET;
  uint32_t request=0,len=0,crc=0;for(unsigned i=0;i<4;i++){request|=(uint32_t)bytes[12+i]<<(8*i);len|=(uint32_t)bytes[24+i]<<(8*i);crc|=(uint32_t)bytes[28+i]<<(8*i);}
  if(!request||len!=n-32||crc!=tdp_crc(bytes+32,len))return TDP_BAD_PACKET;
  emit((TDPReply){TDP_NO_SESSION,0,request,0,512,128,472,120000});return TDP_NO_SESSION;
 }
 if(n>TDP_NATIVE_PACKET_MAX)return TDP_BAD_PACKET;
 flush_reply(p);
 if(p->reply_pending)return TDP_BUSY; /* unsupported pipelining cannot overwrite ACK */
 TDPUI callbacks=ui(p);TDPReply r=tdp_handle(&p->runtime,&callbacks,bytes,n,stream_tick());
#ifdef TIO_ANIMATION_EXPERIMENT
 /* Valid uploads take ownership of the SAME staging buffers. QUERY/invalid
  * packets do not interrupt playback. Never animate during a transaction. */
 if(r.result==TDP_STAGED||r.result==TDP_UI_SUBMITTED||r.result==TDP_CLOSED){
  ta_stop(&p->animation);p->animation_mode=false;
  stream_timer_period(p->timer,100);
 }
#endif
 if(r.result==TDP_UI_SUBMITTED)status(p);
 if(r.result==TDP_CLOSED)p->closing_notified=true;
 reply(p,r);return r.result;
}
