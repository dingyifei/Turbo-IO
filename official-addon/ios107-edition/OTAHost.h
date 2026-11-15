#import <Foundation/Foundation.h>

// The TMG flash path runs ONLY on inspected hosts whose packager wrote that host's
// own routing marker. Old markers or restored preferences never opt another build
// into OTA, and one host's marker never opts in the other.
//
// 1.0.7/230 (profile ios107): unchanged.
static inline BOOL TIOOTA107HostMatches(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"] &&
        [info[@"CFBundleShortVersionString"] isEqual:@"1.0.7"] &&
        [info[@"CFBundleVersion"] isEqual:@"230"] &&
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios107-tmg2-loopback-flash-gated"];
}
// 1.0.11/259 full profile (ios1011, C15): its own routing marker plus the packager's
// TIOHostProfile marker. Matching this does NOT allow a transfer by itself: on this
// host the guard also needs the explicit arm step (TIOOTAFlashArmed) and the main
// image check (TIOHostFullImageMatches); see ExperimentalOTAFlash.m.
#define TIO_OTA_1011_ROUTING_MARKER @"ios1011-tmg-loopback-flash-gated-arm-required"
static inline BOOL TIOOTA1011HostMatches(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"] &&
        [info[@"CFBundleShortVersionString"] isEqual:@"1.0.11"] &&
        [info[@"CFBundleVersion"] isEqual:@"259"] &&
        [info[@"TIOHostProfile"] isEqual:@"ios1011"] &&
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:TIO_OTA_1011_ROUTING_MARKER];
}
// 1.0.21/1 full profile (ios1021, C20): the same model as ios1011, with its own routing
// marker and the packager's TIOHostProfile=ios1021. Same arm step, same transfer gate.
#define TIO_OTA_1021_ROUTING_MARKER @"ios1021-tmg-loopback-flash-gated-arm-required"
static inline BOOL TIOOTA1021HostMatches(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"] &&
        [info[@"CFBundleShortVersionString"] isEqual:@"1.0.21"] &&
        [info[@"CFBundleVersion"] isEqual:@"1"] &&
        [info[@"TIOHostProfile"] isEqual:@"ios1021"] &&
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:TIO_OTA_1021_ROUTING_MARKER];
}
// "ios107", "ios1011", "ios1021" or nil.
static inline NSString *TIOOTAHostProfile(NSDictionary *info) {
    if(TIOOTA107HostMatches(info))return @"ios107";
    if(TIOOTA1011HostMatches(info))return @"ios1011";
    if(TIOOTA1021HostMatches(info))return @"ios1021";
    return nil;
}
static inline BOOL TIOOTAHostMatches(NSDictionary *info) {return TIOOTAHostProfile(info)!=nil;}
// The full hosts that need the arm step (ios1011, ios1021). The arm guard, the arm record
// and the host checks of ExperimentalOTAFlash.m take one of these names.
static inline BOOL TIOOTAArmHostName(id name) {
    return [name isKindOfClass:NSString.class]&&([name isEqualToString:@"ios1011"]||[name isEqualToString:@"ios1021"]);
}
// The exact OTA host check for one named full host; NO for any other name.
static inline BOOL TIOOTAArmHostMatches(NSString *name,NSDictionary *info) {
    if([name isEqual:@"ios1011"])return TIOOTA1011HostMatches(info);
    if([name isEqual:@"ios1021"])return TIOOTA1021HostMatches(info);
    return NO;
}

// The two patched Dart string records of each host's App.framework/App: same
// replacement strings and cached hashes on every host (the stock strings are the
// same), at each host's own offsets. patch-route.mjs ROUTE_PROFILES holds the same table.
static inline NSArray<NSNumber *> *TIOOTARouteOffsets(NSString *profile) {
    if([profile isEqual:@"ios107"])return @[@41206352,@32115728];
    if([profile isEqual:@"ios1011"])return @[@39886000,@30868352];
    if([profile isEqual:@"ios1021"])return @[@46796656,@37435136];
    return nil;
}
static inline BOOL TIOOTARouteFileMatches(NSString *file,NSString *profile) {
    NSArray *offsets=TIOOTARouteOffsets(profile);if(!offsets)return NO;
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:file];BOOL ok=handle!=nil;
    @try {
        NSArray *strings=@[@"http://127.0.0.1:18794/g/xxxxxxxA78p2M",@"http://127.0.0.1:18794/g/xxxxxxxxxxCCXhB"];
        NSArray *hashes=@[@352684455,@555237387];
        for(NSUInteger i=0;i<offsets.count&&ok;i++) {
            NSData *expected=[strings[i] dataUsingEncoding:NSASCIIStringEncoding];
            [handle seekToFileOffset:[offsets[i] unsignedLongLongValue]-12];
            NSData *record=[handle readDataOfLength:12+expected.length];
            if(record.length!=12+expected.length){ok=NO;break;}
            uint32_t hash;uint64_t length;memcpy(&hash,record.bytes,4);memcpy(&length,(const uint8_t *)record.bytes+4,8);
            ok=hash==[hashes[i] unsignedIntValue]&&length==expected.length*2&&
                !memcmp((const uint8_t *)record.bytes+12,expected.bytes,expected.length);
        }
    }@catch(NSException *e){(void)e;ok=NO;}@finally{[handle closeFile];}
    return ok;
}
static inline BOOL TIOOTA107RouteFileMatches(NSString *file) {return TIOOTARouteFileMatches(file,@"ios107");}
