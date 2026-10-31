#define main native_remote_baseline_main
#include "native_remote_test.c"
#undef main
void diagnosis_reset(void){reset();(void)fm_menu_rows();(void)fm_tiles_apply(app);}
void diagnosis_reboot(void){free(timer.user);timer=(HostTimer){0};(void)fm_menu_rows();(void)fm_tiles_apply(app);}
void diagnosis_finish(void){reset();}
unsigned diagnosis_count(void){return fm_tile_count();}
unsigned diagnosis_rank(unsigned id){return fm_tile_rank(id);}
void diagnosis_send(const uint8_t *bytes,unsigned n,uint8_t *out){assert(n==74);TIONativeMessage m={.id=1,.bytes=n,.data=bytes};memset(reply_wire,0,sizeof reply_wire);tgr_native_message(&m);memcpy(out,reply_wire,74);}
