#import <Foundation/Foundation.h>
// Provider-neutral guidance over [lat,lon] polylines. Foundation only: MapKit
// conversion lives in MapKitNavigationUI.m so this file stays unit-testable.
// Icons use the AMap numbering already mapped to TNIcon by TNVScene.
enum {TIOGuideIconUnknown=0,TIOGuideIconLeft=2,TIOGuideIconRight=3,TIOGuideIconSlightLeft=4,TIOGuideIconSlightRight=5,TIOGuideIconSharpLeft=6,TIOGuideIconSharpRight=7,TIOGuideIconUTurn=8,TIOGuideIconStraight=9,TIOGuideIconRoundabout=11,TIOGuideIconArrive=15};
FOUNDATION_EXPORT const double TIOGuideOffRouteMeters,TIOGuideArriveMeters;

@interface TIOGuideStep : NSObject
@property(readonly) NSArray<NSArray<NSNumber *> *> *points;
@property(readonly) NSString *instructions;
+ (instancetype)stepWithPoints:(NSArray *)points instructions:(NSString *)instructions;
@end

// A step's instructions describe the maneuver at its start; its polyline is the
// travel after that maneuver. While on step k, the next maneuver is step k+1.
@interface TIOGuideRoute : NSObject
@property(readonly) NSArray<TIOGuideStep *> *steps;
@property(readonly) double totalMeters,expectedSeconds;
@property(readonly) NSArray<NSArray<NSNumber *> *> *points;
+ (instancetype)routeWithSteps:(NSArray<TIOGuideStep *> *)steps expectedSeconds:(double)seconds;
@end

typedef struct {NSInteger step;NSUInteger segment;double offRoute,along,lat,lon,bearing;} TIOGuideSnapResult;
typedef struct {double toManeuver,remainingMeters,remainingSeconds;} TIOGuideProgressResult;
typedef struct {double lat,lon,heading;BOOL done;} TIOGuidePose;
typedef struct {unsigned strikes,count;double lastAt;} TIOGuideRerouteState;

double TIOGuideDistance(double lat1,double lon1,double lat2,double lon2);
// Searches hintStep and the next step; the full route only when that window is off-route.
TIOGuideSnapResult TIOGuideSnap(TIOGuideRoute *route,double lat,double lon,NSInteger hintStep);
TIOGuideProgressResult TIOGuideProgress(TIOGuideRoute *route,TIOGuideSnapResult snap);
// Snapped point through the end of the next step, capped at max; always >=2 points.
NSArray<NSArray<NSNumber *> *> *TIOGuideUpcoming(TIOGuideRoute *route,TIOGuideSnapResult snap,NSUInteger max);
// Icon for the maneuver at the end of step k (arrive on the last step).
NSInteger TIOGuideIcon(TIOGuideRoute *route,NSInteger step);
NSString *TIOGuideTurnText(NSInteger icon);
NSString *TIOGuideRoadName(NSString *instructions);
// Road entered at the end of step k. MapKit step text describes the maneuver at the end of the step's polyline.
NSString *TIOGuideManeuverRoad(TIOGuideRoute *route,NSInteger k);
NSString *TIOGuideAbbreviate(NSString *name);
double TIOGuideHeading(double course,double speed,double segmentBearing);
// Display-sized distance steps, so the glasses get a new number only when it visibly changes.
long TIOGuideRoundMeters(double meters);
TIOGuideRerouteState TIOGuideRerouteInitial(void);
BOOL TIOGuideShouldReroute(TIOGuideRerouteState *state,double offRoute,double now);
BOOL TIOGuideArrived(TIOGuideRoute *route,TIOGuideSnapResult snap,double lat,double lon);
TIOGuidePose TIOGuideSimulate(TIOGuideRoute *route,double elapsed,double metersPerSecond);
