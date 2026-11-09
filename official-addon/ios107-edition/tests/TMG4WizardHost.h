#import <Foundation/Foundation.h>
// Host-only providers for executing the unchanged phone OTA policy offline.
NSString *TMG4Home(void);
NSTimeInterval TMG4Now(void);
NSDictionary *TMG4HostInfo(void);
NSDictionary *TMG4Prefs(void);
BOOL TDPPhonePauseForOTA(void);
// Main executable header seam (only the 1.0.11 guard tests substitute it).
struct mach_header;
const struct mach_header *TMG4MainImage(void);
// The ios1011 arm record store (test.py substitutes the addon prefs suite with it). Weak, so
// the test file and the adapted policy, which both include this header, share one dictionary.
__attribute__((weak)) NSMutableDictionary *TMG4ArmStore(void){
    static NSMutableDictionary *store;static dispatch_once_t once;dispatch_once(&once,^{store=[NSMutableDictionary new];});return store;
}
