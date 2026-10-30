/* Executes production controller/file/apply bodies. The runner adapts only
 * the 32-bit LVGL timer field accesses and event-size assert for a 64-bit host.
 * ARM compilation and pinned stock ABI tests separately enforce target layout. */
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
static void (*host_timer_callback(void *))(void *);
static void *host_timer_user(void *);
#include "remote_native_host.inc"
typedef struct {void (*callback)(void *);void *user;} HostTimer;
static HostTimer timer,decoy;
static unsigned allocations,frees,reads,writes,snaps,nexts;
static bool fail_alloc,fail_timer,cycle,blocked,render_idle=true,awake=true,detail_open;
static uint32_t now_ms;
static uint8_t app[256],reply_wire[74],encoder[16];
static unsigned raw_callbacks,simulated_steps;
static unsigned snap_count[4],snap_selected[4];
typedef struct {uint8_t bytes[40];int len;size_t pos;bool writing;} File;
static File files[3][2];static int file_error,io_fail;static size_t chunk;
enum {FAIL_OPEN=1,FAIL_READ,FAIL_READ_ZERO,FAIL_ERROR,FAIL_CLOSE,FAIL_WRITE,FAIL_WRITE_ZERO,FAIL_FLUSH,FAIL_FILENO,FAIL_SYNC,FAIL_READ_BIG,FAIL_WRITE_BIG};
static void (*host_timer_callback(void *p))(void *){return ((HostTimer *)p)->callback;}
static void *host_timer_user(void *p){return ((HostTimer *)p)->user;}
void *stream_memalign(size_t alignment,size_t n){(void)alignment;allocations++;return fail_alloc?NULL:malloc(n);}
void stream_free(void *p){frees++;free(p);}
void *stream_timer_next(void *previous){nexts++;if(cycle)return &decoy;return !previous&&timer.user?&timer:NULL;}
void *stream_timer_create(void (*cb)(void *),uint32_t period,void *user){assert(period==1000);if(fail_timer)return NULL;assert(!timer.user);timer=(HostTimer){cb,user};return &timer;}
uint32_t stream_tick(void){return now_ms;}
uint32_t tap_random(void){return 77;}
void *nav_monitors(void){return app;}
void *nav_input(void *p){return p;}
void *nav_link(void *p){return p;}
void *fm_system(void *p){return p;}
unsigned tgr_ota_status(void *p){(void)p;return blocked?1:0;}
bool nav_bonded(void *p){return p!=NULL;}
bool nav_folded(void *p){(void)p;return false;}
bool focus_screen_on(void){return awake;}
bool fm_menu_plain(void *p){return p==app&&awake&&!detail_open;}
int nav_connection(unsigned n){assert(n==0x80);return 1;}
const char *nav_top_app(void){return "com.rayneo.liteos.launcher";}
void nav_screen_on(bool b){(void)b;}
void native_report_activity(void){}
void *tgr_indev_next(void *p){return p?NULL:encoder;}
void *tgr_indev_group(void *p){return p;}
void *tgr_indev_driver(void *p){return p;}
unsigned tgr_indev_type(void *p){assert(p==encoder);return 4;}
bool tgr_intercept(void *p){(void)p;return true;}
unsigned tgr_group_send(void *p,uint32_t key){(void)p;(void)key;return 0;}
void tgr_raw_wheel(const void *p){int32_t delta;memcpy(&delta,p,sizeof delta);raw_callbacks++;assert(find()->knob.state==TK_CANCELED&&find()->synthetic_depth);tgr_knob_observe(app,delta,now_ms);}
void tgr_sim_wheel(int delta){assert(delta==1||delta==-1);simulated_steps++;}
void fm_language_changed(void){}
void fm_relayout(unsigned rows){assert(rows>=1&&rows<=3);}
void fm_sync(void *p){if(!fm_tiles_busy()&&render_idle&&awake&&!detail_open)(void)fm_tiles_apply(p);}
void native_snap(void *p){assert(p==app);if(snaps<4){snap_count[snaps]=*(uint32_t *)(app+0xa0);snap_selected[snaps]=*(uint32_t *)(app+0x88);}snaps++;fm_sync(p);}
int tdp_rnlink_send(unsigned business,const uint8_t *p,unsigned n,void *ctx){assert(business==15&&n==74&&!ctx);memcpy(reply_wire,p,n);return 0;}
void *tap_fs_fopen(const char *path,const char *mode){
 if(io_fail==FAIL_OPEN){file_error=5;return NULL;}unsigned family=strstr(path,"turbo_tiles_")?1:strstr(path,"turbo_lang_")?2:0;size_t n=strlen(path);unsigned bank=(unsigned)(path[n-5]-'0');assert(bank<2);File *f=&files[family][bank];f->writing=mode[0]=='w';f->pos=0;
 if(f->writing){writes++;f->len=0;}else{reads++;if(f->len<0){file_error=2;return NULL;}}return f;
}
size_t tap_fs_fread(void *out,size_t size,size_t n,void *handle){File *f=handle;assert(size==1&&!f->writing);if(io_fail==FAIL_READ||io_fail==FAIL_READ_ZERO)return 0;if(io_fail==FAIL_READ_BIG)return n+1;size_t left=(size_t)f->len-f->pos;if(n>left)n=left;if(chunk&&n>chunk)n=chunk;memcpy(out,f->bytes+f->pos,n);f->pos+=n;return n;}
size_t tap_fs_fwrite(const void *in,size_t size,size_t n,void *handle){File *f=handle;assert(size==1&&f->writing);if(io_fail==FAIL_WRITE||io_fail==FAIL_WRITE_ZERO)return 0;if(io_fail==FAIL_WRITE_BIG)return n+1;if(chunk&&n>chunk)n=chunk;assert(f->pos+n<=40);memcpy(f->bytes+f->pos,in,n);f->pos+=n;f->len=(int)f->pos;return n;}
int tap_fs_ferror(void *p){(void)p;return io_fail==FAIL_ERROR||io_fail==FAIL_READ||io_fail==FAIL_WRITE;}
int tap_fs_feof(void *p){File *f=p;return io_fail==FAIL_READ_ZERO?0:f->pos==(size_t)f->len;}
int tap_fs_fflush(void *p){(void)p;return io_fail==FAIL_FLUSH?-1:0;}
int tap_fs_fileno(void *p){(void)p;return io_fail==FAIL_FILENO?-1:5;}
int tap_fs_fsync(int fd){assert(fd==5);return io_fail==FAIL_SYNC?-1:0;}
int tap_fs_fclose(void *p){(void)p;return io_fail==FAIL_CLOSE?-1:0;}
int *tap_fs_errno(void){return &file_error;}
static void reset(void){if(timer.user)free(timer.user);timer=(HostTimer){0};memset(app,0,sizeof app);*(uint32_t *)(app+0xa0)=13;for(unsigned a=0;a<3;a++)for(unsigned b=0;b<2;b++)files[a][b]=(File){.len=-1};allocations=frees=reads=writes=snaps=nexts=raw_callbacks=simulated_steps=0;memset(encoder,0,sizeof encoder);fail_alloc=fail_timer=cycle=blocked=detail_open=false;render_idle=awake=true;io_fail=0;chunk=0;now_ms=100;}
static TTReply request(TTCommand q){uint8_t raw[32],wire[74];tt_encode(raw,&q);tt_carrier(wire,raw,false);TIONativeMessage m={.id=1,.bytes=74,.data=wire};memset(reply_wire,0,74);tgr_native_message(&m);TTReply r;assert(tt_uncarrier(reply_wire,74,raw,true)&&tt_reply_decode(raw,32,&r));return r;}
static TLGReply language_request(TLGCommand q){uint8_t raw[32],wire[74];tlg_encode(raw,&q);tlg_carrier(wire,raw,false);TIONativeMessage m={.id=1,.bytes=74,.data=wire};memset(reply_wire,0,74);tgr_native_message(&m);TLGReply r;assert(tlg_uncarrier(reply_wire,74,raw,true)&&tlg_reply_decode(raw,32,&r));return r;}
int main(void){
 reset();tgr_knob_cancel(app,now_ms);assert(allocations==0&&reads==0);TTVisible map;fm_tile_snapshot(&map);assert(map.count==13&&reads==0&&allocations==0);assert(control()&&reads==0&&allocations==1);timer.callback(&timer);assert(reads==0);TTReply r=request((TTCommand){.op=TT_QUERY,.request=1,.client=2});assert(r.result==TT_UNAVAILABLE&&reads==0&&writes==0);
 TLGReply lr=language_request((TLGCommand){10,TLG_SET,TLG_ZH});assert(lr.result==TLG_UNAVAILABLE&&lr.source==0&&reads==0&&writes==0&&tio_lang()==TLG_EN);
 assert(fm_menu_rows()==3&&reads==6);unsigned before=reads;assert(fm_menu_rows()==3&&reads==before);*(uint32_t *)(app+0x88)=12;assert(fm_tiles_apply(app)&&snaps==2&&snap_count[0]==13&&snap_count[1]==13);assert(!fm_tiles_apply(app));
 r=request((TTCommand){.op=TT_QUERY,.request=2,.client=2});assert(r.result==TT_OK&&r.token==77&&reads==before+2);snaps=0;detail_open=true;
 r=request((TTCommand){.op=TT_SET,.request=3,.client=2,.token=r.token,.generation=r.generation,.rank=719,.hide=0xf80});assert(r.result==TT_OK&&writes==1&&fm_tile_count()==13&&snaps==0);detail_open=false;render_idle=false;fm_sync(app);assert(fm_tile_count()==13);render_idle=true;awake=false;fm_sync(app);assert(fm_tile_count()==13);awake=true;fm_sync(app);assert(fm_tile_count()==8&&fm_tile_id(7)==12&&fm_tile_rank(12)==7&&*(uint32_t *)(app+0xa0)==8&&*(uint32_t *)(app+0x88)==7&&snaps==2&&snap_count[0]==13&&snap_count[1]==8);
 fm_tiles_forget(app);assert(fm_tile_count()==13);assert(fm_tiles_apply(app)&&fm_tile_count()==8);before=reads;fm_tile_snapshot(&map);assert(reads==before&&map.count==8);
 blocked=true;before=reads;r=request((TTCommand){.op=TT_QUERY,.request=4,.client=2});assert(r.result==TT_BLOCKED&&reads==before);blocked=false;
 // Existing file adapter handles progress and every durability failure.
 before=reads;unsigned allocated=allocations;TDCommand lifecycle={TDQ_KNOB_START,100,1,30000};
 assert(tgr_knob_command(app,&lifecycle,now_ms)==TK_OK);tgr_knob_observe(app,600,now_ms);
 tgr_knob_cancel(app+4,now_ms);assert(find()->knob.state==TK_ACTIVE);
 tgr_knob_cancel(app,now_ms);assert(find()->knob.state==TK_CANCELED&&find()->knob.net==600&&reads==before&&allocations==allocated);
 tgr_knob_observe(app,600,now_ms);assert(find()->knob.net==600);
 TDCommand kq={TDQ_KNOB_START,101,1,30000};assert(tgr_knob_command(app,&kq,now_ms)==TK_OK);now_ms+=100;tgr_knob_observe(app,1200,now_ms);assert(find()->knob.net==1200&&find()->knob.samples==1);
 assert(inject(TGR_NEXT)==TGR_OK&&raw_callbacks==1&&simulated_steps==1&&find()->knob.state==TK_CANCELED&&find()->knob.net==1200&&find()->synthetic_depth==0);
 kq=(TDCommand){TDQ_KNOB_START,102,1,30000};assert(tgr_knob_command(app,&kq,now_ms)==TK_OK);now_ms+=100;tgr_knob_observe(app,4800,now_ms);kq=(TDCommand){TDQ_KNOB_STOP,102,2,0};assert(tgr_knob_command(app,&kq,now_ms)==TK_OK&&find()->knob.net==4800&&find()->knob.samples==1&&reads==before);
 TDSample snapshot={.build=TD_BUILD_TMG6,.kind=TD_STATUS,.session=1,.sequence=1};tgr_runtime_snapshot(&snapshot);assert(snapshot.caps==TD_CAPS_TMG8);uint8_t status_raw[TD_WIRE_BYTES];assert(td_encode(&snapshot,status_raw,sizeof status_raw)&&snapshot.calibration_window==102&&snapshot.calibration_net==4800&&snapshot.tile_generation==1&&reads==before);
 kq=(TDCommand){TDQ_KNOB_START,103,1,30000};assert(tgr_knob_command(app,&kq,now_ms)==TK_OK);blocked=true;timer.callback(&timer);assert(find()->knob.state==TK_CANCELED&&reads==before);blocked=false;kq.session=104;assert(tgr_knob_command(app,&kq,now_ms)==TK_OK);detail_open=true;tgr_knob_observe(app,600,now_ms);assert(find()->knob.state==TK_CANCELED&&find()->knob.samples==0);detail_open=false;
 uint8_t raw[32];TTConfig c;tt_default(&c);tt_file_encode(raw,&c,9);chunk=3;assert(tt_file_write(NULL,0,raw,32));uint8_t reread[33];assert(tt_file_read(NULL,0,reread,33)==32&&!memcmp(raw,reread,32));chunk=0;
 const int write_failures[]={FAIL_OPEN,FAIL_ERROR,FAIL_CLOSE,FAIL_WRITE,FAIL_WRITE_ZERO,FAIL_FLUSH,FAIL_FILENO,FAIL_SYNC,FAIL_WRITE_BIG};
 for(unsigned i=0;i<sizeof write_failures/sizeof *write_failures;i++){io_fail=write_failures[i];assert(!tt_file_write(NULL,1,raw,32));}
 io_fail=0;assert(tt_file_write(NULL,0,raw,32));const int read_failures[]={FAIL_OPEN,FAIL_READ,FAIL_READ_ZERO,FAIL_ERROR,FAIL_CLOSE,FAIL_READ_BIG};for(unsigned i=0;i<sizeof read_failures/sizeof *read_failures;i++){io_fail=read_failures[i];assert(tt_file_read(NULL,0,reread,33)==-1);}io_fail=0;
 // Run the same durability/progress cases through the language adapter.
 uint8_t lang_raw[20],lang_back[21];tls_file_encode(lang_raw,TLG_ZH,11);chunk=3;assert(tls_file_write(NULL,0,lang_raw,20)&&tls_file_read(NULL,0,lang_back,21)==20&&!memcmp(lang_raw,lang_back,20));chunk=0;
 for(unsigned i=0;i<sizeof write_failures/sizeof *write_failures;i++){io_fail=write_failures[i];assert(!tls_file_write(NULL,1,lang_raw,20));}io_fail=0;assert(tls_file_write(NULL,0,lang_raw,20));for(unsigned i=0;i<sizeof read_failures/sizeof *read_failures;i++){io_fail=read_failures[i];assert(tls_file_read(NULL,0,lang_back,21)==-1);}io_fail=0;
 // A real TLG1 handler query reads cached state; reboot loading is lazy.
 before=reads;lr=language_request((TLGCommand){11,TLG_QUERY,TLG_EN});assert(lr.result==TLG_OK&&reads==before);lr=language_request((TLGCommand){12,TLG_SET,TLG_ZH});assert(lr.result==TLG_OK&&lr.source==2&&tio_lang()==TLG_ZH);
 free(timer.user);timer=(HostTimer){0};before=reads;assert(tio_lang()==TLG_EN&&reads==before);assert(fm_menu_rows()==3&&tio_lang()==TLG_ZH&&find()->language.source==2&&reads==before+6);before=reads;lr=language_request((TLGCommand){13,TLG_QUERY,TLG_EN});assert(lr.source==2&&lr.lang==TLG_ZH&&reads==before);
 reset();fail_alloc=true;assert(fm_menu_rows()==3&&!timer.user&&reads==0&&fm_tile_count()==13);reset();fail_timer=true;assert(fm_menu_rows()==3&&!timer.user&&allocations==1&&frees==1&&reads==0);reset();cycle=true;assert(!control()&&nexts==512&&allocations==0);cycle=false;
 reset();puts("PASS native remote: production lazy load, bounded lookup, grant/write/readback, safe active-map switch and native IO fault/progress handling");return 0;
}
