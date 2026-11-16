#import <Foundation/Foundation.h>

// The TMG flash path runs ONLY on the inspected host whose packager wrote that host's
// own routing marker. Old markers or restored preferences never opt another build
// into OTA.
//
// 1.0.21/1 full profile (ios1021, C20 onward): its own routing marker plus the packager's
// TIOHostProfile marker. Matching this does NOT allow a transfer by itself: the guard also
// needs the explicit arm step (TIOOTAFlashArmed) and the main image check
// (TIOHostFullImageMatches); see ExperimentalOTAFlash.m.
#define TIO_OTA_1021_ROUTING_MARKER @"ios1021-tmg-loopback-flash-gated-arm-required"
static inline BOOL TIOOTA1021HostMatches(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"] &&
        [info[@"CFBundleShortVersionString"] isEqual:@"1.0.21"] &&
        [info[@"CFBundleVersion"] isEqual:@"1"] &&
        [info[@"TIOHostProfile"] isEqual:@"ios1021"] &&
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:TIO_OTA_1021_ROUTING_MARKER];
}
// "ios1021" or nil.
static inline NSString *TIOOTAHostProfile(NSDictionary *info) {
    return TIOOTA1021HostMatches(info)?@"ios1021":nil;
}
static inline BOOL TIOOTAHostMatches(NSDictionary *info) {return TIOOTAHostProfile(info)!=nil;}
// The full host that needs the arm step (ios1021). The arm guard, the arm record and the
// host checks of ExperimentalOTAFlash.m take this name.
static inline BOOL TIOOTAArmHostName(id name) {
    return [name isKindOfClass:NSString.class]&&[name isEqualToString:@"ios1021"];
}
// The exact OTA host check for the named full host; NO for any other name.
static inline BOOL TIOOTAArmHostMatches(NSString *name,NSDictionary *info) {
    return [name isEqual:@"ios1021"]&&TIOOTA1021HostMatches(info);
}

// The two patched Dart string records of the host's App.framework/App: the replacement
// strings and cached hashes, at the host's offsets. patch-route.mjs ROUTE_PROFILES holds the same table.
static inline NSArray<NSNumber *> *TIOOTARouteOffsets(NSString *profile) {
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
