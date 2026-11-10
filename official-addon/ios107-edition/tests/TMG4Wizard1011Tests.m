// Full 1.0.11 host (ios1011, C15), armed: the unchanged 1.0.7 wizard and gate, run like
// tests/TMG4WizardTests.m on the real candidate files, plus the arm step around it.
// Disarmed, the wizard cannot authorize; armed, authorization opens the same Mode 2
// only gate (the forced page's Mode 4 is refused), disarm before the transfer revokes
// the grant, and disarm is refused once the transfer has started. No device I/O.
#import "TMG4WizardHost.h"
#import "OTAWizardModel.h"
#import "OTAHost.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#import "FirmwarePins.h"
#import "ReleasePolicy.h"
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
const struct mach_header *TMG4MainImage(void){return Image;}
BOOL TDPPhonePauseForOTA(void){return YES;}
NSDictionary *TIOExperimentalOTAFeedStatus(void){return @{@"bootstrapEligible":@YES,@"running":@YES,@"healthPassed":@YES};}
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(unsigned type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static void Observe(NSString *version){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":version,@"OtaValidationConfirmed":@YES},nil)}});}
static BOOL Send(unsigned type,id json,NSData *binary){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":@"fixture-peer",@"payload":Frame(type,json,binary)}});}
static NSDictionary *Snapshot(void){return TIOOTAWizardSnapshot(@{@"flash":TIOOTAFlashStatus(),@"feed":TIOExperimentalOTAFeedStatus(),@"guard":TIOOTAGuardStatus(),@"prefs":Prefs?:@{},@"packageOK":@YES,@"directoryOK":@YES});}
static int Stage(void){return [TIOOTAFlashStatus()[@"stage"] intValue];}
static NSString *const ArmKey=@"otaFlashArmRecord.ios1011";
// Folder collision: the official folder holds other bytes of the same name (RayNeo's own download of the
// target version, here the stock ZIP of the release's base, argv[2]/stock). Authorization is refused with the
// folder message, nothing is modified, and putting the release back makes it pass again.
static void Collide(NSString *directory,NSString *stock,BOOL (^authorize)(NSError **)){
    NSFileManager *fm=NSFileManager.defaultManager;NSString *aside=[directory stringByAppendingString:@".release"];
    assert([fm moveItemAtPath:directory toPath:aside error:nil]&&[fm copyItemAtPath:stock toPath:directory error:nil]);
    NSError *e=nil;assert(!authorize(&e)&&[TIOOTAFlashStatus()[@"stage"] intValue]==0);
    NSString *want=[NSString stringWithFormat:TIOText(@"ota.directory.foreign"),[@"ota/" stringByAppendingString:TRPFolder],TIO_FW_NAME,@""];
    assert([e.localizedDescription hasPrefix:[want substringToIndex:want.length-3]]);
    NSError *direct=nil;assert(!TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],&direct)&&[direct.localizedDescription isEqual:e.localizedDescription]);
    NSArray *before=[fm contentsOfDirectoryAtPath:directory error:nil];assert(before.count==16&&[[fm contentsOfDirectoryAtPath:stock error:nil] isEqual:before]);
    for(NSString *name in before)assert([[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]] isEqual:[NSData dataWithContentsOfFile:[stock stringByAppendingPathComponent:name]]]);
    assert([fm removeItemAtPath:directory error:nil]&&[fm moveItemAtPath:aside toPath:directory error:nil]);
    assert(TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],nil));
}
// Disarm from a background queue, as the wizard's runAction does, while the main run loop turns.
static BOOL DisarmOffMain(void){
    __block BOOL ok=NO,done=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{BOOL r=TIOOTAFlashDisarm();dispatch_async(dispatch_get_main_queue(),^{ok=r;done=YES;});});
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:10];
    while(!done&&limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    assert(done);return ok;
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==4);NSString *version=@(argv[3]);assert([TRPAccepted() containsObject:version]&&[TIO_FW_ACCEPTED_OS_VERSIONS isEqual:TRPAccepted()]&&[TIO_FW_OTA_FOLDER isEqual:TRPFolder]);
    Home=[@(argv[2]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSString *directory=[Home stringByAppendingPathComponent:[@"Library/Application Support/ota/" stringByAppendingString:TRPFolder]];NSFileManager *fm=NSFileManager.defaultManager;
    assert([fm createDirectoryAtPath:[directory stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]);assert([fm copyItemAtPath:@(argv[1]) toPath:directory error:nil]);
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",@"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    Image=FakeImage(@"22724C97-2EF9-388D-8E6A-6E051855A555");[TMG4ArmStore() removeAllObjects];
    Prefs=@{@"fixture_ota_firmware_auto_update":@NO};TIOOTARecordTransportHookReady();assert(TIOOTAFlashBuild()&&TIOOTAFlashProtected());
    // Disarmed: every other check passes, yet the wizard shows the arm step and cannot authorize.
    Observe(version);assert([TIOOTAFlashStatus()[@"recentTargetVersionRead"] boolValue]);
    NSDictionary *s=Snapshot();assert([s[@"armRequired"] boolValue]&&![s[@"armed"] boolValue]&&[s[@"arm"] integerValue]==TIOOTACheckAction&&![s[@"canAuthorize"] boolValue]);
    assert([TIOOTAWizardHubStatusKey(s) isEqual:@"ota.hub.disarmed"]);
    NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e)&&[e.localizedDescription isEqual:TIOText(@"本机 TMG 刷写尚未启用；先在向导中启用，未授权。")]&&Stage()==0);
    for(NSNumber *mode in @[@1,@2,@3,@4])assert(!Send(4,@{@"Mode":mode},nil));
    // Arm, then the 1.0.7 checks decide: the Auto Update toggle is still required.
    assert(TIOOTAFlashArm(nil));s=Snapshot();assert([s[@"armed"] boolValue]&&[s[@"arm"] integerValue]==TIOOTACheckOK&&[s[@"canAuthorize"] boolValue]);
    Prefs=@{@"fixture_ota_firmware_auto_update":@YES};assert(![Snapshot()[@"canAuthorize"] boolValue]&&!TIOOTAFlashAuthorize(nil)&&Stage()==0);
    Prefs=@{};assert(!TIOOTAFlashAuthorize(nil)&&Stage()==0);Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    // Armed, every other check passes: a glasses version outside this release's set, or other files in the folder, still refuse.
    for(NSString *other in TRPKnown())if(![TRPAccepted() containsObject:other]){Observe(other);assert(![TIOOTAFlashStatus()[@"recentTargetVersionRead"] boolValue]&&!TIOOTAFlashAuthorize(nil)&&Stage()==0);}
    Observe(version);Collide(directory,[@(argv[2]) stringByAppendingPathComponent:@"stock"],^BOOL(NSError **e){return TIOOTAFlashAuthorize(e);});
    // Disarm before the transfer revokes the grant and closes the gate again.
    assert(TIOOTAFlashAuthorize(nil)&&Stage()==1);assert(TIOOTAFlashDisarm()&&Stage()==0&&!TIOOTAFlashArmed());
    assert(!Send(4,@{@"Mode":@2},nil));assert(!TIOOTAFlashAuthorize(nil));
    // Disarm called off the main thread runs on it (the guard's thread): it revokes and clears the record there.
    assert(TIOOTAFlashArm(nil)&&TIOOTAFlashAuthorize(nil)&&Stage()==1);*TMG4ArmLastWriteOnMain()=NO;
    assert(DisarmOffMain()&&Stage()==0&&!TIOOTAFlashArmed()&&*TMG4ArmLastWriteOnMain());assert(!Send(4,@{@"Mode":@2},nil));
    // Re-arm: one confirmation, one authorization; the forced page's Mode 4 is refused, Mode 2 starts.
    assert(TIOOTAFlashArm(nil));Observe(version);
    unsigned confirmations=0;assert([Snapshot()[@"canAuthorize"] boolValue]);confirmations++;e=nil;assert(TIOOTAFlashAuthorize(&e)&&!e&&confirmations==1&&Stage()==1);
    assert(!TIOOTAFlashAuthorize(nil));
    assert(!Send(4,@{@"Mode":@4},nil));assert(!Send(4,@{@"Mode":@1},nil));assert(!Send(4,@{@"Mode":@3},nil));assert(Stage()==1);
    assert(Send(4,@{@"Mode":@2},nil)&&Stage()==2);
    // Mid-transfer: disarm is refused and the record stays; the transfer continues as on 1.0.7.
    assert(!TIOOTAFlashDisarm()&&TIOOTAFlashArmed()&&Stage()==2);
    NSDictionary *files=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:directory],nil);assert(files.count==16);NSArray *manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:nil];
    // A started transfer no longer reads the arm record: with the record gone (a read failure, a
    // preferences glitch or a disarm that raced the guard) or replaced by junk, the 1.0.7 gate decides.
    NSDictionary *record=TMG4ArmStore()[ArmKey];assert(record);[TMG4ArmStore() removeObjectForKey:ArmKey];assert(!TIOOTAFlashArmed());
    assert(Send(5,@{@"OtaVersion":TRPTarget},nil));TMG4ArmStore()[ArmKey]=@"junk";assert(Send(6,manifest,nil));[TMG4ArmStore() removeObjectForKey:ArmKey];unsigned slices=0;NSUInteger total=0;
    for(NSDictionary *row in manifest){NSData *file=files[row[@"Name"]];for(NSUInteger at=0;at<file.length;at+=51200){NSUInteger n=MIN((NSUInteger)51200,file.length-at);assert(Send(7,@{@"Name":row[@"Name"],@"Start":@(at),@"Size":@(n)},[file subdataWithRange:NSMakeRange(at,n)]));slices++;total+=n;}}
    assert(slices==TIO_FW_PAYLOAD_SLICES&&total==TIO_FW_PAYLOAD_BYTES);assert([TIOOTAFlashStatus()[@"validatedSlices"] unsignedIntegerValue]==slices);
    assert(Stage()==2);TMG4ArmStore()[ArmKey]=record;
    assert(!TIOOTAFlashDisarm()&&TIOOTAFlashArmed());assert(!DisarmOffMain()&&TIOOTAFlashArmed());
    // A slice that does not match fails the transfer (stage 3). The gate then refuses to cancel,
    // so disarm is refused too and the record stays; nothing passes either way.
    assert(!Send(7,@{@"Name":manifest[0][@"Name"],@"Start":@0,@"Size":@1},({uint8_t bad=((const uint8_t *)[files[manifest[0][@"Name"]] bytes])[0]^0xff;[NSData dataWithBytes:&bad length:1];}))&&Stage()==3);
    assert(!TIOOTAFlashDisarm()&&TIOOTAFlashArmed()&&Stage()==3);
    for(NSNumber *mode in @[@1,@2,@4])assert(!Send(4,@{@"Mode":mode},nil));
    [fm removeItemAtPath:Home error:nil];[TMG4ArmStore() removeAllObjects];
    printf("PASS full 1.0.11 wizard/gate from %s: disarmed cannot authorize; armed takes the 1.0.7 gate (Auto Update toggle, one authorization, Mode 4 refused, Mode 2 starts, all slices); disarm revokes at stage 1 (also off main, run on main), is refused at stage 2 and 3 with the record kept; a started transfer ignores the arm record; deviceIO=false\n",version.UTF8String);
}return 0;}
