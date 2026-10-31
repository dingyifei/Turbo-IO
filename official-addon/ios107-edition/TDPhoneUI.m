#import "TDPhoneUI.h"
#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import "LanguageFlag.h"
#import "TIODesign.h"
#import "MenuLayout.h"
#import "MenuLayoutUI.h"
#include "knob_calibration.h"
@interface TDPanel:UITableViewController
@property(nonatomic,strong) TDPhoneRun *run;
@property(nonatomic,strong) TDRuntimeSession *runtime;
@property(nonatomic) BOOL preview;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UILabel *intro;
/* The knob step setting (TMG9). layoutLink is the app's shared link unless a preview injects its own canned glasses. */
@property(nonatomic,strong) TIOMenuLayoutLink *layoutLink;
@property(nonatomic,strong) TIOKnobStep *step;
@property(nonatomic) NSUInteger draft; /* the D chosen with the stepper; 0 = follow what the glasses report */
@property(nonatomic) TIOKnobStepState announced;
@property(nonatomic,weak) UIStepper *stepper;
@property(nonatomic) BOOL previewScrollToStep; /* preview only: the knob step fixtures open on the step section, which sits below the first screen */
@end
enum {TDSectionStatus,TDSectionCalibration,TDSectionStep,TDSectionCapture,TDSectionResources,TDSectionIntegrity,TDSectionCount};
enum {TDStepCurrent,TDStepChoose,TDStepApply,TDStepResult,TDStepRows};
static const double TDCountsPerTurn=2000; /* the board estimate the items-per-turn figure is based on */
static NSArray *Rows(void){return @[
 @[@"lv_configured_bytes",TIOText(@"LVGL 配置容量"),@"B"],@[@"lv_used_bytes",TIOText(@"LVGL 当前用量"),@"B"],@[@"lv_peak_bytes",TIOText(@"LVGL 历史峰值"),@"B"],
 @[@"lv_free_bytes",TIOText(@"LVGL 空闲量"),@"B"],@[@"lv_largest_free_bytes",TIOText(@"LVGL 最大空闲块"),@"B"],
 @[@"system_arena_bytes",TIOText(@"系统堆统计容量"),@"B"],@[@"system_used_bytes",TIOText(@"系统堆用量"),@"B"],@[@"system_peak_bytes",TIOText(@"系统堆峰值"),@"B"],@[@"system_free_bytes",TIOText(@"系统堆空闲量"),@"B"],@[@"system_largest_free_bytes",TIOText(@"系统最大空闲块"),@"B"],
 @[@"instrumented_owned_bytes",TIOText(@"已接入统计的扩展分配"),@"B"],@[@"instrumented_owned_peak_bytes",TIOText(@"已接入统计的分配峰值"),@"B"],
 @[@"allocation_failures",TIOText(@"分配失败"),TIOText(@"次")],@[@"rx_packets",TIOText(@"接收包数"),TIOText(@"包")],@[@"rx_bytes",TIOText(@"接收数据量"),@"B"],@[@"rx_max_ms",TIOText(@"接收处理最大耗时"),@"ms"],
 @[@"render_submissions",TIOText(@"渲染提交数（非 FPS）"),TIOText(@"次")],@[@"render_max_ms",TIOText(@"提交最大耗时"),@"ms"],@[@"errors",TIOText(@"扩展错误计数"),TIOText(@"次")]];}
static NSString *RuntimeFormat(NSString *key,...){va_list args;va_start(args,key);NSString *value=[[NSString alloc]initWithFormat:TIOText(key) arguments:args];va_end(args);return value;}
/* "400 counts · 5.0 items per turn": one item per D counts, about 2000 / D items per turn. */
static NSString *StepText(NSUInteger detent){return RuntimeFormat(/*i18n:id*/@"tmg9.knob.format",@(detent),[NSString stringWithFormat:@"%.1f",TDCountsPerTurn/(double)detent]);}
static NSUInteger ValidDetent(id value){NSUInteger d=[value isKindOfClass:NSNumber.class]?[value unsignedIntegerValue]:0;return d>=TK_DETENT_MIN&&d<=TK_DETENT_MAX&&d%TK_DETENT_STEP==0?d:0;}
@implementation TDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"hub.row.diagnosticsRuntime");
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
 UILabel *intro=[[UILabel alloc]initWithFrame:CGRectMake(20,0,320,130)];intro.numberOfLines=0;intro.font=TIODesignFont(TIODesignTextStyleFootnote);intro.adjustsFontForContentSizeCategory=YES;intro.textColor=TIODesignColor(TIODesignColorLabelSecondary);
 intro.text=TIOText(@"tmg4.runtime.intro");self.intro=intro;
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;
 __weak typeof(self) wself=self;
 self.step=[[TIOKnobStep alloc]initWithLink:self.layoutLink?:TIOMenuLayoutSharedLink() reported:^uint32_t{return [wself.runtime glassesDetent];} refresh:^BOOL{return [wself.runtime query];} clock:^double{return NSProcessInfo.processInfo.systemUptime;}];
 UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,130)];intro.autoresizingMask=UIViewAutoresizingFlexibleWidth;[header addSubview:intro];self.tableView.tableHeaderView=header;
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIView *header=self.tableView.tableHeaderView;CGFloat width=CGRectGetWidth(self.tableView.bounds);CGSize size=[self.intro sizeThatFits:CGSizeMake(MAX(1,width-40),CGFLOAT_MAX)];self.intro.frame=CGRectMake(20,12,width-40,ceil(size.height));CGFloat height=ceil(size.height)+24;if(fabs(CGRectGetHeight(header.frame)-height)>.5||CGRectGetWidth(header.frame)!=width){header.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=header;}}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.runtime query];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){(void)t;[weak refresh];}];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];
 if(self.previewScrollToStep)[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:TDStepCurrent inSection:TDSectionStep] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;[self.run checkpoint];}
- (void)refresh{
 [self.run poll];[self.runtime poll];[self.step poll];
 [self announceStep];
 if(!self.stepper.tracking)[self.tableView reloadData]; /* a reload mid-drag would drop the stepper the finger is on */
}
/* VoiceOver hears the end of an attempt: the result row changes, but nothing moves focus to it. */
- (void)announceStep{
 TIOKnobStepState state=self.step.state;if(state==self.announced)return;self.announced=state;
 if(state==TIOKnobStepConfirmed||state==TIOKnobStepFailed)UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,[self stepResult]);
}
static NSString *Value(id value){return !value||value==NSNull.null?TIOText(@"未测"):[value description];}
static NSString *Bytes(id value){return !value||value==NSNull.null?TIOText(@"未测"):[NSByteCountFormatter stringFromByteCount:[value longLongValue] countStyle:NSByteCountFormatterCountStyleMemory];}
static NSString *RuntimeState(NSString *state){return TIOText([@"tmg4.runtime.state." stringByAppendingString:state?:@"idle"]);}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return TDSectionCount;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;return section==TDSectionStatus?8:section==TDSectionCalibration?5:section==TDSectionStep?TDStepRows:section==TDSectionCapture?3:section==TDSectionResources?Rows().count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;return @[TIOText(@"tmg4.runtime.status"),TIOText(@"tmg4.knob.title"),TIOText(@"tmg9.knob.title"),TIOText(@"采集"),TIOText(@"资源与耗时"),TIOText(@"诊断完整性")][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{(void)tableView;return section==TDSectionStatus?TIOText(@"tmg4.runtime.footer"):section==TDSectionCalibration?TIOText(@"tmg4.knob.instructions"):section==TDSectionStep?[self stepFooter]:nil;}
/* Under the step setting: what the glasses report decides every number (one item per D counts, about 2000 / D per turn), the wrap is the TMG8 caps bit, and
 * whether the control is live is the TMG9 caps bit. Before a status sample arrives the footer only asks for one. */
- (NSString *)stepFooter{
 NSDictionary *sample=self.runtime.status[@"sample"];id caps=sample[@"caps"];NSUInteger detent=ValidDetent(sample[@"detent"]);
 if(![caps isKindOfClass:NSNumber.class]&&!detent)return TIOText(@"tmg9.knob.readFirst");
 NSMutableArray *paragraphs=[NSMutableArray array];
 if(detent)[paragraphs addObject:[NSString stringWithFormat:@"%@\n%@",RuntimeFormat(/*i18n:id*/@"tmg9.knob.footer.step",@(detent),[NSString stringWithFormat:@"%.1f",TDCountsPerTurn/(double)detent]),TIOText(([caps unsignedIntValue]&TD_CAP_MENU_CAROUSEL)?@"tmg8.knob.wrap":@"tmg8.knob.noWrap")]];
 [paragraphs addObject:TIOText(self.step.enabled?@"tmg9.knob.hint":([caps unsignedIntValue]&TD_CAP_KNOB_DETENT)?@"tmg9.knob.readFirst":@"tmg9.knob.needsTMG9")];
 return [paragraphs componentsJoinedByString:@"\n\n"];
}
/* The detent the stepper shows: the user's pick, else what the glasses report, else the TMG9 default. */
- (NSUInteger)effectiveDraft{NSUInteger d=self.draft?:ValidDetent(@([self.runtime glassesDetent]));return d?:TK_DETENT_DEFAULT;}
- (NSString *)stepResult{
 TIOKnobStepState state=self.step.state;
 if(!self.step.enabled&&state==TIOKnobStepIdle)return TIOText(@"tmg9.knob.state.unavailable");
 if(state==TIOKnobStepPending)return RuntimeFormat(/*i18n:id*/@"tmg9.knob.state.pending",@(self.step.target));
 if(state==TIOKnobStepConfirmed)return RuntimeFormat(/*i18n:id*/@"tmg9.knob.state.confirmed",@(self.step.target));
 return TIOText(state==TIOKnobStepFailed?@"tmg9.knob.state.failed":@"tmg9.knob.state.idle");
}
/* Start, Finish and Cancel are capsule buttons: the one that moves the measurement forward is filled,
 * Cancel is soft, and an action that does not apply right now is dimmed and not tappable. */
- (void)styleKnobAction:(UITableViewCell *)c row:(NSInteger)row status:(NSDictionary *)status calibration:(NSDictionary *)cal{
 NSString *titles[]={TIOText(@"tmg4.knob.start"),TIOText(@"tmg4.knob.finish"),TIOText(@"tmg4.knob.cancel")};NSString *ids[]={@"knob-start",@"knob-finish",@"knob-cancel"};
 BOOL lease=[status[@"holdsLease"]boolValue];
 BOOL enabled=row==0?!lease&&![status[@"pending"]boolValue]&&![status[@"fileBusy"]boolValue]:row==1?lease:(lease||cal.count);
 [self styleCapsule:c title:titles[row] identifier:ids[row] enabled:enabled primary:row<2];
}
- (void)styleCapsule:(UITableViewCell *)c title:(NSString *)title identifier:(NSString *)identifier enabled:(BOOL)enabled primary:(BOOL)primary{
 c.detailTextLabel.text=nil;c.backgroundColor=UIColor.clearColor;c.backgroundView=nil;c.selectedBackgroundView=nil;c.selectionStyle=UITableViewCellSelectionStyleNone;
 c.textLabel.text=title;c.textLabel.hidden=YES; /* the capsule label below is drawn instead, so the table styling cannot recolor it */
 UIColor *ink=!enabled?TIODesignColor(TIODesignColorLabelTertiary):primary?TIODesignColor(TIODesignColorOnAccent):TIODesignColor(TIODesignColorAccent);
 UIView *capsule=[UIView new];capsule.translatesAutoresizingMaskIntoConstraints=NO;capsule.userInteractionEnabled=NO;capsule.layer.cornerRadius=TIOButtonHeight/2;capsule.layer.cornerCurve=kCACornerCurveContinuous;
 capsule.backgroundColor=!enabled?TIODesignColor(TIODesignColorBgSunken):primary?TIODesignColor(TIODesignColorAccentFill):TIODesignColor(TIODesignColorAccentSoft);
 UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.text=title;label.textAlignment=NSTextAlignmentCenter;label.numberOfLines=0;label.textColor=ink;label.font=TIODesignFont(TIODesignTextStyleHeadline);label.adjustsFontForContentSizeCategory=YES;label.isAccessibilityElement=NO;
 [capsule addSubview:label];[c.contentView insertSubview:capsule atIndex:0];
 [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:TIOSpace4],[label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-TIOSpace4],[label.topAnchor constraintEqualToAnchor:capsule.topAnchor constant:TIOSpace3],[label.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor constant:-TIOSpace3]]];
 NSLayoutConstraint *tall=[capsule.heightAnchor constraintGreaterThanOrEqualToConstant:primary?TIOButtonHeight:TIOHitMin];
 [NSLayoutConstraint activateConstraints:@[[capsule.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace4],[capsule.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace4],[capsule.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:TIOSpace1],[capsule.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-TIOSpace1],tall]];
 c.userInteractionEnabled=enabled;c.accessibilityTraits=UIAccessibilityTraitButton|(enabled?0:UIAccessibilityTraitNotEnabled);c.accessibilityLabel=title;c.accessibilityIdentifier=identifier;
}
/* The knob step section: what the glasses report, the stepper that picks a new D, the capsule that sends it and the result. Without caps bit 10 the
 * same rows show dimmed (nothing to tap); the footer says why. */
- (void)styleStepRow:(UITableViewCell *)c row:(NSInteger)row sample:(NSDictionary *)sample{
 BOOL enabled=self.step.enabled,pending=self.step.state==TIOKnobStepPending;NSUInteger reported=ValidDetent(sample[@"detent"]),draft=[self effectiveDraft];
 if(row==TDStepCurrent){c.textLabel.text=TIOText(@"tmg9.knob.current");c.detailTextLabel.text=reported?StepText(reported):TIOText(@"未测");c.accessibilityIdentifier=@"knob-step-current";}
 else if(row==TDStepChoose){
  c.textLabel.text=TIOText(@"tmg9.knob.choose");c.detailTextLabel.text=StepText(draft);c.accessibilityIdentifier=@"knob-step-choose";
  UIStepper *stepper=[UIStepper new];stepper.minimumValue=TK_DETENT_MIN;stepper.maximumValue=TK_DETENT_MAX;stepper.stepValue=TK_DETENT_STEP;stepper.value=draft;stepper.wraps=NO;stepper.enabled=enabled&&!pending;
  stepper.accessibilityIdentifier=@"knob-step-stepper";stepper.accessibilityLabel=TIOText(@"tmg9.knob.choose");stepper.accessibilityValue=StepText(draft);stepper.accessibilityHint=TIOText(@"tmg9.knob.chooseHint");
  [stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];c.accessoryView=stepper;self.stepper=stepper;
  c.isAccessibilityElement=NO;c.accessibilityElements=@[stepper]; /* the stepper carries the label and value; the cell would only repeat them */
  /* A disabled stepper still draws a bright plus in the simulator, so the whole row dims explicitly. */
  CGFloat alpha=stepper.enabled?1:.4;stepper.alpha=alpha;c.textLabel.alpha=alpha;c.detailTextLabel.alpha=alpha;if(!stepper.enabled)stepper.tintColor=TIODesignColor(TIODesignColorLabelTertiary);
 }else if(row==TDStepApply){
  BOOL can=enabled&&!pending&&draft!=reported;
  [self styleCapsule:c title:TIOText(@"tmg9.knob.apply") identifier:@"knob-step-apply" enabled:can primary:YES];
 }else{c.textLabel.text=TIOText(@"tmg9.knob.result");c.detailTextLabel.text=[self stepResult];c.accessibilityIdentifier=@"knob-step-result";}
}
- (void)stepperChanged:(UIStepper *)sender{
 NSUInteger value=(NSUInteger)llround(sender.value);if(value<TK_DETENT_MIN||value>TK_DETENT_MAX)return;
 self.draft=value;[self.step reset];self.announced=self.step.state;sender.accessibilityValue=StepText(value);
 /* Only the rows that depend on the pick are refreshed; reloading the stepper's own row would end the drag or auto-repeat. */
 [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:TDStepChoose inSection:TDSectionStep]].detailTextLabel.text=StepText(value);
 [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:TDStepApply inSection:TDSectionStep],[NSIndexPath indexPathForRow:TDStepResult inSection:TDSectionStep]] withRowAnimation:UITableViewRowAnimationNone];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)p{
 (void)tableView;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.selectionStyle=UITableViewCellSelectionStyleNone;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 NSDictionary *status=self.runtime.status,*sample=status[@"sample"],*cal=status[@"calibration"];
 if(p.section==0){
  if(p.row==0){c.textLabel.text=TIOText(@"tmg4.runtime.refresh");c.detailTextLabel.text=RuntimeState(status[@"state"]);c.accessibilityIdentifier=@"runtime-refresh";c.userInteractionEnabled=![status[@"pending"]boolValue]&&![status[@"fileBusy"]boolValue];c.textLabel.textColor=c.userInteractionEnabled?TIODesignColor(TIODesignColorAccent):TIODesignColor(TIODesignColorLabelTertiary);c.accessibilityTraits=UIAccessibilityTraitButton|(c.userInteractionEnabled?0:UIAccessibilityTraitNotEnabled);c.selectionStyle=UITableViewCellSelectionStyleDefault;}
  else if(p.row==1){c.textLabel.text=TIOText(@"tmg4.runtime.identity");c.detailTextLabel.text=sample.count?[NSString stringWithFormat:@"%@\n%@",sample[@"firmware"],sample[@"build"]]:TIOText(@"未测");c.detailTextLabel.font=TIODesignMonospacedDigitFont(TIODesignTextStyleCaption);c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.lineBreakMode=NSLineBreakByCharWrapping;}
  else if(p.row==2){c.textLabel.text=TIOText(@"tmg4.runtime.caps");c.detailTextLabel.text=sample[@"caps"]?RuntimeFormat(/*i18n:id*/@"tmg4.runtime.caps.format",[sample[@"caps"]unsignedIntValue]):TIOText(@"未测");}
  else if(p.row==3){c.textLabel.text=TIOText(@"tmg4.runtime.nand");c.detailTextLabel.text=RuntimeFormat(/*i18n:id*/@"tmg4.runtime.nand.format",Bytes(sample[@"nand_total"]),Bytes(sample[@"nand_available"]));}
  else if(p.row==4){c.textLabel.text=TIOText(@"tmg4.runtime.language");id language=sample[@"language"],source=sample[@"language_source"];if(!language||language==NSNull.null)c.detailTextLabel.text=TIOText(@"未测");else c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",TIOText([language intValue]?@"tmg4.runtime.lang.zh":@"tmg4.runtime.lang.en"),TIOText([source intValue]==2?@"tmg4.runtime.saved":@"tmg4.runtime.default")];}
  else if(p.row==5){c.textLabel.text=TIOText(@"tmg4.runtime.tiles");id generation=sample[@"tile_generation"];c.detailTextLabel.text=!generation||generation==NSNull.null?TIOText(@"未测"):RuntimeFormat(/*i18n:id*/@"tmg4.runtime.tiles.format",Value(generation),TIOText(([sample[@"settings_flags"]unsignedIntValue]&4)?@"tmg4.runtime.pendingMenu":@"tmg4.runtime.applied"));}
  else if(p.row==6){c.textLabel.text=TIOText(@"tmg4.runtime.detent");id detent=sample[@"detent"];BOOL legacy=[detent isKindOfClass:NSNumber.class]&&[detent unsignedIntValue]==TK_DETENT_LEGACY&&!([sample[@"caps"]unsignedIntValue]&(TD_CAP_MENU_CAROUSEL|TD_CAP_KNOB_DETENT));c.detailTextLabel.text=legacy||![detent isKindOfClass:NSNumber.class]?RuntimeFormat(/*i18n:id*/@"tmg4.runtime.detent.format",Value(detent)):RuntimeFormat(/*i18n:id*/@"tmg8.runtime.detent.format",Value(detent));}
  else{c.textLabel.text=TIOText(@"tmg4.runtime.sync");c.detailTextLabel.text=TIOText(@"tmg4.runtime.syncHint");c.accessibilityIdentifier=@"language-sync";c.textLabel.textColor=TIODesignColor(TIODesignColorAccent);c.accessibilityTraits=UIAccessibilityTraitButton;c.selectionStyle=UITableViewCellSelectionStyleDefault;}
 }else if(p.section==1){
  if(p.row==0){c.textLabel.text=TIOText(@"tmg4.knob.state");NSString *state=RuntimeState(status[@"state"]);if(cal[@"state"]&&[@[@"ready",@"querying",@"finished"]containsObject:status[@"state"]]){unsigned value=[cal[@"state"]unsignedIntValue];state=TIOText(value==TK_ACTIVE?@"tmg4.runtime.state.rotating":value==TK_FINISHED?@"tmg4.runtime.state.finished":value==TK_EXPIRED?@"tmg4.runtime.state.expired":value==TK_OVERFLOW?@"tmg4.runtime.state.overflow":@"tmg4.runtime.state.canceled");}c.detailTextLabel.text=cal.count?RuntimeFormat(/*i18n:id*/@"tmg4.knob.progress",state,Value(cal[@"samples"]),Value(cal[@"net"]),Value(cal[@"absolute"])):state;}
  else if(p.row==1){c.textLabel.text=TIOText(@"tmg4.knob.estimate");id value=status[@"estimate"];c.detailTextLabel.text=value&&value!=NSNull.null?RuntimeFormat(/*i18n:id*/@"tmg4.knob.result",value):TIOText(@"tmg4.knob.noEstimate");}
  else{[self styleKnobAction:c row:p.row-2 status:status calibration:cal];}
 }else if(p.section==TDSectionStep){[self styleStepRow:c row:p.row sample:sample];
 }else if(p.section==TDSectionCapture){if(p.row==0){c.textLabel.text=TIOText(@"自动采集 10 分钟");UISwitch *toggle=[UISwitch new];toggle.on=self.run.active;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=toggle;}else if(p.row==1){c.textLabel.text=self.run.status;c.detailTextLabel.text=[NSString stringWithFormat:TIOText(@"已记录 %lu 条 · 剩余 %.0f 秒"),(unsigned long)self.run.store.count,self.run.remaining];}else{c.textLabel.text=self.run.saveStatus;c.detailTextLabel.text=TIOText(@"每轮独立保存 · 最多 100 轮，不覆盖旧报告");}}
 else if(p.section==TDSectionResources){NSArray *row=Rows()[p.row];NSDictionary *metrics=self.run.active&&self.run.store.age<5?self.run.store.latest[@"metrics"]:sample[@"metrics"];id value=metrics[row[0]];c.textLabel.text=row[1];c.detailTextLabel.text=!value||value==NSNull.null?TIOText(@"未测"):[NSString stringWithFormat:@"%@ %@",value,row[2]];}
 else{NSString *key=@[@"probe_ms",@"ring_overwritten",@"sequence"][p.row];c.textLabel.text=@[TIOText(@"本次采样耗时（毫秒）"),TIOText(@"眼镜事件环覆盖数"),TIOText(@"最新采样序号")][p.row];c.detailTextLabel.text=Value(self.run.store.latest[key]);}
 return c;
}
/* The capsules are buttons, not list rows: no hairline between them. Hide the separator with a zero-length one, exactly as wide as the cell (an inset larger than the cell draws the line in the margin outside the card). */
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)p{(void)tableView;if((p.section==TDSectionCalibration&&p.row>=2)||(p.section==TDSectionStep&&p.row==TDStepApply))cell.separatorInset=UIEdgeInsetsMake(0,cell.bounds.size.width,0,0);}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)p{
 [tableView deselectRowAtIndexPath:p animated:YES];if(p.section==0&&p.row==0)[self.runtime query];else if(p.section==0&&p.row==7){if(!self.preview)TIOLanguageFlagSync();}
 else if(p.section==TDSectionStep){if(p.row==TDStepApply)[self applyStep];}
 else if(p.section==1){if(p.row==2)[self.runtime beginCalibration];else if(p.row==3)[self.runtime finishCalibration];else if(p.row==4)[self.runtime cancelCalibration];}[self refresh];
}
- (void)applyStep{
 NSDictionary *sample=self.runtime.status[@"sample"];NSUInteger reported=ValidDetent(sample[@"detent"]);
 if(![self effectiveDraft]||[self effectiveDraft]==reported)return;
 if([self.step apply:[self effectiveDraft]]){self.announced=self.step.state;UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,[self stepResult]);}
}
- (void)toggle:(UISwitch *)sender{
 if(sender.on){if(![self.run start])sender.on=NO;}else [self.run stop:@"user_stop"];[self refresh];
}
- (void)share{
 if(!self.run.reportDirectory){TIONotice(self,TIOText(@"common.ui.tdPhone.noReport.title"),TIOText(@"common.ui.tdPhone.noReport.message"));return;}
 NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]URLByAppendingPathComponent:[@"TurboDiagnostics-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])return;
 NSURL *json=[dir URLByAppendingPathComponent:@"diagnostics.json"],*md=[dir URLByAppendingPathComponent:@"diagnostics.md"];
 if(![[self.run reportJSON]writeToURL:json options:NSDataWritingWithoutOverwriting error:&error]||![[self.run reportMarkdown]writeToURL:md atomically:YES encoding:NSUTF8StringEncoding error:&error]){[fm removeItemAtURL:dir error:nil];return;}
 for(NSURL *f in @[json,md])[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:f.path error:nil];
 UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[json,md] applicationActivities:nil];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
 a.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *failure){(void)type;(void)completed;(void)items;(void)failure;[fm removeItemAtURL:dir error:nil];};[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TDPhoneController(TDPhoneRun *run,TDRuntimeSession *runtime){
 TDPanel *p=[[TDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.run=run;p.runtime=runtime;return p;
}

#if TIO_UI_PREVIEW
#include "menu_config.h"
/* Fixtures: unavailable, normal, active, completed (older TMG4-style glasses: 600 counts, no step setting) and the knob step screens:
 * tmg9 (caps bit 10, D = 400 default, setting enabled), tmg9-confirmed (D was applied to 450 and read back), tmg9-failed (the glasses refuse the SET),
 * tmg8 (carousel glasses, fixed 300, setting disabled with the TMG9 note). The layout link, the knob step model and the codec are the real ones;
 * only the glasses are simulated. */
UIViewController *TDPhonePreviewController(NSString *fixture){
 __block TKState knob={0};__block __weak TDRuntimeSession *weak=nil;BOOL unavailable=[fixture isEqual:@"unavailable"];
 BOOL tmg9=[fixture hasPrefix:@"tmg9"],tmg8=[fixture isEqual:@"tmg8"],stepFixture=tmg9||tmg8,failSets=[fixture isEqual:@"tmg9-failed"];
 __block uint32_t glassesD=tmg8?300:tmg9?400:600;__block unsigned rows=stepFixture?TML_CAROUSEL:3,generation=7;__block __weak TIOMenuLayoutLink *weakLink=nil;
 TDRuntimeSession *runtime=[[TDRuntimeSession alloc]initWithPeer:^{return @"preview-runtime";} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(TDCommand q){
  weak.fileBusy=YES;if(q.op==TDQ_KNOB_START)knob=(TKState){.window=q.session,.sequence=q.sequence,.start_sequence=q.sequence,.state=TK_ACTIVE,.lease_ms=30000,.elapsed=800,.samples=4,.net=2400,.absolute=2400};
  else if(q.op==TDQ_KNOB_STOP){knob.state=TK_FINISHED;knob.sequence=q.sequence;knob.elapsed=2000;knob.samples=8;knob.net=4800;knob.absolute=4800;}
  TDSample s={.build=stepFixture?TD_BUILD_TMG6:TD_BUILD_TMG4,.kind=q.op==TDQ_STATUS?TD_STATUS:TD_CALIBRATION,.session=q.session,.sequence=q.sequence,.caps=tmg9?TD_CAPS_TMG9:tmg8?TD_CAPS_TMG8:TD_CAPS_ALL,.detent=glassesD};memset(s.build_sha,stepFixture?0x66:0x44,32);
  if(!unavailable){s.extension_valid=TD_EXT_NAND|TD_EXT_TILES|TD_EXT_LANGUAGE;s.nand_total=536870912;s.nand_available=268435456;s.tile_generation=7;s.language=TIOGlassesLanguageCode(TIOUILanguage());s.language_source=2;s.settings_flags=3;s.valid=7;s.values[TD_LV_TOTAL]=16777216;s.values[TD_LV_USED]=4194304;s.values[TD_LV_PEAK]=5242880;}
  if(knob.window){s.extension_valid|=TD_EXT_CALIBRATION;s.calibration_state=knob.state;s.calibration_window=knob.window;s.calibration_elapsed=knob.elapsed;s.calibration_samples=knob.samples;s.calibration_net=knob.net;s.calibration_absolute=knob.absolute;s.calibration_sequence=knob.sequence;}
  uint8_t raw[TD_WIRE_BYTES];if(!td_encode(&s,raw,sizeof raw)){weak.fileBusy=NO;return NO;}[weak receive:[NSData dataWithBytes:raw length:sizeof raw] device:@"preview-runtime"];weak.fileBusy=NO;return YES;
 }];weak=runtime;
 if([fixture isEqual:@"completed"]||[fixture isEqual:@"active"]){[runtime beginCalibration];if([fixture isEqual:@"completed"])[runtime finishCalibration];}
 TIOMenuLayoutLink *link=nil;
 {
  link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return @"preview-runtime";} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} caps:^uint32_t{return weak.glassesCaps;} send:^BOOL(NSData *data){
   TMLCommand q;uint8_t raw[32];if(!tml_uncarrier(data.bytes,data.length,raw,false)||!tml_decode(raw,32,&q))return NO;
   unsigned result=TML_OK;
   if(q.op==TML_SET){if(failSets)result=TML_STORAGE;else{if(q.detent)glassesD=q.detent;if(q.rows!=rows){rows=q.rows;generation++;}}}
   TMLState state={.token=q.op==TML_QUERY?99:0,.stored={.rows=rows,.generation=generation}};uint8_t reply[32],wire[74];tml_reply(reply,&state,&q,result);tml_carrier(wire,reply,true);
   [weakLink consume:@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"preview-runtime",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}}];return YES;
  }];weakLink=link;
 }
 TDPhoneStore *store=[[TDPhoneStore alloc]initWithBuild:TD_BUILD_TMG4 device:@"preview-runtime"];
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"TurboRuntimePreviewReports"] isDirectory:YES];TDPhoneRun *run=[[TDPhoneRun alloc]initWithStore:store root:root clock:^{return NSProcessInfo.processInfo.systemUptime;} sendStart:^BOOL(uint32_t sid,uint32_t lease){(void)sid;(void)lease;return NO;} sendStop:^{}];
 TDPanel *panel=(TDPanel *)TDPhoneController(run,runtime);panel.preview=YES;panel.layoutLink=link;panel.previewScrollToStep=stepFixture;
 if(stepFixture){[panel loadViewIfNeeded];[runtime query];}
 if([fixture isEqual:@"tmg9-confirmed"]||failSets){panel.draft=450;[panel applyStep];}
 return panel;
}
#endif
