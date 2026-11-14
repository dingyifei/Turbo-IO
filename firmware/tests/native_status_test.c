/* Production diagnostics dispatch with only fixed 32-bit object/timer pointer
 * loads adapted for the host. Probes remain injected; target ABI is ARM-built.
 * The menu tail is reached through menu9.h's real accessors: the menu buffer is
 * TIO_TAIL_END bytes, aligned, and armed with m8_tail_arm (or left unarmed). */
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "../src/diagnostics-v1/diagnostics_service.h"
#include "../src/diagnostics-v1/knob_calibration.h"
static void *host_launcher(void),*host_ptr(void *,unsigned),*host_timer_user(void *);
#define TMG4_INPUT_SHA_BYTES {0x44}
#include "diagnostics_service_host.inc"
typedef struct {void (*callback)(void *);void *user;} HostTimer;
static HostTimer timer;
static TNNavSlot slot;
static uint8_t vm[32];
_Alignas(16) static uint8_t app[TIO_TAIL_END];
_Static_assert(TIO_STOCK_MANAGER_MENU+sizeof(void *)<=sizeof vm,"");
/* The launcher object (named launcher_object: the dispatcher has a launcher() function): its view manager pointer (vm) sits at TIO_STOCK_LAUNCHER_MANAGER. */
static uint8_t launcher_object[TIO_STOCK_LAUNCHER_MANAGER+sizeof(void *)];
static unsigned allocations,frees,probes,statfs_calls,ensures,emits,enqueues;
static bool connected=true,home=true,idle=true,runtime_allowed=true,fail_heap,fail_timer,bad_nand;
static const char *other_app; /* the top app when home is false; NULL means a stock prompter page */
static int tid=7;static uint32_t now_ms=100,probe_delay;
static TKState knob;
static TDSample last;
static void *host_launcher(void){return launcher_object;}
static void *host_ptr(void *p,unsigned offset){void *out=NULL;if(p)memcpy(&out,(uint8_t *)p+offset,sizeof out);return out;}
static void *host_timer_user(void *p){return ((HostTimer *)p)->user;}
static void set_app(void *p){memcpy(vm+TIO_STOCK_MANAGER_MENU,&p,sizeof p);}
void *stream_memalign(size_t align,size_t n){assert(align==8&&n<=4096);allocations++;return fail_heap?NULL:malloc(n);}
void stream_free(void *p){frees++;free(p);}
void *stream_timer_create(void (*cb)(void *),uint32_t ms,void *user){assert(ms==1000);if(fail_timer)return NULL;assert(!timer.user);timer=(HostTimer){cb,user};return &timer;}
void stream_timer_delete(void *p){assert(p==&timer);timer=(HostTimer){0};}
void *nav_monitors(void){return vm;}
void *nav_link(void *p){return p;}
bool nav_bonded(void *p){(void)p;return connected;}
int nav_connection(unsigned n){assert(n==0x80);return connected?1:0;}
bool nav_business_idle(void){return idle;}
int td_gettid(void){return tid;}
uint32_t stream_tick(void){return now_ms;}
const char *nav_top_app(void){return home?"com.rayneo.liteos.launcher":other_app?other_app:"com.rayneo.liteos.prompter";}
void *nav_ensure_menu(void *p){assert(p==vm);ensures++;set_app(app);return app;}
void td_stock_light(void *p,TDDiagnostics *d){TDLightOwner *owner=p;assert(owner&&owner->owner_tid==tid);probes++;now_ms+=probe_delay;td_metric(d,TD_LV_TOTAL,0,false);td_metric(d,TD_LV_USED,1024,true);td_metric(d,TD_LV_PEAK,2048,true);}
int tap_fs_statfs(const char *path,void *out){assert(!strcmp(path,"/mnt/nand_data"));statfs_calls++;uint32_t *s=out;s[2]=131072;s[4]=100;s[6]=80;s[8]=70;if(bad_nand)s[9]=1;return 0;}
bool tgr_runtime_allowed(void){return runtime_allowed;}
unsigned tgr_knob_command(void *p,const TDCommand *q,uint32_t now){assert(p==app);return q->op==TDQ_KNOB_START?tk_start(&knob,q->session,q->sequence,q->lease_ms,now,true):tk_stop(&knob,q->session,q->sequence,now,true);}
void tgr_runtime_snapshot(TDSample *s){s->caps=TD_CAPS_TMG9;s->detent=TK_DETENT_DEFAULT;tk_poll(&knob,now_ms,runtime_allowed);if(knob.window){s->extension_valid|=TD_EXT_CALIBRATION;s->calibration_state=knob.state;s->calibration_window=knob.window;s->calibration_elapsed=knob.elapsed;s->calibration_samples=knob.samples;s->calibration_net=knob.net;s->calibration_absolute=knob.absolute;s->calibration_sequence=knob.sequence;}}
static unsigned nibble(uint8_t c){assert((c>='0'&&c<='9')||(c>='a'&&c<='f'));return c<='9'?c-'0':c-'a'+10;}
int tdp_rnlink_send(unsigned business,const uint8_t *p,unsigned n,void *ctx){assert(business==15&&n==571&&!ctx&&!memcmp(p,(uint8_t[]){8,1,16,6,26,0xb4,4},7));uint8_t raw[256];for(unsigned i=0;i<256;i++)raw[i]=(uint8_t)(16*nibble(p[56+2*i])+nibble(p[57+2*i]));assert(td_decode(raw,sizeof raw,&last));emits++;return 0;}
static int enqueue(unsigned channel,const TIONativeMessage *m){assert(channel==1&&m->id==TD_MESSAGE&&m->bytes==24);enqueues++;return 0;}
static void release_refused(void *p){(void)p;abort();} /* a dispatcher must refuse a message carrying it, never call it */
static void send(TDCommand q){uint8_t raw[24];assert(td_command_encode(q,raw,24));TIONativeMessage m={.id=TD_MESSAGE,.data=raw,.bytes=24};td_message_dispatch(&m);}
static void reset(void){if(slot.diagnostics)td_slot_destroy(&slot);timer=(HostTimer){0};slot=(TNNavSlot){0};memset(vm,0,sizeof vm);{void *v=vm;memset(launcher_object,0,sizeof launcher_object);memcpy(launcher_object+TIO_STOCK_LAUNCHER_MANAGER,&v,sizeof v);}knob=(TKState){0};allocations=frees=probes=statfs_calls=ensures=emits=enqueues=0;connected=home=idle=runtime_allowed=true;fail_heap=fail_timer=bad_nand=false;other_app=NULL;memset(app,0,sizeof app);m8_tail_arm(app);m8_tail(app)->navigation=&slot;tid=7;now_ms=100;probe_delay=0;}
int main(void){
 reset();home=false;send((TDCommand){TDQ_STATUS,91,1,0});assert(last.calibration_result==TK_OK&&probes==1&&statfs_calls==1&&ensures==0);

 reset();assert(!td_message_is_ours(NULL)&&allocations==0&&statfs_calls==0);send((TDCommand){TDQ_STATUS,1,1,0});assert(emits==1&&last.kind==TD_STATUS&&last.session==1&&last.sequence==1&&last.build_sha[0]==0x44&&last.extension_valid==TD_EXT_NAND&&last.nand_available==9175040&&last.values[TD_LV_USED]==1024&&!(last.valid&(1u<<TD_SYS_FREE)));assert(ensures==0&&!timer.user&&allocations==1&&frees==1&&statfs_calls==1);
 reset();idle=false;send((TDCommand){TDQ_STATUS,92,1,0});assert(last.calibration_result==TK_OK&&probes==1&&statfs_calls==1&&ensures==0);
 for(unsigned gate=0;gate<2;gate++){reset();if(gate==0)runtime_allowed=false;if(gate==1)tid=-1;send((TDCommand){TDQ_STATUS,2,1,0});assert(emits==1&&last.calibration_result==TK_BLOCKED&&probes==0&&statfs_calls==0&&ensures==0&&allocations==0);}
 for(unsigned gate=0;gate<2;gate++){reset();set_app(app);if(gate==0)home=false;else idle=false;send((TDCommand){TDQ_KNOB_START,93,1,30000});assert(last.calibration_result==TK_BLOCKED&&probes==0&&statfs_calls==0);}
 reset();connected=false;send((TDCommand){TDQ_STATUS,3,1,0});assert(emits==0&&statfs_calls==0);
 reset();fail_heap=true;send((TDCommand){TDQ_STATUS,4,1,0});assert(last.calibration_result==TK_UNAVAILABLE&&last.valid==0&&ensures==0&&!timer.user);
 reset();set_app(app);send((TDCommand){TDQ_KNOB_START,5,1,30000});assert(last.kind==TD_CALIBRATION&&last.calibration_state==TK_ACTIVE&&statfs_calls==0&&probes==0&&allocations==0);tk_observe(&knob,4800,now_ms+1000,true,false);now_ms+=2000;send((TDCommand){TDQ_KNOB_STOP,5,2,0});assert(last.calibration_state==TK_FINISHED&&last.calibration_net==4800&&last.sequence==2&&statfs_calls==0);
 reset();send((TDCommand){TDQ_START,6,1,600000});assert(ensures==1&&slot.diagnostics&&timer.user&&last.kind==TD_SAMPLE&&statfs_calls==1&&probes==1);now_ms+=1000;timer.callback(&timer);assert(statfs_calls==1&&probes==2);
 unsigned before=probes;tid=8;now_ms+=1000;timer.callback(&timer);assert(probes==before&&statfs_calls==1);send((TDCommand){TDQ_STATUS,7,1,0});assert(last.kind==TD_STATUS&&last.calibration_result==TK_BLOCKED&&probes==before&&statfs_calls==1);tid=7;
 bad_nand=true;send((TDCommand){TDQ_STATUS,8,1,0});assert(!(last.extension_valid&TD_EXT_NAND));now_ms+=1000;timer.callback(&timer);assert(!(last.extension_valid&TD_EXT_NAND)); // failed explicit refresh invalidates the session cache
 bad_nand=false;send((TDCommand){TDQ_STATUS,18,1,0});assert(last.extension_valid&TD_EXT_NAND);now_ms+=1000;timer.callback(&timer);assert((last.extension_valid&TD_EXT_NAND)&&statfs_calls==3);
 send((TDCommand){TDQ_STOP,6,2,0});assert(!slot.diagnostics&&!timer.user);
 reset();fail_timer=true;send((TDCommand){TDQ_START,9,1,600000});assert(!slot.diagnostics&&!timer.user&&allocations==1&&frees==1);
 reset();probe_delay=11;send((TDCommand){TDQ_START,19,1,600000});assert(last.kind==TD_SAMPLE&&last.flags==1&&!slot.diagnostics&&!timer.user);
 reset();uint8_t raw[24];assert(td_command_encode((TDCommand){TDQ_STATUS,10,1,0},raw,24));TIONativeFile f={.data=raw,.declared=24,.received=24,.complete=1};strcpy(f.filename,"turbo-diagnostics.tdg");assert(td_file_receive(&f,enqueue)==TIO_OK&&enqueues==1&&statfs_calls==0);f.received--;assert(td_file_receive(&f,enqueue)==TIO_BAD_SIZE&&enqueues==1);f.received++;strcpy(f.filename,"turbo-diagnostics.tdg-extra");assert(td_file_receive(&f,enqueue)==TIO_FOREIGN&&enqueues==1);
 // An unarmed menu (failed size check or overwritten canary, with a stale slot pointer left in the tail): a start
 // request is discarded with no reply, no slot, no timer and no allocation; a status query is still answered, since
 // status never depends on the menu (the first case above answers one with no launcher on top).
 reset();set_app(app);m8_tail_at(app)->canary^=1u;assert(!m8_tail(app));send((TDCommand){TDQ_START,20,1,600000});assert(emits==0&&!slot.diagnostics&&!timer.user&&allocations==0&&ensures==0&&probes==0&&statfs_calls==0);
 send((TDCommand){TDQ_STATUS,21,1,0});assert(emits==1&&last.kind==TD_STATUS&&last.session==21&&!slot.diagnostics&&!timer.user);
 // An unarmed menu whose stale slot still holds a live session (started by tid 7 while the menu was armed): the owner
 // gate of a status query must not see that session, so tid 8 is answered TK_OK. A tail read that skipped the canary
 // would find tid 7's session and answer TK_BLOCKED. reset() then discards the session through the slot.
 reset();send((TDCommand){TDQ_START,24,1,600000});assert(slot.diagnostics&&timer.user);m8_tail_at(app)->canary^=1u;assert(!m8_tail(app));tid=8;unsigned replies=emits;send((TDCommand){TDQ_STATUS,25,1,0});assert(emits==replies+1&&last.kind==TD_STATUS&&last.session==25&&last.calibration_result==TK_OK);tid=7;
 // Malformed module messages: a set release word, a nonzero reserved word or a set context is refused before any
 // probe, statfs or reply; the same message with all three clear is answered.
 for(unsigned bad=0;bad<3;bad++){reset();uint8_t q[24];assert(td_command_encode((TDCommand){TDQ_STATUS,26,1,0},q,24));TIONativeMessage m={.id=TD_MESSAGE,.data=q,.bytes=24,.release=NULL};if(bad==0)m.release=release_refused;else if(bad==1)m.reserved=1;else m.context=q;td_message_dispatch(&m);assert(emits==0&&probes==0&&statfs_calls==0&&allocations==0);m.release=NULL;m.reserved=0;m.context=NULL;td_message_dispatch(&m);assert(emits==1&&last.session==26&&probes==1&&statfs_calls==1);}
 // Stock Navigation on top: an open request is discarded and creates nothing, and a running session closes on its own tick.
 reset();set_app(app);home=false;other_app="com.rayneo.liteos.navigation";send((TDCommand){TDQ_START,22,1,600000});assert(emits==0&&!slot.diagnostics&&!timer.user&&allocations==0&&ensures==0);
 reset();send((TDCommand){TDQ_START,23,1,600000});assert(slot.diagnostics&&timer.user);unsigned samples=emits;home=false;other_app="com.rayneo.liteos.navigation";now_ms+=1000;timer.callback(&timer);assert(!slot.diagnostics&&!timer.user&&emits==samples&&frees==allocations);
 reset();puts("PASS native status: exact carrier, request-only statfs/probes, gate/owner failures, no status menu/timer creation, calibration and periodic-kind/cache isolation");return 0;
}
