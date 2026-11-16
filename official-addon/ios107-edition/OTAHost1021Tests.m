// Full 1.0.21 host (ios1021, C20 onward): OTAHost.h host and route record checks.
// argv: <stock 1.0.21 App> <1.0.21 App patched by patch-route.mjs ios1021>
#import "OTAHost.h"
#include <assert.h>
static NSString *Tmp;
static void Mutations(NSString *file,NSString *profile){
    NSMutableData *record=[[NSData dataWithContentsOfFile:file] mutableCopy];assert(record);
    for(NSNumber *offset in TIOOTARouteOffsets(profile))for(NSNumber *delta in @[@0,@-12,@-8,@10]){
        NSUInteger i=offset.unsignedIntegerValue+delta.integerValue;((uint8_t *)record.mutableBytes)[i]^=1;
        assert([record writeToFile:Tmp atomically:YES]);assert(!TIOOTARouteFileMatches(Tmp,profile));
        ((uint8_t *)record.mutableBytes)[i]^=1;
    }
    assert([[record subdataWithRange:NSMakeRange(0,[TIOOTARouteOffsets(profile)[0] unsignedIntegerValue])] writeToFile:Tmp atomically:YES]);assert(!TIOOTARouteFileMatches(Tmp,profile));
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==3);Tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.21",@"CFBundleVersion":@"1",@"TIOHostProfile":@"ios1021",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1021_ROUTING_MARKER};
    assert(TIOOTA1021HostMatches(full)&&[TIOOTAHostProfile(full) isEqual:@"ios1021"]&&TIOOTAHostMatches(full));
    assert(TIOOTAArmHostMatches(@"ios1021",full)&&TIOOTAArmHostName(@"ios1021"));
    // Only "ios1021" is an arm host name; the retired full-host names (ios1011, ios107) and the download-only profile are not.
    for(id name in @[@"ios1011",@"ios107",@"ios1021-download",@"ios1011-download",@"IOS1021",@"ios1021 ",@"",@1021,NSNull.null])assert(!TIOOTAArmHostName(name)&&!TIOOTAArmHostMatches(name,full));
    for(NSString *key in full){
        NSMutableDictionary *bad=[full mutableCopy];[bad removeObjectForKey:key];assert(!TIOOTAHostProfile(bad));
        bad[key]=@"invalid";assert(!TIOOTAHostProfile(bad));
    }
    // Near misses of each marker, version and build (the retired 1.0.11 and 1.0.7 markers included) are no OTA host;
    // the download-only marker never opts in at all.
    for(NSArray *kv in @[@[@"TIOExperimentalOTAQueryRouting",@"ios107-tmg2-loopback-flash-gated"],@[@"TIOExperimentalOTAQueryRouting",@"ios1011-tmg-loopback-flash-gated-arm-required"],
            @[@"TIOExperimentalOTAQueryRouting",[TIO_OTA_1021_ROUTING_MARKER uppercaseString]],
            @[@"TIOHostProfile",@"ios1011"],@[@"TIOHostProfile",@"ios1021-download"],@[@"TIOHostProfile",@"ios107"],@[@"TIOHostProfile",@1],
            @[@"CFBundleVersion",@"259"],@[@"CFBundleVersion",@1],@[@"CFBundleShortVersionString",@"1.0.11"],@[@"CFBundleShortVersionString",@"1.0.22"]]){
        NSMutableDictionary *bad=[full mutableCopy];bad[kv[0]]=kv[1];assert(!TIOOTAHostProfile(bad));
    }
    assert([TIOOTARouteOffsets(@"ios1021") isEqual:(@[@46796656,@37435136])]);
    for(id p in @[@"ios1021-download",@"ios1011",@"ios107",@"IOS1021",@""])assert(!TIOOTARouteOffsets(p));
    NSString *stock=@(argv[1]),*patched=@(argv[2]);
    assert(!TIOOTARouteFileMatches(stock,@"ios1021"));
    assert(TIOOTARouteFileMatches(patched,@"ios1021")&&!TIOOTARouteFileMatches(patched,@"ios1011")&&!TIOOTARouteFileMatches(patched,@"ios107"));
    assert(!TIOOTARouteFileMatches(patched,@"ios1021-download")&&!TIOOTARouteFileMatches(@"/nonexistent/TurboIO-test",@"ios1021"));
    Mutations(patched,@"ios1021");
    [NSFileManager.defaultManager removeItemAtPath:Tmp error:nil];
    NSLog(@"PASS: 1.0.21 full host marker exact, near misses and retired markers refused; route records at the 1.0.21 offsets only");
}return 0;}
