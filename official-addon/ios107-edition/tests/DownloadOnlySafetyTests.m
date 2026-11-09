// G2 and G3 for the download-only 1.0.11/259 host, on the pure model the export
// panel and Addon.m use (DownloadOnlySafety.m). No UIKit, device or network.
// G2: a hook install that cannot resolve its targets leaves the guard inactive
//     and the panel unsafe, whatever Auto Update says.
//     The guard row is green only once a stock rayneonet call has passed the hook;
//     installed without that evidence it is amber.
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
    // Stock traffic seen, so the guard level comes from the install alone here.
    return TIOFirmwareExportSafetyModel(@"ios1011-download",installed,installed,YES,prefs);
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
    assert(![TIOFirmwareExportSafetyModel(@"ios1011-download",YES,NO,YES,off)[@"safe"] boolValue]);
    assert(![TIOFirmwareExportSafetyModel(nil,YES,YES,YES,off)[@"safe"] boolValue]);

    // G2 runtime evidence: the guard row's three states.
    // ok: hook installed, transport ready and a stock rayneonet call seen.
    assert([TIODownloadOnlyGuardLevelFor(@"ios1011-download",YES,YES,YES) isEqual:@"ok"]);
    assert([ok[@"guardLevel"] isEqual:@"ok"]&&[ok[@"stockTrafficSeen"] boolValue]&&[ok[@"guardKey"] isEqual:@"fwexport.guard.on"]&&[ok[@"guardDetail"] isEqual:@"fwexport.guard.on.detail"]);
    assert([TIOTextForLanguage(ok[@"guardKey"],TIOLangEnglish) isEqual:@"OTA transfer blocked (stock calls seen)"]);
    assert([TIOTextForLanguage(ok[@"guardKey"],TIOLangChinese) containsString:@"已看到官方调用"]);
    // warn: installed and ready, but no stock call has passed the hook yet. Amber, never safe,
    // whatever Auto Update says; the no-traffic banner shows unless Auto Update is ON.
    assert([TIODownloadOnlyGuardLevelFor(@"ios1011-download",YES,YES,NO) isEqual:@"warn"]);
    NSDictionary *waiting=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,NO,off);
    assert([waiting[@"guardActive"] boolValue]&&![waiting[@"stockTrafficSeen"] boolValue]&&![waiting[@"safe"] boolValue]);
    assert([waiting[@"guardLevel"] isEqual:@"warn"]&&[waiting[@"level"] isEqual:@"warn"]);
    assert([waiting[@"guardKey"] isEqual:@"fwexport.guard.waiting"]&&[waiting[@"guardDetail"] isEqual:@"fwexport.guard.waiting.detail"]);
    assert([waiting[@"bannerKey"] isEqual:@"fwexport.banner.noTraffic"]);Localized(waiting);
    assert([TIOTextForLanguage(waiting[@"guardKey"],TIOLangEnglish) isEqual:@"Guard installed, no stock traffic seen yet: connect the glasses and wait until the row turns green before opening the firmware page"]);
    assert([TIOTextForLanguage(waiting[@"guardKey"],TIOLangChinese) containsString:@"尚未看到官方调用"]);
    NSDictionary *waitingMissing=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,NO,@{});
    assert([waitingMissing[@"level"] isEqual:@"warn"]&&[waitingMissing[@"bannerKey"] isEqual:@"fwexport.banner.noTraffic"]&&![waitingMissing[@"safe"] boolValue]);
    NSDictionary *waitingOn=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,NO,@{@"a_ota_firmware_auto_update":@YES});
    assert([waitingOn[@"guardLevel"] isEqual:@"warn"]&&[waitingOn[@"level"] isEqual:@"danger"]&&[waitingOn[@"bannerKey"] isEqual:@"fwexport.banner.autoOn"]);
    // danger: as before. Stock traffic seen does not rescue a missing guard.
    for(NSArray *a in @[@[@NO,@NO],@[@YES,@NO],@[@NO,@YES]])for(NSNumber *seen in @[@NO,@YES]){
        BOOL installed=[a[0] boolValue],ready=[a[1] boolValue];
        assert([TIODownloadOnlyGuardLevelFor(@"ios1011-download",installed,ready,seen.boolValue) isEqual:@"danger"]);
        NSDictionary *m=TIOFirmwareExportSafetyModel(@"ios1011-download",installed,ready,seen.boolValue,off);
        assert([m[@"guardLevel"] isEqual:@"danger"]&&[m[@"level"] isEqual:@"danger"]&&![m[@"safe"] boolValue]);
        assert([m[@"guardKey"] isEqual:@"fwexport.guard.off"]&&[m[@"bannerKey"] isEqual:@"fwexport.banner.unguarded"]);
    }
    for(NSString *profile in @[@"ios107",@""])assert([TIODownloadOnlyGuardLevelFor(profile,YES,YES,YES) isEqual:@"danger"]);
    assert([TIODownloadOnlyGuardLevelFor(nil,YES,YES,YES) isEqual:@"danger"]);
    // The hub row follows the same keys, in both languages.
    for(NSString *k in @[@"hub.status.firmwareExport.guarded",@"hub.status.firmwareExport.waiting",@"hub.status.firmwareExport.unguarded"]){
        assert(![TIOTextForLanguage(k,TIOLangEnglish) isEqual:k]&&![TIOTextForLanguage(k,TIOLangChinese) isEqual:k]);
    }
    // Origin of a call: the image holding its result block's invoke function.
    NSString *bundle=@"/private/var/containers/Bundle/Application/X/Runner.app",*addon=@"/private/var/containers/Bundle/Application/X/Runner.app/Frameworks/TurboIOPrivateAddon.dylib";
    assert(TIOChannelResultImageIsStock(@"/private/var/containers/Bundle/Application/X/Runner.app/Frameworks/Flutter.framework/Flutter",addon,bundle));
    assert(TIOChannelResultImageIsStock(@"/var/containers/Bundle/Application/X/Runner.app/Runner",addon,bundle));
    assert(!TIOChannelResultImageIsStock(addon,addon,bundle));
    assert(!TIOChannelResultImageIsStock(@"/var/containers/Bundle/Application/X/Runner.app/Frameworks/TurboIOPrivateAddon.dylib",addon,bundle));
    assert(!TIOChannelResultImageIsStock(@"/var/containers/Bundle/Application/X/Runner.app/Frameworks/TurboAppleAI.dylib",nil,bundle));
    assert(!TIOChannelResultImageIsStock(@"/usr/lib/system/libdispatch.dylib",addon,bundle));
    assert(!TIOChannelResultImageIsStock(@"/System/Library/Frameworks/UIKit.framework/UIKit",addon,bundle));
    assert(!TIOChannelResultImageIsStock(@"/private/var/containers/Bundle/Application/X/Runner.appx/Runner",addon,bundle));
    assert(!TIOChannelResultImageIsStock(nil,addon,bundle)&&!TIOChannelResultImageIsStock(@"",addon,bundle));
    assert(!TIOChannelResultImageIsStock(@"/var/containers/Bundle/Application/X/Runner.app/Runner",addon,nil));

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
    NSDictionary *on=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,YES,@{@"a_ota_firmware_auto_update":@NO,@"b_ota_firmware_auto_update":@YES});
    assert([on[@"autoUpdate"] isEqual:@"on"]&&[on[@"autoLevel"] isEqual:@"danger"]&&[on[@"level"] isEqual:@"danger"]&&![on[@"safe"] boolValue]);
    assert([on[@"autoKey"] isEqual:@"fwexport.auto.on"]&&[on[@"bannerKey"] isEqual:@"fwexport.banner.autoOn"]);Localized(on);
    assert([TIOTextForLanguage(on[@"autoKey"],TIOLangEnglish) isEqual:@"Auto Update is ON: turn it off in the firmware page before anything else"]);
    NSDictionary *missing=TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,YES,@{});
    assert([missing[@"autoUpdate"] isEqual:@"missing"]&&[missing[@"autoLevel"] isEqual:@"warn"]&&[missing[@"level"] isEqual:@"warn"]&&![missing[@"safe"] boolValue]);
    assert([missing[@"autoKey"] isEqual:@"fwexport.auto.missing"]&&[missing[@"bannerKey"] isEqual:@"fwexport.banner.autoMissing"]);Localized(missing);
    assert([TIOTextForLanguage(missing[@"autoDetail"],TIOLangEnglish) containsString:@"treats missing as off"]);
    assert([ok[@"autoKey"] isEqual:@"fwexport.auto.off"]&&[ok[@"autoLevel"] isEqual:@"ok"]);
    // Guard off outranks every Auto Update state in the banner and the level.
    for(NSDictionary *p in @[off,@{},@{@"a_ota_firmware_auto_update":@YES}]){
        NSDictionary *m=TIOFirmwareExportSafetyModel(@"ios1011-download",NO,NO,YES,p);
        assert([m[@"bannerKey"] isEqual:@"fwexport.banner.unguarded"]&&[m[@"level"] isEqual:@"danger"]);
    }
    // Read only: the model never changes the preferences it is given.
    NSMutableDictionary *prefs=[@{@"a_ota_firmware_auto_update":@YES} mutableCopy];NSDictionary *before=[prefs copy];
    TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,YES,prefs);assert([prefs isEqual:before]);
    // Full 1.0.11 host (C15): the guard row is the arm state. Disarmed is green only once a stock call has
    // passed the hook (amber "waiting" before that, as on the download-only host), armed amber, no arm guard red.
    NSDictionary *disarmed=TIOFirmwareExportSafetyModelFull(YES,YES,NO,off);
    assert([disarmed[@"guardLevel"] isEqual:@"ok"]&&[disarmed[@"guardKey"] isEqual:@"fwexport.guard.disarmed"]&&[disarmed[@"safe"] boolValue]&&!disarmed[@"bannerKey"]);
    assert([disarmed[@"armed"] isEqual:@NO]&&[disarmed[@"guardActive"] isEqual:@YES]&&[disarmed[@"level"] isEqual:@"ok"]);Localized(disarmed);
    NSDictionary *quiet=TIOFirmwareExportSafetyModelFull(YES,NO,NO,off);
    assert([quiet[@"guardLevel"] isEqual:@"warn"]&&[quiet[@"guardKey"] isEqual:@"fwexport.guard.waiting"]&&![quiet[@"safe"] boolValue]);
    assert([quiet[@"bannerKey"] isEqual:@"fwexport.banner.noTraffic"]&&[quiet[@"armed"] isEqual:@NO]&&[quiet[@"level"] isEqual:@"warn"]&&[quiet[@"stockTrafficSeen"] isEqual:@NO]);Localized(quiet);
    assert([TIOFirmwareExportSafetyModelFull(YES,NO,NO,@{})[@"bannerKey"] isEqual:@"fwexport.banner.noTraffic"]);
    assert([TIOFirmwareExportSafetyModelFull(YES,NO,NO,@{@"a_ota_firmware_auto_update":@YES})[@"bannerKey"] isEqual:@"fwexport.banner.autoOn"]);
    for(int seen=0;seen<2;seen++){
        NSDictionary *armed=TIOFirmwareExportSafetyModelFull(YES,seen,YES,off);
        assert([armed[@"guardLevel"] isEqual:@"warn"]&&[armed[@"guardKey"] isEqual:@"fwexport.guard.armed"]&&![armed[@"safe"] boolValue]);
        assert([armed[@"bannerKey"] isEqual:@"fwexport.banner.armed"]&&[armed[@"armed"] isEqual:@YES]&&[armed[@"level"] isEqual:@"warn"]);Localized(armed);
        assert([TIOFirmwareExportSafetyModelFull(YES,seen,YES,@{@"a_ota_firmware_auto_update":@YES})[@"bannerKey"] isEqual:@"fwexport.banner.autoOn"]);
        assert([TIOFirmwareExportSafetyModelFull(YES,seen,YES,@{})[@"bannerKey"] isEqual:@"fwexport.banner.armed"]);
    }
    assert([TIOFirmwareExportSafetyModelFull(YES,YES,NO,@{})[@"bannerKey"] isEqual:@"fwexport.banner.autoMissing"]);
    for(NSDictionary *p in @[off,@{},@{@"a_ota_firmware_auto_update":@YES}])for(int a=0;a<2;a++)for(int seen=0;seen<2;seen++){
        // No arm guard in force: red, never armed, whatever the stored arm record or the traffic says.
        NSDictionary *m=TIOFirmwareExportSafetyModelFull(NO,seen,a,p);Localized(m);
        assert([m[@"guardKey"] isEqual:@"fwexport.guard.off"]&&[m[@"bannerKey"] isEqual:@"fwexport.banner.unguarded"]&&[m[@"level"] isEqual:@"danger"]&&[m[@"armed"] isEqual:@NO]&&![m[@"safe"] boolValue]);
    }
    for(NSString *k in @[@"fwexport.host.full",@"hub.status.firmwareExport.armed",@"hub.status.firmwareExport.disarmed"]){
        assert(![TIOTextForLanguage(k,TIOLangEnglish) isEqual:k]&&![TIOTextForLanguage(k,TIOLangChinese) isEqual:k]);
    }
    // The download-only model never carries an arm state.
    assert(!TIOFirmwareExportSafetyModel(@"ios1011-download",YES,YES,YES,off)[@"armed"]);
    NSLog(@"PASS: download-only safety: %zu hook target failures leave the guard off and the panel unsafe; guard row ok/warn/danger on stock traffic; Auto Update off/on/missing with worst key wins; read only; full 1.0.11 guard row shows the arm state",sizeof bad/sizeof *bad);
}return 0;}
