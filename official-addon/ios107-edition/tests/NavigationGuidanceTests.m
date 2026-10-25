#import "NavigationGuidance.h"
#include <assert.h>
#include <math.h>
static const double Lat0=37.7749,Lon0=-122.4194;
static NSArray *P(double east,double north){return @[@(Lat0+north/111319.49),@(Lon0+east/(111319.49*cos(Lat0*M_PI/180)))];}
static TIOGuideStep *Step(NSArray *points,NSString *text){return [TIOGuideStep stepWithPoints:points instructions:text];}
static BOOL Near(double a,double b,double tolerance){return fabs(a-b)<=tolerance;}
static TIOGuideRoute *Turn(double degrees,NSString *text){
    double r=degrees*M_PI/180;
    return [TIOGuideRoute routeWithSteps:@[Step(@[P(0,0),P(0,100)],@"Head north"),Step(@[P(0,100),P(100*sin(r),100+100*cos(r))],text)] expectedSeconds:200];
}
int main(void){@autoreleasepool{
    // North 200 m, east 150 m, north 100 m; a zero-length MapKit start step is dropped.
    TIOGuideRoute *route=[TIOGuideRoute routeWithSteps:@[Step(@[P(0,0)],@""),Step(@[P(0,0),P(0,50),P(0,100),P(0,150),P(0,200)],@"Head north on Market Street"),Step(@[P(0,200),P(150,200)],@"Turn right onto Mission Street"),Step(@[P(150,200),P(150,300)],@"Turn left onto North 3rd Street toward Downtown")] expectedSeconds:450];
    assert(route&&route.steps.count==3&&route.points.count==7&&Near(route.totalMeters,450,1));
    assert(![TIOGuideRoute routeWithSteps:@[Step(@[P(0,0)],@"")] expectedSeconds:10]);

    TIOGuideSnapResult s=TIOGuideSnap(route,[P(5,100)[0] doubleValue],[P(5,100)[1] doubleValue],0);
    assert(s.step==0&&Near(s.offRoute,5,0.5)&&Near(s.along,100,0.5)&&Near(s.bearing,0,1));
    TIOGuideProgressResult g=TIOGuideProgress(route,s);
    assert(Near(g.toManeuver,100,0.5)&&Near(g.remainingMeters,350,0.5)&&Near(g.remainingSeconds,350,0.5));
    s=TIOGuideSnap(route,[P(60,205)[0] doubleValue],[P(60,205)[1] doubleValue],0);assert(s.step==1&&Near(s.along,260,0.5)&&Near(s.bearing,90,1));
    // Outside the hinted window: falls back to the full route instead of reporting off-route.
    s=TIOGuideSnap(route,[P(150,280)[0] doubleValue],[P(150,280)[1] doubleValue],0);assert(s.step==2&&s.offRoute<0.5);
    // Inside the window: the hint keeps the result on the hinted steps.
    s=TIOGuideSnap(route,[P(10,190)[0] doubleValue],[P(10,190)[1] doubleValue],1);assert(s.step==1&&Near(s.offRoute,10,0.5));
    s=TIOGuideSnap(route,[P(300,0)[0] doubleValue],[P(300,0)[1] doubleValue],1);assert(s.offRoute>100);

    s=TIOGuideSnap(route,[P(0,100)[0] doubleValue],[P(0,100)[1] doubleValue],0);
    NSArray *ahead=TIOGuideUpcoming(route,s,512);assert(ahead.count==4);
    assert(TIOGuideDistance([ahead[0][0] doubleValue],[ahead[0][1] doubleValue],[P(0,100)[0] doubleValue],[P(0,100)[1] doubleValue])<0.5);
    assert([ahead.lastObject isEqual:route.points[5]]);assert(TIOGuideUpcoming(route,s,3).count==3);
    s=TIOGuideSnap(route,[P(150,300)[0] doubleValue],[P(150,300)[1] doubleValue],2);ahead=TIOGuideUpcoming(route,s,512);
    assert(ahead.count==2&&[ahead[1] isEqual:route.points.lastObject]);

    assert(TIOGuideIcon(route,0)==TIOGuideIconRight&&TIOGuideIcon(route,1)==TIOGuideIconLeft&&TIOGuideIcon(route,2)==TIOGuideIconArrive&&TIOGuideIcon(route,-1)==TIOGuideIconUnknown);
    NSDictionary *bands=@{@10:@(TIOGuideIconStraight),@(-10):@(TIOGuideIconStraight),@45:@(TIOGuideIconSlightRight),@(-45):@(TIOGuideIconSlightLeft),@90:@(TIOGuideIconRight),@(-90):@(TIOGuideIconLeft),@150:@(TIOGuideIconSharpRight),@(-150):@(TIOGuideIconSharpLeft),@178:@(TIOGuideIconUTurn)};
    for(NSNumber *deg in bands)assert(TIOGuideIcon(Turn(deg.doubleValue,@"Continue"),0)==[bands[deg] integerValue]);
    assert(TIOGuideIcon(Turn(30,@"At the roundabout, take the 2nd exit onto Oak Road"),0)==TIOGuideIconRoundabout);
    assert(TIOGuideIcon(Turn(10,@"Make a U-turn"),0)==TIOGuideIconUTurn);
    assert([TIOGuideTurnText(TIOGuideIconRight) isEqual:@"Turn right"]&&[TIOGuideTurnText(TIOGuideIconArrive) isEqual:@"Arrive"]&&[TIOGuideTurnText(0) isEqual:@"Follow the route"]);
    for(NSInteger icon=0;icon<32;icon++)assert([TIOGuideTurnText(icon) lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<48);

    assert([TIOGuideRoadName(@"Turn right onto Mission Street") isEqual:@"Mission St"]);
    assert([TIOGuideRoadName(@"Turn left onto North 3rd Street toward Downtown") isEqual:@"N 3rd St"]);
    assert([TIOGuideRoadName(@"Continue on US-101 South.") isEqual:@"US-101 S"]);
    assert([TIOGuideRoadName(@"Arrive at the destination") isEqual:@""]&&[TIOGuideRoadName(@"Take exit 4A") isEqual:@""]&&[TIOGuideRoadName(nil) isEqual:@""]);
    assert([TIOGuideAbbreviate(@"South") isEqual:@"South"]&&[TIOGuideAbbreviate(@"Broadway") isEqual:@"Broadway"]&&[TIOGuideAbbreviate(@"Martin Luther King Jr Boulevard") isEqual:@"Martin Luther King Jr Blvd"]);

    assert(TIOGuideHeading(-1,5,90)==90&&TIOGuideHeading(180,0.5,90)==90&&TIOGuideHeading(180,5,90)==180&&TIOGuideHeading(NAN,5,450)==90);

    assert(TIOGuideRoundMeters(-3)==0&&TIOGuideRoundMeters(NAN)==0&&TIOGuideRoundMeters(42)==40&&TIOGuideRoundMeters(43)==45&&TIOGuideRoundMeters(347)==350&&TIOGuideRoundMeters(730)==750&&TIOGuideRoundMeters(1249)==1200&&TIOGuideRoundMeters(990)==1000);
    TIOGuideRerouteState r=TIOGuideRerouteInitial();
    assert(!TIOGuideShouldReroute(&r,50,0)&&!TIOGuideShouldReroute(&r,50,1)&&TIOGuideShouldReroute(&r,50,2));
    for(int t=3;t<=6;t++)assert(!TIOGuideShouldReroute(&r,50,t)); // 30 s spacing
    assert(!TIOGuideShouldReroute(&r,5,7)&&!TIOGuideShouldReroute(&r,50,33)&&!TIOGuideShouldReroute(&r,50,34)&&TIOGuideShouldReroute(&r,50,35)&&r.count==2);
    r.count=10;r.lastAt=-INFINITY;for(int t=0;t<5;t++)assert(!TIOGuideShouldReroute(&r,50,1000+t)); // session cap

    s=TIOGuideSnap(route,[P(150,290)[0] doubleValue],[P(150,290)[1] doubleValue],2);assert(TIOGuideArrived(route,s,[P(150,290)[0] doubleValue],[P(150,290)[1] doubleValue]));
    s=TIOGuideSnap(route,[P(150,260)[0] doubleValue],[P(150,260)[1] doubleValue],2);assert(!TIOGuideArrived(route,s,[P(150,260)[0] doubleValue],[P(150,260)[1] doubleValue]));
    s=TIOGuideSnap(route,[P(0,10)[0] doubleValue],[P(0,10)[1] doubleValue],0);assert(!TIOGuideArrived(route,s,[P(150,300)[0] doubleValue],[P(150,300)[1] doubleValue]));

    TIOGuidePose pose=TIOGuideSimulate(route,0,1.4);assert(!pose.done&&Near(pose.heading,0,1)&&TIOGuideDistance(pose.lat,pose.lon,Lat0,Lon0)<0.5);
    pose=TIOGuideSimulate(route,250/1.4,1.4);assert(!pose.done&&Near(pose.heading,90,1)&&TIOGuideDistance(pose.lat,pose.lon,[P(50,200)[0] doubleValue],[P(50,200)[1] doubleValue])<0.5);
    pose=TIOGuideSimulate(route,1000,1.4);assert(pose.done&&TIOGuideDistance(pose.lat,pose.lon,[route.points.lastObject[0] doubleValue],[route.points.lastObject[1] doubleValue])<0.01);
    pose=TIOGuideSimulate(route,NAN,1.4);assert(!pose.done&&TIOGuideDistance(pose.lat,pose.lon,Lat0,Lon0)<0.5);
    puts("PASS guidance: junction dedupe, windowed snap with full-route fallback, progress/ETA, >=2 upcoming points, icon bands, roundabout/U-turn text, English turn text, road names/abbreviation, heading fallback, display distance steps, reroute strikes/spacing/cap, arrival, simulation");
}return 0;}
