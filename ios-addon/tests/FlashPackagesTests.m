// The two packages of one release (TMG15 first, stock 1.0.6.11 second) through the real guard and gate
// (ExperimentalOTAFlash.m, adapted by test.py like flash-sequence-1021) on the full 1.0.21 host
// (tests/FullHostFixture.h), with both real release ZIPs unzipped by test.py. One run per mode, because stages 2
// and 3 last until the process ends:
//   fresh                  a new process selects TMG15, the first package;
//   stock-replay           stock selected: the sequence recorded on 2026-11-15 (tests/flash-sequence-1021.json)
//                          replays with the stock ZIP size, manifest and slices and is allowed, with the slice
//                          totals test.py computed from the stock ZIP in the recorded file order;
//   tmg-stock-manifest     TMG15 authorized and started: the stock manifest is refused;
//   tmg-stock-slice        TMG15 authorized, started, manifest sent: a stock nuttx_ap.bin slice is refused;
//   stock-tmg-manifest     the same the other way round;
//   stock-tmg-slice        the same the other way round;
//   size                   type 3 with the other package's ZIP size is refused at stages 0, 1 and 2;
//   select-stage1          a change of selection at stage 1 cancels the authorization; the folder then holds the
//                          other package and authorization fails with the member mismatch message;
//   select-stage2          a change at stage 2 is refused and the capture is unchanged;
//   select-stage3          a change at stage 3 is refused and the capture is unchanged;
//   index                  prepareDirectory:package: refuses an index that is not the selected one at the capture
//                          (ota.package.changed), each way, with the same capture allowed once it is selected;
//   version               (test-only package table, TIO_TEST_PACKAGE_TABLE: stock accepts only 1.0.6.11) a
//                          version read the selected package does not accept refuses authorization.
// argv: <TMG15 dir> <stock dir> <home root> <fixture> <mode> [<stock slices> <stock slice bytes>]. No device I/O.
#import "TMG4WizardHost.h"
#import "FullHostFixture.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#import "FirmwarePins.h"
#import "HostCompatibility.h"
#import "TIOLanguage.h"
#import <mach-o/loader.h>
#include <assert.h>
static NSString *Home;
static NSTimeInterval Now=100;
static NSDictionary *Prefs,*Host;
static const struct mach_header *Image;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return Now;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
BOOL TDPPhonePauseForOTA(void){return YES;}
const struct mach_header *TMG4MainImage(void){return Image;}
NSDictionary *TIOExperimentalOTAFeedStatus(void){return @{@"bootstrapEligible":@YES,@"running":@YES,@"healthPassed":@YES};}
#if TIO_TEST_PACKAGE_TABLE
// The test-only package table (test.py substitutes it into a copy of ExperimentalOTA.m): the real packages, with the
// stock package accepting only 1.0.6.11, because both real lists are equal.
NSArray *TMG4TestPackages(NSArray *real){
    assert(real.count==2);NSMutableDictionary *stock=[real[1] mutableCopy];
    stock[@"acceptOsVersions"]=@[@"Strix OS 1.0.6.11"];stock[@"acceptQueryCodes"]=@[@"01.00.06.0011"];stock[@"acceptVersionsText"]=@"1.0.6.11";
    return @[real[0],stock];
}
#endif
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *RawFrame(NSUInteger type,NSData *json,NSData *binary){
    NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);
    if(json){Var(d,26);Var(d,json.length);[d appendData:json];}
    if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}
    return d;
}
static NSData *Frame(NSUInteger type,id json,NSData *binary){return RawFrame(type,json&&json!=NSNull.null?[NSJSONSerialization dataWithJSONObject:json options:0 error:nil]:nil,binary);}
static NSString *const Peer=@"fixture-peer";
static BOOL Send(NSData *frame){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":Peer,@"payload":frame}});}
static void Receive(NSData *frame){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":Peer,@"payload":frame}});}
static void ReadVersion(NSString *version){Receive(Frame(1,@{@"OsVersion":version,@"OtaValidationStateCode":@4294967295u,@"OtaValidationState":@"idle",@"OtaValidationConfirmed":@YES,@"PackageInfoVersions":@[@1,@2],@"PackageTypes":@[@"files",@"zip"]},nil));}
static NSDictionary *Status(void){return TIOOTAFlashStatus();}
static NSUInteger Stage(void){return [Status()[@"stage"] unsignedIntegerValue];}
static NSString *Captured(void){return Status()[@"package"];}
static void Check(BOOL ok,const char *what){if(!ok){fprintf(stderr,"FAIL %s (stage %lu, package %s)\n",what,(unsigned long)Stage(),[Captured() UTF8String]);abort();}printf("ok: %s\n",what);}
static NSData *Slice(NSString *name,NSUInteger start,NSData *bytes){return Frame(7,@{@"Name":name,@"Start":@(start),@"Size":@(bytes.length)},bytes);}
static NSData *ZipSize(NSDictionary *package){return Frame(3,@{@"OtaSize":package[@"zipBytes"]},nil);}
static NSString *Directory(void){return [Home stringByAppendingPathComponent:[@"Library/Application Support/ota/" stringByAppendingString:TIO_FW_OTA_FOLDER]];}
// The release folder in the full host's container holds a copy of this unzipped package.
static void Place(const char *source){
    NSFileManager *fm=NSFileManager.defaultManager;[fm removeItemAtPath:Directory() error:nil];
    assert([fm createDirectoryAtPath:Directory().stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);
    assert([fm copyItemAtPath:@(source) toPath:Directory() error:nil]);
}
static BOOL Authorize(NSError **error){return TIOOTAFlashAuthorize(error);}
// The first offset where the two APs differ, on a slice boundary inside both.
static NSUInteger DifferingSlice(NSData *a,NSData *b){
    for(NSUInteger at=0;at<MIN(a.length,b.length);at+=51200){NSUInteger n=MIN((NSUInteger)51200,MIN(a.length,b.length)-at);if(memcmp((const uint8_t *)a.bytes+at,(const uint8_t *)b.bytes+at,n))return at;}
    abort();
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==6||argc==8);NSString *mode=@(argv[5]);NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *modes=@[@"fresh",@"stock-replay",@"tmg-stock-manifest",@"tmg-stock-slice",@"stock-tmg-manifest",@"stock-tmg-slice",@"size",@"select-stage1",@"select-stage2",@"select-stage3",@"index",@"version"];
    assert([modes containsObject:mode]);
    Home=[@(argv[3]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    Host=TFHFullInfo();Image=FakeImage(TFH_UUID);Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    TIOOTARecordTransportHookReady();assert(TIOOTAFullHost()&&TIOOTAFlashProtected());
    // Both packages, each read from its own unzipped ZIP against its own pins.
    assert(TIOOTAPackageCount()==2);NSDictionary *tmg=TIOOTAPackageAt(0),*stock=TIOOTAPackageAt(1);
    assert([tmg[@"name"] isEqual:@"TMG15"]&&[stock[@"name"] isEqual:@"STOCK-1.0.6.11"]&&[stock[@"kind"] isEqual:@"STOCK"]);
    NSDictionary *tmgFiles=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:@(argv[1])],tmg,nil),*stockFiles=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:@(argv[2])],stock,nil);
    assert(tmgFiles.count==17&&stockFiles.count==17);
    assert(!TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:@(argv[1])],stock,nil)&&!TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:@(argv[2])],tmg,nil));
    NSArray *tmgManifest=[NSJSONSerialization JSONObjectWithData:tmgFiles[@"OtaFileInfo.json"] options:0 error:nil],*stockManifest=[NSJSONSerialization JSONObjectWithData:stockFiles[@"OtaFileInfo.json"] options:0 error:nil];
    assert(tmgManifest.count==16&&stockManifest.count==16&&![tmgManifest isEqual:stockManifest]);
    NSData *start=Frame(4,@{@"Mode":@2},nil),*target=Frame(5,@{@"OtaVersion":TIO_FW_OTA_VERSION},nil);
    NSUInteger apDiff=DifferingSlice(tmgFiles[@"nuttx_ap.bin"],stockFiles[@"nuttx_ap.bin"]);
    NSUInteger apSize=MIN((NSUInteger)51200,MIN([tmgFiles[@"nuttx_ap.bin"] length],[stockFiles[@"nuttx_ap.bin"] length])-apDiff);
    if([mode isEqual:@"fresh"]){
        Check(TIOOTASelectedPackageIndex()==0&&[TIOOTASelectedPackage() isEqual:tmg]&&TIOOTASelectionGeneration()==0,"a new process selects the first package, TMG15");
        Check([Status()[@"selectedPackage"] isEqual:@"TMG15"]&&[Status()[@"selectedPackageIndex"] isEqual:@0]&&Stage()==0&&[Captured() isEqual:@""],"status names TMG15 as selected, nothing captured");
        Check([TIO_FW_NAME isEqual:@"TMG15"]&&TIO_FW_ZIP_BYTES==[tmg[@"zipBytes"] unsignedIntegerValue],"the selected-package macros read TMG15");
        printf("PASS flash packages fresh: TMG15 selected in a new process\n");[fm removeItemAtPath:Home error:nil];return 0;
    }
    if([mode isEqual:@"version"]){
#if !TIO_TEST_PACKAGE_TABLE
        abort();
#else
        Check([TIOOTAPackageAt(1)[@"acceptOsVersions"] isEqual:@[@"Strix OS 1.0.6.11"]]&&[TIOOTAPackageAt(0)[@"acceptOsVersions"] containsObject:@"Strix OS 1.0.5.12"],"test-only table: stock accepts only 1.0.6.11, TMG15 accepts 1.0.5.12");
        Place(argv[2]);NSError *e=nil;
        assert(TIOOTASelectPackage(1,&e));ReadVersion(@"Strix OS 1.0.5.12");
        Check(![Status()[@"recentTargetVersionRead"] boolValue],"1.0.5.12 read: not counted for the selected stock package");
        Check(!Authorize(&e)&&[e.localizedDescription isEqual:[NSString stringWithFormat:TIOText(@"ota.version.recheck"),@"1.0.6.11"]]&&Stage()==0,"stock selected, glasses on 1.0.5.12: authorization refused, the message names 1.0.6.11");
        // The same read counts for TMG15, which accepts it; the selection never switches by itself.
        assert(TIOOTASelectPackage(0,&e));Check([Status()[@"recentTargetVersionRead"] boolValue]&&TIOOTASelectedPackageIndex()==0,"the same read counts for TMG15");
        assert(TIOOTASelectPackage(1,&e));ReadVersion(@"Strix OS 1.0.6.11");e=nil;
        Check([Status()[@"recentTargetVersionRead"] boolValue]&&Authorize(&e)&&!e&&Stage()==1&&[Captured() isEqual:@"STOCK-1.0.6.11"],"stock selected, glasses on 1.0.6.11: authorized and stock captured");
        assert(TIOOTAFlashCancel());ReadVersion(@"Strix OS 1.0.4.12");
        Check(![Status()[@"recentTargetVersionRead"] boolValue]&&!Authorize(nil)&&Stage()==0,"a later read of a version no package accepts clears the previous read");
        printf("PASS flash packages version: a version the selected package does not accept refuses authorization\n");[fm removeItemAtPath:Home error:nil];return 0;
#endif
    }
    if([mode isEqual:@"index"]){
        // The capture-time check: the index the caller checked the version against must still be the selected one.
        // A gate of its own (the selection is the process's); each refusal has a control that the same folder and
        // index are captured once that package is selected, so only the index check can refuse.
        TIOOTAFlashGate *g=[TIOOTAFlashGate new];NSURL *dir=[NSURL fileURLWithPath:Directory() isDirectory:YES];NSError *e=nil;
        NSString *changed=TIOText(@"ota.package.changed");
        Place(argv[2]);
        Check(![g prepareDirectory:dir package:1 device:@"d" uptime:1 error:&e]&&[e.localizedDescription isEqual:changed]&&[[g status][@"stage"] isEqual:@0]&&[[g status][@"package"] isEqual:@""],"TMG15 selected, stock folder: a capture of package 1 (stock) is refused as changed, nothing captured");
        e=nil;Check(![g prepareDirectory:dir package:2 device:@"d" uptime:1 error:&e]&&[e.localizedDescription isEqual:changed]&&[[g status][@"stage"] isEqual:@0],"an unknown package index is refused");
        e=nil;assert(TIOOTASelectPackage(1,&e));
        e=nil;Check([g prepareDirectory:dir package:1 device:@"d" uptime:1 error:&e]&&!e&&[[g status][@"package"] isEqual:@"STOCK-1.0.6.11"],"control: stock selected, the same capture is allowed");
        assert([g cancel]);Place(argv[1]);
        e=nil;Check(![g prepareDirectory:dir package:0 device:@"d" uptime:1 error:&e]&&[e.localizedDescription isEqual:changed]&&[[g status][@"stage"] isEqual:@0]&&[[g status][@"package"] isEqual:@""],"stock selected, TMG15 folder: a capture of package 0 (TMG15) is refused as changed, nothing captured");
        e=nil;assert(TIOOTASelectPackage(0,&e));
        e=nil;Check([g prepareDirectory:dir package:0 device:@"d" uptime:1 error:&e]&&!e&&[[g status][@"package"] isEqual:@"TMG15"],"control: TMG15 selected, the same capture is allowed");
        assert([g cancel]);
        printf("PASS flash packages index: a capture for a package that is not selected is refused\n");[fm removeItemAtPath:Home error:nil];return 0;
    }
    ReadVersion(@"Strix OS 1.0.5.12");Check([Status()[@"recentTargetVersionRead"] boolValue],"accepted version read (1.0.5.12)");
    if([mode isEqual:@"stock-replay"]){
        assert(argc==8);NSUInteger wantSlices=strtoul(argv[6],NULL,10),wantBytes=strtoul(argv[7],NULL,10);assert(wantSlices&&wantBytes);
        NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[4])] options:0 error:nil];
        assert([fixture[@"statement"] isEqual:@"sequence seen on 2026-11-15 with RayNeo AI 1.0.21 (1)"]&&[fixture[@"sliceBytes"] isEqual:@51200]);
        NSError *e=nil;Check(TIOOTASelectPackage(1,&e)&&TIOOTASelectedPackageIndex()==1,"stock selected at stage 0");
        Place(argv[2]);
        NSData *manifest=stockFiles[@"OtaFileInfo.json"];assert(manifest.length==[stock[@"manifestBytes"] unsignedIntegerValue]);
        BOOL authorized=NO;NSUInteger sent=0,slices=0,bytes=0;
        for(NSDictionary *s in fixture[@"steps"]){
            NSUInteger type=[s[@"type"] unsignedIntegerValue];
            if([s[@"d"] isEqual:@"rx"]){Receive(Frame(type,s[@"json"],nil));continue;}
            if(type>=3&&!authorized){authorized=YES;e=nil;Check(Authorize(&e)&&!e&&Stage()==1&&[Captured() isEqual:@"STOCK-1.0.6.11"],"stock authorized and captured");}
            NSData *frame=nil;
            // The recorded TMG15 frames become the stock package's: its ZIP size, its manifest and its slices.
            if(type==3){assert([s[@"json"][@"OtaSize"] isEqual:tmg[@"zipBytes"]]);frame=ZipSize(stock);}
            else if(type==6)frame=RawFrame(6,manifest,nil);
            else if(type==7){
                NSData *file=stockFiles[s[@"name"]];assert(file);
                for(NSUInteger at=0;at<file.length;at+=51200){
                    NSData *part=[file subdataWithRange:NSMakeRange(at,MIN((NSUInteger)51200,file.length-at))];
                    if(!Send(Slice(s[@"name"],at,part))){fprintf(stderr,"FAIL stock replay: slice %s at %lu refused\n",[s[@"name"] UTF8String],(unsigned long)at);abort();}
                    slices++;bytes+=part.length;sent++;
                }
                continue;
            }else frame=Frame(type,s[@"json"],nil);
            if(!Send(frame)){fprintf(stderr,"FAIL stock replay: tx type %lu refused at stage %lu\n",(unsigned long)type,(unsigned long)Stage());abort();}
            sent++;
        }
        NSDictionary *status=Status();
        Check(Stage()==2&&[status[@"versionMatched"] boolValue]&&[status[@"manifestMatched"] boolValue],"stage 2, version and stock manifest matched");
        Check(slices==wantSlices&&bytes==wantBytes&&[status[@"validatedSlices"] unsignedIntegerValue]==wantSlices&&[status[@"validatedSliceBytes"] unsignedIntegerValue]==wantBytes,"slice totals equal the ones computed from the stock ZIP");
        printf("PASS flash packages stock-replay: %lu tx frames allowed, stage 2 reached, %lu slices, %lu bytes\n",(unsigned long)sent,(unsigned long)slices,(unsigned long)bytes);
        [fm removeItemAtPath:Home error:nil];return 0;
    }
    if([mode isEqual:@"size"]){
        // Stage 0: the selected package's size only.
        Check(Send(ZipSize(tmg))&&!Send(ZipSize(stock)),"stage 0, TMG15 selected: TMG15 size allowed, stock size refused");
        NSError *e=nil;assert(TIOOTASelectPackage(1,&e));
        Check(Send(ZipSize(stock))&&!Send(ZipSize(tmg)),"stage 0, stock selected: stock size allowed, TMG15 size refused");
        Place(argv[2]);e=nil;assert(Authorize(&e)&&Stage()==1);
        Check(Send(ZipSize(stock))&&!Send(ZipSize(tmg))&&Stage()==1,"stage 1, stock captured: TMG15 size refused");
        Check(Send(start)&&Stage()==2,"stage 2 started");
        Check(!Send(ZipSize(tmg))&&Stage()==3,"stage 2: TMG15 size refused, the transfer ends");
        printf("PASS flash packages size: type 3 with the other package's size refused at stages 0, 1 and 2\n");[fm removeItemAtPath:Home error:nil];return 0;
    }
    BOOL stockFirst=[mode hasPrefix:@"stock-"];NSError *e=nil;
    if(stockFirst){assert(TIOOTASelectPackage(1,&e));Place(argv[2]);}else Place(argv[1]);
    NSDictionary *mine=stockFirst?stock:tmg,*myFiles=stockFirst?stockFiles:tmgFiles,*otherFiles=stockFirst?tmgFiles:stockFiles;
    NSArray *myManifest=stockFirst?stockManifest:tmgManifest,*otherManifest=stockFirst?tmgManifest:stockManifest;
    e=nil;Check(Authorize(&e)&&!e&&Stage()==1&&[Captured() isEqual:mine[@"name"]],"authorized, the selected package captured");
    if([mode isEqual:@"select-stage1"]){
        NSUInteger generation=TIOOTASelectionGeneration();
        Check(TIOOTASelectPackage(1,&e)&&TIOOTASelectedPackageIndex()==1&&TIOOTASelectionGeneration()==generation+1,"a change at stage 1 is accepted");
        Check(Stage()==0&&![Status()[@"authorized"] boolValue]&&[Captured() isEqual:@""],"the stage-1 authorization is cancelled and the capture dropped");
        Check(!Send(start)&&Stage()==0,"type 4 refused after the change");
        // The folder still holds TMG15: authorization for the stock package fails with the member mismatch message.
        // The members are read in name order, so the manifest (OtaFileInfo.json) is the first that differs.
        NSString *mismatch=[NSString stringWithFormat:TIOText(@"ota.identity.payloadMismatch"),@"OtaFileInfo.json",TIOOTAPackageDisplayName(stock)];
        e=nil;Check(!Authorize(&e)&&Stage()==0&&[e.localizedDescription isEqual:mismatch],"the folder holds TMG15: stock authorization refused with the mismatch message naming Stock 1.0.6.11");
        Place(argv[2]);e=nil;Check(Authorize(&e)&&!e&&Stage()==1&&[Captured() isEqual:@"STOCK-1.0.6.11"],"with the stock folder, stock is authorized and captured");
        printf("PASS flash packages select-stage1: the change cancelled the authorization\n");[fm removeItemAtPath:Home error:nil];return 0;
    }
    Check(Send(start)&&Stage()==2,"stage 2 started");
    if([mode isEqual:@"select-stage2"]||[mode isEqual:@"select-stage3"]){
        if([mode isEqual:@"select-stage3"])Check(!Send(start)&&Stage()==3,"a second type 4: stage 3");
        NSUInteger stage=Stage(),generation=TIOOTASelectionGeneration();NSDictionary *before=Status();
        e=nil;Check(!TIOOTASelectPackage(1,&e)&&[e.localizedDescription isEqual:TIOText(@"ota.package.locked")],"a change after the start is refused");
        Check(TIOOTASelectedPackageIndex()==0&&TIOOTASelectionGeneration()==generation&&Stage()==stage&&[Captured() isEqual:@"TMG15"],"selection, stage and capture unchanged");
        Check([Status()[@"validatedSlices"] isEqual:before[@"validatedSlices"]]&&[Status()[@"versionMatched"] isEqual:before[@"versionMatched"]],"the session counters unchanged");
        if(stage==2){
            Check(Send(target)&&Send(RawFrame(6,myFiles[@"OtaFileInfo.json"],nil))&&Send(Slice(@"nuttx_ap.bin",apDiff,[myFiles[@"nuttx_ap.bin"] subdataWithRange:NSMakeRange(apDiff,apSize)]))&&Stage()==2,"the TMG15 session goes on with the TMG15 capture");
        }else Check(!Send(target)&&Stage()==3,"stage 3 stays closed");
        printf("PASS flash packages %s: refused, capture unchanged\n",mode.UTF8String);[fm removeItemAtPath:Home error:nil];return 0;
    }
    Check(Send(target)&&Stage()==2,"type 5 with the target version");
    if([mode hasSuffix:@"-manifest"]){
        Check(!Send(Frame(6,otherManifest,nil))&&Stage()==3,"the other package's manifest is refused, the transfer ends");
    }else{
        assert([myManifest count]);Check(Send(RawFrame(6,myFiles[@"OtaFileInfo.json"],nil)),"the captured manifest is allowed");
        NSData *other=[otherFiles[@"nuttx_ap.bin"] subdataWithRange:NSMakeRange(apDiff,apSize)];
        Check(!Send(Slice(@"nuttx_ap.bin",apDiff,other))&&Stage()==3,"the other package's nuttx_ap.bin slice is refused, the transfer ends");
    }
    printf("PASS flash packages %s: refused\n",mode.UTF8String);
    [fm removeItemAtPath:Home error:nil];
}return 0;}
