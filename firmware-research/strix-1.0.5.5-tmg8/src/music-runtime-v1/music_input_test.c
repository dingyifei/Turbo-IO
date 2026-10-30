#include "music_input.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
int main(void){TMInput s={0};
 for(unsigned i=0;i<1000;i++)assert(!tm_input_wheel(&s,i%2?2:-2,i));
 assert(!tm_input_wheel(&s,200,2000));assert(tm_input_wheel(&s,200,2020)==1);
 for(unsigned i=0;i<10;i++)assert(!tm_input_wheel(&s,600,2050+i*40));
 assert(!tm_input_press(&s,2100));assert(tm_input_wheel(&s,-600,3000)==-1);
 assert(!tm_input_wheel(&s,150,4000));assert(!tm_input_wheel(&s,-150,4010));assert(tm_input_wheel(&s,-150,4020)==-1);
 s=(TMInput){0};assert(tm_input_wheel(&s,INT_MIN,UINT_MAX-100)==-1);assert(!tm_input_wheel(&s,INT_MAX,1));assert(tm_input_wheel(&s,INT_MAX,900)==1);
 s=(TMInput){0};assert(!tm_input_wheel(&s,200,1));assert(!tm_input_wheel(&s,250,400));assert(tm_input_press(&s,800));assert(!tm_input_press(&s,900));
 puts("PASS music input: jitter, detents, one skip per 500 ms, reversal, overflow, click guard passed");
}
