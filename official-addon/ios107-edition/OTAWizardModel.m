#import "OTAWizardModel.h"
#import "ExperimentalOTAFlash.h"
#import <CoreFoundation/CoreFoundation.h>

static BOOL IsAutoUpdateKey(id key) {
    return [key isKindOfClass:NSString.class] && [key hasSuffix:@"_ota_firmware_auto_update"];
}

NSUInteger TIOOTAAutoUpdateKeyCount(NSDictionary *prefs) {
    if (![prefs isKindOfClass:NSDictionary.class]) return 0;
    NSUInteger count = 0;
    for (id key in prefs) if (IsAutoUpdateKey(key)) count++;
    return count;
}

TIOAutoUpdateState TIOOTAAutoUpdateState(NSDictionary *prefs) {
    if (TIOOTAAutoUpdateDisabled(prefs)) return TIOAutoUpdateOff;
    return TIOOTAAutoUpdateKeyCount(prefs) ? TIOAutoUpdateOn : TIOAutoUpdateMissing;
}

BOOL TIOOTAAutoUpdateFixable(NSDictionary *prefs) {
    if (TIOOTAAutoUpdateState(prefs) != TIOAutoUpdateOn || TIOOTAAutoUpdateKeyCount(prefs) != 1) return NO;
    for (id key in prefs) {
        if (!IsAutoUpdateKey(key)) continue;
        id value = prefs[key];
        if ([value isKindOfClass:NSString.class]) return [value isEqualToString:@"true"] || [value isEqualToString:@"false"];
        return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
    }
    return NO;
}

static NSDictionary *Dictionary(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSNumber *Number(id value, NSNumber *fallback) { return [value isKindOfClass:NSNumber.class] ? value : fallback; }

NSDictionary *TIOOTAWizardSnapshot(NSDictionary *inputs) {
    NSDictionary *source = Dictionary(inputs);
    NSDictionary *flash = Dictionary(source[@"flash"]);
    NSDictionary *feed = Dictionary(source[@"feed"]);
    NSDictionary *guard = Dictionary(source[@"guard"]);
    NSDictionary *prefs = Dictionary(source[@"prefs"]);
    NSInteger stage = [flash[@"stage"] integerValue];
    BOOL flashBuild = [flash[@"flashBuild"] boolValue];
    TIOOTAPhase phase = !flashBuild ? TIOOTAPhaseUnavailable :
        stage == 0 ? TIOOTAPhaseReady :
        stage == 1 ? TIOOTAPhaseAuthorized :
        stage == 2 ? TIOOTAPhaseInstalling : TIOOTAPhaseFailed;

    TIOOTACheck package = source[@"packageOK"] == nil ? TIOOTACheckPending :
        [source[@"packageOK"] boolValue] ? TIOOTACheckOK : TIOOTACheckFail;
    BOOL eligible = [feed[@"bootstrapEligible"] boolValue];
    BOOL running = [feed[@"running"] boolValue];
    BOOL healthy = [feed[@"healthPassed"] boolValue];
    TIOOTACheck downloadSource = eligible && running ?
        (healthy ? TIOOTACheckOK : TIOOTACheckPending) : TIOOTACheckFail;
    TIOOTACheck protect = flashBuild && [guard[@"transportHookReady"] boolValue] ? TIOOTACheckOK : TIOOTACheckFail;
    TIOAutoUpdateState autoState = TIOOTAAutoUpdateState(prefs);
    TIOOTACheck autoUpdate = autoState == TIOAutoUpdateOff ? TIOOTACheckOK : TIOOTACheckAction;
    TIOOTACheck version = [flash[@"recentTargetVersionRead"] boolValue] ? TIOOTACheckOK : TIOOTACheckAction;
    TIOOTACheck directory = source[@"directoryOK"] == nil ? TIOOTACheckPending :
        [source[@"directoryOK"] boolValue] ? TIOOTACheckOK : TIOOTACheckFail;

    NSNumber *ageNumber = Number(flash[@"versionReadAge"], @(-1));
    double age = ageNumber.doubleValue;
    double secondsLeft = age < 0 ? 0 : MAX(0, 120 - age);
    BOOL canDownload = package == TIOOTACheckOK && downloadSource == TIOOTACheckOK &&
        protect == TIOOTACheckOK && stage == 0;
    BOOL canContinue = canDownload && autoUpdate == TIOOTACheckOK;
    // Full 1.0.11 host: flashing stays disarmed until the explicit arm step (TIOOTAFlashArm).
    BOOL armRequired = [flash[@"armRequired"] boolValue], armed = armRequired && [flash[@"armed"] boolValue];
    TIOOTACheck arm = !armRequired || armed ? TIOOTACheckOK : TIOOTACheckAction;
    BOOL canAuthorize = canContinue && version == TIOOTACheckOK && directory == TIOOTACheckOK && arm == TIOOTACheckOK && stage == 0;
    // On the full 1.0.11 host the stock firmware page offers an update only while the loopback feed serves one,
    // that is while the download window is open. A stock OTA folder left by an earlier 1.0.7 flash passes the
    // directory check but does not make the page offer anything, so step 2 is never skipped there.
    BOOL downloadRequired = armRequired;
    NSInteger suggestedStep = stage >= 1 ? 3 : !canContinue ? 1 : downloadRequired || directory != TIOOTACheckOK ? 2 : 3;
    return @{
        @"package": @(package), @"source": @(downloadSource), @"protect": @(protect),
        @"autoUpdate": @(autoUpdate), @"version": @(version), @"directory": @(directory),
        @"arm": @(arm), @"armRequired": @(armRequired), @"armed": @(armed), @"downloadRequired": @(downloadRequired),
        @"autoUpdateState": @(autoState), @"autoUpdateFixable": @(TIOOTAAutoUpdateFixable(prefs)),
        @"versionAge": ageNumber, @"versionSecondsLeft": @(secondsLeft),
        @"downloadArmed": @([feed[@"armed"] boolValue]),
        @"downloadSecondsLeft": Number(feed[@"remainingSeconds"], @0),
        @"phase": @(phase), @"stage": Number(flash[@"stage"], @0),
        @"validatedSlices": Number(flash[@"validatedSlices"], @0),
        @"failure": [flash[@"failure"] isKindOfClass:NSString.class] ? flash[@"failure"] : @"",
        @"canDownload": @(canDownload), @"canContinueFromCheck": @(canContinue),
        @"canAuthorize": @(canAuthorize), @"suggestedStep": @(suggestedStep)
    };
}

NSString *TIOOTAWizardHubStatusKey(NSDictionary *snapshot) {
    switch ([snapshot[@"phase"] integerValue]) {
        case TIOOTAPhaseUnavailable: return @"ota.hub.unavailable";
        case TIOOTAPhaseFailed: return @"ota.hub.failed";
        case TIOOTAPhaseInstalling: return @"ota.hub.installing";
        case TIOOTAPhaseAuthorized: return @"ota.hub.authorized";
        default:
            if ([snapshot[@"downloadArmed"] boolValue]) return @"ota.hub.download";
            return [snapshot[@"armRequired"] boolValue] && ![snapshot[@"armed"] boolValue] ? @"ota.hub.disarmed" : @"ota.hub.ready";
    }
}

NSDictionary *TIOOTAWizardDownloadButtons(NSDictionary *snapshot) {
    BOOL open = [snapshot[@"downloadArmed"] boolValue];
    BOOL directoryOK = [snapshot[@"directory"] integerValue] == TIOOTACheckOK;
    BOOL required = [snapshot[@"downloadRequired"] boolValue];
    NSMutableDictionary *buttons = [NSMutableDictionary dictionary];
    if (directoryOK && !required) {
        [buttons addEntriesFromDictionary:@{@"primary":@"ota.continue", @"primaryAction":@"continue", @"primaryEnabled":@YES}];
    } else if (open) {
        [buttons addEntriesFromDictionary:@{@"primary":@"common.goRayNeo", @"primaryAction":@"leave", @"primaryEnabled":@YES}];
    } else {
        [buttons addEntriesFromDictionary:@{@"primary":@"ota.download.open", @"primaryAction":@"open",
            @"primaryEnabled":@([snapshot[@"canDownload"] boolValue])}];
    }
    if (open) [buttons addEntriesFromDictionary:@{@"secondary":@"ota.download.stop", @"secondaryAction":@"stop", @"secondaryDestructive":@YES}];
    else if (required && directoryOK) [buttons addEntriesFromDictionary:@{@"secondary":@"ota.continue", @"secondaryAction":@"continue", @"secondaryDestructive":@NO}];
    return buttons;
}

NSString *TIOOTAFormatClock(NSInteger seconds) {
    NSInteger bounded = MAX(0, seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(bounded / 60), (long)(bounded % 60)];
}

NSArray<NSString *> *TIOOTAWizardFixtureNames(void) {
    return @[@"unavailable", @"missing-key", @"auto-on", @"ready-download", @"download-open",
             @"stale-version", @"ready-authorize", @"authorized", @"installing", @"failed", @"1011-directory"];
}

NSDictionary *TIOOTAWizardFixture(NSString *name) {
    if (![TIOOTAWizardFixtureNames() containsObject:name]) return @{};
    BOOL unavailable = [name isEqualToString:@"unavailable"];
    BOOL missingKey = [name isEqualToString:@"missing-key"];
    BOOL autoOn = [name isEqualToString:@"auto-on"];
    BOOL downloadOpen = [name isEqualToString:@"download-open"];
    BOOL staleVersion = [name isEqualToString:@"stale-version"];
    BOOL readyAuthorize = [name isEqualToString:@"ready-authorize"];
    BOOL authorized = [name isEqualToString:@"authorized"];
    BOOL installing = [name isEqualToString:@"installing"];
    BOOL failed = [name isEqualToString:@"failed"];
    // Full 1.0.11 host, disarmed, with a stock OTA folder from an earlier 1.0.7 flash already in the container.
    BOOL fullHostDirectory = [name isEqualToString:@"1011-directory"];
    NSInteger stage = authorized ? 1 : installing ? 2 : failed ? 3 : 0;
    BOOL directoryReady = staleVersion || readyAuthorize || fullHostDirectory || stage >= 1;
    BOOL recentVersion = readyAuthorize || stage >= 1;
    NSNumber *age = staleVersion ? @300 : recentVersion ? @30 : @(-1);
    NSDictionary *prefs = missingKey || unavailable ? @{} :
        @{@"flutter.fixture_ota_firmware_auto_update":autoOn ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse};
    NSDictionary *flash = @{@"flashBuild":@(!unavailable), @"stage":@(stage),
        @"recentTargetVersionRead":@(recentVersion), @"versionReadAge":age,
        @"validatedSlices":@(installing ? 120 : 0), @"failure":failed ? @"unexpected slice" : @"",
        @"armRequired":@(fullHostDirectory), @"armed":@NO};
    NSDictionary *feed = @{@"bootstrapEligible":@(!unavailable), @"running":@(!unavailable),
        @"healthPassed":@(!unavailable), @"armed":@(downloadOpen),
        @"remainingSeconds":@(downloadOpen ? 600 : 0)};
    NSMutableDictionary *fixture = [@{@"flash":flash, @"feed":feed,
        @"guard":@{@"transportHookReady":@(!unavailable)}, @"prefs":prefs,
        @"packageOK":@YES} mutableCopy];
    if (directoryReady) fixture[@"directoryOK"] = @YES;
    return fixture;
}
