#import "OTAWizardModel.h"
#import "ExperimentalOTAFlash.h"
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>

static NSDictionary *Changed(NSDictionary *base, NSString *section, NSString *key, id value) {
    NSMutableDictionary *inputs = [base mutableCopy];
    NSMutableDictionary *part = [inputs[section] mutableCopy];
    if (value) part[key] = value; else [part removeObjectForKey:key];
    inputs[section] = part;
    return inputs;
}

static void CheckFixtures(void) {
    NSArray<NSString *> *names = @[@"unavailable",@"missing-key",@"auto-on",@"ready-download",
        @"download-open",@"stale-version",@"ready-authorize",@"authorized",@"installing",@"failed"];
    NSArray<NSNumber *> *phases = @[@0,@1,@1,@1,@1,@1,@1,@2,@3,@4];
    NSArray<NSNumber *> *steps = @[@0,@1,@1,@2,@2,@3,@3,@3,@3,@3]; // 0 means no step assertion.
    NSArray<NSNumber *> *download = @[@NO,@YES,@YES,@YES,@YES,@YES,@YES,@NO,@NO,@NO];
    NSArray<NSNumber *> *continueFromCheck = @[@NO,@NO,@NO,@YES,@YES,@YES,@YES,@NO,@NO,@NO];
    NSArray<NSNumber *> *authorize = @[@NO,@NO,@NO,@NO,@NO,@NO,@YES,@NO,@NO,@NO];
    NSArray<NSString *> *hubKeys = @[@"ota.hub.unavailable",@"ota.hub.ready",@"ota.hub.ready",
        @"ota.hub.ready",@"ota.hub.download",@"ota.hub.ready",@"ota.hub.ready",
        @"ota.hub.authorized",@"ota.hub.installing",@"ota.hub.failed"];
    assert([TIOOTAWizardFixtureNames() isEqualToArray:names]);
    for (NSUInteger i = 0; i < names.count; i++) {
        NSDictionary *inputs = TIOOTAWizardFixture(names[i]);
        NSDictionary *snapshot = TIOOTAWizardSnapshot(inputs);
        assert([snapshot[@"phase"] isEqual:phases[i]]);
        if ([steps[i] integerValue]) assert([snapshot[@"suggestedStep"] isEqual:steps[i]]);
        assert([snapshot[@"canDownload"] isEqual:download[i]]);
        assert([snapshot[@"canContinueFromCheck"] isEqual:continueFromCheck[i]]);
        assert([snapshot[@"canAuthorize"] isEqual:authorize[i]]);
        assert([TIOOTAWizardHubStatusKey(snapshot) isEqualToString:hubKeys[i]]);
        assert([snapshot[@"stage"] isEqual:inputs[@"flash"][@"stage"]]);
        assert([snapshot[@"validatedSlices"] isEqual:inputs[@"flash"][@"validatedSlices"]]);
        assert([snapshot[@"failure"] isEqual:inputs[@"flash"][@"failure"]]);
    }
    assert(![TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"missing-key"))[@"autoUpdateFixable"] boolValue]);
    assert([TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"auto-on"))[@"autoUpdateFixable"] boolValue]);
    NSDictionary *open = TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"download-open"));
    assert([open[@"downloadArmed"] boolValue] && [open[@"downloadSecondsLeft"] integerValue] == 600);
    NSDictionary *stale = TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"stale-version"));
    assert([stale[@"version"] integerValue] == TIOOTACheckAction);
    assert([stale[@"versionSecondsLeft"] integerValue] == 0);
    NSDictionary *ready = TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"ready-authorize"));
    assert([ready[@"versionAge"] integerValue] == 30 && [ready[@"versionSecondsLeft"] integerValue] == 90);
    assert([TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"installing"))[@"validatedSlices"] integerValue] == 120);
    assert([TIOOTAWizardSnapshot(TIOOTAWizardFixture(@"failed"))[@"failure"] isEqualToString:@"unexpected slice"]);
    assert(TIOOTAWizardFixture(@"no-such-fixture").count == 0);
}

static void CheckAutoUpdate(void) {
    NSString *key = @"flutter.fixture_ota_firmware_auto_update";
    NSString *other = @"flutter.other_ota_firmware_auto_update";
    NSArray<NSDictionary *> *cases = @[@{}, @{key:@"true"}, @{key:@"false"},
        @{key:(__bridge id)kCFBooleanTrue}, @{key:(__bridge id)kCFBooleanFalse},
        @{key:@0}, @{key:@1}, @{key:@"false",other:@"false"},
        @{key:@"false",other:@"true"}, @{@"unrelated":@"true"}];
    NSArray<NSNumber *> *expectedStates = @[@0,@1,@2,@1,@2,@1,@1,@2,@1,@0];
    NSArray<NSNumber *> *expectedCounts = @[@0,@1,@1,@1,@1,@1,@1,@2,@2,@0];
    for (NSUInteger i = 0; i < cases.count; i++) {
        NSDictionary *prefs = cases[i];
        TIOAutoUpdateState state = TIOOTAAutoUpdateState(prefs);
        assert(state == [expectedStates[i] integerValue]);
        assert(TIOOTAAutoUpdateKeyCount(prefs) == [expectedCounts[i] unsignedIntegerValue]);
        assert((state == TIOAutoUpdateOff) == TIOOTAAutoUpdateDisabled(prefs));
        assert(TIOOTAAutoUpdateFixable(prefs) == (i == 1 || i == 3));
    }
    assert(CFGetTypeID((__bridge CFTypeRef)@0) != CFBooleanGetTypeID());
    assert(CFGetTypeID((__bridge CFTypeRef)@1) != CFBooleanGetTypeID());
}

static void CheckGateMismatchesAndBoundaries(void) {
    NSDictionary *base = TIOOTAWizardFixture(@"ready-authorize");
    NSDictionary *snapshot = TIOOTAWizardSnapshot(Changed(base, @"flash", @"versionReadAge", @120));
    assert([snapshot[@"version"] integerValue] == TIOOTACheckOK);
    assert([snapshot[@"versionSecondsLeft"] integerValue] == 0);
    NSDictionary *stale = Changed(Changed(base, @"flash", @"versionReadAge", @121),
        @"flash", @"recentTargetVersionRead", @NO);
    snapshot = TIOOTAWizardSnapshot(stale);
    assert([snapshot[@"version"] integerValue] == TIOOTACheckAction);
    assert(![snapshot[@"canAuthorize"] boolValue]);
    snapshot = TIOOTAWizardSnapshot(Changed(base, @"flash", @"versionReadAge", nil));
    assert([snapshot[@"versionAge"] integerValue] == -1 && [snapshot[@"versionSecondsLeft"] integerValue] == 0);

    // The preference snapshot wins over a stale summary bit in flash status.
    NSMutableDictionary *missing = [TIOOTAWizardFixture(@"missing-key") mutableCopy];
    missing[@"flash"] = Changed(@{@"flash":missing[@"flash"]}, @"flash", @"automaticUpdateDisabled", @YES)[@"flash"];
    snapshot = TIOOTAWizardSnapshot(missing);
    assert([snapshot[@"autoUpdate"] integerValue] == TIOOTACheckAction);
    assert(![snapshot[@"canAuthorize"] boolValue]);

    snapshot = TIOOTAWizardSnapshot(Changed(base, @"feed", @"healthPassed", @NO));
    assert([snapshot[@"source"] integerValue] == TIOOTACheckPending && ![snapshot[@"canDownload"] boolValue]);
    snapshot = TIOOTAWizardSnapshot(Changed(base, @"feed", @"running", @NO));
    assert([snapshot[@"source"] integerValue] == TIOOTACheckFail && ![snapshot[@"canDownload"] boolValue]);
    snapshot = TIOOTAWizardSnapshot(Changed(base, @"guard", @"transportHookReady", @NO));
    assert([snapshot[@"protect"] integerValue] == TIOOTACheckFail && ![snapshot[@"canDownload"] boolValue]);
    NSMutableDictionary *inputs = [base mutableCopy];
    inputs[@"packageOK"] = @NO;
    snapshot = TIOOTAWizardSnapshot(inputs);
    assert([snapshot[@"package"] integerValue] == TIOOTACheckFail && ![snapshot[@"canDownload"] boolValue]);
    [inputs removeObjectForKey:@"packageOK"];
    snapshot = TIOOTAWizardSnapshot(inputs);
    assert([snapshot[@"package"] integerValue] == TIOOTACheckPending && ![snapshot[@"canDownload"] boolValue]);
    inputs = [base mutableCopy];
    inputs[@"directoryOK"] = @NO;
    snapshot = TIOOTAWizardSnapshot(inputs);
    assert([snapshot[@"directory"] integerValue] == TIOOTACheckFail && ![snapshot[@"canAuthorize"] boolValue]);
    [inputs removeObjectForKey:@"directoryOK"];
    snapshot = TIOOTAWizardSnapshot(inputs);
    assert([snapshot[@"directory"] integerValue] == TIOOTACheckPending && [snapshot[@"suggestedStep"] integerValue] == 2);
    for (NSInteger stage = 1; stage <= 3; stage++) {
        snapshot = TIOOTAWizardSnapshot(Changed(base, @"flash", @"stage", @(stage)));
        assert(![snapshot[@"canDownload"] boolValue] && ![snapshot[@"canAuthorize"] boolValue]);
        assert([snapshot[@"suggestedStep"] integerValue] == 3);
    }
}

int main(void) {
    @autoreleasepool {
        CheckFixtures();
        CheckAutoUpdate();
        CheckGateMismatchesAndBoundaries();
        assert([TIOOTAFormatClock(872) isEqualToString:@"14:32"]);
        assert([TIOOTAFormatClock(-5) isEqualToString:@"0:00"]);
        assert([TIOOTAFormatClock(60) isEqualToString:@"1:00"]);
        NSLog(@"PASS: OTA wizard fixtures, auto-update gate consistency, and boundaries");
    }
    return 0;
}
