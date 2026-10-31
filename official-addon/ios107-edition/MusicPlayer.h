#import <UIKit/UIKit.h>
FOUNDATION_EXPORT UIViewController *TMMusicController(void);
FOUNDATION_EXPORT BOOL TMMusicConsume(NSDictionary *);
FOUNDATION_EXPORT BOOL TMMusicPauseForOTA(void);
// The shared BLE file link: one native file in flight across music and navigation.
FOUNDATION_EXPORT BOOL TMMusicFileInFlight(void);
FOUNDATION_EXPORT BOOL TMMusicFileWaiting(void);
FOUNDATION_EXPORT void TMMusicPauseForVoice(void);
@interface TMPlayer:NSObject
+ (instancetype)shared;
@property(nonatomic,readonly) NSDictionary *song;
@property(nonatomic,readonly) NSArray *lyrics;
@property(nonatomic,readonly) UIImage *cover;
@property(nonatomic,readonly) BOOL playing;
@property(nonatomic,readonly) double position,duration;
@property(nonatomic,readonly) NSString *status,*bridgeStatus;
@property(nonatomic) NSInteger mode;
@property(nonatomic) BOOL glasses,panelVisible;
- (void)play:(BOOL)value;
- (void)step:(NSInteger)delta;
- (void)seek:(double)seconds;
- (void)showOnGlasses;
- (void)hideGlasses;
- (void)refreshNow;
- (BOOL)watchRemoteAvailable;
// Glasses test bench fixture (ds3 p2). Shows a made-up song on the glasses' music page through the normal TMU1 bridge. While it is up
// the Spotify poll is off and the glasses' play/pause keys act on the demo song only. Only an OTA firmware stage blocks it (NO, status set).
@property(nonatomic,readonly) BOOL benchActive;
- (BOOL)benchShowTitle:(NSString *)title artist:(NSString *)artist playing:(BOOL)playing positionMs:(uint32_t)position durationMs:(uint32_t)duration lyrics:(NSArray *)lyrics;
- (void)benchStop;
@end
