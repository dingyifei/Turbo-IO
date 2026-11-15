#define _POSIX_C_SOURCE 200112L
/* The production page is compiled into this file, so the Sensors case can set the page's knob counters to their largest
 * values (a real press count of 4294967295 would take 4 billion presses) and then format the text with the real code. */
#include "native_display_page.c"
#include "native_display_page.h"
#include "native_display_file.h"
#include "display_carrier.h"
#include "display_client.h"
#include "../menu8-renderer.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#ifdef TIO_ANIMATION_EXPERIMENT
#include "../animation-runtime-v1/animation.h"
const uint8_t ta_asset[TA_BYTES*TA_FRAMES]={0};
void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *f,...){(void)a;(void)b;(void)c;(void)d;assert(f);}
static unsigned animation_draws;
#endif
typedef struct Obj {struct Obj *parent;void (*ondelete)(void *);void *user;bool hidden;int w,h;} Obj;
typedef struct Timer {void (*callback)(void *);void *user;} Timer;
static Obj *objects[16];static unsigned object_count,creates,fail_create;
static bool busy,fail_timer,fail_event,fail_config,fail_alloc;
static Timer *timer;static uint32_t now=1000;static unsigned allocs,frees,sends;
static const uint8_t *shown;static TDPReply latest;
static size_t allocation_size;
static void *new_object(void *parent){
 creates++;if(creates==fail_create)return NULL;
 Obj *o=calloc(1,sizeof *o);assert(o&&object_count<16);o->parent=parent;objects[object_count++]=o;return o;
}
static void delete_object(void *p){
 Obj *o=p;assert(o&&object_count);
 for(unsigned i=0;i<object_count;){if(objects[i]->parent==o)delete_object(objects[i]);else i++;}
 if(o->ondelete)o->ondelete(o);
 unsigned i=0;while(i<object_count&&objects[i]!=o)i++;assert(i<object_count);
 objects[i]=objects[--object_count];shown=NULL;free(o);
}
static void hidden(void *p,bool h){((Obj *)p)->hidden=h;}
static bool configure(void *p,void *parent){assert(p&&parent==(void *)1);return !fail_config;}
const M8RenderAPI m8_native_api={.create_root=new_object,.delete_root=delete_object,.hidden=hidden,.configure_root=configure};
void *stream_memalign(size_t align,size_t n){if(fail_alloc)return NULL;void *p=NULL;assert(!posix_memalign(&p,align,n));allocs++;allocation_size=n;return p;}
void stream_free(void *p){assert(!busy&&shown==NULL);frees++;free(p);}
uint32_t stream_tick(void){return now;}
void *stream_timer_create(void (*fn)(void *),uint32_t period,void *user){
#ifdef TIO_ANIMATION_EXPERIMENT
 assert(!timer&&period==100);
#else
 assert(!timer&&period==100);
#endif
 if(fail_timer)return NULL;timer=calloc(1,sizeof *timer);assert(timer);timer->callback=fn;timer->user=user;return timer;
}
void stream_timer_delete(void *t){assert(t==timer);free(timer);timer=NULL;}
void *stream_timer_next(void *previous){return previous?NULL:timer;}
#ifdef TIO_ANIMATION_EXPERIMENT
void stream_timer_period(void *t,uint32_t ms){assert(t==timer&&ms==100);}
#endif
void *tdp_test_timer_user(void *t){return ((Timer *)t)->user;}
bool tdp_test_timer_callback(void *t,void (*fn)(void *)){return ((Timer *)t)->callback==fn;}
void *stream_event_user(void *event){return ((Obj *)event)->user;}
void *stream_add_event(void *o,void (*fn)(void *),uint32_t event,void *user){
 assert(event==0x24);if(fail_event)return NULL;((Obj *)o)->ondelete=fn;((Obj *)o)->user=user;return o;
}
void *stream_canvas_create(void *p){return new_object(p);}
void *native_label_create(void *p){return new_object(p);}
void stream_canvas_set_buffer(void *p,void *b,int32_t w,int32_t h,uint8_t color){
 assert(p&&b&&color==6);assert(((uintptr_t)b&63)==0); /* TMG9: stock rounds the draw buffer up to 64 */
#ifdef TIO_ANIMATION_EXPERIMENT
 assert((w==512&&h==128)||(w==192&&h==176));
 if(w==192)animation_draws++;
#else
 assert(w==512&&h==128);
#endif
 shown=b;
}
uint32_t stream_stride(uint32_t w,uint8_t color){assert(color==6);return w;}
void *stream_display_next(void *p){return p?NULL:(void *)(uintptr_t)0x18002000;}
bool tdp_test_read_word(uint32_t a,uint32_t *v){
 if(a==0x1850ce1c+0x124){*v=0x18001000;return true;}
 if(a==0x18001000+12){*v=0x10462225;return true;}
 if(a==0x18001000+24){*v=busy?1:0;return true;}
 if(a==0x18001000||a==0x18002000+0x2a0){*v=0;return true;}
 assert(0);return false;
}
void stream_invalidate(void *p){assert(p);}
void native_report_activity(void){}
int32_t tio_lv_obj_get_width(void *p){assert(p==(void *)1);return 540;}
int32_t tio_lv_obj_get_height(void *p){assert(p==(void *)1);return 280;}
void tio_lv_obj_set_size(void *p,int32_t w,int32_t h){assert(p);((Obj *)p)->w=w;((Obj *)p)->h=h;}
static char label_text[200];static unsigned label_writes;
void native_label_text(void *p,const char *s){assert(p&&s&&strlen(s)<160);strcpy(label_text,s);label_writes++;}
/* Sensors screen providers (F5): stubs with values the cases set. */
#include "../diagnostics-v1/native_light.h"
volatile uint8_t tio_imu_family=2;
static int sensor_tid=41,light_bucket=-1;static bool heap_valid=true,folded;static uint32_t heap_used=8790000,heap_peak=8800000;static unsigned light_reads;
int td_gettid(void){return sensor_tid;}
static bool no_monitors;
void *nav_monitors(void){return no_monitors?NULL:(void *)16;}
void *nav_input(void *m){assert(m==(void *)16);return (void *)32;}
bool nav_folded(void *i){assert(i==(void *)32);return folded;}
void td_stock_light(void *c,TDDiagnostics *d){TDLightOwner *o=c;assert(o&&o->owner_tid==sensor_tid);
 td_metric(d,TD_LV_USED,heap_used,heap_valid);td_metric(d,TD_LV_PEAK,heap_peak,heap_valid);}
#if TIO_SENSORS_LIGHT
int td_light_bucket(void){light_reads++;return light_bucket;}
#endif
void native_text_color(void *p,uint32_t c,uint32_t style){assert(p&&c==0xffffff&&!style);}
void native_align(void *p,int align,int x,int y){assert(p);(void)align;(void)x;(void)y;}
int tdp_rnlink_send(unsigned bus,const uint8_t *p,unsigned n,void *cb){assert(!cb);assert(tdp_carrier_decode(bus,p,n,&latest));sends++;return 0;}
static uint8_t queue_data[TDP_NATIVE_PACKET_MAX];static TIONativeMessage queued;static unsigned queue_calls;
static int enqueue(unsigned module,const TIONativeMessage *m){assert(module==1&&m->release==NULL&&m->bytes<=512);memcpy(queue_data,m->data,m->bytes);queued=*m;queued.data=queue_data;queue_calls++;return 0;}
static TDPResult deliver(TDPNativePage *page,uint8_t *data,size_t len){
 TIONativeFile file={.data=data,.declared=(uint32_t)len,.complete=1,.received=(uint32_t)len};
 strcpy(file.filename,"turbo-display.tdp");assert(tdp_native_file_receive(&file,enqueue)==TIO_OK);
 memset(data,0,len); /* caller data expires after callback */
 now+=120;return tdp_native_dispatch(page,&queued);
}
static void pulse(void){assert(timer);timer->callback(timer);}
static void failure(unsigned which){
 assert(!timer&&!object_count);TDPNativePage *owner=NULL;creates=0;fail_create=which<=3?which:0;
 fail_timer=which==4;fail_event=which==5;fail_config=which==6;fail_alloc=which==7;
 assert(!tdp_native_open((void *)1,7392,&owner));assert(!owner&&!timer&&!object_count&&allocs==frees);
 fail_create=0;fail_timer=fail_event=fail_config=fail_alloc=false;
}
int main(void){
 for(unsigned i=1;i<=7;i++)failure(i);
 TDPNativePage *owner=NULL;creates=0;
 TDPNativePage *page=tdp_native_open((void *)1,7392,&owner);assert(page&&page==owner&&shown);
 assert(latest.sid==7392&&latest.request==0&&latest.result==TDP_CAPS&&latest.max_rect_bytes==472);
#ifdef TIO_ANIMATION_EXPERIMENT
 assert(animation_draws>0&&allocation_size<132000); /* reused TDP buffers */
 unsigned before_draws;
#endif
 uint8_t wire[TDP_MAX_PACKET],frame[TDP_PIXELS];memset(frame,192,sizeof frame);
 // QUERY immediately after HELLO used to lose its reply to rate limiting.
 size_t early=tdp_client_query(wire,sizeof wire,777);unsigned sent=sends;
 assert(tdp_native_receive(page,wire,early)==TDP_CAPS&&sends==sent);
 now+=100;pulse();assert(sends==sent+1&&latest.request==777);
#ifdef TIO_ANIMATION_EXPERIMENT
 /* Settle the intentionally coarse 100ms pulse, then measure a full second. */
 before_draws=animation_draws;
 for(unsigned i=0;i<200;i++){now+=5;pulse();}
 assert(animation_draws-before_draws==0); /* still image is not continuously repainted */
#endif
 size_t n=tdp_client_query(wire,sizeof wire,1);assert(deliver(page,wire,n)==TDP_CAPS&&latest.request==1);
 n=tdp_client_begin(wire,sizeof wire,7392,2,0,1,tdp_crc(frame,sizeof frame));assert(deliver(page,wire,n)==TDP_STAGED);
#ifdef TIO_ANIMATION_EXPERIMENT
 before_draws=animation_draws;now+=25;pulse();assert(animation_draws==before_draws);
#endif
 unsigned request=3;
 for(unsigned at=0;at<sizeof frame;){unsigned len=sizeof frame-at;if(len>472)len=472;
  n=tdp_client_chunk(wire,sizeof wire,7392,request++,0,1,at,frame+at,len);
  assert(deliver(page,wire,n)==TDP_STAGED&&shown[0]==0);at+=len;
 }
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_COMMIT,7392,request++,0,1);
 assert(deliver(page,wire,n)==TDP_UI_SUBMITTED&&latest.revision==1&&!memcmp(shown,frame,sizeof frame));
 unsigned before=queue_calls;
 TIONativeFile bad={.data=frame,.declared=513,.received=513,.complete=1};strcpy(bad.filename,"turbo-display.tdp");
 assert(tdp_native_file_receive(&bad,enqueue)==TIO_BAD_SIZE&&queue_calls==before);
 strcpy(bad.filename,"turbo-photo.timg");assert(tdp_native_file_receive(&bad,enqueue)==TIO_FOREIGN);
 busy=true;tdp_native_retire(page);assert(!owner);unsigned old_frees=frees;pulse();assert(frees==old_frees);
 assert(!tdp_native_open((void *)1,8642,&owner)); /* old timer pins buffers */
 busy=false;now+=200;pulse();assert(!timer&&!object_count&&allocs==frees);
 creates=0;page=tdp_native_open((void *)1,8642,&owner);assert(page);
 busy=true;delete_object(objects[0]);assert(!owner);pulse();assert(timer);
 busy=false;now+=200;pulse();assert(!timer&&allocs==frees); /* parent deletion while DMA busy */
 creates=0;page=tdp_native_open((void *)1,9264,&owner);assert(page);
 now+=120001;pulse();assert(!owner&&!timer&&!object_count&&allocs==frees);
 creates=0;page=tdp_native_open((void *)1,28285,&owner);assert(page);
 n=tdp_client_control(wire,sizeof wire,TDP_CLOSE,28285,999,0);assert(deliver(page,wire,n)==TDP_CLOSED);
 pulse();assert(!timer&&!owner&&allocs==frees);
 // No open page: return a correlated negative reply, never silently time out.
 n=tdp_client_query(wire,sizeof wire,1000);sent=sends;
 assert(tdp_native_receive(NULL,wire,n)==TDP_NO_SESSION&&sends==sent+1&&latest.request==1000&&latest.sid==0);
 wire[28]^=1;assert(tdp_native_receive(NULL,wire,n)==TDP_BAD_PACKET&&sends==sent+1);
 // Closing within rate window preserves the negative event until the timer,
 // with bounded memory, rather than freeing before it can be offered.
 creates=0;page=tdp_native_open((void *)1,34567,&owner);assert(page);sent=sends;
 tdp_native_retire(page);pulse();assert(timer&&sends==sent);
 now+=100;pulse();assert(!timer&&sends==sent+1&&latest.result==TDP_CLOSED&&latest.sid==34567&&allocs==frees);
 // Sensors screen (F5): the first press opens it; UI heap and Light lines; the longest text fits.
 creates=0;page=tdp_native_open((void *)1,40001,&owner);assert(page);
 tdp_native_knob(page,0,true);
#if TIO_SENSORS_LIGHT
 assert(!strcmp(label_text,"Sensors (read only)\nIMU ST (2)\nUI heap 8790000 max 8800000\nLight n/a\nFold open\nKnob +0 press 0"));
 static const char *const want[9]={"0-1 lx","1-3 lx","3-10 lx","10-300 lx","300-600 lx","600-1000 lx","1000-4000 lx","4000-5000 lx","5000+ lx"};
 /* each bucket compares the whole page text, so a label that only contains the expected one fails */
 char expect[200];
 for(int b=0;b<9;b++){light_bucket=b;now+=100;pulse();
  snprintf(expect,sizeof expect,"Sensors (read only)\nIMU ST (2)\nUI heap 8790000 max 8800000\nLight %s\nFold open\nKnob +0 press 0",want[b]);
  assert(!strcmp(label_text,expect));}
 light_bucket=9;now+=100;pulse();assert(!strcmp(label_text,"Sensors (read only)\nIMU ST (2)\nUI heap 8790000 max 8800000\nLight n/a\nFold open\nKnob +0 press 0"));
 light_bucket=-1;now+=100;pulse();assert(!strcmp(label_text,"Sensors (read only)\nIMU ST (2)\nUI heap 8790000 max 8800000\nLight n/a\nFold open\nKnob +0 press 0"));
 assert(light_reads>=12);
#else
 assert(!strcmp(label_text,"Sensors (read only)\nIMU ST (2)\nUI heap 8790000 max 8800000\nFold open\nKnob +0 press 0"));
 assert(!strstr(label_text,"Light")&&!light_reads);
#endif
 heap_valid=false;now+=1000;pulse();assert(strstr(label_text,"\nUI heap n/a\n"));   /* the next once-a-second sample */
 /* The heap figures are sampled once a second, not on every 100 ms tick. Right after a sample, nine ticks with a new heap
  * figure each redraw nothing; the tick one second after the sample shows the latest figure, in one redraw. */
 heap_valid=true;heap_used=1000;now+=1000;pulse();assert(strstr(label_text,"\nUI heap 1000 max 8800000\n"));
 {unsigned writes=label_writes;
  for(unsigned i=1;i<=9;i++){heap_used=1000+i;now+=100;pulse();}
  assert(label_writes==writes&&strstr(label_text,"\nUI heap 1000 max 8800000\n"));
  heap_used=2000;now+=100;pulse();assert(label_writes==writes+1&&strstr(label_text,"\nUI heap 2000 max 8800000\n"));
  /* A fold or knob change between samples still shows at once (fold: the next tick; knob: the knob call itself), with
   * the last sampled heap figure. */
  writes=label_writes;heap_used=3000;folded=true;now+=100;pulse();
  assert(label_writes==writes+1&&strstr(label_text,"\nUI heap 2000 max 8800000\n")&&strstr(label_text,"\nFold closed\n"));
  heap_used=4000;tdp_native_knob(page,5,false);
  assert(label_writes==writes+2&&strstr(label_text,"\nUI heap 2000 max 8800000\n")&&strstr(label_text,"\nKnob +5 press 0"));
  folded=false;page->knob_delta=0;heap_used=8790000;}
 /* The worst case: every piece at its largest value, formatted by the real sensors_text. The IMU byte is a uint8_t, so
  * its number has at most 3 digits; the heap values and the press count are uint32_t (10 digits); the knob delta is an
  * int32_t (11 characters with the sign); "unknown", "closed" and the 12-character light buckets are the longest words. */
 heap_valid=true;heap_used=heap_peak=4294967295u;tio_imu_family=255;folded=true;light_bucket=6;
 page->knob_delta=-2147483647-1;page->knob_press=4294967295u;sensors_text(page,true);   /* the real code, with a heap sample */
#if TIO_SENSORS_LIGHT
 assert(!strcmp(label_text,"Sensors (read only)\nIMU unknown (255)\nUI heap 4294967295 max 4294967295\nLight 1000-4000 lx\nFold closed\nKnob -2147483648 press 4294967295"));
#else
 assert(!strcmp(label_text,"Sensors (read only)\nIMU unknown (255)\nUI heap 4294967295 max 4294967295\nFold closed\nKnob -2147483648 press 4294967295"));
#endif
 size_t longest=strlen(label_text)+1;assert(longest<TDP_SENSORS_TEXT);
 /* No other combination is longer: every IMU byte, light bucket (and out-of-range ones), fold state, heap state and
  * extreme knob value, each through the real code. */
 {static const int32_t deltas[]={-2147483647-1,2147483647,0};static const uint32_t presses[]={0,4294967295u};size_t most=0;
  for(unsigned imu=0;imu<256;imu++)for(int b=-1;b<=9;b++)for(int f=0;f<3;f++)for(unsigned v=0;v<2;v++)for(unsigned k=0;k<6;k++){
   tio_imu_family=(uint8_t)imu;light_bucket=b;no_monitors=f==2;folded=f==1;heap_valid=v;
   page->knob_delta=deltas[k%3];page->knob_press=presses[k/3];sensors_text(page,true);
   size_t len=strlen(label_text)+1;if(len>most)most=len;}
  assert(most==longest);no_monitors=false;heap_valid=true;}
 tdp_native_retire(page);for(int i=0;i<3&&timer;i++){now+=100;pulse();}assert(!timer&&!owner&&allocs==frees);
 printf("PASS native adapter mocks: 7 allocation/setup failures, SID/PB reply, 139-chunk atomic frame, 512-byte gate, physical/parent/timeout/protocol close; page=%zu bytes; allocations=%u frees=%u; NO real LVGL/radio; Sensors text worst case %zu of %d bytes with the NUL, Light line %s\n",allocation_size,allocs,frees,longest,TDP_SENSORS_TEXT,TIO_SENSORS_LIGHT?"on":"off");
}
