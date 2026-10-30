#ifndef TIO_RUNTIME_NATIVE_H
#define TIO_RUNTIME_NATIVE_H
#include "command.h"
bool tgr_runtime_allowed(void);
void tgr_runtime_snapshot(TDSample *);
unsigned tgr_knob_command(void *,const TDCommand *,uint32_t);
void tgr_knob_observe(void *,int32_t,uint32_t);
void tgr_knob_cancel(void *,uint32_t);
#endif
