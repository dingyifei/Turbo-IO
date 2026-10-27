#import "ResearchUI.h"
#import "TIOLanguage.h"
#import <objc/runtime.h>
static UIColor *Color(CGFloat r,CGFloat g,CGFloat b){return [UIColor colorWithRed:r/255 green:g/255 blue:b/255 alpha:1];}
UIColor *TIOInk(void){return Color(240,237,229);}
UIColor *TIOPaper(void){return Color(23,19,27);}
UIColor *TIOAccent(void){return Color(219,246,122);}
static UIFont *Font(CGFloat size,UIFontWeight weight){return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];}
static UILabel *Label(NSString *text,CGFloat size,UIFontWeight weight){UILabel *l=[UILabel new];l.text=text;l.font=Font(size,weight);l.textColor=TIOInk();l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;return l;}
static void Pin(UIView *v,UIView *p,CGFloat inset){v.translatesAutoresizingMaskIntoConstraints=NO;[p addSubview:v];[NSLayoutConstraint activateConstraints:@[[v.leadingAnchor constraintEqualToAnchor:p.leadingAnchor constant:inset],[v.trailingAnchor constraintEqualToAnchor:p.trailingAnchor constant:-inset],[v.topAnchor constraintEqualToAnchor:p.topAnchor constant:inset],[v.bottomAnchor constraintEqualToAnchor:p.bottomAnchor constant:-inset]]];}
void TIOCloseResearch(UIViewController *source){
 if(!source)return;
 UIViewController *c=source;
 // A sheet may already be detached when its close action reaches us.
 if(!source.view.window&&source.presentingViewController)c=source.presentingViewController;
 NSMutableSet<NSValue *> *visited=[NSMutableSet new];
 while(c&&c.view.tag!=7920){
  NSValue *identity=[NSValue valueWithNonretainedObject:c];
  if([visited containsObject:identity])break;
  [visited addObject:identity];
  UIViewController *next=nil;
  for(id candidate in @[c.navigationController?:NSNull.null,c.tabBarController?:NSNull.null,
                       c.parentViewController?:NSNull.null,c.presentingViewController?:NSNull.null]){
   if(candidate!=NSNull.null&&candidate!=c&&![visited containsObject:[NSValue valueWithNonretainedObject:candidate]]){next=candidate;break;}
  }
  c=next;
 }
 UIViewController *shell=(c&&c.view.tag==7920)?c:source;
 [shell dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOResearchClosed" object:nil];}];
}
void TIOStyleResearchCell(UITableViewCell *c){
 UIColor *original=c.textLabel.textColor;BOOL disabled=(c.accessibilityTraits&UIAccessibilityTraitNotEnabled)!=0;
 BOOL warning=[original isEqual:UIColor.systemRedColor]||[original isEqual:UIColor.systemOrangeColor];
 c.backgroundColor=Color(34,29,37);c.textLabel.textColor=disabled?UIColor.tertiaryLabelColor:warning?original:TIOInk();
 c.textLabel.font=Font(16,UIFontWeightRegular);c.detailTextLabel.font=Font(13,UIFontWeightRegular);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;
 UIColor *detail=c.detailTextLabel.textColor;BOOL detailWarning=[detail isEqual:UIColor.systemRedColor]||[detail isEqual:UIColor.systemOrangeColor];
 c.detailTextLabel.textColor=detailWarning?detail:UIColor.secondaryLabelColor;c.imageView.tintColor=disabled?UIColor.tertiaryLabelColor:warning?original:TIOAccent();c.tintColor=TIOAccent();
 c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(11,16,11,16);
 if([c.accessoryView isKindOfClass:UISwitch.class])((UISwitch *)c.accessoryView).onTintColor=TIOAccent();
 UIView *selected=[UIView new];selected.backgroundColor=[TIOAccent() colorWithAlphaComponent:.07];c.selectedBackgroundView=selected;
}
/* Per-table proxy, retained by that table, weak original delegate. No global
 * UIKit swizzling, no host-app appearance changes and no gesture interception. */
@interface TIOTableTheme:NSObject<UITableViewDelegate>
@property(nonatomic,weak) id<UITableViewDelegate> original;
@end
@implementation TIOTableTheme
- (BOOL)respondsToSelector:(SEL)s{return [super respondsToSelector:s]||[self.original respondsToSelector:s];}
- (id)forwardingTargetForSelector:(SEL)s{return [self.original respondsToSelector:s]?self.original:[super forwardingTargetForSelector:s];}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section{
 if([self.original respondsToSelector:_cmd])[self.original tableView:t willDisplayHeaderView:view forSection:section];
 if([view isKindOfClass:UITableViewHeaderFooterView.class]){
  UILabel *label=((UITableViewHeaderFooterView *)view).textLabel;
  label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
  label.textColor=UIColor.secondaryLabelColor;label.adjustsFontForContentSizeCategory=YES;
 }
}
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)p{
 if([self.original respondsToSelector:_cmd])[self.original tableView:t willDisplayCell:c forRowAtIndexPath:p];TIOStyleResearchCell(c);
}
@end
static char ThemeKey;
void TIOStyleResearchTable(UITableViewController *c){
 c.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 UITableView *t=c.tableView;t.backgroundColor=TIOPaper();t.tintColor=TIOAccent();c.view.tintColor=TIOAccent();t.rowHeight=UITableViewAutomaticDimension;t.estimatedRowHeight=56;t.sectionHeaderTopPadding=12;t.cellLayoutMarginsFollowReadableWidth=YES;t.separatorColor=[UIColor.separatorColor colorWithAlphaComponent:.35];t.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
 TIOTableTheme *proxy=objc_getAssociatedObject(t,&ThemeKey);if(!proxy){proxy=[TIOTableTheme new];objc_setAssociatedObject(t,&ThemeKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}if(t.delegate!=proxy){proxy.original=t.delegate;t.delegate=proxy;}
 c.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
}
UIView *TIOFoldHeader(NSString *title,BOOL expanded,void(^toggle)(void)){
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
 UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];
 c.title=title;
 c.image=[UIImage systemImageNamed:expanded?@"chevron.down":@"chevron.right"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12]];
 c.imagePlacement=NSDirectionalRectEdgeTrailing;c.imagePadding=12;
 c.baseForegroundColor=UIColor.secondaryLabelColor;
 c.contentInsets=NSDirectionalEdgeInsetsMake(8,20,6,20);
 c.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *a){NSMutableDictionary *m=[a mutableCopy];m[NSFontAttributeName]=Font(13,UIFontWeightSemibold);return m;};
 b.configuration=c;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
 NSString *labelFormat=TIOText(expanded?@"hub.fold.expanded":@"hub.fold.collapsed");
 b.accessibilityLabel=[NSString stringWithFormat:labelFormat,title];
 b.accessibilityIdentifier=@"hub-section-developer";
 [b addAction:[UIAction actionWithHandler:^(UIAction *a){if(toggle)toggle();}] forControlEvents:UIControlEventTouchUpInside];
 return b;
}

#include "FeatureComponents.inc"
#import "FocusBridge.h"
#import "focus.h"
#include "FocusUI.inc"

UIViewController *TIOFocusController(void){return [TIOFocus new];}

@interface TIOHubNavigation:UINavigationController<UINavigationControllerDelegate>
@end
@implementation TIOHubNavigation
- (void)viewDidLoad{[super viewDidLoad];self.delegate=self;self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view.tintColor=TIOAccent();UINavigationBarAppearance *a=[UINavigationBarAppearance new];[a configureWithDefaultBackground];a.backgroundColor=[TIOPaper() colorWithAlphaComponent:.92];a.shadowColor=UIColor.clearColor;a.titleTextAttributes=@{NSForegroundColorAttributeName:TIOInk(),NSFontAttributeName:Font(17,UIFontWeightMedium)};self.navigationBar.standardAppearance=a;self.navigationBar.scrollEdgeAppearance=a;}
- (void)closeResearch{TIOCloseResearch(self);}
- (void)ensureCloseForController:(UIViewController *)v{
 NSMutableArray<UIBarButtonItem *> *info=[NSMutableArray new],*other=[NSMutableArray new];
 for(UIBarButtonItem *item in v.navigationItem.rightBarButtonItems?:@[]){
  if(item.tag==7921)continue;
  if(item.tag==7922)[info addObject:item];else [other addObject:item];
 }
 NSMutableArray<UIBarButtonItem *> *items=[NSMutableArray arrayWithArray:info];
 if(other.count<2){
  UIBarButtonItem *close=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain target:self action:@selector(closeResearch)];
  close.tag=7921;close.accessibilityLabel=TIOText(@"common.close");close.accessibilityIdentifier=@"hub-close";
  [items addObject:close];
 }
 [items addObjectsFromArray:other];
 v.navigationItem.rightBarButtonItems=items;
}
- (void)navigationController:(UINavigationController *)n willShowViewController:(UIViewController *)v animated:(BOOL)animated{
 v.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 v.view.tintColor=TIOAccent();TIOStyleFeatureSurface(v.view);
 v.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
 if([v isKindOfClass:UITableViewController.class])TIOStyleResearchTable((UITableViewController *)v);
 [self ensureCloseForController:v];
}
- (void)navigationController:(UINavigationController *)n didShowViewController:(UIViewController *)v animated:(BOOL)animated{
 [self ensureCloseForController:v];
}
- (void)pushViewController:(UIViewController *)v animated:(BOOL)animated{
 if([self.viewControllers containsObject:v]){[self popToViewController:v animated:animated];return;}
 [super pushViewController:v animated:animated];
}
@end

UINavigationController *TIOCreateTurboHub(UIViewController *root){
 NSCAssert(root!=nil,@"Turbo hub requires a root controller");
 TIOHubNavigation *hub=[[TIOHubNavigation alloc]initWithRootViewController:root];
 hub.modalPresentationStyle=UIModalPresentationFullScreen;
 hub.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 hub.view.tag=7920;
 return hub;
}

UIImage *TIOHubIcon(NSString *symbol,NSInteger section){
 static NSCache<NSString *,UIImage *> *cache;static dispatch_once_t once;
 dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=128;});
 NSString *name=symbol.length?symbol:@"circle";
 NSString *key=[NSString stringWithFormat:@"%@|%ld",name,(long)section];
 UIImage *cached=[cache objectForKey:key];if(cached)return cached;
 UIColor *fill=section==0?TIOAccent():section==1?UIColor.systemIndigoColor:
               section==2?UIColor.systemPinkColor:UIColor.systemGrayColor;
 UITraitCollection *dark=[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
 fill=[fill resolvedColorWithTraitCollection:dark];
 UIColor *ink=section==0?TIOPaper():UIColor.whiteColor;
 ink=[ink resolvedColorWithTraitCollection:dark];
 UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
 UIImage *glyph=[UIImage systemImageNamed:name withConfiguration:config];
 if(!glyph)glyph=[UIImage systemImageNamed:@"circle" withConfiguration:config];
 glyph=[glyph imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
 UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=0;format.opaque=NO;
 UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(30,30) format:format];
 UIImage *tile=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
  [fill setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,30,30) cornerRadius:7] fill];
  CGSize size=glyph.size;
  if(size.width>0&&size.height>0){CGFloat scale=MIN(20/size.width,20/size.height);
   size=CGSizeMake(size.width*scale,size.height*scale);
   [glyph drawInRect:CGRectMake((30-size.width)/2,(30-size.height)/2,size.width,size.height)];}
 }];
 tile=[tile imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
 [cache setObject:tile forKey:key];return tile;
}

void TIOHubReload(void){
 if(NSThread.isMainThread)[NSNotificationCenter.defaultCenter postNotificationName:@"TIOHubReload" object:nil];
 else dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOHubReload" object:nil];});
}
