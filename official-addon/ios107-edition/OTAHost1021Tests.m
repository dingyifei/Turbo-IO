// Full 1.0.21 host (ios1021, C20): OTAHost.h host and route record checks per profile.
// argv: <stock 1.0.21 App> <1.0.21 App patched by patch-route.mjs ios1021> <1.0.11 App patched by patch-route.mjs ios1011, or ->
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
    assert(argc==4);Tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.21",@"CFBundleVersion":@"1",@"TIOHostProfile":@"ios1021",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1021_ROUTING_MARKER};
    NSDictionary *full1011=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    assert(TIOOTA1021HostMatches(full)&&!TIOOTA1011HostMatches(full)&&!TIOOTA107HostMatches(full)&&[TIOOTAHostProfile(full) isEqual:@"ios1021"]&&TIOOTAHostMatches(full));
    assert(TIOOTA1011HostMatches(full1011)&&!TIOOTA1021HostMatches(full1011)&&[TIOOTAHostProfile(full1011) isEqual:@"ios1011"]);
    assert(TIOOTAArmHostMatches(@"ios1021",full)&&!TIOOTAArmHostMatches(@"ios1011",full)&&TIOOTAArmHostMatches(@"ios1011",full1011)&&!TIOOTAArmHostMatches(@"ios1021",full1011));
    assert(TIOOTAArmHostName(@"ios1011")&&TIOOTAArmHostName(@"ios1021"));
    for(id name in @[@"ios107",@"ios1011-download",@"ios1021-download",@"IOS1021",@"ios1021 ",@"",@1021,NSNull.null])assert(!TIOOTAArmHostName(name)&&!TIOOTAArmHostMatches(name,full));
    for(NSString *key in full){
        NSMutableDictionary *bad=[full mutableCopy];[bad removeObjectForKey:key];assert(!TIOOTAHostProfile(bad));
        bad[key]=@"invalid";assert(!TIOOTAHostProfile(bad));
    }
    // One host's markers never opt in the other: every mix of the 1.0.11 and 1.0.21 markers, versions and builds
    // other than each host's own set is no OTA host; the download-only marker never opts in at all.
    for(NSArray *kv in @[@[@"TIOExperimentalOTAQueryRouting",@"ios107-tmg2-loopback-flash-gated"],@[@"TIOExperimentalOTAQueryRouting",TIO_OTA_1011_ROUTING_MARKER],
            @[@"TIOHostProfile",@"ios1011"],@[@"TIOHostProfile",@"ios1011-download"],@[@"TIOHostProfile",@"ios107"],@[@"TIOHostProfile",@1],
            @[@"CFBundleVersion",@"259"],@[@"CFBundleVersion",@1],@[@"CFBundleShortVersionString",@"1.0.11"]]){
        NSMutableDictionary *bad=[full mutableCopy];bad[kv[0]]=kv[1];assert(!TIOOTAHostProfile(bad));
    }
    for(NSArray *kv in @[@[@"TIOExperimentalOTAQueryRouting",TIO_OTA_1021_ROUTING_MARKER],@[@"TIOHostProfile",@"ios1021"]]){
        NSMutableDictionary *bad=[full1011 mutableCopy];bad[kv[0]]=kv[1];assert(!TIOOTAHostProfile(bad));
    }
    assert([TIOOTARouteOffsets(@"ios1021") isEqual:(@[@46796656,@37435136])]&&[TIOOTARouteOffsets(@"ios1011") isEqual:(@[@39886000,@30868352])]);
    for(id p in @[@"ios1021-download",@"ios1011-download",@"IOS1021",@""])assert(!TIOOTARouteOffsets(p));
    NSString *stock=@(argv[1]),*patched=@(argv[2]);
    assert(!TIOOTARouteFileMatches(stock,@"ios1021")&&!TIOOTARouteFileMatches(stock,@"ios1011")&&!TIOOTARouteFileMatches(stock,@"ios107"));
    assert(TIOOTARouteFileMatches(patched,@"ios1021")&&!TIOOTARouteFileMatches(patched,@"ios1011")&&!TIOOTARouteFileMatches(patched,@"ios107")&&!TIOOTA107RouteFileMatches(patched));
    assert(!TIOOTARouteFileMatches(patched,@"ios1021-download")&&!TIOOTARouteFileMatches(@"/nonexistent/TurboIO-test",@"ios1021"));
    Mutations(patched,@"ios1021");
    if(strcmp(argv[3],"-")){
        NSString *patched1011=@(argv[3]);
        assert(TIOOTARouteFileMatches(patched1011,@"ios1011")&&!TIOOTARouteFileMatches(patched1011,@"ios1021"));
    }
    [NSFileManager.defaultManager removeItemAtPath:Tmp error:nil];
    NSLog(@"PASS: 1.0.21 full host marker exact, never the 1.0.11 or 1.0.7 markers; route records at the 1.0.21 offsets only%s",strcmp(argv[3],"-")?"; 1.0.11 patched App cross-checked":"");
}return 0;}
