// Download-only 1.0.11/259 host: the business-9 guard is the only thing standing
// between the stock app and an OTA session. Runs the unchanged phone policy
// (ExperimentalOTAFlash.m / ExperimentalOTAFeed.m, adapted by test.py exactly like
// tmg4-wizard) against 1.0.11 host info. No device, network or signing.
// Optional argv: <1.0.11 Runner> <1.0.11 Info.plist> also checks the real image.
//
// G1: test.py builds this file in several TIO_* flag sets (all of
// TIO_OTA_FLASH_ENABLED / TIO_DISPLAY_FLASH / TIO_DISPLAY_PHONE, partial sets, and
// none of them) and requires
// the same sweep= digest from each: the refusal must not depend on build flags.
#import "TMG4WizardHost.h"
#import "HostCompatibility.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "DownloadOnlySafety.h"
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
// Host stand-in for the UIKit phone bridge; only TIOOTAFlashAuthorize reads it,
// after the host check has already refused.
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
// A minimal main executable header carrying only LC_UUID (one buffer per call, kept for the run).
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(NSUInteger type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static BOOL Allowed(id payload,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":payload}});}
static NSUInteger Checked;
// Every frame body in the sweep. Type 4 {Mode:1..4} covers the start the
// mandatory update page auto-sends ({Mode:4}) after a forced cloud reply.
static NSArray *Bodies(void){return @[NSNull.null,@{},@{@"Mode":@1},@{@"Mode":@2},@{@"Mode":@3},@{@"Mode":@4},@{@"OtaSize":@1},@{@"OtaVersion":@"Strix OS 1.0.5.5"},@[]];}
// G4 businessId width: 9+256k aliases (265, 521, 0x109, 65545), above UINT32_MAX,
// negatives (-247 is 9 mod 256), floats and bools. Each must be refused with any payload.
static NSArray *WideIds(void){return @[@265,@521,@0x109,@65545,@0x10009,@256,@0x100000009ULL,@(-247),@(-1),@9.0,@265.0,@9.5,@YES,@NO,[NSNumber numberWithShort:265],@0x7fffff09,@(UINT32_MAX)];}
static NSArray *WidePayloads(void){NSMutableArray *a=[NSMutableArray arrayWithObject:Frame(1,nil,nil)];for(NSNumber *mode in @[@1,@2,@3,@4])[a addObject:Frame(4,@{@"Mode":mode},nil)];[a addObject:Frame(2,nil,nil)];return a;}
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
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@YES,@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@[]},
        @{@"method":@"rayneonet_sendMessage"},
        @{@"arguments":@{@"businessId":@9,@"payload":query}},
        @{@"method":@1,@"arguments":@{@"businessId":@9,@"payload":query}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":[NSData data]}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":@"text"}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":NSNull.null}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@20,@"payload":Frame(4,@{@"Mode":@2},nil)}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@22,@"payload":Frame(4,@{@"Mode":@4},nil)}},
        @{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@255,@"payload":Frame(4,@{@"Mode":@4},nil)}},
        @{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}},
        @{@"method":@"rayneonet_startOta",@"arguments":@{}},
        @{@"method":@"rayneonet_upgrade",@"arguments":@{}},
        @{@"method":@"rayneonet_connect",@"arguments":@{}},
        @{@"method":@"rayneonet_disconnect",@"arguments":@{}},
    ];
    for(id call in calls)[bits appendString:TIOOTAFlashBlockCall(call)?@"1":@"0"];
    // G4: ids the bridge's UInt8(truncating:) would send as business 9, plus other non-ids.
    for(id business in WideIds())for(NSData *payload in WidePayloads())[bits appendString:TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload}})?@"1":@"0"];
    return bits;
}
static NSString *Digest(NSString *s){
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];uint8_t h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);
    NSMutableString *x=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[x appendFormat:@"%02x",h[i]];return x;
}
// Every business-9 frame shape is refused except the exact empty version query.
static void OnlyVersionQueryPasses(void){
    assert(TIOOTADownloadOnlyHost());
    NSData *query=Frame(1,nil,nil);assert(TIOOTAIsEmptyVersionQuery(query));
    for(NSString *peer in @[@"fixture-peer",@"other-peer",@""]){assert(Allowed(query,peer));assert(Allowed(@{@"data":query},peer));}
    for(NSUInteger t=0;t<256;t++)for(id json in Bodies())for(NSData *binary in @[(id)NSNull.null,[NSData dataWithBytes:"x" length:1]]){
        id j=json==NSNull.null?nil:json;NSData *b=binary==(id)NSNull.null?nil:binary;
        BOOL exact=t==1&&!j&&!b;
        assert(Allowed(Frame(t,j,b),@"fixture-peer")==exact);
        // The pure refusal and the dispatching entry point agree on every shape.
        assert(TIOOTADownloadOnlyBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"payload":Frame(t,j,b)}})==!exact);
        Checked++;
    }
    // The flows that matter, named: OTA start (type 4, Mode 1..4; 4 is the forced page), size, version, manifest, slice, idle.
    for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Allowed(Frame(4,@{@"Mode":mode},nil),@"fixture-peer"));
    assert(!Allowed(Frame(4,nil,nil),@"fixture-peer"));
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
    assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@255,@"payload":Frame(4,@{@"Mode":@4},nil)}}));
    // G4: no id that wraps to 9 (or is not a plain byte) gets past, not even with the version query.
    for(id business in WideIds())for(NSData *payload in WidePayloads()){
        NSDictionary *call=@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload}};
        assert(TIOOTAFlashBlockCall(call));assert(TIOOTADownloadOnlyBlockCall(call));Checked++;
    }
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
// G3: the panel's Auto Update reading agrees with the authorization check's parser.
static void AutoUpdateAgrees(void){
    NSArray *cases=@[@{},@{@"a_ota_firmware_auto_update":@NO},@{@"a_ota_firmware_auto_update":@"false"},@{@"a_ota_firmware_auto_update":@YES},
        @{@"a_ota_firmware_auto_update":@"true"},@{@"a_ota_firmware_auto_update":@0},@{@"a_ota_firmware_auto_update":@"0"},
        @{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@YES},@{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@"false"},@{@"other":@YES}];
    for(NSDictionary *p in cases)assert((TIOAutoUpdateReadingFor(p)==TIOAutoUpdateReadingOff)==TIOOTAAutoUpdateDisabled(p));
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1||argc==3);
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSDictionary *d=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011-download"};
    Image=FakeImage(@"22724C97-2EF9-388D-8E6A-6E051855A555");
    NSData *runner=nil;
    if(argc==3){
        NSMutableDictionary *real=[[NSDictionary dictionaryWithContentsOfFile:@(argv[2])] mutableCopy];assert(real);
        assert([real[@"CFBundleShortVersionString"] isEqual:@"1.0.11"]&&[real[@"CFBundleVersion"] isEqual:@"259"]);
        runner=[NSData dataWithContentsOfFile:@(argv[1]) options:NSDataReadingMappedIfSafe error:nil];assert(runner.length>4096);
        const struct mach_header *h=runner.bytes;
        assert([TIOHostProfileFor(h,real) isEqual:@"ios1011-download"]);assert(TIOHostDownloadOnlyImageMatches(h,real));
        assert(!TIOHostImageMatches(h,real));assert(!TIOHostExpectedUUID(real));
        NSMutableDictionary *as107=[real mutableCopy];as107[@"CFBundleShortVersionString"]=@"1.0.7";as107[@"CFBundleVersion"]=@"230";assert(!TIOHostProfileFor(h,as107));
        real[@"TIOHostProfile"]=@"ios1011-download";d=real; // what the packager adds
        Image=h;
    }
    Host=d;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    assert(TIOOTADownloadOnlyHost());
    // (b) never the 1.0.7 OTA host, even with a stale 1.0.7 routing marker.
    assert(!TIOOTA107HostMatches(Host));
    NSMutableDictionary *stale=[d mutableCopy];stale[@"TIOExperimentalOTAQueryRouting"]=@"ios107-tmg2-loopback-flash-gated";assert(!TIOOTA107HostMatches(stale));
    // (d) the flash path is off; whether it is compiled in depends on the flags, the refusal does not.
#if TIO_OTA_FLASH_ENABLED && TIO_DISPLAY_FLASH
    assert(TIOOTAFlashBuild());
#else
    assert(!TIOOTAFlashBuild());
#endif
    assert(!TIOOTAFlashProtected());
    // (b) feed never starts and preparation is refused.
    TIOStartExperimentalOTAFeedIfMarked();
    NSDictionary *feed=TIOExperimentalOTAFeedStatus();
    assert(![feed[@"running"] boolValue]);assert(![feed[@"bootstrapEligible"] boolValue]);assert([feed[@"startAttempts"] intValue]==0);
    // Without the flash build the feed returns before its host check and records no reason.
    assert([feed[@"reason"] isEqual:TIOOTAFlashBuild()?TIOText(@"1.0.7 实验来源宿主版本/UUID/标记不匹配"):@""]);
    NSError *e=nil;assert(!TIOBeginExperimentalOTAPreparation(&e));assert(e);
    // (a) before and after the transport hook is ready.
    NSString *sweep=Sweep();
    OnlyVersionQueryPasses();TIOOTARecordTransportHookReady();assert(!TIOOTAFlashProtected());OnlyVersionQueryPasses();
    assert([Sweep() isEqual:sweep]);
    // (c) authorization fails for the host reason even when everything else is in place.
    Refused();
    TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":@"Strix OS 1.0.5.5",@"OtaValidationConfirmed":@YES},nil)}});
    Refused();
    Host=stale;Refused();OnlyVersionQueryPasses();assert([Sweep() isEqual:sweep]);Host=d;
    // Either signal alone selects the refusal: the packager's marker with an unknown
    // image, or the pinned image without the marker.
    const struct mach_header *pinned=Image;
    Image=FakeImage(@"00000000-0000-0000-0000-000000000001");OnlyVersionQueryPasses();assert([Sweep() isEqual:sweep]);
    NSMutableDictionary *unmarked=[d mutableCopy];[unmarked removeObjectForKey:@"TIOHostProfile"];
    Host=unmarked;assert(!TIOOTADownloadOnlyHost());
    Image=pinned;OnlyVersionQueryPasses();assert([Sweep() isEqual:sweep]);Host=d;
    assert(!Allowed(Frame(4,@{@"Mode":@4},nil),@"fixture-peer"));OnlyVersionQueryPasses();
    AutoUpdateAgrees();
    // Control: the harness does discriminate. The 1.0.7 host takes the unchanged
    // legacy branch: with the flash build only the empty reads 1, 2 and 11 pass an
    // unarmed gate (the phone-only build reads the same three); without it the
    // legacy path guards nothing (as before G1).
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    Image=FakeImage(@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B");
    assert(TIOOTA107HostMatches(Host));assert(!TIOOTADownloadOnlyHost());assert(![Sweep() isEqual:sweep]);
    for(NSUInteger t=0;t<256;t++)for(id json in Bodies()){
        id j=json==NSNull.null?nil:json;(void)j;
#if TIO_OTA_FLASH_ENABLED
        assert(TIOOTAFlashProtected());
        assert(Allowed(Frame(t,j,nil),@"fixture-peer")==((t==1||t==2||t==11)&&(!j||[j isEqual:@{}])));
#else
        assert(!TIOOTAFlashProtected());assert(Allowed(Frame(t,j,nil),@"fixture-peer"));
#endif
    }
#if TIO_OTA_FLASH_ENABLED
    // G4 deliberately makes the guarded 1.0.7 path stricter too: wide ids are malformed there as well,
    // while a plain non-9 byte still passes untouched.
    for(id business in WideIds())for(NSData *payload in WidePayloads())assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload}}));
    assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@255,@"payload":Frame(4,@{@"Mode":@4},nil)}}));
#endif
    Host=d;Image=pinned;assert(!Allowed(Frame(2,nil,nil),@"fixture-peer"));
    NSLog(@"PASS: 1.0.11 download-only guard: %lu frame shapes, only the empty version query passes; type 4 Mode 1-4 refused; feed not started; authorization refused; flash build %s; sweep=%@%s",
        (unsigned long)Checked,TIOOTAFlashBuild()?"on":"off",Digest(sweep),argc==3?"; real 1.0.11 Runner profile":"");
}return 0;}
