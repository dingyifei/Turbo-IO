#import <UIKit/UIKit.h>
#include <stdio.h>

extern UIViewController *TIOCreateTurboPreview(void);
extern UIViewController *TIOExperimentalOTAController(void);
extern UIViewController *TMMusicController(void);
extern NSDictionary *TIOPreviewOTAFixture(NSString *state);

static NSString *Argument(NSString *name) {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUInteger index = [args indexOfObject:name];
    return index != NSNotFound && index + 1 < args.count ? args[index + 1] : nil;
}

@interface TurboPreviewDelegate : NSObject <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation TurboPreviewDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Preview" sessionRole:session.role];
    configuration.delegateClass = TurboPreviewDelegate.class;
    return configuration;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *host = [UIViewController new];
    host.view.backgroundColor = UIColor.systemBackgroundColor;
    self.window.rootViewController = host;
    [self.window makeKeyAndVisible];

    NSString *screen = Argument(@"--screen") ?: @"hub";
    NSString *fixtureState = Argument(@"--ota-fixture");
    if (fixtureState) {
        NSDictionary *fixture = TIOPreviewOTAFixture(fixtureState);
        NSData *data = fixture ? [NSJSONSerialization dataWithJSONObject:fixture options:NSJSONWritingSortedKeys error:nil] : nil;
        NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"null";
        fprintf(stderr, "PREVIEW_OTA_FIXTURE %s %s\n", fixtureState.UTF8String, json.UTF8String);
        fflush(stderr);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *page = nil;
        if ([screen isEqual:@"hub"]) page = TIOCreateTurboPreview();
        else if ([screen isEqual:@"ota"]) page = TIOExperimentalOTAController();
        else if ([screen isEqual:@"music"]) page = TMMusicController();
        if (!page) {
            host.view.backgroundColor = UIColor.systemRedColor;
            fprintf(stderr, "PREVIEW_NIL %s\n", screen.UTF8String);
            fflush(stderr);
            return;
        }
        UIViewController *presented = [screen isEqual:@"hub"] ? page : [[UINavigationController alloc] initWithRootViewController:page];
        presented.modalPresentationStyle = UIModalPresentationFullScreen;
        [host presentViewController:presented animated:NO completion:^{
            presented.view.accessibilityIdentifier = @"preview-ready";
            fprintf(stderr, "PREVIEW_READY %s %s\n", screen.UTF8String, NSStringFromClass(presented.class).UTF8String);
            fflush(stderr);
        }];
    });
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TurboPreviewDelegate.class));
    }
}
