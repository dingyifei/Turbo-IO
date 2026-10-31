#import "GlassesTestBenchUI.h"
#import "GlassesBench.h"
#import "DashboardCard.h"
#import "MusicPlayer.h"
#import "FocusBridge.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import "TIOConfirm.h"
#import "TIODesign.h"
#import "TIOLanguage.h"
#include "focus.h"

/* A row that moves a value one step up or down. The buttons are 44 pt targets; VoiceOver treats the whole row as one adjustable element. */
@interface TGBStepCell:UITableViewCell
@property(nonatomic,copy) void(^onStep)(int direction);
@end
@implementation TGBStepCell
- (BOOL)isAccessibilityElement{return YES;}
- (UIAccessibilityTraits)accessibilityTraits{return UIAccessibilityTraitAdjustable;}
- (NSString *)accessibilityLabel{return self.textLabel.text;}
- (NSString *)accessibilityValue{return self.detailTextLabel.text;}
- (void)accessibilityIncrement{if(self.onStep)self.onStep(1);}
- (void)accessibilityDecrement{if(self.onStep)self.onStep(-1);}
- (void)tap:(UIButton *)sender{if(self.onStep)self.onStep(sender.tag);}
- (void)setCanDecrease:(BOOL)down canIncrease:(BOOL)up{
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[[self button:-1 symbol:@"minus" label:@"bench.decrease" enabled:down],[self button:1 symbol:@"plus" label:@"bench.increase" enabled:up]]];
 stack.frame=CGRectMake(0,0,2*TIOHitMin,TIOHitMin);stack.distribution=UIStackViewDistributionFillEqually;self.accessoryView=stack;
}
- (UIButton *)button:(int)direction symbol:(NSString *)symbol label:(NSString *)label enabled:(BOOL)enabled{
 UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
 UIButtonConfiguration *configuration=[UIButtonConfiguration plainButtonConfiguration];
 configuration.image=[UIImage systemImageNamed:symbol withConfiguration:[[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleBody] configurationByApplyingConfiguration:[UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightSemibold]]];
 button.configuration=configuration;button.tag=direction;button.enabled=enabled;button.accessibilityLabel=TIOText(label);
 [button.widthAnchor constraintEqualToConstant:TIOHitMin].active=YES;[button.heightAnchor constraintEqualToConstant:TIOHitMin].active=YES;
 [button addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];return button;
}
@end

enum {SecIntro,SecLyrics,SecSong,SecCardPreset,SecCardUsage,SecCardMemory,SecCardStorage,SecCardIcons,SecCardSend,SecTimer,SecNotes,SecCount};

static BOOL FirmwareStageRunning(void){id stage=TIOOTAFlashStatus()[@"stage"];return [stage isKindOfClass:NSNumber.class]&&[stage doubleValue]!=0;}

@interface TIOGlassesTestBench:UITableViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *sections;
@property(nonatomic,strong) NSTimer *poll;
@property(nonatomic) DCValues card;
@property(nonatomic) BOOL playing;
@property(nonatomic) uint32_t position;
@property(nonatomic,copy) NSString *previewSection;
@end

@implementation TIOGlassesTestBench

#pragma mark Model

static NSDictionary *Row(NSString *ident,NSString *kind,NSString *title,NSString *detail,BOOL sends,dispatch_block_t act){
 NSMutableDictionary *row=[@{@"id":ident,@"kind":kind,@"title":title?:@"",@"sends":@(sends)} mutableCopy];
 if(detail)row[@"detail"]=detail;if(act)row[@"do"]=[act copy];return row;
}
- (NSDictionary *)section:(NSString *)headerKey footer:(NSString *)footerKey rows:(NSArray *)rows{
 NSMutableDictionary *section=[@{@"rows":rows} mutableCopy];
 if(headerKey)section[@"header"]=TIOText(headerKey);if(footerKey)section[@"footer"]=TIOText(footerKey);return section;
}

- (NSString *)timerStateText{
 TFFocusBridge *bridge=TFFocusBridge.shared;if(!bridge.ready)return TIOText(@"bench.timer.state.unread");
 unsigned status=[bridge.snapshot[@"status"] unsignedIntValue];
 NSString *keys[]={@"bench.timer.state.idle",@"bench.timer.state.running",@"bench.timer.state.paused",@"bench.timer.state.done",@"bench.timer.state.stopped"};
 NSString *name=TIOText(status<5?keys[status]:keys[0]);
 if(status==TF_RUNNING||status==TF_PAUSED){NSString *left=TIOText(@"bench.timer.state.left");return [NSString stringWithFormat:left,name,TGBClockText((uint32_t)(bridge.remaining*1000))];}
 return name;
}

- (void)rebuild{
 __weak typeof(self) w=self;
 NSMutableArray *sections=[NSMutableArray new];
 // Intro: demo label, and the firmware-stage block when it applies.
 NSMutableArray *intro=[NSMutableArray arrayWithObject:Row(@"bench-demo",@"info",TIOText(@"bench.demo.title"),TIOText(@"bench.demo.detail"),NO,nil)];
 if(FirmwareStageRunning())[intro addObject:Row(@"bench-blocked",@"info",TIOText(@"bench.blocked.title"),TIOText(@"bench.blocked"),NO,nil)];
 [sections addObject:[self section:nil footer:nil rows:intro]];
 // Lyrics.
 NSMutableArray *lyrics=[NSMutableArray new];
 for(NSDictionary *fixture in TGBLyricFixtures()){
  NSString *ident=fixture[@"id"];
  [lyrics addObject:Row([@"bench-lyric-" stringByAppendingString:ident],@"action",TIOText([@"bench.lyric." stringByAppendingString:ident]),TGBClipText(fixture[@"current"],TGB_LYRIC_CAP),YES,^{[w sendLyric:fixture];})];
 }
 [sections addObject:[self section:@"bench.lyrics.header" footer:@"bench.lyrics.footer" rows:lyrics]];
 // Fake now-playing song.
 TMPlayer *player=TMPlayer.shared;NSString *positionOf=TIOText(@"bench.music.positionOf");
 NSString *songState=TIOText(player.benchActive?@"bench.music.active":@"bench.music.inactive");
 [sections addObject:[self section:@"bench.music.header" footer:@"bench.music.footer" rows:@[
  Row(@"bench-song-show",@"action",TIOText(@"bench.music.show"),[NSString stringWithFormat:@"%@ · %@",TIOText(@"bench.music.title"),TIOText(@"bench.music.artist")],YES,^{[w showSong];}),
  Row(@"bench-song-playing",@"switch",TIOText(@"bench.music.playing"),nil,NO,nil),
  Row(@"bench-song-position",@"step",TIOText(@"bench.music.position"),[NSString stringWithFormat:positionOf,TGBClockText(self.position),TGBClockText(TGB_LYRIC_DURATION_MS)],NO,nil),
  Row(@"bench-song-stop",@"action",TIOText(@"bench.music.stop"),nil,YES,^{[w stopSong];}),
  Row(@"bench-song-status",@"status",songState,player.bridgeStatus,NO,nil)]]];
 // Dashboard card.
 DCValues card=self.card;NSString *text=TGBCardText(&card);
 NSMutableArray *presets=[NSMutableArray new];
 for(NSString *preset in TGBCardPresetIDs()){
  DCValues values;TGBCardPreset(preset,&values);
  NSMutableDictionary *row=[Row([@"bench-card-preset-" stringByAppendingString:preset],@"preset",TIOText([@"bench.card.preset." stringByAppendingString:preset]),nil,NO,^{[w loadPreset:preset];}) mutableCopy];
  row[@"selected"]=@([TGBCardText(&values) isEqual:text]);[presets addObject:row];
 }
 [sections addObject:[self section:@"bench.card.header" footer:nil rows:presets]];
 NSArray *groups=@[@[@(TGBCardFieldWeekly),@(TGBCardFieldClaude5h),@(TGBCardFieldClaudeWeek)],@[@(TGBCardFieldRamFree),@(TGBCardFieldRamTotal)],@[@(TGBCardFieldDiskFree),@(TGBCardFieldDiskTotal)],@[@(TGBCardFieldIcon1),@(TGBCardFieldIcon2),@(TGBCardFieldIcon3)]];
 NSArray *headers=@[@"bench.card.header.usage",@"bench.card.header.memory",@"bench.card.header.storage",@"bench.card.header.icons"];
 for(NSUInteger g=0;g<groups.count;g++){
  NSMutableArray *rows=[NSMutableArray new];
  for(NSNumber *number in groups[g]){
   TGBCardField field=(TGBCardField)number.unsignedIntegerValue;
   [rows addObject:Row([@"bench-card-" stringByAppendingString:TGBCardFieldID(field)],@"step",TIOText(TGBCardFieldTitleKey(field)),TGBCardFieldText(&card,field),NO,nil)];
  }
  [sections addObject:[self section:headers[g] footer:g==3?@"bench.card.footer":nil rows:rows]];
 }
 NSString *sizeFormat=TIOText(@"bench.card.size");
 NSString *size=text?[NSString stringWithFormat:sizeFormat,(unsigned long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]:TIOText(@"bench.card.invalid");
 [sections addObject:[self section:nil footer:nil rows:@[
  Row(@"bench-card-text",@"text",text?:@"",size,NO,nil),
  Row(@"bench-card-send",@"action",TIOText(@"bench.card.send"),nil,YES,^{[w sendCard];}),
  Row(@"bench-card-remove",@"action",TIOText(@"bench.card.remove"),nil,YES,^{[w removeCard];}),
  Row(@"bench-card-status",@"status",TIOText(@"bench.card.status"),TDCBenchNote(),NO,nil)]]];
 // Pomodoro.
 TFFocusBridge *bridge=TFFocusBridge.shared;BOOL paused=bridge.ready&&[bridge.snapshot[@"status"] unsignedIntValue]==TF_PAUSED;
 [sections addObject:[self section:@"bench.timer.header" footer:@"bench.timer.footer" rows:@[
  Row(@"bench-timer-start",@"action",TIOText(@"bench.timer.start"),nil,YES,^{[w timer:TF_START];}),
  Row(@"bench-timer-pause",@"action",TIOText(paused?@"bench.timer.resume":@"bench.timer.pause"),nil,YES,^{[w timer:paused?TF_RESUME:TF_PAUSE];}),
  Row(@"bench-timer-stop",@"action",TIOText(@"bench.timer.stop"),nil,YES,^{[w timer:TF_STOP];}),
  Row(@"bench-timer-status",@"status",[self timerStateText],bridge.note,NO,nil)]]];
 // What to look for on the glasses.
 [sections addObject:[self section:@"bench.notes.header" footer:nil rows:@[
  Row(@"bench-note-tile",@"info",TIOText(@"bench.notes.tile.title"),TIOText(@"bench.notes.tile.detail"),NO,nil),
  Row(@"bench-note-camera",@"info",TIOText(@"bench.notes.camera.title"),TIOText(@"bench.notes.camera.detail"),NO,nil),
  Row(@"bench-note-route",@"info",TIOText(@"bench.notes.route.title"),TIOText(@"bench.notes.route.detail"),NO,nil)]]];
 self.sections=sections;
}

#pragma mark Actions

- (BOOL)refused{
 if(!FirmwareStageRunning())return NO;
 [self refresh];return YES;
}
- (void)refresh{[self rebuild];[self.tableView reloadData];}
- (void)reloadCard{
 [self rebuild];[self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(SecCardPreset,SecCardSend-SecCardPreset+1)] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)sendLyric:(NSDictionary *)fixture{
 if([self refused])return;
 [TMPlayer.shared benchShowTitle:TIOText(@"bench.music.title") artist:TIOText(@"bench.music.artist") playing:NO positionMs:TGB_LYRIC_POSITION_MS durationMs:TGB_LYRIC_DURATION_MS lyrics:TGBLyricRows(fixture)];
 [self refresh];
}
- (void)showSong{
 if([self refused])return;
 [TMPlayer.shared benchShowTitle:TIOText(@"bench.music.title") artist:TIOText(@"bench.music.artist") playing:self.playing positionMs:self.position durationMs:TGB_LYRIC_DURATION_MS lyrics:TGBDemoSongRows()];
 [self refresh];
}
- (void)stopSong{
 if([self refused])return;
 [TMPlayer.shared benchStop];[self refresh];
}
- (void)loadPreset:(NSString *)preset{DCValues values;if(TGBCardPreset(preset,&values)){self.card=values;[self reloadCard];}}
- (void)stepCard:(TGBCardField)field direction:(int)direction{DCValues values=self.card;if(TGBCardStep(&values,field,direction)){self.card=values;[self reloadCard];}}
- (void)sendCard{
 if([self refused])return;
 NSString *text=TGBCardText(&_card);if(!text){[self refresh];return;}
 __weak typeof(self) w=self;
 TIOConfirm(self,TIOText(@"common.editor.dashboardInstallTitle"),TIOText(@"common.editor.dashboardPrompt"),TIOText(@"common.editor.dashboardInstallAction"),NO,^{TDCBenchInstall(text);[w refresh];});
}
- (void)removeCard{
 if([self refused])return;
 __weak typeof(self) w=self;
 TIOConfirm(self,TIOText(@"common.editor.dashboardRemoveTitle"),TIOText(@"common.editor.dashboardRemoveDetail"),TIOText(@"common.editor.remove"),YES,^{TDCBenchRemove();[w refresh];});
}
/* The first tap reads the glasses timer (TFP1 only sends after a fresh reply, so a stale phone cannot overwrite a running timer); tap again to send. */
- (void)timer:(unsigned)op{
 if([self refused])return;
 [TFFocusBridge.shared perform:op seconds:op==TF_START?TGB_TIMER_SECONDS:0 phase:0];[self refresh];
}

#pragma mark View

- (void)viewDidLoad{
 [super viewDidLoad];self.title=TIOText(@"hub.row.testBench");TIOStyleResearchTable(self);
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=64;
 self.tableView.accessibilityIdentifier=@"bench-table";
 DCValues card;TGBCardPreset(@"typical",&card);if(!self.card.ramTotal)self.card=card;
 [self rebuild];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(tick) name:@"TDCDashboardChanged" object:nil];
}
- (void)dealloc{[self.poll invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)viewWillAppear:(BOOL)animated{
 [super viewWillAppear:animated];[self refresh];
 __weak typeof(self) w=self;[self.poll invalidate];self.poll=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w tick];}];
}
- (void)viewDidAppear:(BOOL)animated{
 [super viewDidAppear:animated];
 NSDictionary *anchors=@{@"lyrics":@(SecLyrics),@"song":@(SecSong),@"card":@(SecCardPreset),@"timer":@(SecTimer)};
 NSNumber *section=self.previewSection?anchors[self.previewSection]:nil;
 if(section)[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section.integerValue] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.poll invalidate];self.poll=nil;}
/* Only the status lines and the stage banner change by themselves, so rows are refreshed in place and an open stepper is not interrupted. */
- (void)tick{
 NSArray<NSDictionary *> *old=self.sections;[self rebuild];
 if(old.count!=self.sections.count||[old[SecIntro][@"rows"] count]!=[self.sections[SecIntro][@"rows"] count]){[self.tableView reloadData];return;}
 NSMutableArray<NSIndexPath *> *changed=[NSMutableArray new];
 for(NSUInteger s=0;s<self.sections.count;s++){
  NSArray *rows=self.sections[s][@"rows"],*before=old[s][@"rows"];
  for(NSUInteger r=0;r<rows.count;r++){
   NSDictionary *row=rows[r],*prior=before[r];
   if(![row[@"kind"] isEqual:@"status"]&&![row[@"id"] isEqual:@"bench-timer-pause"])continue;
   if(![row[@"title"] isEqual:prior[@"title"]]||![row[@"detail"] isEqual:prior[@"detail"]])[changed addObject:[NSIndexPath indexPathForRow:r inSection:s]];
  }
 }
 if(changed.count)[self.tableView reloadRowsAtIndexPaths:changed withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return (NSInteger)self.sections.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return (NSInteger)[self.sections[(NSUInteger)s][@"rows"] count];}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return self.sections[(NSUInteger)s][@"header"];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return self.sections[(NSUInteger)s][@"footer"];}

- (NSDictionary *)rowAt:(NSIndexPath *)p{return self.sections[(NSUInteger)p.section][@"rows"][(NSUInteger)p.row];}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 NSDictionary *row=[self rowAt:p];NSString *kind=row[@"kind"];
 TGBStepCell *step=[kind isEqual:@"step"]?[[TGBStepCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]:nil;
 UITableViewCell *c=step?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 c.textLabel.text=row[@"title"];c.detailTextLabel.text=row[@"detail"];c.accessibilityIdentifier=row[@"id"];
 BOOL blocked=[row[@"sends"] boolValue]&&FirmwareStageRunning();
 if([kind isEqual:@"action"]||[kind isEqual:@"preset"]){
  c.textLabel.textColor=TIODesignColor(TIODesignColorAccent);   // TIODesignStyleRow maps this to the accent text style
  c.accessibilityTraits=UIAccessibilityTraitButton|(blocked?UIAccessibilityTraitNotEnabled:0)|([row[@"selected"] boolValue]?UIAccessibilityTraitSelected:0);
  c.userInteractionEnabled=!blocked;c.accessoryType=[row[@"selected"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
 }else c.selectionStyle=UITableViewCellSelectionStyleNone;
 TIOStyleResearchCell(c);
 if([kind isEqual:@"text"]){c.textLabel.font=TIODesignMonospacedDigitFont(TIODesignTextStyleFootnote);c.textLabel.textColor=TIODesignColor(TIODesignColorLabelSecondary);}
 if([kind isEqual:@"switch"]){
  UISwitch *toggle=[UISwitch new];toggle.on=self.playing;toggle.onTintColor=TIODesignColor(TIODesignColorAccentFill);toggle.accessibilityLabel=row[@"title"];
  [toggle addTarget:self action:@selector(playingChanged:) forControlEvents:UIControlEventValueChanged];c.accessoryView=toggle;
 }
 if(step){
  __weak typeof(self) w=self;NSString *ident=row[@"id"];
  BOOL position=[ident isEqual:@"bench-song-position"];
  TGBCardField field=TGBCardFieldCount;
  for(NSUInteger f=0;f<TGBCardFieldCount;f++)if([ident isEqual:[@"bench-card-" stringByAppendingString:TGBCardFieldID((TGBCardField)f)]])field=(TGBCardField)f;
  BOOL down=YES,up=YES;
  if(position){down=self.position>0;up=self.position+TGB_POSITION_STEP_MS<TGB_LYRIC_DURATION_MS;}
  else{DCValues a=self.card,b=self.card;down=TGBCardStep(&a,field,-1);up=TGBCardStep(&b,field,1);}
  [step setCanDecrease:down canIncrease:up];
  step.onStep=^(int direction){if(position)[w stepPosition:direction];else [w stepCard:field direction:direction];};
 }
 if([kind isEqual:@"status"]){c.accessibilityTraits=UIAccessibilityTraitStaticText;}
 return c;
}
/* The table theme restyles a cell as it appears, so the preview limit of a long lyric is set here, after it. */
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)p{
 if([[self rowAt:p][@"id"] hasPrefix:@"bench-lyric-"])cell.detailTextLabel.numberOfLines=3;
}
- (void)playingChanged:(UISwitch *)sender{self.playing=sender.on;}
- (void)stepPosition:(int)direction{
 int64_t next=(int64_t)self.position+direction*(int64_t)TGB_POSITION_STEP_MS;
 if(next<0||next>=(int64_t)TGB_LYRIC_DURATION_MS)return;
 self.position=(uint32_t)next;[self rebuild];
 [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:SecSong]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];
 dispatch_block_t act=[self rowAt:p][@"do"];if(act)act();
}
@end

UIViewController *TIOGlassesTestBenchController(void){return [[TIOGlassesTestBench alloc]initWithStyle:UITableViewStyleInsetGrouped];}

#if TIO_UI_PREVIEW
UIViewController *TIOGlassesTestBenchPreviewController(NSString *section){
 TIOGlassesTestBench *bench=[[TIOGlassesTestBench alloc]initWithStyle:UITableViewStyleInsetGrouped];
 bench.previewSection=section;DCValues card;TGBCardPreset([section isEqual:@"card"]?@"three100":@"typical",&card);bench.card=card;
 bench.playing=[section isEqual:@"song"];bench.position=[section isEqual:@"song"]?65000:0;return bench;
}
#endif
