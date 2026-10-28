#import "TMG4WizardHost.h"
#import "OTAWizardModel.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#import "FirmwarePins.h"
#include <assert.h>
static NSString *Home;
static NSTimeInterval Now=100;
static BOOL Idle=YES,Healthy=YES;
static NSDictionary *Prefs,*Host;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return Now;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
BOOL TDPPhonePauseForOTA(void){return Idle;}
NSDictionary *TIOExperimentalOTAFeedStatus(void){return @{@"bootstrapEligible":@YES,@"running":@YES,@"healthPassed":@(Healthy)};}
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Frame(unsigned type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];Var(d,26);Var(d,j.length);[d appendData:j];}if(binary){Var(d,34);Var(d,binary.length);[d appendData:binary];}return d;}
static void Observe(NSString *version,BOOL confirmed,NSString *peer){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":peer,@"payload":Frame(1,@{@"OsVersion":version,@"OtaValidationConfirmed":@(confirmed)},nil)}});}
static BOOL Send(unsigned type,id json,NSData *binary,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":Frame(type,json,binary)}});}
static NSDictionary *Snapshot(BOOL directory){return TIOOTAWizardSnapshot(@{@"flash":TIOOTAFlashStatus(),@"feed":TIOExperimentalOTAFeedStatus(),@"guard":TIOOTAGuardStatus(),@"prefs":Prefs?:@{},@"packageOK":@YES,@"directoryOK":@(directory)});}
static void Refused(void){NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e)&&e&&[TIOOTAFlashStatus()[@"stage"]intValue]==0);}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==4);NSString *version=@(argv[3]);assert(([@[@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5"]containsObject:version]));
 Home=[@(argv[2])stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSString *directory=[Home stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.5.5"];NSFileManager *fm=NSFileManager.defaultManager;
 assert([fm createDirectoryAtPath:[directory stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]);assert([fm copyItemAtPath:@(argv[1]) toPath:directory error:nil]);
 Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
 Prefs=@{@"fixture_ota_firmware_auto_update":@NO};TIOOTARecordTransportHookReady();assert(TIOOTAFlashBuild()&&TIOOTAFlashProtected());assert(TIOOTAScopedSenderCount()==0);
 // No TTL/TLG/TDG or nav reply/capability has been provided. The real business-9
 // observer and authorization policy must still permit the old installed OS.
 assert([Snapshot(NO)[@"canDownload"]boolValue]);assert(![Snapshot(NO)[@"canAuthorize"]boolValue]);Refused();
 Observe(version,YES,@"fixture-peer");assert([TIOOTAFlashStatus()[@"recentTargetVersionRead"]boolValue]);assert([Snapshot(YES)[@"canAuthorize"]boolValue]);
 Now+=120;assert([Snapshot(YES)[@"canAuthorize"]boolValue]);Now+=.001;assert(![Snapshot(YES)[@"canAuthorize"]boolValue]);Refused();Observe(version,YES,@"fixture-peer");
 Observe(version,NO,@"fixture-peer");Refused();Observe(@"Strix OS 1.0.3.15",YES,@"fixture-peer");Refused();Observe(version,YES,@"fixture-peer");
 Prefs=@{};Refused();Prefs=@{@"fixture_ota_firmware_auto_update":@YES};Refused();Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
 Idle=NO;Refused();Idle=YES;Healthy=NO;Refused();Healthy=YES;
 NSDictionary *validHost=Host;Host=@{};Refused();Host=validHost;
 NSString *ap=[directory stringByAppendingPathComponent:@"nuttx_ap.bin"];NSMutableData *bytes=[[NSData dataWithContentsOfFile:ap]mutableCopy];NSData *original=[bytes copy];((uint8_t *)bytes.mutableBytes)[50]^=1;assert([bytes writeToFile:ap atomically:YES]);Refused();assert([original writeToFile:ap atomically:YES]);
 // One explicit confirmation boundary invokes the existing authorizer once.
 // Stage1 then makes the wizard's authorize action unavailable; no new UI or
 // policy confirmation path is introduced by the TMG2 compatibility removal.
 unsigned confirmations=0;NSError *error=nil;assert([Snapshot(YES)[@"canAuthorize"]boolValue]);confirmations++;assert(TIOOTAFlashAuthorize(&error)&&!error);assert(confirmations==1);assert([Snapshot(YES)[@"phase"]intValue]==TIOOTAPhaseAuthorized&&! [Snapshot(YES)[@"canAuthorize"]boolValue]);assert(!TIOOTAFlashAuthorize(nil));
 // Wrong peer cannot start an otherwise authorized transfer.
 assert(!Send(4,@{@"Mode":@2},nil,@"other-peer"));assert(TIOOTAFlashCancel());
 Observe(version,YES,@"other-peer");assert(TIOOTAFlashAuthorize(nil));assert(!Send(4,@{@"Mode":@2},nil,@"fixture-peer"));assert(TIOOTAFlashCancel());Observe(version,YES,@"fixture-peer");assert(TIOOTAFlashAuthorize(nil));
 assert(Send(4,@{@"Mode":@2},nil,@"fixture-peer"));assert([Snapshot(YES)[@"phase"]intValue]==TIOOTAPhaseInstalling);assert(!TIOOTAFlashCancel());
 NSDictionary *files=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:directory],nil);assert(files.count==16);NSArray *manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:nil];
 assert(Send(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil,@"fixture-peer"));assert(Send(6,manifest,nil,@"fixture-peer"));unsigned slices=0;NSUInteger total=0;
 for(NSDictionary *row in manifest){NSData *file=files[row[@"Name"]];for(NSUInteger at=0;at<file.length;at+=51200){NSUInteger n=MIN((NSUInteger)51200,file.length-at);assert(Send(7,@{@"Name":row[@"Name"],@"Start":@(at),@"Size":@(n)},[file subdataWithRange:NSMakeRange(at,n)],@"fixture-peer"));slices++;total+=n;}}
 assert(slices==TIO_FW_PAYLOAD_SLICES&&total==TIO_FW_PAYLOAD_BYTES);assert([TIOOTAFlashStatus()[@"validatedSlices"]unsignedIntegerValue]==slices);
 [fm removeItemAtPath:Home error:nil];printf("PASS real OTA wizard/gate from %s: fresh validated business9, exact candidate and all slices, one authorization transition, no feature caps, stale/hash/peer/idle refusals; deviceIO=false\n",version.UTF8String);
}return 0;}
