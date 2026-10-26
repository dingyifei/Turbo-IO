#import <Foundation/Foundation.h>
// OpenMapTiles vector tiles (OpenFreeMap) -> TIORoadMap road features: {properties, geometry:{LineString, [[lon,lat]...]}}.
// bbox is @[minLat,minLon,maxLat,maxLon]; only features touching it are kept.
// Drawn roads come from "transportation" (no names there); "transportation_name" lines become labelOnly features.
NSArray<NSDictionary *> *TIORoadTileFeatures(NSData *tile,unsigned z,unsigned x,unsigned y,NSArray *bbox);
// Tiles at zoom z touching bbox, as @[z,x,y]; empty when more than max would be needed.
NSArray<NSArray<NSNumber *> *> *TIORoadTilesCovering(NSArray *bbox,unsigned z,NSUInteger max);
