// Full 1.0.11/259 host (profile ios1011, C15): TMG flashing is disarmed until the
// owner arms it on this install. Runs the unchanged phone policy
// (ExperimentalOTAFlash.m / ExperimentalOTAFeed.m, adapted by test.py exactly like
// ios1011-guard) against full-profile 1.0.11 host info. No device, network or signing.
// Optional argv: <1.0.11 Runner> <1.0.11 Info.plist> also checks the real image.
//
// test.py builds this file in every ios1011-guard flag set and requires the same
// disarmed sweep= digest from each: the disarmed refusal must not depend on build
// flags. Armed (only possible in a flash build), the business-9 sweep must equal the
// 1.0.7 host's in the same binary; disarming must bring back the disarmed sweep.
// The authorized gate itself (Mode 2 only, forced-page Mode 4 refused, disarm refused
// mid-transfer) is run by the tmg4-wizard-1011 group.
#import "TMG4WizardHost.h"
#import "HostCompatibility.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "DownloadOnlySafety.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
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
// The addon image's LC_UUID, read independently of the policy (the arm record names it).
static NSString *InstallID(void){
    Dl_info info;assert(dladdr((const void *)&TIOOTAArmRequired,&info)&&info.dli_fbase);
    const struct mach_header_64 *h=info.dli_fbase;assert(h->magic==MH_MAGIC_64);const uint8_t *p=(const uint8_t *)(h+1);
    for(uint32_t i=0;i<h->ncmds;i++){const struct load_command *c=(const void *)p;if(c->cmd==LC_UUID)return [[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString];p+=c->cmdsize;}
    assert(0&&"test binary has no LC_UUID");return nil;
}
static NSString *const ArmKey=@"otaFlashArmRecord.ios1011";
// While disarmed: business 9 passes only the empty reads 1, 2, 11 and the exact size query; nothing else.
static void DisarmedRules(void){
    assert(TIOOTAArmRequired());assert(!TIOOTADownloadOnlyHost());assert(![TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]);
    for(NSUInteger t=0;t<256;t++)for(id json in Bodies())for(NSData *binary in @[(id)NSNull.null,[NSData dataWithBytes:"x" length:1]]){
        id j=json==NSNull.null?nil:json;NSData *b=binary==(id)NSNull.null?nil:binary;
        BOOL read=(t==1||t==2||t==11)&&(!j||[j isEqual:@{}])&&!b;
        BOOL size=t==3&&[j isEqual:@{@"OtaSize":@(TIO_FW_ZIP_BYTES)}]&&!b;
        for(NSString *peer in @[@"fixture-peer",@"other-peer",@""])assert(Allowed(Frame(t,j,b),peer)==(read||size));
        assert(TIOOTADisarmedBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":Frame(t,j,b)}})==!(read||size));
        assert(TIOOTADisarmedReadAllowed(Frame(t,j,b))==(read||size));
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
    for(id business in WideIds())for(NSData *payload in WidePayloads()){assert(TIOOTAFlashBlockCall(Call(business,payload)));assert(TIOOTADisarmedBlockCall(Call(business,payload)));Checked++;}
    // Un-scoped sendFile and OTA/upgrade-named methods stay refused.
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_startOta",@"arguments":@{}}));
    assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_upgrade",@"arguments":@{}}));
}
// The named transfer frames refused and the reads passed (the cheap check, for the many record variants).
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
static NSString *const NotArmed=@"本机 TMG 刷写尚未启用；先在向导中启用，未授权。";
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1||argc==3);
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",
        @"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    Image=FakeImage(@"22724C97-2EF9-388D-8E6A-6E051855A555");
    if(argc==3){
        NSMutableDictionary *real=[[NSDictionary dictionaryWithContentsOfFile:@(argv[2])] mutableCopy];assert(real);
        NSData *runner=[NSData dataWithContentsOfFile:@(argv[1]) options:NSDataReadingMappedIfSafe error:nil];assert(runner.length>4096);
        const struct mach_header *h=runner.bytes;
        // The stock plist is the download-only profile; the packager's two markers make it the full one.
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1011-download"]);
        real[@"TIOHostProfile"]=@"ios1011";real[@"TIOExperimentalOTAQueryRouting"]=TIO_OTA_1011_ROUTING_MARKER;
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1011"]);assert(TIOHostFullImageMatches(h,real));assert(!TIOHostImageMatches(h,real));
        full=real;Image=h;
    }
    Host=full;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    NSMutableDictionary *store=TMG4ArmStore();[store removeAllObjects];
    assert(TIOOTA1011HostMatches(Host)&&!TIOOTA107HostMatches(Host)&&[TIOOTAHostProfile(Host) isEqual:@"ios1011"]);
    assert(!TIOOTADownloadOnlyHost()&&TIOOTAArmRequired()&&!TIOOTAFlashArmed());
    // A stale 1.0.7 routing marker never makes this the 1.0.7 OTA host.
    NSMutableDictionary *stale=[full mutableCopy];stale[@"TIOExperimentalOTAQueryRouting"]=@"ios107-tmg2-loopback-flash-gated";assert(!TIOOTA107HostMatches(stale)&&!TIOOTAHostProfile(stale));
    // The full host's routing marker makes it an OTA host, so the phone-only flag set has the flash path too.
#if TIO_OTA_FLASH_ENABLED
    assert(TIOOTAFlashBuild());
#else
    assert(!TIOOTAFlashBuild());
#endif
    // Disarmed by default, before and after the transport hook is ready.
    NSString *sweep=Sweep();
    DisarmedRules();AuthorizeRefused(NotArmed);
    TIOOTARecordTransportHookReady();DisarmedRules();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NotArmed);
    // A version read observed while disarmed changes nothing.
    TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":@"Strix OS 1.0.5.5",@"OtaValidationConfirmed":@YES},nil)}});
    Quick();AuthorizeRefused(NotArmed);
    // Malformed or foreign records count as disarmed in every flag set.
    NSString *install=InstallID();
    NSDictionary *good=@{@"v":@1,@"host":@"ios1011",@"install":install,@"armedAt":@1};
    NSMutableArray *bad=[NSMutableArray arrayWithObjects:@"armed",@YES,@[good],@{},NSNull.null,nil];
    for(NSString *k in good){NSMutableDictionary *m=[good mutableCopy];[m removeObjectForKey:k];[bad addObject:m];}
    for(NSArray *kv in @[@[@"v",@2],@[@"v",@"1"],@[@"host",@"ios107"],@[@"host",@"ios1011-download"],@[@"install",@"00000000-0000-0000-0000-000000000001"],@[@"install",@1],@[@"install",install.lowercaseString],@[@"armedAt",@"1"],@[@"extra",@1]]){
        NSMutableDictionary *m=[good mutableCopy];m[kv[0]]=kv[1];[bad addObject:m];
    }
    for(id record in bad){
        store[ArmKey]=record;assert(!TIOOTAFlashArmed());assert(![TIOOTAFlashArmStatus()[@"armed"] boolValue]);
        Quick();AuthorizeRefused(NotArmed);
    }
    [store removeAllObjects];
    // Arm: refused on near-miss hosts, whatever the flags.
    for(NSArray *kv in @[@[@"TIOExperimentalOTAQueryRouting",NSNull.null],@[@"TIOExperimentalOTAQueryRouting",@"ios107-tmg2-loopback-flash-gated"],@[@"CFBundleVersion",@"260"]]){
        NSMutableDictionary *m=[full mutableCopy];if(kv[1]==NSNull.null)[m removeObjectForKey:kv[0]];else m[kv[0]]=kv[1];Host=m;
        NSError *e=nil;assert(!TIOOTAFlashArm(&e)&&[e.localizedDescription isEqual:TIOText(@"只有完整版 1.0.11 宿主需要并允许启用 TMG 刷写；未启用。")]);assert(!store.count);
        // A valid record does not help a near-miss host either: still the disarmed refusal.
        store[ArmKey]=good;assert(TIOOTAArmRequired());assert(![TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]);
        assert(!Allowed(Frame(4,@{@"Mode":@2},nil),@"fixture-peer"));assert(Allowed(Frame(1,nil,nil),@"fixture-peer"));[store removeAllObjects];
    }
    Host=full;const struct mach_header *pinned=Image;Image=FakeImage(@"00000000-0000-0000-0000-000000000001");
    {NSError *e=nil;assert(!TIOOTAFlashArm(&e)&&e);store[ArmKey]=good;assert(![TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]);assert([Sweep() isEqual:sweep]);[store removeAllObjects];}
    Image=pinned;
    // The marker-less 1.0.11 image is the download-only host: arm state plays no part, only the version query passes.
    NSMutableDictionary *unmarked=[full mutableCopy];[unmarked removeObjectForKey:@"TIOHostProfile"];[unmarked removeObjectForKey:@"TIOExperimentalOTAQueryRouting"];
    for(NSDictionary *h in @[unmarked,({NSMutableDictionary *m=[full mutableCopy];m[@"TIOHostProfile"]=@"ios1011-download";m;})]){
        Host=h;store[ArmKey]=good;assert(TIOOTADownloadOnlyHost()&&!TIOOTAArmRequired()&&!TIOOTAFlashArmed());
        assert(Allowed(Frame(1,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(2,nil,nil),@"fixture-peer"));assert(!Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),@"fixture-peer"));
        for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
        NSError *e=nil;assert(!TIOOTAFlashArm(&e));[store removeAllObjects];
    }
    Host=full;
    NSError *armError=nil;BOOL armed=TIOOTAFlashArm(&armError);
    if(TIOOTAFlashBuild()){
        // Explicit arm: one record in the addon's own store, bound to this addon image.
        assert(armed&&!armError);assert(store.count==1);NSDictionary *record=store[ArmKey];
        assert(record.count==4&&[record[@"v"] isEqual:@1]&&[record[@"host"] isEqual:@"ios1011"]&&[record[@"install"] isEqual:install]&&[record[@"armedAt"] isKindOfClass:NSNumber.class]);
        NSDictionary *status=TIOOTAFlashArmStatus();assert([status[@"armRequired"] boolValue]&&[status[@"armed"] boolValue]&&[status[@"armedForTransfer"] boolValue]&&status[@"armedAt"]);
        assert([TIOOTAFlashStatus()[@"armed"] boolValue]);
        // Armed, the business-9 rule is the 1.0.7 host's, bit for bit, in this flag set.
        NSString *armedSweep=Sweep();
        Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
        Image=FakeImage(@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B");
        assert(!TIOOTAArmRequired()&&![TIOOTAFlashArmStatus()[@"armed"] boolValue]);
        NSString *sweep107=Sweep();assert([armedSweep isEqual:sweep107]);
        Host=full;Image=pinned;
        // An unauthorized gate still refuses every start, the forced page's Mode 4 included.
        for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
        // Authorization now gets past the arm step and stops at the next 1.0.7 check (no local feed here).
        AuthorizeRefused(@"未确认本机下载来源与健康检查，未授权。");
        // Arming twice keeps one record; disarm brings back the disarmed refusal.
        assert(TIOOTAFlashArm(nil)&&store.count==1);
        assert(TIOOTAFlashDisarm());assert(!store.count&&!TIOOTAFlashArmed());
        DisarmedRules();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NotArmed);
        assert(TIOOTAFlashDisarm());
        printf("armed sweep equals the 1.0.7 sweep (%s)\n",Digest(armedSweep).UTF8String);
    }else{
        // No flash build: arming is refused, and even a valid record leaves the disarmed refusal.
        assert(!armed&&[armError.localizedDescription isEqual:TIOText(@"没有试刷构建与发送保护；未开放。")]);assert(!store.count);
        store[ArmKey]=good;assert(TIOOTAFlashArmed());assert(![TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]);
        DisarmedRules();assert([Sweep() isEqual:sweep]);AuthorizeRefused(NotArmed);
        assert(TIOOTAFlashDisarm()&&!store.count);
    }
    // The 1.0.7 host never needs or accepts the arm step.
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    Image=FakeImage(@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B");
    {NSError *e=nil;assert(!TIOOTAArmRequired());assert(!TIOOTAFlashArm(&e)&&e&&!store.count);}
    Host=full;Image=pinned;
    // The export panel's guard row reads the same arm state.
    assert([TIOFirmwareExportSafetyModelFull(YES,TIOOTAFlashArmed(),Prefs)[@"guardKey"] isEqual:@"fwexport.guard.disarmed"]);
    NSLog(@"PASS: 1.0.11 full host: disarmed by default, %lu frame shapes, only the empty reads and the exact size query pass; type 4 Mode 1-4 and frames 5-7 refused; %lu bad arm records refused; arm %s; flash build %s; sweep=%@%s",
        (unsigned long)Checked,(unsigned long)bad.count,TIOOTAFlashBuild()?"then disarm checked":"refused",TIOOTAFlashBuild()?"on":"off",Digest(sweep),argc==3?"; real 1.0.11 Runner profile":"");
}return 0;}
