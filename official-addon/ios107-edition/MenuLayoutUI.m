#import "MenuLayoutUI.h"
#import "TIOLanguage.h"
#import "MenuLayout.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import "TIODesign.h"
#import "MenuLens.h"
#import "TDPhoneBridge.h"
#import "TDPhoneRun.h"
#include "menu_config.h"
#import <objc/message.h>
static TIOMenuLayoutLink *Link(void){
 static TIOMenuLayoutLink *link;static dispatch_once_t once;
 dispatch_once(&once,^{link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return TIOProtocolDevice();} allowed:^BOOL{
  id stage=TIOOTAFlashStatus()[@"stage"];return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;
 } clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(NSData *data){
  id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make])return NO;
  NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];if(![args[@"deviceId"]isEqual:TIOProtocolDevice()])return NO;
  args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,data);
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id result){/* submission is not an ACK */} copy]);return YES;}@catch(NSException *e){return NO;}
 }];
 [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[link cancel];}];
 });return link;
}
static TIOTileLayoutLink *TileLink(void);
BOOL TIOMenuLayoutConsume(NSDictionary *e){return [Link() consume:e]||[TileLink() consume:e];}
static NSString *TileName(NSUInteger tile);
/* The phone-side picture of the glasses menu (docs/design-system PhoneMenuLayout, LensMenuCarousel and LensMenuGrid2, 540 x 220
 * glasses pixels): clock and battery, the icons of the chosen layout drawn from the real outlines, the focused name and the
 * carousel status line. Always lens-black with lens-* greens, whatever the phone's appearance. It is a surrogate drawn with
 * the system font, not a firmware render, and says so to VoiceOver. */
@interface TIOMenuLensView:UIView
@property(nonatomic) TIOMenuLensLayout layout;
@property(nonatomic,copy) NSArray<NSNumber *> *visible; /* tile ids in menu order */
@property(nonatomic) NSUInteger focus; /* index into visible */
@property(nonatomic,copy) NSString *name,*status;
@end
@implementation TIOMenuLensView
- (instancetype)initWithFrame:(CGRect)frame{self=[super initWithFrame:frame];self.contentMode=UIViewContentModeRedraw;return self;}
- (void)setLayout:(TIOMenuLensLayout)layout visible:(NSArray<NSNumber *> *)visible focus:(NSUInteger)focus name:(NSString *)name status:(NSString *)status{
 if(_layout==layout&&_focus==focus&&[_visible isEqual:visible]&&[_name isEqual:name]&&[_status isEqual:status])return;
 _layout=layout;_visible=[visible copy];_focus=focus;_name=[name copy];_status=[status copy];[self setNeedsDisplay];
}
static void LensText(NSString *text,UIFont *font,UIColor *color,CGFloat x,CGFloat width,CGFloat baseline,CGFloat s,NSTextAlignment alignment){
 if(!text.length)return;
 NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=alignment;style.lineBreakMode=NSLineBreakByTruncatingTail;
 [text drawInRect:CGRectMake(x*s,baseline*s-font.ascender,width*s,ceil(font.lineHeight)) withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
- (void)drawRect:(CGRect)rect{
 CGFloat s=CGRectGetWidth(self.bounds)/TIOLensPageW;if(s<=0)return;
 UIColor *ink[3]={TIODesignColor(TIODesignColorLensFull),TIODesignColor(TIODesignColorLensMid),TIODesignColor(TIODesignColorLensTrack)};
 UIColor *mid=ink[TIOMenuLensInkMid],*high=TIODesignColor(TIODesignColorLensHigh),*full=ink[TIOMenuLensInkFull];
 CGContextRef g=UIGraphicsGetCurrentContext();
 /* Band T: clock at the left of the core, battery at the right. */
 LensText(@"10:00",TIODesignLensFont(TIOLensMinSize,s,UIFontWeightRegular),mid,TIOLensCoreXStart,120,TIOMenuLensClockBaseline(),s,NSTextAlignmentLeft);
 CGContextSaveGState(g);[mid setStroke];[mid setFill];
 UIBezierPath *body=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(471*s,25*s,22*s,10*s) cornerRadius:TIORadiusXS*s];body.lineWidth=2*s;[body stroke];
 UIRectFill(CGRectMake(473*s,27*s,15*s,6*s));CGContextRestoreGState(g);
 /* Icons: the 48 x 48 outline scaled to the slot, 2.6 stroke, round caps and joins, no fill. */
 uint8_t tiles[TIOMenuLensSlotMax];NSUInteger count=MIN(self.visible.count,(NSUInteger)TIOMenuLensSlotMax);
 for(NSUInteger i=0;i<count;i++)tiles[i]=(uint8_t)self.visible[i].unsignedIntegerValue;
 TIOMenuLensSlot slots[TIOMenuLensSlotMax];NSUInteger n=TIOMenuLensSlots(self.layout,tiles,count,self.focus,slots);
 for(NSUInteger i=0;i<n;i++){
  CGPathRef path=TIOMenuLensIconPath(slots[i].tile);if(!path)continue;
  CGContextSaveGState(g);
  CGContextTranslateCTM(g,(slots[i].cx-slots[i].size/2)*s,(slots[i].cy-slots[i].size/2)*s);CGContextScaleCTM(g,slots[i].size/TIOMenuLensIconGrid*s,slots[i].size/TIOMenuLensIconGrid*s);
  CGContextSetStrokeColorWithColor(g,ink[slots[i].ink].CGColor);CGContextSetLineWidth(g,TIOMenuLensIconStroke);CGContextSetLineCap(g,kCGLineCapRound);CGContextSetLineJoin(g,kCGLineJoinRound);
  CGContextAddPath(g,path);CGContextStrokePath(g);CGContextRestoreGState(g);
 }
 /* Name (24 px) and, in the carousel, the focused app's status (16 px) under its icon, both centred on the core. */
 LensText(self.name,TIODesignLensFont(TIOLensTitleSize,s,UIFontWeightMedium),full,TIOLensCoreXStart,TIOLensCoreXEnd-TIOLensCoreXStart,TIOMenuLensNameBaseline(self.layout),s,NSTextAlignmentCenter);
 if(self.layout==TIOMenuLensCarousel)LensText(self.status,TIODesignLensFont(TIOLensMinSize,s,UIFontWeightRegular),high,TIOLensCoreXStart,TIOLensCoreXEnd-TIOLensCoreXStart,TIOMenuLensStatusBaseline(),s,NSTextAlignmentCenter);
}
@end

@interface TIOMenuLayoutUI:UITableViewController
@property(nonatomic,strong) TIOMenuLayoutLink *link;
@property(nonatomic,copy) NSString *(^firmware)(void); /* firmware label of the last status sample, nil when none */
@property(nonatomic,copy) void(^refreshCaps)(void); /* asks the glasses for a status sample */
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UIView *segmentsHost;
@property(nonatomic,strong) TIOMenuLensView *lens;
@property(nonatomic,strong) UILabel *caption;
@property(nonatomic,strong) NSTimer *poll;
@property(nonatomic) NSUInteger pick,known; /* the layout shown and chosen, and the last one the glasses confirmed */
@property(nonatomic) NSTimeInterval capsAsked; /* uptime of the last status request for the caps bit */
@property(nonatomic) BOOL syncedCaps; /* the caps bit the last sync read: a stored carousel is drawn differently with and without it */
@end
enum {SectionPreview,SectionLayout,SectionTiles,SectionGlasses,SectionNotes,SectionCount};
@implementation TIOMenuLayoutUI
- (void)viewDidLoad{
 [super viewDidLoad];self.title=TIOText(@"hub.row.menuLayout");TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;
 if(!self.link)self.link=Link();
 if(!self.firmware)self.firmware=^NSString *{return TDGlassesFirmware();};
 if(!self.refreshCaps)self.refreshCaps=^{(void)TDGlassesCapsRefresh();};
 self.pick=3;
 self.lens=[TIOMenuLensView new];self.lens.translatesAutoresizingMaskIntoConstraints=NO;self.lens.accessibilityIdentifier=@"layout-preview";
 self.caption=[UILabel new];self.caption.translatesAutoresizingMaskIntoConstraints=NO;self.caption.numberOfLines=0;self.caption.text=TIOText(@"tmg8.layout.previewCaption");TIODesignStyleHeaderLabel(self.caption);
 self.segments=[[UISegmentedControl alloc]initWithItems:@[TIOText(@"tmg8.layout.seg.carousel"),TIOText(@"tmg8.layout.seg.rows2"),TIOText(@"tmg8.layout.seg.rows3")]];
 self.segments.accessibilityIdentifier=@"layout-segments";[self.segments addTarget:self action:@selector(picked:) forControlEvents:UIControlEventValueChanged];
 self.segmentsHost=TIODesignSegmentedChoice(self.segments,TIOText(@"hub.row.menuLayout"));self.segmentsHost.translatesAutoresizingMaskIntoConstraints=NO;
 [self render];
}
- (void)viewWillAppear:(BOOL)animated{
 [super viewWillAppear:animated];[self refresh];
 __weak typeof(self) w=self;[self.poll invalidate];self.poll=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w tick];}];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.poll invalidate];self.poll=nil;[self.link cancel];}
- (void)refresh{
 __weak typeof(self) w=self;
 [self.link query:^{typeof(self) s=w;[s sync];[s render];[s.tableView reloadData];[s askCaps];}];[self render];[self.tableView reloadData];
}
/* The status sample that carries the caps bit goes stale (TDGlassesCapsFreshSeconds); ask again well before, so the Carousel segment does not flip off on a long visit. */
- (void)askCaps{self.capsAsked=NSProcessInfo.processInfo.systemUptime;if(self.refreshCaps)self.refreshCaps();}
- (void)tick{
 [self render];
 if(!self.link.busy&&NSProcessInfo.processInfo.systemUptime-self.capsAsked>=TDGlassesCapsRefreshSeconds)[self askCaps];
}
/* The layout the glasses confirmed, as it is drawn: a stored carousel on a peer without the TMG8 bit draws as the 2-row grid. */
- (NSUInteger)confirmed{NSUInteger rows=self.link.rows;if(rows==TML_CAROUSEL&&!self.link.glassesReportTMG8Caps)rows=2;return rows>=1&&rows<=3?rows:0;}
- (void)sync{self.syncedCaps=self.link.glassesReportTMG8Caps;NSUInteger rows=[self confirmed];if(rows)self.known=rows;self.pick=rows?:(self.known?:3);}
- (NSString *)firmwareName{
 NSString *name=self.firmware?self.firmware():nil;if(!name.length)return nil;
 return [name isEqual:@"TMG6"]?TIOText(@"tmg8.layout.version.tmg6"):name; /* TMG6 and TMG7 share the build field */
}
- (NSString *)footer{
 if(self.link.glassesReportTMG8Caps)return TIOText(self.pick==TIOMenuLensCarousel?@"tmg8.layout.footer.carousel":@"tmg8.layout.footer.grid");
 NSString *version=[self firmwareName];
 return version?[NSString stringWithFormat:TIOText(@"tmg8.layout.footer.needsTMG8"),version]:TIOText(@"tmg8.layout.footer.unread");
}
- (NSString *)layoutName:(NSUInteger)rows{return TIOText(rows==TIOMenuLensCarousel?@"tmg8.layout.seg.carousel":rows==TIOMenuLensRows2?@"tmg8.layout.seg.rows2":@"tmg8.layout.seg.rows3");}
/* Everything that follows the link, the caps bit or the selection; cheap and idempotent, so the poll may call it. */
- (void)render{
 BOOL tmg8=self.link.glassesReportTMG8Caps;
 /* The caps bit arrives with the status sample, usually after the layout reply: a stored carousel was read as the 2-row grid without it, so read it again once the bit changes. */
 if(tmg8!=self.syncedCaps&&!self.link.busy)[self sync];
 if(!tmg8&&self.pick==TIOMenuLensCarousel)self.pick=self.known&&self.known!=TIOMenuLensCarousel?self.known:2;
 [self.segments setEnabled:tmg8 forSegmentAtIndex:0];[self.segments setEnabled:YES forSegmentAtIndex:1];[self.segments setEnabled:YES forSegmentAtIndex:2];
 self.segments.enabled=!self.link.busy;
 if(self.segments.selectedSegmentIndex!=(NSInteger)self.pick-1)self.segments.selectedSegmentIndex=(NSInteger)self.pick-1;
 uint8_t vis[13];NSMutableArray<NSNumber *> *visible=[NSMutableArray new];NSArray<NSNumber *> *order=TileLink().order;NSUInteger hide=TileLink().hide;
 for(NSUInteger i=0;i<13;i++){NSUInteger tile=order.count==13?order[i].unsignedIntegerValue:i;if(tile>=13||(tile>=7&&tile<=11&&(hide>>tile&1)))continue;vis[visible.count]=(uint8_t)tile;[visible addObject:@(tile)];}
 NSUInteger focus=0;for(NSUInteger i=0;i<visible.count;i++)if(vis[i]==9)focus=i; /* Music is the focused entry, as on the board */
 NSUInteger tile=visible.count?vis[focus]:9;
 [self.lens setLayout:(TIOMenuLensLayout)self.pick visible:visible focus:focus name:TileName(tile) status:tile==9?TIOText(@"tmg8.layout.preview.status"):@""];
 TIODesignStyleLensPreview(self.lens,[NSString stringWithFormat:TIOText(@"tmg8.layout.preview.a11y"),[self layoutName:self.pick],TileName(tile)]);
 NSString *footer=[self footer];UITableViewHeaderFooterView *view=[self.tableView footerViewForSection:SectionLayout];
 if(view&&![view.textLabel.text isEqual:footer]){view.textLabel.text=footer;[view setNeedsLayout];[self.tableView beginUpdates];[self.tableView endUpdates];}
}
- (void)picked:(UISegmentedControl *)control{
 NSUInteger rows=(NSUInteger)control.selectedSegmentIndex+1;
 if(rows==TIOMenuLensCarousel&&!self.link.glassesReportTMG8Caps){[self render];return;}
 self.pick=rows;[self render];
 __weak typeof(self) w=self;[self.link choose:rows done:^{typeof(self) s=w;[s sync];[s render];[s.tableView reloadData];}];[self render];[self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return SectionCount;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==SectionLayout?TIOText(@"tmg8.layout.header"):s==SectionTiles?TIOText(@"tmg4.tiles.title"):s==SectionGlasses?TIOText(@"当前眼镜"):nil;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==SectionLayout?[self footer]:nil;}
- (void)embed:(UIView *)view in:(UITableViewCell *)c top:(CGFloat)top bottom:(CGFloat)bottom{
 [view removeFromSuperview];[c.contentView addSubview:view];
 [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace4],[view.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace4],[view.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:top],[view.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-bottom]]];
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 if(p.section==SectionPreview){
  c.selectionStyle=UITableViewCellSelectionStyleNone;c.textLabel.text=nil;c.detailTextLabel.text=nil;
  UIView *lens=self.lens;[lens removeFromSuperview];[self.caption removeFromSuperview];[c.contentView addSubview:lens];[c.contentView addSubview:self.caption];
  [NSLayoutConstraint activateConstraints:@[[lens.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace3],[lens.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace3],[lens.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:TIOSpace3],
   [lens.heightAnchor constraintEqualToAnchor:lens.widthAnchor multiplier:TIOLensMenuH/TIOLensPageW],
   [self.caption.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace4],[self.caption.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace4],[self.caption.topAnchor constraintEqualToAnchor:lens.bottomAnchor constant:TIOSpace2],[self.caption.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-TIOSpace3]]];
  return c;
 }
 if(p.section==SectionLayout){c.selectionStyle=UITableViewCellSelectionStyleNone;c.textLabel.text=nil;c.detailTextLabel.text=nil;[self embed:self.segmentsHost in:c top:TIOSpace2 bottom:TIOSpace2];return c;}
 if(p.section==SectionTiles){c.textLabel.text=TIOText(@"tmg4.tiles.title");c.detailTextLabel.text=TIOText(@"tmg4.tiles.instructions");c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.accessibilityIdentifier=@"layout-tiles";}
 else if(p.section==SectionGlasses){c.textLabel.text=self.link.busy?TIOText(@"正在与眼镜通信…"):TIOText(@"读取眼镜布局");c.detailTextLabel.text=self.link.note;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];c.accessibilityIdentifier=@"layout-read";c.userInteractionEnabled=!self.link.busy;}
 else{c.textLabel.text=TIOText(@"只调整菜单排版");c.detailTextLabel.text=TIOText(@"入口顺序、实体按键和 Apple Watch 遥控不变。眼镜保存后重启仍生效；首次升级默认三排。切换不会退出当前应用或唤醒屏幕，回菜单后查看。旧固件必须先更新 TMG4；无能力回执不会发送修改。");c.selectionStyle=UITableViewCellSelectionStyleNone;c.userInteractionEnabled=NO;}
 return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];
 if(p.section==SectionGlasses)[self refresh];else if(p.section==SectionTiles)[self.navigationController pushViewController:TIOTileEditorController() animated:YES];
}
@end
UIViewController *TIOMenuLayoutController(void){return [[TIOMenuLayoutUI alloc]initWithStyle:UITableViewStyleInsetGrouped];}

#include "tile_config.h"
static BOOL TileMenuSend(NSData *data){
 id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make])return NO;
 NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];if(![args[@"deviceId"]isEqual:TIOProtocolDevice()])return NO;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,data);
 @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id result){(void)result;} copy]);return YES;}@catch(NSException *e){return NO;}
}
static TIOTileLayoutLink *TileLink(void){
 static TIOTileLayoutLink *link;static dispatch_once_t once;dispatch_once(&once,^{link=[[TIOTileLayoutLink alloc]initWithPeer:^{return TIOProtocolDevice();} allowed:^BOOL{
  id stage=TIOOTAFlashStatus()[@"stage"];return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;
 } clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(NSData *data){return TileMenuSend(data);}];
 [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[link cancel];}];});return link;
}
static NSString *TileName(NSUInteger tile){static NSString *const keys[]={@"tmg4.tile.0",@"tmg4.tile.1",@"tmg4.tile.2",@"tmg4.tile.3",@"tmg4.tile.4",@"tmg4.tile.5",@"tmg4.tile.6",@"tmg4.tile.7",@"tmg4.tile.8",@"tmg4.tile.9",@"tmg4.tile.10",@"tmg4.tile.11",@"tmg4.tile.12"};return tile<13?TIOText(keys[tile]):@"";}
@interface TIOTileEditor:UITableViewController
@property(nonatomic,strong) TIOTileLayoutLink *link;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *draft;
@property(nonatomic) NSUInteger hidden;
@end
@implementation TIOTileEditor
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"tmg4.tiles.title");TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=62;self.tableView.editing=YES;self.tableView.allowsSelectionDuringEditing=YES;self.draft=[@[@7,@8,@9,@10,@11,@12]mutableCopy];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self read];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.link cancel];}
- (void)loadDraft{NSArray *order=self.link.order;if(order.count==13){self.draft=[[order subarrayWithRange:NSMakeRange(7,6)]mutableCopy];self.hidden=self.link.hide;}}
- (void)read{__weak typeof(self) weak=self;[self.link query:^{[weak loadDraft];[weak.tableView reloadData];}];[self.tableView reloadData];}
- (void)save{
 if(!self.link.ready){__weak typeof(self) weak=self;[self.link query:^{if(weak.link.ready)[weak save];else [weak.tableView reloadData];}];[self.tableView reloadData];return;}
 NSMutableArray *order=[NSMutableArray arrayWithArray:@[@0,@1,@2,@3,@4,@5,@6]];[order addObjectsFromArray:self.draft];__weak typeof(self) weak=self;NSUInteger hide=self.hidden;
 [self.link saveOrder:order hide:hide done:^{typeof(self) s=weak;if([s.link.order isEqual:order]&&s.link.hide==hide)[s loadDraft];[s.tableView reloadData];}];[self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{(void)t;return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{(void)t;return s==0?7:s==1?6:3;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{(void)t;return @[TIOText(@"tmg4.tiles.stock"),TIOText(@"tmg4.tiles.custom"),TIOText(@"tmg4.tiles.changes")][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{(void)t;return s==1?TIOText(@"tmg4.tiles.instructions"):s==2?self.link.note:nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 (void)t;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 if(p.section==0){c.textLabel.text=TileName(p.row);c.detailTextLabel.text=TIOText(@"tmg4.tiles.fixed");c.selectionStyle=UITableViewCellSelectionStyleNone;}
 else if(p.section==1){NSUInteger tile=[self.draft[p.row]unsignedIntegerValue];c.textLabel.text=TileName(tile);c.showsReorderControl=YES;c.selectionStyle=UITableViewCellSelectionStyleNone;
  if(tile==12){c.detailTextLabel.text=TIOText(@"tmg4.tiles.camera");c.accessoryType=UITableViewCellAccessoryCheckmark;c.editingAccessoryType=UITableViewCellAccessoryCheckmark;}
  else{UISwitch *toggle=[UISwitch new];toggle.tag=tile;toggle.on=!(self.hidden&(1u<<tile));toggle.onTintColor=TIODesignColor(TIODesignColorAccentFill);toggle.accessibilityLabel=TileName(tile);toggle.enabled=self.link.order.count==13&&!self.link.busy;[toggle addTarget:self action:@selector(visibility:) forControlEvents:UIControlEventValueChanged];c.accessoryView=toggle;c.editingAccessoryView=toggle;}
 }else{[self styleAction:c row:p.row];}
 return c;
}
/* Save is the primary action; Read and Restore are secondary. The link's status
 * sentence is stated once, in this section's footer, not under every button. */
- (void)styleAction:(UITableViewCell *)c row:(NSInteger)row{
 NSString *titles[]={TIOText(@"tmg4.tiles.save"),TIOText(@"tmg4.tiles.read"),TIOText(@"tmg4.tiles.reset")};NSString *ids[]={@"tiles-save",@"tiles-read",@"tiles-reset"};
 BOOL enabled=!self.link.busy,primary=row==0;
 c.detailTextLabel.text=nil;c.backgroundColor=UIColor.clearColor;c.backgroundView=nil;c.selectedBackgroundView=nil;c.selectionStyle=UITableViewCellSelectionStyleNone;
 c.textLabel.text=titles[row];c.textLabel.hidden=YES; /* the capsule label below is drawn instead, so the table styling cannot recolor it */
 UIColor *ink=!enabled?TIODesignColor(TIODesignColorLabelTertiary):primary?TIODesignColor(TIODesignColorOnAccent):TIODesignColor(TIODesignColorAccent);
 UIView *capsule=[UIView new];capsule.translatesAutoresizingMaskIntoConstraints=NO;capsule.userInteractionEnabled=NO;capsule.layer.cornerRadius=TIOButtonHeight/2;capsule.layer.cornerCurve=kCACornerCurveContinuous;
 capsule.backgroundColor=!enabled?TIODesignColor(TIODesignColorBgSunken):primary?TIODesignColor(TIODesignColorAccentFill):TIODesignColor(TIODesignColorAccentSoft);
 UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.text=titles[row];label.textAlignment=NSTextAlignmentCenter;label.numberOfLines=0;label.textColor=ink;label.font=TIODesignFont(TIODesignTextStyleHeadline);label.adjustsFontForContentSizeCategory=YES;label.isAccessibilityElement=NO;
 [capsule addSubview:label];[c.contentView insertSubview:capsule atIndex:0];
 [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:TIOSpace4],[label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-TIOSpace4],[label.topAnchor constraintEqualToAnchor:capsule.topAnchor constant:TIOSpace3],[label.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor constant:-TIOSpace3]]];
 NSLayoutConstraint *tall=[capsule.heightAnchor constraintGreaterThanOrEqualToConstant:primary?TIOButtonHeight:TIOHitMin];
 [NSLayoutConstraint activateConstraints:@[[capsule.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace4],[capsule.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace4],[capsule.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:TIOSpace1],[capsule.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-TIOSpace1],tall]];
 c.userInteractionEnabled=enabled;c.accessibilityTraits=UIAccessibilityTraitButton|(enabled?0:UIAccessibilityTraitNotEnabled);c.accessibilityLabel=titles[row];c.accessibilityIdentifier=ids[row];
}
- (void)visibility:(UISwitch *)sender{if(sender.tag<7||sender.tag>11)return;if(sender.on)self.hidden&=~(1u<<sender.tag);else self.hidden|=1u<<sender.tag;}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)p{(void)t;return p.section==1;}
- (BOOL)tableView:(UITableView *)t canMoveRowAtIndexPath:(NSIndexPath *)p{(void)t;return p.section==1&&self.link.order.count==13&&!self.link.busy;}
- (UITableViewCellEditingStyle)tableView:(UITableView *)t editingStyleForRowAtIndexPath:(NSIndexPath *)p{(void)t;(void)p;return UITableViewCellEditingStyleNone;}
- (BOOL)tableView:(UITableView *)t shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)p{(void)t;(void)p;return NO;}
- (NSIndexPath *)tableView:(UITableView *)t targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to{(void)t;return to.section==1?to:from;}
- (void)tableView:(UITableView *)t moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to{(void)t;if(from.section!=1||to.section!=1||from.row>=6||to.row>=6)return;NSNumber *tile=self.draft[from.row];[self.draft removeObjectAtIndex:from.row];[self.draft insertObject:tile atIndex:to.row];}
/* The capsules are buttons, not list rows: no hairline between them. Hide the separator with a zero-length one, exactly as wide as the cell (an inset larger than the cell draws the line in the margin outside the card). */
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)p{(void)t;if(p.section==2)cell.separatorInset=UIEdgeInsetsMake(0,cell.bounds.size.width,0,0);}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.section!=2)return;if(p.row==1)[self read];else if(p.row==0)[self save];else{self.draft=[@[@7,@8,@9,@10,@11,@12]mutableCopy];self.hidden=0;[self save];}}
@end
UIViewController *TIOTileEditorController(void){TIOTileEditor *c=[[TIOTileEditor alloc]initWithStyle:UITableViewStyleInsetGrouped];c.link=TileLink();return c;}
#if TIO_UI_PREVIEW
UIViewController *TIOTileEditorPreviewController(void){
 __block TTConfig config;tt_unrank(719,0x180,&config);__block uint32_t generation=7;__block __weak TIOTileLayoutLink *weak=nil;
 TIOTileLayoutLink *link=[[TIOTileLayoutLink alloc]initWithPeer:^{return @"preview-tiles";} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(NSData *data){
  TTCommand q;uint8_t raw[32];if(!tt_uncarrier(data.bytes,data.length,raw,false)||!tt_decode(raw,32,&q))return NO;
  if(q.op==TT_SET){TTConfig next;tt_unrank(q.rank,q.hide,&next);uint16_t old;tt_rank(&config,&old);if(old!=q.rank||config.hide!=q.hide){config=next;generation++;if(!generation)generation=1;}}
  TTVisible visible;tt_compact(&config,&visible);uint16_t rank;tt_rank(&config,&rank);TTReply r={.request=q.request,.client=q.client,.token=q.op==TT_QUERY?99:0,.generation=generation,.rank=rank,.hide=config.hide,.op=q.op,.count=visible.count};uint8_t wire[74];tt_reply_encode(raw,&r);tt_carrier(wire,raw,true);
  NSDictionary *event=@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"preview-tiles",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}};[weak consume:event];return YES;
 }];weak=link;TIOTileEditor *c=[[TIOTileEditor alloc]initWithStyle:UITableViewStyleInsetGrouped];c.link=link;return c;
}
#endif
#if TIO_UI_PREVIEW
#include "diagnostics.h"
/* Canned glasses for the preview gate: fixture "tmg8" reports the TMG8 caps bit and stores the carousel, any other fixture is
 * TMG7 glasses with three rows. As on a cold app run, the tmg8 caps bit arrives only after the layout reply (when the screen asks for the status sample). The link, the writer guard and the codec are the real ones; only the glasses are simulated. */
UIViewController *TIOMenuLayoutPreviewController(NSString *fixture){
 BOOL tmg8=[fixture isEqual:@"tmg8"];__block BOOL capsKnown=NO;__block unsigned rows=tmg8?TML_CAROUSEL:3,generation=7;__block __weak TIOMenuLayoutLink *weak=nil;
 TIOMenuLayoutLink *link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return @"preview-layout";} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} caps:^uint32_t{return tmg8?(capsKnown?TD_CAPS_TMG8:0):TD_CAPS_TMG6;} send:^BOOL(NSData *data){
  TMLCommand q;uint8_t raw[32];if(!tml_uncarrier(data.bytes,data.length,raw,false)||!tml_decode(raw,32,&q))return NO;
  if(q.op==TML_SET&&q.rows!=rows){rows=q.rows;generation++;}
  TMLState state={.token=q.op==TML_QUERY?99:0,.stored={.rows=rows,.generation=generation}};uint8_t reply[32],wire[74];tml_reply(reply,&state,&q,TML_OK);tml_carrier(wire,reply,true);
  [weak consume:@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"preview-layout",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}}];return YES;
 }];weak=link;
 TIOMenuLayoutUI *c=[[TIOMenuLayoutUI alloc]initWithStyle:UITableViewStyleInsetGrouped];c.link=link;c.firmware=^NSString *{return @"TMG6";};c.refreshCaps=^{capsKnown=YES;};return c;
}
#endif
