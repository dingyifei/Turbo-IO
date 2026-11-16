#import "RoadMap.h"
#include "nav_map.h"
#include <assert.h>
#include <stdio.h>
@interface TIORoadMap(Diagnosis) - (void)installFeatures:(NSArray *)features bbox:(NSArray *)bbox; @end
static NSArray*LL(double e,double n){return @[@(37+n/111319.49),@(-122+e/(111319.49*cos(37*M_PI/180)))];}
int main(void){@autoreleasepool{
 NSArray *classes=@[@"motorway",@"trunk",@"primary",@"secondary",@"tertiary",@"residential",@"service",@"track",@"path",@"footway"];
 NSMutableArray *fs=[NSMutableArray new];for(unsigned i=0;i<classes.count;i++){NSArray*a=LL(100,20*i+30),*b=LL(200,20*i+30);[fs addObject:@{@"properties":@{@"kind":@"road",@"highway":classes[i]},@"geometry":@{@"type":@"LineString",@"coordinates":@[@[a[1],a[0]],@[b[1],b[0]]]}}];}
 TIORoadMap *map=[[TIORoadMap alloc]initWithWGS84ToMap:nil];map.enabled=YES;[map installFeatures:fs bbox:@[@36.99,@(-122.01),@37.01,@(-121.99)]];
 NSDictionary *f=[map decorate:@{@"phase":@"navigating",@"segment":@0,@"tnrLocation":LL(0,0),@"tnrLocationAt":@(NSProcessInfo.processInfo.systemUptime),@"navHeading":@0,@"navSpeed":@1.4} coordinates:@[LL(0,0),LL(0,300)]];
 NSData*d=f[@"tnrScene"];assert(d);const unsigned char*p=d.bytes;unsigned n=p[6]|(unsigned)p[7]<<8,c[7]={0};for(unsigned i=0;i<n;i++)c[p[18+8*i]]++;
 printf("input major5 residential1 minor4; scene paths=%u styles[0..6]=%u,%u,%u,%u,%u,%u,%u; networkAllowed=%d\n",n,c[0],c[1],c[2],c[3],c[4],c[5],c[6],map.allowNetwork);assert(n==6&&c[4]==0&&c[5]==0);puts("PASS major-only background away from route");return 0;}}
