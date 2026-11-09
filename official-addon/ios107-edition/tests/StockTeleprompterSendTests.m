// D5: the stock teleprompter's rayneonet_sendFile is the one stock file send the
// OTA guard lets through, on the 1.0.7 flash host and on the 1.0.11 download-only
// host. Runs the unchanged phone policy (ExperimentalOTAFlash.m adapted by test.py
// exactly like ios1011-guard) against fake app containers in a temp directory.
// No device, network or signing.
//
// test.py builds this file in the same four TIO_* flag sets as ios1011-guard and
// requires the same sweep= digest from each: the allow-list depends on no flag.
#import "TMG4WizardHost.h"
#import "HostCompatibility.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAGuard.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
static NSString *Home;
static NSDictionary *Host;
static const struct mach_header *Image;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return 100;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return @{@"fixture_ota_firmware_auto_update":@NO};}
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
static NSFileManager *FM;
static NSUInteger Cases;
static NSMutableString *Bits;
static NSString *const Lower=@"0f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5b";
static NSString *const Upper=@"0F8E2C1A-3B4D-4E5F-8A9B-0C1D2E3F4A5B";
static NSString *const Lib=@"Library/Application Support/user_123/teleprompter";
static NSString *const Doc=@"Documents/user_123/teleprompter";
static void Dir(NSString *path){assert([FM createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);}
static NSString *Put(NSString *path,NSData *bytes){Dir(path.stringByDeletingLastPathComponent);assert([bytes writeToFile:path atomically:NO]);return path;}
static NSData *Text(NSUInteger n){NSMutableData *d=[NSMutableData dataWithLength:n];memset(d.mutableBytes,'t',n);return d;}
static NSDictionary *Args(NSString *path,NSString *task){return @{@"deviceId":@"fixture-peer",@"filePath":path,@"taskId":task};}
// One check, recorded in the sweep (unless the outcome is flag-dependent by design).
static void Expect(NSString *container,NSString *method,id args,NSUInteger stage,BOOL want){
    BOOL got=TIOStockTeleprompterSendAllowedIn(container,method,args,stage);
    if(got!=want){NSLog(@"FAIL case %lu: want %d got %d args=%@ stage=%lu",(unsigned long)Cases,want,got,args,(unsigned long)stage);abort();}
    [Bits appendString:got?@"1":@"0"];Cases++;
}
static void Allow(NSString *c,id args){Expect(c,@"rayneonet_sendFile",args,0,YES);}
static void Refuse(NSString *c,id args){Expect(c,@"rayneonet_sendFile",args,0,NO);}
static NSString *Digest(NSString *s){
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];uint8_t h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);
    NSMutableString *x=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[x appendFormat:@"%02x",h[i]];return x;
}
// The pure allow-list, against an explicit container.
static void PureCases(NSString *C){
    char real[PATH_MAX];assert(realpath(C.UTF8String,real));NSString *R=@(real);
    NSString *lib=Put([NSString stringWithFormat:@"%@/%@/%@",C,Lib,Lower],Text(4096));
    NSString *doc=Put([NSString stringWithFormat:@"%@/%@/%@",C,Doc,Upper],Text(1));
    // Its own folder: on a case-insensitive disk the two UUID spellings would name one file.
    NSString *libUpper=Put([NSString stringWithFormat:@"%@/Library/Application Support/user_124/teleprompter/%@",C,Upper],Text(1048576));
    // The exact shape under both roots, both UUID cases, both spellings of the container.
    Allow(C,Args(lib,Lower));Allow(C,Args(doc,Upper));Allow(C,Args(libUpper,Upper));
    Allow(C,Args([lib stringByReplacingOccurrencesOfString:C withString:R],Lower));
    NSString *longUser=Put([NSString stringWithFormat:@"%@/Documents/user_01234567890123456789/teleprompter/%@",C,Lower],Text(10));
    Allow(C,Args(longUser,Lower));
    // Any other OTA stage, any other method.
    for(NSUInteger stage=1;stage<=3;stage++){Expect(C,@"rayneonet_sendFile",Args(lib,Lower),stage,NO);Expect(C,@"rayneonet_sendFile",Args(doc,Upper),stage,NO);}
    Expect(C,@"rayneonet_sendFile",Args(lib,Lower),NSUIntegerMax,NO);
    for(NSString *m in @[@"rayneonet_sendfile",@"rayneonet_sendFile ",@"rayneonet_sendFileAlternate",@"rayneonet_sendMessage",@"rayneonet_startOTA",@""])Expect(C,m,Args(lib,Lower),0,NO);
    Expect(C,(NSString *)@1,Args(lib,Lower),0,NO);Expect(C,nil,Args(lib,Lower),0,NO);
    // Key set: each key missing, an extra key, a renamed key, not a dictionary.
    NSDictionary *good=Args(lib,Lower);
    for(NSString *k in good){NSMutableDictionary *m=[good mutableCopy];[m removeObjectForKey:k];Refuse(C,m);}
    for(id extra in @[@"businessId",@"path",@"fileName",@1]){NSMutableDictionary *m=[good mutableCopy];m[extra]=@"x";Refuse(C,m);}
    Refuse(C,@{@"deviceid":@"fixture-peer",@"filePath":lib,@"taskId":Lower});
    Refuse(C,@{@"deviceId":@"fixture-peer",@"filepath":lib,@"taskId":Lower});
    Refuse(C,nil);Refuse(C,@[lib]);Refuse(C,lib);Refuse(C,@{});Refuse(C,NSNull.null);
    // Value types: NSNull, NSNumber, empty, arrays, data, too long.
    for(NSString *k in good)for(id v in @[NSNull.null,@0,@1,@"",@[good[k]],[good[k] dataUsingEncoding:NSUTF8StringEncoding],@{}]){NSMutableDictionary *m=[good mutableCopy];m[k]=v;Refuse(C,m);}
    {NSMutableDictionary *m=[good mutableCopy];m[@"deviceId"]=[@"" stringByPaddingToLength:257 withString:@"d" startingAtIndex:0];Refuse(C,m);
     m[@"deviceId"]=[@"" stringByPaddingToLength:256 withString:@"d" startingAtIndex:0];Allow(C,m);}
    // taskId must be the file's UUID.
    Refuse(C,Args(lib,Upper));Refuse(C,Args(lib,@"11111111-2222-4333-8444-555555555555"));Refuse(C,Args(doc,Lower));
    // Names: not a UUID, one char more or less, wrong dashes, mixed case, non-hex, braces, unicode.
    NSArray *names=@[@"teleprompter",@"0f8e2c1a3b4d4e5f8a9b0c1d2e3f4a5b",[Lower stringByAppendingString:@"0"],[Lower substringFromIndex:1],
        [Lower stringByAppendingString:@".txt"],@"0f8e2c1a_3b4d_4e5f_8a9b_0c1d2e3f4a5b",@"0f8e2c1a3-b4d-4e5f-8a9b-0c1d2e3f4a5b",@"0f8e2c1a-3b4d-4e5f-8a9b0-c1d2e3f4a5b",
        @"0f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5B",@"0g8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5b",@"{f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5}",@"0f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5é",
        @"0f8e2c1a-3b4d-4e5f-8a9b-0c1d2e3f4a5 ",@"0f8e2c1a--b4d-4e5f-8a9b-0c1d2e3f4a5b",@"------------------------------------"];
    // Each in its own folder: on a case-insensitive disk a case variant would otherwise reopen the valid file.
    NSUInteger u=600;for(NSString *n in names){NSString *p=Put([NSString stringWithFormat:@"%@/Library/Application Support/user_%lu/teleprompter/%@",C,(unsigned long)u++,n],Text(8));Refuse(C,Args(p,n));}
    // Path spelling: .., //, /./, trailing slash, relative, NUL, outside the container.
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123/../user_123/teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123/teleprompter/../teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@//Library/Application Support/user_123/teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123//teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123/teleprompter//%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/./Library/Application Support/user_123/teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123/./teleprompter/%@",C,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/Library/Application Support/user_123/teleprompter/./%@",C,Lower],Lower));
    Refuse(C,Args([lib stringByAppendingString:@"/"],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/%@",Lib,Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"Library/Application Support/user_123/teleprompter/%@",Lower],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@\0/x",lib],Lower));
    Refuse(C,Args([NSString stringWithFormat:@"%@/../%@/%@/%@",C,C.lastPathComponent,Lib,Lower],Lower));
    // Wrong layout: extra or missing folder, user_ without digits or with letters, global variants.
    for(NSString *rel in @[@"Library/Application Support/user_123/teleprompter/sub",@"Library/Application Support/teleprompter",@"Library/Application Support/user_123/x/teleprompter",
        @"Library/Application Support/user_/teleprompter",@"Library/Application Support/user_12a/teleprompter",@"Library/Application Support/user_-1/teleprompter",
        @"Library/Application Support/user_ 1/teleprompter",@"Library/Application Support/user_012345678901234567890/teleprompter",
        @"Library/Application Support/global/teleprompter",@"Library/Application Support/user_global/teleprompter",@"Library/Application Support/user_123/teleprompter_global",
        @"Library/Application Support/user_123/global/teleprompter",@"Library/Application Support/global/user_123/teleprompter",
        @"Documents/global/teleprompter",@"Documents/teleprompter",@"Documents/user_/teleprompter",@"Documents/user_12a/teleprompter",
        @"Library/Caches/user_123/teleprompter",@"Library/user_123/teleprompter",@"tmp/user_123/teleprompter",@"user_123/teleprompter",
        @"Library/Application Support/ota",@"Library/Application Support/ota/user_123/teleprompter",
        // Case tricks.
        @"Library/Application Support/user_123/Teleprompter",@"Library/Application Support/user_123/TELEPROMPTER",@"Library/application support/user_123/teleprompter",
        @"library/Application Support/user_123/teleprompter",@"Library/Application Support/USER_123/teleprompter",@"documents/user_123/teleprompter",@"DOCUMENTS/user_123/teleprompter",
        @"Documents/User_123/teleprompter",@"Documents/user_123/Teleprompter"]){
        NSString *p=[NSString stringWithFormat:@"%@/%@/%@",C,rel,Lower];
        // On a case-insensitive disk the case variants name the real file; create the rest.
        if(![FM fileExistsAtPath:p])Put(p,Text(8));
        Refuse(C,Args(p,Lower));
    }
    // Another app's container, and the container passed in a different spelling.
    NSString *other=[C.stringByDeletingLastPathComponent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *otherFile=Put([NSString stringWithFormat:@"%@/%@/%@",other,Lib,Lower],Text(8));
    Refuse(C,Args(otherFile,Lower));Allow(other,Args(otherFile,Lower));
    Refuse([C stringByAppendingString:@"/"],Args(lib,Lower));Refuse(@"",Args(lib,Lower));Refuse(nil,Args(lib,Lower));
    Refuse([C stringByAppendingString:@"/Library"],Args(lib,Lower));Refuse(@"Library",Args(lib,Lower));
    Refuse(C.lastPathComponent,Args(lib,Lower));
    Refuse(Lib,Args(lib,Lower));
    // A prefix that is a sibling name: <C>x/...
    NSString *sibling=[C stringByAppendingString:@"x"];NSString *sibFile=Put([NSString stringWithFormat:@"%@/%@/%@",sibling,Lib,Lower],Text(8));Refuse(C,Args(sibFile,Lower));
    // Missing file.
    Refuse(C,Args([NSString stringWithFormat:@"%@/Documents/user_77/teleprompter/%@",C,Lower],Lower));
    // Symlinks: the file, the teleprompter folder, the user folder, Documents itself, into ota/.
    NSString *ota=Put([NSString stringWithFormat:@"%@/Library/Application Support/ota/Strix_OS_1.0.5.5/nuttx_ap.bin",C],Text(64));
    NSString *s1=[NSString stringWithFormat:@"%@/Library/Application Support/user_200/teleprompter/%@",C,Lower];Dir(s1.stringByDeletingLastPathComponent);
    assert([FM createSymbolicLinkAtPath:s1 withDestinationPath:ota error:nil]);Refuse(C,Args(s1,Lower));
    NSString *s2=[NSString stringWithFormat:@"%@/Library/Application Support/user_201/teleprompter/%@",C,Lower];Dir(s2.stringByDeletingLastPathComponent);
    assert([FM createSymbolicLinkAtPath:s2 withDestinationPath:lib error:nil]);Refuse(C,Args(s2,Lower));
    NSString *s2r=[NSString stringWithFormat:@"%@/Library/Application Support/user_202/teleprompter/%@",C,Lower];Dir(s2r.stringByDeletingLastPathComponent);
    assert([FM createSymbolicLinkAtPath:s2r withDestinationPath:[@"../../user_123/teleprompter" stringByAppendingPathComponent:Lower] error:nil]);Refuse(C,Args(s2r,Lower));
    NSString *otaDir=ota.stringByDeletingLastPathComponent;Put([otaDir stringByAppendingPathComponent:Lower],Text(8));
    NSString *td=[NSString stringWithFormat:@"%@/Library/Application Support/user_300/teleprompter",C];Dir(td.stringByDeletingLastPathComponent);
    assert([FM createSymbolicLinkAtPath:td withDestinationPath:otaDir error:nil]);Refuse(C,Args([td stringByAppendingPathComponent:Lower],Lower));
    NSString *ud=[NSString stringWithFormat:@"%@/Library/Application Support/user_301",C];
    assert([FM createSymbolicLinkAtPath:ud withDestinationPath:@"user_123" error:nil]);Refuse(C,Args([NSString stringWithFormat:@"%@/teleprompter/%@",ud,Lower],Lower));
    NSString *docs2=[NSString stringWithFormat:@"%@/Documents",other];Put([NSString stringWithFormat:@"%@/user_5/teleprompter/%@",docs2,Lower],Text(8));
    NSString *ctr3=[C.stringByDeletingLastPathComponent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];Dir(ctr3);
    assert([FM createSymbolicLinkAtPath:[ctr3 stringByAppendingPathComponent:@"Documents"] withDestinationPath:docs2 error:nil]);
    Refuse(ctr3,Args([NSString stringWithFormat:@"%@/Documents/user_5/teleprompter/%@",ctr3,Lower],Lower));
    // A container that is itself reached through a symlink still works through its own spelling (that is /var on iOS).
    NSString *alias=[C.stringByDeletingLastPathComponent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([FM createSymbolicLinkAtPath:alias withDestinationPath:C error:nil]);
    Allow(alias,Args([lib stringByReplacingOccurrencesOfString:C withString:alias],Lower));
    Refuse(C,Args([lib stringByReplacingOccurrencesOfString:C withString:alias],Lower)); // alias is not C's spelling
    // A hard link to another file.
    NSString *hl=[NSString stringWithFormat:@"%@/Documents/user_400/teleprompter/%@",C,Lower];Dir(hl.stringByDeletingLastPathComponent);
    assert(link(ota.UTF8String,hl.UTF8String)==0);Refuse(C,Args(hl,Lower));
    // Not a regular file: a folder, a FIFO.
    NSString *dirName=[NSString stringWithFormat:@"%@/Documents/user_401/teleprompter/%@",C,Lower];Dir(dirName);Refuse(C,Args(dirName,Lower));
    NSString *fifo=[NSString stringWithFormat:@"%@/Documents/user_402/teleprompter/%@",C,Lower];Dir(fifo.stringByDeletingLastPathComponent);
    assert(mkfifo(fifo.UTF8String,0600)==0);Refuse(C,Args(fifo,Lower));
    // Size and content: empty, 1 MiB + 1, a ZIP renamed to a UUID, "P" alone, "PK" only, "PK" later in the file.
    NSString *(^At)(NSString *,NSData *)=^(NSString *user,NSData *bytes){return Put([NSString stringWithFormat:@"%@/Documents/%@/teleprompter/%@",C,user,Lower],bytes);};
    Refuse(C,Args(At(@"user_500",[NSData data]),Lower));
    Refuse(C,Args(At(@"user_501",Text(1048577)),Lower));
    NSMutableData *zip=[NSMutableData dataWithBytes:"PK\x03\x04" length:4];[zip appendData:Text(100)];Refuse(C,Args(At(@"user_502",zip),Lower));
    Refuse(C,Args(At(@"user_503",[NSData dataWithBytes:"PK" length:2]),Lower));
    Refuse(C,Args(At(@"user_504",[NSData dataWithBytes:"PK\x05\x06" length:4]),Lower));
    Allow(C,Args(At(@"user_505",[NSData dataWithBytes:"P" length:1]),Lower));
    Allow(C,Args(At(@"user_506",[NSData dataWithBytes:"pk  " length:4]),Lower));
    NSMutableData *late=[Text(10) mutableCopy];[late appendBytes:"PK\x03\x04" length:4];Allow(C,Args(At(@"user_507",late),Lower));
    // Unreadable file: refused, not crashed.
    NSString *locked=At(@"user_508",Text(8));chmod(locked.UTF8String,0);Refuse(C,Args(locked,Lower));chmod(locked.UTF8String,0600);
}
// The dispatching entry point on the given host: the teleprompter shape passes, the rest is unchanged.
static void HostCases(BOOL downloadOnly){
    NSString *lib=[NSString stringWithFormat:@"%@/%@/%@",Home,Lib,Lower],*doc=[NSString stringWithFormat:@"%@/%@/%@",Home,Doc,Upper];
    NSDictionary *call=@{@"method":@"rayneonet_sendFile",@"arguments":Args(lib,Lower)};
    assert(TIOStockTeleprompterSendAllowed(@"rayneonet_sendFile",Args(lib,Lower),0));
    assert(!TIOStockTeleprompterSendAllowed(@"rayneonet_sendFile",Args(lib,Lower),1));
    NSArray *refusedCalls=@[
        @{@"method":@"rayneonet_sendFile",@"arguments":@{@"path":@"/tmp/x.zip"}},
        @{@"method":@"rayneonet_sendFile",@"arguments":@{@"deviceId":@"fixture-peer",@"filePath":lib,@"taskId":Lower,@"businessId":@17}},
        @{@"method":@"rayneonet_sendFile",@"arguments":Args([NSString stringWithFormat:@"%@/Documents/user_500/teleprompter/%@",Home,Lower],Lower)},
        @{@"method":@"rayneonet_sendFile",@"arguments":Args([NSString stringWithFormat:@"%@/Documents/user_502/teleprompter/%@",Home,Lower],Lower)},
        @{@"method":@"rayneonet_sendFile",@"arguments":Args([NSString stringWithFormat:@"%@/Library/Application Support/user_200/teleprompter/%@",Home,Lower],Lower)},
        // A stock photo send: an image under the container, not the teleprompter shape.
        @{@"method":@"rayneonet_sendFile",@"arguments":@{@"deviceId":@"fixture-peer",@"filePath":[Home stringByAppendingPathComponent:@"Documents/photo.jpg"],@"taskId":Lower,@"type":@1}},
        @{@"method":@"rayneonet_sendFile",@"arguments":Args(lib,Upper)},
        @{@"method":@"rayneonet_sendFileAlternate",@"arguments":Args(lib,Lower)},
        @{@"method":@"rayneonet_startOta",@"arguments":Args(lib,Lower)},
        @{@"method":@"rayneonet_upgrade",@"arguments":@{}},
        @{@"arguments":Args(lib,Lower)},
    ];
    NSData *query=[NSData dataWithBytes:"\x08\x01\x10\x01" length:4];
    NSData *start=[NSData dataWithBytes:"\x08\x01\x10\x04\x1a\x0a{\"Mode\":4}" length:16];
    if(downloadOnly){
        assert(TIOOTADownloadOnlyHost());
        assert(!TIOOTAFlashBlockCall(call));assert(!TIOOTADownloadOnlyBlockCall(call));
        assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendFile",@"arguments":Args(doc,Upper)}));
        for(NSDictionary *c in refusedCalls){assert(TIOOTAFlashBlockCall(c));assert(TIOOTADownloadOnlyBlockCall(c));}
        // Business 9: still only the empty version query; wide ids still refused; other businesses pass.
        assert(TIOOTAIsEmptyVersionQuery(query));
        assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":query}}));
        assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":start}}));
        assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@265,@"deviceId":@"fixture-peer",@"payload":query}}));
        assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@17,@"deviceId":@"fixture-peer",@"payload":start}}));
        // Recorded in the sweep: these outcomes must not depend on the build flags.
        for(NSDictionary *c in [refusedCalls arrayByAddingObject:call])[Bits appendString:TIOOTAFlashBlockCall(c)?@"1":@"0"];
    }else{
        assert(!TIOOTADownloadOnlyHost());assert(TIOOTA107HostMatches(Host));
#if TIO_OTA_FLASH_ENABLED
        // The 1.0.7 flash host: the shape passes at stage 0, everything else refused as before.
        assert(TIOOTAFlashBuild());assert([TIOOTAFlashStatus()[@"stage"] intValue]==0);
        assert(!TIOOTAFlashBlockCall(call));assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendFile",@"arguments":Args(doc,Upper)}));
        for(NSDictionary *c in refusedCalls)assert(TIOOTAFlashBlockCall(c));
        assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":start}}));
        assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@265,@"deviceId":@"fixture-peer",@"payload":query}}));
#else
        // Without the flash build the 1.0.7 path guards nothing, as before.
        assert(!TIOOTAFlashBuild());assert(!TIOOTAFlashBlockCall(call));
#endif
    }
    // Scoped addon calls: the stage rule is unchanged (scoped passes only at stage 0).
    assert(!TIOOTAFileCallBlocked(@"rayneonet_sendFile",YES,0));
    for(NSUInteger stage=1;stage<=3;stage++){assert(TIOOTAFileCallBlocked(@"rayneonet_sendFile",YES,stage));assert(TIOOTAFileCallBlocked(@"rayneonet_sendFile",NO,stage));}
    assert(TIOOTAFileCallBlocked(@"rayneonet_sendFile",NO,0));assert(TIOOTAFileCallBlocked(@"rayneonet_startOTA",YES,0));
}
int main(void){@autoreleasepool{
    FM=NSFileManager.defaultManager;Bits=[NSMutableString new];
    // NSTemporaryDirectory() is /var/folders/..., whose realpath is /private/var/...: the same
    // shape as an iOS container, so both spellings of the root are exercised.
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"d5-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    Home=[base stringByAppendingPathComponent:NSUUID.UUID.UUIDString];Dir(Home);
    char real[PATH_MAX];assert(realpath(Home.UTF8String,real));
    PureCases(Home);
    // The same cases against the resolved container spelling.
    NSString *home2=[base stringByAppendingPathComponent:NSUUID.UUID.UUIDString];Dir(home2);assert(realpath(home2.UTF8String,real));
    PureCases(@(real));
    // 1.0.11 download-only host.
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011-download"};
    Image=FakeImage(@"22724C97-2EF9-388D-8E6A-6E051855A555");
    HostCases(YES);TIOOTARecordTransportHookReady();HostCases(YES);
    BOOL flash1011=TIOOTAFlashBuild(); // what test.py checks per flag set, as for ios1011-guard
    // 1.0.7 OTA host.
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    Image=FakeImage(@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B");
    NSString *sweep=[Bits copy];
    HostCases(NO);
    assert([TIOOTADownloadOnlyGuardMarker containsString:@"IOS1011-DOWNLOAD-GUARD-03"]&&[TIOOTADownloadOnlyGuardMarker containsString:@"stock teleprompter sendFile allow-listed"]);
    [FM removeItemAtPath:base error:nil];
    NSLog(@"PASS: stock teleprompter sendFile allow-list: %lu cases; flash build %s; sweep=%@",(unsigned long)Cases,flash1011?"on":"off",Digest(sweep));
}return 0;}
