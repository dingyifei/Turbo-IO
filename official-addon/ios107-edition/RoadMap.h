#import <Foundation/Foundation.h>
@interface TIORoadMap : NSObject<NSURLSessionDataDelegate>
@property BOOL enabled,allowNetwork;
@property(readonly) NSString *note;
- (instancetype)initWithWGS84ToMap:(NSArray *(^)(double lat,double lon))convert;
- (NSDictionary *)decorate:(NSDictionary *)frame coordinates:(NSArray *)coords;
- (void)reset;
- (NSDictionary *)coverageStatus; // regions, features, requests, requestInFlight
#if TIO_MAPKIT_ENABLED
- (void)prefetchRoute:(NSArray *)coords; // save the route corridor's tiles now, for dead zones later
- (void)forgetSavedRoads;                  // delete this trip's saved tiles
#endif
@end
