#import "OTAHost.h"
#import "TIOLanguage.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAFlash.h"
#import "TIOGlassesFileTransport.h"
#import "AppTransport.h"
#import "AppBridge.h"
#import "ExperimentalOTA.h"
#import "FirmwarePins.h"
#import "ExperimentalOTAGuard.h"
#import "HostCompatibility.h"
#include <TargetConditionals.h>
#include <math.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>
#include <dlfcn.h>
#include <mach-o/loader.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if TIO_IMAGE_RX_LAB
#import "ImageUploadTransport.h"
#endif
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneTransport.h"
#endif
#if TIO_DISPLAY_PHONE && TIO_NATIVE_NAV
#import "TNVTransport.h"
#endif
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
#import "DisplayPhoneUI.h"
#endif
typedef BOOL (*TIOOTAScopedSender)(NSString *,NSDictionary *);
// one row per module that sends its own scoped rayneonet_sendFile; deleting a module deletes its row and its #import.
static const TIOOTAScopedSender ScopedFileSenders[]={
#if TIO_IMAGE_RX_LAB
 TIOImageUploadIsScopedCall,
#endif
#if TIO_DISPLAY_PHONE
 TDPPhoneIsScopedCall,
#endif
#if TIO_DISPLAY_PHONE && TIO_NATIVE_NAV
 TAPIsScopedCall,
 TNVIsScopedCall,
 TIOGlassesFileIsScopedCall,
#endif
 NULL};
NSUInteger TIOOTAScopedSenderCount(void){NSUInteger n=0;for(const TIOOTAScopedSender *s=ScopedFileSenders;*s;s++)n++;return n;}
BOOL TIOOTAFileCallBlocked(NSString *method,BOOL scopedImage,NSUInteger stage){
    if(![method isKindOfClass:NSString.class])return YES;
    // Compared from the literal's side, on a plain copy: a subclass's own -isEqual: or -lowercaseString never decides.
    method=[[NSString alloc] initWithString:method];
    if([@"rayneonet_sendFile" isEqualToString:method]&&scopedImage&&stage==0)return NO;
    NSString *lower=method.lowercaseString;
    return [lower containsString:@"sendfile"]||[lower containsString:@"ota"]||[lower containsString:@"upgrade"];
}
// D5: the stock teleprompter's file send. Compiled in every build, no TIO_* flag.
// An allow-list: anything that is not exactly this shape stays refused by
// TIOOTAFileCallBlocked. Stock 1.0.7 sends {deviceId, filePath, taskId} with
// filePath <container>/Library/Application Support/user_<digits>/teleprompter/<UUID>
// and taskId the same UUID; 1.0.11 may stage under Documents/user_<digits>/teleprompter/.
// Limits beyond the observed shape, kept on purpose: deviceId at most 256
// characters, at most 20 digits after user_, file name a UUID in one case.
// Where the bytes go, from a static decomp read only (not checked on the
// device): the stock 1.0.5.5 business-0x11 receiver assembles the file in RAM
// (at most 20 MiB, MD5-checked) and only business 0x14 consumes it, with about a
// 1 MiB RAM cap; no storage write was found, but indirect calls were not
// resolved. 1.0.5.12 is inferred to behave the same.
static const off_t TIOTeleprompterMaxBytes=1048576;
// A ZIP's end-of-central-directory record sits in the last 22 + 65535 bytes.
static const off_t TIOTeleprompterEOCDWindow=65557;
// Only objects of Foundation's or CoreFoundation's own classes: no subclass
// whose count, keys, characters or equality could answer differently per read.
static BOOL TeleprompterPlain(id o,Class kind){
    if(!o||![o isKindOfClass:kind])return NO;
    const char *image=class_getImageName(object_getClass(o));
    return image&&!strncmp(image,"/System/Library/Frameworks/",27)&&(strstr(image,"/CoreFoundation.framework/")||strstr(image,"/Foundation.framework/"));
}
static BOOL TeleprompterString(id v,NSUInteger max){return [v isKindOfClass:NSString.class]&&[(NSString *)v length]>0&&[(NSString *)v length]<=max;}
// Printable ASCII only: no NUL, no Unicode normalization questions.
static BOOL TeleprompterASCII(NSString *s){for(NSUInteger i=0;i<s.length;i++){unichar c=[s characterAtIndex:i];if(c<0x20||c>0x7e)return NO;}return YES;}
// Canonical 8-4-4-4-12 hex, all lower or all upper case.
static BOOL TeleprompterUUID(NSString *s){
    if(s.length!=36)return NO;BOOL upper=NO,lower=NO;
    for(NSUInteger i=0;i<36;i++){unichar c=[s characterAtIndex:i];
        if(i==8||i==13||i==18||i==23){if(c!='-')return NO;continue;}
        if(c>='0'&&c<='9')continue;
        if(c>='a'&&c<='f'){lower=YES;continue;}
        if(c>='A'&&c<='F'){upper=YES;continue;}
        return NO;
    }
    return !(upper&&lower);
}
static BOOL TeleprompterUser(NSString *s){
    if(![s hasPrefix:@"user_"]||s.length<6||s.length>25)return NO;
    for(NSUInteger i=5;i<s.length;i++){unichar c=[s characterAtIndex:i];if(c<'0'||c>'9')return NO;}
    return YES;
}
static NSString *TeleprompterRealPath(NSString *path){
    char resolved[PATH_MAX];if(!realpath(path.UTF8String,resolved))return nil;
    NSString *r=@(resolved);return TeleprompterASCII(r)?r:nil;
}
// One enumeration of a plain dictionary of plain strings into a fresh immutable
// dictionary of fresh strings. Everything after this reads only the snapshot,
// and the hook forwards the snapshot, so the plugin reads what was checked.
static NSDictionary *TeleprompterSnapshot(id args){
    if(!TeleprompterPlain(args,NSDictionary.class))return nil;
    NSMutableDictionary *m=[NSMutableDictionary dictionaryWithCapacity:3];
    for(id k in (NSDictionary *)args){
        if(m.count>=3)return nil;
        id v=[(NSDictionary *)args objectForKey:k];
        if(!TeleprompterPlain(k,NSString.class)||!TeleprompterPlain(v,NSString.class))return nil;
        NSString *key=[[NSString alloc] initWithString:k];if(m[key])return nil;
        m[key]=[[NSString alloc] initWithString:v];
    }
    return [m copy];
}
// Walks root/components with O_NOFOLLOW at every step, so no component can be
// a symlink at open time, then checks the file on the descriptor it opened.
// Accepted window: the plugin opens the path again after this check. Only the
// app writes under its container (UIFileSharingEnabled is false on both hosts),
// and the glasses-side receiver is the backstop for anything swapped in between.
static BOOL TeleprompterFileOK(NSString *root,NSArray<NSString *> *components,NSString *path){
    struct stat ls,fs;
    if(lstat(path.UTF8String,&ls)||!S_ISREG(ls.st_mode))return NO;
    int dir=open(root.UTF8String,O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(dir<0)return NO;
    for(NSUInteger i=0;i+1<components.count;i++){
        int next=openat(dir,components[i].UTF8String,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(dir);
        if(next<0)return NO;dir=next;
    }
    int fd=openat(dir,components.lastObject.UTF8String,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);close(dir);
    if(fd<0)return NO;
    BOOL ok=!fstat(fd,&fs)&&S_ISREG(fs.st_mode)&&fs.st_dev==ls.st_dev&&fs.st_ino==ls.st_ino&&fs.st_nlink==1&&fs.st_size>0&&fs.st_size<=TIOTeleprompterMaxBytes;
    // Not a ZIP: no "PK" at offset 0 and no end-of-central-directory signature in the tail
    // (catches a ZIP behind a BOM or any other prefix). Both reads use this descriptor.
    if(ok){uint8_t magic[2]={0,0};ssize_t n=pread(fd,magic,2,0);ok=n>=1&&!(n==2&&magic[0]=='P'&&magic[1]=='K');}
    if(ok){
        off_t start=fs.st_size>TIOTeleprompterEOCDWindow?fs.st_size-TIOTeleprompterEOCDWindow:0;size_t want=(size_t)(fs.st_size-start);
        uint8_t *tail=malloc(want);ok=tail!=NULL;
        if(ok){size_t got=0;while(got<want){ssize_t r=pread(fd,tail+got,want-got,start+(off_t)got);if(r<=0)break;got+=(size_t)r;}
            ok=got==want&&!memmem(tail,want,"PK\x05\x06",4);free(tail);}
    }
    close(fd);return ok;
}
static NSDictionary *TeleprompterCheck(NSString *container,NSString *method,id args,NSUInteger otaStage){
    if(otaStage!=0||!TeleprompterPlain(method,NSString.class))return nil;
    if(![@"rayneonet_sendFile" isEqualToString:[[NSString alloc] initWithString:method]])return nil;
    NSDictionary *a=TeleprompterSnapshot(args);
    if(a.count!=3||![[NSSet setWithArray:a.allKeys] isEqualToSet:[NSSet setWithObjects:@"deviceId",@"filePath",@"taskId",nil]])return nil;
    NSString *device=a[@"deviceId"],*path=a[@"filePath"],*task=a[@"taskId"];
    if(!TeleprompterString(device,256)||!TeleprompterString(path,PATH_MAX-1)||!TeleprompterString(task,36))return nil;
    if(!TeleprompterASCII(path)||![path hasPrefix:@"/"]||!TeleprompterUUID(task))return nil;
    // The container comes from the app (NSHomeDirectory()), never from the path.
    if(!TeleprompterString(container,PATH_MAX-1))return nil;
    container=[[NSString alloc] initWithString:container];
    if(!TeleprompterASCII(container)||![container hasPrefix:@"/"]||[container hasSuffix:@"/"])return nil;
    NSString *root=TeleprompterRealPath(container);if(!root)return nil;
    // iOS reports the container as /var/..., whose realpath is /private/var/...: accept either spelling of the same root.
    NSString *suffix=nil;
    for(NSString *prefix in @[container,root]){NSString *p=[prefix stringByAppendingString:@"/"];if([path hasPrefix:p]){suffix=[path substringFromIndex:p.length];break;}}
    if(!suffix)return nil;
    NSArray<NSString *> *c=[suffix componentsSeparatedByString:@"/"];NSUInteger user;
    if(c.count==5&&[@"Library" isEqualToString:c[0]]&&[@"Application Support" isEqualToString:c[1]])user=2;
    else if(c.count==4&&[@"Documents" isEqualToString:c[0]])user=1;
    else return nil;
    if(!TeleprompterUser(c[user])||![@"teleprompter" isEqualToString:c[user+1]]||![task isEqualToString:c[user+2]])return nil;
    // No symlink anywhere below the root, no "..", "." or "//": the resolved path is the path itself.
    NSString *expected=[[root stringByAppendingString:@"/"] stringByAppendingString:suffix];
    if(![expected isEqualToString:TeleprompterRealPath(path)])return nil;
    return TeleprompterFileOK(root,c,expected)?a:nil;
}
NSDictionary *TIOStockTeleprompterSendSnapshotIn(NSString *container,NSString *method,id args,NSUInteger otaStage){
    @try{return TeleprompterCheck(container,method,args,otaStage);}@catch(__unused id e){return nil;}
}
BOOL TIOStockTeleprompterSendAllowedIn(NSString *container,NSString *method,id args,NSUInteger otaStage){
    return TIOStockTeleprompterSendSnapshotIn(container,method,args,otaStage)!=nil;
}
BOOL TIOStockTeleprompterSendAllowed(NSString *method,id args,NSUInteger otaStage){
    return TIOStockTeleprompterSendAllowedIn(NSHomeDirectory(),method,args,otaStage);
}
// The call the hook forwards for an allowed teleprompter send: built from the
// method literal and the checked snapshot, never from the caller's objects.
id TIOStockTeleprompterForwardCall(NSDictionary *snapshot){
    Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:");
    if(![snapshot isKindOfClass:NSDictionary.class]||![cls respondsToSelector:make])return nil;
    @try{return ((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,@"rayneonet_sendFile",snapshot);}@catch(__unused id e){return nil;}
}
static id Error(NSError **error,NSString *s){if(error)*error=[NSError errorWithDomain:@"TurboIO.OTAFlash" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];return nil;}
static BOOL Number(id n,NSUInteger *out){
    if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()||CFNumberIsFloatType((__bridge CFNumberRef)n)||[n longLongValue]<0)return NO;
    uint64_t v=[n unsignedLongLongValue];if(v>UINT32_MAX)return NO;*out=(NSUInteger)v;return YES;
}
// G4: the RayneoNet plugin bridge narrows businessId with UInt8(truncating:),
// so 265 (9+256k) goes on the wire as business 9. Every send path and the
// receive monitor read the id through this helper: above 255 is malformed.
static BOOL Business(id n,NSUInteger *out){NSUInteger v=0;if(!Number(n,&v)||v>UINT8_MAX)return NO;*out=v;return YES;}
static BOOL Var(const uint8_t *b,NSUInteger n,NSUInteger *at,uint64_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t x=b[(*at)++];if(i==4&&(x&0xf0))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return i==0||x!=0;}return NO;}
NSDictionary *TIOOTAFrame(NSData *data){
    if(![data isKindOfClass:NSData.class]||data.length<4||data.length>65536)return nil;
    const uint8_t *b=data.bytes;NSUInteger at=0;unsigned seen=0;uint64_t version=0,type=0;NSData *json=[NSData data],*binary=[NSData data];
    while(at<data.length){uint64_t key,v;if(!Var(b,data.length,&at,&key))return nil;unsigned tag=(unsigned)(key>>3),wire=key&7;
        if(tag<1||tag>6||(seen&(1u<<tag)))return nil;seen|=1u<<tag;
        if(tag==3||tag==4){if(wire!=2||!Var(b,data.length,&at,&v)||v>data.length-at)return nil;if(tag==3)json=[data subdataWithRange:NSMakeRange(at,(NSUInteger)v)];else binary=[data subdataWithRange:NSMakeRange(at,(NSUInteger)v)];at+=(NSUInteger)v;}
        else{if(wire!=0||!Var(b,data.length,&at,&v))return nil;if(tag==1)version=v;if(tag==2)type=v;if(tag==6&&v!=0)return nil;}
    }
    if(version!=1||!type)return nil;
    id obj=json.length?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:@{};
    if(![obj isKindOfClass:NSDictionary.class]&&![obj isKindOfClass:NSArray.class])return nil;
    return @{@"type":@(type),@"json":obj,@"binary":binary};
}
BOOL TIOPhoneOTAReadAllowed(NSData *data){
    NSDictionary *frame=TIOOTAFrame(data);NSUInteger type=[frame[@"type"] unsignedIntegerValue];
    return [@[@1,@2,@11] containsObject:@(type)]&&[frame[@"json"] isEqual:@{}]&&[frame[@"binary"] length]==0;
}
@implementation TIOOTAFlashGate{
    NSDictionary<NSString *,NSData *> *_files;NSArray *_manifest;NSString *_device,*_failure;
    NSTimeInterval _deadline;NSUInteger _stage,_slices,_bytes;BOOL _versionSent,_manifestSent;
}
- (BOOL)prepareDirectory:(NSURL *)directory device:(NSString *)device uptime:(NSTimeInterval)now error:(NSError **)error{
    @synchronized(self){
        if(_stage||![device isKindOfClass:NSString.class]||!device.length||device.length>200||!isfinite(now)||now<0){Error(error,TIOText(@"当前不是可授权状态或没有有效设备；未开放。"));return NO;}
        NSDictionary *files=TIOCopyExperimentalOTAPayloads(directory,error);if(!files)return NO;
        id manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:error];if(![manifest isKindOfClass:NSArray.class]||[manifest count]!=15)return NO;
        _files=files;_manifest=manifest;_device=[device copy];_deadline=now+900;_stage=1;_failure=nil;return YES;
    }
}
- (BOOL)allows:(NSData *)payload device:(NSString *)device uptime:(NSTimeInterval)now{
    @synchronized(self){
        NSDictionary *f=TIOOTAFrame(payload);NSUInteger t=[f[@"type"] unsignedIntegerValue];id j=f[@"json"];NSData *binary=f[@"binary"];
        BOOL dict=[j isKindOfClass:NSDictionary.class],empty=dict&&[j count]==0&&!binary.length;
        // 1 = OS version, 2 = battery. Idle is 11, NOT 2: official 1.0.5
        // failure recovery sent msgType=11 on 2026-09-21 at 17:38:03.477.
        // Allow its empty read even after a blocked start so the official
        // recovery loop can establish that no glasses transfer is active.
        if((t==1||t==2||t==11)&&empty)return YES;
        NSUInteger n=0;
        if(t==3&&dict&&[j count]==1&&Number(j[@"OtaSize"],&n)&&n==TIO_FW_ZIP_BYTES&&!binary.length)return YES;
        if(!_stage){if(t==4)_failure=[NSString stringWithFormat:TIOText(@"ota.identity.notAuthorized"),TIO_FW_NAME,TIO_FW_NAME];return NO;}
        if(_stage==3||!isfinite(now)||now<0)return NO;
        if(_stage==1&&now>=_deadline){[self cancel];return NO;}
        BOOL ok=[device isEqual:_device];
        if(t==4)ok=ok&&_stage==1&&dict&&[j count]==1&&Number(j[@"Mode"],&n)&&n==2&&!binary.length;
        else if(t==5)ok=ok&&_stage==2&&dict&&[j isEqual:@{@"OtaVersion":@"Strix OS 1.0.5.5"}]&&!binary.length;
        else if(t==6)ok=ok&&_stage==2&&_versionSent&&[j isKindOfClass:NSArray.class]&&[j isEqual:_manifest]&&!binary.length;
        else if(t==7){
            NSUInteger start=0,size=0;NSString *name=dict?j[@"Name"]:nil;NSData *file=[name isKindOfClass:NSString.class]?_files[name]:nil;
            ok=ok&&_stage==2&&_manifestSent&&dict&&[j count]==3&&file&&![name isEqual:@"OtaFileInfo.json"]&&Number(j[@"Start"],&start)&&Number(j[@"Size"],&size)&&size>0&&size<=51200&&start<file.length&&size<=file.length-start&&binary.length==size;
            if(ok)ok=memcmp(binary.bytes,(const uint8_t *)file.bytes+start,size)==0;
            if(ok){_slices++;_bytes+=size;}
        }else ok=NO;
        if(!ok){_failure=TIOText(@"非预期设备、会话、清单或分片，发送被拒绝");if(_stage==2)_stage=3;return NO;}
        if(t==4)_stage=2;if(t==5)_versionSent=YES;if(t==6)_manifestSent=YES;return YES;
    }
}
- (BOOL)cancel{@synchronized(self){if(_stage>=2)return NO;_stage=0;_files=nil;_manifest=nil;_device=nil;_deadline=0;return YES;}}
- (NSDictionary *)status{@synchronized(self){return @{@"stage":@(_stage),@"authorized":@(_stage==1||_stage==2),@"started":@(_stage>=2),@"versionMatched":@(_versionSent),@"manifestMatched":@(_manifestSent),@"validatedSlices":@(_slices),@"validatedSliceBytes":@(_bytes),@"failure":_failure?:@"",@"runtimeValidated":@NO};}}
@end
BOOL TIOOTAFlashBuild(void){
#if TARGET_OS_IPHONE && TIO_OTA_FLASH_ENABLED
#if TIO_DISPLAY_FLASH
    // Compiled experimental builds must stay gated even if Info.plist is stale.
    // Authorization/feed still require the exact marker below.
    return YES;
#else
    return TIOOTAHostMatches(NSBundle.mainBundle.infoDictionary);
#endif
#else
    return NO;
#endif
}
static TIOOTAFlashGate *Gate;static NSString *ObservedDevice;static NSTimeInterval ObservedAt;
BOOL TIOOTAAutoUpdateDisabled(NSDictionary *preferences){
    if(![preferences isKindOfClass:NSDictionary.class])return NO;
    NSUInteger found=0;
    for(id key in preferences){if(![key isKindOfClass:NSString.class]||![key hasSuffix:@"_ota_firmware_auto_update"])continue;found++;
        id v=preferences[key];if([v isKindOfClass:NSString.class]){if(![v isEqual:@"false"])return NO;}
        else if(![v isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)v)!=CFBooleanGetTypeID()||[v boolValue])return NO;
    }
    return found>0;
}
static TIOOTAFlashGate *Current(void){@synchronized(NSProcessInfo.processInfo){if(!Gate)Gate=[TIOOTAFlashGate new];return Gate;}}
// The flash session stage the file guard reads (test.py's stock-teleprompter group substitutes this seam).
static NSUInteger GateStage(void){return [[Current() status][@"stage"] unsignedIntegerValue];}
BOOL TIOOTAFlashProtected(void){
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
    if(!TIOOTAHostMatches(NSBundle.mainBundle.infoDictionary))return NO;
#endif
    return TIOOTAFlashBuild()&&[TIOOTAGuardStatus()[@"transportHookReady"] boolValue];
}
BOOL TIOOTAFlashDisableAutoUpdate(void){
    if(!TIOOTAFlashProtected())return NO;
    NSUserDefaults *p=NSUserDefaults.standardUserDefaults;NSMutableArray *keys=[NSMutableArray new];
    for(NSString *key in p.dictionaryRepresentation)if([key hasSuffix:@"_ota_firmware_auto_update"])[keys addObject:key];
    // Do not guess between accounts. The private pre-install preference backup
    // preserves the old value; no account identifiers are written to reports.
    if(keys.count!=1)return NO;id v=[p objectForKey:keys[0]];
    if([v isKindOfClass:NSString.class]&&([v isEqual:@"true"]||[v isEqual:@"false"]))[p setObject:@"false" forKey:keys[0]];
    else if([v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID())[p setBool:NO forKey:keys[0]];
    else return NO;
    [p synchronize];return YES;
}
static id Get(id obj,NSString *key){@try{return [obj valueForKey:key];}@catch(NSException *e){return nil;}}
// Download-only 1.0.11/259 host (G1). The refusal below is compiled in every
// build and depends on no TIO_* flag: TIO_OTA_FLASH_ENABLED, TIO_DISPLAY_FLASH
// and TIO_DISPLAY_PHONE only shape the 1.0.7 path further down.
NSString *const TIOOTADownloadOnlyGuardMarker=@"ota guard=IOS1011-DOWNLOAD-GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed; business 9 refused except the empty version query";
BOOL TIOOTADownloadOnlyHost(void){
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    // The packager's marker alone also counts: refusing more is the safe side.
    return [TIOHostProfileFor(TIOHostMainImage(),info) isEqual:@"ios1011-download"]||[info[@"TIOHostProfile"] isEqual:@"ios1011-download"];
}
// teleprompter (may be NULL) receives the checked snapshot when the call passes as the stock teleprompter send.
static BOOL DownloadOnlyBlock(id call,NSDictionary **teleprompter){
    NSString *method=Get(call,@"method");NSDictionary *args=Get(call,@"arguments");
    if(![method isKindOfClass:NSString.class])return YES;
    if([@"rayneonet_sendMessage" isEqualToString:method]){
        NSUInteger business=0;if(![args isKindOfClass:NSDictionary.class]||!Business(args[@"businessId"],&business))return YES;
        if(business!=9)return NO;
        id data=args[@"payload"];if(![data isKindOfClass:NSData.class])data=Get(data,@"data");
        return !TIOOTAIsEmptyVersionQuery(data);
    }
    // No addon file sender is scoped here: the download-only host sends nothing of its own.
    // D5: the one stock file send let through is the narrow teleprompter shape; the stage must be 0 here too.
    NSUInteger stage=GateStage();
    NSDictionary *snapshot=TIOStockTeleprompterSendSnapshotIn(NSHomeDirectory(),method,args,stage);
    BOOL blocked=TIOOTAFileCallBlocked(method,snapshot!=nil,stage);
    if(teleprompter&&!blocked)*teleprompter=snapshot;
    return blocked;
}
BOOL TIOOTADownloadOnlyBlockCall(id call){return DownloadOnlyBlock(call,NULL);}
// Full 1.0.11 host (ios1011, C15): TMG flashing is disarmed until the owner arms it
// in the flash wizard. Like G1 this refusal is compiled in every build and depends
// on no TIO_* flag. While disarmed, business 9 lets through only the reads the
// stock firmware page makes (empty OS version 1, battery 2, idle 11) and the size
// query (3, OtaSize equal to the bundled ZIP), so its update check against the
// loopback feed and the wire log see the real sequence; type 4 (any Mode) and the
// version, manifest and slice frames (5, 6, 7) are refused, whatever the Auto Update
// toggle says. The 1.0.11 order (2/3/1/4), the type 3 shape and the normal page's
// Mode are known only from a static read: the C15 capture must confirm them before
// anyone arms. Armed, the host takes the 1.0.7 path below unchanged (TIOOTAFlashGate:
// Mode 2 only, so a forced page's Mode 4 is still refused; Auto Update off; fresh
// version read; single confirmation).
NSString *const TIOOTAArmGuardMarker=@"ota guard=IOS1011-FULL-DISARM-01; flag-independent; disarmed until armed on this install; business 9 transfer frames refused while disarmed; reads and the exact size query pass";
BOOL TIOOTADisarmedReadAllowed(NSData *data){
    if(TIOPhoneOTAReadAllowed(data))return YES;
    NSDictionary *f=TIOOTAFrame(data);id j=f[@"json"];NSUInteger n=0;
    if(!([f[@"type"] isEqual:@3]&&[j isKindOfClass:NSDictionary.class]&&[j count]==1&&Number(j[@"OtaSize"],&n)&&n==TIO_FW_ZIP_BYTES&&[f[@"binary"] length]==0))return NO;
    // NSJSONSerialization keeps one value of a repeated key, so {"OtaSize":<bytes>,"OtaSize":1}
    // parses as one exact key. The raw text must name the key once: no backslash (so no
    // escaped spelling of it) and exactly one "OtaSize".
    return TIOOTARawJSONNamesKeyOnce(data,@"OtaSize");
}
// The file-call rule both full hosts share: an addon scoped sender, then the stock
// teleprompter shape (only at stage 0), else TIOOTAFileCallBlocked.
static BOOL FileCallBlock(NSString *method,id args,NSDictionary **teleprompter){
    // The pinned files path uses business 9 frames, never sendFile / ZIP mode.
    BOOL scopedImage=NO;for(const TIOOTAScopedSender *s=ScopedFileSenders;*s&&!scopedImage;s++)scopedImage=(*s)(method,args);
    NSUInteger stage=GateStage();
    // D5: an addon scoped sender decides first; otherwise the stock teleprompter shape passes like a scoped call, only at stage 0.
    NSDictionary *snapshot=scopedImage?nil:TIOStockTeleprompterSendSnapshotIn(NSHomeDirectory(),method,args,stage);
    BOOL blocked=TIOOTAFileCallBlocked(method,scopedImage||snapshot,stage);
    if(teleprompter&&!blocked)*teleprompter=snapshot;
    return blocked;
}
static BOOL DisarmedBlock(id call,NSDictionary **teleprompter){
    NSString *method=Get(call,@"method");NSDictionary *args=Get(call,@"arguments");
    if(![method isKindOfClass:NSString.class])return YES;
    if([@"rayneonet_sendMessage" isEqualToString:method]){
        NSUInteger business=0;if(![args isKindOfClass:NSDictionary.class]||!Business(args[@"businessId"],&business))return YES;
        if(business!=9)return NO;
        id data=args[@"payload"];if(![data isKindOfClass:NSData.class])data=Get(data,@"data");
        return !TIOOTADisarmedReadAllowed(data);
    }
    return FileCallBlock(method,args,teleprompter);
}
BOOL TIOOTADisarmedBlockCall(id call){return DisarmedBlock(call,NULL);}
// A well-formed rayneonet_sendMessage call with businessId 9 (the same reading DisarmedBlock uses).
static BOOL Business9Call(id call){
    NSString *method=Get(call,@"method");NSDictionary *args=Get(call,@"arguments");NSUInteger business=0;
    return [method isKindOfClass:NSString.class]&&[@"rayneonet_sendMessage" isEqualToString:method]&&[args isKindOfClass:NSDictionary.class]&&Business(args[@"businessId"],&business)&&business==9;
}
// The type 3 frame's raw JSON text (field 3): no backslash anywhere and exactly one
// occurrence of the quoted key. Without escapes every key's raw text is its decoded
// text, so a second key with the same name would show up as a second occurrence.
BOOL TIOOTARawJSONNamesKeyOnce(NSData *data,NSString *key){
    if(![data isKindOfClass:NSData.class]||!TIOOTAFrame(data))return NO;
    const uint8_t *b=data.bytes;NSUInteger at=0;uint64_t k,v;NSData *json=nil;
    // TIOOTAFrame accepted this payload, so every field below parses and appears at most once.
    while(at<data.length){if(!Var(b,data.length,&at,&k))return NO;
        if((k&7)==2){if(!Var(b,data.length,&at,&v)||v>data.length-at)return NO;if((k>>3)==3)json=[data subdataWithRange:NSMakeRange(at,(NSUInteger)v)];at+=(NSUInteger)v;}
        else if(!Var(b,data.length,&at,&v))return NO;}
    if(!json.length||memchr(json.bytes,'\\',json.length))return NO;
    NSData *quoted=[[NSString stringWithFormat:@"\"%@\"",key] dataUsingEncoding:NSUTF8StringEncoding];
    NSRange first=[json rangeOfData:quoted options:0 range:NSMakeRange(0,json.length)];if(first.location==NSNotFound)return NO;
    NSUInteger after=NSMaxRange(first);
    return [json rangeOfData:quoted options:0 range:NSMakeRange(after,json.length-after)].location==NSNotFound;
}
BOOL TIOOTAArmRequired(void){
    if(TIOOTADownloadOnlyHost())return NO;
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    // Any one sign of the full 1.0.11 build asks for the arm step: refusing more is the safe side.
    return [TIOHostProfileFor(TIOHostMainImage(),info) isEqual:@"ios1011"]||[info[@"TIOHostProfile"] isEqual:@"ios1011"]||
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:TIO_OTA_1011_ROUTING_MARKER];
}
// The arm record lives in the addon's own preferences suite, never in the host's.
// It names the addon image it was made by: that image's LC_UUID. LC_UUID is a hash of
// the dylib's contents, not an install identity. An addon dylib that differs by one byte
// reads as disarmed, but a repackage with a byte-identical dylib stays armed, and a
// C15 -> C13 -> C15 round trip keeps the record (C13 never reads or clears it).
// Disarm before rolling back.
static NSString *const ArmKey=@"otaFlashArmRecord.ios1011";
static NSString *ArmSuite(void){return @"io.turboio.official-private-addon";}
// Only the suite's own persistent domain (current user, any host). CFPreferencesCopyValue
// looks in that one domain and nowhere else, so a launch argument (NSArgumentDomain,
// e.g. -otaFlashArmRecord.ios1011 <dict>), a registered default or the host's own
// preferences can never arm. -[NSUserDefaults initWithSuiteName:] searches the argument
// domain too, so it is not used here.
static id ArmRecord(void){
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)ArmKey,(__bridge CFStringRef)ArmSuite(),kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
}
static void ArmRecordWrite(id record){
    CFPreferencesSetValue((__bridge CFStringRef)ArmKey,(__bridge CFPropertyListRef)record,(__bridge CFStringRef)ArmSuite(),kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)ArmSuite(),kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
}
static NSString *ArmImageUUID(void){
    Dl_info info;if(!dladdr((const void *)&TIOOTAArmRequired,&info)||!info.dli_fbase)return nil;
    const struct mach_header_64 *h=info.dli_fbase;if(h->magic!=MH_MAGIC_64||h->ncmds>1024||h->sizeofcmds>1024*1024)return nil;
    const uint8_t *p=(const uint8_t *)(h+1),*end=p+h->sizeofcmds;
    for(uint32_t i=0;i<h->ncmds;i++){
        if((size_t)(end-p)<sizeof(struct load_command))return nil;
        const struct load_command *c=(const void *)p;if(c->cmdsize<sizeof(*c)||c->cmdsize>(size_t)(end-p))return nil;
        if(c->cmd==LC_UUID&&c->cmdsize==sizeof(struct uuid_command))return [[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString];
        p+=c->cmdsize;
    }
    return nil;
}
// The addon image does not change while it is loaded: read its load commands once.
static NSString *ArmInstallID(void){
    static NSString *uuid;static dispatch_once_t once;dispatch_once(&once,^{uuid=ArmImageUUID();});return uuid;
}
// A CFNumber (so not a CFBoolean, not an NSDecimalNumber or other NSNumber subclass).
static BOOL ArmPlainNumber(id n){
    return [n isKindOfClass:NSNumber.class]&&![n isKindOfClass:NSDecimalNumber.class]&&CFGetTypeID((__bridge CFTypeRef)n)==CFNumberGetTypeID();
}
static BOOL ArmRecordValid(id r){
    NSString *install=ArmInstallID();
    if(!install||![r isKindOfClass:NSDictionary.class]||[r count]!=4)return NO;
    // v: the integer 1, written as an integer (not @YES, @1.0 or a decimal number).
    id v=r[@"v"];if(!ArmPlainNumber(v)||CFNumberIsFloatType((__bridge CFNumberRef)v)||[v longLongValue]!=1)return NO;
    return [r[@"host"] isEqual:@"ios1011"]&&[r[@"install"] isKindOfClass:NSString.class]&&[r[@"install"] isEqualToString:install]&&ArmPlainNumber(r[@"armedAt"]);
}
BOOL TIOOTAFlashArmed(void){return TIOOTAArmRequired()&&ArmRecordValid(ArmRecord());}
// The flash build AND the full host's routing marker AND the pinned image: fixed for the process.
static BOOL ArmTransferHost(void){
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    return TIOOTAFlashBuild()&&TIOOTA1011HostMatches(info)&&TIOHostFullImageMatches(TIOHostMainImage(),info);
}
// Armed AND ArmTransferHost.
static BOOL ArmedForTransfer(void){return TIOOTAFlashArmed()&&ArmTransferHost();}
BOOL TIOOTAFlashArm(NSError **error){
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    if(!TIOOTAArmRequired()||!TIOOTA1011HostMatches(info)||!TIOHostFullImageMatches(TIOHostMainImage(),info)){Error(error,TIOText(@"只有完整版 1.0.11 宿主需要并允许启用 TMG 刷写；未启用。"));return NO;}
    if(!TIOOTAFlashProtected()){Error(error,TIOText(@"没有试刷构建与发送保护；未开放。"));return NO;}
    NSString *install=ArmInstallID();if(!install){Error(error,TIOText(@"无法确认本次安装；未启用。"));return NO;}
    ArmRecordWrite(@{@"v":@1,@"host":@"ios1011",@"install":install,@"armedAt":@(floor(NSDate.date.timeIntervalSince1970))});
    if(!TIOOTAFlashArmed()){Error(error,TIOText(@"无法保存启用状态；未启用。"));return NO;}
    return YES;
}
BOOL TIOOTAFlashDisarm(void){
    // The guard runs on the main thread (the rayneonet hook); disarm runs there too, so no
    // business-9 frame can move the gate between the cancel and the record removal.
    if(!NSThread.isMainThread){__block BOOL done=NO;dispatch_sync(dispatch_get_main_queue(),^{done=TIOOTAFlashDisarm();});return done;}
    // Never cut a running transfer: the glasses would be left mid-flash. The cancel itself
    // decides (it refuses at stage 2, a started or completed transfer, and at stage 3, a failed
    // one; both last until the app restarts); if it refuses,
    // the record stays.
    if(![Current() cancel])return NO;
    ArmRecordWrite(nil);
    return !ArmRecordValid(ArmRecord());
}
NSDictionary *TIOOTAFlashArmStatus(void){
    BOOL required=TIOOTAArmRequired();id r=required?ArmRecord():nil;BOOL armed=required&&ArmRecordValid(r);
    NSMutableDictionary *s=[@{@"armRequired":@(required),@"armed":@(armed),@"armedForTransfer":@(required&&ArmedForTransfer())} mutableCopy];
    if(armed)s[@"armedAt"]=r[@"armedAt"];
    return s;
}
// A disconnect, unbind or unpair call forgets the version read and revokes a stage 1 grant.
static void ObserveDisconnect(id method){
    if(![method isKindOfClass:NSString.class])return;
    if([[method lowercaseString] containsString:@"disconnect"]||[[method lowercaseString] containsString:@"unbind"]||[[method lowercaseString] containsString:@"unpair"]){@synchronized(NSProcessInfo.processInfo){ObservedDevice=nil;ObservedAt=0;}[Current() cancel];}
}
BOOL TIOOTAFlashBlockCallSnapshot(id call,NSDictionary **teleprompter){
    if(teleprompter)*teleprompter=nil;
    if(TIOOTADownloadOnlyHost())return DownloadOnlyBlock(call,teleprompter);
    if(TIOOTAArmRequired()){
        // Only a business-9 frame can depend on the arm state: for every other call the
        // disarmed rule and the armed (1.0.7) rule give the same verdict, so the record is
        // not read for them. The 1.0.7 path's disconnect side effect (forget the version
        // read, revoke a stage 1 grant) still runs, armed or not, in every build.
        if(!Business9Call(call)){ObserveDisconnect(Get(call,@"method"));return DisarmedBlock(call,teleprompter);}
        // Once a transfer has started (stage 2) the record is not read again: a record read
        // failure, a preferences glitch or a disarm racing the guard cannot cut it. The host
        // checks still apply, and the 1.0.7 gate below decides every frame.
        if(!(GateStage()==2?ArmTransferHost():ArmedForTransfer()))return DisarmedBlock(call,teleprompter);
    }
    if(!TIOOTAFlashBuild())return NO;
    NSString *method=Get(call,@"method");NSDictionary *args=Get(call,@"arguments");
    if(![method isKindOfClass:NSString.class])return YES;
    ObserveDisconnect(method);
    if([@"rayneonet_sendMessage" isEqualToString:method]){
        NSUInteger business=0;if(![args isKindOfClass:NSDictionary.class]||!Business(args[@"businessId"],&business))return YES;
        if(business!=9)return NO;
        id data=args[@"payload"];if(![data isKindOfClass:NSData.class])data=Get(data,@"data");
        if(!TIOOTAHostMatches(NSBundle.mainBundle.infoDictionary))
            return !TIOOTAIsEmptyVersionQuery(data);
#if TIO_DISPLAY_PHONE && !TIO_DISPLAY_FLASH
        // Phone-only test package: no OTA mutation, even if an old gate was armed.
        return !TIOPhoneOTAReadAllowed(data);
#endif
        return ![Current() allows:data device:args[@"deviceId"] uptime:NSProcessInfo.processInfo.systemUptime];
    }
    return FileCallBlock(method,args,teleprompter);
}
BOOL TIOOTAFlashBlockCall(id call){return TIOOTAFlashBlockCallSnapshot(call,NULL);}
void TIOOTAFlashObserveEvent(NSDictionary *event){
    if(!TIOOTAFlashBuild()||![event[@"eventType"] isEqual:@"messageReceived"])return;
    NSDictionary *m=event[@"message"];NSUInteger business=0;if(![m isKindOfClass:NSDictionary.class]||!Business(m[@"businessId"],&business)||business!=9)return;
    NSDictionary *f=TIOOTAFrame(m[@"payload"]);id j=f[@"json"];
    if([f[@"type"] isEqual:@1]){@synchronized(NSProcessInfo.processInfo){ObservedDevice=nil;ObservedAt=0;}}
    if([f[@"type"] isEqual:@1]&&[j isKindOfClass:NSDictionary.class]&&[@[@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5"] containsObject:j[@"OsVersion"]]&&[j[@"OtaValidationConfirmed"] isEqual:@YES]&&[m[@"deviceId"] isKindOfClass:NSString.class]){
        @synchronized(NSProcessInfo.processInfo){ObservedDevice=[m[@"deviceId"] copy];ObservedAt=NSProcessInfo.processInfo.systemUptime;}
    }
}
BOOL TIOOTAFlashAuthorize(NSError **error){
    if(!TIOOTAHostMatches(NSBundle.mainBundle.infoDictionary)){Error(error,TIOText(@"1.0.7 OTA 专用宿主或路由标记不匹配，未授权。"));return NO;}
    if(TIOOTAArmRequired()&&!ArmedForTransfer()){Error(error,TIOText(@"本机 TMG 刷写尚未启用；先在向导中启用，未授权。"));return NO;}
    NSDictionary *feed=TIOExperimentalOTAFeedStatus();
    if(![feed[@"bootstrapEligible"] boolValue]||![feed[@"running"] boolValue]||![feed[@"healthPassed"] boolValue]){Error(error,TIOText(@"未确认本机下载来源与健康检查，未授权。"));return NO;}
#if TARGET_OS_IPHONE && TIO_DISPLAY_PHONE
    if(TAPPhoneBridge.shared.busy||TAPPhoneBridge.shared.needsReadback){Error(error,TIOText(@"应用文件仍在传输或结果未知，先查询完成；未开放升级。"));return NO;}
#endif
    if(!TIOOTAFlashProtected()){Error(error,TIOText(@"没有试刷构建与发送保护；未开放。"));return NO;}
#if TARGET_OS_IPHONE && TIO_DISPLAY_FLASH
    if(!TDPPhonePauseForOTA()){Error(error,TIOText(@"显示文件仍在传输或结果未知，请等待终态；未开放升级。若任务无法收尾，先退出显示页并重启 App 重新检查。"));return NO;}
#endif
    if(!TIOOTAAutoUpdateDisabled(NSUserDefaults.standardUserDefaults.dictionaryRepresentation)){Error(error,TIOText(@"请先在官方眼镜软件版本页关闭自动更新；未读到明确关闭状态，不授予试刷权限。"));return NO;}
    NSString *device;NSTimeInterval at;@synchronized(NSProcessInfo.processInfo){device=ObservedDevice;at=ObservedAt;}
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(!device.length||now-at>120){Error(error,TIOText(@"请先从官方固件页重新检查版本；需要两分钟内的 1.0.4.12 或 1.0.5.5 有效回读。"));return NO;}
    NSURL *dir=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.5.5"] isDirectory:YES];
    return [Current() prepareDirectory:dir device:device uptime:now error:error];
}
BOOL TIOOTAFlashCancel(void){return [Current() cancel];}
NSDictionary *TIOOTAFlashStatus(void){NSMutableDictionary *s=[[Current() status] mutableCopy];s[@"flashBuild"]=@(TIOOTAFlashBuild());[s addEntriesFromDictionary:TIOOTAFlashArmStatus()];s[@"automaticUpdateDisabled"]=@(TIOOTAAutoUpdateDisabled(NSUserDefaults.standardUserDefaults.dictionaryRepresentation));@synchronized(NSProcessInfo.processInfo){s[@"recentTargetVersionRead"]=@(ObservedDevice.length&&NSProcessInfo.processInfo.systemUptime-ObservedAt<=120);s[@"versionReadAge"]=@(ObservedDevice.length?MAX(0,NSProcessInfo.processInfo.systemUptime-ObservedAt):-1);}return s;}
