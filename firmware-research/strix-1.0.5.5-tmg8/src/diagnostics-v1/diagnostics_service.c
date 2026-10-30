#include "diagnostics_service.h"
#include "command.h"
#include "native_light.h"
#include "runtime_native.h"
#include "../navigation-runtime-v1/menu9.h"
#include <string.h>
#define TD_MESSAGE 0x54444731u
#ifndef TMG4_INPUT_SHA_BYTES
#define TMG4_INPUT_SHA_BYTES {0}
#endif
static const uint8_t build_sha[32]=TMG4_INPUT_SHA_BYTES;
typedef struct {TDDiagnostics d;TDLightOwner owner;TNNavSlot *slot;void *timer;uint32_t command_seq;uint64_t nand_total,nand_available;bool nand_valid;} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*nav_monitors(void),*nav_link(void *);
extern uint32_t stream_tick(void);
extern bool nav_bonded(void *),nav_business_idle(void);
extern int nav_connection(unsigned),td_gettid(void),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *),tap_fs_statfs(const char *,void *);
extern void *nav_ensure_menu(void *);
extern const char *nav_top_app(void);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19971594,0x3c);}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool launcher(void){const char *s=nav_top_app();const char *n="com.rayneo.liteos.launcher";if(!s)return false;for(unsigned i=0;i<32;i++){if(s[i]!=n[i])return false;if(!n[i])return true;}return false;}
static void emit(const TDSample *sample){
 uint8_t raw[TD_WIRE_BYTES],out[640];if(!td_encode(sample,raw,sizeof raw))return;
 static const char prefix[]="{\"cmd\":\"turbo_diagnostics_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 enum{len=sizeof prefix-1+2*TD_WIRE_BYTES+sizeof suffix-1};_Static_assert(len==564&&len+7==571&&len+7<sizeof out,"bounded TMG4 reply");
 unsigned pos=0;out[pos++]=8;out[pos++]=1;out[pos++]=16;out[pos++]=6;out[pos++]=26;out[pos++]=(len&127)|128;out[pos++]=len>>7;
 memcpy(out+pos,prefix,sizeof prefix-1);pos+=sizeof prefix-1;for(unsigned i=0;i<TD_WIRE_BYTES;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}memcpy(out+pos,suffix,sizeof suffix-1);pos+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,pos,NULL);
}
static uint32_t clock_ms(void *unused){(void)unused;return stream_tick();}
static bool nand(uint64_t *total,uint64_t *available){uint32_t words[16]={0};return !tap_fs_statfs("/mnt/nand_data",words)&&td_nand_metrics(words,sizeof words,total,available);}
static void enrich(TDSample *s,const Control *c){
 memcpy(s->build_sha,build_sha,32);tgr_runtime_snapshot(s);if(c&&c->nand_valid){s->extension_valid|=TD_EXT_NAND;s->nand_total=c->nand_total;s->nand_available=c->nand_available;}
}
static void discard(Control *c){if(!c)return;if(c->slot)c->slot->diagnostics=NULL;if(c->timer)stream_timer_delete(c->timer);stream_free(c);}
static void tick(void *timer){
 Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;if(td_gettid()!=c->owner.owner_tid)return;
 uint32_t now=stream_tick();if(!paired()||!launcher()||!nav_business_idle()||!td_active(&c->d,now)){discard(c);return;}
 TDSample s;if(td_sample(&c->d,now,true,td_stock_light,clock_ms,&c->owner,&s)){enrich(&s,c);emit(&s);}if(!c->d.enabled)discard(c);
}
void td_slot_destroy(TNNavSlot *slot){if(slot&&slot->diagnostics)discard(slot->diagnostics);}
TIOImageResult td_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){
 static const char name[]="turbo-diagnostics.tdg";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;TDCommand q;if(f->complete!=1||f->received!=f->declared||!td_command_decode(f->data,f->received,&q))return TIO_BAD_SIZE;
 if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TD_MESSAGE,.data=f->data,.bytes=f->received};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool td_message_is_ours(const TIONativeMessage *m){return m&&m->id==TD_MESSAGE;}
static void reply_query(void *app,Control *c,TDCommand q,bool gate){
 TDSample s;memset(&s,0,sizeof s);s.build=TD_BUILD_TMG6;s.session=q.session;s.sequence=q.sequence;s.tick_ms=stream_tick();s.kind=q.op==TDQ_STATUS?TD_STATUS:TD_CALIBRATION;s.caps=TD_CAPS_TMG8;s.detent=TK_DETENT_RAW;s.calibration_result=gate?TK_OK:TK_BLOCKED;
 if(gate&&q.op==TDQ_STATUS){
  if(c){c->nand_valid=false;c->nand_total=c->nand_available=0;}
  /* One-shot RAM scratch is fixed-size heap state, not a new timer/controller. */
  TDDiagnostics *d=stream_memalign(8,sizeof *d);if(!d)s.calibration_result=TK_UNAVAILABLE;else{
   td_init(d,TD_BUILD_TMG6);TDLightOwner owner={td_gettid()};uint32_t began=stream_tick();td_stock_light(&owner,d);s.probe_ms=stream_tick()-began;s.valid=d->valid;memcpy(s.values,d->values,sizeof s.values);stream_free(d);if(s.probe_ms>10)s.flags=1;
  }
  uint64_t total,available;if(nand(&total,&available)){s.extension_valid|=TD_EXT_NAND;s.nand_total=total;s.nand_available=available;if(c){c->nand_total=total;c->nand_available=available;c->nand_valid=true;}}
 }else if(gate)s.calibration_result=(uint8_t)tgr_knob_command(app,&q,stream_tick());
 enrich(&s,NULL);emit(&s);
}
void td_message_dispatch(const TIONativeMessage *m){
 TDCommand q;if(!td_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!td_command_decode(m->data,m->bytes,&q)||!paired())return;
 bool home=launcher();void *vm=home?manager():NULL,*app=ptr(vm,0x10);TNNavSlot *s=app?((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation:NULL;Control *c=s?s->diagnostics:NULL;
 if(q.op>=TDQ_STATUS){int tid=td_gettid();bool gate=tgr_runtime_allowed()&&tid>=0&&(!c||c->owner.owner_tid==tid)&&(q.op==TDQ_STATUS||(home&&nav_business_idle()));reply_query(app,c,q,gate);return;}
 if(!home||!vm)return;if(!app&&q.op==TDQ_START&&nav_business_idle())app=nav_ensure_menu(vm);
 s=app?((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation:NULL;if(!s)return;c=s->diagnostics;
 if(q.op==TDQ_STOP){if(c&&c->d.session==q.session&&q.sequence>c->command_seq)discard(c);return;}if(c)return;
 if(!nav_business_idle())return;int tid=td_gettid();if(tid<0)return;c=stream_memalign(8,sizeof *c);if(!c)return;memset(c,0,sizeof *c);c->slot=s;c->owner.owner_tid=tid;c->command_seq=q.sequence;
 td_init(&c->d,TD_BUILD_TMG6);if(!td_start(&c->d,q.session,stream_tick(),q.lease_ms)){stream_free(c);return;}if(tgr_runtime_allowed())c->nand_valid=nand(&c->nand_total,&c->nand_available);
 td_allocation(&c->d,stream_tick(),sizeof *c,true);c->timer=stream_timer_create(tick,1000,c);if(!c->timer){stream_free(c);return;}s->diagnostics=c;tick(c->timer);
}
