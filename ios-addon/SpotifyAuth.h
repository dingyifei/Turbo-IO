#import "SpotifyHTTP.h"
FOUNDATION_EXPORT NSString *const TMSpotifyDefaultRedirect;
FOUNDATION_EXPORT NSString *const TMSpotifyLoopbackRedirect;
FOUNDATION_EXPORT NSString *const TMSpotifyScopes;
FOUNDATION_EXPORT NSString *const TMSpotifyAuthChanged;
FOUNDATION_EXPORT NSString *TMSpotifyBase64URL(NSData *data);
FOUNDATION_EXPORT NSString *TMSpotifyRandomURLSafe(NSUInteger bytes);
FOUNDATION_EXPORT NSString *TMSpotifyNewVerifier(void);
FOUNDATION_EXPORT NSString *TMSpotifyChallenge(NSString *verifier);
FOUNDATION_EXPORT BOOL TMSpotifyValidClientID(NSString *clientID);
FOUNDATION_EXPORT NSString *TMSpotifyRedirectScheme(NSString *redirect);
FOUNDATION_EXPORT uint16_t TMSpotifyLoopbackPort(NSString *redirect);
FOUNDATION_EXPORT NSURL *TMSpotifyAuthorizeURL(NSString *clientID, NSString *redirect, NSString *challenge, NSString *state);
FOUNDATION_EXPORT NSDictionary *TMSpotifyCallbackResult(NSURL *callback, NSString *redirect, NSString *state);
FOUNDATION_EXPORT NSString *TMSpotifyCallbackShape(NSURL *callback);
FOUNDATION_EXPORT NSURL *TMSpotifyLoopbackRequestURL(NSData *head, uint16_t port);
FOUNDATION_EXPORT NSURLRequest *TMSpotifyTokenRequest(NSDictionary<NSString *,NSString *> *form);
FOUNDATION_EXPORT NSDictionary *TMSpotifyParseToken(NSData *body, NSInteger status, NSDate *now);
@interface TMSpotifyTokenStore : NSObject
+ (instancetype)keychain;
+ (instancetype)memory;
- (NSDictionary *)load;
- (BOOL)save:(NSDictionary *)data;
- (void)remove;
@end
@interface TMSpotifyAuth : NSObject
+ (instancetype)shared;
- (instancetype)initWithHTTP:(TMSpotifyHTTP)http store:(TMSpotifyTokenStore *)store defaults:(NSUserDefaults *)defaults clock:(NSDate *(^)(void))clock;
@property(nonatomic,readonly) NSString *clientID;
@property(nonatomic,copy) NSString *redirect;
@property(nonatomic,readonly) BOOL signedIn;
@property(nonatomic,readonly) NSString *callbackDiagnostics;
- (BOOL)setClientIDString:(NSString *)value;
- (NSURL *)beginSignIn;
- (void)finishSignInWithCallback:(NSURL *)url done:(void(^)(NSString *error))done;
- (void)accessToken:(void(^)(NSString *token,NSString *error))done;
- (void)invalidateAccessToken;
- (void)signOut;
// Ends the pending browser attempt and invalidates its unfinished exchange.
- (void)cancelPendingSignIn;
@end
