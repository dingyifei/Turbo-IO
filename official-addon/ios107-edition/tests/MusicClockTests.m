#include "MusicClock.h"
#include <assert.h>
#include <stdio.h>

int main(void){
 assert(!TMClockDue(100,119.9));
 assert(TMClockDue(100,120));
 assert(TMClockDue(0,50));
 TMClockSample playing={true,10000,120000,100};
 assert(!TMClockDrifted(playing,(TMClockSample){true,13000,120000,103}));
 assert(TMClockDrifted(playing,(TMClockSample){true,18000,120000,103}));
 TMClockSample paused={false,10000,120000,100};
 assert(!TMClockDrifted(paused,(TMClockSample){false,10000,120000,110}));
 assert(TMClockDrifted(paused,(TMClockSample){true,10000,120000,100}));
 assert(TMClockDrifted(paused,(TMClockSample){false,10000,125000,100}));
 assert(!TMClockDrifted((TMClockSample){true,119000,120000,100},
                       (TMClockSample){true,120000,120000,103}));
 assert(TMClockDrifted((TMClockSample){false,60000,120000,100},
                      (TMClockSample){false,1000,120000,110}));
 puts("PASS: MusicClock (10 cases)");
 return 0;
}
