// Download-only 1.0.11/259 host: the business-9 guard is the only thing standing
// between the stock app and an OTA session. Runs the unchanged phone policy
// (ExperimentalOTAFlash.m / ExperimentalOTAFeed.m, adapted by test.py exactly like
// tmg4-wizard) against 1.0.11 host info. No device, network or signing.
// Optional argv: <1.0.11 Runner> <1.0.11 Info.plist> also checks the real image.
#import "TMG4WizardHost.h"
#import "HostCompatibility.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "TIOLanguage.h"
#include <assert.h>
static NSString *Home;
static NSTimeInterval Now=100;
static NSDictionary *Prefs,*Host;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return Now;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
BOOL TDPPhonePauseForOTA(void){return YES;}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(NSUInteger type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static BOOL Allowed(id payload,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":payload}});}
static void Observe(NSString *version){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":version,@"OtaValidationConfirmed":@YES},nil)}});}
static NSUInteger Checked;
// Every business-9 frame shape is refused except the exact empty version query.
static void OnlyVersionQueryPasses(void){
    NSData *query=Frame(1,nil,nil);assert(TIOOTAIsEmptyVersionQuery(query));
    for(NSString *peer in @[@"fixture-peer",@"other-peer",@""]){assert(Allowed(query,peer));assert(Allowed(@{@"data":query},peer));}
    NSArray *bodies=@[NSNull.null,@{},@{@"Mode":@2},@{@"OtaSize":@1},@{@"OtaVersion":@"Strix OS 1.0.5.5"},@[]];
    for(NSUInteger t=0;t<256;t++)for(id json in bodies)for(NSData *binary in @[(id)NSNull.null,[NSData dataWithBytes:"x" length:1]]){
        id j=json==NSNull.null?nil:json;NSData *b=binary==(id)NSNull.null?nil:binary;
        BOOL exact=t==1&&!j&&!b;
        assert(Allowed(Frame(t,j,b),@"fixture-peer")==exact);Checked++;
    }
    // The flows that matter, named: OTA start (type 4, Mode 2), size, version, manifest, slice, idle.
    assert(!Allowed(Frame(4,@{@"Mode":@2},nil),@"fixture-peer"));assert(!Allowed(Frame(4,nil,nil),@"fixture-peer"));
    assert(!Allowed(Frame(3,@{@"OtaSize":@123},nil),@"fixture-peer"));assert(!Allowed(Frame(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil),@"fixture-peer"));
    assert(!Allowed(Frame(6,@[],nil),@"fixture-peer"));assert(!Allowed(Frame(7,@{@"Name":@"nuttx_ap.bin",@"Start":@0,@"Size":@1},[NSData dataWithBytes:"x" length:1]),@"fixture-peer"));
    assert(!Allowed(Frame(2,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(11,nil,nil),@"fixture-peer"));
    // Malformed calls are refused; non-OTA business ids pass through untouched.
    for(id payload in @[[NSData data],[NSData dataWithBytes:"\x08\x01" length:2],@"text",@{},NSNull.null])assert(!Allowed(payload,@"fixture-peer"));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"payload":query}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@"9",@"payload":query}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9.5,@"payload":query}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@[]}));
    assert(TIOOTAFlashBlockCall(@{@"arguments":@{@"businessId":@9,@"payload":query}}));
    assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@20,@"payload":Frame(4,@{@"Mode":@2},nil)}}));
    // D3 is deferred: un-scoped sendFile and any OTA/upgrade-named method stay refused, unchanged.
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_startOta",@"arguments":@{}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_upgrade",@"arguments":@{}}));
}
static void Refused(void){
    NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e));assert(e);
    assert([e.localizedDescription isEqual:TIOText(@"1.0.7 OTA 专用宿主或路由标记不匹配，未授权。")]);
    NSDictionary *s=TIOOTAFlashStatus();assert([s[@"stage"] intValue]==0);assert(![s[@"authorized"] boolValue]);assert(![s[@"started"] boolValue]);
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1||argc==3);
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *d=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011-download"};
    if(argc==3){
        NSMutableDictionary *real=[[NSDictionary dictionaryWithContentsOfFile:@(argv[2])] mutableCopy];assert(real);
        assert([real[@"CFBundleShortVersionString"] isEqual:@"1.0.11"]&&[real[@"CFBundleVersion"] isEqual:@"259"]);
        NSData *runner=[NSData dataWithContentsOfFile:@(argv[1]) options:NSDataReadingMappedIfSafe error:nil];assert(runner.length>4096);
        const struct mach_header *h=runner.bytes;
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1011-download"]);assert(TIOHostDownloadOnlyImageMatches(h,real));
        assert(!TIOHostImageMatches(h,real));assert(!TIOHostExpectedUUID(real));
        NSMutableDictionary *as107=[real mutableCopy];as107[@"CFBundleShortVersionString"]=@"1.0.7";as107[@"CFBundleVersion"]=@"230";assert(!TIOHostProfileFor(h,as107));
        real[@"TIOHostProfile"]=@"ios1011-download";d=real; // what the packager adds
    }
    Host=d;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    // (b) never the 1.0.7 OTA host, even with a stale 1.0.7 routing marker.
    assert(!TIOOTA107HostMatches(Host));
    NSMutableDictionary *stale=[d mutableCopy];stale[@"TIOExperimentalOTAQueryRouting"]=@"ios107-tmg2-loopback-flash-gated";assert(!TIOOTA107HostMatches(stale));
    // (d) the guard is compiled in; protection (the 1.0.7 flash path) is not.
    assert(TIOOTAFlashBuild());assert(!TIOOTAFlashProtected());
    // (b) feed never starts and preparation is refused.
    TIOStartExperimentalOTAFeedIfMarked();
    NSDictionary *feed=TIOExperimentalOTAFeedStatus();
    assert(![feed[@"running"] boolValue]);assert(![feed[@"bootstrapEligible"] boolValue]);assert([feed[@"startAttempts"] intValue]==0);
    assert([feed[@"reason"] isEqual:TIOText(@"1.0.7 实验来源宿主版本/UUID/标记不匹配")]);
    NSError *e=nil;assert(!TIOBeginExperimentalOTAPreparation(&e));assert(e);
    // (a) before and after the transport hook is ready.
    OnlyVersionQueryPasses();TIOOTARecordTransportHookReady();assert(!TIOOTAFlashProtected());OnlyVersionQueryPasses();
    // (c) authorization fails for the host reason even when everything else is in place.
    Refused();Observe(@"Strix OS 1.0.5.5");assert([TIOOTAFlashStatus()[@"recentTargetVersionRead"] boolValue]);Refused();
    Host=stale;Refused();OnlyVersionQueryPasses();Host=d;
    assert(!Allowed(Frame(4,@{@"Mode":@2},nil),@"fixture-peer"));OnlyVersionQueryPasses();
    // Control: the harness does discriminate. The 1.0.7 host takes the other branch.
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    assert(TIOOTA107HostMatches(Host));assert(TIOOTAFlashProtected());assert(Allowed(Frame(2,nil,nil),@"fixture-peer"));
    Host=d;assert(!Allowed(Frame(2,nil,nil),@"fixture-peer"));
    NSLog(@"PASS: 1.0.11 download-only guard: %lu frame shapes, only the empty version query passes; type 4 refused; feed not started; authorization refused; flash build on%s",(unsigned long)Checked,argc==3?"; real 1.0.11 Runner profile":"");
}return 0;}
