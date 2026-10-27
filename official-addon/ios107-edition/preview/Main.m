#import <UIKit/UIKit.h>
#import "ExperimentalOTAUI.h"
#import "OTAWizardModel.h"
#import "TIOLanguage.h"
#include <stdio.h>

extern UIViewController *TIOCreateTurboPreview(void);
extern UIViewController *TMMusicController(void);
extern NSDictionary *TIOPreviewOTAFixture(NSString *state);

static BOOL HasArgument(NSString *name) {
    return [NSProcessInfo.processInfo.arguments containsObject:name];
}

static NSString *Argument(NSString *name) {
    NSArray<NSString *> *args=NSProcessInfo.processInfo.arguments;
    NSUInteger index=[args indexOfObject:name];
    return index!=NSNotFound && index+1<args.count ? args[index+1] : nil;
}

static void Visit(UIView *root,void(^block)(UIView *view)) {
    if (!root) return;
    block(root);
    for (UIView *child in root.subviews) Visit(child,block);
}

static BOOL EffectivelyHidden(UIView *view) {
    for (UIView *cursor=view;cursor;cursor=cursor.superview) {
        if (cursor.hidden || cursor.alpha<=.01) return YES;
    }
    return NO;
}

static UITableView *FindTable(UIViewController *controller) {
    if ([controller isKindOfClass:UITableViewController.class]) return ((UITableViewController *)controller).tableView;
    __block UITableView *found=nil;
    Visit(controller.view,^(UIView *view){if (!found && [view isKindOfClass:UITableView.class]) found=(UITableView *)view;});
    return found;
}

static NSString *HeaderTitle(UITableView *table,NSInteger section) {
    id<UITableViewDataSource> dataSource=table.dataSource;
    NSString *title=nil;
    if ([dataSource respondsToSelector:@selector(tableView:titleForHeaderInSection:)])
        title=[dataSource tableView:table titleForHeaderInSection:section];
    if (title.length) return title;
    id<UITableViewDelegate> delegate=table.delegate;
    UIView *header=[delegate respondsToSelector:@selector(tableView:viewForHeaderInSection:)] ?
        [delegate tableView:table viewForHeaderInSection:section] : nil;
    __block NSString *foldTitle=nil;
    Visit(header,^(UIView *view){
        if (foldTitle || ![view isKindOfClass:UIButton.class]) return;
        foldTitle=((UIButton *)view).configuration.title;
    });
    return foldTitle?:@"";
}

static NSDictionary *ReportFor(UIViewController *controller) {
    [controller loadViewIfNeeded];
    UITableView *table=FindTable(controller);
    NSMutableArray *sections=[NSMutableArray array];
    if (table) {
        id<UITableViewDataSource> dataSource=table.dataSource;
        NSInteger sectionCount=[dataSource respondsToSelector:@selector(numberOfSectionsInTableView:)] ?
            [dataSource numberOfSectionsInTableView:table] : 1;
        for (NSInteger section=0;section<sectionCount;section++) {
            NSMutableArray *rows=[NSMutableArray array];
            NSInteger count=[dataSource tableView:table numberOfRowsInSection:section];
            for (NSInteger row=0;row<count;row++) {
                NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell=[dataSource tableView:table cellForRowAtIndexPath:path];
                [rows addObject:@{@"id":cell.accessibilityIdentifier?:@"",
                                  @"title":cell.textLabel.text?:@"",
                                  @"status":cell.detailTextLabel.text?:@""}];
            }
            [sections addObject:@{@"title":HeaderTitle(table,section),@"rows":rows}];
        }
    }
    __block NSString *subtitle=@"";
    NSMutableArray *buttons=[NSMutableArray array],*steps=[NSMutableArray array];
    Visit(controller.view,^(UIView *view){
        NSString *identifier=view.accessibilityIdentifier;
        if ([identifier isEqual:@"ota-subtitle"] && [view isKindOfClass:UILabel.class] && !EffectivelyHidden(view))
            subtitle=((UILabel *)view).text?:@"";
        if ([identifier isEqual:@"ota-primary"] || [identifier isEqual:@"ota-secondary"]) {
            UIButton *button=[view isKindOfClass:UIButton.class]?(UIButton *)view:nil;
            if (button) [buttons addObject:@{@"id":identifier,
                @"title":button.configuration.title?:[button titleForState:UIControlStateNormal]?:@"",
                @"enabled":@(button.enabled),@"hidden":@(EffectivelyHidden(button))}];
        }
        if ([identifier hasPrefix:@"ota-step-"] && !EffectivelyHidden(view)) {
            [steps addObject:@{@"id":identifier,@"label":view.accessibilityLabel?:@"",
                               @"selected":@((view.accessibilityTraits&UIAccessibilityTraitSelected)!=0)}];
        }
    });
    NSString *screen=controller.navigationItem.title?:controller.title?:@"";
    return @{@"screen":screen,@"subtitle":subtitle,
             @"preferredLanguage":NSLocale.preferredLanguages.firstObject?:@"",
             @"sections":sections,@"buttons":buttons,@"steps":steps};
}

static void WriteReport(UINavigationController *navigation,UIViewController *fallback) {
    UIViewController *visible=navigation?:fallback;
    for (NSUInteger depth=0;visible && depth<16;depth++) {
        if (visible.presentedViewController) {visible=visible.presentedViewController;continue;}
        if ([visible isKindOfClass:UINavigationController.class]) {
            UIViewController *top=((UINavigationController *)visible).topViewController;
            if (top && top!=visible) {visible=top;continue;}
        }
        if ([visible isKindOfClass:UITabBarController.class]) {
            UIViewController *selected=((UITabBarController *)visible).selectedViewController;
            if (selected && selected!=visible) {visible=selected;continue;}
        }
        break;
    }
    visible=visible?:fallback;
    NSDictionary *report=ReportFor(visible);
    NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *file=[documents URLByAppendingPathComponent:@"ui-report.json"];
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    if (data && [data writeToURL:file atomically:YES]) NSLog(@"WP5_REPORT_WRITTEN");
    else NSLog(@"WP5_REPORT_FAILED");
}

static void SelectHubKey(UINavigationController *navigation,NSString *key) {
    UIViewController *root=navigation.viewControllers.firstObject;
    UITableView *table=FindTable(root);
    if (!table || !key.length) return;
    NSString *identifier=[@"hub-" stringByAppendingString:key];
    id<UITableViewDataSource> dataSource=table.dataSource;
    NSInteger sections=[dataSource respondsToSelector:@selector(numberOfSectionsInTableView:)] ?
        [dataSource numberOfSectionsInTableView:table] : 1;
    for (NSInteger section=0;section<sections;section++) {
        NSInteger rows=[dataSource tableView:table numberOfRowsInSection:section];
        for (NSInteger row=0;row<rows;row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
            UITableViewCell *cell=[dataSource tableView:table cellForRowAtIndexPath:path];
            if (![cell.accessibilityIdentifier isEqual:identifier]) continue;
            id<UITableViewDelegate> delegate=(id<UITableViewDelegate>)root;
            if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)])
                [delegate tableView:table didSelectRowAtIndexPath:path];
            return;
        }
    }
    NSLog(@"WP5_PUSH_NOT_FOUND %@",key);
}

static void ScrollHubBottom(UINavigationController *navigation) {
    UITableView *table=FindTable(navigation.viewControllers.firstObject);
    id<UITableViewDataSource> dataSource=table.dataSource;
    if (!table || !dataSource) return;
    NSInteger sections=[dataSource respondsToSelector:@selector(numberOfSectionsInTableView:)] ?
        [dataSource numberOfSectionsInTableView:table] : 1;
    for (NSInteger section=sections-1;section>=0;section--) {
        NSInteger rows=[dataSource tableView:table numberOfRowsInSection:section];
        if (!rows) continue;
        [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows-1 inSection:section]
                     atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        break;
    }
}

@interface TurboPreviewDelegate : NSObject<UIApplicationDelegate,UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end

@implementation TurboPreviewDelegate
- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)options {return YES;}
- (UISceneConfiguration *)application:(__unused UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Preview" sessionRole:session.role];
    configuration.delegateClass=TurboPreviewDelegate.class;
    return configuration;
}
- (void)scene:(UIScene *)scene willConnectToSession:(__unused UISceneSession *)session options:(__unused UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *host=[UIViewController new];
    host.view.backgroundColor=UIColor.systemBackgroundColor;
    self.window.rootViewController=host;
    [self.window makeKeyAndVisible];

    NSString *screen=Argument(@"--screen")?:@"hub";
    NSString *fixture=Argument(@"--ota-fixture");
    BOOL wizard=HasArgument(@"--ota-wizard");
    if (fixture) {
        NSDictionary *value=wizard?TIOOTAWizardFixture(fixture):TIOPreviewOTAFixture(fixture);
        NSData *data=value?[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil]:nil;
        NSString *json=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"null";
        fprintf(stderr,"PREVIEW_OTA_FIXTURE %s %s\n",fixture.UTF8String,json.UTF8String);
        fflush(stderr);
    }
    [[NSUserDefaults.alloc initWithSuiteName:@"io.turboio.research.preview"] setBool:HasArgument(@"--expand-developer") forKey:@"hubDeveloperExpanded"];
    TIOSetUILanguageOverride(@"auto");
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *presented=nil;
        UINavigationController *navigation=nil;
        if (wizard || HasArgument(@"--hub") || [screen isEqual:@"hub"]) {
            if (wizard) TIOOTAWizardUseFixture(fixture?:@"ready-authorize");
            UIViewController *hub=TIOCreateTurboPreview();
            if ([hub isKindOfClass:UINavigationController.class]) {
                navigation=(UINavigationController *)hub;
                presented=hub;
            }
        } else if ([screen isEqual:@"ota"]) {
            UIViewController *page=TIOExperimentalOTAController();
            if (page) navigation=[[UINavigationController alloc] initWithRootViewController:page];
            presented=navigation;
        } else if ([screen isEqual:@"music"]) {
            UIViewController *page=TMMusicController();
            if (page) navigation=[[UINavigationController alloc] initWithRootViewController:page];
            presented=navigation;
        }
        if (!presented) {
            host.view.backgroundColor=UIColor.systemRedColor;
            fprintf(stderr,"PREVIEW_NIL %s\n",screen.UTF8String);fflush(stderr);
            return;
        }
        presented.modalPresentationStyle=UIModalPresentationFullScreen;
        [host presentViewController:presented animated:NO completion:^{
            presented.view.accessibilityIdentifier=@"preview-ready";
            fprintf(stderr,"PREVIEW_READY %s %s\n",screen.UTF8String,NSStringFromClass(presented.class).UTF8String);
            fflush(stderr);
            if (wizard) {
                [navigation pushViewController:TIOExperimentalOTAController() animated:NO];
            } else if ([screen isEqual:@"hub"] || HasArgument(@"--hub")) {
                NSString *key=Argument(@"--push");
                if (key) SelectHubKey(navigation,key);
            }
            if (HasArgument(@"--scroll-bottom")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{ScrollHubBottom(navigation);});
            if (HasArgument(@"--report")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{WriteReport(navigation,presented);});
        }];
    });
}
@end

int main(int argc,char **argv) {
    @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(TurboPreviewDelegate.class));}
}
