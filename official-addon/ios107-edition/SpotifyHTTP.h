#import <Foundation/Foundation.h>
typedef void(^TMSpotifyHTTPDone)(NSData *body,NSHTTPURLResponse *response,NSError *error);
typedef void(^TMSpotifyHTTP)(NSURLRequest *request,TMSpotifyHTTPDone done);
FOUNDATION_EXPORT TMSpotifyHTTP TMSpotifyDefaultHTTP(void);
