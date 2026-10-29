#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "MapKitNavigationUI.h"
#import "NavigationGuidance.h"
#import "TIOLanguage.h"

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

// ---- Navigation: the real TIOMapKitNavigationPanel with a stub route ----
// MKRoute has no public initialiser, so a subclass supplies the canned numbers that the
// panel reads. Nothing here plans a route, starts location or contacts the glasses.
@interface TIOPreviewRoute : MKRoute
@property(nonatomic,strong) MKPolyline *stubLine;
@end
@implementation TIOPreviewRoute
- (MKPolyline *)polyline {return self.stubLine;}
- (NSTimeInterval)expectedTravelTime {return 14*60;}
- (CLLocationDistance)distance {return 1900;}
- (NSArray<MKRouteStep *> *)steps {return @[];}
@end

static void StubSet(id object,NSString *key,id value) {[object setValue:value forKey:key];}

// state: @"ready" (route planned, not started) or @"active" (navigating, End shown).
UIViewController *TIOPreviewNavigationController(NSString *state) {
    UIViewController *panel=TIOMapKitNavigationController();
    [panel loadViewIfNeeded];
    static const double pts[][2]={{37.7955,-122.3937},{37.7990,-122.3996},{37.8008,-122.4040},{37.8024,-122.4058}};
    NSMutableArray *stepPoints=[NSMutableArray array];
    CLLocationCoordinate2D coords[4];
    for (int i=0;i<4;i++) {coords[i]=CLLocationCoordinate2DMake(pts[i][0],pts[i][1]);}
    NSArray *instructions=@[@"Head northwest on The Embarcadero",@"Turn left onto Battery Street",@"Turn right onto Filbert Street",@"Arrive at Coit Tower"];
    for (int i=0;i<3;i++) {
        [stepPoints addObject:[TIOGuideStep stepWithPoints:@[@[@(pts[i][0]),@(pts[i][1])],@[@(pts[i+1][0]),@(pts[i+1][1])]] instructions:instructions[i]]];
    }
    [stepPoints addObject:[TIOGuideStep stepWithPoints:@[@[@(pts[3][0]),@(pts[3][1])],@[@(pts[3][0]),@(pts[3][1])]] instructions:instructions[3]]];
    TIOGuideRoute *guide=[TIOGuideRoute routeWithSteps:stepPoints expectedSeconds:14*60];
    TIOPreviewRoute *route=[TIOPreviewRoute new];
    route.stubLine=[MKPolyline polylineWithCoordinates:coords count:4];
    MKMapItem *destination=[[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:coords[3]]];
    StubSet(panel,@"destination",destination);StubSet(panel,@"destinationName",@"Coit Tower");
    StubSet(panel,@"route",route);StubSet(panel,@"guide",guide);StubSet(panel,@"note",nil);
    // Live source (the default is Simulate, which hides the Apple Maps hand-off); the board shows both buttons.
    ((UISegmentedControl *)[panel valueForKey:@"sourceControl"]).selectedSegmentIndex=1;
    UISearchBar *search=[panel valueForKey:@"search"];search.text=@"Coit Tower";
    MKMapView *map=[panel valueForKey:@"map"];
    MKPointAnnotation *pin=[MKPointAnnotation new];pin.coordinate=coords[3];pin.title=@"Coit Tower";[map addAnnotation:pin];StubSet(panel,@"destinationPin",pin);
    [map addOverlay:route.stubLine level:MKOverlayLevelAboveRoads];StubSet(panel,@"line",route.stubLine);
    if ([state isEqual:@"active"]) {
        // Live-style navigation: the simulation clock is not running, so the shot is deterministic and the
        // map is not followed. The glasses attempt is already spent (glassesTried), so the panel's
        // timer never starts a glasses session; the simulator has no location fix to feed updates.
        StubSet(panel,@"navigating",@YES);StubSet(panel,@"simulated",@NO);StubSet(panel,@"glassesTried",@YES);
        StubSet(panel,@"display",@{@"turn":@"Turn left",@"icon":@(TIOGuideIconLeft),@"meters":@120,@"road":@"Battery Street",@"remainingSeconds":@(11*60),@"remainingMeters":@1500,
            @"tnrPassing":[TIOText(@"nav.passing") stringByReplacingOccurrencesOfString:@"%@" withString:@"The Embarcadero"],@"tnrLocation":@[@(pts[1][0]),@(pts[1][1])]});
    }
    SEL refresh=NSSelectorFromString(@"refresh");
    if ([panel respondsToSelector:refresh]) ((void(*)(id,SEL))objc_msgSend)(panel,refresh);
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:panel];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [map setVisibleMapRect:route.stubLine.boundingMapRect edgePadding:UIEdgeInsetsMake(200,40,300,40) animated:NO];
    });
    return navigation;
}

// What the report records about the panel, read by key so a renamed property reports NO rather than crashing.
NSDictionary *TIOPreviewNavigationFacts(UIViewController *panel) {
    if (![NSStringFromClass(panel.class) isEqual:@"TIOMapKitNavigationPanel"]) return @{};
    BOOL (^hidden)(NSString *)=^BOOL(NSString *key){
        @try {UIView *view=[panel valueForKey:key];return !view||view.hidden;} @catch (NSException *e) {return YES;}
    };
    NSString *(^text)(NSString *)=^NSString *(NSString *key){
        @try {return [[panel valueForKey:key] text]?:@"";} @catch (NSException *e) {return @"";}
    };
    BOOL navigating=NO,hasGuide=NO;
    @try {navigating=[[panel valueForKey:@"navigating"] boolValue];hasGuide=[panel valueForKey:@"guide"]!=nil;} @catch (NSException *e) {}
    return @{@"navigating":@(navigating),@"routeLoaded":@(hasGuide),@"title":text(@"titleLabel"),@"metrics":text(@"metricsLabel"),
             @"startVisible":@(!hidden(@"startButton")),@"endVisible":@(!hidden(@"stopButton")),@"appleMapsVisible":@(!hidden(@"appleMapsButton"))};
}

// ---- Captions: the real Apple captions panel (Swift) with canned state ----
// preview/build.sh compiles TurboAppleAI.dylib for the simulator with -DTIO_UI_PREVIEW, which adds
// +makePreviewController:. fixture: @"listening" (default) or @"idle".
UIViewController *TIOPreviewCaptionsController(NSString *fixture) {
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TurboAppleAI.dylib"];
    if (!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)) return nil;
    // The host tells the module the UI language the same way (AppleAI.m); without it the panel stays English.
    Class probe=NSClassFromString(@"TIOAppleAIProbe");SEL language=NSSelectorFromString(@"setUILanguage:");
    if ([probe respondsToSelector:language]) ((void(*)(id,SEL,id))objc_msgSend)(probe,language,TIOUILanguage());
    Class panel=NSClassFromString(@"TIOAppleCaptionPanel");
    SEL make=NSSelectorFromString(@"makePreviewController:");
    if (![panel respondsToSelector:make]) return nil;
    id page=((id(*)(id,SEL,id))objc_msgSend)(panel,make,fixture?:@"listening");
    if (![page isKindOfClass:UIViewController.class]) return nil;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:page];
    navigation.navigationBar.prefersLargeTitles=YES; // the hub shell does the same
    return navigation;
}
#endif
