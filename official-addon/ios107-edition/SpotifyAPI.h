#import "SpotifyAuth.h"
typedef NS_ENUM(NSInteger,TMSpotifyErrorKind){TMSpotifyOK=0,TMSpotifyNotConfigured,TMSpotifySignedOut,TMSpotifyPremiumRequired,TMSpotifyRestricted,TMSpotifyNoActiveDevice,TMSpotifyRateLimited,TMSpotifyNetwork,TMSpotifyServer,TMSpotifyBadResponse};
FOUNDATION_EXPORT TMSpotifyErrorKind TMSpotifyClassify(NSData *body,NSHTTPURLResponse *response,NSError *error,NSTimeInterval *retryAfter);
FOUNDATION_EXPORT NSURL *TMSpotifyImageURL(NSArray *images);
FOUNDATION_EXPORT NSDictionary *TMSpotifyStateFromPlayer(NSDictionary *json);
FOUNDATION_EXPORT NSString *TMSpotifyPickDevice(NSArray *devices);
@interface TMSpotifyAPI : NSObject
+ (instancetype)shared;
- (instancetype)initWithAuth:(TMSpotifyAuth *)auth http:(TMSpotifyHTTP)http clock:(NSTimeInterval(^)(void))uptime;
@property(nonatomic,readonly) NSTimeInterval backoffUntil;
- (void)player:(void(^)(NSDictionary *state,TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)devices:(void(^)(NSArray<NSDictionary *> *devices,TMSpotifyErrorKind kind))done;
- (void)play:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)pause:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)next:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)previous:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)seek:(uint32_t)ms done:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
- (void)transfer:(NSString *)deviceID play:(BOOL)play done:(void(^)(TMSpotifyErrorKind kind,NSTimeInterval retry))done;
@end
