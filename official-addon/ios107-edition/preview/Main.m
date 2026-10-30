#import <UIKit/UIKit.h>
#import "ExperimentalOTAUI.h"
#import "OTAWizardModel.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
#import "MenuLayoutUI.h"
#import "TDPhoneUI.h"
#import "ResearchUI.h"
#import "EditorUI.h"
#import "EditorCrop.h"
#import "TIODesign.h"
#include <stdio.h>
// Design-system gallery (docs/design-system): every token as TIODesign renders
// it, following the system appearance. DESIGN_SELFTEST compares the compiled
// UIKit values with the token tables.
static BOOL SameRGB(UIColor *color,UITraitCollection *traits,uint32_t want){
 CGFloat r=0,g=0,b=0,a=0;[[color resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a];
 uint32_t got=((uint32_t)lround(r*255)<<16)|((uint32_t)lround(g*255)<<8)|(uint32_t)lround(b*255);
 return got==want&&a==1;
}
static void DesignSelfTest(void){
 int bad=0;
 UITraitCollection *light=[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
 UITraitCollection *dark=[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
 for(NSInteger i=0;i<TIODesignColorTokenCount;i++){
  UIColor *c=TIODesignColor((TIODesignColorToken)i);
  if(!SameRGB(c,light,TIODesignColorRGB((TIODesignColorToken)i,NO))){bad++;fprintf(stderr,"DESIGN_BAD light %s\n",TIODesignColorName((TIODesignColorToken)i).UTF8String);}
  if(!SameRGB(c,dark,TIODesignColorRGB((TIODesignColorToken)i,YES))){bad++;fprintf(stderr,"DESIGN_BAD dark %s\n",TIODesignColorName((TIODesignColorToken)i).UTF8String);}
 }
 UITraitCollection *large=[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryLarge];
 UITraitCollection *ax5=[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
 for(NSInteger i=0;i<TIODesignTextStyleCount;i++){
  UIFont *f=TIODesignFontForTraits((TIODesignTextStyle)i,large);
  NSInteger css=TIODesignTextStyleCSSWeight((TIODesignTextStyle)i);
  NSString *name=f.fontName.lowercaseString;
  BOOL faceOK=css>=700?[name containsString:@"bold"]&&![name containsString:@"semibold"]:css>=600?[name containsString:@"semibold"]:css>=500?[name containsString:@"medium"]:(![name containsString:@"bold"]&&![name containsString:@"medium"]);
  if(fabs(f.pointSize-TIODesignTextStyleSize((TIODesignTextStyle)i))>.01||!faceOK){bad++;fprintf(stderr,"DESIGN_BAD font %ld %.2f %s\n",(long)i,f.pointSize,f.fontName.UTF8String);}
  if(TIODesignFontForTraits((TIODesignTextStyle)i,ax5).pointSize<=f.pointSize){bad++;fprintf(stderr,"DESIGN_BAD scaling %ld\n",(long)i);}
 }
 for(NSInteger section=0;section<4;section++){
  UIImage *icon=TIODesignHubIcon(@"gearshape",section);
  uint32_t fills[4][2]={{TIODesignColorRGB(TIODesignColorAccentFill,NO),TIODesignColorRGB(TIODesignColorAccentFill,YES)},
   {TIODesignColorRGB(TIODesignColorTileAssistant,NO),TIODesignColorRGB(TIODesignColorTileAssistant,YES)},
   {TIODesignColorRGB(TIODesignColorTileMedia,NO),TIODesignColorRGB(TIODesignColorTileMedia,YES)},
   {TIODesignColorRGB(TIODesignColorTileDeveloper,NO),TIODesignColorRGB(TIODesignColorTileDeveloper,YES)}};
  for(int mode=0;mode<2;mode++){
   UIImage *variant=[icon.imageAsset imageWithTraitCollection:mode?dark:light];
   UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc]initWithSize:variant.size];
   UIImage *flat=[r imageWithActions:^(UIGraphicsImageRendererContext *ctx){[variant drawAtPoint:CGPointZero];}];
   CGImageRef cg=flat.CGImage;CGDataProviderRef provider=CGImageGetDataProvider(cg);NSData *bytes=(__bridge_transfer NSData *)CGDataProviderCopyData(provider);
   const uint8_t *px=bytes.bytes;size_t row=CGImageGetBytesPerRow(cg),bpp=CGImageGetBitsPerPixel(cg)/8;size_t x=(size_t)(3*flat.scale),y=(size_t)(15*flat.scale);
   const uint8_t *q=px+y*row+x*bpp;
   BOOL bgra=(CGImageGetBitmapInfo(cg)&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Little;
   uint32_t got=bgra?((uint32_t)q[2]<<16)|((uint32_t)q[1]<<8)|q[0]:((uint32_t)q[0]<<16)|((uint32_t)q[1]<<8)|q[2];
   if(got!=fills[section][mode]){bad++;fprintf(stderr,"DESIGN_BAD hub icon section %ld %s got %06x want %06x\n",(long)section,mode?"dark":"light",got,fills[section][mode]);}
  }
 }
 fprintf(stderr,"DESIGN_SELFTEST %s %d\n",bad?"FAIL":"PASS",bad);fflush(stderr);
}

static UILabel *GalleryLabel(NSString *text,TIODesignTextStyle style,TIODesignColorToken color){
 UILabel *l=[UILabel new];l.text=text;l.font=TIODesignFont(style);l.textColor=TIODesignColor(color);l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;return l;
}
static UIViewController *TokensSample(void){
 UIViewController *page=[UIViewController new];page.title=@"Design tokens";page.view.backgroundColor=TIODesignColor(TIODesignColorBg);
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[page.view addSubview:scroll];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=TIOSpace4;stack.translatesAutoresizingMaskIntoConstraints=NO;
 stack.layoutMarginsRelativeArrangement=YES;stack.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(TIOSpace4,TIOSpace4,TIOSpace8,TIOSpace4);[scroll addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[
  [scroll.topAnchor constraintEqualToAnchor:page.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:page.view.bottomAnchor],
  [scroll.leadingAnchor constraintEqualToAnchor:page.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:page.view.trailingAnchor],
  [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
  [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor]]];
 NSArray<NSString *> *styles=@[@"Large title",@"Title 2",@"Title 3",@"Headline",@"Body",@"Subheadline",@"Footnote",@"Caption"];
 for(NSInteger i=0;i<TIODesignTextStyleCount;i++)[stack addArrangedSubview:GalleryLabel(styles[i],(TIODesignTextStyle)i,TIODesignColorLabel)];
 [stack addArrangedSubview:GalleryLabel(@"Secondary label",TIODesignTextStyleSubheadline,TIODesignColorLabelSecondary)];
 UIStackView *swatches=[UIStackView new];swatches.spacing=TIOSpace2;swatches.distribution=UIStackViewDistributionFillEqually;
 TIODesignColorToken swatchTokens[]={TIODesignColorBgRaised,TIODesignColorBgSunken,TIODesignColorAccent,TIODesignColorAccentSoft,TIODesignColorStatusOk,TIODesignColorStatusWarn,TIODesignColorStatusDanger};
 for(size_t i=0;i<sizeof swatchTokens/sizeof *swatchTokens;i++){
  UIView *v=[UIView new];v.backgroundColor=TIODesignColor(swatchTokens[i]);v.layer.cornerRadius=TIORadiusSM;v.layer.borderWidth=1;v.layer.borderColor=TIODesignColor(TIODesignColorSeparator).CGColor;
  [v.heightAnchor constraintEqualToConstant:TIOHitMin].active=YES;[swatches addArrangedSubview:v];
 }
 [stack addArrangedSubview:swatches];
 NSArray *roles=@[@"Start navigation",@"Open Apple Maps",@"Remove route",@"Erase everything"];
 for(NSInteger i=0;i<4;i++){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:roles[i] forState:UIControlStateNormal];b.translatesAutoresizingMaskIntoConstraints=NO;TIODesignStyleButton(b,(TIODesignButtonRole)i);b.accessibilityIdentifier=[NSString stringWithFormat:@"tokens-button-%ld",(long)i];[stack addArrangedSubview:b];}
 UIStackView *pills=[UIStackView new];pills.axis=UILayoutConstraintAxisVertical;pills.spacing=TIOSpace2;pills.alignment=UIStackViewAlignmentLeading;
 [pills addArrangedSubview:TIODesignStatusPill(TIODesignStatusOk,@"Connected")];[pills addArrangedSubview:TIODesignStatusPill(TIODesignStatusWarn,@"Update ready")];
 [pills addArrangedSubview:TIODesignStatusPill(TIODesignStatusDanger,@"Failed")];[pills addArrangedSubview:TIODesignStatusPill(TIODesignStatusNeutral,@"Idle")];
 [stack addArrangedSubview:pills];
 UITableViewCell *row=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];row.textLabel.text=@"Show on glasses";row.detailTextLabel.text=@"Apple Maps turn-by-turn";
 row.accessoryType=UITableViewCellAccessoryDisclosureIndicator;TIODesignStyleRow(row);row.layer.cornerRadius=TIORadiusLG/2;row.clipsToBounds=YES;[row.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin+TIOSpace4].active=YES;[stack addArrangedSubview:row];
 UILabel *glasses=[UILabel new];glasses.text=@"Turn right";glasses.font=TIODesignLegacyFont(TIOLensTitleSize,UIFontWeightMedium);glasses.textColor=TIODesignColor(TIODesignColorLensFull);glasses.textAlignment=NSTextAlignmentCenter;
 UIView *lens=TIODesignLensPreviewCard(glasses,@"Glasses preview: Turn right in 100 metres",NO);[stack addArrangedSubview:lens];
 [stack addArrangedSubview:TIODesignEmptyState(@"eyeglasses",@"Glasses not connected",@"Turn them on and bring them near the phone.",@"Open settings",^{})];
 return page;
}

extern UIViewController *TIOCreateTurboPreview(void);
extern UIViewController *TMMusicController(void);
extern NSDictionary *TIOPreviewOTAFixture(NSString *state);
extern UIViewController *TIOPreviewNavigationController(NSString *state);
extern NSDictionary *TIOPreviewNavigationFacts(UIViewController *panel);
extern UIViewController *TIOPreviewCaptionsController(NSString *fixture);

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
                UITableViewCell *cell=[table cellForRowAtIndexPath:path]?:[dataSource tableView:table cellForRowAtIndexPath:path];
                [rows addObject:@{@"id":cell.accessibilityIdentifier?:@"",
                                  @"title":cell.textLabel.text?:@"",
                                  @"status":cell.detailTextLabel.text?:@"",
                                  @"enabled":@(cell.userInteractionEnabled),
                                  @"movable":@([dataSource respondsToSelector:@selector(tableView:canMoveRowAtIndexPath:)]&&[dataSource tableView:table canMoveRowAtIndexPath:path]),
                                  @"speedStep":[cell.accessoryView isKindOfClass:UISegmentedControl.class]?@(((UISegmentedControl *)cell.accessoryView).selectedSegmentIndex):NSNull.null,
                                  @"switchOn":[cell.accessoryView isKindOfClass:UISwitch.class]?@(((UISwitch *)cell.accessoryView).on):NSNull.null,
                                  @"accessory":@(table.editing?cell.editingAccessoryType:cell.accessoryType),
                                  @"editingSwitch":@([cell.editingAccessoryView isKindOfClass:UISwitch.class]),
                                  @"rendered":@([table cellForRowAtIndexPath:path]!=nil)}];
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
    // The menu layout screen: its segmented control, the lens preview's VoiceOver summary and the footnote under the control.
    __block NSDictionary *layout=@{};
    Visit(controller.view,^(UIView *view){
        if([view.accessibilityIdentifier isEqual:@"layout-segments"]&&[view isKindOfClass:UISegmentedControl.class]){
            UISegmentedControl *control=(UISegmentedControl *)view;NSMutableArray *segments=[NSMutableArray array];
            for(NSInteger i=0;i<control.numberOfSegments;i++)[segments addObject:@{@"title":[control titleForSegmentAtIndex:i]?:@"",@"enabled":@([control isEnabledForSegmentAtIndex:i]),@"selected":@(control.selectedSegmentIndex==i)}];
            NSMutableDictionary *facts=[layout mutableCopy];facts[@"segments"]=segments;layout=facts;
        }
        if([view.accessibilityIdentifier isEqual:@"layout-preview"]){
            NSMutableDictionary *facts=[layout mutableCopy];facts[@"preview"]=view.accessibilityLabel?:@"";facts[@"previewIsElement"]=@(view.isAccessibilityElement);layout=facts;
        }
    });
    if(layout.count&&table){NSMutableDictionary *facts=[layout mutableCopy];facts[@"footer"]=[table.dataSource respondsToSelector:@selector(tableView:titleForFooterInSection:)]?[table.dataSource tableView:table titleForFooterInSection:1]?:@"":@"";layout=facts;}
    NSString *screen=controller.navigationItem.title?:controller.title?:@"";
    NSString *style=controller.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"dark":controller.traitCollection.userInterfaceStyle==UIUserInterfaceStyleLight?@"light":@"unspecified";
    return @{@"screen":screen,@"controllerClass":NSStringFromClass(controller.class),@"navigation":TIOPreviewNavigationFacts(controller),
             @"interfaceStyle":style,@"contentSizeCategory":controller.traitCollection.preferredContentSizeCategory?:@"",@"subtitle":subtitle,@"layout":layout,
             @"preferredLanguage":NSLocale.preferredLanguages.firstObject?:@"",@"deviceIO":@NO,@"hardwareValidated":@NO,
             @"sections":sections,@"buttons":buttons,@"steps":steps,@"editing":@(table.editing),@"selectionWhileEditing":@(table.allowsSelectionDuringEditing)};
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

// A real UIKit alert reproduces the timing of a credential Save action. No
// private UIAlertAction invocation is needed: the helper is called at the
// same point, just before or just after an animated source dismissal starts.
static void RunConfirmRaceCase(UIViewController *host, NSUInteger index,
                               NSMutableArray<NSDictionary *> *results, dispatch_block_t finished);

static void FinishConfirmRace(NSArray<NSDictionary *> *results) {
    BOOL passed=results.count==6;
    for (NSDictionary *entry in results) passed=passed && [entry[@"pass"] boolValue];
    NSDictionary *report=@{@"pass":@(passed),@"cases":results};
    NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *path=[documents URLByAppendingPathComponent:@"confirm-race-report.json"];
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    BOOL written=data && [data writeToURL:path atomically:YES];
    fprintf(stderr,"CONFIRM_RACE_%s %lu\n",passed&&written?"PASS":"FAIL",(unsigned long)results.count);
    fflush(stderr);
}

static void RunConfirmRaceCase(UIViewController *host, NSUInteger index,
                               NSMutableArray<NSDictionary *> *results, dispatch_block_t finished) {
    if (index==6) { finished(); return; }
    NSUInteger kind=index%3;
    BOOL dismissing=index>=3;
    NSString *kindName=@[@"notice",@"confirm",@"choose"][kind];
    NSString *state=dismissing?@"dismissing":@"active";
    NSString *targetTitle=[NSString stringWithFormat:@"race-%@-%@",kindName,state];
    UIAlertController *source=[UIAlertController alertControllerWithTitle:@"race-source" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [source addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text=@"invalid"; }];
    [source addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:source animated:YES completion:^{
        __block NSUInteger callbackCount=0;
        void (^invoke)(void)=^{
            UIViewController *from=dismissing?host:nil;
            if (kind==0) TIONotice(from,targetTitle,@"race-message");
            else if (kind==1) TIOConfirm(from,targetTitle,@"race-message",TIOText(@"common.ok"),YES,^{callbackCount++;});
            else TIOChoose(from,targetTitle,@"race-message",@[TIOText(@"common.ok")],0,[NSIndexSet indexSetWithIndex:0],^(NSInteger chosen) {
                (void)chosen; callbackCount++;
            });
        };
        BOOL sourceWasVisible=source.presentingViewController!=nil && source.view.window!=nil;
        if (dismissing) [source dismissViewControllerAnimated:YES completion:nil];
        invoke();
        BOOL noPrematureTarget=(source.presentedViewController==nil &&
            (host.presentedViewController==source || host.presentedViewController==nil));
        if (!dismissing) [source dismissViewControllerAnimated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.85*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            UIViewController *top=host.presentedViewController;
            BOOL onScreen=[top isKindOfClass:UIAlertController.class] && top.view.window!=nil && !top.isBeingDismissed;
            BOOL expected=onScreen && [((UIAlertController *)top).title isEqualToString:targetTitle];
            BOOL pass=sourceWasVisible && noPrematureTarget && expected && callbackCount==0;
            [results addObject:@{@"kind":kindName,@"state":state,@"pass":@(pass),
                                 @"sourceWasVisible":@(sourceWasVisible),@"noPrematureTarget":@(noPrematureTarget),
                                 @"targetOnScreen":@(expected),
                                 @"observedTitle":onScreen?(((UIAlertController *)top).title?:@""):@"",
                                 @"callbackCount":@(callbackCount)}];
            dispatch_block_t next=^{ RunConfirmRaceCase(host,index+1,results,finished); };
            if (host.presentedViewController) [host dismissViewControllerAnimated:NO completion:next];
            else dispatch_async(dispatch_get_main_queue(),next);
        });
    }];
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

    if (HasArgument(@"--confirm-race-test")) {
        fprintf(stderr,"PREVIEW_READY confirm-race %s\n",NSStringFromClass(host.class).UTF8String);
        fflush(stderr);
        NSMutableArray<NSDictionary *> *results=[NSMutableArray array];
        dispatch_async(dispatch_get_main_queue(),^{
            RunConfirmRaceCase(host,0,results,^{ FinishConfirmRace(results); });
        });
        return;
    }

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
    // push-<hub row key> opens that row's screen from the hub; developer rows need the fold open.
    BOOL pushScreen=[screen hasPrefix:@"push-"];
    [[NSUserDefaults.alloc initWithSuiteName:@"io.turboio.research.preview"] setBool:HasArgument(@"--expand-developer")||pushScreen forKey:@"hubDeveloperExpanded"];
    TIOSetUILanguageOverride(@"auto");
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *presented=nil;
        UINavigationController *navigation=nil;
        UIViewController *captionsPage=nil; // pushed from the hub after it is on screen
        if (wizard || HasArgument(@"--hub") || ([screen isEqual:@"hub"]||[screen isEqual:@"voice"]||pushScreen)) {
            if (wizard) TIOOTAWizardUseFixture(fixture?:@"ready-authorize");
            UIViewController *hub=TIOCreateTurboPreview();
            if ([hub isKindOfClass:UINavigationController.class]) {
                navigation=(UINavigationController *)hub;
                presented=hub;
            }
        } else if ([screen hasPrefix:@"editor-"]) {
            // Pages of the dashboard editor that no hub row opens directly.
            UIViewController *page=TCEPreviewController([screen substringFromIndex:7]);
            if ([page isKindOfClass:UINavigationController.class]) navigation=(UINavigationController *)page;
            else if (page) navigation=TIOCreateTurboHub(page);
            presented=navigation;
        } else if ([screen isEqual:@"tokens"]) {DesignSelfTest();navigation=[[UINavigationController alloc]initWithRootViewController:TokensSample()];presented=navigation;
        } else if ([screen isEqual:@"nav"]||[screen isEqual:@"nav-active"]) {
            // The real TIOMapKitNavigationPanel with a stub route; nav-active is the navigating state (End shown).
            UIViewController *page=TIOPreviewNavigationController([screen isEqual:@"nav-active"]?@"active":@"ready");
            if ([page isKindOfClass:UINavigationController.class]) navigation=(UINavigationController *)page;
            presented=navigation;
        } else if ([screen isEqual:@"captions"]) {
            // Pushed from the real hub, as production does, so the hub's navigation delegate styles it (its large title stays).
            captionsPage=TIOPreviewCaptionsController(Argument(@"--captions-fixture")?:@"listening");
            UIViewController *hub=captionsPage?TIOCreateTurboPreview():nil;
            if ([hub isKindOfClass:UINavigationController.class]) navigation=(UINavigationController *)hub;
            presented=navigation;
        } else if ([screen isEqual:@"ota"]) {
            UIViewController *page=TIOExperimentalOTAController();
            if (page) navigation=[[UINavigationController alloc] initWithRootViewController:page];
            presented=navigation;
        } else if ([screen isEqual:@"tiles"]) {
            UIViewController *page=TIOTileEditorPreviewController();
            if(page)navigation=TIOCreateTurboHub(page);presented=navigation;
        } else if ([screen isEqual:@"layout"] || [screen isEqual:@"layout-tmg7"]) {
            // The real menu layout screen with canned glasses: layout = TMG8 glasses (carousel stored), layout-tmg7 = older glasses.
            UIViewController *page=TIOMenuLayoutPreviewController([screen isEqual:@"layout"]?@"tmg8":@"tmg7");
            if(page)navigation=TIOCreateTurboHub(page);presented=navigation;
        } else if ([screen isEqual:@"runtime"] || [screen isEqual:@"knob"]) {
            NSString *runtimeFixture=Argument(@"--runtime-fixture")?:([screen isEqual:@"knob"]?@"completed":@"normal");
            UIViewController *page=TDPhonePreviewController(runtimeFixture);
            if(page)navigation=TIOCreateTurboHub(page);presented=navigation;
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
            } else if (captionsPage) {
                [navigation pushViewController:captionsPage animated:NO];
            } else if ([screen isEqual:@"hub"] || pushScreen || HasArgument(@"--hub")) {
                NSString *key=pushScreen?[screen substringFromIndex:5]:Argument(@"--push");
                if (key) SelectHubKey(navigation,key);
            }
            if([screen isEqual:@"tiles"]||[screen isEqual:@"knob"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{UITableView *table=FindTable(navigation.topViewController);if(table){[table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1] atScrollPosition:UITableViewScrollPositionTop animated:NO];CGPoint offset=table.contentOffset;offset.y=MAX(-table.adjustedContentInset.top,offset.y-36);[table setContentOffset:offset animated:NO];}});
            if([screen isEqual:@"tiles"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{UITableView *table=FindTable(navigation.topViewController);[table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];});
            if([screen isEqual:@"voice"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{UITableView *table=FindTable(navigation.topViewController);id<UITableViewDataSource> ds=table.dataSource;for(NSInteger section=0;section<[ds numberOfSectionsInTableView:table];section++)for(NSInteger row=0;row<[ds tableView:table numberOfRowsInSection:section];row++){NSIndexPath *ip=[NSIndexPath indexPathForRow:row inSection:section];if([[[ds tableView:table cellForRowAtIndexPath:ip] accessibilityIdentifier] isEqual:@"hub-ttsSpeed"])[table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];}});
            if ([screen isEqual:@"tokens"]&&HasArgument(@"--scroll-bottom")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{Visit(navigation.topViewController.view,^(UIView *v){if([v isKindOfClass:UIScrollView.class]&&![v isKindOfClass:UITableView.class]){UIScrollView *sv=(UIScrollView *)v;[sv setContentOffset:CGPointMake(0,MAX(0,sv.contentSize.height-sv.bounds.size.height+sv.adjustedContentInset.bottom)) animated:NO];}});});
            if (HasArgument(@"--scroll-bottom")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{ScrollHubBottom(navigation);});
            if (HasArgument(@"--report")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{WriteReport(navigation,presented);});
        }];
    });
}
@end

int main(int argc,char **argv) {
    @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(TurboPreviewDelegate.class));}
}
