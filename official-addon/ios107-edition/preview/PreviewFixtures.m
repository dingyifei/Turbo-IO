#import <Foundation/Foundation.h>

#if TIO_UI_PREVIEW
// Canned data only: WP5 supplies UI injection. These fixtures never open grants.
NSDictionary *TIOPreviewOTAFixture(NSString *state) {
    NSArray *states = @[@"locked", @"autoUpdateUnknown", @"versionStale",
                        @"downloadReady", @"authorized", @"started"];
    if (![states containsObject:state]) return nil;
    BOOL locked = [state isEqual:@"locked"];
    BOOL unknownAutoUpdate = [state isEqual:@"autoUpdateUnknown"];
    BOOL staleVersion = [state isEqual:@"versionStale"];
    BOOL started = [state isEqual:@"started"];
    BOOL authorized = started || [state isEqual:@"authorized"];
    BOOL available = !locked;
    BOOL automaticUpdateDisabled = available && !unknownAutoUpdate;
    BOOL recentTargetVersionRead = available && !staleVersion;
    NSUInteger stage = started ? 2 : (authorized ? 1 : 0);
    return @{
        @"flash": @{
            @"stage": @(stage),
            @"authorized": @(authorized),
            @"started": @(started),
            @"versionMatched": @(started),
            @"manifestMatched": @(started),
            @"validatedSlices": @(started ? 1 : 0),
            @"validatedSliceBytes": @(started ? 51200 : 0),
            @"failure": @"",
            @"runtimeValidated": @NO,
            @"flashBuild": @YES,
            @"automaticUpdateDisabled": @(automaticUpdateDisabled),
            @"recentTargetVersionRead": @(recentTargetVersionRead)
        },
        @"feed": @{
            @"running": @(available),
            @"port": @(available ? 18794 : 0),
            @"armed": @(available),
            @"remainingSeconds": @(available ? 900 : 0),
            @"queryCount": @0,
            @"firmwareQueries": @0,
            @"appQueries": @0,
            @"unknownQueries": @0,
            @"downloadRequests": @0,
            @"rejectedCount": @0,
            @"armingCompiledIn": @YES,
            @"runtimeValidated": @NO,
            @"bootstrapEligible": @(available),
            @"startAttempts": @(available ? 1 : 0),
            @"startErrorCode": @0,
            @"reason": @"",
            @"launchID": @"preview-fixture",
            @"processIdentifier": @0,
            @"healthPassed": @(available),
            @"healthCheckedAt": @(available ? 1 : 0)
        },
        @"guard": @{
            @"preparationBuild": @NO,
            @"transportHookReady": @(available),
            @"blockedCalls": @0,
            @"versionReadCalls": @(recentTargetVersionRead ? 1 : 0),
            @"releaseSupported": @NO
        }
    };
}
#endif
