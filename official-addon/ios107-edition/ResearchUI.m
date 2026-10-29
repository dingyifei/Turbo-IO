#import "ResearchUI.h"
#import "TIOLanguage.h"
#import "TIODesign.h"
/* Pre-design-system helpers. They only forward to TIODesign so existing call
 * sites keep compiling; new code uses TIODesign directly. */
UIColor *TIOInk(void){return TIODesignColor(TIODesignColorLabel);}
UIColor *TIOPaper(void){return TIODesignColor(TIODesignColorBg);}
UIColor *TIOAccent(void){return TIODesignColor(TIODesignColorAccent);}
static UIFont *Font(CGFloat size,UIFontWeight weight){return TIODesignLegacyFont(size,weight);}
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
void TIOStyleResearchCell(UITableViewCell *c){TIODesignStyleRow(c);}
void TIOStyleResearchTable(UITableViewController *c){
 TIODesignStyleTable(c);
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
- (void)viewDidLoad{[super viewDidLoad];self.delegate=self;self.view.tintColor=TIOAccent();UINavigationBarAppearance *a=[UINavigationBarAppearance new];[a configureWithDefaultBackground];a.backgroundColor=[TIOPaper() colorWithAlphaComponent:.92];a.shadowColor=UIColor.clearColor;a.titleTextAttributes=@{NSForegroundColorAttributeName:TIOInk(),NSFontAttributeName:Font(17,UIFontWeightMedium)};self.navigationBar.standardAppearance=a;self.navigationBar.scrollEdgeAppearance=a;}
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
 hub.view.tag=7920;
 return hub;
}

UIImage *TIOHubIcon(NSString *symbol,NSInteger section){return TIODesignHubIcon(symbol,section);}

void TIOHubReload(void){
 if(NSThread.isMainThread)[NSNotificationCenter.defaultCenter postNotificationName:@"TIOHubReload" object:nil];
 else dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOHubReload" object:nil];});
}
