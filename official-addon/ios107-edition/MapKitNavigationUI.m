#import "MapKitNavigationUI.h"
#import "NavigationGuidance.h"
#import "NavigationSubtitleHUD.h"
#import "ResearchUI.h"
#import "RoadMap.h"
#import "DisplayPhoneUI.h"
#import "NativeNavigation.h"
#import "NativeNavigationUI.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#include <math.h>
// MKPlacemark is deprecated on newer SDKs but is the iOS 16 way to build a map item.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const RoadsKey=@"TurboMapKitNearbyRoadsV3"; // V3: route corridor saved on the phone for dead zones; asks again
enum {ModeWalk=0,ModeCycle=1,ModeDrive=2};
static double SimSpeed(NSInteger mode){return mode==ModeDrive?11:mode==ModeCycle?4.5:1.4;}
static MKDirectionsTransportType Transport(NSInteger mode){return mode==ModeDrive?MKDirectionsTransportTypeAutomobile:mode==ModeCycle?MKDirectionsTransportTypeCycling:MKDirectionsTransportTypeWalking;}
static NSString *Meters(double m){if(!isfinite(m)||m<0)return @"—";if(m>=1000)return [NSString stringWithFormat:@"%.1f km",m/1000];long r=m<50?lround(m):lround(m/10)*10;return [NSString stringWithFormat:@"%ld m",r];}
static NSString *Minutes(double s){if(!isfinite(s)||s<0)return @"—";long m=MAX(1,lround(ceil(s/60)));return m>=60?[NSString stringWithFormat:@"%ld h %ld min",m/60,m%60]:[NSString stringWithFormat:@"%ld min",m];}
static NSString *Clock(double s){if(!isfinite(s)||s<0)return @"—";NSDateFormatter *f=[NSDateFormatter new];f.timeStyle=NSDateFormatterShortStyle;f.dateStyle=NSDateFormatterNoStyle;return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:s]];}
// The 1.0.7 host declares the location background mode; check rather than assume, since
// enabling background updates without it raises an exception.
static BOOL BackgroundLocation(void){id m=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"];return [m isKindOfClass:NSArray.class]&&[m containsObject:@"location"];}
static NSString *AppState(void){switch(UIApplication.sharedApplication.applicationState){case UIApplicationStateActive:return @"active";case UIApplicationStateInactive:return @"inactive";default:return @"background";}}
static NSString *GlassesBusy(void){
    if(![TIOSubtitleNavigationStatus()[@"phase"] isEqual:@"idle"])return @"Caption navigation is still running.";
    return nil;
}
static NSArray *Coordinates(MKPolyline *line){
    NSUInteger n=line.pointCount;if(!n||n>200000)return @[];CLLocationCoordinate2D *c=calloc(n,sizeof *c);if(!c)return @[];
    [line getCoordinates:c range:NSMakeRange(0,n)];NSMutableArray *out=[NSMutableArray arrayWithCapacity:n];
    for(NSUInteger i=0;i<n;i++)[out addObject:@[@(c[i].latitude),@(c[i].longitude)]];free(c);return out;
}
static TIOGuideRoute *GuideRoute(MKRoute *route){
    NSMutableArray *steps=[NSMutableArray new];
    for(MKRouteStep *s in route.steps){NSArray *points=Coordinates(s.polyline);if(points.count)[steps addObject:[TIOGuideStep stepWithPoints:points instructions:s.instructions]];}
    return [TIOGuideRoute routeWithSteps:steps expectedSeconds:route.expectedTravelTime];
}

@interface TIOMapKitNavigationPanel:UIViewController<MKMapViewDelegate,CLLocationManagerDelegate,UISearchBarDelegate,MKLocalSearchCompleterDelegate,UITableViewDataSource,UITableViewDelegate>
@property MKMapView *map;
@property UISearchBar *search;
@property UITableView *results;
@property MKLocalSearchCompleter *completer;
@property UISegmentedControl *modeControl,*sourceControl;
@property UILabel *titleLabel,*detailLabel,*metricsLabel,*glassesLabel;
@property UIButton *startButton,*stopButton,*appleMapsButton;
@property CLLocationManager *locator;
@property CLLocation *fix;
@property MKMapItem *destination;
@property NSString *destinationName;
@property CLLocationCoordinate2D simStart;
@property BOOL hasSimStart,pickingStart;
@property MKRoute *route;
@property TIOGuideRoute *guide;
@property MKPolyline *line;
@property MKPointAnnotation *destinationPin,*startPin,*simMarker;
@property BOOL planning,navigating,simulated,rerouting,weak,arrived,simPaused,glassesStarted,glassesTried;
@property NSUInteger generation;
@property NSInteger mode,snapStep;
@property TIOGuideRerouteState reroute;
@property NSTimeInterval simElapsed,simLastTick,lastOffer,firstFrameAt,weakSince,lastUI,lastFollow;
@property NSDictionary *display;
@property TIORoadMap *roadMap;
@property NSTimer *timer;
@property BOOL idleBefore,inBackground,openMapsPending;
@property NSTimeInterval openMapsAt,lastTrace,lastTraceSave,lastLabel;
@property NSUInteger offers,fixes;
@property NSMutableArray *trace;
@property NSString *note;
@end

@implementation TIOMapKitNavigationPanel
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight{UILabel *l=[UILabel new];l.numberOfLines=0;l.font=[UIFont systemFontOfSize:size weight:weight];l.adjustsFontForContentSizeCategory=YES;return l;}
- (UIButton *)action:(NSString *)title icon:(NSString *)icon selector:(SEL)sel primary:(BOOL)primary{
    UIButtonConfiguration *c=primary?[UIButtonConfiguration filledButtonConfiguration]:[UIButtonConfiguration tintedButtonConfiguration];c.title=title;c.image=[UIImage systemImageNamed:icon];c.imagePadding=6;c.baseBackgroundColor=primary?TIOAccent():nil;
    UIButton *b=[UIButton buttonWithConfiguration:c primaryAction:nil];[b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];return b;
}
- (UIStackView *)card{
    UIStackView *s=[UIStackView new];s.axis=UILayoutConstraintAxisVertical;s.spacing=8;s.layoutMargins=UIEdgeInsetsMake(12,14,12,14);s.layoutMarginsRelativeArrangement=YES;s.translatesAutoresizingMaskIntoConstraints=NO;
    s.backgroundColor=[TIOPaper() colorWithAlphaComponent:.97];s.layer.cornerRadius=20;s.layer.shadowColor=UIColor.blackColor.CGColor;s.layer.shadowOpacity=.12;s.layer.shadowRadius=14;s.layer.shadowOffset=CGSizeMake(0,4);return s;
}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Navigation";self.view.backgroundColor=TIOPaper();self.view.tintColor=TIOAccent();
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(more)];
    self.roadMap=[[TIORoadMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){return @[@(lat),@(lon)];}];
    self.roadMap.enabled=[NSUserDefaults.standardUserDefaults boolForKey:RoadsKey];self.reroute=TIOGuideRerouteInitial();
    self.map=[MKMapView new];self.map.delegate=self;self.map.translatesAutoresizingMaskIntoConstraints=NO;self.map.showsCompass=YES;[self.view addSubview:self.map];
    [self.map addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPress:)]];
    UIStackView *top=[self card];self.search=[UISearchBar new];self.search.placeholder=@"Where to?";self.search.delegate=self;self.search.searchBarStyle=UISearchBarStyleMinimal;[top addArrangedSubview:self.search];
    self.modeControl=[[UISegmentedControl alloc]initWithItems:@[@"Walk",@"Cycle",@"Drive"]];self.modeControl.selectedSegmentIndex=ModeWalk;[self.modeControl addTarget:self action:@selector(optionsChanged) forControlEvents:UIControlEventValueChanged];[top addArrangedSubview:self.modeControl];
    self.sourceControl=[[UISegmentedControl alloc]initWithItems:@[@"Simulate",@"Live"]];self.sourceControl.selectedSegmentIndex=0;[self.sourceControl addTarget:self action:@selector(optionsChanged) forControlEvents:UIControlEventValueChanged];[top addArrangedSubview:self.sourceControl];
    [self.view addSubview:top];
    self.results=[UITableView new];self.results.translatesAutoresizingMaskIntoConstraints=NO;self.results.dataSource=self;self.results.delegate=self;self.results.layer.cornerRadius=16;self.results.hidden=YES;[self.view addSubview:self.results];
    self.completer=[MKLocalSearchCompleter new];self.completer.delegate=self;self.completer.resultTypes=MKLocalSearchCompleterResultTypeAddress|MKLocalSearchCompleterResultTypePointOfInterest;
    UIStackView *bottom=[self card];self.titleLabel=[self label:20 weight:UIFontWeightSemibold];self.detailLabel=[self label:14 weight:UIFontWeightRegular];self.detailLabel.textColor=UIColor.secondaryLabelColor;
    self.metricsLabel=[self label:15 weight:UIFontWeightMedium];self.metricsLabel.font=[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];self.glassesLabel=[self label:12 weight:UIFontWeightRegular];self.glassesLabel.textColor=UIColor.secondaryLabelColor;
    for(UIView *v in @[self.titleLabel,self.detailLabel,self.metricsLabel])[bottom addArrangedSubview:v];
    UIStackView *buttons=[UIStackView new];buttons.spacing=10;buttons.distribution=UIStackViewDistributionFillEqually;
    self.startButton=[self action:@"Start" icon:@"location.north.fill" selector:@selector(start) primary:YES];self.stopButton=[self action:@"End" icon:@"stop.fill" selector:@selector(stopTapped) primary:NO];
    self.appleMapsButton=[self action:@"Apple Maps" icon:@"map" selector:@selector(appleMapsTapped) primary:NO];
    [buttons addArrangedSubview:self.startButton];[buttons addArrangedSubview:self.appleMapsButton];[buttons addArrangedSubview:self.stopButton];[bottom addArrangedSubview:buttons];[bottom addArrangedSubview:self.glassesLabel];[self.view addSubview:bottom];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.map.topAnchor constraintEqualToAnchor:self.view.topAnchor],[self.map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [top.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[top.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[top.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.results.leadingAnchor constraintEqualToAnchor:top.leadingAnchor],[self.results.trailingAnchor constraintEqualToAnchor:top.trailingAnchor],[self.results.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:6],[self.results.heightAnchor constraintEqualToConstant:280],
        [bottom.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[bottom.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[bottom.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8]]];
    self.locator=[CLLocationManager new];self.locator.delegate=self;self.locator.desiredAccuracy=kCLLocationAccuracyBest;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(researchClosed) name:@"TIOResearchClosed" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(enterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    self.note=@"Search for a destination, or long-press the map.";[self refresh];
}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if(!self.timer){__weak typeof(self) weak=self;self.timer=[NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){[weak tick];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];}
    [self startLocating];
}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    // A presented alert or the lock screen does not end navigation; leaving the panel does.
    if(!self.isMovingFromParentViewController&&!self.isBeingDismissed&&!self.navigationController.isBeingDismissed)return;
    TNVLifecycle(@"mapkit-panel-closed");[self stopNavigation:nil];[self.roadMap forgetSavedRoads];[self.timer invalidate];self.timer=nil;[self.locator stopUpdatingLocation];
}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)researchClosed{[self stopNavigation:@"Navigation ended."];}
- (void)alert:(NSString *)title message:(NSString *)message{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}

#pragma mark Location
- (void)startLocating{
    CLAuthorizationStatus s=self.locator.authorizationStatus;
    if(s==kCLAuthorizationStatusNotDetermined){[self.locator requestWhenInUseAuthorization];return;}
    if(s==kCLAuthorizationStatusAuthorizedWhenInUse||s==kCLAuthorizationStatusAuthorizedAlways){self.map.showsUserLocation=YES;[self.locator startUpdatingLocation];}
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager{
    CLAuthorizationStatus s=manager.authorizationStatus;BOOL ok=s==kCLAuthorizationStatusAuthorizedWhenInUse||s==kCLAuthorizationStatusAuthorizedAlways;
    if(ok)[self startLocating];else if(s!=kCLAuthorizationStatusNotDetermined){self.map.showsUserLocation=NO;if(self.navigating&&!self.simulated)[self stopNavigation:@"Location access was turned off."];}
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    CLLocation *l=locations.lastObject;if(!l||l.horizontalAccuracy<0||fabs(l.timestamp.timeIntervalSinceNow)>4)return;
    BOOL centerFirst=!self.fix;self.fix=l;
    if(centerFirst&&!self.destination)[self.map setRegion:MKCoordinateRegionMakeWithDistance(l.coordinate,1200,1200) animated:YES];
    if(centerFirst&&self.destination&&!self.guide&&!self.planning&&!self.navigating)[self plan]; // destination chosen before the first fix
    if(!self.navigating||self.simulated||self.arrived)return;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(l.horizontalAccuracy>50){if(!self.weakSince)self.weakSince=now;if(now-self.weakSince>5&&!self.weak){self.weak=YES;self.note=@"Weak GPS signal. Guidance resumes when the signal improves.";[self refresh];}}
    else{self.weakSince=0;if(self.weak){self.weak=NO;self.note=nil;}}
    if(self.weak||l.horizontalAccuracy>80)return;
    self.fixes++;[self updateAt:l.coordinate.latitude lon:l.coordinate.longitude course:l.course speed:l.speed now:now];
    TDPPhoneNavigationPump(); // timers may be coalesced in the background; fixes keep the glasses fed
}

#pragma mark Destination
- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)c{self.results.hidden=!c.results.count||!self.search.isFirstResponder;[self.results reloadData];}
- (void)completer:(MKLocalSearchCompleter *)c didFailWithError:(NSError *)error{self.results.hidden=YES;}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text{if(!text.length){self.results.hidden=YES;return;}self.completer.region=self.map.region;self.completer.queryFragment=text;}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar{MKLocalSearchRequest *r=[MKLocalSearchRequest new];r.naturalLanguageQuery=bar.text;r.region=self.map.region;[self runSearch:r];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return MIN(self.completer.results.count,(NSUInteger)8);}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
    UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"r"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"r"];
    MKLocalSearchCompletion *r=self.completer.results[p.row];c.textLabel.text=r.title;c.detailTextLabel.text=r.subtitle;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.row>=(NSInteger)self.completer.results.count)return;[self runSearch:[[MKLocalSearchRequest alloc]initWithCompletion:self.completer.results[p.row]]];}
- (void)runSearch:(MKLocalSearchRequest *)request{
    [self.search resignFirstResponder];self.results.hidden=YES;if(self.navigating){[self alert:@"End navigation first" message:@"End the current route before choosing a new destination."];return;}
    [[[MKLocalSearch alloc]initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error){
        MKMapItem *item=response.mapItems.firstObject;if(!item){[self alert:@"No results" message:@"Try a different search, or long-press the map to drop a pin."];return;}
        [self setDestination:item name:item.name?:@"Destination"];
    }];
}
- (void)longPress:(UILongPressGestureRecognizer *)g{
    if(g.state!=UIGestureRecognizerStateBegan||self.navigating)return;
    CLLocationCoordinate2D c=[self.map convertPoint:[g locationInView:self.map] toCoordinateFromView:self.map];
    if(self.pickingStart){self.pickingStart=NO;self.simStart=c;self.hasSimStart=YES;self.sourceControl.selectedSegmentIndex=0;
        if(self.startPin)[self.map removeAnnotation:self.startPin];self.startPin=[MKPointAnnotation new];self.startPin.coordinate=c;self.startPin.title=@"Simulation start";[self.map addAnnotation:self.startPin];
        if(self.destination)[self plan];else{self.note=@"Start set. Now choose a destination.";[self refresh];}return;}
    [self setDestination:[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:c]] name:@"Dropped pin"];
}
- (void)setDestination:(MKMapItem *)item name:(NSString *)name{
    self.destination=item;self.destinationName=name;self.search.text=name;
    if(self.destinationPin)[self.map removeAnnotation:self.destinationPin];self.destinationPin=[MKPointAnnotation new];self.destinationPin.coordinate=item.placemark.coordinate;self.destinationPin.title=name;[self.map addAnnotation:self.destinationPin];
    [self plan];
}
- (void)optionsChanged{
    if(self.navigating){self.modeControl.selectedSegmentIndex=self.mode;self.sourceControl.selectedSegmentIndex=self.simulated?0:1;[self alert:@"End navigation first" message:@"Options can be changed after the current route ends."];return;}
    if(self.destination)[self plan];else[self refresh];
}

#pragma mark Routing
- (CLLocationCoordinate2D)originForSimulation:(BOOL)sim valid:(BOOL *)valid{
    if(sim&&self.hasSimStart){*valid=YES;return self.simStart;}
    *valid=self.fix&&fabs(self.fix.timestamp.timeIntervalSinceNow)<120;return self.fix.coordinate;
}
- (void)plan{
    BOOL sim=self.sourceControl.selectedSegmentIndex==0,valid=NO;CLLocationCoordinate2D from=[self originForSimulation:sim valid:&valid];
    if(!valid){self.note=sim?@"Waiting for your location. Or use ⋯ › Set simulation start, then long-press the map.":@"Waiting for your location. Allow location access for live navigation.";[self refresh];return;}
    [self calculateFrom:from reroute:NO];
}
- (void)calculateFrom:(CLLocationCoordinate2D)from reroute:(BOOL)reroute{
    if(!self.destination)return;NSUInteger g=++self.generation;self.planning=!reroute;if(!reroute){self.route=nil;self.guide=nil;}
    MKDirectionsRequest *r=[MKDirectionsRequest new];r.source=[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:from]];r.destination=self.destination;
    r.transportType=Transport(reroute?self.mode:self.modeControl.selectedSegmentIndex);r.requestsAlternateRoutes=NO;
    if(!reroute){self.note=@"Finding a route…";[self refresh];}
    [[[MKDirections alloc]initWithRequest:r] calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response,NSError *error){
        if(g!=self.generation)return;MKRoute *route=response.routes.firstObject;TIOGuideRoute *guide=route?GuideRoute(route):nil;
        if(!guide){self.planning=NO;self.rerouting=NO;self.note=reroute?@"Couldn't find a new route. Keep following the old one or end navigation.":[NSString stringWithFormat:@"No route found%@.",error.localizedDescription.length?[@": " stringByAppendingString:error.localizedDescription]:@""];[self refresh];return;}
        self.route=route;self.guide=guide;self.planning=NO;self.snapStep=0;
        // Save the street map along the whole route now (often still on Wi-Fi); a reroute adds its new corridor.
        if([NSUserDefaults.standardUserDefaults boolForKey:RoadsKey]){self.roadMap.allowNetwork=YES;if(!reroute&&!self.navigating)[self.roadMap forgetSavedRoads];[self.roadMap prefetchRoute:guide.points];}
        if(self.line)[self.map removeOverlay:self.line];self.line=route.polyline;[self.map addOverlay:self.line level:MKOverlayLevelAboveRoads];
        if(reroute){self.rerouting=NO;self.note=@"New route found.";}
        else{self.note=nil;[self.map setVisibleMapRect:self.line.boundingMapRect edgePadding:UIEdgeInsetsMake(200,40,260,40) animated:YES];}
        [self refresh];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&(self.planning||self.rerouting)){self.planning=NO;self.rerouting=NO;self.note=@"Route search timed out. Check your connection and try again.";[self refresh];}});
}
- (MKOverlayRenderer *)mapView:(MKMapView *)map rendererForOverlay:(id<MKOverlay>)overlay{
    if([overlay isKindOfClass:MKPolyline.class]){MKPolylineRenderer *r=[[MKPolylineRenderer alloc]initWithPolyline:(MKPolyline *)overlay];r.lineWidth=6;r.strokeColor=UIColor.systemIndigoColor;return r;}
    return [[MKOverlayRenderer alloc]initWithOverlay:overlay];
}

#pragma mark Navigation
- (void)start{
    if(self.navigating||!self.guide||self.planning)return;BOOL sim=self.sourceControl.selectedSegmentIndex==0;
    if(!sim){CLAuthorizationStatus s=self.locator.authorizationStatus;if(s!=kCLAuthorizationStatusAuthorizedWhenInUse&&s!=kCLAuthorizationStatusAuthorizedAlways){[self alert:@"Location needed" message:@"Allow location access in Settings for live navigation, or use Simulate."];return;}}
    self.navigating=YES;self.simulated=sim;self.mode=self.modeControl.selectedSegmentIndex;self.arrived=NO;self.rerouting=NO;self.weak=NO;self.weakSince=0;self.snapStep=0;self.reroute=TIOGuideRerouteInitial();
    self.simElapsed=0;self.simLastTick=NSProcessInfo.processInfo.systemUptime;self.simPaused=NO;self.lastOffer=0;self.firstFrameAt=0;self.glassesStarted=NO;self.glassesTried=NO;self.display=nil;
    self.roadMap.enabled=[NSUserDefaults.standardUserDefaults boolForKey:RoadsKey];self.roadMap.allowNetwork=self.roadMap.enabled;
    self.idleBefore=UIApplication.sharedApplication.idleTimerDisabled;UIApplication.sharedApplication.idleTimerDisabled=YES;
    self.locator.desiredAccuracy=kCLLocationAccuracyBestForNavigation;self.locator.distanceFilter=kCLDistanceFilterNone;
    self.locator.activityType=self.mode==ModeDrive?CLActivityTypeAutomotiveNavigation:self.mode==ModeCycle?CLActivityTypeOtherNavigation:CLActivityTypeFitness;
    // Keep running behind Apple Maps or the lock screen. Location updates keep the process alive,
    // which also keeps the simulation timer and the glasses transport running.
    if(BackgroundLocation()){self.locator.allowsBackgroundLocationUpdates=YES;self.locator.pausesLocationUpdatesAutomatically=NO;self.locator.showsBackgroundLocationIndicator=YES;[self.locator startUpdatingLocation];}
    self.offers=0;self.fixes=0;self.trace=[NSMutableArray new];[self traceEvent:sim?@"start-simulation":@"start-live"];
    if(sim){self.simMarker=[MKPointAnnotation new];self.simMarker.title=@"Simulated position";[self.map addAnnotation:self.simMarker];}
    else [self.map setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];
    self.note=!BackgroundLocation()?@"Keep the phone unlocked with this screen open.":sim?@"Simulating. You can switch apps or lock the phone (experimental).":@"Navigating. You can switch to Apple Maps or lock the phone (experimental).";[self refresh];
}
- (void)stopTapped{[self stopNavigation:self.navigating?@"Navigation ended.":nil];}
- (void)stopNavigation:(NSString *)message{
    BOOL was=self.navigating;self.navigating=NO;self.generation++;self.rerouting=NO;self.weak=NO;self.simPaused=NO;
    TDPPhoneNavigationStop(); // also asks a failed session to send its one farewell STOP
    self.glassesStarted=NO;self.glassesTried=NO;[self.roadMap reset];if(was)[self.roadMap forgetSavedRoads]; // a trip's route corridor is not kept after it ends
    if(self.simMarker){[self.map removeAnnotation:self.simMarker];self.simMarker=nil;}
    if(was){UIApplication.sharedApplication.idleTimerDisabled=self.idleBefore;self.map.userTrackingMode=MKUserTrackingModeNone;self.locator.desiredAccuracy=kCLLocationAccuracyBest;
        if(BackgroundLocation()){self.locator.allowsBackgroundLocationUpdates=NO;self.locator.pausesLocationUpdatesAutomatically=YES;}
        [self traceEvent:@"stop"];[self saveTrace];}
    self.openMapsPending=NO;
    if(message)self.note=message;[self refresh];
}
- (void)resignActive{
    if(!self.navigating)return;[self traceEvent:@"inactive"];
    // Without the background mode the process will be suspended: pause cleanly instead.
    if(self.simulated&&!BackgroundLocation()){self.simPaused=YES;TNVReplayPaused(YES);}
}
- (void)enterBackground{if(!self.navigating)return;self.inBackground=YES;TNVLifecycle(@"mapkit-background");[self traceEvent:@"background"];[self saveTrace];}
- (void)becomeActive{
    if(self.navigating){self.inBackground=NO;TNVLifecycle(@"mapkit-foreground");[self traceEvent:@"active"];}
    if(self.simPaused){self.simPaused=NO;TNVReplayPaused(NO);}
    self.simLastTick=NSProcessInfo.processInfo.systemUptime;
}
- (void)tick{
    TDPPhoneNavigationPump();NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(self.navigating&&self.simulated&&!self.simPaused&&!self.arrived&&self.guide){
        self.simElapsed+=MIN(1,now-self.simLastTick);self.simLastTick=now;
        if(now-self.lastOffer>=0.2){TIOGuidePose p=TIOGuideSimulate(self.guide,self.simElapsed,SimSpeed(self.mode));self.simMarker.coordinate=CLLocationCoordinate2DMake(p.lat,p.lon);
            if(now-self.lastFollow>=1){self.lastFollow=now;[self.map setCenterCoordinate:self.simMarker.coordinate animated:YES];}
            [self updateAt:p.lat lon:p.lon course:p.heading speed:SimSpeed(self.mode) now:now];}
    }
    if(self.glassesStarted){NSDictionary *s=TDPPhoneNavigationStatus();if([s[@"failed"] boolValue]||(![s[@"active"] boolValue]&&![s[@"busy"] boolValue])){self.glassesStarted=NO;if(self.navigating&&!self.arrived)self.note=@"Lost the glasses connection. Use ⋯ › Reconnect glasses.";}}
    if(self.openMapsPending&&(self.glassesStarted||(self.glassesTried&&!self.glassesStarted)||now-self.openMapsAt>8)){self.openMapsPending=NO;[self openAppleMaps];}
    if(now-self.lastLabel>=1){self.lastLabel=now;self.glassesLabel.text=[self glassesText];} // map-saving progress
    if(self.navigating&&now-self.lastTrace>=2)[self traceEvent:@"tick"];
    if(self.navigating&&now-self.lastTraceSave>=5)[self saveTrace];
    if(now-self.lastUI>=0.5&&!self.inBackground)[self refresh];
}
- (void)updateAt:(double)lat lon:(double)lon course:(double)course speed:(double)speed now:(NSTimeInterval)now{
    if(!self.navigating||self.arrived||!self.guide)return;self.lastOffer=now;
    TIOGuideSnapResult s=TIOGuideSnap(self.guide,lat,lon,self.snapStep);
    if(!self.simulated&&!self.rerouting&&TIOGuideShouldReroute(&_reroute,s.offRoute,now)){self.rerouting=YES;self.note=@"Off route. Finding a new route…";[self calculateFrom:CLLocationCoordinate2DMake(lat,lon) reroute:YES];}
    if(s.offRoute<=TIOGuideOffRouteMeters)self.snapStep=s.step;
    BOOL arrive=TIOGuideArrived(self.guide,s,lat,lon)||(self.simulated&&TIOGuideSimulate(self.guide,self.simElapsed,SimSpeed(self.mode)).done);
    TIOGuideProgressResult p=TIOGuideProgress(self.guide,s);NSInteger icon=arrive?TIOGuideIconArrive:self.rerouting?TIOGuideIconUnknown:TIOGuideIcon(self.guide,s.step);
    NSString *turn=self.rerouting&&!arrive?@"Rerouting…":TIOGuideTurnText(icon);
    NSString *road=icon==TIOGuideIconArrive?(self.destinationName?:@""):self.rerouting?@"":TIOGuideManeuverRoad(self.guide,s.step);
    // Show the matched position when close to the route; the raw fix when clearly off it.
    BOOL matched=s.offRoute<=15;double plat=matched?s.lat:lat,plon=matched?s.lon:lon;
    NSArray *ahead=TIOGuideUpcoming(self.guide,s,512);
    NSMutableDictionary *f=[@{@"phase":@"navigating",@"icon":@(icon),@"meters":@(arrive?0:TIOGuideRoundMeters(p.toManeuver)),@"turn":turn,@"road":road,@"remainingMeters":@(arrive?0:TIOGuideRoundMeters(p.remainingMeters)),@"remainingSeconds":@(arrive?0:60*(long)ceil(p.remainingSeconds/60)),
        @"simulated":@(self.simulated),@"segment":@(s.step),@"observedAt":@(NSDate.date.timeIntervalSince1970),@"tnrSource":self.simulated?@"mapkit-simulation":@"mapkit-realtime"} mutableCopy];
    [f addEntriesFromDictionary:TNVNormalizeCoordinates(ahead)];
    f[@"navSpeed"]=@(isfinite(speed)&&speed>=0?speed:0);f[@"tnrLocation"]=@[@(plat),@(plon)];f[@"tnrLocationAt"]=@(now);f[@"navHeading"]=@((unsigned)lround(TIOGuideHeading(course,speed,s.bearing))%360);
    NSDictionary *frame=[self.roadMap decorate:f coordinates:ahead];self.display=frame;
    if(!self.firstFrameAt)self.firstFrameAt=now;
    if(self.glassesStarted){TDPPhoneNavigationOffer(frame);self.offers++;}
    else if(!self.glassesTried&&(!self.roadMap.enabled||frame[@"tnrScene"]||now-self.firstFrameAt>5))[self startGlasses:frame];
    if(arrive)[self arriveWithFrame:frame];
}
- (void)startGlasses:(NSDictionary *)frame{
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;self.glassesTried=YES;
    NSString *busy=GlassesBusy();if(busy){self.note=[busy stringByAppendingString:@" Stop it, then use ⋯ › Reconnect glasses."];return;}
    self.glassesStarted=TDPPhoneNavigationStart(frame);
    if(!self.glassesStarted)[self alert:@"Glasses didn't start" message:@"Check that the glasses are connected and idle on the home screen, then use ⋯ › Reconnect glasses. Phone navigation continues."];
}
- (void)arriveWithFrame:(NSDictionary *)frame{
    self.arrived=YES;self.note=[NSString stringWithFormat:@"Arrived at %@.",self.destinationName?:@"your destination"];[self refresh];NSUInteger g=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&self.arrived)[self stopNavigation:self.note];});
}

#pragma mark Apple Maps hand-off
- (void)appleMapsTapped{
    if(self.navigating){[self openAppleMaps];return;}
    if(!self.guide||self.planning)return;
    // Start first: the glasses session can only open while this app is in front.
    self.sourceControl.selectedSegmentIndex=1;[self start];if(!self.navigating)return;
    self.openMapsPending=YES;self.openMapsAt=NSProcessInfo.processInfo.systemUptime;self.note=@"Connecting the glasses, then opening Apple Maps…";[self refresh];
}
- (void)openAppleMaps{
    if(!self.destination)return;NSString *mode=self.mode==ModeDrive?MKLaunchOptionsDirectionsModeDriving:self.mode==ModeCycle?MKLaunchOptionsDirectionsModeCycling:MKLaunchOptionsDirectionsModeWalking;
    [self traceEvent:@"open-apple-maps"];
    BOOL ok=[MKMapItem openMapsWithItems:@[[MKMapItem mapItemForCurrentLocation],self.destination] launchOptions:@{MKLaunchOptionsDirectionsModeKey:mode}];
    if(!ok)[self alert:@"Couldn't open Apple Maps" message:@"Turbo IO navigation continues on the glasses."];
}

#pragma mark Background trace
// Evidence for the unresolved background stall: what the app, location and glasses
// transport were doing, sampled every 2 s. No coordinates are stored.
- (void)traceEvent:(NSString *)event{
    if(!self.trace)return;self.lastTrace=NSProcessInfo.processInfo.systemUptime;NSDictionary *s=TDPPhoneNavigationStatus();
    NSMutableDictionary *e=[@{@"event":event,@"t":@(round(self.lastTrace*10)/10),@"app":AppState(),@"fixes":@(self.fixes),@"offers":@(self.offers),@"glassesStarted":@(self.glassesStarted),@"simulated":@(self.simulated),@"rerouting":@(self.rerouting),@"weak":@(self.weak)} mutableCopy];
    if(self.fix)e[@"fixAge"]=@(round(-self.fix.timestamp.timeIntervalSinceNow*10)/10);
    NSDictionary *roads=self.roadMap.coverageStatus;e[@"roadsOn"]=@(self.roadMap.enabled);e[@"roadFeatures"]=roads[@"features"]?:@0;e[@"roadRequests"]=roads[@"requests"]?:@0;e[@"roadLoading"]=roads[@"requestInFlight"]?:@NO;e[@"tilesWanted"]=roads[@"tiles"][@"wanted"]?:@0;e[@"tilesSaved"]=roads[@"tiles"][@"saved"]?:@0;e[@"tilesFailed"]=roads[@"tiles"][@"failed"]?:@0;e[@"tileBytes"]=roads[@"tiles"][@"downloadedBytes"]?:@0;
    for(NSString *k in @[@"active",@"busy",@"failed",@"snapshots",@"maps",@"poses",@"ackMs",@"fileMs",@"poseAgeMs",@"replayPaused",@"inFlightOp",@"files",@"backoff",@"mapPaths",@"mapLabels"])if(s[k])e[k]=s[k];
    [self.trace addObject:e];if(self.trace.count>900)[self.trace removeObjectAtIndex:0];
}
- (void)saveTrace{
    if(!self.trace.count)return;self.lastTraceSave=NSProcessInfo.processInfo.systemUptime;
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSString *file=[dir stringByAppendingPathComponent:@"mapkit-navigation-trace.json"];
    NSDictionary *d=@{@"build":@"MAPKIT-NAV-06",@"backgroundLocationMode":@(BackgroundLocation()),@"saved":@(NSDate.date.timeIntervalSince1970),@"events":[self.trace copy]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    if([data writeToFile:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil])[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file error:nil];
}

#pragma mark UI
- (void)refresh{
    self.lastUI=NSProcessInfo.processInfo.systemUptime;BOOL sim=self.sourceControl.selectedSegmentIndex==0;NSDictionary *d=self.display;
    if(self.navigating&&d){
        self.titleLabel.text=[NSString stringWithFormat:@"%@ · %@",d[@"turn"],Meters([d[@"meters"] doubleValue])];
        NSString *road=d[@"road"];self.detailLabel.text=self.note?:(road.length?road:(self.simulated?@"Simulated route":@"Follow the route"));
        double sec=[d[@"remainingSeconds"] doubleValue];self.metricsLabel.text=[NSString stringWithFormat:@"%@  ·  %@  ·  arrive %@",Minutes(sec),Meters([d[@"remainingMeters"] doubleValue]),Clock(sec)];
    }else if(self.guide&&!self.navigating){
        self.titleLabel.text=self.destinationName?:@"Route ready";self.detailLabel.text=self.note?:(sim?(self.hasSimStart?@"Simulated from the chosen start":@"Simulated from your location"):@"From your location");
        self.metricsLabel.text=[NSString stringWithFormat:@"%@  ·  %@  ·  arrive %@",Minutes(self.route.expectedTravelTime),Meters(self.route.distance),Clock(self.route.expectedTravelTime)];
    }else{self.titleLabel.text=self.destinationName?:@"Where to?";self.detailLabel.text=self.note?:@"";self.metricsLabel.text=nil;}
    self.metricsLabel.hidden=!self.metricsLabel.text.length;
    UIButtonConfiguration *c=self.startButton.configuration;c.title=self.planning?@"Finding route…":sim?@"Start simulation":@"Start";self.startButton.configuration=c;
    self.startButton.hidden=self.navigating;self.startButton.enabled=self.guide&&!self.planning;self.stopButton.hidden=!self.navigating;
    // Apple Maps only follows your real position, so the hand-off is for live routes.
    self.appleMapsButton.hidden=self.navigating?self.simulated:sim;self.appleMapsButton.enabled=self.navigating||(self.guide&&!self.planning);
    self.modeControl.enabled=self.sourceControl.enabled=!self.navigating;self.search.userInteractionEnabled=!self.navigating;
    self.glassesLabel.text=[self glassesText];
}
- (NSString *)glassesText{
    NSDictionary *s=TDPPhoneNavigationStatus();NSDictionary *c=self.roadMap.coverageStatus,*t=c[@"tiles"];NSUInteger saved=[t[@"saved"] unsignedIntegerValue],wanted=[t[@"wanted"] unsignedIntegerValue];
    NSString *stored=wanted>saved?[NSString stringWithFormat:@" · saving map %lu/%lu%@",(unsigned long)saved,(unsigned long)wanted,[t[@"failed"] unsignedIntegerValue]?@", no signal":@""]:wanted?@" · route map saved":@"";
    NSString *roads=!self.roadMap.enabled?@"roads off":[([c[@"features"] unsignedIntegerValue]?@"roads on · OpenFreeMap © OpenStreetMap":@"roads waiting") stringByAppendingString:stored];
    if([s[@"active"] boolValue])return [NSString stringWithFormat:@"Glasses: connected · %@ updates · %@ maps · %@",s[@"snapshots"]?:@0,s[@"maps"]?:@0,roads];
    if(self.navigating)return [(self.glassesTried?@"Glasses: not connected":@"Glasses: connecting…") stringByAppendingString:stored];
    return [@"Glasses: turn-by-turn starts automatically with navigation" stringByAppendingString:stored];
}
- (void)more{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Navigation options" message:@"Guidance behind Apple Maps or the lock screen is experimental; if the glasses freeze, return to this screen. Not for driving." preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL roads=[NSUserDefaults.standardUserDefaults boolForKey:RoadsKey];
    [a addAction:[UIAlertAction actionWithTitle:roads?@"Turn off nearby roads on glasses":@"Show nearby roads on glasses…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self toggleRoads];}]];
    [a addAction:[UIAlertAction actionWithTitle:TNVAlways()?@"Let glasses display sleep":@"Keep glasses display on" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){TNVSetAlways(!TNVAlways());}]];
    if(!self.navigating){
        [a addAction:[UIAlertAction actionWithTitle:@"Set simulation start (long-press map)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self.pickingStart=YES;self.note=@"Long-press the map to set where the simulation starts.";[self refresh];}]];
        if(self.hasSimStart)[a addAction:[UIAlertAction actionWithTitle:@"Simulate from my location" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self.hasSimStart=NO;if(self.startPin)[self.map removeAnnotation:self.startPin];self.startPin=nil;if(self.destination)[self plan];}]];
    }
    if(self.navigating)[a addAction:[UIAlertAction actionWithTitle:@"Reconnect glasses" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self reconnect];}]];
    if(self.route)[a addAction:[UIAlertAction actionWithTitle:@"Route steps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self showSteps];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)toggleRoads{
    NSUserDefaults *u=NSUserDefaults.standardUserDefaults;
    if([u boolForKey:RoadsKey]){[u setBool:NO forKey:RoadsKey];self.roadMap.enabled=NO;self.roadMap.allowNetwork=NO;[self.roadMap forgetSavedRoads];[self refresh];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Show nearby roads?" message:@"When you plan a route, the street map along it (about 700 m either side) is downloaded from OpenFreeMap (tiles.openfreemap.org, OpenStreetMap data) and saved on this phone until navigation ends, so nearby streets still show on the glasses without cell signal. Open highway needs well under 1 MB per 100 km; city driving more (San Francisco to San Jose is about 10 MB). Plan on Wi-Fi when you can. The route itself still comes from Apple Maps." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Allow" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[u setBool:YES forKey:RoadsKey];self.roadMap.enabled=YES;self.roadMap.allowNetwork=YES;if(self.guide)[self.roadMap prefetchRoute:self.guide.points];[self refresh];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)reconnect{
    if([TDPPhoneNavigationStatus()[@"busy"] boolValue]){[self alert:@"Glasses busy" message:@"Wait a few seconds for the last update to finish, then try again."];return;}
    if([TDPPhoneNavigationStatus()[@"active"] boolValue])TDPPhoneNavigationStop();
    self.glassesStarted=NO;self.glassesTried=NO;self.firstFrameAt=0;self.note=@"Reconnecting to the glasses…";[self refresh];
}
- (void)showSteps{
    NSMutableArray *lines=[NSMutableArray new];
    for(MKRouteStep *s in self.route.steps){if(!s.instructions.length)continue;[lines addObject:[NSString stringWithFormat:@"%lu. %@ · %@",(unsigned long)lines.count+1,s.instructions,Meters(s.distance)]];if(lines.count>=40)break;}
    [self alert:@"Route steps" message:lines.count?[lines componentsJoinedByString:@"\n"]:@"No steps."];
}
@end

UIViewController *TIOMapKitNavigationController(void){return [TIOMapKitNavigationPanel new];}
