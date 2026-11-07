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
