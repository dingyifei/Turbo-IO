// Edge cases for the full 1.0.11/259 host (profile ios1011, C15) that
// tests/Host1011FullGuardTests.m does not already cover: the profile marker's near
// misses, raw-JSON size queries, frame and payload shapes, businessId types, and arm
// record and store near misses. Runs the unchanged phone policy (ExperimentalOTAFlash.m,
// adapted by test.py exactly like ios1011-full-guard) in the same six TIO_* flag sets;
// every case's verdict goes into sweep=, which must be the same in every set.
// No device, network or signing.
//
// XFAIL: cases the intended rule refuses but the current policy accepts. Each is listed
// with input, expected, actual and the deciding line; it is checked to still fail, and
// when a fix makes it pass the run aborts with XPASS so the case moves into the normal
// list. They are not hidden: the run prints every one.
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
#include <stdio.h>
#include <stdlib.h>
#if TIO_WIRE_LOG
#import "WireLogGuardHarness.h" // every call runs through the wire log; the digest must not change
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
static void Var(NSMutableData *d,uint64_t n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
// A frame whose JSON field carries the given text byte for byte (nil: no JSON field).
static NSData *RawFrame(uint64_t type,NSString *json,NSData *binary){
    NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);
    if(json){NSData *j=[json dataUsingEncoding:NSUTF8StringEncoding];Var(d,26);Var(d,j.length);[d appendData:j];}
    if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}
    return d;
}
static NSData *Frame(uint64_t type,id json){
    return RawFrame(type,json?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:json options:0 error:nil] encoding:NSUTF8StringEncoding]:nil,nil);
}
static NSData *Read1(void){return Frame(1,nil);}
static NSData *Start2(void){return Frame(4,@{@"Mode":@2});}
static NSDictionary *CallWith(NSDictionary *args){return @{@"method":@"rayneonet_sendMessage",@"arguments":args};}
static NSDictionary *Call(id business,id payload){return CallWith(@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload});}
static BOOL Allowed(id payload){return !TIOOTAFlashBlockCall(Call(@9,payload));}

// Every verdict, in order, for the cross-flag-set digest.
static NSMutableString *Bits;
static NSUInteger Cases,XFails;
static NSMutableDictionary<NSString *,NSNumber *> *Areas;
static void Check(const char *area,NSString *name,BOOL actual,BOOL expected){
    [Bits appendString:actual?@"1":@"0"];Cases++;
    NSString *a=@(area);Areas[a]=@(Areas[a].unsignedIntegerValue+1);
    if(actual!=expected){fprintf(stderr,"FAIL [%s] %s: expected %d, actual %d\n",area,name.UTF8String,expected,actual);abort();}
}
// Expected to fail today: actual must still differ from expected, else XPASS aborts.
static void XFail(const char *area,NSString *name,BOOL actual,BOOL expected,const char *decision){
    [Bits appendString:actual?@"1":@"0"];Cases++;XFails++;
    NSString *a=@(area);Areas[a]=@(Areas[a].unsignedIntegerValue+1);
    if(actual==expected){fprintf(stderr,"XPASS [%s] %s: now %d as intended; move it from XFail to Check\n",area,name.UTF8String,actual);abort();}
    printf("XFAIL [%s] %s: expected %d, actual %d (decided at %s)\n",area,name.UTF8String,expected,actual,decision);
}
static NSString *Digest(NSString *s){
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];uint8_t h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);
    NSMutableString *x=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[x appendFormat:@"%02x",h[i]];return x;
}
static NSString *InstallID(void){
    Dl_info info;assert(dladdr((const void *)&TIOOTAArmRequired,&info)&&info.dli_fbase);
    const struct mach_header_64 *h=info.dli_fbase;assert(h->magic==MH_MAGIC_64);const uint8_t *p=(const uint8_t *)(h+1);
    for(uint32_t i=0;i<h->ncmds;i++){const struct load_command *c=(const void *)p;if(c->cmd==LC_UUID)return [[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString];p+=c->cmdsize;}
    assert(0&&"test binary has no LC_UUID");return nil;
}
static NSString *const ArmKey=@"otaFlashArmRecord.ios1011";
static NSString *const PinnedUUID=@"22724C97-2EF9-388D-8E6A-6E051855A555";
static NSDictionary *Full;
static const struct mach_header *Pinned;
static NSDictionary *With(NSDictionary *base,NSString *key,id value){NSMutableDictionary *m=[base mutableCopy];if(value)m[key]=value;else [m removeObjectForKey:key];return m;}
static NSString *Show(id v){
    if(!v)return @"<absent>";
    NSString *s=[NSString stringWithFormat:@"%@<%@>",v,NSStringFromClass([v class])];
    return [[s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\0" withString:@"\\0"];
}

// --- Profile: "ios1011" only for the pinned image AND the exact NSString marker.
static void ProfileCases(void){
    unichar nul[]={'i','o','s','1','0','1','1',0};
    NSArray *misses=@[@"IOS1011",@"Ios1011",@"ios1011 ",@" ios1011",@"ios1011\n",[NSString stringWithCharacters:nul length:8],
        @"ios1O11",@"ｉｏｓ１０１１",@"ios1011​",@"ios1011-full",@"ios10110",@"ios101",@"",@"ios107",
        NSNull.null,@1011,@YES,@[@"ios1011"],@{@"ios1011":@YES},[@"ios1011" dataUsingEncoding:NSUTF8StringEncoding],[NSURL URLWithString:@"ios1011"]];
    for(id marker in misses)for(NSNumber *routing in @[@YES,@NO]){
        Host=With(Full,@"TIOHostProfile",marker);if(!routing.boolValue)Host=With(Host,@"TIOExperimentalOTAQueryRouting",nil);Image=Pinned;
        NSString *n=[NSString stringWithFormat:@"marker %@ routing %@",Show(marker),routing];
        Check("profile",[n stringByAppendingString:@" -> ios1011-download"],[TIOHostProfileFor(Image,Host) isEqual:@"ios1011-download"],YES);
        Check("profile",[n stringByAppendingString:@" not an OTA host"],TIOOTAHostProfile(Host)!=nil,NO);
        Check("profile",[n stringByAppendingString:@" download-only guard"],TIOOTADownloadOnlyHost(),YES);
        Check("profile",[n stringByAppendingString:@" arm not required"],TIOOTAArmRequired(),NO);
        Check("profile",[n stringByAppendingString:@" full features off"],TIOHostFullImageMatches(Image,Host),NO);
        // Download-only rule: only the empty version query passes, whatever record is stored.
        TMG4ArmStore()[ArmKey]=@{@"v":@1,@"host":@"ios1011",@"install":InstallID(),@"armedAt":@1};
        Check("profile",[n stringByAppendingString:@" version query passes"],Allowed(Read1()),YES);
        Check("profile",[n stringByAppendingString:@" battery read refused"],Allowed(Frame(2,nil)),NO);
        Check("profile",[n stringByAppendingString:@" size query refused"],Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)})),NO);
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" arm refused"],TIOOTAFlashArm(NULL),NO);
        Check("profile",[n stringByAppendingString:@" stored record ignored"],TIOOTAFlashArmed(),NO);
        [TMG4ArmStore() removeAllObjects];
    }
    // A mutable string with the same characters is the same marker.
    Host=With(Full,@"TIOHostProfile",[NSMutableString stringWithString:@"ios1011"]);
    Check("profile",@"NSMutableString ios1011 -> ios1011",[TIOHostProfileFor(Pinned,Host) isEqual:@"ios1011"],YES);
    Check("profile",@"NSMutableString ios1011 arm required",TIOOTAArmRequired(),YES);
    // Exact marker on anything but the pinned image: never the ios1011 profile, and still disarmed.
    struct {NSString *name;const struct mach_header *image;} images[]={
        {@"1.0.7 image",FakeImage(@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B")},{@"other image",FakeImage(@"00000000-0000-0000-0000-000000000001")},
        {@"no image",NULL}};
    for(size_t i=0;i<sizeof images/sizeof *images;i++){
        Host=Full;Image=images[i].image;NSString *n=images[i].name;
        Check("profile",[n stringByAppendingString:@" not the ios1011 profile"],[TIOHostProfileFor(Image,Host) isEqual:@"ios1011"],NO);
        Check("profile",[n stringByAppendingString:@" arm required"],TIOOTAArmRequired(),YES);
        Check("profile",[n stringByAppendingString:@" arm refused"],TIOOTAFlashArm(NULL),NO);
        [TMG4ArmStore() removeAllObjects];
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" read passes"],Allowed(Read1()),YES);
    }
    // Info near misses with the exact marker: the profile or the OTA host check fails, arm is refused, disarmed reads stay.
    NSArray *infos=@[@[@"CFBundleVersion",@259],@[@"CFBundleVersion",@"259 "],@[@"CFBundleShortVersionString",@"1.0.11 "],
        @[@"CFBundleShortVersionString",@"1.0.11.0"],@[@"CFBundleIdentifier",@"com.rayneo.venus"],@[@"TIOExperimentalOTAQueryRouting",[TIO_OTA_1011_ROUTING_MARKER uppercaseString]]];
    for(NSArray *kv in infos){
        Host=With(Full,kv[0],kv[1]);Image=Pinned;NSString *n=[NSString stringWithFormat:@"%@=%@",kv[0],Show(kv[1])];
        Check("profile",[n stringByAppendingString:@" not the ios1011 OTA host"],TIOOTA1011HostMatches(Host),NO);
        Check("profile",[n stringByAppendingString:@" arm required"],TIOOTAArmRequired(),YES);
        Check("profile",[n stringByAppendingString:@" arm refused"],TIOOTAFlashArm(NULL),NO);
        TMG4ArmStore()[ArmKey]=@{@"v":@1,@"host":@"ios1011",@"install":InstallID(),@"armedAt":@1};
        Check("profile",[n stringByAppendingString:@" valid record: not armed for transfer"],[TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue],NO);
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" read passes"],Allowed(Read1()),YES);
        [TMG4ArmStore() removeAllObjects];
    }
    Host=Full;Image=Pinned;
}

// --- Disarmed business 9: only empty reads 1, 2, 11 and type 3 with OtaSize exactly the ZIP byte count.
static void FrameCases(void){
    Host=Full;Image=Pinned;[TMG4ArmStore() removeAllObjects];assert(TIOOTAArmRequired()&&!TIOOTAFlashArmed());
    unsigned long long N=TIO_FW_ZIP_BYTES;
    NSString *(^size)(NSString *)=^(NSString *v){return [NSString stringWithFormat:@"{\"OtaSize\":%@}",v];};
    NSString *n=[NSString stringWithFormat:@"%llu",N];
    // Allowed: the exact query, with JSON whitespace only.
    for(NSString *json in @[size(n),[NSString stringWithFormat:@" { \"OtaSize\" : %@ } ",n],[NSString stringWithFormat:@"{\n\"OtaSize\":%@\n}",n]])
        Check("frames",[@"type 3 " stringByAppendingString:json],Allowed(RawFrame(3,json,nil)),YES);
    // Refused: any other value or spelling of the size.
    NSArray *values=@[[n stringByAppendingString:@".0"],[n stringByAppendingString:@"e0"],[NSString stringWithFormat:@"%llu",N-1],[NSString stringWithFormat:@"-%llu",N],
        [NSString stringWithFormat:@"\"%llu\"",N],@"true",@"false",@"null",[NSString stringWithFormat:@"[%llu]",N],[NSString stringWithFormat:@"{\"v\":%llu}",N],
        [@"0" stringByAppendingString:n],[NSString stringWithFormat:@"%llu",N+(1ULL<<32)],[NSString stringWithFormat:@"%llu",N+(1ULL<<63)],[n stringByAppendingString:@"000000000000000000"],
        @"1e30",[NSString stringWithFormat:@"%.17g",(double)N+0.5],@"0",@"-0"];
    for(NSString *v in values)Check("frames",[@"type 3 " stringByAppendingString:size(v)],Allowed(RawFrame(3,size(v),nil)),NO);
    for(NSString *json in @[[NSString stringWithFormat:@"{\"otaSize\":%@}",n],[NSString stringWithFormat:@"{\"OTASize\":%@}",n],[NSString stringWithFormat:@"{\"OtaSize \":%@}",n],
            [NSString stringWithFormat:@"{\"OtaSize\":%@,\"Mode\":4}",n],[NSString stringWithFormat:@"{\"OtaSize\":%@,\"OtaVersion\":\"Strix OS 1.0.5.5\"}",n],
            [NSString stringWithFormat:@"{\"OtaSize\":%@,\"x\":null}",n],[NSString stringWithFormat:@"[{\"OtaSize\":%@}]",n],size(n).uppercaseString,@"{}",@"[]",@""])
        Check("frames",[@"type 3 " stringByAppendingString:json],Allowed(RawFrame(3,json.length?json:nil,nil)),NO);
    Check("frames",@"type 3 exact size with an empty binary field",Allowed(RawFrame(3,size(n),[NSData data])),YES); // empty bytes field: no binary content
    Check("frames",@"type 3 exact size with a 1-byte binary",Allowed(RawFrame(3,size(n),[NSData dataWithBytes:"\0" length:1])),NO);
    // Duplicate key: NSJSONSerialization keeps the first value (as cJSON's lookup does). The body is not the
    // exact one-key query, so the intended rule refuses it either way; today the first-exact form passes.
    Check("frames",[NSString stringWithFormat:@"type 3 {\"OtaSize\":1,\"OtaSize\":%@} (duplicate key, first wrong)",n],
        Allowed(RawFrame(3,[NSString stringWithFormat:@"{\"OtaSize\":1,\"OtaSize\":%@}",n],nil)),NO);
    XFail("frames",[NSString stringWithFormat:@"type 3 {\"OtaSize\":%@,\"OtaSize\":1} (duplicate key, first exact)",n],
        Allowed(RawFrame(3,[NSString stringWithFormat:@"{\"OtaSize\":%@,\"OtaSize\":1}",n],nil)),NO,"ExperimentalOTAFlash.m:350 TIOOTADisarmedReadAllowed (parsed dictionary has one key; the duplicate is not seen)");
    // Reads: an empty or whitespace-only object only.
    for(NSNumber *t in @[@1,@2,@11]){
        unsigned long long type=t.unsignedLongLongValue;
        Check("frames",[NSString stringWithFormat:@"type %@ {}",t],Allowed(RawFrame(type,@"{}",nil)),YES);
        Check("frames",[NSString stringWithFormat:@"type %@ { }",t],Allowed(RawFrame(type,@" { } ",nil)),YES);
        for(NSString *json in @[@"[]",@"null",@"{\"a\":1}",@"{\"OsVersion\":\"Strix OS 1.0.5.5\"}",size(n),@"0",@"\"\""])
            Check("frames",[NSString stringWithFormat:@"type %@ %@",t,json],Allowed(RawFrame(type,json,nil)),NO);
        Check("frames",[NSString stringWithFormat:@"type %@ with a binary",t],Allowed(RawFrame(type,nil,[NSData dataWithBytes:"\0" length:1])),NO);
        // A type that truncates to a read on a byte-wide reader is not a read.
        uint64_t aliases[]={type+256,type+65536,type+(1ULL<<31)};
        for(size_t i=0;i<3;i++)Check("frames",[NSString stringWithFormat:@"type %llu (aliases %@)",aliases[i],t],Allowed(RawFrame(aliases[i],nil,nil)),NO);
    }
    uint64_t sizeTypes[]={3+256,3+65536,4+256,0,12,(1ULL<<32)-1,(1ULL<<32)+1};
    for(size_t i=0;i<sizeof sizeTypes/sizeof *sizeTypes;i++)
        Check("frames",[NSString stringWithFormat:@"type %llu size query",sizeTypes[i]],Allowed(RawFrame(sizeTypes[i],size(n),nil)),NO);
    // Transfer frames, any body, with or without a binary.
    for(NSNumber *t in @[@4,@5,@6,@7,@8,@9,@10,@12,@13,@255])for(NSString *json in @[@"",@"{}",@"{\"Mode\":2}",@"{\"Mode\":\"2\"}",@"{\"Mode\":2.0}",@"{\"Mode\":true}",size(n)])
        for(NSNumber *bin in @[@NO,@YES])
            Check("frames",[NSString stringWithFormat:@"type %@ %@%@",t,json,bin.boolValue?@" +binary":@""],Allowed(RawFrame(t.unsignedLongLongValue,json.length?json:nil,bin.boolValue?[NSData dataWithBytes:"x" length:1]:nil)),NO);
    // Wire-level shapes: duplicate or non-canonical fields never make a read.
    uint8_t dupType[]={8,1,16,1,16,4};uint8_t longType[]={8,1,16,0x84,0x00};uint8_t tag6[]={8,1,16,1,48,1};uint8_t version2[]={8,2,16,1};
    uint8_t tag6zero[]={8,1,16,1,48,0};uint8_t reordered[]={16,1,8,1};
    Check("frames",@"type 1 then type 4 (duplicate tag)",Allowed([NSData dataWithBytes:dupType length:sizeof dupType]),NO);
    Check("frames",@"type 4 with a padded varint",Allowed([NSData dataWithBytes:longType length:sizeof longType]),NO);
    Check("frames",@"type 1 with tag 6 = 1",Allowed([NSData dataWithBytes:tag6 length:sizeof tag6]),NO);
    Check("frames",@"type 1 version 2",Allowed([NSData dataWithBytes:version2 length:sizeof version2]),NO);
    Check("frames",@"type 1 with tag 6 = 0",Allowed([NSData dataWithBytes:tag6zero length:sizeof tag6zero]),YES);
    Check("frames",@"type 1 with the type before the version",Allowed([NSData dataWithBytes:reordered length:sizeof reordered]),YES);
    NSMutableData *trail=[Read1() mutableCopy];[trail appendBytes:"\0" length:1];Check("frames",@"type 1 with a trailing zero byte",Allowed(trail),NO);
    // Payload containers: NSData or a dictionary's "data" only; strings, arrays and nesting refused.
    NSData *start=Start2(),*read=Read1();
    Check("frames",@"payload NSMutableData read",Allowed([read mutableCopy]),YES);
    Check("frames",@"payload {data: read, x: 1}",Allowed(@{@"data":read,@"x":@1}),YES);
    Check("frames",@"payload {data: Mode 2, x: 1}",Allowed(@{@"data":start,@"x":@1}),NO);
    Check("frames",@"payload {Data: read}",Allowed(@{@"Data":read}),NO);
    Check("frames",@"payload {data: {data: read}}",Allowed(@{@"data":@{@"data":read}}),NO);
    Check("frames",@"payload [read]",Allowed(@[read]),NO);
    Check("frames",@"payload base64 read",Allowed([read base64EncodedStringWithOptions:0]),NO);
    Check("frames",@"payload latin-1 string read",Allowed([[NSString alloc]initWithData:read encoding:NSISOLatin1StringEncoding]),NO);
    Check("frames",@"payload JSON {type:1}",Allowed(@"{\"type\":1}"),NO);
    Check("frames",@"payload {type:1, json:{}}",Allowed(@{@"type":@1,@"json":@{}}),NO);
    Check("frames",@"payload @1",Allowed(@1),NO);
    // Call shape: extra argument keys never open a transfer frame; a read keeps passing (the stock call carries extra keys).
    for(NSDictionary *extra in @[@{@"x":@1},@{@"Mode":@2},@{@"businessID":@20},@{@"payload2":read},@{@"force":@YES}]){
        NSMutableDictionary *a=[@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":start} mutableCopy];[a addEntriesFromDictionary:extra];
        Check("frames",[NSString stringWithFormat:@"Mode 2 with extra argument %@",extra.allKeys.firstObject],!TIOOTAFlashBlockCall(CallWith(a)),NO);
        a[@"payload"]=read;
        Check("frames",[NSString stringWithFormat:@"read with extra argument %@",extra.allKeys.firstObject],!TIOOTAFlashBlockCall(CallWith(a)),YES);
    }
    Check("frames",@"Mode 2 without deviceId",!TIOOTAFlashBlockCall(CallWith(@{@"businessId":@9,@"payload":start})),NO);
    Check("frames",@"Mode 2 with deviceId NSNull",!TIOOTAFlashBlockCall(CallWith(@{@"businessId":@9,@"deviceId":NSNull.null,@"payload":start})),NO);
    // TIOOTADisarmedBlockCall agrees with the guard on every frame shape above that it sees directly.
    for(NSData *d in @[read,start,Frame(3,@{@"OtaSize":@(N)}),Frame(3,@{@"OtaSize":@(N-1)}),Frame(11,nil)])
        Check("frames",@"TIOOTADisarmedBlockCall agrees",TIOOTADisarmedBlockCall(Call(@9,d)),TIOOTAFlashBlockCall(Call(@9,d)));
}

// --- businessId: anything but a plain integer 0..255 is refused; 9 in any integer width is 9.
static void BusinessCases(void){
    Host=Full;Image=Pinned;[TMG4ArmStore() removeAllObjects];
    NSData *start=Start2(),*read=Read1();
    NSArray *refused=@[@"9",@"09",@" 9",@"9 ",@"0x9",@"265",@"",NSNull.null,@[@9],@{@"id":@9},[@"9" dataUsingEncoding:NSUTF8StringEncoding],
        [NSDecimalNumber decimalNumberWithString:@"9"],[NSDecimalNumber decimalNumberWithString:@"265"],[NSDecimalNumber decimalNumberWithString:@"9.5"],
        [NSNumber numberWithFloat:9],[NSNumber numberWithDouble:9],[NSNumber numberWithDouble:-0.0],[NSNumber numberWithDouble:NAN],[NSNumber numberWithDouble:INFINITY],
        @YES,@NO,(__bridge id)kCFBooleanTrue,@(-9),@(-256+9),@(LLONG_MIN),@(LLONG_MIN+9),[NSNumber numberWithUnsignedLongLong:UINT64_MAX],
        [NSNumber numberWithUnsignedLongLong:(1ULL<<63)+9],@256,@257,@511,@(9+512),@(UINT32_MAX-246),[NSNumber numberWithShort:-247],[NSNumber numberWithChar:-1],
        [NSValue valueWithRange:NSMakeRange(9,0)],NSDate.date,[NSURL URLWithString:@"9"]];
    for(id b in refused){
        Check("business",[NSString stringWithFormat:@"%@ Mode 2 refused",Show(b)],!TIOOTAFlashBlockCall(Call(b,start)),NO);
        Check("business",[NSString stringWithFormat:@"%@ read refused",Show(b)],!TIOOTAFlashBlockCall(Call(b,read)),NO);
        Check("business",[NSString stringWithFormat:@"%@ disarmed refusal",Show(b)],TIOOTADisarmedBlockCall(Call(b,read)),YES);
    }
    // 9 in every integer width: the business-9 rule applies (read passes, Mode 2 refused).
    for(NSNumber *b in @[[NSNumber numberWithChar:9],[NSNumber numberWithUnsignedChar:9],[NSNumber numberWithShort:9],[NSNumber numberWithUnsignedShort:9],
            [NSNumber numberWithInt:9],[NSNumber numberWithUnsignedInt:9],[NSNumber numberWithLong:9],[NSNumber numberWithLongLong:9],[NSNumber numberWithUnsignedLongLong:9],
            [NSNumber numberWithInteger:9],[NSNumber numberWithUnsignedInteger:9]]){
        Check("business",[NSString stringWithFormat:@"9 as %s: Mode 2 refused",b.objCType],!TIOOTAFlashBlockCall(Call(b,start)),NO);
        Check("business",[NSString stringWithFormat:@"9 as %s: read passes",b.objCType],!TIOOTAFlashBlockCall(Call(b,read)),YES);
    }
    // A misspelt key leaves no businessId: refused.
    for(NSString *key in @[@"businessID",@"BusinessId",@"business_id",@"businessId "])
        Check("business",[key stringByAppendingString:@": Mode 2 refused"],!TIOOTAFlashBlockCall(CallWith(@{key:@9,@"deviceId":@"fixture-peer",@"payload":start})),NO);
    // Other plain bytes are not OTA traffic and pass untouched, even with an OTA-looking frame.
    for(NSNumber *b in @[@0,@8,@10,@20,@255,[NSNumber numberWithUnsignedChar:255]])
        Check("business",[NSString stringWithFormat:@"%@ Mode 2 passes (not business 9)",b],!TIOOTAFlashBlockCall(Call(b,start)),YES);
}

// --- Arm record: exactly {v:1, host:"ios1011", install:<addon LC_UUID>, armedAt:<number>} under the one key in the addon suite.
static void RecordCases(void){
    Host=Full;Image=Pinned;NSMutableDictionary *store=TMG4ArmStore();[store removeAllObjects];
    NSString *install=InstallID();
    NSDictionary *good=@{@"v":@1,@"host":@"ios1011",@"install":install,@"armedAt":@1};
    void(^armed)(NSString *,id,BOOL)=^(NSString *name,id record,BOOL expected){
        [store removeAllObjects];store[ArmKey]=record;
        Check("record",name,TIOOTAFlashArmed(),expected);
        Check("record",[name stringByAppendingString:@" (status)"],[TIOOTAFlashArmStatus()[@"armed"] boolValue],expected);
        if(!expected){Check("record",[name stringByAppendingString:@": Mode 2 refused"],Allowed(Start2()),NO);
            Check("record",[name stringByAppendingString:@": read passes"],Allowed(Read1()),YES);}
        [store removeAllObjects];
    };
    void(^field)(NSString *,id,BOOL)=^(NSString *key,id value,BOOL expected){armed([NSString stringWithFormat:@"%@=%@",key,Show(value)],With(good,key,value),expected);};
    armed(@"good record",good,YES);
    // Equal-content variants of the right types are the same record.
    field(@"host",[NSMutableString stringWithString:@"ios1011"],YES);field(@"install",[NSMutableString stringWithString:install],YES);
    field(@"v",[NSNumber numberWithLongLong:1],YES);field(@"armedAt",@0,YES);field(@"armedAt",@1762560000,YES);
    // v: only the integer 1.
    for(id v in @[@0,@2,@(-1),@"1",@" 1",NSNull.null,@[@1],@{@"v":@1},[@"1" dataUsingEncoding:NSUTF8StringEncoding]])field(@"v",v,NO);
    XFail("record",@"v=@YES (CFBoolean) counts as v 1",({store[ArmKey]=With(good,@"v",@YES);BOOL a=TIOOTAFlashArmed();[store removeAllObjects];a;}),NO,"ExperimentalOTAFlash.m:402 ArmRecordValid [r[@\"v\"] isEqual:@1]");
    XFail("record",@"v=@1.0 (double) counts as v 1",({store[ArmKey]=With(good,@"v",@1.0);BOOL a=TIOOTAFlashArmed();[store removeAllObjects];a;}),NO,"ExperimentalOTAFlash.m:402 ArmRecordValid [r[@\"v\"] isEqual:@1]");
    XFail("record",@"v=NSDecimalNumber 1 counts as v 1",({store[ArmKey]=With(good,@"v",[NSDecimalNumber decimalNumberWithString:@"1"]);BOOL a=TIOOTAFlashArmed();[store removeAllObjects];a;}),NO,"ExperimentalOTAFlash.m:402 ArmRecordValid [r[@\"v\"] isEqual:@1]");
    // host: exact lower case, no padding.
    unichar nul[]={'i','o','s','1','0','1','1',0};
    for(id h in @[@"IOS1011",@"Ios1011",@"ios1011 ",@" ios1011",@"ios1011\n",[NSString stringWithCharacters:nul length:8],@"ios1011-download",@"ios107",@"",NSNull.null,@1011,@[@"ios1011"],
            [@"ios1011" dataUsingEncoding:NSUTF8StringEncoding]])field(@"host",h,NO);
    // install: the addon's own LC_UUID string exactly.
    // One hex letter in lower case (the UUID string always has at least one A-F).
    NSRange letter=[install rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEF"]];assert(letter.location!=NSNotFound);
    NSString *mixed=[install stringByReplacingCharactersInRange:letter withString:[install substringWithRange:letter].lowercaseString];
    for(id i in @[[@" " stringByAppendingString:install],[install stringByAppendingString:@" "],[install stringByAppendingString:@"\n"],[NSString stringWithFormat:@"{%@}",install],
            [install stringByReplacingOccurrencesOfString:@"-" withString:@""],mixed,PinnedUUID,@"",[[NSUUID alloc]initWithUUIDString:install],
            [install dataUsingEncoding:NSUTF8StringEncoding],@[install],NSNull.null])field(@"install",i,NO);
    // armedAt: a number; not a string, date object, container, data or null.
    for(id t in @[@"1",@"2026-11-08",NSNull.null,[NSDate dateWithTimeIntervalSince1970:1],@[@1],@{@"t":@1},[@"1" dataUsingEncoding:NSUTF8StringEncoding]])field(@"armedAt",t,NO);
    XFail("record",@"armedAt=@YES (CFBoolean) counts as a time",({store[ArmKey]=With(good,@"armedAt",@YES);BOOL a=TIOOTAFlashArmed();[store removeAllObjects];a;}),NO,"ExperimentalOTAFlash.m:403 ArmRecordValid [r[@\"armedAt\"] isKindOfClass:NSNumber.class]");
    // Shape: renamed, missing or extra keys; key case.
    for(NSString *k in good){
        NSMutableDictionary *m=[good mutableCopy];id v=m[k];[m removeObjectForKey:k];m[k.uppercaseString]=v;
        armed([NSString stringWithFormat:@"key %@ renamed %@",k,k.uppercaseString],m,NO);
        m=[good mutableCopy];m[[k stringByAppendingString:@" "]]=v;[m removeObjectForKey:k];armed([NSString stringWithFormat:@"key %@ padded",k],m,NO);
    }
    {NSMutableDictionary *m=[good mutableCopy];m[@"extra"]=NSNull.null;armed(@"extra key null",m,NO);}
    {NSMutableDictionary *m=[good mutableCopy];m[@1]=@1;armed(@"extra non-string key",m,NO);}
    {NSMutableDictionary *m=[good mutableCopy];[m removeObjectForKey:@"armedAt"];m[@"armedat"]=@1;armed(@"armedAt spelt armedat",m,NO);}
    armed(@"record as key/value array",@[@"v",@1,@"host",@"ios1011",@"install",install,@"armedAt",@1],NO);
    armed(@"record as JSON string",[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:good options:0 error:nil] encoding:NSUTF8StringEncoding],NO);
    armed(@"record as JSON data",[NSJSONSerialization dataWithJSONObject:good options:0 error:nil],NO);
    armed(@"record as @YES",@YES,NO);armed(@"record as @1",@1,NO);
    // Wrong key or wrong store: never armed.
    for(NSString *key in @[@"otaFlashArmRecord.IOS1011",@"otaFlashArmRecord.ios1011 ",@" otaFlashArmRecord.ios1011",@"otaFlashArmRecord",@"otaFlashArmRecord.ios107",
            @"otaFlashArmRecord.ios1011-download",@"OTAFlashArmRecord.ios1011",@"otaFlashArmRecord.ios1011.v2",@"otaFlashArmRecord_ios1011",@"otaFlashArmed"]){
        [store removeAllObjects];store[key]=good;
        Check("record",[NSString stringWithFormat:@"good record under %@",key],TIOOTAFlashArmed(),NO);
        Check("record",[NSString stringWithFormat:@"good record under %@: Mode 2 refused",key],Allowed(Start2()),NO);
    }
    [store removeAllObjects];
    // The host's standard defaults never arm, under the right key or any near miss.
    NSDictionary *savedPrefs=Prefs;
    for(NSString *key in @[ArmKey,@"otaFlashArmed",@"io.turboio.official-private-addon"]){
        Prefs=With(savedPrefs,key,good);
        Check("record",[NSString stringWithFormat:@"good record in standard defaults under %@",key],TIOOTAFlashArmed(),NO);
        Check("record",[NSString stringWithFormat:@"good record in standard defaults under %@: Mode 2 refused",key],Allowed(Start2()),NO);
        Check("record",[NSString stringWithFormat:@"good record in standard defaults under %@: authorize refused",key],TIOOTAFlashAuthorize(NULL),NO);
    }
    Prefs=With(savedPrefs,ArmKey,@{ArmKey:good});Check("record",@"nested record in standard defaults",TIOOTAFlashArmed(),NO);
    Prefs=savedPrefs;
    // Disarm (stage 0) removes the record whatever its shape; disarming when not armed succeeds.
    Check("record",@"disarm with no record",TIOOTAFlashDisarm(),YES);
    for(id r in @[good,With(good,@"v",@2),@"armed",NSNull.null,@[good]]){
        store[ArmKey]=r;
        Check("record",[NSString stringWithFormat:@"disarm removes %@",[r isKindOfClass:NSDictionary.class]?@"a record":Show(r)],TIOOTAFlashDisarm()&&!store[ArmKey],YES);
    }
    // Disarm touches only the arm key.
    store[@"otaFlashArmRecord.IOS1011"]=good;store[ArmKey]=good;
    Check("record",@"disarm leaves other keys",TIOOTAFlashDisarm()&&!store[ArmKey]&&store[@"otaFlashArmRecord.IOS1011"],YES);
    [store removeAllObjects];
}

int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1);
    Bits=[NSMutableString new];Areas=[NSMutableDictionary new];
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    Full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",
        @"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    Pinned=FakeImage(PinnedUUID);Host=Full;Image=Pinned;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    [TMG4ArmStore() removeAllObjects];
    assert([TIOHostProfileFor(Image,Host) isEqual:@"ios1011"]&&TIOOTAArmRequired()&&!TIOOTAFlashArmed());
    TIOOTARecordTransportHookReady();
    ProfileCases();FrameCases();BusinessCases();RecordCases();
    // Back on the clean full host: still disarmed, nothing stored.
    Host=Full;Image=Pinned;assert(!TMG4ArmStore().count&&!TIOOTAFlashArmed()&&!Allowed(Start2())&&Allowed(Read1()));
    NSMutableArray *counts=[NSMutableArray new];for(NSString *a in [Areas.allKeys sortedArrayUsingSelector:@selector(compare:)])[counts addObject:[NSString stringWithFormat:@"%@ %@",a,Areas[a]]];
    NSLog(@"PASS: 1.0.11 full host edge cases: %lu checks (%@), %lu XFAIL listed above; flash build %s; sweep=%@",
        (unsigned long)Cases,[counts componentsJoinedByString:@", "],(unsigned long)XFails,TIOOTAFlashBuild()?"on":"off",Digest(Bits));
}return 0;}
