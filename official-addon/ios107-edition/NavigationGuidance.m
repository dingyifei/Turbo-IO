#import "NavigationGuidance.h"
#include <math.h>
const double TIOGuideOffRouteMeters=40,TIOGuideArriveMeters=25;
static const double MetersPerDegree=111319.49;
static double Bearing(double lat1,double lon1,double lat2,double lon2){double x=(lon2-lon1)*cos((lat1+lat2)*M_PI/360),y=lat2-lat1;double b=atan2(x,y)*180/M_PI;return b<0?b+360:b;}
static double Delta(double from,double to){double d=fmod(to-from+540,360)-180;return d==-180?180:d;}
double TIOGuideDistance(double lat1,double lon1,double lat2,double lon2){double x=(lon2-lon1)*MetersPerDegree*cos((lat1+lat2)*M_PI/360),y=(lat2-lat1)*MetersPerDegree;return hypot(x,y);}
static BOOL LatLon(id p){return [p isKindOfClass:NSArray.class]&&[p count]==2&&[p[0] isKindOfClass:NSNumber.class]&&[p[1] isKindOfClass:NSNumber.class]&&isfinite([p[0] doubleValue])&&isfinite([p[1] doubleValue])&&fabs([p[0] doubleValue])<=85&&fabs([p[1] doubleValue])<=180;}

@interface TIOGuideRoute()
@property(readonly) const double *lat,*lon,*cum;
- (NSUInteger)startOf:(NSInteger)step;
- (NSUInteger)endOf:(NSInteger)step;
- (NSInteger)stepForSegment:(NSUInteger)segment;
- (TIOGuidePose)poseAt:(double)meters;
@end

@implementation TIOGuideStep
+ (instancetype)stepWithPoints:(NSArray *)points instructions:(NSString *)instructions{
    TIOGuideStep *s=[self new];s->_points=[points copy]?:@[];s->_instructions=[instructions isKindOfClass:NSString.class]?[instructions copy]:@"";return s;
}
@end

@implementation TIOGuideRoute{
    NSMutableData *_lat,*_lon,*_cum,*_start,*_end;
}
+ (instancetype)routeWithSteps:(NSArray<TIOGuideStep *> *)input expectedSeconds:(double)seconds{
    TIOGuideRoute *r=[self new];NSMutableArray *steps=[NSMutableArray new],*points=[NSMutableArray new];
    NSMutableData *lat=[NSMutableData new],*lon=[NSMutableData new],*start=[NSMutableData new];
    for(TIOGuideStep *step in input){
        NSUInteger first=NSNotFound,added=0;
        for(NSArray *p in step.points){
            if(!LatLon(p))continue;double a=[p[0] doubleValue],o=[p[1] doubleValue];
            // Consecutive steps share their junction point; keep one copy.
            if(points.count&&TIOGuideDistance(a,o,[points.lastObject[0] doubleValue],[points.lastObject[1] doubleValue])<0.5){if(first==NSNotFound)first=points.count-1;continue;}
            if(first==NSNotFound)first=points.count;
            [points addObject:@[@(a),@(o)]];[lat appendBytes:&a length:sizeof a];[lon appendBytes:&o length:sizeof o];added++;
        }
        if(!added||points.count<2)continue; // Zero-length steps carry no geometry.
        [steps addObject:step];[start appendBytes:&first length:sizeof first];
    }
    if(steps.count<1||points.count<2)return nil;
    NSUInteger n=points.count,k=steps.count;const double *la=lat.bytes,*lo=lon.bytes;NSMutableData *cum=[NSMutableData dataWithLength:n*sizeof(double)];double *c=cum.mutableBytes;
    for(NSUInteger i=1;i<n;i++)c[i]=c[i-1]+TIOGuideDistance(la[i-1],lo[i-1],la[i],lo[i]);
    NSMutableData *end=[NSMutableData dataWithLength:k*sizeof(NSUInteger)];NSUInteger *e=end.mutableBytes;const NSUInteger *s=start.bytes;
    for(NSUInteger i=0;i<k;i++)e[i]=i+1<k?s[i+1]:n-1;
    r->_steps=steps;r->_points=points;r->_lat=lat;r->_lon=lon;r->_cum=cum;r->_start=start;r->_end=end;r->_totalMeters=c[n-1];r->_expectedSeconds=isfinite(seconds)&&seconds>0?seconds:0;return r;
}
- (const double *)lat{return _lat.bytes;}
- (const double *)lon{return _lon.bytes;}
- (const double *)cum{return _cum.bytes;}
- (NSUInteger)startOf:(NSInteger)step{return ((const NSUInteger *)_start.bytes)[step];}
- (NSUInteger)endOf:(NSInteger)step{return ((const NSUInteger *)_end.bytes)[step];}
- (NSInteger)stepForSegment:(NSUInteger)segment{for(NSInteger k=(NSInteger)_steps.count-1;k>=0;k--)if([self startOf:k]<=segment)return k;return 0;}
- (TIOGuidePose)poseAt:(double)meters{
    const double *la=self.lat,*lo=self.lon,*c=self.cum;NSUInteger n=_points.count,lo_=0,hi=n-1;meters=MAX(0,MIN(_totalMeters,meters));
    while(hi-lo_>1){NSUInteger mid=(lo_+hi)/2;if(c[mid]<=meters)lo_=mid;else hi=mid;}
    double len=c[hi]-c[lo_],t=len>0?(meters-c[lo_])/len:0;
    return (TIOGuidePose){la[lo_]+(la[hi]-la[lo_])*t,lo[lo_]+(lo[hi]-lo[lo_])*t,Bearing(la[lo_],lo[lo_],la[hi],lo[hi]),meters>=_totalMeters};
}
@end

static TIOGuideSnapResult SnapRange(TIOGuideRoute *r,double lat,double lon,NSUInteger from,NSUInteger to){
    const double *la=r.lat,*lo=r.lon,*c=r.cum;double k=cos(lat*M_PI/180)*MetersPerDegree;
    TIOGuideSnapResult best={0,from,INFINITY,0,lat,lon,0};
    for(NSUInteger i=from;i<to&&i+1<r.points.count;i++){
        double ax=(lo[i]-lon)*k,ay=(la[i]-lat)*MetersPerDegree,bx=(lo[i+1]-lon)*k,by=(la[i+1]-lat)*MetersPerDegree,dx=bx-ax,dy=by-ay,den=dx*dx+dy*dy;
        double t=den>0?MAX(0,MIN(1,-(ax*dx+ay*dy)/den)):0,d=hypot(ax+dx*t,ay+dy*t);
        if(d<best.offRoute){best.offRoute=d;best.segment=i;best.along=c[i]+(c[i+1]-c[i])*t;best.lat=la[i]+(la[i+1]-la[i])*t;best.lon=lo[i]+(lo[i+1]-lo[i])*t;best.bearing=Bearing(la[i],lo[i],la[i+1],lo[i+1]);}
    }
    best.step=[r stepForSegment:best.segment];return best;
}
TIOGuideSnapResult TIOGuideSnap(TIOGuideRoute *r,double lat,double lon,NSInteger hint){
    NSInteger last=(NSInteger)r.steps.count-1;
    if(hint>=0&&hint<=last){TIOGuideSnapResult near=SnapRange(r,lat,lon,[r startOf:hint],[r endOf:MIN(hint+1,last)]);if(near.offRoute<=TIOGuideOffRouteMeters)return near;}
    return SnapRange(r,lat,lon,0,r.points.count-1);
}
TIOGuideProgressResult TIOGuideProgress(TIOGuideRoute *r,TIOGuideSnapResult s){
    double remaining=MAX(0,r.totalMeters-s.along),maneuver=MAX(0,r.cum[[r endOf:s.step]]-s.along);
    return (TIOGuideProgressResult){maneuver,remaining,r.totalMeters>0?r.expectedSeconds*remaining/r.totalMeters:0};
}
NSArray *TIOGuideUpcoming(TIOGuideRoute *r,TIOGuideSnapResult s,NSUInteger max){
    max=MAX(2,max);NSInteger last=(NSInteger)r.steps.count-1;NSUInteger stop=[r endOf:MIN(s.step+1,last)];
    NSMutableArray *out=[NSMutableArray arrayWithObject:@[@(s.lat),@(s.lon)]];
    for(NSUInteger i=s.segment+1;i<=stop&&out.count<max;i++)if(TIOGuideDistance(r.lat[i],r.lon[i],[out.lastObject[0] doubleValue],[out.lastObject[1] doubleValue])>=0.5)[out addObject:r.points[i]];
    if(out.count<2){NSUInteger n=r.points.count;return @[r.points[n-2],r.points[n-1]];}
    return out;
}
NSInteger TIOGuideIcon(TIOGuideRoute *r,NSInteger k){
    NSInteger last=(NSInteger)r.steps.count-1;if(k<0)return TIOGuideIconUnknown;if(k>=last)return TIOGuideIconArrive;
    NSString *next=r.steps[k+1].instructions.lowercaseString;
    if([next containsString:@"u-turn"]||[next containsString:@"make a u"])return TIOGuideIconUTurn;
    if([next containsString:@"roundabout"]||[next containsString:@"traffic circle"]||[next containsString:@"rotary"])return TIOGuideIconRoundabout;
    double junction=r.cum[[r endOf:k]],stepStart=r.cum[[r startOf:k]],nextEnd=r.cum[[r endOf:k+1]];
    double inFrom=MAX(stepStart,junction-20),outTo=MIN(nextEnd,junction+20);
    if(junction-inFrom<1||outTo-junction<1)return TIOGuideIconStraight;
    TIOGuidePose a=[r poseAt:inFrom],b=[r poseAt:junction],c=[r poseAt:outTo];
    double d=Delta(Bearing(a.lat,a.lon,b.lat,b.lon),Bearing(b.lat,b.lon,c.lat,c.lon)),m=fabs(d);BOOL right=d>0;
    if(m<20)return TIOGuideIconStraight;if(m<60)return right?TIOGuideIconSlightRight:TIOGuideIconSlightLeft;
    if(m<135)return right?TIOGuideIconRight:TIOGuideIconLeft;if(m<=170)return right?TIOGuideIconSharpRight:TIOGuideIconSharpLeft;
    return TIOGuideIconUTurn;
}
NSString *TIOGuideTurnText(NSInteger icon){
    switch(icon){case TIOGuideIconLeft:return @"Turn left";case TIOGuideIconRight:return @"Turn right";case TIOGuideIconSlightLeft:return @"Slight left";case TIOGuideIconSlightRight:return @"Slight right";case TIOGuideIconSharpLeft:return @"Sharp left";case TIOGuideIconSharpRight:return @"Sharp right";case TIOGuideIconUTurn:return @"Make a U-turn";case TIOGuideIconStraight:return @"Continue straight";case TIOGuideIconRoundabout:return @"Enter roundabout";case TIOGuideIconArrive:return @"Arrive";default:return @"Follow the route";}
}
NSString *TIOGuideRoadName(NSString *text){
    if(![text isKindOfClass:NSString.class]||!text.length)return @"";NSRange at=NSMakeRange(NSNotFound,0);
    for(NSString *key in @[@" onto ",@" on "]){at=[text rangeOfString:key options:NSCaseInsensitiveSearch|NSBackwardsSearch];if(at.location!=NSNotFound)break;}
    if(at.location==NSNotFound)return @"";NSString *name=[text substringFromIndex:NSMaxRange(at)];
    for(NSString *cut in @[@" toward",@" towards",@" for ",@", then"]){NSRange c=[name rangeOfString:cut options:NSCaseInsensitiveSearch];if(c.location!=NSNotFound)name=[name substringToIndex:c.location];}
    name=[name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .,;"]];
    return [name.lowercaseString hasPrefix:@"the destination"]?@"":TIOGuideAbbreviate(name);
}
NSString *TIOGuideAbbreviate(NSString *name){
    if(![name isKindOfClass:NSString.class])return @"";
    static NSDictionary *map;static dispatch_once_t once;dispatch_once(&once,^{map=@{@"street":@"St",@"avenue":@"Ave",@"road":@"Rd",@"boulevard":@"Blvd",@"drive":@"Dr",@"highway":@"Hwy",@"lane":@"Ln",@"parkway":@"Pkwy",@"court":@"Ct",@"place":@"Pl",@"terrace":@"Ter",@"expressway":@"Expy",@"freeway":@"Fwy",@"square":@"Sq",@"north":@"N",@"south":@"S",@"east":@"E",@"west":@"W",@"northeast":@"NE",@"northwest":@"NW",@"southeast":@"SE",@"southwest":@"SW"};});
    NSArray *words=[name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];NSMutableArray *out=[NSMutableArray new];
    for(NSString *w in words){if(!w.length)continue;NSString *short_=words.count>1?map[w.lowercaseString]:nil;[out addObject:short_?:w];}
    return [out componentsJoinedByString:@" "];
}
double TIOGuideHeading(double course,double speed,double segmentBearing){
    double h=isfinite(course)&&course>=0&&isfinite(speed)&&speed>1?course:segmentBearing;h=fmod(h,360);return h<0?h+360:h;
}
TIOGuideRerouteState TIOGuideRerouteInitial(void){return (TIOGuideRerouteState){0,0,-INFINITY};}
BOOL TIOGuideShouldReroute(TIOGuideRerouteState *s,double offRoute,double now){
    if(!s)return NO;s->strikes=offRoute>TIOGuideOffRouteMeters?s->strikes+1:0;
    if(s->strikes<3||s->count>=10||now-s->lastAt<30)return NO;
    s->strikes=0;s->count++;s->lastAt=now;return YES;
}
BOOL TIOGuideArrived(TIOGuideRoute *r,TIOGuideSnapResult s,double lat,double lon){
    NSArray *end=r.points.lastObject;return s.step==(NSInteger)r.steps.count-1&&TIOGuideDistance(lat,lon,[end[0] doubleValue],[end[1] doubleValue])<=TIOGuideArriveMeters;
}
TIOGuidePose TIOGuideSimulate(TIOGuideRoute *r,double elapsed,double mps){
    double d=isfinite(elapsed)&&isfinite(mps)?MAX(0,elapsed*mps):0;return [r poseAt:d];
}
