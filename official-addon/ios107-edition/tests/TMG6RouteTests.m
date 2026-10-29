#import <Foundation/Foundation.h>
#import "NavigationGuidance.h"
#import "RoadMap.h"
#include "nav_map.h"
#include <assert.h>
#include <math.h>

static NSArray *P(double e,double n){double lat=37.7749,lon=-122.4194;return @[@(lat+n/111319.49),@(lon+e/(111319.49*cos(lat*M_PI/180)))];}
static TIOGuideStep *Step(NSArray *p){return [TIOGuideStep stepWithPoints:p instructions:@"Continue"];} 
int main(void){@autoreleasepool{
 TIOGuideRoute *r=[TIOGuideRoute routeWithSteps:@[Step(@[P(0,0),P(0,40)]),Step(@[P(0,40),P(40,40)]),Step(@[P(40,40),P(40,80)]),Step(@[P(40,80),P(80,80)])] expectedSeconds:100];
 TIOGuideSnapResult s=TIOGuideSnap(r,[P(0,0)[0] doubleValue],[P(0,0)[1] doubleValue],0);
 NSArray *ahead=TIOGuideUpcoming(r,s,512);printf("route_points=%lu upcoming_points=%lu stop_step=%ld last_included=(%.0f,%.0f)\n",(unsigned long)r.points.count,(unsigned long)ahead.count,(long)s.step+1,TIOGuideDistance([ahead.lastObject[0] doubleValue],[ahead.lastObject[1] doubleValue],[P(0,0)[0] doubleValue],[P(0,0)[1] doubleValue]),TIOGuideDistance([ahead.lastObject[0] doubleValue],[ahead.lastObject[1] doubleValue],[P(40,40)[0] doubleValue],[P(40,40)[1] doubleValue]));
 TIORoadMap *map=[[TIORoadMap alloc]initWithWGS84ToMap:nil];map.enabled=YES;double now=NSProcessInfo.processInfo.systemUptime;
 NSDictionary *f=[map decorate:@{@"phase":@"navigating",@"segment":@(s.step),@"tnrRoute":r.points,@"navHeading":@0,@"tnrLocation":P(0,0),@"tnrLocationAt":@(now)} coordinates:ahead];
 NSData *scene=f[@"tnrScene"],*pose=f[@"tnrPose"];assert(scene&&pose);TNRState state={0};assert(tnr_receive(&state,TNR_SCENE,scene.bytes,scene.length,1000));assert(tnr_receive(&state,TNR_POSE,pose.bytes,pose.length,1000));uint8_t image[TNR_W*TNR_H];tnr_draw(&state,1000,image);
 unsigned routePaths=0,routePoints=0;for(unsigned i=0;i<state.scenes[state.bank].path_count;i++)if(state.scenes[state.bank].paths[i].style==6){routePaths++;routePoints+=state.scenes[state.bank].paths[i].count;}
 unsigned after=0;for(int y=58;y<=68;y++)for(int x=118;x<=123;x++)if(image[y*TNR_W+x])after++;
 printf("scene_valid=%d path_count=%u route_paths=%u route_points=%u after_second_turn_pixels=%u\n",state.valid,state.scenes[state.bank].path_count,routePaths,routePoints,after);
 TIORoadMap *fullMap=[[TIORoadMap alloc]initWithWGS84ToMap:nil];fullMap.enabled=YES;
 NSDictionary *ff=[fullMap decorate:@{@"phase":@"navigating",@"segment":@(s.step),@"navHeading":@0,@"tnrLocation":P(0,0),@"tnrLocationAt":@(now)} coordinates:r.points];
 TNRState positive={0};NSData *fs=ff[@"tnrScene"],*fp=ff[@"tnrPose"];assert(fs&&fp);assert(tnr_receive(&positive,TNR_SCENE,fs.bytes,fs.length,1000));assert(tnr_receive(&positive,TNR_POSE,fp.bytes,fp.length,1000));tnr_draw(&positive,1000,image);unsigned yes=0;for(int y=58;y<=68;y++)for(int x=118;x<=123;x++)if(image[y*TNR_W+x])yes++;
 printf("full_route_positive_control_pixels=%u\n",yes);
 assert(after>0&&yes>0);
 // More than 2048 source samples before the first turn must not consume the
 // visible geometry budget or starve later turns that still fit the map.
 NSMutableArray *dense=[NSMutableArray new];for(unsigned i=0;i<=4000;i++)[dense addObject:P(0,i/100.0)];[dense addObjectsFromArray:@[P(40,40),P(40,80),P(80,80)]];
 NSMutableDictionary *input=[@{@"phase":@"navigating",@"segment":@0,@"navHeading":@0,@"tnrLocation":P(0,0),@"tnrLocationAt":@(NSProcessInfo.processInfo.systemUptime),@"tnrRoute":dense} mutableCopy];
 NSDictionary *df=[map decorate:input coordinates:ahead];TNRState ds={0};NSData *dd=df[@"tnrScene2"];assert(tnr_receive(&ds,TNR_SCENE2,dd.bytes,dd.length,1000));tnr_draw(&ds,1000,image);assert(image[62*TNR_W+120]>0);
 // A replacement route at the same step/position invalidates cached geometry.
 input[@"tnrRoute"]=@[P(0,0),P(0,40),P(-40,40),P(-40,80)];NSDictionary *rf=[map decorate:input coordinates:ahead];NSData *rd=rf[@"tnrScene2"];assert(![rd isEqual:dd]);TNRState rs={0};assert(tnr_receive(&rs,TNR_SCENE2,rd.bytes,rd.length,1000));tnr_draw(&rs,1000,image);assert(image[62*TNR_W+72]>0&&image[62*TNR_W+120]==0);
 puts("PASS route geometry beyond two maneuvers survives the real scene encoder and rasterizer");return 0;
} }
