#include "../src/diagnostics-v1/diagnostics.h"
#include "../src/diagnostics-v1/command.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
static void crc(uint8_t *p){uint32_t c=td_crc(p,252);for(unsigned i=0;i<4;i++)p[252+i]=(uint8_t)(c>>(8*i));}
int main(void){
 assert(TD_WIRE_BYTES==256);TDSample s={.build=TD_BUILD_TMG4,.kind=TD_STATUS,.session=1,.sequence=2,.caps=TD_CAPS_ALL,.detent=600,.extension_valid=15,.nand_total=128000,.nand_available=64000,.tile_generation=UINT32_MAX,.language=1,.language_source=2,.calibration_state=2,.calibration_result=0,.calibration_window=3,.calibration_elapsed=2000,.calibration_samples=8,.calibration_net=-4800,.calibration_absolute=4800,.calibration_sequence=2,.settings_flags=3},out;
 memset(s.build_sha,0xab,32);uint8_t wire[TD_WIRE_BYTES];assert(td_encode(&s,wire,sizeof wire)&&td_decode(wire,sizeof wire,&out));assert(out.kind==TD_STATUS&&out.nand_available==64000&&out.calibration_net==-4800&&out.tile_generation==UINT32_MAX&&!memcmp(out.build_sha,s.build_sha,32));
 for(unsigned n=0;n<270;n++)if(n!=256)assert(!td_decode(wire,n,&out));for(unsigned i=0;i<256;i++)for(unsigned bit=0;bit<8;bit++){wire[i]^=1u<<bit;assert(!td_decode(wire,256,&out));wire[i]^=1u<<bit;}
 wire[124]='X';crc(wire);assert(!td_decode(wire,256,&out));assert(td_encode(&s,wire,256));wire[232]=1;crc(wire);assert(!td_decode(wire,256,&out));assert(td_encode(&s,wire,256));wire[5]=3;crc(wire);assert(!td_decode(wire,256,&out));
 s.extension_valid=0;s.nand_total=s.nand_available=0;s.tile_generation=0;s.language=s.language_source=0;s.calibration_state=s.calibration_window=s.calibration_elapsed=s.calibration_samples=s.calibration_net=s.calibration_absolute=s.calibration_sequence=0;s.settings_flags=0;assert(td_encode(&s,wire,256));s.nand_total=1;assert(!td_encode(&s,wire,256));s.nand_total=0;s.build=0x01000001;assert(!td_encode(&s,wire,256));
 uint32_t st[16]={0};uint64_t total=99,available=98;st[2]=131072;st[4]=100;st[6]=80;st[8]=70;assert(td_nand_metrics(st,sizeof st,&total,&available)&&total==13107200&&available==9175040);for(unsigned i=0;i<64;i++)assert(!td_nand_metrics(st,i,&total,&available));st[9]=1;assert(!td_nand_metrics(st,64,&total,&available));st[9]=0;st[8]=81;assert(!td_nand_metrics(st,64,&total,&available));st[8]=70;st[2]=3;assert(!td_nand_metrics(st,64,&total,&available));st[2]=131072;st[4]=UINT32_MAX;assert(!td_nand_metrics(st,64,&total,&available));assert(!td_nand_metrics(NULL,64,&total,&available));
 uint8_t cmd[24];TDCommand q;assert(td_command_encode((TDCommand){TDQ_STATUS,1,1,0},cmd,24)&&td_command_decode(cmd,24,&q));assert(td_command_encode((TDCommand){TDQ_KNOB_START,1,2,30000},cmd,24));assert(!td_command_encode((TDCommand){TDQ_KNOB_START,1,2,30001},cmd,24));assert(td_command_encode((TDCommand){TDQ_KNOB_STOP,1,3,0},cmd,24));assert(!td_command_encode((TDCommand){TDQ_STATUS,1,1,1},cmd,24));
 uint32_t seed=9;for(unsigned i=0;i<50000;i++){uint8_t bytes[272];for(unsigned j=0;j<272;j++){seed=seed*1664525u+1013904223u;bytes[j]=(uint8_t)(seed>>24);}TDSample previous;memset(&out,0x5a,sizeof out);previous=out;if(!td_decode(bytes,i%273,&out))assert(!memcmp(&previous,&out,sizeof out));(void)td_command_decode(bytes,i%273,&q);(void)td_nand_metrics(bytes,i%273,&total,&available);}
 puts("PASS runtime status: exact v2 layout, optional-field validity, family/kind/CRC/reserved bounds, statfs ABI and command/fuzz limits");
}
