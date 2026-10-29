#import "MenuLayoutUI.h"
#import "TIOLanguage.h"
#import "MenuLayout.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import "TIODesign.h"
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
@interface TIOMenuLayoutUI:UITableViewController @end
@implementation TIOMenuLayoutUI
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"hub.row.menuLayout");TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self refresh];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[Link() cancel];}
- (void)refresh{__weak typeof(self) w=self;[Link() query:^{[w.tableView reloadData];}];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==1?2:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[TIOText(@"当前眼镜"),TIOText(@"显示排数"),TIOText(@"tmg4.tiles.title"),TIOText(@"使用说明")][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 if(p.section==0){c.textLabel.text=Link().busy?TIOText(@"正在与眼镜通信…"):TIOText(@"读取眼镜布局");c.detailTextLabel.text=Link().note;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];}
 else if(p.section==1){NSUInteger rows=p.row==0?3:2;c.textLabel.text=rows==3?TIOText(@"三排 · 九宫格（默认）"):TIOText(@"两排 · 舒展留白");c.detailTextLabel.text=rows==3?TIOText(@"每页 9 项 · 32px 图标 · 紧凑浏览"):TIOText(@"每页 6 项 · 40px 图标 · 更大行距");c.imageView.image=[UIImage systemImageNamed:rows==3?@"square.grid.3x3":@"rectangle.grid.3x2"];c.accessoryType=Link().rows==rows?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
 else if(p.section==2){c.textLabel.text=TIOText(@"tmg4.tiles.title");c.detailTextLabel.text=TIOText(@"tmg4.tiles.instructions");c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 else{c.textLabel.text=TIOText(@"只调整菜单排版");c.detailTextLabel.text=TIOText(@"入口顺序、实体按键和 Apple Watch 遥控不变。眼镜保存后重启仍生效；首次升级默认三排。切换不会退出当前应用或唤醒屏幕，回菜单后查看。旧固件必须先更新 TMG4；无能力回执不会发送修改。");c.selectionStyle=UITableViewCellSelectionStyleNone;}
 c.userInteractionEnabled=p.section!=3&&!Link().busy;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(p.section==0){[self refresh];return;}if(p.section==2){[self.navigationController pushViewController:TIOTileEditorController() animated:YES];return;}if(p.section!=1)return;
 __weak typeof(self) w=self;[Link() choose:p.row==0?3:2 done:^{[w.tableView reloadData];}];[self.tableView reloadData];
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
