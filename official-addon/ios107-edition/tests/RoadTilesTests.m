#import "RoadTiles.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
// Hand-encoded Mapbox Vector Tile with OpenMapTiles layers; checks class mapping, names, geometry, bbox and malformed input.
static void V(NSMutableData *d,uint64_t v){do{uint8_t b=v&127;v>>=7;if(v)b|=128;[d appendBytes:&b length:1];}while(v);}
static void Bytes(NSMutableData *d,unsigned field,NSData *b){V(d,field<<3|2);V(d,b.length);[d appendData:b];}
static void Str(NSMutableData *d,unsigned field,NSString *s){Bytes(d,field,[s dataUsingEncoding:NSUTF8StringEncoding]);}
static uint64_t Z(long long v){return (uint64_t)((v<<1)^(v>>63));}
static NSData *Value(id v){NSMutableData *d=[NSMutableData new];if([v isKindOfClass:NSString.class])Str(d,1,v);else{V(d,5<<3);V(d,[v unsignedLongLongValue]);}return d;}
// lines: array of polylines in tile units; tags: flat key/value index pairs.
static NSData *Feature(unsigned type,NSArray *tags,NSArray *lines){
 NSMutableData *f=[NSMutableData new],*t=[NSMutableData new],*g=[NSMutableData new];for(NSNumber *n in tags)V(t,n.unsignedIntValue);Bytes(f,2,t);V(f,3<<3);V(f,type);
 long long x=0,y=0;for(NSArray *line in lines){for(NSUInteger i=0;i<line.count;i++){if(i<2)V(g,(i?2:1)|(i?(line.count-1):1)<<3);long long nx=[line[i][0] longLongValue],ny=[line[i][1] longLongValue];V(g,Z(nx-x));V(g,Z(ny-y));x=nx;y=ny;}}
 Bytes(f,4,g);return f;
}
static NSData *Layer(NSString *name,NSArray *keys,NSArray *values,NSArray *features){
 NSMutableData *l=[NSMutableData new];V(l,15<<3);V(l,2);Str(l,1,name);for(NSData *f in features)Bytes(l,2,f);for(NSString *k in keys)Str(l,3,k);for(id v in values)Bytes(l,4,Value(v));V(l,5<<3);V(l,4096);return l;
}
static double Lon(double tx){return tx/16384*360-180;}
static double Lat(double ty){return atan(sinh(M_PI*(1-2*ty/16384)))*180/M_PI;}
int main(void){@autoreleasepool{
 const unsigned X=2621,Y=6332;
 NSArray *keys=@[@"class",@"ramp",@"brunnel",@"layer",@"name",@"name_en"],*values=@[@"secondary",@1,@"bridge",@"minor",@"rail",@2,@"Calle Mayor",@"Main Street"];
 NSArray *roads=@[
  Feature(2,@[@0,@0,@1,@1],@[@[@[@100,@100],@[@200,@100],@[@200,@300]]]),                 // secondary ramp -> secondary_link
  Feature(2,@[@0,@3,@2,@2,@3,@5],@[@[@[@300,@300],@[@400,@300]]]),                         // minor bridge layer 2 -> residential
  Feature(2,@[@0,@4],@[@[@[@100,@500],@[@900,@500]]]),                                     // rail: skipped
  Feature(3,@[@0,@3],@[@[@[@0,@0],@[@50,@0],@[@50,@50]]]),                                 // area polygon: skipped
  Feature(2,@[@0,@3],@[@[@[@500,@500],@[@600,@500]],@[@[@500,@700],@[@600,@700]]]),        // multi-line -> two features
  Feature(2,@[@0,@3],@[@[@[@4000,@4000],@[@4090,@4000]]])];                                // outside bbox: dropped
 NSArray *names=@[Feature(2,@[@0,@3,@4,@6,@5,@7],@[@[@[@300,@300],@[@400,@300]]]),Feature(2,@[@0,@3],@[@[@[@300,@300],@[@400,@300]]])]; // the unnamed one is skipped
 NSMutableData *tile=[NSMutableData new];Bytes(tile,3,Layer(@"building",keys,values,@[Feature(3,@[@0,@3],@[@[@[@1,@1],@[@2,@2]]])]));Bytes(tile,3,Layer(@"transportation",keys,values,roads));Bytes(tile,3,Layer(@"transportation_name",keys,values,names));
 NSArray *bbox=@[@(Lat(Y+0.5)),@(Lon(X)),@(Lat(Y)),@(Lon(X+0.5))]; // top-left quarter of the tile
 NSArray *f=TIORoadTileFeatures(tile,14,X,Y,bbox);assert(f.count==5);
 NSDictionary *a=f[0][@"properties"];assert([a[@"highway"] isEqual:@"secondary_link"]&&[a[@"kind"] isEqual:@"road"]&&!a[@"labelOnly"]);
 NSArray *c=f[0][@"geometry"][@"coordinates"];assert(c.count==3&&[f[0][@"geometry"][@"type"] isEqual:@"LineString"]);
 assert(fabs([c[0][0] doubleValue]-Lon(X+100/4096.))<1e-9&&fabs([c[0][1] doubleValue]-Lat(Y+100/4096.))<1e-9&&fabs([c[2][1] doubleValue]-Lat(Y+300/4096.))<1e-9);
 NSDictionary *b=f[1][@"properties"];assert([b[@"highway"] isEqual:@"residential"]&&[b[@"bridge"] isEqual:@"yes"]&&[b[@"layer"] isEqual:@2]);
 assert([f[2][@"geometry"][@"coordinates"] count]==2&&[f[3][@"geometry"][@"coordinates"] count]==2&&[f[3][@"geometry"][@"coordinates"][0][1] doubleValue]<[f[2][@"geometry"][@"coordinates"][0][1] doubleValue]);
 NSDictionary *n=f[4][@"properties"];assert([n[@"labelOnly"] isEqual:@YES]&&[n[@"name"] isEqual:@"Calle Mayor"]&&[n[@"name:en"] isEqual:@"Main Street"]);
 assert(TIORoadTileFeatures(tile,14,1u<<14,Y,bbox).count==0&&TIORoadTileFeatures(tile,14,X,Y,@[]).count==0);
 // Every truncation and a byte-flip sweep must stay in bounds (ASan) and never invent extra features.
 for(NSUInteger len=0;len<tile.length;len++)assert(TIORoadTileFeatures([tile subdataWithRange:NSMakeRange(0,len)],14,X,Y,bbox).count<=5);
 for(NSUInteger i=0;i<tile.length;i++){NSMutableData *bad=[tile mutableCopy];((uint8_t *)bad.mutableBytes)[i]^=0xff;TIORoadTileFeatures(bad,14,X,Y,bbox);}
 // ~2 km box in San Francisco spans 2x2 z14 tiles; a cap below that returns nothing rather than partial coverage.
 NSArray *sf=@[@(37.7858-.009),@(-122.4064-.0114),@(37.7858+.009),@(-122.4064+.0114)];NSArray *t=TIORoadTilesCovering(sf,14,9);
 assert(t.count==4&&[t[0] isEqual:(@[@14,@2620,@6331])]&&[t[3] isEqual:(@[@14,@2621,@6332])]&&TIORoadTilesCovering(sf,14,3).count==0&&TIORoadTilesCovering(@[@1,@2],14,9).count==0);
 // Corridor: a 5 km drive due east saves tiles in driving order, both sides of the road where the corridor crosses a tile row.
 NSMutableArray *drive=[NSMutableArray new];for(int i=0;i<=50;i++)[drive addObject:@[@37.7858,@(-122.4064+i*100/(111319.49*cos(37.7858*M_PI/180)))]];
 NSArray *corridor=TIORoadTilesAlongRoute(drive,14,600,3000);assert(corridor.count>=3&&corridor.count<=12&&[corridor[0][1] intValue]<=2621);
 for(NSUInteger i=1;i<corridor.count;i++)assert([corridor[i][1] intValue]>=[corridor[i-1][1] intValue]-1);assert([[NSSet setWithArray:corridor] count]==corridor.count);
 assert(TIORoadTilesAlongRoute(drive,14,600,2).count==2&&TIORoadTilesAlongRoute(@[drive[0]],14,600,10).count==0);
 // Store: fake network serves the tile index and tiles; one tile fails until the "signal" returns.
 NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
 __block BOOL signal=NO;__block unsigned fetches=0;NSData *body=[@"tile-bytes" dataUsingEncoding:NSUTF8StringEncoding];
 TIORoadTileFetch fake=^(NSURL *url,void(^done)(NSData *)){fetches++;NSData *d=nil;
  if([url.absoluteString isEqual:@"https://tiles.openfreemap.org/planet"])d=[NSJSONSerialization dataWithJSONObject:@{@"tiles":@[@"https://tiles.openfreemap.org/planet/v1/{z}/{x}/{y}.pbf"]} options:0 error:nil];
  else if([url.absoluteString hasPrefix:@"https://tiles.openfreemap.org/planet/v1/14/"]&&(signal||![url.absoluteString hasSuffix:@"/2/2.pbf"]))d=body;
  dispatch_async(dispatch_get_global_queue(0,0),^{done(d);});};
 void(^spin)(BOOL(^)(void))=^(BOOL(^until)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];while(!until()&&end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];};
 TIORoadTileStore *store=[[TIORoadTileStore alloc]initWithDirectory:dir fetch:fake];store.retryAfter=0.2;__block unsigned landed=0;store.landed=^{landed++;};
 NSArray *six=@[@[@14,@1,@1],@[@14,@2,@1],@[@14,@3,@1],@[@14,@1,@2],@[@14,@2,@2],@[@14,@3,@2]];[store want:six urgent:NO];
 spin(^{return (BOOL)([store.status[@"saved"] intValue]==5&&[store.status[@"failed"] intValue]==1);});
 assert([store.status[@"saved"] intValue]==5&&[store.status[@"wanted"] intValue]==6&&landed==5&&[[store tile:six[0]] isEqual:body]&&![store tile:six[4]]);
 unsigned before=fetches;[store want:@[six[0]] urgent:YES];assert(fetches==before); // saved tiles are never fetched again
 signal=YES;spin(^{return (BOOL)([store.status[@"saved"] intValue]==6);});assert([store.status[@"saved"] intValue]==6&&[store.status[@"failed"] intValue]==0&&[[store tile:six[4]] isEqual:body]);
 // Offline restart: a fresh store reads the saved tiles and the saved tile index without the network.
 TIORoadTileStore *offline=[[TIORoadTileStore alloc]initWithDirectory:dir fetch:^(NSURL *u,void(^done)(NSData *)){assert(0);}];[offline want:six urgent:YES];assert([[offline tile:six[5]] isEqual:body]);
 // Ending the trip deletes every saved tile.
 [store clear];assert(![store tile:six[0]]&&[store.status[@"saved"] intValue]==0);
 for(NSURL *u in [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil])assert(![u.pathExtension isEqual:@"tile"]);
 [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
 puts("PASS tiles: OpenMapTiles class mapping, ramps/bridges/layers, multi-lines, label-only names, bbox filter, truncation/bit-flip safety, tile cover, route corridor order, saved-tile store with retry/offline/clear");
}return 0;}
