// Full 1.0.21/1 host (profile ios1021; tests/FullHostFixture.h): every business-9 frame goes through
// the one flash gate, which at stage 0 passes only the empty reads 1, 2, 11 and the exact size query.
// Runs the unchanged phone policy (ExperimentalOTAFlash.m / ExperimentalOTAFeed.m, adapted by test.py
// exactly like ios1021-download-guard) against full-profile host info. No device, network or signing.
// Optional argv: <Runner> <Info.plist> of that host also checks the real image.
//
// test.py builds this file in every guard flag set and requires the same sweep= digest from each:
// the stage-0 refusal must not depend on build flags. Near-miss full hosts (wrong build, wrong image)
// take the same gate and print the same sweep; their authorization is refused. The authorized gate
// itself is run by the tmg4-wizard and flash-sequence-1021 groups.
#import "TMG4WizardHost.h"
#import "FullHostFixture.h"
#import "HostCompatibility.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "DownloadOnlySafety.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
#if TIO_WIRE_LOG
#import "WireLogGuardHarness.h" // the sweep runs through the wire log; its digest must not change
#endif
static NSString *Home;
static NSTimeInterval Now=100;
static NSDictionary *Prefs,*Host;
static const struct mach_header *Image;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return Now;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
const struct mach_header *TMG4MainImage(void){return Image;}
BOOL TDPPhonePauseForOTA(void){return YES;}
#if TIO_DISPLAY_PHONE
#import "AppBridge.h"
@implementation TAPPhoneBridge
+ (instancetype)shared{return nil;}
- (void)query{}
- (void)install:(NSDictionary *)package{}
- (void)operate:(unsigned)op slot:(unsigned)slot expected:(NSDictionary *)target{}
- (void)observe:(NSDictionary *)event{}
@end
void TAPObserveEvent(NSDictionary *event){}
#endif
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(NSUInteger type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static NSDictionary *Call(id business,id payload){return @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload}};}
static BOOL Allowed(id payload,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":payload}});}
static NSUInteger Checked;
// Type 4 {Mode:1..4} covers the forced update page's {Mode:4}; OtaSize covers the exact size query and a wrong size.
static NSArray *Bodies(void){return @[NSNull.null,@{},@{@"Mode":@1},@{@"Mode":@2},@{@"Mode":@3},@{@"Mode":@4},@{@"OtaSize":@1},@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},@{@"OtaSize":@(TIO_FW_ZIP_BYTES+1)},@{@"OtaVersion":@"Strix OS 1.0.5.5"},@[]];}
static NSArray *WideIds(void){return @[@265,@521,@0x109,@65545,@0x10009,@256,@0x100000009ULL,@(-247),@(-1),@9.0,@265.0,@9.5,@YES,@NO,[NSNumber numberWithShort:265],@0x7fffff09,@(UINT32_MAX)];}
static NSArray *WidePayloads(void){NSMutableArray *a=[NSMutableArray arrayWithObject:Frame(1,nil,nil)];for(NSNumber *mode in @[@1,@2,@3,@4])[a addObject:Frame(4,@{@"Mode":mode},nil)];[a addObject:Frame(2,nil,nil)];[a addObject:Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil)];return a;}
// One character per call, in a fixed order: '1' blocked, '0' passed.
static NSString *Sweep(void){
    NSMutableString *bits=[NSMutableString new];
    for(NSUInteger t=0;t<256;t++)for(id json in Bodies())for(NSData *binary in @[(id)NSNull.null,[NSData dataWithBytes:"x" length:1]]){
        id j=json==NSNull.null?nil:json;NSData *b=binary==(id)NSNull.null?nil:binary;
        for(NSString *peer in @[@"fixture-peer",@""])[bits appendString:Allowed(Frame(t,j,b),peer)?@"0":@"1"];
        [bits appendString:Allowed(@{@"data":Frame(t,j,b)},@"fixture-peer")?@"0":@"1"];
    }
    NSData *query=Frame(1,nil,nil);
    NSArray *calls=@[
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@"9",@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9.5,@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@[]},
        @{@"method":@"rayneonet_sendMessage"},
        @{@"arguments":@{@"businessId":@9,@"payload":query}},
        @{@"method":@1,@"arguments":@{@"businessId":@9,@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":[NSData data]}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":@"text"}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@20,@"payload":Frame(4,@{@"Mode":@2},nil)}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@255,@"payload":Frame(4,@{@"Mode":@4},nil)}},
        @{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}},
        @{@"method":@"rayneonet_startOta",@"arguments":@{}},
        @{@"method":@"rayneonet_upgrade",@"arguments":@{}},
        @{@"method":@"rayneonet_connect",@"arguments":@{}},
    ];
    for(id call in calls)[bits appendString:TIOOTAFlashBlockCall(call)?@"1":@"0"];
    for(id business in WideIds())for(NSData *payload in WidePayloads())[bits appendString:TIOOTAFlashBlockCall(Call(business,payload))?@"1":@"0"];
    return bits;
}
static NSString *Digest(NSString *s){
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];uint8_t h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);
    NSMutableString *x=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[x appendFormat:@"%02x",h[i]];return x;
}
// At stage 0: business 9 passes only the empty reads 1, 2, 11 and the exact size query; nothing else.
static void Stage0Rules(void){
    assert(TIOOTAFullHost());assert(!TIOOTADownloadOnlyHost());assert([TIOOTAFlashStatus()[@"stage"] intValue]==0);
    for(NSUInteger t=0;t<256;t++)for(id json in Bodies())for(NSData *binary in @[(id)NSNull.null,[NSData dataWithBytes:"x" length:1]]){
        id j=json==NSNull.null?nil:json;NSData *b=binary==(id)NSNull.null?nil:binary;
        BOOL read=(t==1||t==2||t==11)&&(!j||[j isEqual:@{}])&&!b;
        BOOL size=t==3&&[j isEqual:@{@"OtaSize":@(TIO_FW_ZIP_BYTES)}]&&!b;
        for(NSString *peer in @[@"fixture-peer",@"other-peer",@""])assert(Allowed(Frame(t,j,b),peer)==(read||size));
        assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":Frame(t,j,b)}})==!(read||size));
        Checked++;
    }
    // Named: type 4 Mode 1..4 (4 is the forced page's start), and the version, manifest and slice frames.
    for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
    assert(!Allowed(Frame(4,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil),@"fixture-peer"));
    assert(!Allowed(Frame(6,@[],nil),@"fixture-peer"));assert(!Allowed(Frame(7,@{@"Name":@"nuttx_ap.bin",@"Start":@0,@"Size":@1},[NSData dataWithBytes:"x" length:1]),@"fixture-peer"));
    assert(Allowed(Frame(1,nil,nil),@"fixture-peer")&&Allowed(Frame(2,nil,nil),@"fixture-peer")&&Allowed(Frame(11,nil,nil),@"fixture-peer"));
    assert(Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),@"fixture-peer"));
    assert(!Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES),@"Mode":@2},nil),@"fixture-peer"));
    assert(!Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},[NSData dataWithBytes:"x" length:1]),@"fixture-peer"));
    // Malformed calls are refused; non-OTA business ids pass untouched.
    for(id payload in @[[NSData data],[NSData dataWithBytes:"\x08\x01" length:2],@"text",@{},NSNull.null])assert(!Allowed(payload,@"fixture-peer"));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@"9",@"payload":Frame(1,nil,nil)}}));
    assert(TIOOTAFlashBlockCall(@{@"arguments":@{@"businessId":@9,@"payload":Frame(1,nil,nil)}}));
    assert(!TIOOTAFlashBlockCall(Call(@20,Frame(4,@{@"Mode":@2},nil))));assert(!TIOOTAFlashBlockCall(Call(@255,Frame(4,@{@"Mode":@4},nil))));
    // G4: no id that wraps to 9 (or is not a plain byte) gets past, not even with a read.
    for(id business in WideIds())for(NSData *payload in WidePayloads()){assert(TIOOTAFlashBlockCall(Call(business,payload)));Checked++;}
    // Un-scoped sendFile and OTA/upgrade-named methods stay refused.
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_startOta",@"arguments":@{}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_upgrade",@"arguments":@{}}));
}
// The dry-run bookkeeping (preparation-status.json flashGate.refusedFrames / lastRefusedFrame): each refused
// business-9 call is counted and described (type, key names, Mode, OtaSize, OtaVersion cut to 64 characters,
// manifest rows, binary length, stage, host kind); other calls are not counted; the verdicts stay the same.
// With the wire log on, the call runs through the hook's guard stage (MethodHookStages.h), which notes the
// refusal itself; without it, the test notes it as that stage would. The counts are the same either way.
static BOOL Refuse(NSDictionary *call){
    BOOL blocked=TIOOTAFlashBlockCall(call);
#if !TIO_WIRE_LOG
    if(blocked)TIOOTAFlashNoteRefused(call);
#endif
    return blocked;
}
static void RefusedNote(void){
    NSUInteger before=[TIOOTAFlashStatus()[@"refusedFrames"] unsignedIntegerValue];
    NSDictionary *mode=Call(@9,Frame(4,@{@"Mode":@2},nil));assert(Refuse(mode));
    NSDictionary *s=TIOOTAFlashStatus(),*n=s[@"lastRefusedFrame"];assert([s[@"refusedFrames"] unsignedIntegerValue]==before+1);
    assert([n isEqual:(@{@"type":@4,@"parsed":@YES,@"stage":@0,@"downloadOnlyHost":@NO,@"binaryBytes":@0,@"keys":@[@"Mode"],@"Mode":@2})]);
    NSString *longVersion=[@"Strix OS 1.0.6.11 " stringByPaddingToLength:100 withString:@"x" startingAtIndex:0];
    assert(Refuse(Call(@9,Frame(5,@{@"OtaVersion":longVersion,@"Extra":@1},[NSData dataWithBytes:"ab" length:2]))));
    n=TIOOTAFlashStatus()[@"lastRefusedFrame"];assert([n[@"type"] isEqual:@5]&&[n[@"OtaVersion"] isEqual:[longVersion substringToIndex:64]]&&[n[@"keys"] isEqual:(@[@"Extra",@"OtaVersion"])]&&[n[@"binaryBytes"] isEqual:@2]&&!n[@"Mode"]);
    assert(Refuse(Call(@9,Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES),@"Mode":@2},nil))));
    n=TIOOTAFlashStatus()[@"lastRefusedFrame"];assert([n[@"type"] isEqual:@3]&&[n[@"OtaSize"] isEqual:@(TIO_FW_ZIP_BYTES)]&&[n[@"Mode"] isEqual:@2]);
    assert(Refuse(Call(@9,Frame(6,@[@{},@{},@{}],nil))));n=TIOOTAFlashStatus()[@"lastRefusedFrame"];
    assert([n[@"type"] isEqual:@6]&&[n[@"rows"] isEqual:@3]&&!n[@"keys"]);
    assert(Refuse(Call(@9,[NSData data])));n=TIOOTAFlashStatus()[@"lastRefusedFrame"];assert([n[@"type"] isEqual:@(-1)]&&[n[@"parsed"] isEqual:@NO]&&!n[@"binaryBytes"]);
    NSUInteger counted=[TIOOTAFlashStatus()[@"refusedFrames"] unsignedIntegerValue];assert(counted==before+5);
    // Not counted: an allowed read, a call to another business id, a refused call that is not business 9, junk.
    assert(!Refuse(Call(@9,Frame(1,nil,nil)))&&!Refuse(Call(@20,Frame(4,@{@"Mode":@2},nil))));
    assert(Refuse(@{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}}));
    TIOOTAFlashNoteRefused(Call(@20,Frame(4,@{@"Mode":@2},nil)));TIOOTAFlashNoteRefused(nil);TIOOTAFlashNoteRefused(@"x");
    assert([TIOOTAFlashStatus()[@"refusedFrames"] unsignedIntegerValue]==counted);
    assert(TIOOTAFlashBlockCall(mode)&&!Allowed(Frame(4,@{@"Mode":@2},nil),@"fixture-peer")&&Allowed(Frame(1,nil,nil),@"fixture-peer"));
}
// The named transfer frames refused and the reads passed (the cheap check, for the host variants).
static void Quick(void){
    for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
    assert(!Allowed(Frame(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil),@"fixture-peer")&&!Allowed(Frame(6,@[],nil),@"fixture-peer"));
    assert(!Allowed(Frame(7,@{@"Name":@"nuttx_ap.bin",@"Start":@0,@"Size":@1},[NSData dataWithBytes:"x" length:1]),@"fixture-peer"));
    assert(Allowed(Frame(1,nil,nil),@"fixture-peer")&&Allowed(Frame(2,nil,nil),@"fixture-peer")&&Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),@"fixture-peer"));
}
static void AuthorizeRefused(NSString *reason){
    NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e));assert(e);assert([e.localizedDescription isEqual:TIOText(reason)]);
    NSDictionary *s=TIOOTAFlashStatus();assert([s[@"stage"] intValue]==0);assert(![s[@"authorized"] boolValue]);
}
static NSString *const NoFeed=@"未确认本机下载来源与健康检查，未授权。";
static NSString *const NotHost=@"ota.authorize.host";
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1||argc==3);
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *full=TFHFullInfo();
    Image=FakeImage(TFH_UUID);
    if(argc==3){
        NSMutableDictionary *real=[[NSDictionary dictionaryWithContentsOfFile:@(argv[2])] mutableCopy];assert(real);
        NSData *runner=[NSData dataWithContentsOfFile:@(argv[1]) options:NSDataReadingMappedIfSafe error:nil];assert(runner.length>4096);
        const struct mach_header *h=runner.bytes;
        // The stock plist is the download-only profile; the packager's profile marker makes it the full one.
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1021-download"]);
        // Near-miss and retired markers leave it download-only.
        real[@"TIOHostProfile"]=TFH_NEAR_PROFILE;
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1021-download"]);assert(!TIOHostFullImageMatches(h,real));
        real[@"TIOHostProfile"]=@"ios1011";
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1021-download"]);assert(!TIOHostFullImageMatches(h,real));
        real[@"TIOHostProfile"]=TFH_PROFILE;
        assert([TIOHostProfileFor(h,real) isEqual:TFH_PROFILE]);assert(TIOHostFullImageMatches(h,real));
        full=real;Image=h;
    }
    Host=full;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    assert(TFH_HOST_MATCHES(Host)&&[TIOOTAHostProfile(Host) isEqual:TFH_PROFILE]);
    assert(!TIOOTADownloadOnlyHost()&&TIOOTAFullHost()&&[TIOOTAFlashStatus()[@"fullHost"] boolValue]);
    // A stale routing key left by a retired build changes nothing: the profile marker decides.
    NSMutableDictionary *stale=[full mutableCopy];stale[@"TIOExperimentalOTAQueryRouting"]=@"ios107-tmg2-loopback-flash-gated";assert([TIOOTAHostProfile(stale) isEqual:TFH_PROFILE]);
#if TIO_OTA_FLASH_ENABLED
    assert(TIOOTAFlashBuild());
#else
    assert(!TIOOTAFlashBuild());
#endif
    // Stage 0 in every flag set, before and after the transport hook is ready.
    NSString *sweep=Sweep();
    Stage0Rules();AuthorizeRefused(NoFeed);RefusedNote();
    TIOOTARecordTransportHookReady();Stage0Rules();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NoFeed);
    // A version read changes nothing at stage 0.
    TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":@"Strix OS 1.0.5.12",@"OtaValidationConfirmed":@YES},nil)}});
    Quick();AuthorizeRefused(NoFeed);assert([Sweep() isEqual:sweep]);
    // Near-miss full hosts (this profile marker with another build, bundle or app version, or on another
    // image): the same gate at stage 0, the same sweep, and authorization refused at the host check.
    const struct mach_header *pinned=Image;
    for(NSArray *kv in @[@[@"CFBundleVersion",TFH_NEXT_BUILD],@[@"CFBundleShortVersionString",TFH_NEAR_VERSION],@[@"CFBundleIdentifier",@"com.rayneo.venus"],@[@"CFBundleVersion",@1]]){
        NSMutableDictionary *m=[full mutableCopy];m[kv[0]]=kv[1];Host=m;
        assert(TIOOTAFullHost()&&!TFH_HOST_MATCHES(Host));Quick();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NotHost);
    }
    Host=full;Image=FakeImage(@"00000000-0000-0000-0000-000000000001");
    assert(TIOOTAFullHost()&&TFH_HOST_MATCHES(Host)&&!TIOHostFullImageMatches(Image,Host));Quick();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NotHost);
    Image=NULL;assert(TIOOTAFullHost());Quick();AuthorizeRefused(NotHost);
    Image=pinned;
    // The marker-less image is the download-only host (so is this image with a near-miss profile
    // marker): only the version query passes.
    NSMutableDictionary *unmarked=[full mutableCopy];[unmarked removeObjectForKey:@"TIOHostProfile"];
    for(NSDictionary *h in @[unmarked,({NSMutableDictionary *m=[full mutableCopy];m[@"TIOHostProfile"]=@"ios1021-download";m;}),
        ({NSMutableDictionary *m=[unmarked mutableCopy];m[@"TIOHostProfile"]=TFH_NEAR_PROFILE;m;})]){
        Host=h;assert(TIOOTADownloadOnlyHost()&&!TIOOTAFullHost());
        assert(Allowed(Frame(1,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(2,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),@"fixture-peer"));
        for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
        AuthorizeRefused(NotHost);
    }
    // An app that is not the supported host (another version, no markers, another image) is neither host:
    // a flash build refuses business 9 but the empty version query, any other build blocks nothing.
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":TFH_NEAR_VERSION,@"CFBundleVersion":TFH_NEAR_BUILD};
    Image=FakeImage(@"00000000-0000-0000-0000-000000000004");
    assert(!TIOOTAFullHost()&&!TIOOTADownloadOnlyHost());AuthorizeRefused(NotHost);
    assert(Allowed(Frame(1,nil,nil),@"fixture-peer"));
    assert(Allowed(Frame(4,@{@"Mode":@2},nil),@"fixture-peer")==!TIOOTAFlashBuild());assert(Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),@"fixture-peer")==!TIOOTAFlashBuild());
    Host=full;Image=pinned;
    // The export panel's guard row: no flash authorization open, so the gate row is locked.
    assert(![TIOOTAFlashStatus()[@"authorized"] boolValue]);
    assert([TIOFirmwareExportSafetyModelFull(YES,YES,[TIOOTAFlashStatus()[@"authorized"] boolValue],Prefs)[@"guardKey"] isEqual:@"fwexport.guard.locked"]);
    assert([TIOFirmwareExportSafetyModelFull(YES,NO,NO,Prefs)[@"guardKey"] isEqual:@"fwexport.guard.waiting"]);
    NSLog(@"PASS: " TFH_NAME " full host: stage 0 in every flag set, %lu frame shapes, only the empty reads and the exact size query pass; type 4 Mode 1-4 and frames 5-7 refused; near-miss full hosts take the same gate and are refused authorization; flash build %s; sweep=%@%s",
        (unsigned long)Checked,TIOOTAFlashBuild()?"on":"off",Digest(sweep),argc==3?"; real " TFH_NAME " Runner profile":"");
}return 0;}
