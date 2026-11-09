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
// test.py substitutes the arm record's CFPreferences calls with these, so they read and
// write TMG4ArmStore(). Only the addon suite's (current user, any host) domain is accepted.
static inline BOOL TMG4ArmDomain(CFStringRef app,CFStringRef user,CFStringRef host){
    return [(__bridge NSString *)app isEqualToString:@"io.turboio.official-private-addon"]&&CFEqual(user,kCFPreferencesCurrentUser)&&CFEqual(host,kCFPreferencesAnyHost);
}
__attribute__((weak)) CFPropertyListRef TMG4ArmCopyValue(CFStringRef key,CFStringRef app,CFStringRef user,CFStringRef host){
    if(!TMG4ArmDomain(app,user,host))abort();id v=TMG4ArmStore()[(__bridge NSString *)key];return v?CFBridgingRetain(v):NULL;
}
// Whether the last arm store write ran on the main thread (the guard's thread).
__attribute__((weak)) BOOL *TMG4ArmLastWriteOnMain(void){static BOOL onMain;return &onMain;}
__attribute__((weak)) void TMG4ArmSetValue(CFStringRef key,CFPropertyListRef value,CFStringRef app,CFStringRef user,CFStringRef host){
    if(!TMG4ArmDomain(app,user,host))abort();*TMG4ArmLastWriteOnMain()=NSThread.isMainThread;if(value)TMG4ArmStore()[(__bridge NSString *)key]=(__bridge id)value;else [TMG4ArmStore() removeObjectForKey:(__bridge NSString *)key];
}
__attribute__((weak)) Boolean TMG4ArmSynchronize(CFStringRef app,CFStringRef user,CFStringRef host){if(!TMG4ArmDomain(app,user,host))abort();return true;}
