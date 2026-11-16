// The real OTA wizard and gate on the full 1.0.21 host (tests/FullHostFixture.h), on the real
// candidate files: the version read (kept until a disconnect call or a later reply replaces it), the
// accepted versions, the folder check, Auto Update, the idle and health checks, one authorization,
// the peer, every slice, and the stages that cannot be cancelled. No device I/O.
#import "TMG4WizardHost.h"
#import "FullHostFixture.h"
#import "OTAWizardModel.h"
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
static BOOL Idle=YES,Healthy=YES;
static NSDictionary *Prefs,*Host;
static const struct mach_header *Image;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return Now;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
BOOL TDPPhonePauseForOTA(void){return Idle;}
const struct mach_header *TMG4MainImage(void){return Image;}
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
NSDictionary *TIOExperimentalOTAFeedStatus(void){return @{@"bootstrapEligible":@YES,@"running":@YES,@"healthPassed":@(Healthy)};}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(unsigned type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static void Observe(NSString *version,BOOL confirmed,NSString *peer){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":peer,@"payload":Frame(1,@{@"OsVersion":version,@"OtaValidationConfirmed":@(confirmed)},nil)}});}
static BOOL Send(unsigned type,id json,NSData *binary,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":Frame(type,json,binary)}});}
static NSDictionary *Snapshot(BOOL directory){return TIOOTAWizardSnapshot(@{@"flash":TIOOTAFlashStatus(),@"feed":TIOExperimentalOTAFeedStatus(),@"guard":TIOOTAGuardStatus(),@"prefs":Prefs?:@{},@"packageOK":@YES,@"directoryOK":@(directory)});}
// Folder collision: the official folder holds other bytes of the same names (RayNeo's own download of the
// target version, here the stock ZIP of the release's base, argv[2]/stock). Authorization is refused with the
// member message, nothing is modified, and putting the release back makes it pass again.
static void Collide(NSString *directory,NSString *stock,BOOL (^authorize)(NSError **)){
    NSFileManager *fm=NSFileManager.defaultManager;NSString *aside=[directory stringByAppendingString:@".release"];
    assert([fm moveItemAtPath:directory toPath:aside error:nil]&&[fm copyItemAtPath:stock toPath:directory error:nil]);
    NSError *e=nil;assert(!authorize(&e)&&[TIOOTAFlashStatus()[@"stage"] intValue]==0);
    NSString *tail=[NSString stringWithFormat:TIOText(@"ota.identity.payloadMismatch"),@"",TIO_FW_NAME];
    assert([e.localizedDescription hasSuffix:tail]);
    NSError *direct=nil;assert(!TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],&direct)&&[direct.localizedDescription isEqual:e.localizedDescription]);
    NSArray *before=[fm contentsOfDirectoryAtPath:directory error:nil];assert(before.count==TIO_FW_MEMBER_PINS.count&&[[fm contentsOfDirectoryAtPath:stock error:nil] isEqual:before]);
    for(NSString *name in before)assert([[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]] isEqual:[NSData dataWithContentsOfFile:[stock stringByAppendingPathComponent:name]]]);
    // A partial download (a member missing, a member cut short, an empty folder) or one with an extra file:
    // refused just the same, with the member message, and the authorization and the folder check agree.
    for(NSString *damage in @[@"missing",@"truncated",@"empty",@"extra"]){
        assert([fm removeItemAtPath:directory error:nil]&&[fm copyItemAtPath:stock toPath:directory error:nil]);
        NSString *victim=[directory stringByAppendingPathComponent:@"smf.json"];
        if([damage isEqual:@"missing"])assert([fm removeItemAtPath:victim error:nil]);
        if([damage isEqual:@"truncated"]){NSData *d=[NSData dataWithContentsOfFile:victim];assert([[d subdataWithRange:NSMakeRange(0,d.length/2)] writeToFile:victim atomically:NO]);}
        if([damage isEqual:@"empty"])for(NSString *n in [fm contentsOfDirectoryAtPath:directory error:nil])assert([fm removeItemAtPath:[directory stringByAppendingPathComponent:n] error:nil]);
        if([damage isEqual:@"extra"])assert([[NSData dataWithBytes:"x" length:1] writeToFile:[directory stringByAppendingPathComponent:@"fota_1.bin"] atomically:NO]);
        e=nil;assert(!authorize(&e)&&[TIOOTAFlashStatus()[@"stage"] intValue]==0);
        assert(e&&[e.localizedDescription hasSuffix:tail]);
        direct=nil;assert(!TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],&direct)&&[direct.localizedDescription isEqual:e.localizedDescription]);
    }
    // A missing folder: refused, with the folder message.
    assert([fm removeItemAtPath:directory error:nil]);direct=nil;assert(!TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],&direct)&&direct&&![direct.localizedDescription hasSuffix:tail]);
    assert([fm moveItemAtPath:aside toPath:directory error:nil]);
    assert(TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],nil));
    // The release with an extra file beside it passes: only the pinned members are read and sent.
    NSString *extra=[directory stringByAppendingPathComponent:@"fota_1.bin"];
    assert([[NSData dataWithBytes:"x" length:1] writeToFile:extra atomically:NO]&&TIOCheckOfficialOTADirectory([NSURL fileURLWithPath:directory],nil));
    assert([fm removeItemAtPath:extra error:nil]);
}
static void Refused(void){NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e)&&e&&[TIOOTAFlashStatus()[@"stage"]intValue]==0);}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==4);NSString *version=@(argv[3]);assert([TRPAccepted() containsObject:version]&&[TIO_FW_ACCEPTED_OS_VERSIONS isEqual:TRPAccepted()]&&[TIO_FW_OTA_FOLDER isEqual:TRPFolder]);
 Home=[@(argv[2])stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSString *directory=[Home stringByAppendingPathComponent:[@"Library/Application Support/ota/" stringByAppendingString:TRPFolder]];NSFileManager *fm=NSFileManager.defaultManager;
 assert([fm createDirectoryAtPath:[directory stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]);assert([fm copyItemAtPath:@(argv[1]) toPath:directory error:nil]);
 Host=TFHFullInfo();Image=FakeImage(TFH_UUID);
 Prefs=@{@"fixture_ota_firmware_auto_update":@NO};TIOOTARecordTransportHookReady();assert(TIOOTAFlashBuild()&&TIOOTAFlashProtected());assert(TIOOTAScopedSenderCount()==0);
 assert(TIOOTAFullHost()&&[TIOOTAFlashStatus()[@"fullHost"] boolValue]&&[Snapshot(NO)[@"downloadRequired"] boolValue]);
 // No TTL/TLG/TDG or nav reply/capability has been provided. The real business-9
 // observer and authorization policy must still permit the old installed OS.
 assert([Snapshot(NO)[@"canDownload"]boolValue]);assert(![Snapshot(NO)[@"canAuthorize"]boolValue]);Refused();
 // G4: the bridge narrows businessId with UInt8(truncating:). Ids that wrap to 9 (or are not a plain
 // byte) are refused on send and ignored by the receive monitor; a non-9 byte still passes.
 NSArray *wide=@[@265,@521,@0x109,@65545,@0x10009,@256,@0x100000009ULL,@(-247),@(-1),@9.0,@265.0,@9.5,@YES,@NO,@(UINT32_MAX)];
 for(id business in wide){
  for(NSData *payload in @[Frame(1,nil,nil),Frame(2,nil,nil),Frame(4,@{@"Mode":@1},nil),Frame(4,@{@"Mode":@2},nil),Frame(4,@{@"Mode":@3},nil),Frame(4,@{@"Mode":@4},nil)])
   assert(TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":payload}}));
  TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":business,@"deviceId":@"fixture-peer",@"payload":Frame(1,@{@"OsVersion":version,@"OtaValidationConfirmed":@YES},nil)}});
  assert(![TIOOTAFlashStatus()[@"recentTargetVersionRead"]boolValue]);
 }
 assert(!TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@255,@"deviceId":@"fixture-peer",@"payload":Frame(4,@{@"Mode":@4},nil)}}));
 assert(Send(1,nil,nil,@"fixture-peer"));
 Observe(version,YES,@"fixture-peer");assert([TIOOTAFlashStatus()[@"recentTargetVersionRead"]boolValue]);assert([Snapshot(YES)[@"canAuthorize"]boolValue]);
 // The read has no time limit: an hour later it still counts. A disconnect call clears it, and so does any later
 // version reply that is not accepted.
 Now+=3600;assert([Snapshot(YES)[@"canAuthorize"]boolValue]);
 for(NSString *method in @[@"rayneonet_disconnect",@"rayneonet_unbindDevice",@"rayneonet_unpair"]){
  TIOOTAFlashBlockCall(@{@"method":method,@"arguments":@{}});assert(![TIOOTAFlashStatus()[@"recentTargetVersionRead"]boolValue]&&![Snapshot(YES)[@"canAuthorize"]boolValue]);Refused();
  Observe(version,YES,@"fixture-peer");assert([Snapshot(YES)[@"canAuthorize"]boolValue]);
 }
 Observe(version,NO,@"fixture-peer");Refused();Observe(@"Strix OS 1.0.3.15",YES,@"fixture-peer");Refused();
 for(NSString *other in TRPKnown())if(![TRPAccepted() containsObject:other]){Observe(other,YES,@"fixture-peer");assert(![TIOOTAFlashStatus()[@"recentTargetVersionRead"]boolValue]);Refused();}
 Observe(version,YES,@"fixture-peer");
 Collide(directory,[@(argv[2]) stringByAppendingPathComponent:@"stock"],^BOOL(NSError **e){return TIOOTAFlashAuthorize(e);});
 Prefs=@{};Refused();Prefs=@{@"fixture_ota_firmware_auto_update":@YES};Refused();Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
 Idle=NO;Refused();Idle=YES;Healthy=NO;Refused();Healthy=YES;
 // The host is checked once, here: another build, a missing marker or another image refuses authorization.
 NSDictionary *validHost=Host;Host=@{};Refused();
 for(NSArray *kv in @[@[@"CFBundleVersion",TFH_NEXT_BUILD],@[@"TIOHostProfile",TFH_NEAR_PROFILE],@[@"CFBundleShortVersionString",TFH_NEAR_VERSION]]){
  NSMutableDictionary *m=[validHost mutableCopy];m[kv[0]]=kv[1];Host=m;NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e));
  assert([e.localizedDescription isEqual:TIOText(@"ota.authorize.host")]||[kv[0] isEqual:@"TIOHostProfile"]);assert([TIOOTAFlashStatus()[@"stage"]intValue]==0);
 }
 Host=validHost;const struct mach_header *pinned=Image;Image=FakeImage(@"00000000-0000-0000-0000-000000000001");
 {NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e)&&[e.localizedDescription isEqual:TIOText(@"ota.authorize.host")]);}Image=pinned;
 NSString *ap=[directory stringByAppendingPathComponent:@"nuttx_ap.bin"];NSMutableData *bytes=[[NSData dataWithContentsOfFile:ap]mutableCopy];NSData *original=[bytes copy];((uint8_t *)bytes.mutableBytes)[50]^=1;assert([bytes writeToFile:ap atomically:YES]);Refused();assert([original writeToFile:ap atomically:YES]);
 // One explicit confirmation boundary invokes the existing authorizer once.
 // Stage1 then makes the wizard's authorize action unavailable; no new UI or
 // policy confirmation path is introduced by the TMG2 compatibility removal.
 unsigned confirmations=0;NSError *error=nil;assert([Snapshot(YES)[@"canAuthorize"]boolValue]);confirmations++;assert(TIOOTAFlashAuthorize(&error)&&!error);assert(confirmations==1);assert([Snapshot(YES)[@"phase"]intValue]==TIOOTAPhaseAuthorized&&! [Snapshot(YES)[@"canAuthorize"]boolValue]);assert(!TIOOTAFlashAuthorize(nil));
 // Wrong peer cannot start an otherwise authorized transfer.
 assert(!Send(4,@{@"Mode":@2},nil,@"other-peer"));assert(TIOOTAFlashCancel());
 Observe(version,YES,@"other-peer");assert(TIOOTAFlashAuthorize(nil));assert(!Send(4,@{@"Mode":@2},nil,@"fixture-peer"));assert(TIOOTAFlashCancel());Observe(version,YES,@"fixture-peer");assert(TIOOTAFlashAuthorize(nil));
 assert(Send(4,@{@"Mode":@2},nil,@"fixture-peer"));assert([Snapshot(YES)[@"phase"]intValue]==TIOOTAPhaseInstalling);assert(!TIOOTAFlashCancel());
 NSDictionary *files=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:directory],nil);assert(files.count==TIO_FW_MEMBER_PINS.count);NSArray *manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:nil];
 assert(Send(5,@{@"OtaVersion":TRPTarget},nil,@"fixture-peer"));assert(Send(6,manifest,nil,@"fixture-peer"));unsigned slices=0;NSUInteger total=0;
 for(NSDictionary *row in manifest){NSData *file=files[row[@"Name"]];for(NSUInteger at=0;at<file.length;at+=51200){NSUInteger n=MIN((NSUInteger)51200,file.length-at);assert(Send(7,@{@"Name":row[@"Name"],@"Start":@(at),@"Size":@(n)},[file subdataWithRange:NSMakeRange(at,n)],@"fixture-peer"));slices++;total+=n;}}
 assert(slices==TIO_FW_PAYLOAD_SLICES&&total==TIO_FW_PAYLOAD_BYTES);assert([TIOOTAFlashStatus()[@"validatedSlices"]unsignedIntegerValue]==slices);
 // Stage 2 cannot be cancelled, not even by a disconnect call; an unexpected frame moves it to stage 3, which
 // lasts until the app restarts: no cancel, no new authorization, every transfer frame refused, reads still pass.
 assert(!TIOOTAFlashCancel());TIOOTAFlashBlockCall(@{@"method":@"rayneonet_disconnect",@"arguments":@{}});assert([TIOOTAFlashStatus()[@"stage"]intValue]==2);
 Observe(version,YES,@"fixture-peer");
 assert(!Send(4,@{@"Mode":@2},nil,@"fixture-peer"));assert([TIOOTAFlashStatus()[@"stage"]intValue]==3);
 assert(!TIOOTAFlashCancel()&&!TIOOTAFlashAuthorize(nil)&&[TIOOTAFlashStatus()[@"stage"]intValue]==3);
 assert(!Send(6,manifest,nil,@"fixture-peer")&&Send(1,nil,nil,@"fixture-peer")&&Send(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil,@"fixture-peer"));
 [fm removeItemAtPath:Home error:nil];printf("PASS real OTA wizard/gate on the full " TFH_NAME " host from %s: validated business9 read, exact candidate and all slices, one authorization transition, no feature caps, host/hash/peer/idle refusals, stages 2 and 3 not cancellable; deviceIO=false\n",version.UTF8String);
}return 0;}
