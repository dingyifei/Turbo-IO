// G2 and G3 for the download-only 1.0.11/259 host, on the pure model the export
// panel and Addon.m use (DownloadOnlySafety.m). No UIKit, device or network.
// G2: a hook install that cannot resolve its targets leaves the guard inactive
//     and the panel unsafe, whatever Auto Update says.
// G3: Auto Update is read (never written) from *_ota_firmware_auto_update keys.
#import "DownloadOnlySafety.h"
#import "TIOLanguage.h"
#include <assert.h>

static Class Fake(NSString *name,NSString *selector,const char *types){
    Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);assert(c);
    if(selector)assert(class_addMethod(c,NSSelectorFromString(selector),imp_implementationWithBlock(^(id self){}),types));
    objc_registerClassPair(c);return c;
}
// What TIOInstallGlassesChannelHook does with the target check: install only when it
// passes; the transport hook is recorded ready only by a successful install.
static NSDictionary *AfterInstall(Class bridge,Class engine,NSDictionary *prefs,NSString **failure){
    NSString *why=TIOChannelHookTargetFailure(bridge,engine);if(failure)*failure=why;
    BOOL installed=why==nil;
    assert(TIODownloadOnlyGuardActiveFor(@"ios1011-download",installed,installed)==installed);
    return TIOFirmwareExportSafetyModel(@"ios1011-download",installed,installed,prefs);
}
static void Localized(NSDictionary *m){
    for(NSString *k in @[@"guardKey",@"guardDetail",@"autoKey",@"autoDetail",@"bannerKey"]){
        NSString *key=m[k];if(!key){assert([k isEqual:@"bannerKey"]);continue;}
        assert(![TIOTextForLanguage(key,TIOLangEnglish) isEqual:key]);assert(![TIOTextForLanguage(key,TIOLangChinese) isEqual:key]);
    }
}
int main(void){@autoreleasepool{
    NSDictionary *off=@{@"acct_ota_firmware_auto_update":@NO};
    // G2: target check, each way it can fail.
    Class bridge=Fake(@"FakeBridge",@"handleMethodCall:result:","v@:@@"),engine=Fake(@"FakeEngine",@"sendOnChannel:message:binaryReply:","v@:@@@");
    assert(TIOChannelHookTargetFailure(bridge,engine)==nil);
    struct {Class bridge,engine;NSString *needle;} bad[]={
        {Nil,engine,@"bridge class missing"},
        {Fake(@"BridgeNoMethod",nil,NULL),engine,@"handleMethodCall:result:"},
        {Fake(@"BridgeReturnsBool",@"handleMethodCall:result:","B@:@@"),engine,@"handleMethodCall:result:"},
        {Fake(@"BridgeScalarArg",@"handleMethodCall:result:","v@:@q"),engine,@"handleMethodCall:result:"},
        {Fake(@"BridgeOtherSelector",@"handleMethodCall:","v@:@"),engine,@"handleMethodCall:result:"},
        {bridge,Nil,@"FlutterEngine class missing"},
        {bridge,Fake(@"EngineNoMethod",nil,NULL),@"sendOnChannel:message:binaryReply:"},
        {bridge,Fake(@"EngineScalarArg",@"sendOnChannel:message:binaryReply:","v@:@@q"),@"sendOnChannel:message:binaryReply:"},
        {bridge,Fake(@"EngineReturnsObject",@"sendOnChannel:message:binaryReply:","@@:@@@"),@"sendOnChannel:message:binaryReply:"},
    };
    for(size_t i=0;i<sizeof bad/sizeof *bad;i++){
        NSString *why=nil;NSDictionary *m=AfterInstall(bad[i].bridge,bad[i].engine,off,&why);
        assert(why.length&&[why containsString:bad[i].needle]);
        assert(![m[@"guardActive"] boolValue]&&![m[@"safe"] boolValue]);
        assert([m[@"guardLevel"] isEqual:@"danger"]&&[m[@"level"] isEqual:@"danger"]);
        assert([m[@"guardKey"] isEqual:@"fwexport.guard.off"]&&[m[@"bannerKey"] isEqual:@"fwexport.banner.unguarded"]);
        Localized(m);
    }
    // The working install: guard on and, with Auto Update off, safe and quiet.
    NSDictionary *ok=AfterInstall(bridge,engine,off,NULL);
    assert([ok[@"guardActive"] boolValue]&&[ok[@"safe"] boolValue]&&[ok[@"level"] isEqual:@"ok"]&&!ok[@"bannerKey"]);Localized(ok);
    // The guard needs all three parts; no profile but the download-only one counts.
    for(NSString *profile in @[@"ios107",@"",@"ios1011"])assert(!TIODownloadOnlyGuardActiveFor(profile,YES,YES));
    assert(!TIODownloadOnlyGuardActiveFor(nil,YES,YES));
    assert(!TIODownloadOnlyGuardActiveFor(@"ios1011-download",YES,NO));assert(!TIODownloadOnlyGuardActiveFor(@"ios1011-download",NO,YES));
    assert(![TIOFirmwareExportSafetyModel(@"ios1011-download",YES,NO,off)[@"safe"] boolValue]);
    assert(![TIOFirmwareExportSafetyModel(nil,YES,YES,off)[@"safe"] boolValue]);

    // G3: explicit off.
    for(NSDictionary *p in @[off,@{@"x_ota_firmware_auto_update":@"false"},@{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@"false",@"unrelated":@YES}])
        assert(TIOAutoUpdateReadingFor(p)==TIOAutoUpdateReadingOff);
    // On, or any value that is not an explicit false; one bad key is enough (worst wins).
    for(id v in @[@YES,@"true",@0,@1,@"0",@"False",@"",NSNull.null,@{},@[]])assert(TIOAutoUpdateReadingFor(@{@"x_ota_firmware_auto_update":v})==TIOAutoUpdateReadingOn);
    assert(TIOAutoUpdateReadingFor(@{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@YES})==TIOAutoUpdateReadingOn);
    assert(TIOAutoUpdateReadingFor(@{@"a_ota_firmware_auto_update":@"false",@"b_ota_firmware_auto_update":@"yes"})==TIOAutoUpdateReadingOn);
    // Missing: no key with the suffix (exact suffix, string keys only).
    for(id p in @[@{},@{@"ota_firmware_auto_update_x":@NO},@{@"x_ota_firmware_auto_updates":@NO},@{@1:@NO},[NSNull null]])assert(TIOAutoUpdateReadingFor(p)==TIOAutoUpdateReadingMissing);
    assert(TIOAutoUpdateReadingFor(nil)==TIOAutoUpdateReadingMissing);
    assert([TIOAutoUpdateReadingName(TIOAutoUpdateReadingOff) isEqual:@"off"]&&[TIOAutoUpdateReadingName(TIOAutoUpdateReadingMissing) isEqual:@"missing"]&&[TIOAutoUpdateReadingName(TIOAutoUpdateReadingOn) isEqual:@"on"]);
    // Panel rows and banner with the guard on.
    NSDictionary *on=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,@{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@YES});
    assert([on[@"autoUpdate"] isEqual:@"on"]&&[on[@"autoLevel"] isEqual:@"danger"]&&[on[@"level"] isEqual:@"danger"]&&![on[@"safe"] boolValue]);
    assert([on[@"autoKey"] isEqual:@"fwexport.auto.on"]&&[on[@"bannerKey"] isEqual:@"fwexport.banner.autoOn"]);Localized(on);
    assert([TIOTextForLanguage(on[@"autoKey"],TIOLangEnglish) isEqual:@"Auto Update is ON: turn it off in the firmware page before anything else"]);
    NSDictionary *missing=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,@{});
    assert([missing[@"autoUpdate"] isEqual:@"missing"]&&[missing[@"autoLevel"] isEqual:@"warn"]&&[missing[@"level"] isEqual:@"warn"]&&![missing[@"safe"] boolValue]);
    assert([missing[@"autoKey"] isEqual:@"fwexport.auto.missing"]&&[missing[@"bannerKey"] isEqual:@"fwexport.banner.autoMissing"]);Localized(missing);
    assert([TIOTextForLanguage(missing[@"autoDetail"],TIOLangEnglish) containsString:@"treats missing as off"]);
    assert([ok[@"autoKey"] isEqual:@"fwexport.auto.off"]&&[ok[@"autoLevel"] isEqual:@"ok"]);
    // Guard off outranks every Auto Update state in the banner and the level.
    for(NSDictionary *p in @[off,@{},@{@"a_ota_firmware_auto_update":@YES}]){
        NSDictionary *m=TIOFirmwareExportSafetyModel(@"ios1011-download",NO,NO,p);
        assert([m[@"bannerKey"] isEqual:@"fwexport.banner.unguarded"]&&[m[@"level"] isEqual:@"danger"]);
    }
    // Read only: the model never changes the preferences it is given.
    NSMutableDictionary *prefs=[@{@"a_ota_firmware_auto_update":@YES} mutableCopy];NSDictionary *before=[prefs copy];
    TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,prefs);assert([prefs isEqual:before]);
    NSLog(@"PASS: download-only safety: %zu hook target failures leave the guard off and the panel unsafe; Auto Update off/on/missing with worst key wins; read only",sizeof bad/sizeof *bad);
}return 0;}
