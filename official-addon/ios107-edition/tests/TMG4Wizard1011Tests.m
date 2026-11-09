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
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==4);NSString *version=@(argv[3]);assert(([@[@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5"] containsObject:version]));
    Home=[@(argv[2]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSString *directory=[Home stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.5.5"];NSFileManager *fm=NSFileManager.defaultManager;
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
    // Disarm before the transfer revokes the grant and closes the gate again.
    assert(TIOOTAFlashAuthorize(nil)&&Stage()==1);assert(TIOOTAFlashDisarm()&&Stage()==0&&!TIOOTAFlashArmed());
    assert(!Send(4,@{@"Mode":@2},nil));assert(!TIOOTAFlashAuthorize(nil));
    // Re-arm: one confirmation, one authorization; the forced page's Mode 4 is refused, Mode 2 starts.
    assert(TIOOTAFlashArm(nil));Observe(version);
    unsigned confirmations=0;assert([Snapshot()[@"canAuthorize"] boolValue]);confirmations++;e=nil;assert(TIOOTAFlashAuthorize(&e)&&!e&&confirmations==1&&Stage()==1);
    assert(!TIOOTAFlashAuthorize(nil));
    assert(!Send(4,@{@"Mode":@4},nil));assert(!Send(4,@{@"Mode":@1},nil));assert(!Send(4,@{@"Mode":@3},nil));assert(Stage()==1);
    assert(Send(4,@{@"Mode":@2},nil)&&Stage()==2);
    // Mid-transfer: disarm is refused and the record stays; the transfer continues as on 1.0.7.
    assert(!TIOOTAFlashDisarm()&&TIOOTAFlashArmed()&&Stage()==2);
    NSDictionary *files=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:directory],nil);assert(files.count==16);NSArray *manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:nil];
    assert(Send(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil));assert(Send(6,manifest,nil));unsigned slices=0;NSUInteger total=0;
    for(NSDictionary *row in manifest){NSData *file=files[row[@"Name"]];for(NSUInteger at=0;at<file.length;at+=51200){NSUInteger n=MIN((NSUInteger)51200,file.length-at);assert(Send(7,@{@"Name":row[@"Name"],@"Start":@(at),@"Size":@(n)},[file subdataWithRange:NSMakeRange(at,n)]));slices++;total+=n;}}
    assert(slices==TIO_FW_PAYLOAD_SLICES&&total==TIO_FW_PAYLOAD_BYTES);assert([TIOOTAFlashStatus()[@"validatedSlices"] unsignedIntegerValue]==slices);
    assert(!TIOOTAFlashDisarm()&&TIOOTAFlashArmed());
    [fm removeItemAtPath:Home error:nil];[TMG4ArmStore() removeAllObjects];
    printf("PASS full 1.0.11 wizard/gate from %s: disarmed cannot authorize; armed takes the 1.0.7 gate (Auto Update toggle, one authorization, Mode 4 refused, Mode 2 starts, all slices); disarm revokes at stage 1 and is refused at stage 2; deviceIO=false\n",version.UTF8String);
}return 0;}
