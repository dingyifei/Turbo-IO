#import <Foundation/Foundation.h>
// Host-only providers for executing the unchanged phone OTA policy offline.
NSString *TMG4Home(void);
NSTimeInterval TMG4Now(void);
NSDictionary *TMG4HostInfo(void);
NSDictionary *TMG4Prefs(void);
BOOL TDPPhonePauseForOTA(void);
