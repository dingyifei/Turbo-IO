#import <Foundation/Foundation.h>
#import "nav_runtime.h"
typedef void(^TNVSubmitted)(BOOL,NSString *);
BOOL TNVDecodeReply(NSDictionary *,TNReply *);
BOOL TNVScene(NSDictionary *,BOOL,TNScene *);
NSDictionary *TNVNormalizeCoordinates(NSArray *);
@interface TNVSession:NSObject
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup;
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always;
- (void)offer:(NSDictionary *)frame;
- (void)setAlways:(BOOL)always;
- (void)stop;
- (void)setReplayPaused:(BOOL)paused;
- (void)backgroundDrainExpired;
- (void)disconnect;
- (void)setBackground:(BOOL)background; // background apps get the slower pose rate
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@property(nonatomic,readonly) BOOL active,busy;
// One native file in flight across navigation (TNV1) and music (TMU1): both share the phone's single BLE file link.
// peerFileInFlight: the other feature owns the link now, send nothing. peerWaiting: it has a packet ready, so a
// non-urgent slot (pose, passing, routine UPDATE) may be given to it once per window. STOP and urgent UPDATE never yield.
@property(nonatomic,copy) BOOL(^peerFileInFlight)(void);
@property(nonatomic,copy) BOOL(^peerWaiting)(void);
@property(nonatomic,readonly) BOOL fileInFlight;
@property(nonatomic,readonly) NSDictionary *status;
@end
