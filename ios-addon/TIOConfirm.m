#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import "ResearchUI.h"
#import "TIODesign.h"

static UIViewController *TIOPresentationSource(UIViewController *from);
static UIViewController *TIOWindowRoot(void);

UIViewController *TIOTopController(void) {
    if (!NSThread.isMainThread) {
        __block UIViewController *result=nil;
        dispatch_sync(dispatch_get_main_queue(), ^{ result=TIOTopController(); });
        return result;
    }
    return TIOPresentationSource(TIOWindowRoot());
}

static UIViewController *TIOWindowRoot(void) {
    UIWindow *window=nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window=candidate; break; }
        }
        if (window) break;
    }
    // The host app also uses the legacy application-window lifecycle.
    if (!window) for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) { window=candidate; break; }
    }
    return window.rootViewController;
}

static UIViewController *TIOPresentationSource(UIViewController *from) {
    if (!from || !from.view.window) return nil;
    while (from.isBeingDismissed && from.presentingViewController) from=from.presentingViewController;
    while (from.presentedViewController && !from.presentedViewController.isBeingDismissed) {
        from=from.presentedViewController;
    }
    return from.isBeingDismissed ? nil : from;
}

static UIViewController *TIOPresenter(UIViewController *from) {
    UIViewController *source=TIOPresentationSource(from);
    return source ?: TIOTopController();
}

// UIAlertAction handlers can run before UIKit finishes dismissing the alert.
// Wait for the presentation relationship to end before invoking a caller's work.
static void TIOAfterAlertDismissal(UIViewController *alert, dispatch_block_t work) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!alert.presentingViewController) { work(); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC/60)),
                       dispatch_get_main_queue(), ^{ TIOAfterAlertDismissal(alert, work); });
    });
}

// An action handler may run before UIKit removes its source alert. The caller
// can also pass the controller underneath an alert that is already dismissing.
static UIViewController *TIOPresentationBlocker(UIViewController *from) {
    UIViewController *cursor=(from && from.view.window) ? from : TIOWindowRoot();
    for (NSUInteger depth=0;cursor && depth<32;depth++) {
        if (cursor.presentingViewController &&
            (cursor.isBeingDismissed || [cursor isKindOfClass:UIAlertController.class])) return cursor;
        UIViewController *next=cursor.presentedViewController;
        if (!next || next==cursor) break;
        cursor=next;
    }
    return nil;
}

static void TIOPresentAfterDismissal(UIViewController *from, void(^present)(UIViewController *presenter)) {
    UIViewController *blocker=TIOPresentationBlocker(from);
    if (blocker) {
        // Retain the outgoing alert until its presentation relationship ends.
        TIOAfterAlertDismissal(blocker, ^{ TIOPresentAfterDismissal(from,present); });
        return;
    }
    UIViewController *presenter=TIOPresenter(from);
    if (presenter) present(presenter);
}

void TIONotice(UIViewController *from, NSString *title, NSString *message) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TIONotice(from,title,message); });
        return;
    }
    TIOPresentAfterDismissal(from, ^(UIViewController *presenter) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:TIOText(@"common.ok") style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

void TIOConfirm(UIViewController *from, NSString *title, NSString *message,
                NSString *action, BOOL destructive, void(^confirmed)(void)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TIOConfirm(from,title,message,action,destructive,confirmed); });
        return;
    }
    TIOPresentAfterDismissal(from, ^(UIViewController *presenter) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController *weakAlert=alert;
        [alert addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:action style:destructive?UIAlertActionStyleDestructive:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *chosen) {
            UIAlertController *activeAlert=weakAlert;
            if (confirmed && activeAlert) TIOAfterAlertDismissal(activeAlert, confirmed);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

void TIOChoose(UIViewController *from, NSString *title, NSString *message,
               NSArray<NSString *> *options, NSInteger selected, NSIndexSet *destructive,
               void(^chosen)(NSInteger index)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TIOChoose(from,title,message,options,selected,destructive,chosen); });
        return;
    }
    TIOPresentAfterDismissal(from, ^(UIViewController *presenter) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
        __weak UIAlertController *weakAlert=alert;
        [options enumerateObjectsUsingBlock:^(NSString *option, NSUInteger index, __unused BOOL *stop) {
            NSString *label=(selected>=0 && index==(NSUInteger)selected)?[option stringByAppendingString:@" ✓"]:option;
            UIAlertActionStyle style=[destructive containsIndex:index]?UIAlertActionStyleDestructive:UIAlertActionStyleDefault;
            [alert addAction:[UIAlertAction actionWithTitle:label style:style handler:^(__unused UIAlertAction *action) {
                UIAlertController *activeAlert=weakAlert;
                if (chosen && activeAlert) TIOAfterAlertDismissal(activeAlert, ^{ chosen((NSInteger)index); });
            }]];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
        UIPopoverPresentationController *popover=alert.popoverPresentationController;
        popover.sourceView=presenter.view;
        popover.sourceRect=CGRectMake(CGRectGetMidX(presenter.view.bounds),100,1,1);
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

@interface TIOInfoSheet : UIViewController
- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body;
@end

@implementation TIOInfoSheet {
    NSString *_body;
}
- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body {
    if ((self=[super init])) { self.title=title; _body=[body copy]; }
    return self;
}
- (void)loadView {
    UIView *view=[UIView new];
    view.backgroundColor=TIOPaper();
    UITextView *text=[UITextView new];
    text.translatesAutoresizingMaskIntoConstraints=NO;
    text.backgroundColor=UIColor.clearColor;
    text.text=_body;
    text.editable=NO;
    text.selectable=YES;
    text.font=TIODesignFont(TIODesignTextStyleBody);
    text.textColor=TIODesignColor(TIODesignColorLabelSecondary);
    text.textContainerInset=UIEdgeInsetsMake(16,20,24,20);
    text.adjustsFontForContentSizeCategory=YES;
    text.dataDetectorTypes=UIDataDetectorTypeNone;
    [view addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [text.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [text.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [text.trailingAnchor constraintEqualToAnchor:view.trailingAnchor]
    ]];
    self.view=view;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:TIOText(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(closeInfo)];
}
- (void)closeInfo { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface TIOInfoButton : UIBarButtonItem
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,copy) NSString *infoTitle;
@property(nonatomic,copy) NSString *infoBody;
- (void)showInfo;
@end

@implementation TIOInfoButton
- (void)showInfo {
    UIViewController *presenter=TIOPresenter(self.owner);
    if (!presenter) return;
    TIOInfoSheet *sheet=[[TIOInfoSheet alloc] initWithTitle:self.infoTitle body:self.infoBody];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:sheet];
    navigation.navigationBar.prefersLargeTitles=NO;
    navigation.modalPresentationStyle=UIModalPresentationPageSheet;
    UISheetPresentationController *presentation=navigation.sheetPresentationController;
    presentation.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];
    presentation.prefersGrabberVisible=YES;
    presentation.preferredCornerRadius=16;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
@end

void TIOAttachInfo(UIViewController *vc, NSString *title, NSString *body) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TIOAttachInfo(vc,title,body); });
        return;
    }
    TIOInfoButton *button=[[TIOInfoButton alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
        style:UIBarButtonItemStylePlain target:nil action:nil];
    button.owner=vc;
    button.infoTitle=title;
    button.infoBody=body;
    button.target=button;
    button.action=@selector(showInfo);
    button.tag=7922;
    button.accessibilityLabel=TIOText(@"common.info");
    button.accessibilityIdentifier=@"info-button";
    NSMutableArray<UIBarButtonItem *> *items=[vc.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    NSIndexSet *old=[items indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *item, __unused NSUInteger index, __unused BOOL *stop) {
        return item.tag==7922;
    }];
    [items removeObjectsAtIndexes:old];
    [items insertObject:button atIndex:0];
    vc.navigationItem.rightBarButtonItems=items;
}
