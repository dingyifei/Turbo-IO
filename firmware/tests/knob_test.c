#include "../src/diagnostics-v1/knob_calibration.h"
#include <assert.h>
#include <stdio.h>
#include <limits.h>
#include <string.h>
int main(void){
 TKState s={0};uint64_t estimate=77;assert(!tk_estimate(&s,&estimate)&&estimate==77);assert(tk_start(&s,1,1,30000,100,true)==TK_OK&&s.state==TK_ACTIVE);
 tk_observe(&s,1200,200,true,false);tk_observe(&s,2400,300,true,false);uint32_t start=s.started;assert(tk_start(&s,1,1,30000,500,true)==TK_OK&&s.started==start&&s.samples==2&&s.net==3600);assert(tk_start(&s,2,1,30000,500,true)==TK_BUSY);
 assert(tk_stop(&s,2,2,600,true)==TK_SESSION&&s.state==TK_ACTIVE);assert(tk_stop(&s,1,1,600,true)==TK_SESSION);assert(tk_stop(&s,1,2,600,true)==TK_OK&&s.state==TK_FINISHED&&s.elapsed==500);assert(tk_estimate(&s,&estimate)&&estimate==3600);assert(tk_stop(&s,1,2,900,true)==TK_OK&&s.elapsed==500);assert(tk_start(&s,1,1,30000,900,true)==TK_OK&&s.state==TK_FINISHED);
 assert(tk_start(&s,2,1,30000,1000,true)==TK_OK);tk_observe(&s,-4800,2000,true,false);assert(tk_stop(&s,2,2,3000,true)==TK_OK&&tk_estimate(&s,&estimate)&&estimate==4800);
 assert(tk_start(&s,3,1,30000,4000,true)==TK_OK);tk_observe(&s,1000,4100,true,false);tk_observe(&s,-500,4200,true,false);tk_stop(&s,3,2,4300,true);assert(!tk_estimate(&s,&estimate));
 assert(tk_start(&s,4,1,30000,5000,true)==TK_OK);tk_observe(&s,600,5100,true,true);assert(s.state==TK_CANCELED&&s.samples==0);assert(tk_start(&s,5,1,30000,5101,true)==TK_OK);tk_observe(&s,4800,5200,true,false);tk_stop(&s,5,2,5300,true);assert(tk_estimate(&s,&estimate)&&estimate==4800);
 assert(tk_start(&s,6,1,30000,UINT32_MAX-100,true)==TK_OK);tk_observe(&s,INT_MIN,99,true,false);assert(s.net==INT_MIN&&s.absolute==2147483648ULL&&s.elapsed==200);tk_stop(&s,6,2,199,true);assert(tk_estimate(&s,&estimate)&&estimate==2147483648ULL);
 assert(tk_start(&s,7,1,1000,UINT32_MAX-500,true)==TK_OK);tk_observe(&s,0,100,true,false);assert(s.samples==0);tk_observe(&s,1,499,true,false);assert(s.state==TK_EXPIRED&&s.samples==0&&s.elapsed==1000);assert(!tk_estimate(&s,&estimate));
 assert(tk_start(&s,8,1,30000,100,true)==TK_OK);tk_poll(&s,200,false);assert(s.state==TK_CANCELED&&!tk_estimate(&s,&estimate));assert(tk_start(&s,9,1,30000,300,false)==TK_BLOCKED);
 assert(tk_start(&s,9,UINT32_MAX-1,30000,300,true)==TK_OK);tk_observe(&s,1,301,true,false);assert(tk_stop(&s,9,UINT32_MAX,302,true)==TK_OK);assert(tk_stop(&s,9,1,303,true)==TK_SESSION);
 assert(tk_start(&s,10,1,30000,400,true)==TK_OK);s.net=INT64_MAX;s.absolute=INT64_MAX;s.samples=1;tk_observe(&s,1,401,true,false);assert(s.state==TK_OVERFLOW&&!tk_estimate(&s,&estimate));
 assert(tk_start(&s,11,1,30000,500,true)==TK_OK);s.net=INT64_MIN;s.absolute=1ULL<<63;s.samples=1;tk_observe(&s,-1,501,true,false);assert(s.state==TK_OVERFLOW);
 assert(tk_start(&s,12,1,30000,600,true)==TK_OK);s.net=0;s.absolute=UINT64_MAX;s.samples=1;tk_observe(&s,1,601,true,false);assert(s.state==TK_OVERFLOW);
 assert(tk_start(&s,0,1,1,0,true)==TK_UNAVAILABLE&&tk_start(&s,1,0,1,0,true)==TK_UNAVAILABLE&&tk_start(&s,1,1,30001,0,true)==TK_UNAVAILABLE);assert(tk_start(NULL,1,1,1,0,true)==TK_UNAVAILABLE&&!tk_estimate(NULL,&estimate));
 uint32_t seed=7;for(unsigned i=0;i<50000;i++){TKState f={0};seed=seed*1664525u+1013904223u;uint32_t began=seed;assert(tk_start(&f,i+1,1,30000,began,true)==TK_OK);for(unsigned j=0;j<8;j++){seed=seed*1664525u+1013904223u;int32_t delta;memcpy(&delta,&seed,4);tk_observe(&f,delta,began+j*100,true,false);}tk_stop(&f,i+1,2,began+1000,true);assert(f.absolute>=(f.net<0?0u-(uint64_t)f.net:(uint64_t)f.net));(void)tk_estimate(&f,&estimate);}
 for(unsigned i=0;i<50000;i++){seed=seed*1664525u+1013904223u;uint64_t absolute=(uint64_t)seed<<32;seed=seed*1664525u+1013904223u;absolute|=seed;seed=seed*1664525u+1013904223u;uint64_t net=((uint64_t)(seed&0x7fffffffu)<<32)|seed;TKState f={.state=TK_FINISHED,.samples=1,.net=(int64_t)net,.absolute=absolute};bool expected=net&&absolute>=net&&net>=absolute-absolute/10;assert(tk_estimate(&f,&estimate)==expected);if(expected)assert(estimate==net);}
 puts("PASS knob: signed raw units, synthetic/replacement windows, reversal, replay, lease/tick wrap, sequence exhaustion and overflow fuzz");
}
