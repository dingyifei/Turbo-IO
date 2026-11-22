// Replays the flash sequence recorded on 2026-11-15 with RayNeo AI 1.0.21 (1) (tests/flash-sequence-1021.json)
// through the real guard and gate (ExperimentalOTAFlash.m, adapted by test.py like tmg4-wizard) on the full
// 1.0.21 host (tests/FullHostFixture.h). The slices are cut from the release's unzipped --firmware ZIP, so the
// fixture holds no payload bytes. One run per mode, because stages 2 and 3 last until the process ends:
//   replay        every tx frame allowed, stage 2 reached, 314 slices and 15,753,934 bytes;
//   no-auth       a transfer frame with no authorization;
//   mode          type 4 with a Mode other than 2;
//   version       type 5 with a wrong OtaVersion;
//   manifest      type 6 with a changed manifest;
//   early-slice   a slice before the manifest;
//   flip          a slice with one byte flipped;
//   unpinned      a slice of a file that is not pinned;
//   past-end      a slice past the end of its file;
//   device        type 4 and a slice from another device;
//   expired       type 4 after the authorization is 15 minutes old;
//   second-start  a second type 4 after the start, then stage 3.
// Each mutation must be refused. One more mode checks the hook protection (TIOOTAFlashProtected) on its own:
//   unprotected   the exact host, its pinned image, the feed, Auto Update off and an accepted version read
//                 are all in place, and authorization is still refused while the protection is missing:
//                 before the transport hook is ready (flash build), and in a build without
//                 TIO_OTA_FLASH_ENABLED (test.py runs this mode in both builds).
// argv: <candidate dir> <home root> <fixture> <mode>. No device I/O.
#import "TMG4WizardHost.h"
#import "FullHostFixture.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#import "FirmwarePins.h"
#import "HostCompatibility.h"
#import "TIOLanguage.h"
#import <CommonCrypto/CommonDigest.h>
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
static NSString *const Peer=@"fixture-peer",*const OtherPeer=@"other-peer";
static BOOL Send(NSData *frame,NSString *peer){return !TIOOTAFlashBlockCall(@{@"method":@"rayneonet_sendMessage",@"arguments":@{@"businessId":@9,@"deviceId":peer,@"payload":frame}});}
static void Receive(NSData *frame){TIOOTAFlashObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@9,@"deviceId":Peer,@"payload":frame}});}
static NSUInteger Stage(void){return [TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue];}
static NSString *Hex(NSData *d){uint8_t h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);NSMutableString *x=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[x appendFormat:@"%02x",h[i]];return x;}
static NSData *Slice(NSString *name,NSUInteger start,NSData *bytes){return Frame(7,@{@"Name":name,@"Start":@(start),@"Size":@(bytes.length)},bytes);}
// A mutated frame: refused, and the gate then in the stage given.
static void Refused(const char *what,NSData *frame,NSString *peer,NSUInteger stage){
    BOOL allowed=Send(frame,peer);
    if(allowed||Stage()!=stage){fprintf(stderr,"FAIL %s: allowed %d, stage %lu (want refused, stage %lu)\n",what,allowed,(unsigned long)Stage(),(unsigned long)stage);abort();}
    printf("refused: %s (stage %lu)\n",what,(unsigned long)stage);
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==5);NSString *mode=@(argv[4]);NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *modes=@[@"replay",@"no-auth",@"mode",@"version",@"manifest",@"early-slice",@"flip",@"unpinned",@"past-end",@"device",@"expired",@"second-start",@"unprotected"];
    assert([modes containsObject:mode]);
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[3])] options:0 error:nil];
    assert([fixture[@"statement"] isEqual:@"sequence seen on 2026-11-15 with RayNeo AI 1.0.21 (1)"]&&[fixture[@"businessId"] isEqual:@9]);
    NSUInteger sliceBytes=[fixture[@"sliceBytes"] unsignedIntegerValue];assert(sliceBytes==51200);
    NSArray *steps=fixture[@"steps"];assert(steps.count);
    // The release folder in the full host's container, from the unzipped --firmware ZIP.
    Home=[@(argv[2]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *directory=[Home stringByAppendingPathComponent:[@"Library/Application Support/ota/" stringByAppendingString:TIO_FW_OTA_FOLDER]];
    assert([fm createDirectoryAtPath:directory.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);
    assert([fm copyItemAtPath:@(argv[1]) toPath:directory error:nil]);
    NSDictionary *files=TIOCopyExperimentalOTAPayloads([NSURL fileURLWithPath:directory],TIOOTASelectedPackage(),nil);assert(files.count==TIO_FW_MEMBER_PINS.count);
    Host=TFHFullInfo();Image=FakeImage(TFH_UUID);Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    if([mode isEqual:@"unprotected"]){
        NSString *unprotected=TIOText(@"没有试刷构建与发送保护；未开放。");NSError *e=nil;
        assert(TIOOTAFullHost()&&TIOOTA1021HostMatches(Host)&&TIOHostFullImageMatches(Image,Host)&&TIOOTAAutoUpdateDisabled(Prefs));
        NSDictionary *read=nil;for(NSDictionary *s in steps)if([s[@"d"] isEqual:@"rx"]&&[s[@"type"] isEqual:@1]){read=s[@"json"];break;}
        assert([read isKindOfClass:NSDictionary.class]);Receive(Frame(1,read,nil));
        if(TIOOTAFlashBuild()){
            // The transport hook is not ready yet: the protection is the only condition missing.
            assert([TIOOTAFlashStatus()[@"recentTargetVersionRead"] boolValue]&&!TIOOTAFlashProtected());
            assert(!TIOOTAFlashAuthorize(&e)&&[e.localizedDescription isEqual:unprotected]&&Stage()==0);
            Refused("type 4 before the transport hook is ready",Frame(4,@{@"Mode":@2},nil),Peer,0);
            // With the hook ready the same state authorizes, so nothing else was missing.
            TIOOTARecordTransportHookReady();e=nil;assert(TIOOTAFlashProtected()&&TIOOTAFlashAuthorize(&e)&&!e&&Stage()==1);
        }else{
            // A build without TIO_OTA_FLASH_ENABLED is never protected, even with the transport hook ready.
            TIOOTARecordTransportHookReady();assert(!TIOOTAFlashProtected());
            assert(!TIOOTAFlashAuthorize(&e)&&[e.localizedDescription isEqual:unprotected]&&Stage()==0);
            Refused("type 4 in a build without TIO_OTA_FLASH_ENABLED",Frame(4,@{@"Mode":@2},nil),Peer,0);
        }
        printf("PASS flash sequence unprotected: authorization refused without the hook protection (flash build %s)\n",TIOOTAFlashBuild()?"on":"off");
        [fm removeItemAtPath:Home error:nil];return 0;
    }
    TIOOTARecordTransportHookReady();assert(TIOOTAFullHost()&&TIOOTAFlashProtected()&&Stage()==0);
    // The fixture's file plan must match the release: sizes, slice counts and the first and last slice sizes.
    NSUInteger planned=0,plannedBytes=0;
    for(NSDictionary *s in steps)if([s[@"type"] isEqual:@7]){
        NSData *file=files[s[@"name"]];assert(file&&file.length==[s[@"bytes"] unsignedIntegerValue]);
        NSUInteger n=(file.length+sliceBytes-1)/sliceBytes;assert(n==[s[@"slices"] unsignedIntegerValue]);
        assert(MIN(sliceBytes,file.length)==[s[@"first"] unsignedIntegerValue]&&file.length-(n-1)*sliceBytes==[s[@"last"] unsignedIntegerValue]);
        planned+=n;plannedBytes+=file.length;
    }
    assert(planned==[fixture[@"totalSlices"] unsignedIntegerValue]&&plannedBytes==[fixture[@"totalSliceBytes"] unsignedIntegerValue]);
    assert(planned==314&&plannedBytes==15753934);
    NSData *manifest=files[@"OtaFileInfo.json"];
    BOOL authorized=NO,started=NO,sentVersion=NO,sentManifest=NO;NSUInteger sent=0,slices=0;
    for(NSDictionary *s in steps){
        NSUInteger type=[s[@"type"] unsignedIntegerValue],count=s[@"count"]?[s[@"count"] unsignedIntegerValue]:1;
        if([s[@"d"] isEqual:@"rx"]){for(NSUInteger i=0;i<count;i++)Receive(Frame(type,s[@"json"],nil));continue;}
        assert([s[@"d"] isEqual:@"tx"]);
        // The owner's one confirmation in the wizard comes after the version read and before the first transfer frame.
        if(type>=3&&!authorized){
            authorized=YES;
            if(![mode isEqual:@"no-auth"]){NSError *e=nil;assert(TIOOTAFlashAuthorize(&e)&&!e&&Stage()==1);}
            if([mode isEqual:@"expired"])Now+=900;
        }
        if(type==4&&!started){
            if([mode isEqual:@"no-auth"]){Refused("type 4 with no authorization",Frame(4,s[@"json"],nil),Peer,0);
                assert(!Send(Frame(5,@{@"OtaVersion":TIO_FW_OTA_VERSION},nil),Peer)&&!Send(RawFrame(6,manifest,nil),Peer)&&Stage()==0);break;}
            if([mode isEqual:@"expired"]){Refused("type 4 after a 15 minute old authorization",Frame(4,s[@"json"],nil),Peer,0);break;}
            if([mode isEqual:@"mode"]){
                for(NSArray *m in @[@[@1,@"1"],@[@3,@"3"],@[@4,@"4 (the forced update page)"],@[@0,@"0"],@[@"2",@"\"2\" (a string)"],@[@2.5,@"2.5"],@[@YES,@"true"]])
                    Refused([[@"type 4 Mode " stringByAppendingString:m[1]] UTF8String],Frame(4,@{@"Mode":m[0]},nil),Peer,1);
                Refused("type 4 Mode 2 with another key",Frame(4,@{@"Mode":@2,@"Force":@YES},nil),Peer,1);
                break;
            }
            if([mode isEqual:@"device"])Refused("type 4 from another device",Frame(4,s[@"json"],nil),OtherPeer,1);
        }
        if(type==5&&[mode isEqual:@"version"]){Refused("type 5 with a wrong OtaVersion",Frame(5,@{@"OtaVersion":@"Strix OS 1.0.5.12"},nil),Peer,3);break;}
        if(type==5&&[mode isEqual:@"second-start"]){Refused("a second type 4 after the start",Frame(4,@{@"Mode":@2},nil),Peer,3);
            assert(!Send(Frame(5,s[@"json"],nil),Peer)&&!TIOOTAFlashCancel()&&!TIOOTAFlashAuthorize(nil)&&Stage()==3);
            assert(Send(Frame(1,nil,nil),Peer)&&Send(Frame(3,@{@"OtaSize":@(TIO_FW_ZIP_BYTES)},nil),Peer));break;}
        if(type==6&&[mode isEqual:@"early-slice"]){NSData *first=files[@"nuttx_audio.bin"];
            Refused("a slice before the manifest",Slice(@"nuttx_audio.bin",0,[first subdataWithRange:NSMakeRange(0,sliceBytes)]),Peer,3);break;}
        if(type==6&&[mode isEqual:@"manifest"]){
            NSMutableArray *rows=[[NSJSONSerialization JSONObjectWithData:manifest options:NSJSONReadingMutableContainers error:nil] mutableCopy];
            rows[0][@"Extra"]=@1;
            Refused("type 6 with a changed manifest",Frame(6,rows,nil),Peer,3);break;
        }
        NSData *frame=nil;
        if(type==6){
            assert(manifest.length==[s[@"jsonBytes"] unsignedIntegerValue]&&[Hex(manifest) isEqual:s[@"jsonSha256"]]);
            frame=RawFrame(6,manifest,nil);
        }else if(type==7){
            NSString *name=s[@"name"];NSData *file=files[name];BOOL mutated=NO;
            for(NSUInteger at=0;at<file.length;at+=sliceBytes){
                NSData *bytes=[file subdataWithRange:NSMakeRange(at,MIN(sliceBytes,file.length-at))];
                if([name isEqual:@"nuttx_ap.bin"]&&at==80*sliceBytes){
                    if([mode isEqual:@"flip"]){NSMutableData *m=[bytes mutableCopy];((uint8_t *)m.mutableBytes)[1234]^=1;Refused("a slice with one byte flipped",Slice(name,at,m),Peer,3);mutated=YES;break;}
                    if([mode isEqual:@"unpinned"]){Refused("a slice of a file that is not pinned",Slice(@"rives.bin",0,bytes),Peer,3);mutated=YES;break;}
                    if([mode isEqual:@"past-end"]){NSMutableData *m=[[file subdataWithRange:NSMakeRange(file.length-100,100)] mutableCopy];[m appendData:[NSMutableData dataWithLength:100]];
                        Refused("a slice past the end of its file",Slice(name,file.length-100,m),Peer,3);mutated=YES;break;}
                    if([mode isEqual:@"device"]){Refused("a slice from another device",Slice(name,at,bytes),OtherPeer,3);mutated=YES;break;}
                }
                if(!Send(Slice(name,at,bytes),Peer)){fprintf(stderr,"FAIL replay: slice %s at %lu refused\n",name.UTF8String,(unsigned long)at);abort();}
                slices++;sent++;
            }
            if(mutated)break;
            continue;
        }else frame=Frame(type,s[@"json"],nil);
        for(NSUInteger i=0;i<count;i++){
            if(!Send(frame,Peer)){fprintf(stderr,"FAIL replay: tx type %lu refused at stage %lu\n",(unsigned long)type,(unsigned long)Stage());abort();}
            sent++;
        }
        if(type==4){started=YES;assert(Stage()==2);}
        if(type==5)sentVersion=YES;
        if(type==6)sentManifest=YES;
    }
    NSDictionary *status=TIOOTAFlashStatus();
    if([mode isEqual:@"replay"]){
        assert(started&&sentVersion&&sentManifest&&Stage()==2&&[status[@"started"] boolValue]);
        assert(slices==314&&[status[@"validatedSlices"] unsignedIntegerValue]==314&&[status[@"validatedSliceBytes"] unsignedIntegerValue]==15753934);
        // After the flash the glasses report the target version: still stage 2, and it cannot be cancelled.
        assert(!TIOOTAFlashCancel()&&Stage()==2);
        printf("PASS flash sequence replay: %lu tx frames allowed, stage 2 reached, %lu slices, %lu bytes\n",(unsigned long)sent,(unsigned long)slices,(unsigned long)[status[@"validatedSliceBytes"] unsignedIntegerValue]);
    }else printf("PASS flash sequence mutation %s: refused\n",mode.UTF8String);
    [fm removeItemAtPath:Home error:nil];
}return 0;}
