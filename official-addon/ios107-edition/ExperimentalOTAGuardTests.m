#import "ExperimentalOTAGuard.h"
#include <assert.h>
int main(void){@autoreleasepool{
    uint8_t raw[]={8,1,16,1};NSData *query=[NSData dataWithBytes:raw length:sizeof(raw)];
    assert(TIOOTAIsEmptyVersionQuery(query));
    for(int t=0;t<256;t++){uint8_t b[]={8,1,16,(uint8_t)t};NSData *d=[NSData dataWithBytes:b length:4];if(t!=1)assert(!TIOOTAIsEmptyVersionQuery(d));}
    for(NSArray *bytes in @[@[@8,@1,@16,@1,@26,@1,@0],@[@8,@1,@16,@1,@34,@1,@0],@[@8,@1,@16,@1,@48,@1],@[@8,@1,@16,@1,@16,@7],@[@8,@129,@0,@16,@1],@[@8,@1,@16,@1,@56,@0]]){NSMutableData *d=[NSMutableData new];for(NSNumber *v in bytes){uint8_t b=v.intValue;[d appendBytes:&b length:1];}assert(!TIOOTAIsEmptyVersionQuery(d));}
    NSLog(@"PASS: empty OS-version query recognised");
}return 0;}
