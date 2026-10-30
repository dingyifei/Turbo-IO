#import "TDPhoneUI.h"
#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import "LanguageFlag.h"
#import "TIODesign.h"
@interface TDPanel:UITableViewController
@property(nonatomic,strong) TDPhoneRun *run;
@property(nonatomic,strong) TDRuntimeSession *runtime;
@property(nonatomic) BOOL preview;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UILabel *intro;
@end
static NSArray *Rows(void){return @[
 @[@"lv_configured_bytes",TIOText(@"LVGL 配置容量"),@"B"],@[@"lv_used_bytes",TIOText(@"LVGL 当前用量"),@"B"],@[@"lv_peak_bytes",TIOText(@"LVGL 历史峰值"),@"B"],
 @[@"lv_free_bytes",TIOText(@"LVGL 空闲量"),@"B"],@[@"lv_largest_free_bytes",TIOText(@"LVGL 最大空闲块"),@"B"],
 @[@"system_arena_bytes",TIOText(@"系统堆统计容量"),@"B"],@[@"system_used_bytes",TIOText(@"系统堆用量"),@"B"],@[@"system_peak_bytes",TIOText(@"系统堆峰值"),@"B"],@[@"system_free_bytes",TIOText(@"系统堆空闲量"),@"B"],@[@"system_largest_free_bytes",TIOText(@"系统最大空闲块"),@"B"],
 @[@"instrumented_owned_bytes",TIOText(@"已接入统计的扩展分配"),@"B"],@[@"instrumented_owned_peak_bytes",TIOText(@"已接入统计的分配峰值"),@"B"],
 @[@"allocation_failures",TIOText(@"分配失败"),TIOText(@"次")],@[@"rx_packets",TIOText(@"接收包数"),TIOText(@"包")],@[@"rx_bytes",TIOText(@"接收数据量"),@"B"],@[@"rx_max_ms",TIOText(@"接收处理最大耗时"),@"ms"],
 @[@"render_submissions",TIOText(@"渲染提交数（非 FPS）"),TIOText(@"次")],@[@"render_max_ms",TIOText(@"提交最大耗时"),@"ms"],@[@"errors",TIOText(@"扩展错误计数"),TIOText(@"次")]];}
static NSString *RuntimeFormat(NSString *key,...){va_list args;va_start(args,key);NSString *value=[[NSString alloc]initWithFormat:TIOText(key) arguments:args];va_end(args);return value;}
@implementation TDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"hub.row.diagnosticsRuntime");
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
 UILabel *intro=[[UILabel alloc]initWithFrame:CGRectMake(20,0,320,130)];intro.numberOfLines=0;intro.font=TIODesignFont(TIODesignTextStyleFootnote);intro.adjustsFontForContentSizeCategory=YES;intro.textColor=TIODesignColor(TIODesignColorLabelSecondary);
 intro.text=TIOText(@"tmg4.runtime.intro");self.intro=intro;
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;
 UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,130)];intro.autoresizingMask=UIViewAutoresizingFlexibleWidth;[header addSubview:intro];self.tableView.tableHeaderView=header;
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIView *header=self.tableView.tableHeaderView;CGFloat width=CGRectGetWidth(self.tableView.bounds);CGSize size=[self.intro sizeThatFits:CGSizeMake(MAX(1,width-40),CGFLOAT_MAX)];self.intro.frame=CGRectMake(20,12,width-40,ceil(size.height));CGFloat height=ceil(size.height)+24;if(fabs(CGRectGetHeight(header.frame)-height)>.5||CGRectGetWidth(header.frame)!=width){header.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=header;}}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.runtime query];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){(void)t;[weak refresh];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;[self.run checkpoint];}
- (void)refresh{
 [self.run poll];[self.runtime poll];
 [self.tableView reloadData];
}
static NSString *Value(id value){return !value||value==NSNull.null?TIOText(@"未测"):[value description];}
static NSString *Bytes(id value){return !value||value==NSNull.null?TIOText(@"未测"):[NSByteCountFormatter stringFromByteCount:[value longLongValue] countStyle:NSByteCountFormatterCountStyleMemory];}
static NSString *RuntimeState(NSString *state){return TIOText([@"tmg4.runtime.state." stringByAppendingString:state?:@"idle"]);}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return 5;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;return section==0?8:section==1?5:section==2?3:section==3?Rows().count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;return @[TIOText(@"tmg4.runtime.status"),TIOText(@"tmg4.knob.title"),TIOText(@"采集"),TIOText(@"资源与耗时"),TIOText(@"诊断完整性")][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{(void)tableView;return section==0?TIOText(@"tmg4.runtime.footer"):section==1?[self knobFooter]:nil;}
/* The detent line follows the glasses: the 300-count detent, about 6.7 items per turn and the wrap are TMG8 behaviour (it reports caps bit 9 and detent 300);
 * TMG7 and older report 600 counts per item (about 3.3 per turn) and stop at the ends. Before a status sample arrives only the instructions show. */
- (NSString *)knobFooter{
 NSDictionary *sample=self.runtime.status[@"sample"];id caps=sample[@"caps"];NSString *instructions=TIOText(@"tmg4.knob.instructions");
 if(![caps isKindOfClass:NSNumber.class])return instructions;
 return [NSString stringWithFormat:@"%@\n\n%@",instructions,TIOText(([caps unsignedIntValue]&TD_CAP_MENU_CAROUSEL)?@"tmg8.knob.detent":@"tmg8.knob.detentLegacy")];
}
/* Start, Finish and Cancel are capsule buttons: the one that moves the measurement forward is filled,
 * Cancel is soft, and an action that does not apply right now is dimmed and not tappable. */
- (void)styleKnobAction:(UITableViewCell *)c row:(NSInteger)row status:(NSDictionary *)status calibration:(NSDictionary *)cal{
 NSString *titles[]={TIOText(@"tmg4.knob.start"),TIOText(@"tmg4.knob.finish"),TIOText(@"tmg4.knob.cancel")};NSString *ids[]={@"knob-start",@"knob-finish",@"knob-cancel"};
 BOOL lease=[status[@"holdsLease"]boolValue];
 BOOL enabled=row==0?!lease&&![status[@"pending"]boolValue]&&![status[@"fileBusy"]boolValue]:row==1?lease:(lease||cal.count);
 BOOL primary=row<2;
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
  else if(p.row==6){c.textLabel.text=TIOText(@"tmg4.runtime.detent");id detent=sample[@"detent"];BOOL carousel=[detent isKindOfClass:NSNumber.class]&&[detent unsignedIntValue]==300;c.detailTextLabel.text=carousel?RuntimeFormat(/*i18n:id*/@"tmg8.runtime.detent.format",Value(detent)):RuntimeFormat(/*i18n:id*/@"tmg4.runtime.detent.format",Value(detent));}
  else{c.textLabel.text=TIOText(@"tmg4.runtime.sync");c.detailTextLabel.text=TIOText(@"tmg4.runtime.syncHint");c.accessibilityIdentifier=@"language-sync";c.textLabel.textColor=TIODesignColor(TIODesignColorAccent);c.accessibilityTraits=UIAccessibilityTraitButton;c.selectionStyle=UITableViewCellSelectionStyleDefault;}
 }else if(p.section==1){
  if(p.row==0){c.textLabel.text=TIOText(@"tmg4.knob.state");NSString *state=RuntimeState(status[@"state"]);if(cal[@"state"]&&[@[@"ready",@"querying",@"finished"]containsObject:status[@"state"]]){unsigned value=[cal[@"state"]unsignedIntValue];state=TIOText(value==TK_ACTIVE?@"tmg4.runtime.state.rotating":value==TK_FINISHED?@"tmg4.runtime.state.finished":value==TK_EXPIRED?@"tmg4.runtime.state.expired":value==TK_OVERFLOW?@"tmg4.runtime.state.overflow":@"tmg4.runtime.state.canceled");}c.detailTextLabel.text=cal.count?RuntimeFormat(/*i18n:id*/@"tmg4.knob.progress",state,Value(cal[@"samples"]),Value(cal[@"net"]),Value(cal[@"absolute"])):state;}
  else if(p.row==1){c.textLabel.text=TIOText(@"tmg4.knob.estimate");id value=status[@"estimate"];c.detailTextLabel.text=value&&value!=NSNull.null?RuntimeFormat(/*i18n:id*/@"tmg4.knob.result",value):TIOText(@"tmg4.knob.noEstimate");}
  else{[self styleKnobAction:c row:p.row-2 status:status calibration:cal];}
 }else if(p.section==2){if(p.row==0){c.textLabel.text=TIOText(@"自动采集 10 分钟");UISwitch *toggle=[UISwitch new];toggle.on=self.run.active;[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=toggle;}else if(p.row==1){c.textLabel.text=self.run.status;c.detailTextLabel.text=[NSString stringWithFormat:TIOText(@"已记录 %lu 条 · 剩余 %.0f 秒"),(unsigned long)self.run.store.count,self.run.remaining];}else{c.textLabel.text=self.run.saveStatus;c.detailTextLabel.text=TIOText(@"每轮独立保存 · 最多 100 轮，不覆盖旧报告");}}
 else if(p.section==3){NSArray *row=Rows()[p.row];NSDictionary *metrics=self.run.active&&self.run.store.age<5?self.run.store.latest[@"metrics"]:sample[@"metrics"];id value=metrics[row[0]];c.textLabel.text=row[1];c.detailTextLabel.text=!value||value==NSNull.null?TIOText(@"未测"):[NSString stringWithFormat:@"%@ %@",value,row[2]];}
 else{NSString *key=@[@"probe_ms",@"ring_overwritten",@"sequence"][p.row];c.textLabel.text=@[TIOText(@"本次采样耗时（毫秒）"),TIOText(@"眼镜事件环覆盖数"),TIOText(@"最新采样序号")][p.row];c.detailTextLabel.text=Value(self.run.store.latest[key]);}
 return c;
}
/* The capsules are buttons, not list rows: no hairline between them. Hide the separator with a zero-length one, exactly as wide as the cell (an inset larger than the cell draws the line in the margin outside the card). */
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)p{(void)tableView;if(p.section==1&&p.row>=2)cell.separatorInset=UIEdgeInsetsMake(0,cell.bounds.size.width,0,0);}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)p{
 [tableView deselectRowAtIndexPath:p animated:YES];if(p.section==0&&p.row==0)[self.runtime query];else if(p.section==0&&p.row==7){if(!self.preview)TIOLanguageFlagSync();}
 else if(p.section==1){if(p.row==2)[self.runtime beginCalibration];else if(p.row==3)[self.runtime finishCalibration];else if(p.row==4)[self.runtime cancelCalibration];}[self refresh];
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
UIViewController *TDPhonePreviewController(NSString *fixture){
 __block TKState knob={0};__block __weak TDRuntimeSession *weak=nil;BOOL unavailable=[fixture isEqual:@"unavailable"];
 TDRuntimeSession *runtime=[[TDRuntimeSession alloc]initWithPeer:^{return @"preview-runtime";} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(TDCommand q){
  weak.fileBusy=YES;if(q.op==TDQ_KNOB_START)knob=(TKState){.window=q.session,.sequence=q.sequence,.start_sequence=q.sequence,.state=TK_ACTIVE,.lease_ms=30000,.elapsed=800,.samples=4,.net=2400,.absolute=2400};
  else if(q.op==TDQ_KNOB_STOP){knob.state=TK_FINISHED;knob.sequence=q.sequence;knob.elapsed=2000;knob.samples=8;knob.net=4800;knob.absolute=4800;}
  TDSample s={.build=TD_BUILD_TMG4,.kind=q.op==TDQ_STATUS?TD_STATUS:TD_CALIBRATION,.session=q.session,.sequence=q.sequence,.caps=TD_CAPS_ALL,.detent=600};memset(s.build_sha,0x44,32);
  if(!unavailable){s.extension_valid=TD_EXT_NAND|TD_EXT_TILES|TD_EXT_LANGUAGE;s.nand_total=536870912;s.nand_available=268435456;s.tile_generation=7;s.language=TIOGlassesLanguageCode(TIOUILanguage());s.language_source=2;s.settings_flags=3;s.valid=7;s.values[TD_LV_TOTAL]=16777216;s.values[TD_LV_USED]=4194304;s.values[TD_LV_PEAK]=5242880;}
  if(knob.window){s.extension_valid|=TD_EXT_CALIBRATION;s.calibration_state=knob.state;s.calibration_window=knob.window;s.calibration_elapsed=knob.elapsed;s.calibration_samples=knob.samples;s.calibration_net=knob.net;s.calibration_absolute=knob.absolute;s.calibration_sequence=knob.sequence;}
  uint8_t raw[TD_WIRE_BYTES];if(!td_encode(&s,raw,sizeof raw)){weak.fileBusy=NO;return NO;}[weak receive:[NSData dataWithBytes:raw length:sizeof raw] device:@"preview-runtime"];weak.fileBusy=NO;return YES;
 }];weak=runtime;
 if([fixture isEqual:@"completed"]||[fixture isEqual:@"active"]){[runtime beginCalibration];if([fixture isEqual:@"completed"])[runtime finishCalibration];}
 TDPhoneStore *store=[[TDPhoneStore alloc]initWithBuild:TD_BUILD_TMG4 device:@"preview-runtime"];
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"TurboRuntimePreviewReports"] isDirectory:YES];TDPhoneRun *run=[[TDPhoneRun alloc]initWithStore:store root:root clock:^{return NSProcessInfo.processInfo.systemUptime;} sendStart:^BOOL(uint32_t sid,uint32_t lease){(void)sid;(void)lease;return NO;} sendStop:^{}];
 TDPanel *panel=(TDPanel *)TDPhoneController(run,runtime);panel.preview=YES;return panel;
}
#endif
