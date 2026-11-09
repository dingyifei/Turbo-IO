// Full 1.0.11 host (ios1011, C15): where the arm record is read from. Runs the unchanged
// phone policy (ExperimentalOTAFlash.m, adapted by test.py like tmg4-wizard-1011) with the
// REAL CFPreferences calls, only the suite name swapped for a throwaway one, so the Mac's
// preferences for the addon's own suite are never touched. The throwaway suite is removed
// at the end. No device, network or signing.
//
// The record must come from the suite's persistent domain only. NSUserDefaults'
// -initWithSuiteName: also searches NSArgumentDomain, so a launch argument
// -otaFlashArmRecord.ios1011 '<dict>...</dict>' (an XML plist gives real NSNumbers) would
// arm without the wizard. This test launches itself with that argument and requires the
// child to stay disarmed, and does the same with an in-process argument domain.
#import "TMG4WizardHost.h"
#import "OTAHost.h"
#import "HostCompatibility.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTAGuard.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#import <dlfcn.h>
#import <mach-o/loader.h>
#include <assert.h>
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
static NSString *Home,*Suite;
static NSDictionary *Prefs,*Host;
static const struct mach_header *Image;
NSString *TMG4Home(void){return Home;}
NSTimeInterval TMG4Now(void){return 100;}
NSDictionary *TMG4HostInfo(void){return Host;}
NSDictionary *TMG4Prefs(void){return Prefs;}
const struct mach_header *TMG4MainImage(void){return Image;}
NSString *TMG4ArmSuite(void){return Suite;}
BOOL TDPPhonePauseForOTA(void){return YES;}
NSDictionary *TIOExperimentalOTAFeedStatus(void){return @{};}
static NSString *const ArmKey=@"otaFlashArmRecord.ios1011";
static NSString *const NotArmed=@"本机 TMG 刷写尚未启用；先在向导中启用，未授权。";
typedef struct {struct mach_header_64 h;struct uuid_command u;} FakeHeader;
static const struct mach_header *FakeImage(NSString *uuid){
    FakeHeader *f=calloc(1,sizeof *f);assert(f);f->h.magic=MH_MAGIC_64;f->h.filetype=MH_EXECUTE;f->h.ncmds=1;f->h.sizeofcmds=sizeof(struct uuid_command);
    f->u.cmd=LC_UUID;f->u.cmdsize=sizeof(struct uuid_command);[[[NSUUID alloc]initWithUUIDString:uuid] getUUIDBytes:f->u.uuid];
    return (const struct mach_header *)f;
}
static NSString *InstallID(void){
    Dl_info info;assert(dladdr((const void *)&TIOOTAArmRequired,&info)&&info.dli_fbase);
    const struct mach_header_64 *h=info.dli_fbase;assert(h->magic==MH_MAGIC_64);const uint8_t *p=(const uint8_t *)(h+1);
    for(uint32_t i=0;i<h->ncmds;i++){const struct load_command *c=(const void *)p;if(c->cmd==LC_UUID)return [[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString];p+=c->cmdsize;}
    assert(0&&"test binary has no LC_UUID");return nil;
}
static NSDictionary *Good(void){return @{@"v":@1,@"host":@"ios1011",@"install":InstallID(),@"armedAt":@1};}
// What -initWithSuiteName: sees for the key (the old reader): proves the argument domain carries the record.
static id SuiteView(void){return [[[NSUserDefaults alloc]initWithSuiteName:Suite] objectForKey:ArmKey];}
static id Persistent(void){return [NSUserDefaults.standardUserDefaults persistentDomainForName:Suite][ArmKey];}
static void Disarmed(const char *where){
    assert(TIOOTAArmRequired());
    if(TIOOTAFlashArmed()||[TIOOTAFlashArmStatus()[@"armed"] boolValue]||[TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]){fprintf(stderr,"FAIL: armed from %s\n",where);abort();}
    NSError *e=nil;assert(!TIOOTAFlashAuthorize(&e)&&[e.localizedDescription isEqual:TIOText(NotArmed)]);
}
static void Clean(void){
    CFPreferencesSetValue((__bridge CFStringRef)ArmKey,NULL,(__bridge CFStringRef)Suite,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)Suite,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    // cfprefsd wrote the file on the synchronize above and has nothing left to write: delete it.
    NSString *plist=[NSString stringWithFormat:@"%@/Library/Preferences/%@.plist",NSHomeDirectory(),Suite];
    [NSFileManager.defaultManager removeItemAtPath:plist error:nil];
}
int main(int argc,char **argv){@autoreleasepool{
    Host=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259",
        @"TIOHostProfile":@"ios1011",@"TIOExperimentalOTAQueryRouting":TIO_OTA_1011_ROUTING_MARKER};
    Image=FakeImage(@"22724C97-2EF9-388D-8E6A-6E051855A555");Prefs=@{@"fixture_ota_firmware_auto_update":@NO};
    Home=NSTemporaryDirectory();TIOOTARecordTransportHookReady();assert(TIOOTAFlashBuild()&&TIOOTAFlashProtected());
    if(argc==4&&!strcmp(argv[1],"child")){
        // Launched with -otaFlashArmRecord.ios1011 <XML dict>: the suite view has a valid record, the guard must not.
        Suite=@(getenv("TIO_ARMSTORE_SUITE"));assert([Suite hasPrefix:@"io.turboio.test-armstore."]);NSDictionary *seen=SuiteView();
        assert([seen isEqual:Good()]&&[seen[@"v"] isKindOfClass:NSNumber.class]);assert(!Persistent());
        Disarmed("a launch argument");
        printf("child: launch argument record ignored\n");return 0;
    }
    assert(argc==1);
    Suite=[@"io.turboio.test-armstore." stringByAppendingString:NSUUID.UUID.UUIDString];Clean();
    // 1. A launch argument, in a child process of this same binary (same LC_UUID).
    NSDictionary *good=Good();
    NSString *xml=[[NSString alloc]initWithData:[NSPropertyListSerialization dataWithPropertyList:good format:NSPropertyListXMLFormat_v1_0 options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSRange open=[xml rangeOfString:@"<dict>"],close=[xml rangeOfString:@"</dict>" options:NSBackwardsSearch];
    NSString *dict=[xml substringWithRange:NSMakeRange(open.location,NSMaxRange(close)-open.location)];
    // <self> child -otaFlashArmRecord.ios1011 <dict>; the throwaway suite name travels in the environment.
    char *spawnArgs[]={argv[0],"child","-otaFlashArmRecord.ios1011",(char *)dict.UTF8String,NULL};
    setenv("TIO_ARMSTORE_SUITE",Suite.UTF8String,1);
    pid_t pid;int status=0;
    assert(posix_spawn(&pid,argv[0],NULL,NULL,spawnArgs,environ)==0);assert(waitpid(pid,&status,0)==pid);
    if(!WIFEXITED(status)||WEXITSTATUS(status)){fprintf(stderr,"FAIL: launch-argument child status %d\n",status);Clean();abort();}
    // 2. The same through an in-process argument domain.
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{ArmKey:good} forName:NSArgumentDomain];
    assert([SuiteView() isEqual:good]&&!Persistent());Disarmed("the argument domain");
    // 3. A registered default (NSRegistrationDomain) for the key does not arm either.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{ArmKey:good}];Disarmed("a registered default");
    // 4. The wizard's arm writes the suite's persistent domain, which is what arms; disarm clears it.
    NSError *e=nil;assert(TIOOTAFlashArm(&e)&&!e);NSDictionary *stored=Persistent();
    assert(stored.count==4&&[stored[@"install"] isEqual:InstallID()]&&[stored[@"v"] isEqual:@1]);
    assert(TIOOTAFlashArmed()&&[TIOOTAFlashArmStatus()[@"armedForTransfer"] boolValue]);
    assert(TIOOTAFlashDisarm()&&!Persistent());Disarmed("the argument domain after disarm");
    // 5. A record written straight into the persistent domain arms (the reader's one source).
    CFPreferencesSetValue((__bridge CFStringRef)ArmKey,(__bridge CFPropertyListRef)good,(__bridge CFStringRef)Suite,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)Suite,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    assert(TIOOTAFlashArmed());assert(TIOOTAFlashDisarm()&&!TIOOTAFlashArmed());
    [NSUserDefaults.standardUserDefaults removeVolatileDomainForName:NSArgumentDomain];
    Clean();
    printf("PASS: 1.0.11 arm record read from the suite's persistent domain only: launch argument, argument domain and registered default ignored; arm/disarm round trip through the real preferences on a throwaway suite\n");
}return 0;}
