#import "SpotifyHTTP.h"
#import <stdint.h>
FOUNDATION_EXPORT NSArray<NSDictionary *> *TMParseLRC(NSString *input);
FOUNDATION_EXPORT NSURL *TMLRCLIBGetURL(NSString *title,NSString *artist,NSString *album,uint32_t durationMs);
FOUNDATION_EXPORT NSURL *TMLRCLIBSearchURL(NSString *title,NSString *artist);
FOUNDATION_EXPORT NSDictionary *TMLRCLIBRows(NSData *body,NSInteger status,uint32_t durationMs);
@interface TMSpotifyLyrics:NSObject
+ (instancetype)shared;
- (instancetype)initWithHTTP:(TMSpotifyHTTP)http;
- (void)lyricsForID:(NSString *)trackID title:(NSString *)title artist:(NSString *)artist album:(NSString *)album durationMs:(uint32_t)durationMs done:(void(^)(NSArray *rows,NSString *kind,BOOL failed))done;
@end
