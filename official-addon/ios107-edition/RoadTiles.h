#import <Foundation/Foundation.h>
// OpenMapTiles vector tiles (OpenFreeMap) -> TIORoadMap road features: {properties, geometry:{LineString, [[lon,lat]...]}}.
// bbox is @[minLat,minLon,maxLat,maxLon]; only features touching it are kept.
// Drawn roads come from "transportation" (no names there); "transportation_name" lines become labelOnly features.
NSArray<NSDictionary *> *TIORoadTileFeatures(NSData *tile,unsigned z,unsigned x,unsigned y,NSArray *bbox);
// Tiles at zoom z touching bbox, as @[z,x,y]; empty when more than max would be needed.
NSArray<NSArray<NSNumber *> *> *TIORoadTilesCovering(NSArray *bbox,unsigned z,NSUInteger max);
// Tiles within radius metres of a route ([lat,lon] points), in driving order so the start is saved first; at most max.
NSArray<NSArray<NSNumber *> *> *TIORoadTilesAlongRoute(NSArray *coords,unsigned z,double radius,NSUInteger max);
typedef void(^TIORoadTileFetch)(NSURL *url,void(^done)(NSData *body)); // body nil on any failure; done may run on any queue
// One trip's OpenFreeMap tiles saved on disk, so nearby roads keep drawing without cell signal.
// Main-thread object, except -tile:, which only reads files. Downloads 4 at a time and retries failed tiles every retryAfter seconds.
@interface TIORoadTileStore:NSObject
- (instancetype)initWithDirectory:(NSURL *)directory fetch:(TIORoadTileFetch)fetch;
- (void)want:(NSArray *)tiles urgent:(BOOL)urgent; // queue tiles not yet saved; urgent ones jump the queue
- (NSData *)tile:(NSArray<NSNumber *> *)zxy;      // saved tile bytes, or nil
- (void)clear;                                    // forget the queue and delete every saved tile
@property NSTimeInterval retryAfter;
@property(copy) void(^landed)(void);              // a tile was saved (main thread)
@property(readonly) NSDictionary *status;         // wanted, saved, failed, downloading, downloadedBytes
@end
