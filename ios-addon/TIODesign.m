#import "TIODesign.h"
#import <objc/runtime.h>

#pragma mark Colors

typedef struct { const char *name; uint32_t light; uint32_t dark; } TIODesignColorRow;
#define TIO_DESIGN_COLOR_ROW(Id,name,light,dark) {name,light,dark},
static const TIODesignColorRow ColorRows[]={TIO_DESIGN_COLORS(TIO_DESIGN_COLOR_ROW)};
#undef TIO_DESIGN_COLOR_ROW

static UIColor *RGB(uint32_t value){
 return [UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
}

UIColor *TIODesignColor(TIODesignColorToken token){
 static UIColor *cache[TIODesignColorTokenCount];static dispatch_once_t once;
 dispatch_once(&once,^{
  for(NSInteger i=0;i<TIODesignColorTokenCount;i++){
   uint32_t light=ColorRows[i].light,dark=ColorRows[i].dark;
   if(light==dark)cache[i]=RGB(light);
   else cache[i]=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){
    return RGB(traits.userInterfaceStyle==UIUserInterfaceStyleDark?dark:light);
   }];
  }
 });
 return (token>=0&&token<TIODesignColorTokenCount)?cache[token]:cache[TIODesignColorLabel];
}
NSString *TIODesignColorName(TIODesignColorToken token){
 return (token>=0&&token<TIODesignColorTokenCount)?@(ColorRows[token].name):@"";
}
UIColor *TIODesignColorNamed(NSString *name){
 for(NSInteger i=0;i<TIODesignColorTokenCount;i++)if(strcmp(ColorRows[i].name,name.UTF8String)==0)return TIODesignColor((TIODesignColorToken)i);
 return nil;
}
uint32_t TIODesignColorRGB(TIODesignColorToken token, BOOL dark){
 if(token<0||token>=TIODesignColorTokenCount)return 0;
 return dark?ColorRows[token].dark:ColorRows[token].light;
}

#pragma mark Type

typedef struct { const char *name; CGFloat size; CGFloat line; NSInteger weight; CGFloat tracking; } TIODesignTypeRow;
#define TIO_DESIGN_TYPE_ROW(Id,name,size,line,weight,tracking) {name,size,line,weight,tracking},
static const TIODesignTypeRow TypeRows[]={TIO_DESIGN_TYPES(TIO_DESIGN_TYPE_ROW)};
#undef TIO_DESIGN_TYPE_ROW

static UIFontWeight WeightForCSS(NSInteger css){
 return css>=700?UIFontWeightBold:css>=600?UIFontWeightSemibold:css>=500?UIFontWeightMedium:UIFontWeightRegular;
}
static UIFontTextStyle SystemStyle(TIODesignTextStyle style){
 switch(style){
  case TIODesignTextStyleLargeTitle:return UIFontTextStyleLargeTitle;
  case TIODesignTextStyleTitle2:return UIFontTextStyleTitle2;
  case TIODesignTextStyleTitle3:return UIFontTextStyleTitle3;
  case TIODesignTextStyleHeadline:return UIFontTextStyleHeadline;
  case TIODesignTextStyleSubheadline:return UIFontTextStyleSubheadline;
  case TIODesignTextStyleFootnote:return UIFontTextStyleFootnote;
  case TIODesignTextStyleCaption:return UIFontTextStyleCaption1;
  default:return UIFontTextStyleBody;
 }
}
static const TIODesignTypeRow *TypeRow(TIODesignTextStyle style){
 return &TypeRows[(style>=0&&style<TIODesignTextStyleCount)?style:TIODesignTextStyleBody];
}
static UIFont *ScaledFont(TIODesignTextStyle style,UIFont *base,UITraitCollection *traits){
 UIFontMetrics *metrics=[UIFontMetrics metricsForTextStyle:SystemStyle(style)];
 return traits?[metrics scaledFontForFont:base compatibleWithTraitCollection:traits]:[metrics scaledFontForFont:base];
}
UIFont *TIODesignFontForTraits(TIODesignTextStyle style, UITraitCollection *traits){
 const TIODesignTypeRow *row=TypeRow(style);
 return ScaledFont(style,[UIFont systemFontOfSize:row->size weight:WeightForCSS(row->weight)],traits);
}
UIFont *TIODesignFont(TIODesignTextStyle style){return TIODesignFontForTraits(style,nil);}
UIFont *TIODesignFontWeight(TIODesignTextStyle style, UIFontWeight weight){
 return ScaledFont(style,[UIFont systemFontOfSize:TypeRow(style)->size weight:weight],nil);
}
UIFont *TIODesignMonospacedDigitFont(TIODesignTextStyle style){
 const TIODesignTypeRow *row=TypeRow(style);
 return ScaledFont(style,[UIFont monospacedDigitSystemFontOfSize:row->size weight:WeightForCSS(row->weight)],nil);
}
UIFont *TIODesignMonospacedDigitFontMagnified(TIODesignTextStyle style, CGFloat factor, CGFloat maximum){
 const TIODesignTypeRow *row=TypeRow(style);
 UIFont *base=[UIFont monospacedDigitSystemFontOfSize:row->size*factor weight:WeightForCSS(row->weight)];
 return [[UIFontMetrics metricsForTextStyle:SystemStyle(style)] scaledFontForFont:base maximumPointSize:maximum];
}
NSString *TIODesignTextStyleName(TIODesignTextStyle style){return @(TypeRow(style)->name);}
CGFloat TIODesignTextStyleSize(TIODesignTextStyle style){return TypeRow(style)->size;}
CGFloat TIODesignTextStyleLineHeight(TIODesignTextStyle style){return TypeRow(style)->line;}
UIFontWeight TIODesignTextStyleWeight(TIODesignTextStyle style){return WeightForCSS(TypeRow(style)->weight);}
NSInteger TIODesignTextStyleCSSWeight(TIODesignTextStyle style){return TypeRow(style)->weight;}
CGFloat TIODesignTextStyleTracking(TIODesignTextStyle style){return TypeRow(style)->tracking;}
UIFont *TIODesignLegacyFont(CGFloat size, UIFontWeight weight){
 return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
}

UIFont *TIODesignLensFont(CGFloat glassesPixels, CGFloat previewScale, UIFontWeight weight){
 return [UIFont monospacedDigitSystemFontOfSize:MAX(1,glassesPixels*previewScale) weight:weight];
}

#pragma mark Numbers

typedef struct { const char *name; CGFloat first; CGFloat second; BOOL pair; } TIODesignNumberRow;
#define TIO_DESIGN_NUMBER_1(Id,name,value) {name,(value),0,NO},
#define TIO_DESIGN_NUMBER_2(name,A,a,B,b) {name,(a),(b),YES},
static const TIODesignNumberRow NumberRows[]={
 TIO_DESIGN_NUMBERS_1(TIO_DESIGN_NUMBER_1)
 TIO_DESIGN_NUMBERS_2(TIO_DESIGN_NUMBER_2)
};
#undef TIO_DESIGN_NUMBER_1
#undef TIO_DESIGN_NUMBER_2
BOOL TIODesignNumber(NSString *name, CGFloat *first, CGFloat *second){
 for(size_t i=0;i<sizeof NumberRows/sizeof *NumberRows;i++){
  if(strcmp(NumberRows[i].name,name.UTF8String)!=0)continue;
  if(first)*first=NumberRows[i].first;
  if(second)*second=NumberRows[i].second;
  return YES;
 }
 return NO;
}
NSArray<NSString *> *TIODesignNumberNames(void){
 NSMutableArray *names=[NSMutableArray new];
 for(size_t i=0;i<sizeof NumberRows/sizeof *NumberRows;i++)[names addObject:@(NumberRows[i].name)];
 return names;
}

#pragma mark Motion

BOOL TIODesignReduceMotion(void){return UIAccessibilityIsReduceMotionEnabled();}
void TIODesignAnimate(NSTimeInterval duration, void (^animations)(void), void (^completion)(BOOL finished)){
 if(TIODesignReduceMotion()||duration<=0){
  animations();if(completion)completion(YES);return;
 }
 [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:animations completion:completion];
}

#pragma mark Buttons

void TIODesignStyleButton(UIButton *button, TIODesignButtonRole role){
 NSString *title=button.configuration.title?:[button titleForState:UIControlStateNormal];
 UIButtonConfiguration *c;
 UIColor *accent=TIODesignColor(TIODesignColorAccent),*danger=TIODesignColor(TIODesignColorStatusDanger);
 switch(role){
  case TIODesignButtonPrimary:
   c=UIButtonConfiguration.filledButtonConfiguration;
   c.baseBackgroundColor=TIODesignColor(TIODesignColorAccentFill);c.baseForegroundColor=TIODesignColor(TIODesignColorOnAccent);break;
  case TIODesignButtonDestructiveFilled:
   c=UIButtonConfiguration.filledButtonConfiguration;
   c.baseBackgroundColor=danger;c.baseForegroundColor=TIODesignColor(TIODesignColorOnAccent);break;   /* white on light danger (5.4:1), the dark surface color on dark danger (6.5:1); white on dark danger is 2.8:1 */
  case TIODesignButtonDestructive:
   c=UIButtonConfiguration.plainButtonConfiguration;c.baseForegroundColor=danger;break;
  case TIODesignButtonSecondary:default:
   c=UIButtonConfiguration.tintedButtonConfiguration;
   c.baseForegroundColor=accent;c.background.backgroundColor=TIODesignColor(TIODesignColorAccentSoft);break;
 }
 c.title=title;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
 /* 14 + 22 pt headline line + 14 = 50 pt before Dynamic Type grows it. */
 c.contentInsets=NSDirectionalEdgeInsetsMake(14,TIOSpace5,14,TIOSpace5);
 c.titleTextAttributesTransformer=^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes){
  NSMutableDictionary *m=[attributes mutableCopy];m[NSFontAttributeName]=TIODesignFont(TIODesignTextStyleHeadline);return m;
 };
 button.configuration=c;button.titleLabel.adjustsFontForContentSizeCategory=YES;
 button.tintColor=accent;
 /* Floor the height only for Auto Layout buttons: a frame-based button keeps its frame. */
 static NSString *const floorID=@"TIODesign.buttonHeight";
 if(!button.translatesAutoresizingMaskIntoConstraints){
  BOOL found=NO;for(NSLayoutConstraint *k in button.constraints)if([k.identifier isEqualToString:floorID]){found=YES;break;}
  if(!found){NSLayoutConstraint *k=[button.heightAnchor constraintGreaterThanOrEqualToConstant:TIOButtonHeight];k.identifier=floorID;k.active=YES;}
 }
}

#pragma mark Lists

static BOOL IsWarning(UIColor *color){
 return [color isEqual:UIColor.systemRedColor]||[color isEqual:UIColor.systemOrangeColor]||
        [color isEqual:TIODesignColor(TIODesignColorStatusDanger)]||[color isEqual:TIODesignColor(TIODesignColorStatusWarn)];
}
static UIColor *WarningToken(UIColor *color){
 if([color isEqual:UIColor.systemRedColor])return TIODesignColor(TIODesignColorStatusDanger);
 if([color isEqual:UIColor.systemOrangeColor])return TIODesignColor(TIODesignColorStatusWarn);
 return color;
}

void TIODesignStyleRow(UITableViewCell *c){
 UIColor *original=c.textLabel.textColor;BOOL disabled=(c.accessibilityTraits&UIAccessibilityTraitNotEnabled)!=0;
 BOOL warning=IsWarning(original);
 UIColor *tertiary=TIODesignColor(TIODesignColorLabelTertiary),*accent=TIODesignColor(TIODesignColorAccent);
 c.backgroundColor=TIODesignColor(TIODesignColorBgRaised);
 /* A row may ask for an action (accent or system blue), secondary or tertiary text; any other color is the primary label. */
 UIColor *text=TIODesignColor(TIODesignColorLabel);
 if([original isEqual:accent]||[original isEqual:UIColor.systemBlueColor])text=accent;
 else if([original isEqual:UIColor.secondaryLabelColor])text=TIODesignColor(TIODesignColorLabelSecondary);
 else if([original isEqual:UIColor.tertiaryLabelColor])text=tertiary;
 c.textLabel.textColor=disabled?tertiary:warning?WarningToken(original):text;
 c.textLabel.font=TIODesignFont(TIODesignTextStyleBody);c.detailTextLabel.font=TIODesignFont(TIODesignTextStyleSubheadline);
 c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;
 UIColor *detail=c.detailTextLabel.textColor;
 c.detailTextLabel.textColor=IsWarning(detail)?WarningToken(detail):TIODesignColor(TIODesignColorLabelSecondary);
 c.imageView.tintColor=disabled?tertiary:warning?WarningToken(original):accent;c.tintColor=accent;
 c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(TIOSpace3,TIOSpace4,TIOSpace3,TIOSpace4);
 if([c.accessoryView isKindOfClass:UISwitch.class])((UISwitch *)c.accessoryView).onTintColor=accent;
 UIView *selected=[UIView new];selected.backgroundColor=TIODesignColor(TIODesignColorAccentSoft);c.selectedBackgroundView=selected;
}

UIView *TIODesignValueAccessory(NSString *value){
 UILabel *label=[UILabel new];label.text=value;label.font=TIODesignFont(TIODesignTextStyleBody);
 label.textColor=TIODesignColor(TIODesignColorLabelSecondary);label.adjustsFontForContentSizeCategory=YES;
 UIImageSymbolConfiguration *symbol=[UIImageSymbolConfiguration configurationWithFont:TIODesignFontWeight(TIODesignTextStyleFootnote,UIFontWeightSemibold)];
 UIImageView *chevron=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:symbol]];
 chevron.tintColor=TIODesignColor(TIODesignColorLabelTertiary);chevron.contentMode=UIViewContentModeCenter;
 [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[label,chevron]];
 stack.axis=UILayoutConstraintAxisHorizontal;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=TIOSpace2;
 CGSize size=[stack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
 stack.frame=CGRectMake(0,0,ceil(size.width),MAX(ceil(size.height),TIOHitMin));
 stack.isAccessibilityElement=NO;stack.accessibilityElementsHidden=YES;
 return stack;
}

@interface TIODesignSegmentedHost:UIView
@property(nonatomic,strong) UISegmentedControl *control;
@property(nonatomic,strong) UIButton *menuButton;
@property(nonatomic,copy) NSString *choiceLabel;
@end
@implementation TIODesignSegmentedHost
- (instancetype)initWithControl:(UISegmentedControl *)control label:(NSString *)label{
 self=[super initWithFrame:CGRectZero];if(!self)return nil;
 _control=control;_choiceLabel=[label copy];
 UIButtonConfiguration *c=UIButtonConfiguration.tintedButtonConfiguration;
 c.baseForegroundColor=TIODesignColor(TIODesignColorAccent);c.background.backgroundColor=TIODesignColor(TIODesignColorAccentSoft);
 c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;c.image=[UIImage systemImageNamed:@"chevron.up.chevron.down"];
 c.imagePlacement=NSDirectionalRectEdgeTrailing;c.imagePadding=TIOSpace2;
 _menuButton=[UIButton buttonWithType:UIButtonTypeSystem];_menuButton.configuration=c;_menuButton.showsMenuAsPrimaryAction=YES;
 [_menuButton.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;
 [control.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[control,_menuButton]];stack.axis=UILayoutConstraintAxisVertical;
 stack.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]]];
 for(NSString *key in @[@"enabled",@"selectedSegmentIndex"])[control addObserver:self forKeyPath:key options:0 context:NULL];
 [self update];return self;
}
- (void)dealloc{for(NSString *key in @[@"enabled",@"selectedSegmentIndex"])[_control removeObserver:self forKeyPath:key];}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{[self update];}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{[super traitCollectionDidChange:previous];[self update];}
- (void)layoutSubviews{[super layoutSubviews];[self update];}
- (void)update{
 BOOL ax=UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
 UIFont *font=TIODesignFont(TIODesignTextStyleSubheadline);
 [_control setTitleTextAttributes:@{NSFontAttributeName:font} forState:UIControlStateNormal];
 [_control setTitleTextAttributes:@{NSFontAttributeName:font} forState:UIControlStateSelected];
 _control.apportionsSegmentWidthsByContent=YES;
 // Menu when the text size is an accessibility size, or when the titles do not fit on one line at this width.
 CGFloat need=[_control sizeThatFits:CGSizeMake(CGFLOAT_MAX,TIOHitMin)].width;
 BOOL menu=ax||(self.bounds.size.width>0&&need>self.bounds.size.width+.5);
 _control.hidden=menu;_menuButton.hidden=!menu;if(!menu)return;
 NSInteger selected=_control.selectedSegmentIndex;NSString *title=selected>=0?[_control titleForSegmentAtIndex:selected]:@"";
 UIButtonConfiguration *c=_menuButton.configuration;if(![c.title isEqual:title]){c.title=title;_menuButton.configuration=c;}
 _menuButton.enabled=_control.enabled;_menuButton.accessibilityLabel=_choiceLabel;_menuButton.accessibilityValue=title;
 NSMutableArray<UIAction *> *actions=[NSMutableArray new];__weak typeof(self) weak=self;
 for(NSInteger index=0;index<_control.numberOfSegments;index++){
  UIAction *action=[UIAction actionWithTitle:[_control titleForSegmentAtIndex:index]?:@"" image:nil identifier:nil handler:^(UIAction *x){
   TIODesignSegmentedHost *strong=weak;if(!strong)return;
   strong.control.selectedSegmentIndex=index;[strong.control sendActionsForControlEvents:UIControlEventValueChanged];[strong update];
  }];
  action.state=index==selected?UIMenuElementStateOn:UIMenuElementStateOff;
  if(![_control isEnabledForSegmentAtIndex:index])action.attributes=UIMenuElementAttributesDisabled; /* a disabled segment is a disabled menu item */
  [actions addObject:action];
 }
 _menuButton.menu=[UIMenu menuWithChildren:actions];
}
@end
UIView *TIODesignSegmentedChoice(UISegmentedControl *control, NSString *label){
 return [[TIODesignSegmentedHost alloc]initWithControl:control label:label];
}

void TIODesignStyleHeaderLabel(UILabel *label){
 label.font=TIODesignFont(TIODesignTextStyleFootnote);
 label.textColor=TIODesignColor(TIODesignColorLabelSecondary);label.adjustsFontForContentSizeCategory=YES;
}

/* Per-table proxy, retained by that table, weak original delegate. No global
 * UIKit swizzling, no host-app appearance changes and no gesture interception. */
@interface TIODesignTableTheme:NSObject<UITableViewDelegate>
@property(nonatomic,weak) id<UITableViewDelegate> original;
@end
@implementation TIODesignTableTheme
- (BOOL)respondsToSelector:(SEL)s{return [super respondsToSelector:s]||[self.original respondsToSelector:s];}
- (id)forwardingTargetForSelector:(SEL)s{return [self.original respondsToSelector:s]?self.original:[super forwardingTargetForSelector:s];}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section{
 if([self.original respondsToSelector:_cmd])[self.original tableView:t willDisplayHeaderView:view forSection:section];
 if([view isKindOfClass:UITableViewHeaderFooterView.class])TIODesignStyleHeaderLabel(((UITableViewHeaderFooterView *)view).textLabel);
}
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)p{
 if([self.original respondsToSelector:_cmd])[self.original tableView:t willDisplayCell:c forRowAtIndexPath:p];
 TIODesignStyleRow(c);
}
@end
static char ThemeKey;
void TIODesignStyleTable(UITableViewController *c){
 UIColor *accent=TIODesignColor(TIODesignColorAccent);
 UITableView *t=c.tableView;t.backgroundColor=TIODesignColor(TIODesignColorBg);t.tintColor=accent;c.view.tintColor=accent;
 t.rowHeight=UITableViewAutomaticDimension;t.estimatedRowHeight=56;t.sectionHeaderTopPadding=TIOSpace3;
 t.cellLayoutMarginsFollowReadableWidth=YES;t.separatorColor=TIODesignColor(TIODesignColorSeparator);
 t.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
 TIODesignTableTheme *proxy=objc_getAssociatedObject(t,&ThemeKey);
 if(!proxy){proxy=[TIODesignTableTheme new];objc_setAssociatedObject(t,&ThemeKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 if(t.delegate!=proxy){proxy.original=t.delegate;t.delegate=proxy;}
 /* The hub root keeps its large title; pushed pages use standard titles unless they set a mode themselves. */
 UINavigationController *nav=c.navigationController;
 BOOL root=nav&&nav.viewControllers.firstObject==c&&nav.navigationBar.prefersLargeTitles;
 if(root)c.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeAlways;
 else if(c.navigationItem.largeTitleDisplayMode==UINavigationItemLargeTitleDisplayModeAutomatic)c.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever; /* a page that asked for the large title itself (the caption panels) keeps it */
}

/* Normalize only standard system surfaces in our navigation subtree. Preview
 * canvases, maps, status colors and custom image rendering remain untouched. */
void TIODesignStyleSurface(UIView *view){
 UIColor *bg=view.backgroundColor,*accent=TIODesignColor(TIODesignColorAccent);
 if([bg isEqual:UIColor.systemBackgroundColor]||[bg isEqual:UIColor.systemGroupedBackgroundColor])view.backgroundColor=TIODesignColor(TIODesignColorBg);
 else if([bg isEqual:UIColor.secondarySystemGroupedBackgroundColor])view.backgroundColor=TIODesignColor(TIODesignColorBgRaised);
 if([view isKindOfClass:UITextView.class]){UITextView *text=(id)view;text.tintColor=accent;text.adjustsFontForContentSizeCategory=YES;}
 if([view isKindOfClass:UITextField.class]){UITextField *field=(id)view;field.tintColor=accent;field.textColor=TIODesignColor(TIODesignColorLabel);}
 if([view isKindOfClass:UIButton.class]){
  UIButton *button=(id)view;UIButtonConfiguration *c=button.configuration;
  if([c.baseBackgroundColor isEqual:UIColor.systemIndigoColor]||[c.baseBackgroundColor isEqual:UIColor.systemBlueColor]){
   c.baseBackgroundColor=TIODesignColor(TIODesignColorAccentFill);c.baseForegroundColor=TIODesignColor(TIODesignColorOnAccent);button.configuration=c;
  }
 }
 for(UIView *child in view.subviews)TIODesignStyleSurface(child);
}

#pragma mark Hub icon

static UIImage *RenderHubTile(UIColor *fill,UIColor *ink,NSString *name,UITraitCollection *traits){
 UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
 UIImage *glyph=[UIImage systemImageNamed:name withConfiguration:config];
 if(!glyph)glyph=[UIImage systemImageNamed:@"circle" withConfiguration:config];
 glyph=[glyph imageWithTintColor:[ink resolvedColorWithTraitCollection:traits] renderingMode:UIImageRenderingModeAlwaysOriginal];
 UIColor *resolved=[fill resolvedColorWithTraitCollection:traits];
 UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=traits.displayScale>0?traits.displayScale:UITraitCollection.currentTraitCollection.displayScale;if(format.scale<1)format.scale=2;format.opaque=NO;
 CGFloat tile=TIOIconTile;
 UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(tile,tile) format:format];
 UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
  [resolved setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,tile,tile) cornerRadius:TIORadiusSM] fill];
  CGSize size=glyph.size;
  if(size.width>0&&size.height>0){
   CGFloat scale=MIN(20/size.width,20/size.height);size=CGSizeMake(size.width*scale,size.height*scale);
   [glyph drawInRect:CGRectMake((tile-size.width)/2,(tile-size.height)/2,size.width,size.height)];
  }
 }];
 return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *TIODesignHubIcon(NSString *symbol, NSInteger section){
 static NSCache<NSString *,UIImage *> *cache;static dispatch_once_t once;
 dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=128;});
 NSString *name=symbol.length?symbol:@"circle";
 NSString *key=[NSString stringWithFormat:@"%@|%ld",name,(long)section];
 UIImage *cached=[cache objectForKey:key];if(cached)return cached;
 UIColor *fill=TIODesignColor(section==0?TIODesignColorAccentFill:section==1?TIODesignColorTileAssistant:
                              section==2?TIODesignColorTileMedia:TIODesignColorTileDeveloper);
 UIColor *ink=section==0?TIODesignColor(TIODesignColorOnAccent):UIColor.whiteColor;
  CGFloat displayScale=UITraitCollection.currentTraitCollection.displayScale;if(displayScale<1)displayScale=2;
  UITraitCollection *scale=[UITraitCollection traitCollectionWithDisplayScale:displayScale];
  UITraitCollection *lightTraits=[UITraitCollection traitCollectionWithTraitsFromCollections:@[scale,[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]]];
  UITraitCollection *darkTraits=[UITraitCollection traitCollectionWithTraitsFromCollections:@[scale,[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]]];
 UIImage *light=RenderHubTile(fill,ink,name,lightTraits),*dark=RenderHubTile(fill,ink,name,darkTraits);
 [light.imageAsset registerImage:dark withTraitCollection:darkTraits];
 [cache setObject:light forKey:key];return light;
}

#pragma mark Status and empty state

/* A capsule: the radius is clamped to half the height, because a 999 pt mask would clip everything. */
@interface TIODesignPillView:UIStackView
@end
@implementation TIODesignPillView
- (void)layoutSubviews{[super layoutSubviews];self.layer.cornerRadius=MIN(TIORadiusPill,CGRectGetHeight(self.bounds)/2);}
@end

/* The word is set in `label`, not in the status color: the status colors on their own 15% tint reach only 3.7 to 4.3:1 in light
 * (4.5:1 needed at 13 pt) and the neutral label-secondary on bg-sunken 4.2:1. The symbol carries the status color (3:1 for
 * graphics) and the tint; TIODesignTests asserts every pairing in both themes. */
UIView *TIODesignStatusPill(TIODesignStatus status, NSString *word){
 UIColor *color;NSString *symbol;
 switch(status){
  case TIODesignStatusOk:color=TIODesignColor(TIODesignColorStatusOk);symbol=@"checkmark.circle.fill";break;
  case TIODesignStatusWarn:color=TIODesignColor(TIODesignColorStatusWarn);symbol=@"exclamationmark.triangle.fill";break;
  case TIODesignStatusDanger:color=TIODesignColor(TIODesignColorStatusDanger);symbol=@"xmark.octagon.fill";break;
  default:color=TIODesignColor(TIODesignColorLabelSecondary);symbol=@"circle.fill";break;
 }
 UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleFootnote scale:UIImageSymbolScaleSmall];
 UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]];
 icon.tintColor=color;icon.contentMode=UIViewContentModeScaleAspectFit;icon.isAccessibilityElement=NO;icon.accessibilityElementsHidden=YES;
 [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
 UILabel *label=[UILabel new];label.text=word;label.font=TIODesignFontWeight(TIODesignTextStyleFootnote,UIFontWeightSemibold);
 label.textColor=TIODesignColor(TIODesignColorLabel);label.adjustsFontForContentSizeCategory=YES;label.numberOfLines=0;
 UIStackView *stack=[[TIODesignPillView alloc]initWithArrangedSubviews:@[icon,label]];
 stack.axis=UILayoutConstraintAxisHorizontal;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=TIOSpace1;
 stack.layoutMarginsRelativeArrangement=YES;stack.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(TIOSpace1,TIOSpace2,TIOSpace1,TIOSpace2);
 stack.backgroundColor=status==TIODesignStatusNeutral?TIODesignColor(TIODesignColorBgSunken):[color colorWithAlphaComponent:.15];
 stack.layer.cornerCurve=kCACornerCurveContinuous;stack.layer.masksToBounds=YES;
 [stack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
 stack.isAccessibilityElement=YES;stack.accessibilityLabel=word;stack.accessibilityTraits=UIAccessibilityTraitStaticText;
 return stack;
}

UIView *TIODesignEmptyState(NSString *symbol, NSString *title, NSString *detail, NSString *actionTitle, void (^action)(void)){
 UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:38 weight:UIImageSymbolWeightRegular];
 UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]];
 icon.tintColor=TIODesignColor(TIODesignColorAccent);icon.contentMode=UIViewContentModeScaleAspectFit;
 icon.isAccessibilityElement=NO;icon.accessibilityElementsHidden=YES;
 UILabel *name=[UILabel new],*text=[UILabel new];
 name.text=title;name.font=TIODesignFont(TIODesignTextStyleTitle3);name.textColor=TIODesignColor(TIODesignColorLabel);
 text.text=detail;text.font=TIODesignFont(TIODesignTextStyleSubheadline);text.textColor=TIODesignColor(TIODesignColorLabelSecondary);
 for(UILabel *l in @[name,text]){l.numberOfLines=0;l.textAlignment=NSTextAlignmentCenter;l.adjustsFontForContentSizeCategory=YES;}
 name.accessibilityTraits|=UIAccessibilityTraitHeader;
 NSMutableArray *rows=[@[icon,name,text] mutableCopy];
 if(actionTitle.length&&action){
  UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
  UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];
  c.title=actionTitle;c.baseForegroundColor=TIODesignColor(TIODesignColorAccent);
  c.contentInsets=NSDirectionalEdgeInsetsMake(TIOSpace3,TIOSpace4,TIOSpace3,TIOSpace4);
  c.titleTextAttributesTransformer=^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes){
   NSMutableDictionary *m=[attributes mutableCopy];m[NSFontAttributeName]=TIODesignFont(TIODesignTextStyleHeadline);return m;
  };
  button.configuration=c;button.titleLabel.adjustsFontForContentSizeCategory=YES;
  [button.heightAnchor constraintGreaterThanOrEqualToConstant:TIOHitMin].active=YES;
  void (^handler)(void)=[action copy];
  [button addAction:[UIAction actionWithHandler:^(UIAction *a){handler();}] forControlEvents:UIControlEventTouchUpInside];
  [rows addObject:button];
 }
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:rows];
 stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=TIOSpace3;
 stack.layoutMarginsRelativeArrangement=YES;
 stack.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(TIOSpace6,TIOSpace6,TIOSpace6,TIOSpace6);
 return stack;
}

#pragma mark Lens preview

void TIODesignStyleLensPreview(UIView *surface, NSString *summary){
 surface.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 surface.backgroundColor=TIODesignColor(TIODesignColorLensBlack);
 surface.layer.cornerRadius=TIORadiusMD;surface.layer.cornerCurve=kCACornerCurveContinuous;surface.clipsToBounds=YES;
 surface.isAccessibilityElement=YES;surface.accessibilityLabel=summary;surface.accessibilityTraits=UIAccessibilityTraitImage;
}

UIView *TIODesignLensPreviewCard(UIView *content, NSString *summary, BOOL menu){
 UIView *card=[UIView new];
 card.backgroundColor=TIODesignColor(TIODesignColorBgRaised);
 card.layer.cornerRadius=TIORadiusMD;card.layer.cornerCurve=kCACornerCurveContinuous;
 UIView *surface=[UIView new];surface.translatesAutoresizingMaskIntoConstraints=NO;
 TIODesignStyleLensPreview(surface,summary);
 [card addSubview:surface];
 if(content){
  content.translatesAutoresizingMaskIntoConstraints=NO;[surface addSubview:content];
  [NSLayoutConstraint activateConstraints:@[
   [content.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],[content.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
   [content.topAnchor constraintEqualToAnchor:surface.topAnchor],[content.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor]]];
 }
 [NSLayoutConstraint activateConstraints:@[
  [surface.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:TIOSpace3],
  [surface.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-TIOSpace3],
  [surface.topAnchor constraintEqualToAnchor:card.topAnchor constant:TIOSpace3],
  [surface.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-TIOSpace3],
  [surface.heightAnchor constraintEqualToAnchor:surface.widthAnchor multiplier:(menu?TIOLensMenuH:TIOLensPageH)/TIOLensPageW]]];
 return card;
}
