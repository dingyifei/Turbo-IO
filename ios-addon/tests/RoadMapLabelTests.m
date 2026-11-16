#import "RoadMap.h"
#include "nav_map.h"
#include <assert.h>
// Built with -DTIO_MAPKIT_ENABLED=1: labels prefer name:en, then name, abbreviated.
static NSString *Fixture;
@interface LabelMap:TIORoadMap @end
@implementation LabelMap
- (NSString *)fixturePath:(NSString *)name{return Fixture;}
@end
static unsigned u16(const uint8_t *p){return p[0]|(unsigned)p[1]<<8;}
static NSArray *WGS(void){return @[@[@37.7749,@-122.4194],@[@37.7755,@-122.4188],@[@37.7761,@-122.4182]];}
// Every feature gets the same geometry, alongside the route; returns scene + label strings.
static NSDictionary *Scene(NSArray *propertiesList){
    NSArray *wgs=WGS();NSMutableArray *osm=[NSMutableArray new],*features=[NSMutableArray new];
    for(NSArray *p in wgs)[osm addObject:@[p[1],p[0]]];for(NSDictionary *pr in propertiesList)[features addObject:@{@"properties":pr,@"geometry":@{@"type":@"LineString",@"coordinates":osm}}];
    NSDictionary *fixture=@{@"meta":@{@"bbox":@[@37.772,@-122.422,@37.778,@-122.416]},@"geojson":@{@"features":features}};
    assert([[NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil] writeToFile:Fixture atomically:YES]);
    LabelMap *map=[[LabelMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){return @[@(lat),@(lon)];}];map.enabled=YES;
    NSDictionary *frame=@{@"phase":@"navigating",@"segment":@1,@"tnrLocation":wgs[0],@"tnrLocationAt":@(NSProcessInfo.processInfo.systemUptime),@"navHeading":@45};
    NSDictionary *out=[map decorate:frame coordinates:wgs];NSData *scene=out[@"tnrScene"],*v2=out[@"tnrScene2"];assert(scene&&v2);
    NSMutableArray *labels=[NSMutableArray new];for(unsigned i=0;i<u16((const uint8_t *)v2.bytes+10);i++){const uint8_t *label=(const uint8_t *)v2.bytes+scene.length+40*i;[labels addObject:[[NSString alloc]initWithBytes:label+8 length:label[4] encoding:NSUTF8StringEncoding]];}
    [map reset];return @{@"paths":@(u16((const uint8_t *)scene.bytes+6)),@"labels":labels};
}
static NSString *Label(NSDictionary *properties){NSArray *labels=Scene(@[properties])[@"labels"];assert(labels.count==1);return labels[0];}
int main(void){@autoreleasepool{
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:nil]);Fixture=[dir stringByAppendingPathComponent:@"fixture.json"];
    assert([Label(@{@"kind":@"road",@"highway":@"residential",@"name":@"Market Street",@"name:zh":@"市场街"}) isEqual:@"Market St"]);
    assert([Label(@{@"kind":@"road",@"highway":@"residential",@"name":@"Calle Mayor",@"name:en":@"Main Street"}) isEqual:@"Main St"]);
    assert([Label(@{@"kind":@"road",@"highway":@"residential",@"name":@"Broadway"}) isEqual:@"Broadway"]);
    // OpenFreeMap: names arrive as separate label-only lines; they label the drawn road but are never drawn (route + 1 road).
    NSDictionary *named=Scene(@[@{@"kind":@"road",@"highway":@"residential"},@{@"kind":@"road",@"highway":@"residential",@"labelOnly":@YES,@"name":@"Calle Mayor",@"name:en":@"Main Street"}]);
    assert([named[@"paths"] isEqual:@2]&&[named[@"labels"] isEqual:@[@"Main St"]]);
    // A name whose road did not make the drawn budget is not shown floating on its own.
    NSDictionary *alone=Scene(@[@{@"kind":@"road",@"highway":@"residential",@"labelOnly":@YES,@"name":@"Main Street"}]);assert([alone[@"paths"] isEqual:@1]&&![alone[@"labels"] count]);
    assert([NSFileManager.defaultManager removeItemAtPath:dir error:nil]);
    puts("PASS MapKit labels: name:en over name over name:zh, abbreviated to the glasses label slot; label-only name lines");
}return 0;}
