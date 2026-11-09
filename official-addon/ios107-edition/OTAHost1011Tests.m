// Full 1.0.11 host (ios1011, C15): OTAHost.h host and route record checks per profile.
// argv: <stock 1.0.11 App> <1.0.11 App patched by patch-route.mjs ios1011> <patched 1.0.7 App or ->
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
    NSDictionary *full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    NSDictionary *old=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    assert(TIOOTA1011HostMatches(full)&&!TIOOTA107HostMatches(full)&&[TIOOTAHostProfile(full) isEqual:@"ios1011"]&&TIOOTAHostMatches(full));
    assert(TIOOTA107HostMatches(old)&&!TIOOTA1011HostMatches(old)&&[TIOOTAHostProfile(old) isEqual:@"ios107"]);
    for(NSString *key in full){
        NSMutableDictionary *bad=[full mutableCopy];[bad removeObjectForKey:key];assert(!TIOOTAHostProfile(bad));
        bad[key]=@"invalid";assert(!TIOOTAHostProfile(bad));
    }
    // One host's marker never opts in the other; the download-only marker never opts in at all.
    for(NSArray *kv in @[@[@"TIOExperimentalOTAQueryRouting",@"ios107-tmg2-loopback-flash-gated"],@[@"TIOHostProfile",@"ios1011-download"],@[@"TIOHostProfile",@"ios107"],@[@"TIOHostProfile",@1]]){
        NSMutableDictionary *bad=[full mutableCopy];bad[kv[0]]=kv[1];assert(!TIOOTAHostProfile(bad));
    }
    NSMutableDictionary *cross=[old mutableCopy];cross[@"TIOExperimentalOTAQueryRouting"]=TIO_OTA_1011_ROUTING_MARKER;cross[@"TIOHostProfile"]=@"ios1011";assert(!TIOOTAHostProfile(cross));
    assert([TIOOTARouteOffsets(@"ios107") isEqual:(@[@41206352,@32115728])]&&[TIOOTARouteOffsets(@"ios1011") isEqual:(@[@39886000,@30868352])]);
    for(id p in @[@"ios1011-download",@"IOS1011",@""])assert(!TIOOTARouteOffsets(p));
    NSString *stock=@(argv[1]),*patched=@(argv[2]);
    assert(!TIOOTARouteFileMatches(stock,@"ios1011")&&!TIOOTARouteFileMatches(stock,@"ios107"));
    assert(TIOOTARouteFileMatches(patched,@"ios1011")&&!TIOOTARouteFileMatches(patched,@"ios107")&&!TIOOTA107RouteFileMatches(patched));
    assert(!TIOOTARouteFileMatches(patched,@"ios1011-download")&&!TIOOTARouteFileMatches(@"/nonexistent/TurboIO-test",@"ios1011"));
    Mutations(patched,@"ios1011");
    if(strcmp(argv[3],"-")){
        NSString *patched107=@(argv[3]);
        assert(TIOOTARouteFileMatches(patched107,@"ios107")&&TIOOTA107RouteFileMatches(patched107)&&!TIOOTARouteFileMatches(patched107,@"ios1011"));
        Mutations(patched107,@"ios107");
    }
    [NSFileManager.defaultManager removeItemAtPath:Tmp error:nil];
    NSLog(@"PASS: 1.0.11 full host marker exact, never the 1.0.7 marker; route records at each host's own offsets%s",strcmp(argv[3],"-")?"; 1.0.7 patched App cross-checked":"");
}return 0;}
