/* Glasses PIN lock: the stock bindings (docs/lock-design.md §5-§8). Everything that changes the lock state runs on the
 * LVGL/UI thread: the key and wheel read hooks, the 250 ms tick, the TLK: message (LauncherThreadMsgHandler), boot (the
 * first of those calls) and the factory-reset worker (an LVGL timer). Other threads (the screen gate under the screen
 * controller mutex, the assistant and microphone gates) only read bytes this file keeps current; the screen gate also
 * reads the PMU clock and the stock fold state and writes two of those bytes.
 * Fail-closed rule: a dark panel is the failure state; nothing here can stop the phone link or an OTA. */
#include "lock_service.h"
#include "lock_view.h"
#include "lock_anchor.h"
#include "../common-v1/knob_detent.h"
#include "../common-v1/tio_ui.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include <stddef.h>
#include <string.h>
extern void *tap_fs_fopen(const char *,const char *);
extern size_t tap_fs_fread(void *,size_t,size_t,void *),tap_fs_fwrite(const void *,size_t,size_t,void *);
extern int tap_fs_ferror(void *),tap_fs_feof(void *),tap_fs_fflush(void *),tap_fs_fileno(void *),tap_fs_fclose(void *);
extern int tap_fs_fsync(int),*tap_fs_errno(void),tap_fs_statfs(const char *,void *);
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
#include "lock_files.inc"
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void),tap_random(void);
extern int td_gettid(void);
extern int32_t tio_lv_obj_get_width(void *),tio_lv_obj_get_height(void *);
extern void *nav_monitors(void),*nav_input(void *),*nav_link(void *),*fm_system(void *),*fm_battery_monitor(void *);
extern int64_t fm_local_time(void *);
extern int fm_battery_level(void *);
extern void menu_text_align(void *,int,uint32_t);
extern unsigned tgr_ota_status(void *);
extern bool nav_bonded(void *),nav_folded(void *),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *),nav_force_off(void);
extern void nav_screen_on(bool),*tgr_indev_driver(void *),*stream_display_next(void *);
extern void *tio_lv_obj_create_ex(void *,uint32_t);
extern void tio_lv_obj_delete(void *),tio_lv_obj_set_size(void *,int,int),tio_lv_obj_add_flag(void *,uint32_t),tio_lv_obj_remove_flag(void *,uint32_t);
extern void tio_lv_obj_set_style_border_width(void *,int32_t,uint32_t),tio_lv_obj_set_style_radius(void *,int32_t,uint32_t);
extern void tio_lv_obj_set_style_bg_color(void *,uint32_t,uint32_t),tio_lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t),native_align(void *,int,int,int);
extern unsigned tio_lang_stored(void);
#include "../lock_stock.h"   /* pmu_rtc_epoch, kws_enable/disable, key_queue_flush, ots_topic_read, the gate prototypes */
/* Entry trampolines of the two patched stock read callbacks. */
extern void stock_key_read(void *,void *),stock_wheel_read(void *,void *);

/* TIO_LOCK_TRACE: emulator trace builds only (never a release); the two boot lines below are always logged. */
#ifdef TIO_LOCK_TRACE
#define TR(...) native_log(1,0,0,0,__VA_ARGS__)
#else
#define TR(...) ((void)0)
#endif
#define LOCK_MAGIC 0x544c4b31u   /* "TLK1" */
#define LOCK_TICK_MS 250u
#define KWS_REPEAT_MS 60000u
#define KEY_FACTORY_CONFIRM 0x3du   /* five presses + 3 s hold: always to stock */
#define KEY_REBOND 0x44u            /* the 5 s hold: always to stock (owner, 14:44) */
#define KEY_RELEASED 0x49u
/* A valid PMU reading is a UTC time from 2024 to 2099; a failed PMU read converts to year 63636 (far future). */
#define PMU_MIN 1704067200ll
#define PMU_MAX 4102444800ll

typedef struct {
 uint32_t magic;void *timer;
 TLKService svc;
 /* Bytes read from other threads. */
 volatile uint8_t dark;          /* the screen gate refuses "on" */
 volatile uint8_t locked;        /* the assistant and microphone gates refuse */
 volatile uint8_t lock_request;  /* set by the screen and wake gates when the idle or fold time has passed; applied by the tick */
 volatile uint32_t gate_fold_s;  /* PMU seconds the screen gate first saw the panel go off while folded */
 /* UI thread only. */
 void *cover;TLKView view;bool view_open;uint32_t view_ms;uint8_t lang;
 bool kws_off;uint32_t kws_ms;
 int32_t wheel_acc;uint32_t wheel_ms;
 bool was_folded;
 bool pending;      /* storage not mounted yet: the record is unknown, so dark and gated with no input (§7 boot) */
 uint32_t load_ms;  /* stream_tick of the last mount check */
 uint8_t tr_state;  /* the last state sync saw (trace builds) */
} LockCtl;
#define PENDING_UNTIL_MS 60000u   /* also the window in which the assistant and microphone gates refuse without a lock */
#define PENDING_EVERY_MS 1000u
#define NAND_DATA "/mnt/nand_data"
#define LFS_MAGIC 0x0a732923u     /* NuttX LITTLEFS_SUPER_MAGIC, statfs f_type */
static TLKLoad load_kind(const TLKService *s){return s->lock.damaged?TLK_LOAD_DAMAGED:s->stored.generation?TLK_LOAD_GOOD:TLK_LOAD_NONE;}

static uint32_t now_s(void){int64_t t=pmu_rtc_epoch();return t>=PMU_MIN&&t<PMU_MAX?(uint32_t)t:0;}

/* ---------------------------------------------------------------- display */
static void *slot(void *d,uint32_t off){void *p;memcpy(&p,(uint8_t *)d+off,sizeof p);return p;}
/* Only the top layer is hidden under the cover: it is a permanent display object, so the one that was hidden is the one
 * shown again. The active screen is left alone (stock may load or delete screens while the cover is up; a screen hidden
 * here and replaced would stay black after unlock); the opaque full-page cover on the sys layer hides it. */
static void layers_hidden(bool hidden){
 void *d=stream_display_next(NULL);if(!d)return;
 void *top=slot(d,TIO_STOCK_DISPLAY_TOP);if(!top)return;
 if(hidden)tio_lv_obj_add_flag(top,TIO_STOCK_OBJ_FLAG_HIDDEN);else tio_lv_obj_remove_flag(top,TIO_STOCK_OBJ_FLAG_HIDDEN);
}
static void cover_drop(LockCtl *c){
 if(c->view_open){tlv_close(&c->view);c->view_open=false;}
 if(c->cover){tio_lv_obj_delete(c->cover);c->cover=NULL;layers_hidden(false);}
}
/* The cover: one black object on the sys layer with the top layer hidden, and the lock view created on it. The view's
 * root takes the cover's size, which LVGL applies at its next layout pass, so the view opens on a later call (the next
 * key, wheel step or 250 ms tick). Returns 1 ready, 0 waiting for the layout, -1 failed (the caller keeps the panel dark). */
#define VIEW_WAIT_MS 2000u
static int cover_make(LockCtl *c){
 if(c->cover&&c->view_open)return 1;
 void *d=stream_display_next(NULL),*sys=d?slot(d,TIO_STOCK_DISPLAY_SYS):NULL;if(!sys){TR("[TurboLock] cover no sys d=%p",d);return -1;}
 if(!c->cover){
  void *o=tio_lv_obj_create_ex(sys,0);if(!o){TR("[TurboLock] cover create failed");return -1;}
  tio_lv_obj_set_size(o,TIO_PAGE_W,TIO_MENU_H);tio_lv_obj_set_style_bg_color(o,0,0);tio_lv_obj_set_style_bg_opa(o,255,0);
  tio_lv_obj_set_style_border_width(o,0,0);tio_lv_obj_set_style_radius(o,0,0);native_align(o,1,0,0);   /* no theme outline */
  c->cover=o;c->view_ms=stream_tick();c->lang=(uint8_t)tio_lang_stored();layers_hidden(true);   /* language read once per cover */
 }
 if(tio_lv_obj_get_width(c->cover)<TIO_PAGE_W||tio_lv_obj_get_height(c->cover)<TIO_MENU_H){
  if((uint32_t)(stream_tick()-c->view_ms)>VIEW_WAIT_MS){TR("[TurboLock] cover never laid out");cover_drop(c);return -1;}
  return 0;
 }
 TNWidgets w=tn_lvgl_widgets();if(!tlv_open(&c->view,&w,NULL,c->cover)){TR("[TurboLock] view open failed");cover_drop(c);return -1;}
 menu_text_align(c->view.labels[TLV_BATT],3,0);   /* battery right-aligned to the core edge, as on the launcher menu */
 c->view_open=true;return 1;
}
/* The cover must stay the last child of the sys layer, the one drawn on top. A child stock adds later (a call view, a
 * toast, the assistant view) or one it brings to the front would draw over the lock screen; the caller then closes the
 * lock screen and goes dark, and the next press opens it again on top. Unreadable counts as covered (fail closed). */
static bool cover_last(const LockCtl *c){
 void *d=stream_display_next(NULL),*sys=d?slot(d,TIO_STOCK_DISPLAY_SYS):NULL;if(!sys)return false;
 void *sa=slot(sys,TIO_STOCK_OBJ_SPEC_ATTR);if(!sa)return false;
 uint16_t n;memcpy(&n,(uint8_t *)sa+TIO_STOCK_SPEC_CHILD_CNT,sizeof n);
 void **children=slot(sa,TIO_STOCK_SPEC_CHILDREN);if(!n||!children)return false;
 void *last;memcpy(&last,&children[n-1u],sizeof last);return last==c->cover;
}
static void go_dark(LockCtl *c){c->dark=1;cover_drop(c);(void)nav_force_off();}

/* Brings the panel, the cover and the gates in line with the lock state. UI thread only. */
static void sync(LockCtl *c,uint32_t now_ms){
 TLK *t=&c->svc.lock;
 if(t->state!=c->tr_state){TR("[TurboLock] state %u->%u ms=%u dark=%u cover=%u",c->tr_state,t->state,now_ms,c->dark,c->cover!=NULL);c->tr_state=(uint8_t)t->state;}
 c->locked=tlk_locked(t)?1:0;
 if(c->locked)c->lock_request=0;   /* a gate's request is met; never carried over an unlock */
 if(t->state==TLK_DARK){if(!c->dark)go_dark(c);}
 else if(t->state==TLK_OFF||t->state==TLK_UNLOCKED){
  c->dark=0;cover_drop(c);
 }else{   /* a lock screen (PIN, wrong, waiting, use phone) or the failure notice */
  if(c->cover&&tlk_locked(t)&&!cover_last(c)){   /* something drawn over the lock screen: close it, dark */
   native_log(1,0,0,0,"[TurboLock] covered: lock screen closed state=%u ms=%u",t->state,now_ms);
   tlk_close_screen(t);go_dark(c);return;
  }
  int k=cover_make(c);
  if(k<0){t->state=tlk_locked(t)?TLK_DARK:t->state;go_dark(c);c->locked=tlk_locked(t)?1:0;return;}   /* backstop: dark */
  bool was=c->dark;c->dark=0;
  if(k>0){
   TLVScene s;tlv_snapshot(&s,t,now_s(),now_ms);
   if(t->state==TLK_ENTRY){   /* band T: time and battery from the same stock getters as the launcher menu */
    void *mon=nav_monitors(),*sys=mon?fm_system(mon):NULL,*bat=mon?fm_battery_monitor(mon):NULL;
    s.local=sys?fm_local_time(sys):0;s.battery=bat?fm_battery_level(bat):-1;
   }
   (void)tlv_draw(&c->view,&s,c->lang);
  }   /* else the black cover until the view opens */
  if(was||!focus_screen_on())nav_screen_on(true);
 }
 if(t->flush_input){t->flush_input=false;key_queue_flush();c->wheel_acc=0;}
 /* Wake word: off while locked and unfolded (stock turns it on at every return to running); back on at unlock. */
 if(c->locked&&!c->was_folded){if(!c->kws_off||(uint32_t)(now_ms-c->kws_ms)>=KWS_REPEAT_MS){kws_disable();c->kws_off=true;c->kws_ms=now_ms;}}
 else if(!c->locked&&c->kws_off){c->kws_off=false;if(!c->was_folded)kws_enable();}
}
static void tick(void *);
static LockCtl *any(void){LockCtl *c=lock_anchor_any();return c&&c->magic==LOCK_MAGIC?c:NULL;}
/* UI thread: the head node (two loads) first, then our node anywhere in the list, then the timer scan. */
static LockCtl *ui(void){
 LockCtl *c=any();if(c)return c;
 c=lock_anchor_find();if(c&&c->magic==LOCK_MAGIC)return c;
 c=lock_anchor_ui(tick);return c&&c->magic==LOCK_MAGIC?c:NULL;
}
/* Before the first write of a boot that read no generation (no file, or Off after the Pending cap), take the stored
 * generation if a record has appeared since, so the new record is written above it and wins at the next boot. */
static void stored_refresh(LockCtl *c){
 if(c->svc.stored.generation)return;TLKRecord r;TLRStored st;
 if(tlr_load(&tlr_io,&r,&st)==TLK_LOAD_GOOD&&st.generation)c->svc.stored=st;
}
static void persist(LockCtl *c){if(c->svc.lock.dirty)stored_refresh(c);(void)tlk_service_persist(&c->svc,&tlr_io);}

/* ---------------------------------------------------------------- boot record */
static bool folded_now(void){void *m=nav_monitors(),*i=m?nav_input(m):NULL;return i&&nav_folded(i);}
/* The fold edge (UI thread). Run by the tick and also at every launcher message (ours runs before stock's handler, and the
 * input monitor stores the hall state before it posts the hall message), at every key event and at every knob step, so
 * the fold lock is taken before stock handles the unfold or the first input after it. Returns the fold state. */
static bool fold_edge(LockCtl *c,uint32_t s){
 TLK *t=&c->svc.lock;bool folded=folded_now();
 if(folded&&!c->was_folded)tlk_fold(t,c->gate_fold_s?c->gate_fold_s:s);
 else if(!folded&&c->was_folded)tlk_unfold(t,s);
 else if(!folded&&c->gate_fold_s){tlk_fold(t,c->gate_fold_s);tlk_unfold(t,s);}   /* a fold only the gate saw (the tick slept through it) */
 if(!folded)c->gate_fold_s=0;
 c->was_folded=folded;
 return folded;
}
/* fold_edge outside the tick: a lock it takes is applied at once (dark before the caller goes on). */
static void fold_edge_now(LockCtl *c){
 if(c->pending)return;   /* the Pending settle applies the fold state itself */
 TLKState before=c->svc.lock.state;(void)fold_edge(c,now_s());
 if(c->svc.lock.state!=before){uint32_t ms=stream_tick();sync(c,ms);persist(c);}
}
/* /mnt/nand_data is mounted when statfs on it reports the littlefs type with a nonzero size. Before the mount the path
 * does not resolve to that filesystem, and a record read there cannot tell "no file" from "not mounted yet". */
static bool store_mounted(void){uint32_t w[16]={0};return !tap_fs_statfs(NAND_DATA,w)&&w[0]==LFS_MAGIC&&w[2]&&w[4];}
/* Ends the Pending state (once per boot; it is never entered again) with the service read just now. Leaving Pending
 * unlocked brings back the panel the Pending dark turned off; the wake word is left to stock (Pending turned it off,
 * stock turns it on at its next return to running), so a user who keeps it off does not get it switched on. */
static void adopt(LockCtl *c,const TLKService *n,bool mounted,bool folded){
 c->pending=false;c->svc=*n;c->svc.motion_supported=false;   /* milestone 3 */
 if(folded)tlk_fold(&c->svc.lock,now_s());
 native_log(1,0,0,0,"[TurboLock] settle mounted=%u load=%u state=%u ms=%u",mounted,load_kind(&c->svc),c->svc.lock.state,stream_tick());
 if(!tlk_locked(&c->svc.lock)){c->kws_off=false;if(!folded){c->dark=0;cover_drop(c);nav_screen_on(true);}}
}
/* A Pending check. Mounted: the read settles the boot by the start-up table. statfs can also fail on a mounted volume
 * (littlefs walks the whole volume to report its size), so the record is read anyway: a CRC-good record cannot come from
 * an unmounted path and settles at once. At the cap (final) a good record locks and anything else is Off: storage never
 * shown mounted within the first minute (the stated limit, docs/lock-design.md §7). */
static void pending_check(LockCtl *c,bool folded,bool final){
 bool mounted=store_mounted();TLKService n;tlk_service_boot(&n,&tlr_io);TLKLoad k=load_kind(&n);
 if(mounted||k==TLK_LOAD_GOOD)adopt(c,&n,mounted,folded);
 else if(final){tlk_boot(&n.lock,TLK_LOAD_NONE,NULL);n.stored=(TLRStored){0,1};adopt(c,&n,false,folded);}
}

/* ---------------------------------------------------------------- tick */
static void tick(void *timer){
 LockCtl *c;memcpy(&c,(uint8_t *)timer+TIO_STOCK_TIMER_USER,sizeof c);if(!c||c->magic!=LOCK_MAGIC)return;
 /* The cross-thread anchor must stay at the head of the interceptor list; if it was displaced, go dark while locked
  * (the gates on other threads cannot see the lock meanwhile) and put it back. */
 if(!lock_anchor_present(c)){TR("[TurboLock] anchor displaced locked=%u",c->locked);if(c->locked)go_dark(c);(void)lock_anchor_install(c);}
 TLK *t=&c->svc.lock;uint32_t ms=stream_tick(),s=now_s();
 bool folded=fold_edge(c,s);
 t->screen_on=focus_screen_on();
 if(c->pending){   /* storage not mounted at boot: check once a second; the first mounted read settles the boot */
  if(ms>=PENDING_UNTIL_MS)pending_check(c,folded,true);
  else if((uint32_t)(ms-c->load_ms)>=PENDING_EVERY_MS){c->load_ms=ms;pending_check(c,folded,false);}
  if(c->pending){sync(c,ms);return;}
 }
 if(c->lock_request){c->lock_request=0;if(!tlk_locked(t)&&t->state!=TLK_OFF)(void)tlk_phone_lock(t);}
 tlk_tick(t,s,ms);
 sync(c,ms);persist(c);
}

/* ---------------------------------------------------------------- boot */
/* The lock starts at the first of: the launcher's link-callback shim (before the first content frame), a launcher message,
 * a keypad or wheel read, a TLK: message. All run on the launcher's LVGL thread (emulator trace: one thread id), so the
 * timer, the cover and nav_force_off are called from the thread that owns them. ui() finds the state again on every
 * later call, so this runs once per boot. */
static LockCtl *lock_boot(void){
 LockCtl *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=LOCK_MAGIC;
 bool mounted=store_mounted();
 tlk_service_boot(&c->svc,&tlr_io);
 if(!mounted&&load_kind(&c->svc)!=TLK_LOAD_GOOD){   /* Pending: dark, no record (a good record is taken even if statfs failed) */
  c->pending=true;tlk_boot(&c->svc.lock,TLK_LOAD_DAMAGED,NULL);c->svc.lock.damaged=false;c->svc.stored=(TLRStored){0,1};
 }
 c->svc.motion_supported=false;   /* milestone 3 */
 c->load_ms=stream_tick();
 native_log(1,0,0,0,"[TurboLock] boot mounted=%u load=%u state=%u ms=%u",mounted,load_kind(&c->svc),c->svc.lock.state,c->load_ms);
 c->timer=stream_timer_create(tick,LOCK_TICK_MS,c);
 /* Without a tick the lock cannot run its screens; a locked boot still goes dark and the phone can unlock. */
 c->was_folded=folded_now();if(c->was_folded&&!c->pending)tlk_fold(&c->svc.lock,now_s());
 bool anchored=lock_anchor_install(c);TR("[TurboLock] boot anchor=%u timer=%p tid=%d",anchored,c->timer,td_gettid());
 if(!anchored&&!c->timer){c->magic=0;stream_free(c);return NULL;}   /* not findable again: retry next poll */
 sync(c,stream_tick());
 return c;
}
static LockCtl *ui_or_boot(void){LockCtl *c=ui();return c?c:lock_boot();}
/* The early start: the launcher's link-callback registration (stream_register_shim, about 1.3 s before the first content
 * frame) and every launcher message. Both are on the launcher's UI thread, the one that polls the keypad (trace builds
 * log the thread id at each entry to show it). Idempotent: after the first call it only finds the state again. */
void lock_boot_early(void){LockCtl *c=ui();if(c){fold_edge_now(c);return;}TR("[TurboLock] early tid=%d ms=%u",td_gettid(),stream_tick());(void)lock_boot();}

/* ---------------------------------------------------------------- input */
static TLKInput key_input(uint32_t key){return key==TIO_STOCK_KEY_CONFIRM?TLK_IN_PRESS:key==TIO_STOCK_KEY_BACK?TLK_IN_BACK:TLK_IN_OTHER;}
/* The keypad read callback (patched entry). Stock reads first, so the button hub always drains; while locked the key is
 * handed to the lock and blanked, so no interceptor, group or app sees it. */
void lock_hook_key_read(void *indev,void *data){
 LockCtl *c=ui_or_boot();
 if(!c||c->svc.lock.state==TLK_OFF){stock_key_read(indev,data);return;}   /* first branch: no lock, nothing touched */
 /* LVGL pre-fills data.key with the last key on every poll, and stock's read leaves it alone when the hub is empty, so
  * an unchanged key is not an event. Blank it before the read: still 0 afterwards means no event this poll; the
  * previous value is put back so LVGL sees exactly what stock would have left. */
 uint8_t *d=data;uint32_t prev=*(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY);
 *(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY)=0;
 stock_key_read(indev,data);
 uint32_t key=*(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY);
 if(!key){*(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY)=prev;return;}
 if(key==KEY_FACTORY_CONFIRM||key==KEY_REBOND)return;
 if(c->pending){*(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY)=0;d[TIO_STOCK_INDEV_DATA_STATE]=0;return;}   /* no record yet: nothing to enter */
 fold_edge_now(c);
 TLK *t=&c->svc.lock;uint32_t ms=stream_tick();t->screen_on=focus_screen_on();
 bool consumed;
 if(key==KEY_RELEASED)consumed=tlk_locked(t)||t->state==TLK_NOTICE;
 else consumed=tlk_input(t,key_input(key),0,now_s(),ms);
 TR("[TurboLock] key 0x%x state=%u consumed=%u tid=%d",key,t->state,consumed,td_gettid());
 if(consumed){*(uint32_t *)(d+TIO_STOCK_INDEV_DATA_KEY)=0;d[TIO_STOCK_INDEV_DATA_STATE]=0;}
 if(consumed||t->dirty||tlk_locked(t)||t->flush_input){sync(c,ms);persist(c);}
}
/* One record of the wheel topic: {u64 timestamp; i32 x; i32 y} (topic meta 'timestamp:%llu,x:%li,y:%li'). */
typedef struct {uint64_t ts;int32_t x,y;} WheelSample;
_Static_assert(sizeof(WheelSample)==16,"sensor_ots record");
/* Reads and discards everything queued on the wheel topic; returns the summed x. */
static int32_t wheel_drain(void *indev){
 uint8_t *ctx=tgr_indev_driver(indev);if(!ctx)return 0;int fd=*(int *)(ctx+TIO_STOCK_WHEEL_FD);
 WheelSample buf[8];int32_t sum=0;
 for(unsigned round=0;round<4;round++){
  int n=ots_topic_read(fd,buf,sizeof buf);if(n<(int)sizeof(WheelSample))break;
  for(int i=0;i<n/(int)sizeof(WheelSample);i++)sum+=buf[i].x;
 }
 *(int16_t *)(ctx+TIO_STOCK_ENCODER_STEP)=0;return sum;
}
/* The wheel read callback (patched entry). While a lock screen or the dark lock is up, stock is never called: the topic
 * is drained here, so neither the LVGL step nor the raw broadcast (launcher carousel, screen-off knob wake) runs and
 * nothing is left to replay at unlock. */
void lock_hook_wheel_read(void *indev,void *data){
 LockCtl *c=ui_or_boot();
 if(!c||c->svc.lock.state==TLK_OFF){stock_wheel_read(indev,data);return;}   /* first branch */
 TLK *t=&c->svc.lock;uint8_t *d=data;
 if(t->state==TLK_UNLOCKED)fold_edge_now(c);   /* before stock sees the step */
 if(t->state==TLK_UNLOCKED){
  stock_wheel_read(indev,data);
  if(*(int16_t *)(d+TIO_STOCK_INDEV_DATA_ENC_DIFF)){
   uint32_t ms=stream_tick();t->screen_on=focus_screen_on();
   if(tlk_input(t,TLK_IN_OTHER,0,now_s(),ms)){*(int16_t *)(d+TIO_STOCK_INDEV_DATA_ENC_DIFF)=0;sync(c,ms);}   /* idle passed: locked now */
  }
  return;
 }
 int32_t sum=wheel_drain(indev);*(int16_t *)(d+TIO_STOCK_INDEV_DATA_ENC_DIFF)=0;
 if(!sum||c->pending)return;
 TR("[TurboLock] wheel sum=%d state=%u",sum,t->state);
 uint32_t ms=stream_tick();if((uint32_t)(ms-c->wheel_ms)>250u)c->wheel_acc=0;c->wheel_ms=ms;c->wheel_acc+=sum;
 const int32_t detent=(int32_t)tio_knob_detent();
 uint8_t *ctx=tgr_indev_driver(indev);bool reverse=ctx&&ctx[TIO_STOCK_ENCODER_REVERSE];
 bool changed=false;
 while(c->wheel_acc>=detent||c->wheel_acc<=-detent){
  int sign=c->wheel_acc>0?1:-1;c->wheel_acc-=sign*detent;
  (void)tlk_input(t,TLK_IN_STEP,reverse?sign:-sign,now_s(),ms);changed=true;   /* stock's own direction rule */
 }
 if(changed)sync(c,ms);
}

/* ---------------------------------------------------------------- gates read from other threads */
/* No lock found (not started yet at boot, or the anchor displaced for one tick): refuse during the first minute of
 * uptime, the Pending window; after that a lock that never started must not keep the assistant off for good. */
/* Unlocked, but the fold delay has passed since a fold not yet seen by the UI thread (between stock's unfold and our next
 * fold edge), or the idle time has passed: the next UI-thread step locks. Read only (any thread). */
static bool fold_passed(const LockCtl *c,const TLK *t,uint32_t s){
 return t->folded?tlk_fold_due(t,s):(c->gate_fold_s&&!folded_now()&&(!s||s<c->gate_fold_s||s-c->gate_fold_s>=(uint32_t)t->rec.fold_min*60u));
}
bool lock_refuse_can_wakeup(void){
 LockCtl *c=any();if(!c)return stream_tick()<PENDING_UNTIL_MS;
 if(c->locked)return true;
 const TLK *t=&c->svc.lock;if(t->state!=TLK_UNLOCKED&&t->state!=TLK_NOTICE)return false;
 uint32_t s=now_s();
 if(fold_passed(c,t,s)||tlk_idle_due(t,s)){c->lock_request=1;return true;}
 return false;
}
bool lock_refuse_open_remote_audio(void){return lock_refuse_can_wakeup();}
bool lock_refuse_open_recorder(void){return lock_refuse_can_wakeup();}
/* screen_state_update(new_state, source), with the screen controller mutex held. It reads the lock's bytes, the PMU
 * clock and stock's fold state (MonitorManager getter, the input monitor's hall read, which logs), writes gate_fold_s and
 * lock_request, and calls no screen, nav or LVGL function. */
bool lock_refuse_screen(uint32_t state,uint32_t source){
 (void)source;LockCtl *c=any();if(!c)return false;
 const TLK *t=&c->svc.lock;
 if(state!=1){   /* going off: remember when the panel went off folded, for the fold delay */
  if(!c->gate_fold_s&&folded_now())c->gate_fold_s=now_s();
  return false;
 }
 if(c->dark){TR("[TurboLock] screen on refused (dark) src=%u",source);return true;}
 if(t->state!=TLK_UNLOCKED&&t->state!=TLK_NOTICE)return false;
 uint32_t s=now_s();
 if(tlk_idle_passed(t,s)||fold_passed(c,t,s)){c->lock_request=1;return true;}
 return false;
}
/* The stock factory-reset worker (patched entry, an LVGL timer callback; stock arms it only after its refusal checks
 * passed and the reset was accepted; stock always runs afterwards). Both banks are rewritten as the same "lock off"
 * record with a generation above the stored one, so whichever write lands wins over the old record; the running lock
 * is switched Off too, so a later write cannot bring the old record back if stock does not reboot. Best effort. */
void lock_on_factory_reset(void){
 TLKRecord old;TLRStored st={0};(void)tlr_load(&tlr_io,&old,&st);
 LockCtl *c=ui();if(c&&c->svc.stored.generation>st.generation)st.generation=c->svc.stored.generation;
 uint32_t gen=st.generation+1;
 TLKRecord r;tlk_record_default(&r);uint8_t raw[TLR_BYTES];tlr_encode(raw,&r,gen);
 for(unsigned b=0;b<2;b++)(void)tlr_file_write(NULL,b,raw,sizeof raw);
 if(c){tlk_boot(&c->svc.lock,TLK_LOAD_NONE,NULL);c->svc.stored.generation=gen;c->svc.stored.bank=1;c->pending=false;sync(c,stream_tick());}
}

/* ---------------------------------------------------------------- phone */
bool lock_native_locked(void){LockCtl *c=ui();return c&&c->locked;}   /* UI thread (remote gate) */
/* TLK: gate: no OTA running, bonded, connected. Not the fold state and not the top app. */
static bool tlk_allowed(void){
 void *m=nav_monitors(),*l=m?nav_link(m):NULL,*sys=m?fm_system(m):NULL;
 return l&&sys&&tgr_ota_status(sys)==0&&nav_bonded(l)&&nav_connection(TIO_STOCK_LINK_CONNECTED);
}
/* Returns true when the message was a TLK: command (answered or dropped). UI thread. */
bool lock_native_message(const uint8_t *data,unsigned bytes){
 uint8_t raw[32];if(!tlk_uncarrier(data,bytes,raw,false))return false;
 TLKCommand q;if(!tlk_decode(raw,sizeof raw,&q))return true;
 LockCtl *c=ui_or_boot();if(!c||c->magic!=LOCK_MAGIC)return true;
 if(c->pending){pending_check(c,folded_now(),false);if(c->pending)return true;}   /* no record yet: no answer, the phone asks again */
 stored_refresh(c);
 uint8_t salt[TLK_SALT_LEN];uint32_t a=tap_random(),b=tap_random();memcpy(salt,&a,4);memcpy(salt+4,&b,4);
 uint32_t ms=stream_tick();TLKReply r;
 c->svc.lock.screen_on=focus_screen_on();
 (void)tlk_service_command(&c->svc,&q,&r,ms,now_s(),q.op==TLK_OP_QUERY?tap_random():0,salt,tlk_allowed(),&tlr_io);
 sync(c,ms);
 uint8_t out[74];tlk_reply_encode(raw,&r);tlk_carrier(out,raw,true);(void)tdp_rnlink_send(TIO_STOCK_RNLINK_BUSINESS,out,sizeof out,NULL);
 return true;
}
