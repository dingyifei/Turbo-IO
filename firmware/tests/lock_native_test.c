/* Host test for the PIN lock's stock bindings (src/lock-v1/lock_native.c) against a scripted model of the stock calls:
 * boot (no file / enabled / damaged), the keypad and wheel read hooks (consume-and-drop, pass-through, the keys that always
 * reach stock), the cross-thread gates (screen, assistant, microphone, recorder), the idle and fold locks through the
 * screen gate and the tick, the TLK: phone path, the factory-reset clear, the anchor's self-repair and the head-motion
 * messages to and from the Bluetooth core.
 * The model is what the static RE says the stock calls do (build/re/ notes); it is not hardware evidence. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* ------------------------------------------------------------------ stock model */
static uint32_t ms;static int64_t pmu;static bool folded,screen,ota,connected=true,bonded=true;
static int screen_on_calls,force_off_calls,kws_on,kws_off,flushes,stock_key_calls,stock_wheel_calls,replies;
static uint8_t last_reply[74];static uint32_t rnd=0x1234;
static uint32_t next_key;static int16_t next_diff;
static int32_t topic[32];static unsigned topic_n;
static uint8_t wheel_ctx[16];
static uint8_t display[0x300];static char cover_obj[4],screen_obj[4],foreign_obj[4];static int covers,cover_deletes;
/* The sys layer with LVGL's children list (stock_layout.h): creation appends, deletion removes, the last is on top. */
static uint8_t sys_obj[16],sys_spec[0x30];static void *sys_kids[8];
static uint16_t kids_n(void){uint16_t n;memcpy(&n,sys_spec+TIO_STOCK_SPEC_CHILD_CNT,2);return n;}
static void kids_set(uint16_t n){memcpy(sys_spec+TIO_STOCK_SPEC_CHILD_CNT,&n,2);}
static void kid_add(void *o){uint16_t n=kids_n();assert(n<8);sys_kids[n]=o;kids_set((uint16_t)(n+1));}
static void kid_remove(void *o){uint16_t n=kids_n(),j=0;for(uint16_t i=0;i<n;i++)if(sys_kids[i]!=o)sys_kids[j++]=sys_kids[i];kids_set(j);}
static void sys_reset(void){memset(sys_obj,0,sizeof sys_obj);memset(sys_spec,0,sizeof sys_spec);void *p=sys_spec;memcpy(sys_obj+TIO_STOCK_OBJ_SPEC_ATTR,&p,sizeof p);p=sys_kids;memcpy(sys_spec+TIO_STOCK_SPEC_CHILDREN,&p,sizeof p);}
uint32_t stream_tick(void){return ms;}
uint32_t tap_random(void){return rnd+=0x9e3779b9u;}
void *stream_memalign(size_t a,size_t n){void *p=NULL;if(posix_memalign(&p,a<sizeof(void*)?sizeof(void*):a,n))return NULL;return p;}
void stream_free(void *p){free(p);}
static uint8_t timer_obj[64];
void *stream_timer_create(void (*cb)(void *),uint32_t period,void *user){(void)cb;(void)period;memcpy(timer_obj+TIO_STOCK_TIMER_USER,&user,sizeof user);return timer_obj;}
void *stream_timer_next(void *t){(void)t;return NULL;}
static char monitors,input,link_;void *nav_monitors(void){return &monitors;}void *nav_input(void *m){(void)m;return &input;}void *nav_link(void *m){(void)m;return &link_;}
void *fm_system(void *m){(void)m;return &monitors;}
static int invalidates,time_reads;static char battery_mon;static int64_t local_time;static int battery_level=-1;static int aligned_right;static void *centred[16];static int n_centred;
void *fm_battery_monitor(void *m){(void)m;return &battery_mon;}
int64_t fm_local_time(void *s){assert(s==&monitors);time_reads++;return local_time;}
int fm_battery_level(void *b){assert(b==&battery_mon);return battery_level;}
void menu_text_align(void *o,int a,uint32_t f){(void)o;(void)f;if(a==3)aligned_right++;if(a==2)centred[n_centred++%16]=o;}
void stream_invalidate(void *o){assert(o==cover_obj);invalidates++;}
unsigned tgr_ota_status(void *s){(void)s;return ota?1:0;}
bool nav_bonded(void *l){(void)l;return bonded;}bool nav_folded(void *i){(void)i;return folded;}bool focus_screen_on(void){return screen;}
int nav_connection(unsigned f){(void)f;return connected;}
int tdp_rnlink_send(unsigned b,const uint8_t *p,unsigned n,void *cb){(void)cb;assert(b==TIO_STOCK_RNLINK_BUSINESS&&n==74);memcpy(last_reply,p,74);replies++;return 0;}
int nav_force_off(void){force_off_calls++;screen=false;return 0;}
void nav_screen_on(bool on){screen_on_calls++;screen=on;}
void *tgr_indev_driver(void *indev){(void)indev;return wheel_ctx;}
void *stream_display_next(void *d){return d?NULL:display;}
void *tio_lv_obj_create_ex(void *parent,uint32_t f){(void)f;assert(parent==sys_obj);covers++;kid_add(cover_obj);return cover_obj;}
void tio_lv_obj_delete(void *o){assert(o==cover_obj);cover_deletes++;kid_remove(o);}
static int cover_w,cover_h,layout_lag;   /* LVGL applies a size at its next layout pass: layout_lag reads of 0 first */
void tio_lv_obj_set_size(void *o,int w,int h){if(o==cover_obj){cover_w=w;cover_h=h;}}
int32_t tio_lv_obj_get_width(void *o){assert(o==cover_obj);if(layout_lag){layout_lag--;return 0;}return cover_w;}
int32_t tio_lv_obj_get_height(void *o){assert(o==cover_obj);return layout_lag?0:cover_h;}
int td_gettid(void){return 7;}
static int hidden_set,hidden_clear;
void tio_lv_obj_add_flag(void *o,uint32_t f){(void)o;(void)f;hidden_set++;}
void tio_lv_obj_remove_flag(void *o,uint32_t f){(void)o;(void)f;hidden_clear++;}
void tio_lv_obj_set_style_bg_color(void *o,uint32_t c,uint32_t s){(void)o;(void)c;(void)s;}
void tio_lv_obj_set_style_bg_opa(void *o,uint8_t a,uint32_t s){(void)o;(void)a;(void)s;}
void tio_lv_obj_set_style_border_width(void *o,int32_t v,uint32_t s){(void)o;(void)v;(void)s;}
void tio_lv_obj_set_style_radius(void *o,int32_t v,uint32_t s){(void)o;(void)v;(void)s;}
void native_align(void *o,int a,int x,int y){(void)o;(void)a;(void)x;(void)y;}
unsigned tio_lang_stored(void){return 0;}
unsigned tio_knob_detent(void){return 400;}
int64_t pmu_rtc_epoch(void){return pmu;}
void kws_enable(void){kws_on++;}void kws_disable(void){kws_off++;}
void key_queue_flush(void){flushes++;}
int ots_topic_read(int fd,void *buf,size_t len){
 assert(fd==7&&len>=16);unsigned max=(unsigned)(len/16),n=topic_n<max?topic_n:max;uint8_t *p=buf;
 for(unsigned i=0;i<n;i++){memset(p+16*i,0,16);memcpy(p+16*i+8,&topic[i],4);}
 memmove(topic,topic+n,(topic_n-n)*sizeof topic[0]);topic_n-=n;return (int)(n*16);
}
/* Like stock: an empty hub leaves data.key as LVGL pre-filled it (the last key); an event writes key and pressed. */
void stock_key_read(void *indev,void *data){(void)indev;stock_key_calls++;if(next_key){memcpy((uint8_t *)data+TIO_STOCK_INDEV_DATA_KEY,&next_key,4);((uint8_t *)data)[TIO_STOCK_INDEV_DATA_STATE]=1;next_key=0;}}
void stock_wheel_read(void *indev,void *data){(void)indev;stock_wheel_calls++;memcpy((uint8_t *)data+TIO_STOCK_INDEV_DATA_ENC_DIFF,&next_diff,2);next_diff=0;topic_n=0;}
void *volatile tio_key_interceptors;
/* The neck tx queue: a queued message belongs to the tx thread, which sends and frees it. */
static int neck_sends;static bool neck_fail;static uint8_t neck_last[16];
int neck_send(void *msg,int32_t timeout){assert(timeout==0);neck_sends++;if(neck_fail)return -1;memcpy(neck_last,msg,16);free(msg);return 0;}
/* Widgets for the PIN view. */
static int view_texts;
static bool w_idle(void *c){(void)c;return true;}
static char w_objs[32];static int w_n;
static void *w_obj(void *c,void *p){(void)c;(void)p;return &w_objs[w_n++%32];}
static void *w_label(void *c,void *p,unsigned f){(void)f;return w_obj(c,p);}
static void w_place(void *c,void *o,int x,int y,int w,int h){(void)c;(void)o;(void)x;(void)y;(void)w;(void)h;}
static char w_txt[32][48];
static void w_text(void *c,void *o,const char *s){(void)c;view_texts++;snprintf(w_txt[(char *)o-w_objs],48,"%s",s);}
static bool w_shown[32];
static const char *shown(void *label){return w_shown[(char *)label-w_objs]?w_txt[(char *)label-w_objs]:"";}
static void w_destroy(void *c,void *o){(void)c;(void)o;}
#include "../src/navigation-runtime-v1/nav_view.h"
static int unaligned_buffers;
static void *w_canvas(void *c,void *p){return w_obj(c,p);}
static void w_buffer(void *c,void *o,const uint8_t *d,unsigned w,unsigned h){(void)c;(void)o;(void)w;(void)h;if((uintptr_t)d&63)unaligned_buffers++;}
static void w_visible(void *c,void *o,bool on){(void)c;w_shown[(char *)o-w_objs]=on;}
TNWidgets tn_lvgl_widgets(void){return (TNWidgets){.idle=w_idle,.root=w_obj,.canvas=w_canvas,.label=w_label,.place=w_place,.buffer=w_buffer,.text_static=w_text,.visible=w_visible,.destroy=w_destroy};}
/* An in-memory /mnt/nand_data with fault switches. */
typedef struct {char path[64];uint8_t data[64];size_t n;bool exists;} File;
static File files[2];static int writes;static bool write_fail;static int fail_bank=-1;static bool read_fail;static int err;
typedef struct {File *f;size_t pos;bool w;} Handle;
static File *lookup(const char *p){for(int i=0;i<2;i++)if(!strcmp(files[i].path,p))return &files[i];return NULL;}
static bool mounted=true,statfs_fail;
void *tap_fs_fopen(const char *p,const char *m){File *f=lookup(p);assert(f);if(!mounted){err=2;return NULL;}   /* an unmounted path does not resolve */
 if(m[0]=='r'&&read_fail){err=5;return NULL;}if(m[0]=='r'&&!f->exists){err=2;return NULL;}if(m[0]=='w'){if(write_fail||(fail_bank>=0&&f==&files[fail_bank]))return NULL;f->exists=true;f->n=0;writes++;}Handle *h=calloc(1,sizeof *h);h->f=f;h->w=m[0]=='w';return h;}
size_t tap_fs_fread(void *b,size_t s,size_t n,void *hp){Handle *h=hp;size_t k=s*n,left=h->f->n-h->pos;if(k>left)k=left;memcpy(b,h->f->data+h->pos,k);h->pos+=k;return k/s;}
size_t tap_fs_fwrite(const void *b,size_t s,size_t n,void *hp){Handle *h=hp;size_t k=s*n;assert(h->f->n+k<=sizeof h->f->data);memcpy(h->f->data+h->f->n,b,k);h->f->n+=k;return n;}
int tap_fs_ferror(void *h){(void)h;return 0;}
int tap_fs_feof(void *hp){Handle *h=hp;return h->pos>=h->f->n;}
int tap_fs_fflush(void *h){(void)h;return 0;}int tap_fs_fileno(void *h){(void)h;return 3;}int tap_fs_fsync(int fd){(void)fd;return 0;}
int tap_fs_fclose(void *h){free(h);return 0;}
int *tap_fs_errno(void){return &err;}
static int statfs_calls;
int tap_fs_statfs(const char *p,void *buf){statfs_calls++;assert(!strcmp(p,"/mnt/nand_data"));if(!mounted||statfs_fail){err=mounted?5:2;return -1;}uint32_t *w=buf;w[0]=0x0a732923u;w[2]=131072;w[4]=539;return 0;}
/* Stock wake locks: a token per acquire, released by (name, token); a release of a token not held is a stock miscount. */
static uint32_t holds_live[4];static int hold_takes,hold_releases,hold_next=0x50;
uint32_t nav_always_on(const char *n){assert(!strcmp(n,"turbo_lock_v1"));for(int i=0;i<4;i++)if(!holds_live[i]){holds_live[i]=(uint32_t)++hold_next;hold_takes++;return holds_live[i];}assert(!"wake lock list full");return 0;}
void nav_release_always_on(const char *n,uint32_t tok){assert(!strcmp(n,"turbo_lock_v1")&&tok);for(int i=0;i<4;i++)if(holds_live[i]==tok){holds_live[i]=0;hold_releases++;return;}assert(!"released a token not held");}
static int holds_held(void){int k=0;for(int i=0;i<4;i++)k+=holds_live[i]!=0;return k;}
/* LVGL lv_obj_move_to_index on a sys-layer child (only the cover is ever moved). */
static int moves;
void tio_lv_obj_move_to_index(void *o,int32_t idx){assert(o==cover_obj);uint16_t n=kids_n();assert(idx==(int32_t)n-1);kid_remove(o);kid_add(o);moves++;}
/* Focus mode: manager (+4 overlay view) -> overlay view (+4 LVGL root on the sys layer). */
static uint8_t focus_mgr[16],focus_view[16];static char focus_root_obj[4];
void *volatile tio_focus_manager;
static void focus_reset(bool on){memset(focus_mgr,0,sizeof focus_mgr);memset(focus_view,0,sizeof focus_view);tio_focus_manager=on?focus_mgr:NULL;
 void *p=focus_view;memcpy(focus_mgr+TIO_STOCK_FOCUS_MGR_OVERLAY,&p,sizeof p);p=focus_root_obj;memcpy(focus_view+TIO_STOCK_FOCUS_OVERLAY_ROOT,&p,sizeof p);}
static int logs;void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *f,...){(void)a;(void)b;(void)c;(void)d;(void)f;logs++;}

#include "../src/lock-v1/lock_anchor.c"
#include "../src/lock-v1/lock_native.c"

/* ------------------------------------------------------------------ helpers */
enum {T0=1800000000};
static void reset_world(bool keep_files){
 LockCtl *c=lock_anchor_any();(void)c;tio_key_interceptors=NULL;   /* a fresh boot: RAM is gone */
 memset(holds_live,0,sizeof holds_live);hold_takes=hold_releases=0;tio_focus_manager=NULL;   /* stock's wake lock list too */
 ms=1000;pmu=T0;folded=false;screen=true;ota=false;connected=true;bonded=true;
 screen_on_calls=force_off_calls=kws_on=kws_off=flushes=stock_key_calls=stock_wheel_calls=replies=0;
 covers=cover_deletes=hidden_set=hidden_clear=0;topic_n=0;next_key=0;next_diff=0;
 memset(wheel_ctx,0,sizeof wheel_ctx);int fd=7;memcpy(wheel_ctx+TIO_STOCK_WHEEL_FD,&fd,4);
 sys_reset();local_time=0;battery_level=-1;memset(display,0,sizeof display);void *p=screen_obj;memcpy(display+TIO_STOCK_DISPLAY_SCREEN,&p,sizeof p);p=sys_obj;memcpy(display+TIO_STOCK_DISPLAY_SYS,&p,sizeof p);
 if(!keep_files){memset(files,0,sizeof files);}
 strcpy(files[0].path,"/mnt/nand_data/turbo_lock_v1_0.cfg");strcpy(files[1].path,"/mnt/nand_data/turbo_lock_v1_1.cfg");
 writes=0;write_fail=false;fail_bank=-1;read_fail=false;mounted=true;statfs_fail=false;
}
static uint8_t lv_data[0x14];   /* LVGL's indev data: persists between polls, key = the last key */
/* Boot is the first keypad poll (an empty one here); a second poll finds the same state and boots nothing. */
static LockCtl *boot(void){
 memset(lv_data,0,sizeof lv_data);int k=stock_key_calls;lock_hook_key_read(NULL,lv_data);LockCtl *c=lock_anchor_any();assert(c&&c->magic==LOCK_MAGIC);
 lock_hook_key_read(NULL,lv_data);assert(lock_anchor_any()==c&&stock_key_calls==k+2);stock_key_calls=k;return c;
}
static void do_tick(void){tick(timer_obj);}
static uint32_t key(uint32_t k){next_key=k;lock_hook_key_read(NULL,lv_data);uint32_t out;memcpy(&out,lv_data+TIO_STOCK_INDEV_DATA_KEY,4);return out;}
static uint32_t poll_empty(void){return key(0);}
static int16_t wheel(int32_t x,unsigned samples){uint8_t data[0x14]={0};for(unsigned i=0;i<samples;i++)topic[topic_n++]=x;lock_hook_wheel_read(NULL,data);int16_t d;memcpy(&d,data+TIO_STOCK_INDEV_DATA_ENC_DIFF,2);return d;}
static uint32_t req=1;
static TLKReply phone(uint8_t op,uint32_t token,const TLKCommand *extra){
 TLKCommand q={0};if(extra)q=*extra;q.op=op;q.token=token;q.client=42;q.request=req++;
 uint8_t raw[32],wire[74];tlk_encode(raw,&q);tlk_carrier(wire,raw,false);int before=replies;assert(lock_native_message(wire,74));assert(replies==before+1);
 uint8_t back[32];assert(tlk_uncarrier(last_reply,74,back,true));TLKReply r;assert(tlk_reply_decode(back,32,&r)&&r.request==q.request);return r;
}
static TLKReply op(uint8_t o,const TLKCommand *extra){TLKReply r=phone(TLK_OP_QUERY,0,NULL);assert(r.result==TLK_R_OK&&r.token);return phone(o,r.token,extra);}
/* Phone unlock: while locked and unfolded the glasses show "Unlocked" for 2 s (panel on), then the state underneath. */
static TLKReply unlock(void){TLKReply r=op(TLK_OP_UNLOCK,NULL);LockCtl *c=lock_anchor_any();if(c&&c->svc.lock.state==TLK_UNLOCKED_MSG){ms+=TLK_UNLOCKED_SHOW_MS;tick(timer_obj);}return r;}
static void enter_pin(const uint8_t pin[4]){
 ms+=TLK_ENTRY_GRACE_MS;   /* the PIN screen was lit by the last sync; input counts after the grace */
 for(unsigned i=0;i<4;i++){for(unsigned k=0;k<pin[i];k++)assert(wheel(-400,1)==0);assert(key(TIO_STOCK_KEY_CONFIRM)==0);}
}

int main(void){
 const uint8_t PIN[4]={2,0,0,5},BAD[4]={1,1,1,1};
 /* 1. No lock file (an upgrade from TMG12): Off, nothing is touched, every key and knob step reaches stock. */
 reset_world(false);LockCtl *c=boot();
 assert(c->svc.lock.state==TLK_OFF&&!c->dark&&!c->locked&&force_off_calls==0);
 AnchorNode *head=tio_key_interceptors;assert(head&&head->handler(NULL)==0);   /* the anchor never consumes a key */
 assert(key(0x45)==0x45&&key(TIO_STOCK_KEY_CONFIRM)==TIO_STOCK_KEY_CONFIRM&&stock_key_calls==2);
 next_diff=3;assert(wheel(500,2)==3&&stock_wheel_calls==1);
 assert(!lock_refuse_screen(1,1)&&!lock_refuse_can_wakeup()&&!lock_refuse_open_remote_audio()&&!lock_refuse_open_recorder()&&!lock_native_locked());
 /* 2. The phone sets a PIN: enabled, unlocked, the record written. The TLK: gate ignores the fold state. */
 folded=true;TLKCommand pin={.pin={2,0,0,5}};TLKReply r=op(TLK_OP_SET_PIN,&pin);folded=false;
 assert(r.result==TLK_R_OK&&(r.flags&TLK_F_ENABLED)&&!(r.flags&TLK_F_LOCKED)&&writes==1&&files[0].exists);
 ota=true;r=phone(TLK_OP_QUERY,0,NULL);assert(r.result==TLK_R_BLOCKED);ota=false;
 connected=false;r=phone(TLK_OP_QUERY,0,NULL);assert(r.result==TLK_R_BLOCKED);connected=true;
 /* 3. Reboot: locked and dark before anything is drawn. */
 reset_world(true);c=boot();
 assert(c->svc.lock.state==TLK_DARK&&c->dark&&c->locked&&force_off_calls==1&&!screen);
 assert(lock_refuse_screen(1,1)&&!lock_refuse_screen(0,1));
 assert(lock_refuse_can_wakeup()&&lock_refuse_open_remote_audio()&&lock_refuse_open_recorder()&&lock_native_locked());
 assert(kws_off==1);
 /* Keys while dark: the double press, holds and five-press are blanked; the factory confirm and the 5 s hold reach
  * stock; back reaches stock while dark; the stock read ran every time (the button hub drains). */
 int calls=stock_key_calls;
 assert(key(0x45)==0&&key(0x46)==0&&key(0x42)==0&&key(0x43)==0&&key(0x3c)==0&&key(0x47)==0&&key(0x49)==0);
 assert(key(0x3d)==0x3d&&key(0x44)==0x44&&key(TIO_STOCK_KEY_BACK)==TIO_STOCK_KEY_BACK);
 assert(stock_key_calls==calls+10&&c->svc.lock.state==TLK_DARK&&!screen);
 /* Knob while dark: stock never runs, the topic is drained, the pending step cleared, nothing shown. */
 int16_t pending=5;memcpy(wheel_ctx+TIO_STOCK_ENCODER_STEP,&pending,2);calls=stock_wheel_calls;
 assert(wheel(-900,8)==0&&stock_wheel_calls==calls&&topic_n==0);memcpy(&pending,wheel_ctx+TIO_STOCK_ENCODER_STEP,2);assert(pending==0);
 assert(c->svc.lock.state==TLK_DARK&&!screen);
 /* 4. A press brings up the PIN screen: the gate opens, the cover goes up, the panel turns on. */
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY);
 assert(!c->dark&&screen&&covers==1&&c->view_open&&hidden_set>0&&!lock_refuse_screen(1,1)&&c->locked);
 /* First press (device feedback 1): the wake press opened the PIN screen and the sync lit it (queue flushed); an impatient
  * second press and a turn inside the grace are dropped, so no digit is taken; after the grace a turn counts. */
 assert(c->svc.lock.lit&&c->svc.lock.lit_ms==ms);
 {int fl=flushes;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&wheel(-400,1)==0&&c->svc.lock.slot==0&&c->svc.lock.digit==0&&flushes==fl);}
 ms+=TLK_ENTRY_GRACE_MS;assert(wheel(-400,1)==0&&c->svc.lock.digit==1);assert(wheel(400,1)==0&&c->svc.lock.digit==0);
 /* 5. Digits by knob (one detent = one step; the topic samples are summed), wrong PIN, then the right one. */
 ms+=100;enter_pin(BAD);assert(c->svc.lock.state==TLK_WRONG&&c->svc.lock.rec.wrong==1&&files[0].exists);
 ms+=2000;do_tick();assert(c->svc.lock.state==TLK_ENTRY);
 /* The PIN screen came back after "Wrong PIN" and was lit again at that tick: the queue is flushed then, once. */
 assert(c->svc.lock.lit&&flushes==2);
 calls=stock_wheel_calls;ms+=100;enter_pin(PIN);assert(stock_wheel_calls==calls);
 assert(c->svc.lock.state==TLK_NOTICE&&c->svc.lock.notice==1&&!c->locked&&!lock_refuse_can_wakeup()&&flushes==3);   /* + the unlock flush */
 assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_UNLOCKED);   /* the press that dismisses the notice is consumed */
 do_tick();assert(cover_deletes==1&&hidden_clear>0&&kws_on==1);
 assert(key(0x45)==0x45);next_diff=1;assert(wheel(500,1)==1);   /* unlocked: stock again */
 /* 6. Idle lock through the screen gate: screen off, 5 min without use, a wake is refused and the tick locks. */
 screen=false;pmu+=299;assert(!lock_refuse_screen(1,2));pmu+=1;
 assert(lock_refuse_screen(1,2)&&c->lock_request);do_tick();assert(c->svc.lock.state==TLK_DARK&&c->dark&&lock_refuse_screen(1,2));
 /* Knob or key use keeps it unlocked. */
 /* Phone unlock while dark: the panel turns on with "Unlocked" in band B, the gates open at once; 2 s later the cover goes. */
 {int on=screen_on_calls,cov=covers;r=op(TLK_OP_UNLOCK,NULL);
  assert(r.result==TLK_R_OK&&c->svc.lock.state==TLK_UNLOCKED_MSG&&!c->dark&&!c->locked&&screen&&screen_on_calls>on&&covers==cov+1&&!lock_refuse_can_wakeup());
  ms+=100;do_tick();assert(!strcmp(shown(c->view.labels[TLV_B]),"Unlocked")&&c->svc.lock.lit);
  /* F2-3: shown TLK_UNLOCKED_SHOW_MS from the moment the panel was asked on, not from the phone's command. */
  ms+=TLK_UNLOCKED_SHOW_MS-200;do_tick();assert(c->svc.lock.state==TLK_UNLOCKED_MSG&&c->cover);
  ms+=200;do_tick();assert(c->svc.lock.state==TLK_UNLOCKED&&!c->cover&&screen);}
 assert(c->svc.lock.state==TLK_UNLOCKED&&!c->dark);
 screen=false;pmu+=200;assert(key(TIO_STOCK_KEY_CONFIRM)==TIO_STOCK_KEY_CONFIRM);pmu+=200;assert(!lock_refuse_screen(1,2));
 /* An input after the idle time with the screen off locks first and is then handled as locked input. */
 screen=false;pmu+=300;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&screen);
 key(TIO_STOCK_KEY_BACK);assert(c->svc.lock.state==TLK_DARK);
 /* 7. Fold lock: fold seen by the gate as the panel goes off, unfold after the fold delay. */
 r=unlock();assert(c->svc.lock.state==TLK_UNLOCKED);
 folded=true;assert(!lock_refuse_screen(0,3)&&c->gate_fold_s==(uint32_t)pmu);
 pmu+=300;folded=false;assert(lock_refuse_screen(1,3)&&c->lock_request);do_tick();assert(c->svc.lock.state==TLK_DARK);
 /* A fold only the gate saw (no tick while folded): the first unfolded tick applies it before the screen-on request. */
 r=unlock();folded=true;screen=false;assert(!lock_refuse_screen(0,3));pmu+=300;folded=false;do_tick();assert(c->svc.lock.state==TLK_DARK);
 /* Folded and unfolded within the delay: stays unlocked. */
 r=unlock();folded=true;screen=false;do_tick();pmu+=10;folded=false;screen=true;assert(!lock_refuse_screen(1,3));do_tick();assert(c->svc.lock.state==TLK_UNLOCKED);
 /* The unfold window: after a fold past the delay the lock is taken at the first UI-thread step after stock's unfold (a
  * launcher message, which runs before stock's handler, or a key), not at the next tick; before that the wake gates refuse. */
 r=unlock();folded=true;screen=false;do_tick();pmu+=300;folded=false;
 assert(lock_refuse_can_wakeup()&&lock_refuse_open_recorder()&&lock_refuse_open_remote_audio()&&c->svc.lock.state==TLK_UNLOCKED);
 lock_boot_early();assert(c->svc.lock.state==TLK_DARK&&c->dark&&!c->lock_request);
 r=unlock();do_tick();assert(c->svc.lock.state==TLK_UNLOCKED);   /* no stale lock request after the unlock */
 folded=true;screen=false;do_tick();pmu+=300;folded=false;
 assert(key(TIO_STOCK_KEY_CONFIRM)==0&&tlk_locked(&c->svc.lock));
 r=unlock();do_tick();assert(c->svc.lock.state==TLK_UNLOCKED);
 /* Unlocked with the screen on past the idle time (reading): the wake gates do not refuse. */
 screen=true;do_tick();pmu+=400;assert(!lock_refuse_can_wakeup());pmu-=400;
 /* 8. A clock fault never keeps the glasses unlocked. */
 screen=false;pmu=0;assert(lock_refuse_screen(1,2));do_tick();assert(c->svc.lock.state==TLK_DARK);
 pmu=T0+5000;r=unlock();screen=false;pmu=(int64_t)1e12;assert(lock_refuse_screen(1,2));do_tick();assert(c->svc.lock.state==TLK_DARK);
 pmu=T0+6000;
 /* 9. Phone while locked: other families are refused (remote gate), TLK: answers; Lock now from the phone. */
 assert(lock_native_locked());r=unlock();assert(!lock_native_locked());r=op(TLK_OP_LOCK_NOW,NULL);assert(r.result==TLK_R_OK&&c->dark&&!screen);
 /* 10. The anchor displaced (something inserted ahead of it): the tick goes dark while locked and puts it back. */
 static AnchorNode other;memset(&other,0,sizeof other);other.next=tio_key_interceptors;tio_key_interceptors=&other;
 assert(!lock_anchor_any()&&(lock_refuse_can_wakeup()==(ms<PENDING_UNTIL_MS)));{uint32_t m0=ms;ms=PENDING_UNTIL_MS;assert(!lock_refuse_can_wakeup());ms=m0;}int offs=force_off_calls;do_tick();assert(force_off_calls>offs||c->dark);
 assert(lock_anchor_any()==c&&((AnchorNode *)tio_key_interceptors)->next==&other&&other.next==NULL);
 /* 11. Wrong tries persist across a reboot and the delay continues. */
 r=unlock();r=op(TLK_OP_LOCK_NOW,NULL);
 for(int i=0;i<3;i++){key(TIO_STOCK_KEY_CONFIRM);enter_pin(BAD);ms+=2000;do_tick();if(c->svc.lock.state==TLK_ENTRY)key(TIO_STOCK_KEY_BACK);}
 assert(c->svc.lock.rec.wrong==3&&c->svc.lock.rec.delay_until==(uint32_t)pmu+30);
 reset_world(true);pmu=T0+6000+10;c=boot();assert(c->svc.lock.state==TLK_DARK&&c->svc.lock.rec.wrong==3);
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->svc.lock.state==TLK_WAITING&&screen);
 /* 12. Factory reset: the record becomes "off" in both banks, so the next boot is unlocked. */
 lock_on_factory_reset();reset_world(true);c=boot();assert(c->svc.lock.state==TLK_OFF&&!c->dark);
 /* 13. Both banks damaged: locked; a press shows "Use phone" and goes dark again; the phone unlocks and repairs. */
 r=op(TLK_OP_SET_PIN,&pin);files[0].data[9]^=1;files[1].data[9]^=1;files[1].exists=true;files[1].n=files[0].n;
 reset_world(true);c=boot();assert(c->svc.lock.state==TLK_DARK&&c->svc.lock.damaged);
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->svc.lock.state==TLK_USE_PHONE&&screen);ms+=2000;do_tick();assert(c->svc.lock.state==TLK_DARK&&!screen);
 r=unlock();assert(r.result==TLK_R_OK&&!c->locked);r=op(TLK_OP_SET_PIN,&pin);assert(!(r.flags&TLK_F_DAMAGED));
 reset_world(true);c=boot();assert(c->svc.lock.state==TLK_DARK&&!c->svc.lock.damaged);
 /* 14. The cover cannot be made (no sys layer): the backstop keeps the panel dark. */
 memset(display,0,sizeof display);ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->dark&&!screen&&c->svc.lock.state==TLK_DARK);
 /* 15. A stale key (LVGL re-presents the last key on every empty poll) is not an event: it neither keeps the glasses
  *     unlocked nor counts as a press while locked. */
 reset_world(true);c=boot();
 r=unlock();assert(c->svc.lock.state==TLK_UNLOCKED);ms+=100;
 assert(key(TIO_STOCK_KEY_CONFIRM)==TIO_STOCK_KEY_CONFIRM);
 screen=false;pmu+=300;for(int i=0;i<5;i++)assert(poll_empty()==TIO_STOCK_KEY_CONFIRM&&c->svc.lock.state==TLK_UNLOCKED);
 assert(lock_refuse_screen(1,2)&&c->lock_request);do_tick();assert(c->svc.lock.state==TLK_DARK);
 for(int i=0;i<5;i++){ms+=30;assert(poll_empty()==TIO_STOCK_KEY_CONFIRM);}
 assert(c->svc.lock.state==TLK_DARK&&!screen);
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&screen);   /* a real press still opens the PIN screen */
 /* 16. Boot from a wheel poll or a TLK: message works the same (whichever LVGL-thread call comes first). */
 reset_world(true);assert(!lock_anchor_any());{uint8_t wd[0x14]={0};lock_hook_wheel_read(NULL,wd);}c=lock_anchor_any();assert(c&&c->svc.lock.state==TLK_DARK);
 reset_world(true);r=phone(TLK_OP_QUERY,0,NULL);c=lock_anchor_any();assert(c&&(r.flags&TLK_F_LOCKED));
 /* 16a. The view opens after LVGL has laid out the cover (the 1.0.6.11 emulator run LKT-R3: a view opened in the same
  *      call as the cover read a 0x0 parent); a cover that is never laid out falls back to dark. Until the cover is laid
  *      out (drawn) the panel stays dark and gated, so it never lights on the frame stock drew under it (runs LKF-F2b,
  *      LKF-B1). */
 reset_world(true);c=boot();layout_lag=1;int on16=screen_on_calls;
 assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&c->cover&&!c->view_open&&c->dark&&!screen&&screen_on_calls==on16&&lock_refuse_screen(1,1));
 do_tick();assert(c->view_open&&c->svc.lock.state==TLK_ENTRY&&!c->dark&&screen&&screen_on_calls==on16+1);
 reset_world(true);c=boot();layout_lag=1000;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&!c->view_open);
 for(int i=0;i<12;i++){ms+=250;do_tick();}assert(c->dark&&!c->cover&&!screen&&c->svc.lock.state==TLK_DARK);layout_lag=0;
 /* 16b. The early start (stream_register_shim, launcher messages) boots once and then only finds the state. */
 reset_world(true);lock_boot_early();c=lock_anchor_any();assert(c&&c->svc.lock.state==TLK_DARK&&c->dark);lock_boot_early();assert(lock_anchor_any()==c);
 /* 17. Storage not mounted at the first poll: Pending (dark, gated, every key and knob step dropped, no phone answer)
  *     until the first mounted read, which settles the boot by the normal table; never Pending again in that boot. */
 static File saved[2];memcpy(saved,files,sizeof files);
 reset_world(true);mounted=false;ms=1000;screen=true;c=boot();
 assert(c->pending&&c->svc.lock.state==TLK_DARK&&c->dark&&c->locked&&!screen&&lock_refuse_can_wakeup()&&lock_refuse_screen(1,0));
 {int k=stock_key_calls;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->pending&&c->svc.lock.state==TLK_DARK&&stock_key_calls==k+1);}   /* a press opens nothing */
 assert(key(0x3d)==0x3d);   /* the factory-reset confirm still reaches stock */
 assert(wheel(-400,1)==0&&c->svc.lock.state==TLK_DARK);
 {TLKCommand q={0};q.op=TLK_OP_QUERY;q.client=42;q.request=req++;uint8_t raw[32],wire[74];tlk_encode(raw,&q);tlk_carrier(wire,raw,false);int before=replies;assert(lock_native_message(wire,74)&&replies==before&&c->pending);}
 do_tick();assert(c->pending);ms+=250;mounted=true;do_tick();assert(c->pending);   /* checked once a second */
 ms+=1000;do_tick();assert(!c->pending&&c->svc.lock.state==TLK_DARK&&!c->svc.lock.damaged&&c->svc.lock.rec.enabled);   /* record: locked */
 mounted=false;read_fail=true;for(int i=0;i<5;i++){ms+=1000;do_tick();}assert(!c->pending&&!c->svc.lock.damaged);   /* never Pending again */
 /* Mounted late with no lock file: Off, and the panel the Pending dark turned off comes back. */
 reset_world(false);mounted=false;c=boot();assert(c->pending&&!screen);ms+=1000;do_tick();assert(c->pending);
 mounted=true;ms+=1000;int on=screen_on_calls;do_tick();assert(!c->pending&&c->svc.lock.state==TLK_OFF&&!c->dark&&!c->locked&&screen&&screen_on_calls==on+1);
 assert(!lock_refuse_can_wakeup()&&!lock_refuse_screen(1,0));
 /* Mounted at the first poll with no file: Off at once, no dark time, no statfs-driven retries. */
 reset_world(false);int fo=force_off_calls;c=boot();assert(!c->pending&&c->svc.lock.state==TLK_OFF&&force_off_calls==fo&&screen);
 int sc=statfs_calls;for(int i=0;i<5;i++){ms+=1000;do_tick();}assert(statfs_calls==sc);
 /* Mounted, but the read fails (I/O error): damaged, dark, the normal rule (no Pending). */
 reset_world(false);read_fail=true;c=boot();assert(!c->pending&&c->svc.lock.damaged&&c->svc.lock.state==TLK_DARK);read_fail=false;
 /* Never mounted within the first minute: Off (stated limit), panel back. */
 memcpy(files,saved,sizeof files);reset_world(true);mounted=false;c=boot();
 while(ms<PENDING_UNTIL_MS){ms+=1000;do_tick();}assert(!c->pending&&c->svc.lock.state==TLK_OFF&&screen);
 /* A phone message while Pending with storage now mounted settles first, then answers. */
 reset_world(true);mounted=false;c=boot();mounted=true;r=phone(TLK_OP_QUERY,0,NULL);assert(!c->pending&&(r.flags&TLK_F_LOCKED));
 /* statfs fails on a mounted volume (littlefs walks the volume for its size): a good record is still taken at boot. */
 memcpy(files,saved,sizeof files);reset_world(true);statfs_fail=true;c=boot();assert(!c->pending&&c->svc.lock.state==TLK_DARK&&c->svc.lock.rec.enabled);
 /* ... and no file with statfs failing: Pending, then Off at the cap (the volume cannot be shown mounted). */
 reset_world(false);statfs_fail=true;c=boot();assert(c->pending);while(ms<PENDING_UNTIL_MS){ms+=1000;do_tick();}assert(!c->pending&&c->svc.lock.state==TLK_OFF);
 /* Pending, then storage appears with a good record while statfs still fails: locked at the next check. */
 memcpy(files,saved,sizeof files);reset_world(true);mounted=false;c=boot();assert(c->pending);mounted=true;statfs_fail=true;ms+=1000;do_tick();assert(!c->pending&&c->svc.lock.state==TLK_DARK);
 /* Off after the cap, storage mounts later, the phone sets a PIN: the write goes above the old record's generation. */
 memcpy(files,saved,sizeof files);reset_world(true);mounted=false;c=boot();while(ms<PENDING_UNTIL_MS){ms+=1000;do_tick();}assert(c->svc.lock.state==TLK_OFF&&!c->svc.stored.generation);
 mounted=true;{TLKRecord old;TLRStored ost;assert(tlr_load(&tlr_io,&old,&ost)==TLK_LOAD_GOOD);
  TLKCommand q={0};q.pin[0]=9;q.pin[1]=9;q.pin[2]=9;q.pin[3]=9;r=op(TLK_OP_SET_PIN,&q);assert(r.result==TLK_R_OK&&c->svc.stored.generation==ost.generation+1);}
 reset_world(true);c=boot();{const uint8_t P9[4]={9,9,9,9};assert(c->svc.lock.state==TLK_DARK);assert(key(TIO_STOCK_KEY_CONFIRM)==0);enter_pin(P9);assert(c->svc.lock.state==TLK_UNLOCKED);}
 /* A Pending boot that settles Off does not switch the wake word on (stock does that at its next return to running). */
 reset_world(false);mounted=false;c=boot();do_tick();assert(c->kws_off);int on0=kws_on;mounted=true;ms+=1000;do_tick();assert(c->svc.lock.state==TLK_OFF&&kws_on==on0&&!c->kws_off);
 /* No lock object (not started, or the anchor displaced): the assistant gates refuse in the first minute only. */
 reset_world(true);assert(!lock_anchor_any());ms=5000;assert(lock_refuse_can_wakeup()&&lock_refuse_open_recorder()&&!lock_refuse_screen(1,0));
 ms=PENDING_UNTIL_MS;assert(!lock_refuse_can_wakeup());
 /* 18. Factory reset with one bank write failing: the Off record still wins at the next boot, and the running lock is Off
  *     at once (no later write brings the old record back). */
 memcpy(files,saved,sizeof files);reset_world(true);c=boot();assert(c->svc.lock.state==TLK_DARK);
 fail_bank=1;lock_on_factory_reset();fail_bank=-1;assert(c->svc.lock.state==TLK_OFF&&!c->dark&&!c->locked);
 do_tick();reset_world(true);c=boot();assert(c->svc.lock.state==TLK_OFF);
 memcpy(files,saved,sizeof files);reset_world(true);c=boot();fail_bank=0;lock_on_factory_reset();fail_bank=-1;reset_world(true);c=boot();assert(c->svc.lock.state==TLK_OFF);
 /* 19. Band T of the PIN screen: time and battery from stock's getters, battery right-aligned; unknown shows --:-- and --%. */
 memcpy(files,saved,sizeof files);reset_world(true);c=boot();local_time=1800057600+3600*14+60*7;   /* 1800057600 is a midnight */battery_level=83;
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&c->view_open&&aligned_right>0);
 {int hit=0;for(unsigned i=TLV_M;i<=TLV_B;i++)for(int j=0;j<16;j++)if(centred[j]==c->view.labels[i]){hit++;break;}assert(hit==2);}   /* the message lines centred */
 assert(((uintptr_t)c&63)==0&&!unaligned_buffers);   /* the state block and every canvas buffer the view hands over are 64-byte aligned */
 ms+=3000;do_tick();   /* the hint covers band T for 3 s after the screen opens */
 assert(!strcmp(shown(c->view.labels[TLV_TIME]),"14:07")&&!strcmp(shown(c->view.labels[TLV_BATT]),"83%"));
 assert(invalidates>0);   /* the panel came on: the whole cover is redrawn */
 /* Read at most once a second: a tick 100 ms later still shows the old values, one a second later the new ones. */
 int tr=time_reads;battery_level=-1;local_time=0;ms+=100;do_tick();assert(time_reads==tr&&!strcmp(shown(c->view.labels[TLV_BATT]),"83%"));
 ms+=1000;do_tick();assert(time_reads==tr+1&&!strcmp(shown(c->view.labels[TLV_TIME]),"--:--")&&!strcmp(shown(c->view.labels[TLV_BATT]),"--%"));
 /* 20. Something stock adds to the sys layer over the PIN screen (a call view, a toast): the next sync closes the lock
  *     screen, drops the half-entered digits and goes dark; the next press opens it again on top. */
 ms+=100;assert(wheel(-400,1)==0&&key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.slot==1);
 int fo20=force_off_calls,del=cover_deletes;kid_add(foreign_obj);ms+=100;do_tick();
 assert(c->svc.lock.state==TLK_DARK&&c->dark&&!screen&&force_off_calls==fo20+1&&cover_deletes==del+1&&!c->cover&&c->locked&&lock_refuse_screen(1,1));
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&c->svc.lock.slot==0&&c->cover&&sys_kids[kids_n()-1]==cover_obj);
 ms+=100;do_tick();assert(c->svc.lock.state==TLK_ENTRY&&!c->dark);   /* on top again: stays up */
 /* Stock bringing an older child to the front counts the same. */
 kid_remove(foreign_obj);kid_add(foreign_obj);ms+=100;do_tick();assert(c->svc.lock.state==TLK_DARK&&c->dark);
 /* Unreadable children list: fail closed (dark). */
 kid_remove(foreign_obj);ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY);
 memset(sys_obj+TIO_STOCK_OBJ_SPEC_ATTR,0,sizeof(void *));ms+=100;do_tick();assert(c->svc.lock.state==TLK_DARK&&c->dark);
 sys_reset();kids_set(0);
 /* The failure notice is unlocked: something over it changes nothing. */
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY);enter_pin(BAD);ms+=2000;do_tick();enter_pin(PIN);
 assert(c->svc.lock.state==TLK_NOTICE);kid_add(foreign_obj);ms+=100;do_tick();assert(c->svc.lock.state==TLK_NOTICE&&!c->dark);kid_remove(foreign_obj);
 /* 14. Head motion: MOTION_ON sends "motion on" to the Bluetooth core (fire-and-forget, never waiting for queue room);
  * a send that is not queued refuses the op; "motion seen" counts as use only while motion is on; before MOTION_ON
  * (after every boot) it changes nothing. */
 reset_world(false);c=boot();r=op(TLK_OP_SET_PIN,&pin);assert(r.result==TLK_R_OK&&(r.flags&TLK_F_MOTION_SUPPORTED)&&!(r.flags&TLK_F_MOTION));
 lock_motion_rx();screen=false;do_tick();pmu+=299;assert(!lock_refuse_screen(1,2));pmu+=1;assert(lock_refuse_screen(1,2));do_tick();assert(c->svc.lock.state==TLK_DARK);
 r=unlock();assert(c->svc.lock.state==TLK_UNLOCKED);
 neck_fail=true;neck_sends=0;r=op(TLK_OP_MOTION_ON,NULL);assert(r.result==TLK_R_REFUSED&&!(r.flags&TLK_F_MOTION)&&neck_sends==1&&!c->svc.motion_on);
 neck_fail=false;r=op(TLK_OP_MOTION_ON,NULL);assert(r.result==TLK_R_OK&&(r.flags&TLK_F_MOTION)&&neck_sends==2&&c->svc.motion_on);
 {uint16_t ty;uint32_t w[3];memcpy(&ty,neck_last,2);memcpy(w,neck_last+4,12);assert(ty==8&&neck_last[2]==0&&neck_last[3]==0&&w[0]==8&&w[1]==0x314f4d54u&&w[2]==1);}
 screen=false;pmu+=200;lock_motion_rx();lock_motion_rx();do_tick();assert(c->svc.lock.state==TLK_UNLOCKED&&c->motion_seen==c->motion_rx);
 pmu+=200;assert(!lock_refuse_screen(1,2));do_tick();pmu+=100;assert(lock_refuse_screen(1,2));do_tick();assert(c->svc.lock.state==TLK_DARK);
 lock_motion_rx();pmu+=1;do_tick();assert(c->svc.lock.state==TLK_DARK);   /* motion never unlocks */
 r=op(TLK_OP_DISABLE,NULL);assert(r.result==TLK_R_OK&&c->svc.lock.state==TLK_OFF);neck_sends=0;r=op(TLK_OP_MOTION_ON,NULL);assert(r.result==TLK_R_REFUSED&&neck_sends==0);
 tio_key_interceptors=NULL;lock_motion_rx();   /* no lock state found: dropped, no crash */
 reset_world(true);
 /* 21. The wake lock (TMG17): taken once when a time-limited lock screen is lit, never on the failure notice, and released
  *     on every way out: PIN unlock, phone unlock ("Unlocked" holds it, then releases), entry timeout, covered close, fold,
  *     back to dark, phone lock now, disable. Never two at once, never a release of a token not held. */
 assert(!holds_held());
 memcpy(files,saved,sizeof files);reset_world(true);c=boot();assert(!c->hold&&!holds_held());
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&screen&&c->hold&&holds_held()==1);
 {int t0=hold_takes;for(int i=0;i<8;i++){ms+=250;do_tick();}assert(hold_takes==t0&&holds_held()==1);}   /* syncs do not take it again */
 ms+=TLK_ENTRY_TIMEOUT_MS;do_tick();assert(c->svc.lock.state==TLK_DARK&&!c->hold&&!holds_held()&&!screen);   /* 30 s untouched: dark, released */
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);   /* turns and presses keep it up: the lock's 30 s runs from the last input */
 for(int i=0;i<5;i++){ms+=TLK_ENTRY_TIMEOUT_MS-1000;assert(wheel(-400,1)==0);do_tick();assert(c->svc.lock.state==TLK_ENTRY&&c->hold);}
 key(TIO_STOCK_KEY_BACK);assert(c->svc.lock.state==TLK_DARK&&!holds_held());   /* back from the first slot: dark */
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);folded=true;do_tick();assert(c->svc.lock.state==TLK_DARK&&!holds_held());folded=false;do_tick();
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);kid_add(foreign_obj);ms+=100;do_tick();assert(c->svc.lock.state==TLK_DARK&&!holds_held());kid_remove(foreign_obj);
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);enter_pin(BAD);assert(c->svc.lock.state==TLK_WRONG&&holds_held()==1);   /* wrong PIN: same hold */
 ms+=2000;do_tick();assert(c->svc.lock.state==TLK_ENTRY&&holds_held()==1);enter_pin(PIN);
 assert(c->svc.lock.state==TLK_NOTICE&&!holds_held());   /* the notice holds nothing */
 key(TIO_STOCK_KEY_CONFIRM);do_tick();assert(c->svc.lock.state==TLK_UNLOCKED&&!holds_held());
 r=op(TLK_OP_LOCK_NOW,NULL);ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);r=op(TLK_OP_LOCK_NOW,NULL);assert(c->dark&&!holds_held());
 r=op(TLK_OP_UNLOCK,NULL);assert(c->svc.lock.state==TLK_UNLOCKED_MSG&&holds_held()==1);   /* "Unlocked" (4-5 s) */
 ms+=TLK_UNLOCKED_SHOW_MS+100;do_tick();do_tick();assert(c->svc.lock.state==TLK_UNLOCKED&&!holds_held());
 r=op(TLK_OP_LOCK_NOW,NULL);ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);r=op(TLK_OP_UNLOCK,NULL);do_tick();assert(holds_held()==1);
 r=op(TLK_OP_LOCK_NOW,NULL);ms+=100;key(TIO_STOCK_KEY_CONFIRM);assert(c->hold);r=op(TLK_OP_DISABLE,NULL);assert(c->svc.lock.state==TLK_OFF&&!holds_held());
 r=op(TLK_OP_SET_PIN,&pin);assert(hold_takes==hold_releases);
 /* 22. Focus mode ("Do Not Disturb") moves its overlay root to the top of the sys layer 3 s after the panel lights: the
  *     cover is moved back on top and redrawn, the PIN screen and its digits stay. Any other top child, a missing step in
  *     the manager -> overlay -> root chain, or a cover no longer in the list still closes to dark. */
 reset_world(true);c=boot();focus_reset(true);kid_add(focus_root_obj);
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY&&sys_kids[kids_n()-1]==cover_obj);
 ms+=TLK_ENTRY_GRACE_MS;assert(wheel(-400,1)==0&&wheel(-400,1)==0&&key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.slot==1);
 {int m0=moves,inv=invalidates,fo=force_off_calls;kid_remove(focus_root_obj);kid_add(focus_root_obj);ms+=250;do_tick();
  assert(moves==m0+1&&invalidates>inv&&sys_kids[kids_n()-1]==cover_obj&&c->svc.lock.state==TLK_ENTRY&&c->svc.lock.slot==1&&!c->dark&&force_off_calls==fo&&c->hold);}
 {const uint8_t rest[3]={0,0,5};for(unsigned i=0;i<3;i++){for(unsigned k=0;k<rest[i];k++)assert(wheel(-400,1)==0);assert(key(TIO_STOCK_KEY_CONFIRM)==0);}}
 assert(c->svc.lock.state==TLK_UNLOCKED&&!holds_held());   /* 2-0-0-5 after the raise: unlocked */
 r=op(TLK_OP_LOCK_NOW,NULL);
 #define FOCUS_CLOSES(setup) do{ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_ENTRY);int m0=moves;setup;kid_remove(focus_root_obj);kid_add(focus_root_obj);ms+=250;do_tick();\
  assert(moves==m0&&c->svc.lock.state==TLK_DARK&&c->dark&&!holds_held());focus_reset(true);}while(0)
 FOCUS_CLOSES(tio_focus_manager=NULL);
 FOCUS_CLOSES(memset(focus_mgr+TIO_STOCK_FOCUS_MGR_OVERLAY,0,sizeof(void *)));
 FOCUS_CLOSES(memset(focus_view+TIO_STOCK_FOCUS_OVERLAY_ROOT,0,sizeof(void *)));
 FOCUS_CLOSES(kid_remove(cover_obj));
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);{int m0=moves;kid_add(foreign_obj);ms+=250;do_tick();assert(moves==m0&&c->svc.lock.state==TLK_DARK&&!holds_held());kid_remove(foreign_obj);}
 /* The focus root under a foreign child: closes (only the overlay itself on top is raised over). */
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);kid_remove(focus_root_obj);kid_add(focus_root_obj);kid_add(foreign_obj);ms+=250;do_tick();assert(c->svc.lock.state==TLK_DARK);kid_remove(foreign_obj);
 /* 23. The failure notice goes dark TLK_ENTRY_TIMEOUT_MS after it was lit or last touched, once (no relight while stock
  *     keeps the panel off), stays the state, and the next press shows it again; a press then dismisses it. */
 ms+=100;key(TIO_STOCK_KEY_CONFIRM);enter_pin(BAD);ms+=2000;do_tick();enter_pin(PIN);assert(c->svc.lock.state==TLK_NOTICE&&c->cover&&screen);
 ms+=100;do_tick();assert(c->svc.lock.lit&&!holds_held());
 screen=false;ms+=15000;do_tick();assert(screen&&c->cover);   /* inside its time: a stock turn-off is relit, as before */
 {int fo=force_off_calls,on=screen_on_calls;ms+=TLK_ENTRY_TIMEOUT_MS-15000;do_tick();
  assert(c->svc.lock.state==TLK_NOTICE&&c->svc.lock.notice_dark&&!c->cover&&!screen&&force_off_calls==fo+1&&!c->dark&&!c->locked);
  for(int i=0;i<40;i++){ms+=250;do_tick();}assert(screen_on_calls==on&&force_off_calls==fo+1&&!screen);   /* stays dark */
  assert(!lock_refuse_screen(1,1));}   /* unlocked: stock may light the panel */
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_NOTICE&&!c->svc.lock.notice_dark&&c->cover&&screen);   /* shown again */
 ms+=100;assert(key(TIO_STOCK_KEY_CONFIRM)==0&&c->svc.lock.state==TLK_UNLOCKED);do_tick();assert(!c->cover);
 puts("PASS lock_native: boot off/locked/damaged, key consume-and-drop with 0x3d/0x44 to stock, knob drain, PIN entry and notice, idle and fold locks via the screen gate, clock faults, phone ops and gates, anchor repair, reboot during a delay, factory reset clear, cover backstop, view opened after the cover layout, early start, stale key not an event, boot from the first LVGL-thread call, Pending until the first mounted read (late mount locked/Off, never mounted, phone while Pending, no re-entry), gates refuse with no lock in the first minute, factory reset with a failed bank, first-press grace on the PIN screen, the phone's Unlocked lights the panel, head motion (MOTION_ON sent fire-and-forget or refused, motion seen as use only while on), wake lock taken once per lit lock screen and released on every way out, cover raised over the focus-mode overlay only, failure notice dark after its untouched time and shown again at the next press");
}
