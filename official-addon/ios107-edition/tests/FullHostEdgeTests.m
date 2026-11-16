// Edge cases for the full 1.0.21/1 host (profile ios1021, C20 onward; tests/FullHostFixture.h)
// that tests/FullHostGuardTests.m does not already cover: the profile marker's near
// misses, raw-JSON size queries, frame and payload shapes, businessId types, and a record
// left by the retired arm step. Runs the unchanged phone policy (ExperimentalOTAFlash.m,
// adapted by test.py exactly like ios1021-full-guard) in the same five TIO_* flag sets;
// every case's verdict goes into sweep=, which must be the same in every set.
// No device, network or signing.
//
// XFAIL: cases the intended rule refuses but the current policy accepts (none at present;
// the five found in d7(7) are fixed and checked as normal cases). Each is listed
// with input, expected, actual and the deciding line; it is checked to still fail, and
// when a fix makes it pass the run aborts with XPASS so the case moves into the normal
// list. They are not hidden: the run prints every one.
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
static NSString *const PinnedUUID=TFH_UUID;
static NSDictionary *Full;
static const struct mach_header *Pinned;
static NSDictionary *With(NSDictionary *base,NSString *key,id value){NSMutableDictionary *m=[base mutableCopy];if(value)m[key]=value;else [m removeObjectForKey:key];return m;}
static NSString *Show(id v){
    if(!v)return @"<absent>";
    NSString *s=[NSString stringWithFormat:@"%@<%@>",v,NSStringFromClass([v class])];
    return [[s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\0" withString:@"\\0"];
}

// --- Profile: this host's profile ("ios1021") only for the pinned image AND the exact NSString marker.
static void ProfileCases(void){
    NSArray *misses=TFHMarkerMisses();
    for(id marker in misses){
        Host=With(Full,@"TIOHostProfile",marker);Image=Pinned;
        NSString *n=[NSString stringWithFormat:@"marker %@",Show(marker)];
        Check("profile",[n stringByAppendingString:@" -> ios1021-download"],[TIOHostProfileFor(Image,Host) isEqual:@"ios1011-download"],YES);
        Check("profile",[n stringByAppendingString:@" not an OTA host"],TIOOTAHostProfile(Host)!=nil,NO);
        Check("profile",[n stringByAppendingString:@" download-only guard"],TIOOTADownloadOnlyHost(),YES);
        Check("profile",[n stringByAppendingString:@" not the full host"],TIOOTAFullHost(),NO);
        Check("profile",[n stringByAppendingString:@" full features off"],TIOHostFullImageMatches(Image,Host),NO);
        // Download-only rule: only the empty version query passes.
        Check("profile",[n stringByAppendingString:@" version query passes"],Allowed(Read1()),YES);
        Check("profile",[n stringByAppendingString:@" battery read refused"],Allowed(Frame(2,nil)),NO);
        Check("profile",[n stringByAppendingString:@" size query refused"],Allowed(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)})),NO);
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" authorize refused"],TIOOTAFlashAuthorize(NULL),NO);
    }
    // A mutable string with the same characters is the same marker.
    Host=With(Full,@"TIOHostProfile",[NSMutableString stringWithString:TFH_PROFILE]);
    Check("profile",@"NSMutableString marker -> full profile",[TIOHostProfileFor(Pinned,Host) isEqual:TFH_PROFILE],YES);
    Check("profile",@"NSMutableString marker full host",TIOOTAFullHost(),YES);
    // Exact marker on anything but the pinned image: never the full profile, but still the full host's gate
    // (the marker alone counts), and authorization is refused at the image check.
    struct {NSString *name;const struct mach_header *image;} images[]={
        {@"another image",FakeImage(@"00000000-0000-0000-0000-000000000002")},{@"other image",FakeImage(@"00000000-0000-0000-0000-000000000001")},
        {@"a third image",FakeImage(@"00000000-0000-0000-0000-000000000003")},{@"no image",NULL}};
    for(size_t i=0;i<sizeof images/sizeof *images;i++){
        Host=Full;Image=images[i].image;NSString *n=images[i].name;
        Check("profile",[n stringByAppendingString:@" not the full profile"],[TIOHostProfileFor(Image,Host) isEqual:TFH_PROFILE],NO);
        Check("profile",[n stringByAppendingString:@" full host gate"],TIOOTAFullHost(),YES);
        Check("profile",[n stringByAppendingString:@" authorize refused"],TIOOTAFlashAuthorize(NULL),NO);
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" read passes"],Allowed(Read1()),YES);
    }
    // Info near misses with the exact marker: the OTA host check fails and authorization is refused; the stage-0
    // reads stay. A neighbouring version and build (with this host's marker) are near misses too.
    NSArray *infos=@[@[@"CFBundleVersion",@(TFH_BUILD.integerValue)],@[@"CFBundleVersion",[TFH_BUILD stringByAppendingString:@" "]],@[@"CFBundleShortVersionString",[TFH_VERSION stringByAppendingString:@" "]],
        @[@"CFBundleShortVersionString",[TFH_VERSION stringByAppendingString:@".0"]],@[@"CFBundleIdentifier",@"com.rayneo.venus"],
        @[@"CFBundleShortVersionString",TFH_NEAR_VERSION],@[@"CFBundleVersion",TFH_NEAR_BUILD]];
    for(NSArray *kv in infos){
        Host=With(Full,kv[0],kv[1]);Image=Pinned;NSString *n=[NSString stringWithFormat:@"%@=%@",kv[0],Show(kv[1])];
        Check("profile",[n stringByAppendingString:@" not the full OTA host"],TFH_HOST_MATCHES(Host),NO);
        Check("profile",[n stringByAppendingString:@" full host gate"],TIOOTAFullHost(),YES);
        Check("profile",[n stringByAppendingString:@" authorize refused"],TIOOTAFlashAuthorize(NULL),NO);
        Check("profile",[n stringByAppendingString:@" Mode 2 refused"],Allowed(Start2()),NO);
        Check("profile",[n stringByAppendingString:@" read passes"],Allowed(Read1()),YES);
    }
    // Another app (its own version, build, a stale routing key and its own image) carrying this host's profile
    // marker: the full host's gate at stage 0, and authorization refused.
    {
        Host=With(With(With(Full,@"CFBundleShortVersionString",TFH_NEAR_VERSION),@"CFBundleVersion",TFH_NEAR_BUILD),@"TIOExperimentalOTAQueryRouting",@"ios107-tmg2-loopback-flash-gated");
        Image=FakeImage(@"00000000-0000-0000-0000-000000000004");
        assert(!TIOOTAHostMatches(Host)&&!TIOHostFullImageMatches(Image,Host));
        Check("profile",@"another app with this profile marker: full host gate",TIOOTAFullHost(),YES);
        Check("profile",@"another app with this profile marker: authorize refused",TIOOTAFlashAuthorize(NULL),NO);
        Check("profile",@"another app with this profile marker: Mode 2 refused",Allowed(Start2()),NO);
        Check("profile",@"another app with this profile marker: read passes",Allowed(Read1()),YES);
    }
    Host=Full;Image=Pinned;
}

// --- Stage 0, business 9: only empty reads 1, 2, 11 and type 3 with OtaSize exactly the ZIP byte count.
static void FrameCases(void){
    Host=Full;Image=Pinned;assert(TIOOTAFullHost()&&[TIOOTAFlashStatus()[@"stage"] intValue]==0);
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
    // Duplicate or escaped keys: the gate reads the body with NSJSONSerialization, which decodes escapes and keeps
    // the first value of a repeated key (as cJSON's lookup on the glasses does). A body that decodes to exactly
    // {OtaSize:<ZIP bytes>} is the size query; the rest is refused. A type 3 query transfers nothing, so the gate
    // no longer checks the raw text for a second key.
    for(NSString *json in @[[NSString stringWithFormat:@"{\"OtaSize\":1,\"OtaSize\":%@}",n],[NSString stringWithFormat:@"{\"OtaSize\":%@,\"OtaSize\":1}",n],
            [NSString stringWithFormat:@"{\"OtaSize\":%@,\"Ota\\u0053ize\":1}",n],[NSString stringWithFormat:@"{\"Ota\\u0053ize\":1,\"OtaSize\":%@}",n],
            [NSString stringWithFormat:@"{\"Ota\\u0053ize\":%@}",n],[NSString stringWithFormat:@"{\"OtaSize\":%@,\"\\u004ftaSize\":%@}",n,n],[NSString stringWithFormat:@"{\"OtaSize\":%@,\"OtaSize\":%@}",n,n],
            [NSString stringWithFormat:@"{\"OtaSize\":%@}\"OtaSize\"",n]]){
        id decoded=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        Check("frames",[@"type 3 " stringByAppendingString:json],Allowed(RawFrame(3,json,nil)),[decoded isEqual:@{@"OtaSize":@(N)}]);
    }
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
    // A fresh gate at stage 0 agrees with the guard on every frame shape above that it sees directly.
    for(NSData *d in @[read,start,Frame(3,@{@"OtaSize":@(N)}),Frame(3,@{@"OtaSize":@(N-1)}),Frame(11,nil)])
        Check("frames",@"a fresh gate agrees",![[TIOOTAFlashGate new] allows:d device:@"fixture-peer" uptime:Now],TIOOTAFlashBlockCall(Call(@9,d)));
}

// --- businessId: anything but a plain integer 0..255 is refused; 9 in any integer width is 9.
static void BusinessCases(void){
    Host=Full;Image=Pinned;
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

// --- A record left by the retired arm step (C20 wrote otaFlashArmRecord.ios1021 to the addon suite) is never read:
// in the host's defaults or not, the gate stays at stage 0 and authorization still needs everything else.
static void LeftoverCases(void){
    Host=Full;Image=Pinned;NSDictionary *saved=Prefs;
    NSDictionary *record=@{@"v":@1,@"host":TFH_PROFILE,@"install":PinnedUUID,@"armedAt":@1};
    for(NSString *key in @[@"otaFlashArmRecord.ios" TFH_D,@"otaFlashArmRecord.ios1011",@"otaFlashArmed",@"io.turboio.official-private-addon"]){
        Prefs=With(saved,key,record);
        Check("leftover",[NSString stringWithFormat:@"record under %@: Mode 2 refused",key],Allowed(Start2()),NO);
        Check("leftover",[NSString stringWithFormat:@"record under %@: read passes",key],Allowed(Read1()),YES);
        Check("leftover",[NSString stringWithFormat:@"record under %@: authorize refused",key],TIOOTAFlashAuthorize(NULL),NO);
    }
    Prefs=saved;
}

int main(int argc,char **argv){@autoreleasepool{
    assert(argc==1);
    Bits=[NSMutableString new];Areas=[NSMutableDictionary new];
    Home=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    Full=TFHFullInfo();
    Pinned=FakeImage(PinnedUUID);Host=Full;Image=Pinned;Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    assert([TIOHostProfileFor(Image,Host) isEqual:TFH_PROFILE]&&TIOOTAFullHost());
    TIOOTARecordTransportHookReady();
    ProfileCases();FrameCases();BusinessCases();LeftoverCases();
    // Back on the clean full host: still stage 0.
    Host=Full;Image=Pinned;assert([TIOOTAFlashStatus()[@"stage"] intValue]==0&&!Allowed(Start2())&&Allowed(Read1()));
    NSMutableArray *counts=[NSMutableArray new];for(NSString *a in [Areas.allKeys sortedArrayUsingSelector:@selector(compare:)])[counts addObject:[NSString stringWithFormat:@"%@ %@",a,Areas[a]]];
    NSLog(@"PASS: " TFH_NAME " full host edge cases: %lu checks (%@), %lu XFAIL listed above; flash build %s; sweep=%@",
        (unsigned long)Cases,[counts componentsJoinedByString:@", "],(unsigned long)XFails,TIOOTAFlashBuild()?"on":"off",Digest(Bits));
}return 0;}
