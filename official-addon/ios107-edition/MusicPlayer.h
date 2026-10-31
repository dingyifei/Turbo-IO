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
@end
