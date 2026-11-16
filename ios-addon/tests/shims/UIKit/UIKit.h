// Host-only stand-in for the few UIKit symbols that MusicPlayer.m and NativeNavigationUI.m touch, so their unchanged
// source runs on macOS in tests/MusicNavigationTests.m. Not part of any product build (the iOS SDK supplies UIKit there).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
typedef NS_ENUM(NSInteger,UIApplicationState){UIApplicationStateActive,UIApplicationStateInactive,UIApplicationStateBackground};
typedef NSUInteger UIBackgroundTaskIdentifier;
static const UIBackgroundTaskIdentifier UIBackgroundTaskInvalid=0;
extern NSString *const UIApplicationWillEnterForegroundNotification;
@interface UIImage:NSObject
@property(nonatomic,readonly) CGImageRef CGImage;
+ (instancetype)imageWithCGImage:(CGImageRef)image;
@end
@interface UIViewController:NSObject
@end
@interface UIApplication:NSObject
@property(class,nonatomic,readonly) UIApplication *sharedApplication;
@property(nonatomic,readonly) UIApplicationState applicationState;
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void(^)(void))handler;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
@end
