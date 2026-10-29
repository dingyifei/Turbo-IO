#import "MapKitNavigationUI.h"
#import "TIODesign.h"
#import "TIOLanguage.h"
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
// TIOText with a printf template: a plain wrapper keeps clang from treating the key as the format.
static NSString *FormatText(NSString *key){return TIOText(key);}
// Text on map chrome (search, mode control, bar buttons) scales with Dynamic Type but stops growing
// at 28 pt, so the floating cards never swallow the map. Sheet text is uncapped and scrolls instead.
static UIFont *ChromeFont(TIODesignTextStyle style,UIFontWeight weight){
    UIFont *base=TIODesignFontWeight(style,weight);
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[base fontWithSize:TIODesignTextStyleSize(style)] maximumPointSize:28];
}
static NSString *Meters(double m){if(!isfinite(m)||m<0)return @"—";if(m>=1000)return [NSString stringWithFormat:FormatText(@"nav.unit.km"),m/1000];long r=m<50?lround(m):lround(m/10)*10;return [NSString stringWithFormat:FormatText(@"nav.unit.m"),r];}
static NSString *Minutes(double s){if(!isfinite(s)||s<0)return @"—";long m=MAX(1,lround(ceil(s/60)));return m>=60?[NSString stringWithFormat:FormatText(@"nav.unit.hmin"),m/60,m%60]:[NSString stringWithFormat:FormatText(@"nav.unit.min"),m];}
static NSString *Clock(double s){if(!isfinite(s)||s<0)return @"—";NSDateFormatter *f=[NSDateFormatter new];f.timeStyle=NSDateFormatterShortStyle;f.dateStyle=NSDateFormatterNoStyle;return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:s]];}
// The 1.0.7 host declares the location background mode; check rather than assume, since
// enabling background updates without it raises an exception.
static BOOL BackgroundLocation(void){id m=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"];return [m isKindOfClass:NSArray.class]&&[m containsObject:@"location"];}
static NSString *AppState(void){switch(UIApplication.sharedApplication.applicationState){case UIApplicationStateActive:return @"active";case UIApplicationStateInactive:return @"inactive";default:return @"background";}}
static NSString *GlassesBusy(void){
    if(![TIOSubtitleNavigationStatus()[@"phase"] isEqual:@"idle"])return TIOText(@"nav.busy.captions");
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

// Turn wording for the screen. The glasses frame keeps its own English text (sent unchanged).
static NSString *TurnText(NSInteger icon){
    switch(icon){
        case TIOGuideIconLeft:return TIOText(@"nav.turn.left");case TIOGuideIconRight:return TIOText(@"nav.turn.right");
        case TIOGuideIconSlightLeft:return TIOText(@"nav.turn.slightLeft");case TIOGuideIconSlightRight:return TIOText(@"nav.turn.slightRight");
        case TIOGuideIconSharpLeft:return TIOText(@"nav.turn.sharpLeft");case TIOGuideIconSharpRight:return TIOText(@"nav.turn.sharpRight");
        case TIOGuideIconUTurn:return TIOText(@"nav.turn.uturn");case TIOGuideIconStraight:return TIOText(@"nav.turn.straight");
        case TIOGuideIconRoundabout:return TIOText(@"nav.turn.roundabout");case TIOGuideIconArrive:return TIOText(@"nav.turn.arrive");
        default:return TIOText(@"nav.turn.follow");
    }
}
static NSString *LensSymbol(NSInteger icon){
    switch(icon){
        case TIOGuideIconLeft:case TIOGuideIconSharpLeft:return @"arrow.turn.up.left";
        case TIOGuideIconRight:case TIOGuideIconSharpRight:return @"arrow.turn.up.right";
        case TIOGuideIconSlightLeft:return @"arrow.up.left";case TIOGuideIconSlightRight:return @"arrow.up.right";
        case TIOGuideIconUTurn:return @"arrow.uturn.left";case TIOGuideIconRoundabout:return @"arrow.triangle.turn.up.right.circle";
        case TIOGuideIconArrive:return @"mappin.and.ellipse";
        default:return @"arrow.up";
    }
}

// The phone-side picture of the glasses navigation page (docs/design-system LensPreview, 540x180
// glasses pixels): road being passed in band T, trip line in band M, arrow, distance and turn in
// band B, and the route on the right. Always lens-black with lens-* greens. It is a surrogate
// drawn with the system font, not a firmware render, and says so to VoiceOver.
@interface TIONavLensView:UIView
@property(nonatomic,copy) NSDictionary *model; // passing, trip, icon, distance, turn, road, route, here
@end
@implementation TIONavLensView
- (instancetype)initWithFrame:(CGRect)frame{self=[super initWithFrame:frame];self.contentMode=UIViewContentModeRedraw;return self;}
- (void)setModel:(NSDictionary *)model{if(_model==model||[_model isEqual:model])return;_model=[model copy];[self setNeedsDisplay];}
- (void)drawRect:(CGRect)rect{
    NSDictionary *m=self.model;CGFloat s=CGRectGetWidth(self.bounds)/TIOLensPageW;if(!m||s<=0)return;
    UIColor *full=TIODesignColor(TIODesignColorLensFull),*high=TIODesignColor(TIODesignColorLensHigh),*mid=TIODesignColor(TIODesignColorLensMid),*track=TIODesignColor(TIODesignColorLensTrack);
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByTruncatingTail;
    CGFloat mapWidth=140,mapX=TIOLensCoreXEnd-mapWidth,textRight=mapX-10; // text stays left of the map column
    CGSize (^draw)(NSString *,UIFont *,UIColor *,CGFloat,CGFloat,CGFloat)=^CGSize(NSString *text,UIFont *font,UIColor *color,CGFloat x,CGFloat y,CGFloat maxX){
        NSDictionary *attributes=@{NSFontAttributeName:font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style};
        CGSize size=[text sizeWithAttributes:attributes];
        [text drawInRect:CGRectMake(x*s,y*s,MAX(0,maxX-x)*s,ceil(size.height)) withAttributes:attributes];
        return CGSizeMake(MIN(size.width/s,MAX(0,maxX-x)),size.height/s);
    };
    NSString *passing=m[@"passing"];
    if(passing.length)draw(passing,TIODesignLensFont(TIOLensLabelSize,s,UIFontWeightRegular),mid,TIOLensCoreXStart,TIOLensBandTTop+(TIOLensBandTBottom-TIOLensBandTTop-TIOLensLabelLine)/2,textRight);
    NSString *trip=m[@"trip"];
    if(trip.length)draw(trip,TIODesignLensFont(TIOLensLabelSize,s,UIFontWeightRegular),high,TIOLensCoreXStart,TIOLensBandMTop+(TIOLensBandMBottom-TIOLensBandMTop-TIOLensLabelLine)/2,textRight);
    // Band B: arrow, distance and turn, the primary information lowest.
    CGFloat arrow=40,bandB=TIOLensBandBTop,x=TIOLensCoreXStart+arrow+12;
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:arrow*s*0.8 weight:UIImageSymbolWeightSemibold];
    UIImage *glyph=[[UIImage systemImageNamed:LensSymbol([m[@"icon"] integerValue]) withConfiguration:config] imageWithTintColor:full renderingMode:UIImageRenderingModeAlwaysOriginal];
    if(glyph){CGSize g=glyph.size;[glyph drawInRect:CGRectMake((TIOLensCoreXStart+(arrow-g.width/s)/2)*s,(bandB+8+(arrow-g.height/s)/2)*s,g.width,g.height)];}
    NSString *distance=m[@"distance"];CGFloat turnX=x;
    if(distance.length){CGSize d=draw(distance,TIODesignLensFont(TIOLensPrimarySize,s,UIFontWeightMedium),full,x,bandB+2,textRight);turnX=x+d.width+14;}
    NSString *turn=m[@"turn"];
    if(turn.length&&turnX<textRight)draw(turn,TIODesignLensFont(TIOLensMinSize,s,UIFontWeightMedium),full,turnX,bandB+2+(TIOLensPrimaryLine-TIOLensMinLine)/2+4,textRight);
    NSString *road=m[@"road"];
    if(road.length)draw(road,TIODesignLensFont(TIOLensMinSize,s,UIFontWeightRegular),high,x,bandB+2+TIOLensPrimaryLine,textRight);
    // Right column: faint street grid with the route in full green.
    CGRect map=CGRectMake(mapX*s,(TIOLensBandTTop+8)*s,mapWidth*s,(TIOLensBandBBottom-TIOLensBandTTop-6)*s);
    CGContextRef g=UIGraphicsGetCurrentContext();CGContextSaveGState(g);CGContextClipToRect(g,map);
    [track setStroke];UIBezierPath *grid=[UIBezierPath bezierPath];grid.lineWidth=MAX(1,2*s);
    for(int i=1;i<4;i++){[grid moveToPoint:CGPointMake(CGRectGetMinX(map),CGRectGetMinY(map)+CGRectGetHeight(map)*i/4)];[grid addLineToPoint:CGPointMake(CGRectGetMaxX(map),CGRectGetMinY(map)+CGRectGetHeight(map)*i/4)];
        [grid moveToPoint:CGPointMake(CGRectGetMinX(map)+CGRectGetWidth(map)*i/4,CGRectGetMinY(map))];[grid addLineToPoint:CGPointMake(CGRectGetMinX(map)+CGRectGetWidth(map)*i/4,CGRectGetMaxY(map))];}
    [grid stroke];
    NSArray *route=m[@"route"];
    if(route.count>1){
        double minLat=90,maxLat=-90,minLon=180,maxLon=-180;
        for(NSArray *p in route){double la=[p[0] doubleValue],lo=[p[1] doubleValue];minLat=MIN(minLat,la);maxLat=MAX(maxLat,la);minLon=MIN(minLon,lo);maxLon=MAX(maxLon,lo);}
        double k=cos((minLat+maxLat)/2*M_PI/180),w=MAX((maxLon-minLon)*k,1e-9),h=MAX(maxLat-minLat,1e-9);
        CGFloat pad=10*s,fit=MIN((CGRectGetWidth(map)-2*pad)/w,(CGRectGetHeight(map)-2*pad)/h);
        CGPoint (^point)(NSArray *)=^CGPoint(NSArray *p){return CGPointMake(CGRectGetMidX(map)+([p[1] doubleValue]-(minLon+maxLon)/2)*k*fit,CGRectGetMidY(map)-([p[0] doubleValue]-(minLat+maxLat)/2)*fit);};
        UIBezierPath *line=[UIBezierPath bezierPath];line.lineWidth=MAX(1.5,4*s);line.lineJoinStyle=kCGLineJoinRound;line.lineCapStyle=kCGLineCapRound;
        NSUInteger stride=MAX(1,route.count/200);
        for(NSUInteger i=0;i<route.count;i+=stride){CGPoint p=point(route[i]);if(!i)[line moveToPoint:p];else [line addLineToPoint:p];}
        [line addLineToPoint:point(route.lastObject)];
        [full setStroke];[line stroke];
        NSArray *here=m[@"here"];
        if(here.count==2){CGPoint p=point(here);[full setFill];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x-4*s,p.y-4*s,8*s,8*s)] fill];}
    }
    CGContextRestoreGState(g);
}
@end

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
// Layout: glass buttons, top card, bottom sheet. Navigation state above is untouched by the UI.
@property UIButton *backButton,*moreButton;
@property UIView *topCard,*sheet,*grabber,*pillHolder,*pill;
@property UIStackView *titleRow,*buttonRow;
@property NSLayoutConstraint *buttonRatio,*pillWidth;
@property UIScrollView *sheetScroll;
@property TIONavLensView *lensView;
@property BOOL collapsed;
@property NSString *pillKey,*menuKey;
@property NSDictionary *readyLens;
@property TIOGuideRoute *readyGuide;
@end

@implementation TIOMapKitNavigationPanel
- (UILabel *)label:(TIODesignTextStyle)style weight:(UIFontWeight)weight{UILabel *l=[UILabel new];l.numberOfLines=0;l.font=TIODesignFontWeight(style,weight);l.textColor=TIODesignColor(TIODesignColorLabel);l.adjustsFontForContentSizeCategory=YES;return l;}
- (UIButton *)action:(NSString *)title icon:(NSString *)icon selector:(SEL)sel role:(TIODesignButtonRole)role{
    UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];c.title=title;
    UIButton *b=[UIButton buttonWithConfiguration:c primaryAction:nil];b.translatesAutoresizingMaskIntoConstraints=NO;
    TIODesignStyleButton(b,role);
    if(icon){c=b.configuration;c.image=[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleHeadline scale:UIImageSymbolScaleSmall]];c.imagePadding=TIOSpace1+2;b.configuration=c;}
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];return b;
}
// Floating glass surface (bar buttons, top card): bg-raised at 94%, opaque when Reduce Transparency is on.
- (void)glass:(UIView *)v radius:(CGFloat)radius{
    CGFloat alpha=UIAccessibilityIsReduceTransparencyEnabled()?1:.94;
    v.backgroundColor=[TIODesignColor(TIODesignColorBgRaised) colorWithAlphaComponent:alpha];v.layer.cornerRadius=radius;v.layer.cornerCurve=kCACornerCurveContinuous;
    v.layer.shadowColor=UIColor.blackColor.CGColor;v.layer.shadowOpacity=.14;v.layer.shadowRadius=TIOSpace3+TIOSpace1+TIOSpace1;v.layer.shadowOffset=CGSizeMake(0,TIOSpace1+2);
}
- (UIButton *)glassButton:(NSString *)title symbol:(NSString *)symbol label:(NSString *)label{
    UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];
    c.image=[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:TIOSpace4+1 weight:UIImageSymbolWeightSemibold]];
    c.title=title;c.imagePadding=TIOSpace1;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
    c.contentInsets=NSDirectionalEdgeInsetsMake(0,title?TIOSpace2:TIOSpace3,0,title?TIOSpace3:TIOSpace3);
    c.baseForegroundColor=title?TIODesignColor(TIODesignColorAccent):TIODesignColor(TIODesignColorLabel);
    c.titleTextAttributesTransformer=^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes){
        NSMutableDictionary *m=[attributes mutableCopy];m[NSFontAttributeName]=ChromeFont(TIODesignTextStyleBody,UIFontWeightRegular);return m;
    };
    UIButton *b=[UIButton buttonWithConfiguration:c primaryAction:nil];b.translatesAutoresizingMaskIntoConstraints=NO;
    [self glass:b radius:TIOHitMin/2];b.accessibilityLabel=label;
    [b.heightAnchor constraintEqualToConstant:TIOHitMin].active=YES;[b.widthAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;
    return b;
}
- (void)styleSegments:(UISegmentedControl *)c{
    UIFont *font=ChromeFont(TIODesignTextStyleFootnote,UIFontWeightSemibold);
    [c setTitleTextAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:TIODesignColor(TIODesignColorLabel)} forState:UIControlStateNormal];
    [c setTitleTextAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:TIODesignColor(TIODesignColorLabel)} forState:UIControlStateSelected];
    [c setTitleTextAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:TIODesignColor(TIODesignColorLabelTertiary)} forState:UIControlStateDisabled];
    c.backgroundColor=TIODesignColor(TIODesignColorBgSunken);c.selectedSegmentTintColor=TIODesignColor(TIODesignColorBgRaised);
}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=TIOText(@"hub.row.navigation");self.view.backgroundColor=TIODesignColor(TIODesignColorBg);self.view.tintColor=TIODesignColor(TIODesignColorAccent);
    self.roadMap=[[TIORoadMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){return @[@(lat),@(lon)];}];
    self.roadMap.enabled=[NSUserDefaults.standardUserDefaults boolForKey:RoadsKey];self.reroute=TIOGuideRerouteInitial();
    // Map first: it fills the screen, and everything else floats over it.
    self.map=[MKMapView new];self.map.delegate=self;self.map.translatesAutoresizingMaskIntoConstraints=NO;self.map.showsCompass=YES;[self.view addSubview:self.map];
    [self.map addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPress:)]];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    // Glass back and options buttons.
    self.backButton=[self glassButton:TIOText(@"hub.title") symbol:@"chevron.left" label:TIOText(@"nav.back.a11y")];
    [self.backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    self.moreButton=[self glassButton:nil symbol:@"ellipsis" label:TIOText(@"nav.options.title")];
    self.moreButton.accessibilityHint=TIOText(@"nav.options.hint");self.moreButton.showsMenuAsPrimaryAction=YES;
    [self.view addSubview:self.backButton];[self.view addSubview:self.moreButton];
    // Top card: search and the Walk/Cycle/Drive capsule. Simulate/Live lives in the options menu; the
    // source control below only holds that choice (the menu writes it) and is never shown.
    UIStackView *top=[UIStackView new];top.axis=UILayoutConstraintAxisVertical;top.spacing=TIOSpace2;top.layoutMargins=UIEdgeInsetsMake(TIOSpace2,TIOSpace2,TIOSpace2,TIOSpace2);top.layoutMarginsRelativeArrangement=YES;top.translatesAutoresizingMaskIntoConstraints=NO;
    [self glass:top radius:TIORadiusLG];self.topCard=top;
    self.search=[UISearchBar new];self.search.placeholder=TIOText(@"nav.search.placeholder");self.search.delegate=self;self.search.searchBarStyle=UISearchBarStyleMinimal;
    self.search.accessibilityLabel=TIOText(@"nav.search.a11y");
    UISearchTextField *field=self.search.searchTextField;field.font=ChromeFont(TIODesignTextStyleBody,UIFontWeightRegular);field.adjustsFontForContentSizeCategory=YES;field.textColor=TIODesignColor(TIODesignColorLabel);
    field.backgroundColor=TIODesignColor(TIODesignColorBgSunken);field.layer.cornerRadius=TIOHitMin*.4;field.layer.cornerCurve=kCACornerCurveContinuous;field.layer.masksToBounds=YES;field.tintColor=TIODesignColor(TIODesignColorAccent);
    field.attributedPlaceholder=[[NSAttributedString alloc]initWithString:TIOText(@"nav.search.placeholder") attributes:@{NSForegroundColorAttributeName:TIODesignColor(TIODesignColorLabelSecondary),NSFontAttributeName:ChromeFont(TIODesignTextStyleBody,UIFontWeightRegular)}];
    field.leftView.tintColor=TIODesignColor(TIODesignColorLabelSecondary);
    [self.search.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;[top addArrangedSubview:self.search];
    self.modeControl=[[UISegmentedControl alloc]initWithItems:@[TIOText(@"nav.mode.walk"),TIOText(@"nav.mode.cycle"),TIOText(@"nav.mode.drive")]];self.modeControl.selectedSegmentIndex=ModeWalk;
    [self.modeControl addTarget:self action:@selector(optionsChanged) forControlEvents:UIControlEventValueChanged];self.modeControl.accessibilityLabel=TIOText(@"nav.mode.a11y");
    [self styleSegments:self.modeControl];[self.modeControl.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;[top addArrangedSubview:self.modeControl];
    self.sourceControl=[[UISegmentedControl alloc]initWithItems:@[TIOText(@"nav.source.simulate"),TIOText(@"nav.source.live")]];self.sourceControl.selectedSegmentIndex=0;
    [self.view addSubview:top];
    self.results=[UITableView new];self.results.translatesAutoresizingMaskIntoConstraints=NO;self.results.dataSource=self;self.results.delegate=self;self.results.layer.cornerRadius=TIORadiusLG/2;self.results.layer.masksToBounds=YES;self.results.hidden=YES;
    self.results.backgroundColor=TIODesignColor(TIODesignColorBgRaised);self.results.separatorColor=TIODesignColor(TIODesignColorSeparator);[self.view addSubview:self.results];
    self.completer=[MKLocalSearchCompleter new];self.completer.delegate=self;self.completer.resultTypes=MKLocalSearchCompleterResultTypeAddress|MKLocalSearchCompleterResultTypePointOfInterest;
    // Bottom sheet: grabber, title and metrics with the glasses pill, lens preview, Start / Apple Maps (End while navigating), footnote.
    UIView *sheet=[UIView new];sheet.translatesAutoresizingMaskIntoConstraints=NO;sheet.backgroundColor=TIODesignColor(TIODesignColorBgRaised);self.sheet=sheet;
    sheet.layer.cornerRadius=TIORadiusLG;sheet.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;sheet.layer.cornerCurve=kCACornerCurveContinuous;
    sheet.layer.shadowColor=UIColor.blackColor.CGColor;sheet.layer.shadowOpacity=.12;sheet.layer.shadowRadius=TIOSpace5;sheet.layer.shadowOffset=CGSizeMake(0,-TIOSpace1);
    self.titleLabel=[self label:TIODesignTextStyleTitle3 weight:UIFontWeightSemibold];self.titleLabel.accessibilityTraits|=UIAccessibilityTraitHeader;
    self.metricsLabel=[self label:TIODesignTextStyleSubheadline weight:UIFontWeightRegular];self.metricsLabel.textColor=TIODesignColor(TIODesignColorLabelSecondary);self.metricsLabel.font=TIODesignMonospacedDigitFont(TIODesignTextStyleSubheadline);
    self.detailLabel=[self label:TIODesignTextStyleFootnote weight:UIFontWeightRegular];self.detailLabel.textColor=TIODesignColor(TIODesignColorLabelSecondary);self.detailLabel.textAlignment=NSTextAlignmentCenter;
    self.glassesLabel=[self label:TIODesignTextStyleCaption weight:UIFontWeightRegular];self.glassesLabel.textColor=TIODesignColor(TIODesignColorLabelSecondary);self.glassesLabel.textAlignment=NSTextAlignmentCenter;
        self.pillHolder=[UIView new];self.pillHolder.translatesAutoresizingMaskIntoConstraints=NO;[self.pillHolder setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];[self.pillHolder setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self.titleRow=[[UIStackView alloc]initWithArrangedSubviews:@[self.titleLabel,self.pillHolder]];self.titleRow.axis=UILayoutConstraintAxisHorizontal;self.titleRow.alignment=UIStackViewAlignmentTop;self.titleRow.spacing=TIOSpace2;
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.lensView=[TIONavLensView new];self.lensView.translatesAutoresizingMaskIntoConstraints=NO;TIODesignStyleLensPreview(self.lensView,@"");
    self.lensView.accessibilityHint=TIOText(@"nav.lens.approx");
    [self.lensView.heightAnchor constraintEqualToAnchor:self.lensView.widthAnchor multiplier:TIOLensPageH/TIOLensPageW].active=YES;
    self.startButton=[self action:TIOText(@"nav.start") icon:@"location.north.fill" selector:@selector(start) role:TIODesignButtonPrimary];
    self.stopButton=[self action:TIOText(@"nav.end") icon:@"stop.fill" selector:@selector(stopTapped) role:TIODesignButtonDestructive];
    self.appleMapsButton=[self action:TIOText(@"nav.appleMaps") icon:nil selector:@selector(appleMapsTapped) role:TIODesignButtonSecondary];
    self.buttonRow=[[UIStackView alloc]initWithArrangedSubviews:@[self.startButton,self.stopButton,self.appleMapsButton]];self.buttonRow.spacing=TIOSpace3;
    self.buttonRatio=[self.appleMapsButton.widthAnchor constraintEqualToAnchor:self.startButton.widthAnchor multiplier:.5];self.buttonRatio.priority=UILayoutPriorityDefaultHigh;self.buttonRatio.active=YES;
    UIStackView *content=[[UIStackView alloc]initWithArrangedSubviews:@[self.titleRow,self.metricsLabel,self.lensView,self.buttonRow,self.detailLabel,self.glassesLabel]];
    content.axis=UILayoutConstraintAxisVertical;content.spacing=TIOSpace3-2;[content setCustomSpacing:2 afterView:self.titleRow];content.translatesAutoresizingMaskIntoConstraints=NO;
    for(UIView *v in @[self.titleLabel,self.metricsLabel,self.detailLabel,self.glassesLabel])[v setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;scroll.alwaysBounceVertical=NO;self.sheetScroll=scroll;
    [scroll addSubview:content];[sheet addSubview:scroll];
    // The grabber's 44 pt hit area overlaps the sheet's top margin; tap or drag toggles the details.
    UIView *grabber=[UIView new];grabber.translatesAutoresizingMaskIntoConstraints=NO;self.grabber=grabber;
    UIView *bar=[UIView new];bar.translatesAutoresizingMaskIntoConstraints=NO;bar.backgroundColor=TIODesignColor(TIODesignColorSeparator);bar.layer.cornerRadius=TIORadiusXS+.5;bar.userInteractionEnabled=NO;[grabber addSubview:bar];
    grabber.isAccessibilityElement=YES;grabber.accessibilityTraits=UIAccessibilityTraitButton;
    [grabber addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(toggleSheet)]];
    [grabber addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(grabberPan:)]];
    [sheet addSubview:grabber];[self.view addSubview:sheet];
    UILayoutGuide *scrollContent=scroll.contentLayoutGuide,*scrollFrame=scroll.frameLayoutGuide;
    // Sheet height follows its content (top margin included) up to 62% of the screen, then the content scrolls.
    NSLayoutConstraint *fit=[scroll.heightAnchor constraintEqualToAnchor:content.heightAnchor constant:TIOSpace6];fit.priority=UILayoutPriorityDefaultLow; // below every compression resistance: the cap shrinks the scroll view, never the content
    [NSLayoutConstraint activateConstraints:@[
        [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.map.topAnchor constraintEqualToAnchor:self.view.topAnchor],[self.map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.backButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:TIOSpace2],[self.backButton.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.moreButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-TIOSpace2],[self.moreButton.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [top.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:TIOSpace4],[top.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-TIOSpace4],[top.topAnchor constraintEqualToAnchor:self.backButton.bottomAnchor constant:TIOSpace2],
        [self.results.leadingAnchor constraintEqualToAnchor:top.leadingAnchor],[self.results.trailingAnchor constraintEqualToAnchor:top.trailingAnchor],[self.results.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:TIOSpace2],[self.results.heightAnchor constraintEqualToConstant:280],
        [sheet.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[sheet.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[sheet.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sheet.topAnchor constraintGreaterThanOrEqualToAnchor:top.bottomAnchor constant:TIOSpace2],
        [scroll.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:sheet.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:sheet.safeAreaLayoutGuide.bottomAnchor constant:-TIOSpace2],fit,
        [scroll.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:.62],
        [content.leadingAnchor constraintEqualToAnchor:scrollContent.leadingAnchor constant:TIOSpace5],[content.trailingAnchor constraintEqualToAnchor:scrollContent.trailingAnchor constant:-TIOSpace5],
        [content.topAnchor constraintEqualToAnchor:scrollContent.topAnchor constant:TIOSpace6],[content.bottomAnchor constraintEqualToAnchor:scrollContent.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scrollFrame.widthAnchor constant:-2*TIOSpace5],
                [grabber.leadingAnchor constraintEqualToAnchor:sheet.leadingAnchor],[grabber.trailingAnchor constraintEqualToAnchor:sheet.trailingAnchor],[grabber.topAnchor constraintEqualToAnchor:sheet.topAnchor],[grabber.heightAnchor constraintEqualToConstant:TIOHitMin],
        [bar.centerXAnchor constraintEqualToAnchor:grabber.centerXAnchor],[bar.topAnchor constraintEqualToAnchor:grabber.topAnchor constant:TIOSpace2],[bar.widthAnchor constraintEqualToConstant:36],[bar.heightAnchor constraintEqualToConstant:5]]];
    self.pillWidth=[self.pillHolder.widthAnchor constraintLessThanOrEqualToAnchor:self.titleRow.widthAnchor multiplier:.55];self.pillWidth.active=YES;
    [self.pillHolder.widthAnchor constraintLessThanOrEqualToAnchor:self.titleRow.widthAnchor].active=YES;
    self.locator=[CLLocationManager new];self.locator.delegate=self;self.locator.desiredAccuracy=kCLLocationAccuracyBest;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(researchClosed) name:@"TIOResearchClosed" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(enterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    self.note=TIOText(@"nav.hint.search");[self adaptLayout];[self refresh];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{
    [super traitCollectionDidChange:previous];
    if(previous.preferredContentSizeCategory!=self.traitCollection.preferredContentSizeCategory){[self styleSegments:self.modeControl];[self adaptLayout];}
}
// At accessibility text sizes the pill drops under the title and the buttons stack.
- (void)adaptLayout{
    BOOL large=UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.titleRow.axis=large?UILayoutConstraintAxisVertical:UILayoutConstraintAxisHorizontal;self.titleRow.alignment=large?UIStackViewAlignmentFill:UIStackViewAlignmentTop;
    self.buttonRow.axis=large?UILayoutConstraintAxisVertical:UILayoutConstraintAxisHorizontal;self.buttonRow.distribution=UIStackViewDistributionFill;self.buttonRatio.active=!large;self.pillWidth.active=!large;
}
- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    // The pill's word wraps instead of truncating once it has a width to wrap to.
    UIStackView *pillStack=[self.pill isKindOfClass:UIStackView.class]?(UIStackView *)self.pill:nil;UILabel *word=[pillStack.arrangedSubviews.lastObject isKindOfClass:UILabel.class]?pillStack.arrangedSubviews.lastObject:nil;
    CGFloat room=MAX(0,CGRectGetWidth(self.pillHolder.bounds)-4*TIOSpace2-TIOSpace5);
    if(word&&room>0&&fabs(word.preferredMaxLayoutWidth-room)>.5){word.preferredMaxLayoutWidth=room;[word invalidateIntrinsicContentSize];[self.pill invalidateIntrinsicContentSize];}
    // Keep Apple's attribution and the compass clear of the floating cards.
    self.map.layoutMargins=UIEdgeInsetsMake(CGRectGetMaxY(self.topCard.frame),TIOSpace2,MAX(0,CGRectGetHeight(self.view.bounds)-CGRectGetMinY(self.sheet.frame)),TIOSpace2);
}
- (UIEdgeInsets)mapPadding{
    CGFloat top=200,bottom=260;
    if(CGRectGetHeight(self.view.bounds)>200){[self.view layoutIfNeeded];top=CGRectGetMaxY(self.topCard.frame)+TIOSpace5;bottom=CGRectGetHeight(self.view.bounds)-CGRectGetMinY(self.sheet.frame)+TIOSpace5;}
    return UIEdgeInsetsMake(top,40,bottom,40);
}
- (void)backTapped{
    UINavigationController *nav=self.navigationController;
    if(nav.viewControllers.count>1)[nav popViewControllerAnimated:YES];else if(self.presentingViewController)[self dismissViewControllerAnimated:YES completion:nil];
}
- (void)toggleSheet{[self setSheetCollapsed:!self.collapsed];}
- (void)grabberPan:(UIPanGestureRecognizer *)g{
    if(g.state!=UIGestureRecognizerStateEnded)return;
    CGFloat dy=[g translationInView:self.sheet].y,vy=[g velocityInView:self.sheet].y;
    if(dy>TIOSpace5||vy>300)[self setSheetCollapsed:YES];else if(dy<-TIOSpace5||vy<-300)[self setSheetCollapsed:NO];
}
- (void)setSheetCollapsed:(BOOL)collapsed{
    if(collapsed==self.collapsed)return;self.collapsed=collapsed;
    TIODesignAnimate(.25,^{[self applySheetVisibility];[self.view layoutIfNeeded];},nil);
    self.grabber.accessibilityLabel=TIOText(collapsed?@"nav.sheet.expand":@"nav.sheet.collapse");
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,nil);
}
- (void)applySheetVisibility{
    self.lensView.hidden=self.collapsed||!self.guide;self.detailLabel.hidden=self.collapsed||!self.detailLabel.text.length;
    self.glassesLabel.hidden=self.collapsed||!self.glassesLabel.text.length;
}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated]; // the map owns the top edge
    if(!self.timer){__weak typeof(self) weak=self;self.timer=[NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){[weak tick];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];}
    [self startLocating];
}
- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    if(self.isMovingFromParentViewController||self.navigationController.topViewController!=self)[self.navigationController setNavigationBarHidden:NO animated:animated];
}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    // A presented alert or the lock screen does not end navigation; leaving the panel does.
    if(!self.isMovingFromParentViewController&&!self.isBeingDismissed&&!self.navigationController.isBeingDismissed)return;
    TNVLifecycle(@"mapkit-panel-closed");[self stopNavigation:nil];[self.roadMap forgetSavedRoads];[self.timer invalidate];self.timer=nil;[self.locator stopUpdatingLocation];
}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)researchClosed{[self stopNavigation:TIOText(@"nav.note.ended")];}
- (void)alert:(NSString *)title message:(NSString *)message{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.ok") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}

#pragma mark Location
- (void)startLocating{
    CLAuthorizationStatus s=self.locator.authorizationStatus;
    if(s==kCLAuthorizationStatusNotDetermined){[self.locator requestWhenInUseAuthorization];return;}
    if(s==kCLAuthorizationStatusAuthorizedWhenInUse||s==kCLAuthorizationStatusAuthorizedAlways){self.map.showsUserLocation=YES;[self.locator startUpdatingLocation];}
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager{
    CLAuthorizationStatus s=manager.authorizationStatus;BOOL ok=s==kCLAuthorizationStatusAuthorizedWhenInUse||s==kCLAuthorizationStatusAuthorizedAlways;
    if(ok)[self startLocating];else if(s!=kCLAuthorizationStatusNotDetermined){self.map.showsUserLocation=NO;if(self.navigating&&!self.simulated)[self stopNavigation:TIOText(@"nav.note.locationOff")];}
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    CLLocation *l=locations.lastObject;if(!l||l.horizontalAccuracy<0||fabs(l.timestamp.timeIntervalSinceNow)>4)return;
    BOOL centerFirst=!self.fix;self.fix=l;
    if(centerFirst&&!self.destination)[self.map setRegion:MKCoordinateRegionMakeWithDistance(l.coordinate,1200,1200) animated:YES];
    if(centerFirst&&self.destination&&!self.guide&&!self.planning&&!self.navigating)[self plan]; // destination chosen before the first fix
    if(!self.navigating||self.simulated||self.arrived)return;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(l.horizontalAccuracy>50){if(!self.weakSince)self.weakSince=now;if(now-self.weakSince>5&&!self.weak){self.weak=YES;self.note=TIOText(@"nav.note.weak");[self refresh];}}
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
    MKLocalSearchCompletion *r=self.completer.results[p.row];c.textLabel.text=r.title;c.detailTextLabel.text=r.subtitle;TIODesignStyleRow(c);return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.row>=(NSInteger)self.completer.results.count)return;[self runSearch:[[MKLocalSearchRequest alloc]initWithCompletion:self.completer.results[p.row]]];}
- (void)runSearch:(MKLocalSearchRequest *)request{
    [self.search resignFirstResponder];self.results.hidden=YES;if(self.navigating){[self alert:TIOText(@"nav.alert.endFirst.title") message:TIOText(@"nav.alert.endFirst.dest")];return;}
    [[[MKLocalSearch alloc]initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error){
        MKMapItem *item=response.mapItems.firstObject;if(!item){[self alert:TIOText(@"nav.alert.noResults.title") message:TIOText(@"nav.alert.noResults.message")];return;}
        [self setDestination:item name:item.name?:TIOText(@"nav.dest.default")];
    }];
}
- (void)longPress:(UILongPressGestureRecognizer *)g{
    if(g.state!=UIGestureRecognizerStateBegan||self.navigating)return;
    CLLocationCoordinate2D c=[self.map convertPoint:[g locationInView:self.map] toCoordinateFromView:self.map];
    if(self.pickingStart){self.pickingStart=NO;self.simStart=c;self.hasSimStart=YES;self.sourceControl.selectedSegmentIndex=0;
        if(self.startPin)[self.map removeAnnotation:self.startPin];self.startPin=[MKPointAnnotation new];self.startPin.coordinate=c;self.startPin.title=TIOText(@"nav.pin.simStart");[self.map addAnnotation:self.startPin];
        if(self.destination)[self plan];else{self.note=TIOText(@"nav.note.startSet");[self refresh];}return;}
    [self setDestination:[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:c]] name:TIOText(@"nav.dest.pin")];
}
- (void)setDestination:(MKMapItem *)item name:(NSString *)name{
    self.destination=item;self.destinationName=name;self.search.text=name;
    if(self.destinationPin)[self.map removeAnnotation:self.destinationPin];self.destinationPin=[MKPointAnnotation new];self.destinationPin.coordinate=item.placemark.coordinate;self.destinationPin.title=name;[self.map addAnnotation:self.destinationPin];
    [self plan];
}
- (void)optionsChanged{
    if(self.navigating){self.modeControl.selectedSegmentIndex=self.mode;self.sourceControl.selectedSegmentIndex=self.simulated?0:1;[self alert:TIOText(@"nav.alert.endFirst.title") message:TIOText(@"nav.alert.endFirst.options")];return;}
    if(self.destination)[self plan];else[self refresh];
}

#pragma mark Routing
- (CLLocationCoordinate2D)originForSimulation:(BOOL)sim valid:(BOOL *)valid{
    if(sim&&self.hasSimStart){*valid=YES;return self.simStart;}
    *valid=self.fix&&fabs(self.fix.timestamp.timeIntervalSinceNow)<120;return self.fix.coordinate;
}
- (void)plan{
    BOOL sim=self.sourceControl.selectedSegmentIndex==0,valid=NO;CLLocationCoordinate2D from=[self originForSimulation:sim valid:&valid];
    if(!valid){self.note=sim?TIOText(@"nav.note.waitSim"):TIOText(@"nav.note.waitLive");[self refresh];return;}
    [self calculateFrom:from reroute:NO];
}
- (void)calculateFrom:(CLLocationCoordinate2D)from reroute:(BOOL)reroute{
    if(!self.destination)return;NSUInteger g=++self.generation;self.planning=!reroute;if(!reroute){self.route=nil;self.guide=nil;}
    MKDirectionsRequest *r=[MKDirectionsRequest new];r.source=[[MKMapItem alloc]initWithPlacemark:[[MKPlacemark alloc]initWithCoordinate:from]];r.destination=self.destination;
    r.transportType=Transport(reroute?self.mode:self.modeControl.selectedSegmentIndex);r.requestsAlternateRoutes=NO;
    if(!reroute){self.note=TIOText(@"nav.note.finding");[self refresh];}
    [[[MKDirections alloc]initWithRequest:r] calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response,NSError *error){
        if(g!=self.generation)return;MKRoute *route=response.routes.firstObject;TIOGuideRoute *guide=route?GuideRoute(route):nil;
        if(!guide){self.planning=NO;self.rerouting=NO;self.note=reroute?TIOText(@"nav.note.rerouteFail"):error.localizedDescription.length?[NSString stringWithFormat:FormatText(@"nav.note.noRouteWhy"),error.localizedDescription]:TIOText(@"nav.note.noRoute");[self refresh];return;}
        self.route=route;self.guide=guide;self.planning=NO;self.snapStep=0;
        // Save the street map along the whole route now (often still on Wi-Fi); a reroute adds its new corridor.
        if([NSUserDefaults.standardUserDefaults boolForKey:RoadsKey]){self.roadMap.allowNetwork=YES;if(!reroute&&!self.navigating)[self.roadMap forgetSavedRoads];[self.roadMap prefetchRoute:guide.points];}
        if(self.line)[self.map removeOverlay:self.line];self.line=route.polyline;[self.map addOverlay:self.line level:MKOverlayLevelAboveRoads];
        if(reroute){self.rerouting=NO;self.note=TIOText(@"nav.note.newRoute");}
        else{self.note=nil;[self.map setVisibleMapRect:self.line.boundingMapRect edgePadding:[self mapPadding] animated:YES];}
        [self refresh];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&(self.planning||self.rerouting)){self.planning=NO;self.rerouting=NO;self.note=TIOText(@"nav.note.timeout");[self refresh];}});
}
- (MKOverlayRenderer *)mapView:(MKMapView *)map rendererForOverlay:(id<MKOverlay>)overlay{
    if([overlay isKindOfClass:MKPolyline.class]){MKPolylineRenderer *r=[[MKPolylineRenderer alloc]initWithPolyline:(MKPolyline *)overlay];r.lineWidth=6;r.lineCap=kCGLineCapRound;r.lineJoin=kCGLineJoinRound;r.strokeColor=[TIODesignColor(TIODesignColorAccent) resolvedColorWithTraitCollection:self.traitCollection];return r;}
    return [[MKOverlayRenderer alloc]initWithOverlay:overlay];
}

#pragma mark Navigation
- (void)start{
    if(self.navigating||!self.guide||self.planning)return;BOOL sim=self.sourceControl.selectedSegmentIndex==0;
    if(!sim){CLAuthorizationStatus s=self.locator.authorizationStatus;if(s!=kCLAuthorizationStatusAuthorizedWhenInUse&&s!=kCLAuthorizationStatusAuthorizedAlways){[self alert:TIOText(@"nav.alert.location.title") message:TIOText(@"nav.alert.location.message")];return;}}
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
    if(sim){self.simMarker=[MKPointAnnotation new];self.simMarker.title=TIOText(@"nav.pin.simPosition");[self.map addAnnotation:self.simMarker];}
    else [self.map setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];
    self.note=!BackgroundLocation()?TIOText(@"nav.note.keepUnlocked"):sim?TIOText(@"nav.note.simulating"):TIOText(@"nav.note.navigating");[self refresh];
}
- (void)stopTapped{[self stopNavigation:self.navigating?TIOText(@"nav.note.ended"):nil];}
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
        self.simElapsed+=MAX(0,now-self.simLastTick);self.simLastTick=now;
        if(now-self.lastOffer>=0.2){TIOGuidePose p=TIOGuideSimulate(self.guide,self.simElapsed,SimSpeed(self.mode));self.simMarker.coordinate=CLLocationCoordinate2DMake(p.lat,p.lon);
            if(now-self.lastFollow>=1){self.lastFollow=now;[self.map setCenterCoordinate:self.simMarker.coordinate animated:YES];}
            [self updateAt:p.lat lon:p.lon course:p.heading speed:SimSpeed(self.mode) now:now];}
    }
    if(self.glassesStarted){NSDictionary *s=TDPPhoneNavigationStatus();if([s[@"failed"] boolValue]||(![s[@"active"] boolValue]&&![s[@"busy"] boolValue])){self.glassesStarted=NO;if(self.navigating&&!self.arrived)self.note=TIOText(@"nav.note.lost");}}
    if(self.openMapsPending&&(self.glassesStarted||(self.glassesTried&&!self.glassesStarted)||now-self.openMapsAt>8)){self.openMapsPending=NO;[self openAppleMaps];}
    if(now-self.lastLabel>=1){self.lastLabel=now;self.glassesLabel.text=[self glassesText];} // map-saving progress
    if(self.navigating&&now-self.lastTrace>=2)[self traceEvent:@"tick"];
    if(self.navigating&&now-self.lastTraceSave>=5)[self saveTrace];
    if(now-self.lastUI>=0.5&&!self.inBackground)[self refresh];
}
- (void)updateAt:(double)lat lon:(double)lon course:(double)course speed:(double)speed now:(NSTimeInterval)now{
    if(!self.navigating||self.arrived||!self.guide)return;self.lastOffer=now;
    TIOGuideSnapResult s=TIOGuideSnap(self.guide,lat,lon,self.snapStep);
    if(!self.simulated&&!self.rerouting&&TIOGuideShouldReroute(&_reroute,s.offRoute,now)){self.rerouting=YES;self.note=TIOText(@"nav.note.offRoute");[self calculateFrom:CLLocationCoordinate2DMake(lat,lon) reroute:YES];}
    if(s.offRoute<=TIOGuideOffRouteMeters)self.snapStep=s.step;
    BOOL arrive=TIOGuideArrived(self.guide,s,lat,lon)||(self.simulated&&TIOGuideSimulate(self.guide,self.simElapsed,SimSpeed(self.mode)).done);
    TIOGuideProgressResult p=TIOGuideProgress(self.guide,s);NSInteger icon=arrive?TIOGuideIconArrive:self.rerouting?TIOGuideIconUnknown:TIOGuideIcon(self.guide,s.step);
    NSString *turn=self.rerouting&&!arrive?@"Rerouting…":TIOGuideTurnText(icon); // glasses-facing wording, sent unchanged
    NSString *road=icon==TIOGuideIconArrive?(self.destinationName?:@""):self.rerouting?@"":TIOGuideManeuverRoad(self.guide,s.step);
    // Show the matched position when close to the route; the raw fix when clearly off it.
    BOOL matched=s.offRoute<=15;double plat=matched?s.lat:lat,plon=matched?s.lon:lon;
    NSArray *ahead=TIOGuideUpcoming(self.guide,s,512);
    NSMutableDictionary *f=[@{@"phase":@"navigating",@"icon":@(icon),@"meters":@(arrive?0:TIOGuideRoundMeters(p.toManeuver)),@"turn":turn,@"road":road,@"remainingMeters":@(arrive?0:TIOGuideRoundMeters(p.remainingMeters)),@"remainingSeconds":@(arrive?0:60*(long)ceil(p.remainingSeconds/60)),
        @"simulated":@(self.simulated),@"segment":@(s.step),@"observedAt":@(NSDate.date.timeIntervalSince1970),@"tnrSource":self.simulated?@"mapkit-simulation":@"mapkit-realtime"} mutableCopy];
    [f addEntriesFromDictionary:TNVNormalizeCoordinates(ahead)];
    f[@"navSpeed"]=@(isfinite(speed)&&speed>=0?speed:0);f[@"tnrLocation"]=@[@(plat),@(plon)];f[@"tnrLocationAt"]=@(self.simulated?now:now-MAX(0,-self.fix.timestamp.timeIntervalSinceNow));f[@"navHeading"]=@((unsigned)lround(TIOGuideHeading(course,speed,s.bearing))%360);
    f[@"tnrCurrentRoad"]=s.step>0?TIOGuideFullRoadName(self.guide.steps[s.step-1].instructions):(self.guide.initialRoad?:@"");
    f[@"tnrNextRoad"]=TIOGuideFullRoadName(self.guide.steps[s.step].instructions);
    f[@"tnrRoute"]=self.guide.points;f[@"tnrRouteStart"]=@(s.segment);
    NSDictionary *frame=[self.roadMap decorate:f coordinates:ahead];self.display=frame;
    if(!self.firstFrameAt)self.firstFrameAt=now;
    if(self.glassesStarted){TDPPhoneNavigationOffer(frame);self.offers++;}
    else if(!self.glassesTried&&(!self.roadMap.enabled||frame[@"tnrScene"]||now-self.firstFrameAt>5))[self startGlasses:frame];
    if(arrive)[self arriveWithFrame:frame];
}
- (void)startGlasses:(NSDictionary *)frame{
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;self.glassesTried=YES;
    NSString *busy=GlassesBusy();if(busy){self.note=[[busy stringByAppendingString:@" "] stringByAppendingString:TIOText(@"nav.busy.suffix")];return;}
    self.glassesStarted=TDPPhoneNavigationStart(frame);
    if(!self.glassesStarted)[self alert:TIOText(@"nav.alert.glasses.title") message:TIOText(@"nav.alert.glasses.message")];
}
- (void)arriveWithFrame:(NSDictionary *)frame{
    self.arrived=YES;self.note=[NSString stringWithFormat:FormatText(@"nav.note.arrived"),self.destinationName?:TIOText(@"nav.dest.yours")];[self refresh];NSUInteger g=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&self.arrived)[self stopNavigation:self.note];});
}

#pragma mark Apple Maps hand-off
- (void)appleMapsTapped{
    if(self.navigating){[self openAppleMaps];return;}
    if(!self.guide||self.planning)return;
    // Start first: the glasses session can only open while this app is in front.
    self.sourceControl.selectedSegmentIndex=1;[self start];if(!self.navigating)return;
    self.openMapsPending=YES;self.openMapsAt=NSProcessInfo.processInfo.systemUptime;self.note=TIOText(@"nav.note.connectingMaps");[self refresh];
}
- (void)openAppleMaps{
    if(!self.destination)return;NSString *mode=self.mode==ModeDrive?MKLaunchOptionsDirectionsModeDriving:self.mode==ModeCycle?MKLaunchOptionsDirectionsModeCycling:MKLaunchOptionsDirectionsModeWalking;
    [self traceEvent:@"open-apple-maps"];
    BOOL ok=[MKMapItem openMapsWithItems:@[[MKMapItem mapItemForCurrentLocation],self.destination] launchOptions:@{MKLaunchOptionsDirectionsModeKey:mode}];
    if(!ok)[self alert:TIOText(@"nav.alert.maps.title") message:TIOText(@"nav.alert.maps.message")];
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
- (NSString *)turnTextFor:(NSDictionary *)d{
    // The glasses frame carries English wording; the screen shows the same maneuver in the UI language.
    if([d[@"turn"] isEqual:@"Rerouting…"])return TIOText(@"nav.turn.rerouting");
    return d[@"icon"]?TurnText([d[@"icon"] integerValue]):(d[@"turn"]?:TIOText(@"nav.turn.follow"));
}
- (NSString *)tripLineForSeconds:(double)sec meters:(double)meters{
    return [NSString stringWithFormat:@"%@ · %@ · %@",Minutes(sec),Meters(meters),Clock(sec)];
}
// What the lens preview shows: the live maneuver while navigating, otherwise the first maneuver of the planned route.
- (NSDictionary *)lensModel{
    if(!self.guide)return nil;
    NSDictionary *d=self.display;NSInteger icon=TIOGuideIconUnknown;NSString *turn=@"",*road=@"",*passing=@"";double meters=0,seconds=0,total=0;NSArray *here=nil;
    if(self.navigating&&d){
        icon=[d[@"icon"] integerValue];turn=[self turnTextFor:d];road=d[@"road"]?:@"";passing=d[@"tnrPassing"]?:@"";meters=[d[@"meters"] doubleValue];
        seconds=[d[@"remainingSeconds"] doubleValue];total=[d[@"remainingMeters"] doubleValue];here=d[@"tnrLocation"];
    }else{
        NSArray *points=self.guide.points;
        if(self.readyGuide!=self.guide||!self.readyLens){
            NSMutableDictionary *first=[NSMutableDictionary new];
            if(points.count){
                TIOGuideSnapResult snap=TIOGuideSnap(self.guide,[points[0][0] doubleValue],[points[0][1] doubleValue],0);
                TIOGuideProgressResult progress=TIOGuideProgress(self.guide,snap);
                first[@"icon"]=@(TIOGuideIcon(self.guide,snap.step));first[@"road"]=TIOGuideManeuverRoad(self.guide,snap.step)?:@"";first[@"meters"]=@(progress.toManeuver);
            }
            self.readyLens=first;self.readyGuide=self.guide;
        }
        icon=[self.readyLens[@"icon"] integerValue];turn=TurnText(icon);road=self.readyLens[@"road"]?:@"";meters=[self.readyLens[@"meters"] doubleValue];
        seconds=self.route.expectedTravelTime;total=self.route.distance;
    }
    NSString *distance=Meters(meters),*trip=[self tripLineForSeconds:seconds meters:total];
    NSString *onto=road.length?[NSString stringWithFormat:FormatText(@"nav.lens.onto"),road]:@"";
    NSMutableArray *spoken=[NSMutableArray arrayWithObjects:turn,distance,nil];if(onto.length)[spoken addObject:onto];if(passing.length)[spoken addObject:passing];
    NSMutableDictionary *m=[@{@"passing":passing,@"trip":trip,@"icon":@(icon),@"distance":distance,@"turn":turn,@"road":onto,@"summary":[spoken componentsJoinedByString:@", "]} mutableCopy];
    NSArray *route=self.guide.points;if(route.count)m[@"route"]=route;if(here.count==2)m[@"here"]=here;
    return m;
}
- (void)updateGlassesPill{
    // The pill shows a short word (it must fit at large text sizes); VoiceOver gets the full phrase.
    TIODesignStatus status;NSString *word,*spoken;
    if([TDPPhoneNavigationStatus()[@"active"] boolValue]){status=TIODesignStatusOk;word=TIOText(@"nav.glasses.connected.short");spoken=TIOText(@"nav.glasses.connected");}
    else if(self.navigating){if(self.glassesTried){status=TIODesignStatusWarn;word=TIOText(@"nav.glasses.notConnected.short");spoken=TIOText(@"nav.glasses.notConnected");}else{status=TIODesignStatusNeutral;word=TIOText(@"nav.glasses.connecting.short");spoken=TIOText(@"nav.glasses.connecting");}}
    else{status=TIODesignStatusNeutral;word=TIOText(@"nav.glasses.onStart");spoken=word;}
    NSString *key=[NSString stringWithFormat:@"%ld|%@",(long)status,word];
    if([key isEqual:self.pillKey])return;self.pillKey=key;
    [self.pill removeFromSuperview];UIView *pill=TIODesignStatusPill(status,word);pill.translatesAutoresizingMaskIntoConstraints=NO;pill.accessibilityLabel=spoken;self.pill=pill;[self.pillHolder addSubview:pill];
    [NSLayoutConstraint activateConstraints:@[[pill.leadingAnchor constraintEqualToAnchor:self.pillHolder.leadingAnchor],[pill.trailingAnchor constraintEqualToAnchor:self.pillHolder.trailingAnchor],[pill.topAnchor constraintEqualToAnchor:self.pillHolder.topAnchor],[pill.bottomAnchor constraintEqualToAnchor:self.pillHolder.bottomAnchor]]];
}
- (void)refresh{
    self.lastUI=NSProcessInfo.processInfo.systemUptime;BOOL sim=self.sourceControl.selectedSegmentIndex==0;NSDictionary *d=self.display;
    if(self.navigating&&d){
        self.titleLabel.text=[NSString stringWithFormat:@"%@ · %@",[self turnTextFor:d],Meters([d[@"meters"] doubleValue])];
        NSString *road=d[@"road"];self.detailLabel.text=self.note?:(road.length?road:(self.simulated?TIOText(@"nav.detail.simulatedRoute"):TIOText(@"nav.turn.follow")));
        double sec=[d[@"remainingSeconds"] doubleValue];self.metricsLabel.text=[self metricsForSeconds:sec meters:[d[@"remainingMeters"] doubleValue]];
    }else if(self.guide&&!self.navigating){
        self.titleLabel.text=self.destinationName?:TIOText(@"nav.title.ready");self.detailLabel.text=self.note?:(sim?(self.hasSimStart?TIOText(@"nav.detail.simStart"):TIOText(@"nav.detail.simHere")):TIOText(@"nav.detail.live"));
        self.metricsLabel.text=[self metricsForSeconds:self.route.expectedTravelTime meters:self.route.distance];
    }else{self.titleLabel.text=self.destinationName?:TIOText(@"nav.search.placeholder");self.detailLabel.text=self.note?:@"";self.metricsLabel.text=nil;}
    self.metricsLabel.hidden=!self.metricsLabel.text.length;
    UIButtonConfiguration *c=self.startButton.configuration;c.title=self.planning?TIOText(@"nav.start.finding"):sim?TIOText(@"nav.start.simulation"):TIOText(@"nav.start");self.startButton.configuration=c;
    self.startButton.hidden=self.navigating;self.startButton.enabled=self.guide&&!self.planning;self.stopButton.hidden=!self.navigating;
    // Apple Maps only follows your real position, so the hand-off is for live routes.
    self.appleMapsButton.hidden=self.navigating?self.simulated:sim;self.appleMapsButton.enabled=self.navigating||(self.guide&&!self.planning);
    self.modeControl.enabled=!self.navigating;self.search.userInteractionEnabled=!self.navigating;
    self.glassesLabel.text=[self glassesText];[self updateGlassesPill];
    NSDictionary *lens=[self lensModel];self.lensView.model=lens;
    TIODesignStyleLensPreview(self.lensView,lens?[NSString stringWithFormat:FormatText(@"nav.lens.a11y"),lens[@"summary"]]:@"");
    self.grabber.accessibilityLabel=TIOText(self.collapsed?@"nav.sheet.expand":@"nav.sheet.collapse");
    [self applySheetVisibility];[self refreshMenu];
}
- (NSString *)metricsForSeconds:(double)sec meters:(double)meters{
    return [NSString stringWithFormat:@"%@ · %@ · %@",Minutes(sec),Meters(meters),[NSString stringWithFormat:FormatText(@"nav.metrics.arrive"),Clock(sec)]];
}
// Road-map detail under the footnote: how the street map for the glasses is doing. Empty when roads are off.
- (NSString *)glassesText{
    NSDictionary *s=TDPPhoneNavigationStatus();NSDictionary *c=self.roadMap.coverageStatus,*t=c[@"tiles"];NSUInteger saved=[t[@"saved"] unsignedIntegerValue],wanted=[t[@"wanted"] unsignedIntegerValue];
    NSMutableArray *parts=[NSMutableArray new];
    if([s[@"active"] boolValue])[parts addObject:[NSString stringWithFormat:FormatText(@"nav.glasses.stats"),s[@"snapshots"]?:@0,s[@"maps"]?:@0]];
    if(self.roadMap.enabled)[parts addObject:[c[@"features"] unsignedIntegerValue]?TIOText(@"nav.roads.on"):TIOText(@"nav.roads.waiting")];
    if(wanted>saved){
        NSString *saving=[NSString stringWithFormat:FormatText(@"nav.roads.saving"),(unsigned long)saved,(unsigned long)wanted];
        [parts addObject:[t[@"failed"] unsignedIntegerValue]?[NSString stringWithFormat:@"%@, %@",saving,TIOText(@"nav.roads.noSignal")]:saving];
    }else if(wanted)[parts addObject:TIOText(@"nav.roads.saved")];
    return [parts componentsJoinedByString:@" · "];
}
// Simulate/Live, nearby roads and the glasses controls live in the ⋯ menu. It is rebuilt only when what it
// offers changes, never while it is open for the same state.
- (void)refreshMenu{
    BOOL sim=self.sourceControl.selectedSegmentIndex==0,roads=[NSUserDefaults.standardUserDefaults boolForKey:RoadsKey];
    NSString *key=[NSString stringWithFormat:@"%d%d%d%d%d%d",sim,self.navigating,self.route!=nil,self.hasSimStart,roads,TNVAlways()];
    if([key isEqual:self.menuKey])return;self.menuKey=key;
    __weak typeof(self) me=self;
    UIAction *simulate=[UIAction actionWithTitle:TIOText(@"nav.source.simulate") image:[UIImage systemImageNamed:@"play.circle"] identifier:nil handler:^(UIAction *a){me.sourceControl.selectedSegmentIndex=0;[me optionsChanged];}];
    UIAction *live=[UIAction actionWithTitle:TIOText(@"nav.source.live") image:[UIImage systemImageNamed:@"location"] identifier:nil handler:^(UIAction *a){me.sourceControl.selectedSegmentIndex=1;[me optionsChanged];}];
    simulate.state=sim?UIMenuElementStateOn:UIMenuElementStateOff;live.state=sim?UIMenuElementStateOff:UIMenuElementStateOn;
    if(self.navigating){simulate.attributes=live.attributes=UIMenuElementAttributesDisabled;}
    UIMenu *source=[UIMenu menuWithTitle:TIOText(@"nav.source.title") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[simulate,live]];
    NSMutableArray *glasses=[NSMutableArray new];
    [glasses addObject:[UIAction actionWithTitle:TIOText(roads?@"nav.menu.roadsOff":@"nav.menu.roadsOn") image:[UIImage systemImageNamed:@"road.lanes"] identifier:nil handler:^(UIAction *a){[me toggleRoads];}]];
    [glasses addObject:[UIAction actionWithTitle:TIOText(TNVAlways()?@"nav.menu.displaySleep":@"nav.menu.displayOn") image:[UIImage systemImageNamed:@"eyeglasses"] identifier:nil handler:^(UIAction *a){TNVSetAlways(!TNVAlways());me.menuKey=nil;[me refresh];}]];
    if(self.navigating)[glasses addObject:[UIAction actionWithTitle:TIOText(@"nav.menu.reconnect") image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"] identifier:nil handler:^(UIAction *a){[me reconnect];}]];
    NSMutableArray *route=[NSMutableArray new];
    if(!self.navigating){
        [route addObject:[UIAction actionWithTitle:TIOText(@"nav.menu.setStart") image:[UIImage systemImageNamed:@"mappin.and.ellipse"] identifier:nil handler:^(UIAction *a){me.pickingStart=YES;me.note=TIOText(@"nav.note.pickStart");[me refresh];}]];
        if(self.hasSimStart)[route addObject:[UIAction actionWithTitle:TIOText(@"nav.menu.simHere") image:[UIImage systemImageNamed:@"location.circle"] identifier:nil handler:^(UIAction *a){me.hasSimStart=NO;if(me.startPin)[me.map removeAnnotation:me.startPin];me.startPin=nil;if(me.destination)[me plan];}]];
    }
    if(self.route)[route addObject:[UIAction actionWithTitle:TIOText(@"nav.steps.title") image:[UIImage systemImageNamed:@"list.number"] identifier:nil handler:^(UIAction *a){[me showSteps];}]];
    [route addObject:[UIAction actionWithTitle:TIOText(@"nav.menu.notes") image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(UIAction *a){[me alert:TIOText(@"nav.options.title") message:TIOText(@"nav.options.message")];}]];
    self.moreButton.menu=[UIMenu menuWithTitle:TIOText(@"nav.options.title") children:@[source,[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:glasses],[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:route]]];
}
- (void)toggleRoads{
    NSUserDefaults *u=NSUserDefaults.standardUserDefaults;
    if([u boolForKey:RoadsKey]){[u setBool:NO forKey:RoadsKey];self.roadMap.enabled=NO;self.roadMap.allowNetwork=NO;[self.roadMap forgetSavedRoads];[self refresh];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:TIOText(@"nav.roads.title") message:TIOText(@"nav.roads.message") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:TIOText(@"nav.roads.allow") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[u setBool:YES forKey:RoadsKey];self.roadMap.enabled=YES;self.roadMap.allowNetwork=YES;if(self.guide)[self.roadMap prefetchRoute:self.guide.points];[self refresh];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)reconnect{
    if([TDPPhoneNavigationStatus()[@"busy"] boolValue]){[self alert:TIOText(@"nav.alert.busy.title") message:TIOText(@"nav.alert.busy.message")];return;}
    if([TDPPhoneNavigationStatus()[@"active"] boolValue])TDPPhoneNavigationStop();
    self.glassesStarted=NO;self.glassesTried=NO;self.firstFrameAt=0;self.note=TIOText(@"nav.note.reconnecting");[self refresh];
}
- (void)showSteps{
    NSMutableArray *lines=[NSMutableArray new];
    for(MKRouteStep *s in self.route.steps){if(!s.instructions.length)continue;[lines addObject:[NSString stringWithFormat:@"%lu. %@ · %@",(unsigned long)lines.count+1,s.instructions,Meters(s.distance)]];if(lines.count>=40)break;}
    [self alert:TIOText(@"nav.steps.title") message:lines.count?[lines componentsJoinedByString:@"\n"]:TIOText(@"nav.steps.none")];
}
@end

UIViewController *TIOMapKitNavigationController(void){return [TIOMapKitNavigationPanel new];}
