#import "ClenchLabUI.h"
#if TIO_IMAGE_RX_LAB
#import "ClenchLab.h"
#import "AlwaysOnAudio.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "TIOConfirm.h"
#import "ResearchUI.h"
#import "TIODesign.h"
#import "TIOLanguage.h"
#import <CommonCrypto/CommonDigest.h>
// The session outlives this page: the user leaves it to start and stop LifeLog in the official app.
// Background, resign-active, termination and device changes end the capture at once. Auto-lock is not one of them: the
// idle timer is disabled only while capturing, and the model turns it back on at the end only if the Lab disabled it.
// Known limitation shared with MapKit navigation and the camera (both save and restore the same flag): one that starts
// while the Lab holds the flag writes the Lab's "disabled" back when it ends.
static NSTimer *Ticker;
static NSString *Fmt(NSString *key,...){va_list a;va_start(a,key);NSString *r=[[NSString alloc]initWithFormat:TIOText(key) arguments:a];va_end(a);return r;}
static BOOL Sharing;
// Attach and zip work on the global session and its manifests, so the in-progress flag is global too: a second panel
// instance must not run status updates or another attach while an earlier panel's background work is running.
static BOOL Busy;
static NSMutableSet<NSString *> *AutoAttached;
// A manual Attach waits for the same settled official stop as the automatic one; only one waits at a time.
static NSURL *ManualAttach;static NSUInteger ManualPolls;
static const NSUInteger ManualAttachPolls=12;
static NSTimer *RestoreTimer;
static void ArmRestore(void);
// C2-4/S2-02: a live camera or running navigation anywhere in the visible chain (under an alert too) saved the Lab's
// "disabled" and restores it itself; the Lab then leaves the flag alone at the end instead of re-enabling auto-lock under it.
static BOOL HoldsIdle(UIViewController *v){
 if([v isKindOfClass:UITabBarController.class])v=((UITabBarController *)v).selectedViewController;if([v isKindOfClass:UINavigationController.class])v=((UINavigationController *)v).topViewController;
 Class camera=NSClassFromString(@"TCView"),nav=NSClassFromString(@"TIOMapKitNavigationPanel");NSString *key=camera&&[v isKindOfClass:camera]?@"configuredIdle":(nav&&[v isKindOfClass:nav]?@"navigating":nil);
 return key&&[v respondsToSelector:NSSelectorFromString(key)]&&[[v valueForKey:key] boolValue];
}
static BOOL IdleHeldOnScreen(void){for(UIViewController *v=TIOTopController();v;v=v.presentingViewController)if(HoldsIdle(v))return YES;return NO;}
static BOOL Ready(void){id stage=TIOOTAFlashStatus()[@"stage"];return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;}
static TIOClenchSession *Lab(void){
 static TIOClenchSession *lab;static dispatch_once_t once;
 dispatch_once(&once,^{
  TIOClenchConfig *c=[TIOClenchConfig standardConfig];c.dumpStatus=^NSDictionary *{return TIOAOStatus();};c.dumpConfigure=^BOOL(NSDictionary *x){return TIOAOConfigureDump(x);};c.device=^NSString *{return TIOProtocolDevice();};
  c.idleTimerDisabled=^BOOL{return UIApplication.sharedApplication.idleTimerDisabled;};c.setIdleTimerDisabled=^(BOOL v){UIApplication.sharedApplication.idleTimerDisabled=v;};c.idleTimerHeldElsewhere=^BOOL{return IdleHeldOnScreen();};
  lab=[[TIOClenchSession alloc]initWithConfig:c];AutoAttached=[NSMutableSet new];
  lab.changed=^{[NSNotificationCenter.defaultCenter postNotificationName:TIOClenchLabChangedNotification object:nil];};
  lab.stopPrompt=^(BOOL restored){[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];TIONotice(nil,TIOText(@"clench.stopPrompt.title"),restored?TIOText(@"clench.stopPrompt.message"):TIOText(@"clench.stopPrompt.restoreFailed"));if(!restored)ArmRestore();};
  NSNotificationCenter *n=NSNotificationCenter.defaultCenter;
  for(NSString *name in @[UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification,UIApplicationWillTerminateNotification])
   [n addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[lab lifecycleStop:@"app-inactive"];}];
  [n addObserverForName:TIOProtocolDeviceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[lab tick];}];
 });return lab;
}
static BOOL DumpOutstanding(NSDictionary *p){return p&&[p[@"labDumpEnabled"] boolValue]&&![p[@"dumpRestored"] boolValue]&&!p[@"dumpRestoreWaived"];}
// Any dump restore still owed: an open record, or one the user waived for Start (restoreOwed) that still has to read back.
static BOOL RestoreOwed(void){return DumpOutstanding(Lab().pending)||Lab().restoreOwed!=nil;}
// A failed or waived restore is retried every 5 s while the app is in the foreground, whether or not the Lab page is open,
// until it reads back. Never touches the stop state; never sends a glasses command.
static void ArmRestore(void){
 if(RestoreTimer||!RestoreOwed())return;
 RestoreTimer=[NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *t){
  if(!RestoreOwed()){[t invalidate];if(RestoreTimer==t)RestoreTimer=nil;return;}
  if(!Busy&&Lab().phase!=TIOClenchPhaseCapturing&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[Lab() restorePendingDump];
 }];
 [NSRunLoop.mainRunLoop addTimer:RestoreTimer forMode:NSRunLoopCommonModes];
}
// Two independent drivers: a 4 Hz timer and one-shot deadlines at the stop and receive limits.
static void Arm(void){
 [Ticker invalidate];Ticker=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t){[Lab() tick];if(Lab().phase!=TIOClenchPhaseCapturing){[t invalidate];if(Ticker==t)Ticker=nil;ArmRestore();}}];
 [NSRunLoop.mainRunLoop addTimer:Ticker forMode:NSRunLoopCommonModes];NSString *sid=Lab().sessionId;
 for(NSNumber *at in @[@(Lab().config.stopRequestLimit),@(Lab().config.receiveLimit)])
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((at.doubleValue+0.05)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if([Lab().sessionId isEqual:sid])[Lab() tick];});
}
static NSString *DeviceKey(NSString *d){NSData *b=[d dataUsingEncoding:NSUTF8StringEncoding];unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,h);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<8;i++)[s appendFormat:@"%02x",h[i]];return s;}
static NSDictionary *WakeState(void){NSString *d=TIOProtocolDevice();if(!d.length)return nil;id v=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"clenchLab.wake.v1"][DeviceKey(d)];return [v isKindOfClass:NSDictionary.class]?v:nil;}
static void SaveWake(NSInteger mode){NSString *d=TIOProtocolDevice();if(!d.length)return;NSMutableDictionary *all=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"clenchLab.wake.v1"] mutableCopy]?:[NSMutableDictionary new];all[DeviceKey(d)]=@{@"mode":@(mode),@"at":@(NSDate.date.timeIntervalSince1970)};[NSUserDefaults.standardUserDefaults setObject:all forKey:@"clenchLab.wake.v1"];}
// Refused while capturing: the session's wakeWord context is read at Start, so a mid-session send would go unrecorded.
static BOOL WakeReady(void){return TIOProtocolDevice().length&&Ready()&&Lab().wakeCommandAllowed;}
static NSString *WakeBlockedText(void){return Lab().wakeCommandAllowed?TIOText(@"clench.wake.unavailable"):TIOText(@"clench.wake.capturing");}
static NSString *LabelName(NSString *l){NSDictionary *m=@{@"double-tap":TIOText(@"clench.label.double-tap"),@"single-tap":TIOText(@"clench.label.single-tap"),@"true-clench":TIOText(@"clench.label.true-clench"),@"chew":TIOText(@"clench.label.chew"),@"talk":TIOText(@"clench.label.talk"),@"walk":TIOText(@"clench.label.walk"),@"tap-temple":TIOText(@"clench.label.tap-temple"),@"silence":TIOText(@"clench.label.silence")};return [l isKindOfClass:NSString.class]&&m[l]?m[l]:TIOText(@"clench.label.choose");}
static NSString *ErrorText(NSString *code){NSDictionary *m=@{@"busy":TIOText(@"clench.error.busy"),@"pending":TIOText(@"clench.error.pending"),@"label":TIOText(@"clench.error.label"),@"source":TIOText(@"clench.error.source"),@"device":TIOText(@"clench.error.device"),@"dump-unavailable":TIOText(@"clench.error.dump-unavailable"),@"dump-enable-failed":TIOText(@"clench.error.dump-enable-failed"),@"storage":TIOText(@"clench.error.storage"),@"inactive":TIOText(@"clench.error.inactive")};return m[code]?:TIOText(@"clench.error.storage");}
static NSString *Clock(NSTimeInterval at){NSDateFormatter *f=[NSDateFormatter new];f.dateStyle=NSDateFormatterNoStyle;f.timeStyle=NSDateFormatterShortStyle;return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:at]];}

@interface TIOClenchLabPanel:UITableViewController
@property(nonatomic,copy) NSString *label,*shape,*listKey;
@property(nonatomic,strong) NSArray<NSDictionary *> *sessions;
@property(nonatomic,strong) NSTimer *poll;
@property(nonatomic,weak) UIButton *markButton;
@property(nonatomic,weak) UILabel *statusTitle,*statusDetail;
@end
@implementation TIOClenchLabPanel
- (void)viewDidLoad{
 [super viewDidLoad];self.title=TIOText(@"hub.row.clenchLab");TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=TIOHitMin*2;self.label=Lab().label;
 TIOAttachInfo(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.footer.privacy"));
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(labChanged) name:TIOClenchLabChangedNotification object:nil];
 // A temporary zip left by an interrupted share is removed; nothing in the session folders is touched.
 if(!Sharing)[NSFileManager.defaultManager removeItemAtURL:TIOClenchDefaultExportRoot() error:nil];
 // A record from an earlier launch says the Lab changed the dump config: put it back (read-back verified). No glasses command.
 if(!Busy)[Lab() restorePendingDump];
 [self reloadSessions];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[_poll invalidate];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];__weak typeof(self) weak=self;[self.poll invalidate];self.poll=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weak pollOfficial];}];[self reloadSessions];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.poll invalidate];self.poll=nil;ManualAttach=nil;}
- (void)reloadSessions{[self readSessions];[self labChanged];}
- (void)readSessions{self.sessions=TIOClenchListSessions(TIOClenchDefaultRoot());self.listKey=TIOClenchListStateKey(Lab());self.shape=nil;}
- (NSString *)currentShape{NSDictionary *p=Lab().pending;return [NSString stringWithFormat:@"%ld|%d|%d|%@|%@|%@|%lu|%@|%d|%d|%d|%d",(long)Lab().phase,Lab().stopRequested,p!=nil,p[@"stopPending"],p[@"dumpRestored"],p[@"dumpRestoreWaived"],(unsigned long)self.sessions.count,self.label,TIOProtocolDevice().length>0,Ready(),Busy,[self offerConfirm]];}
- (void)labChanged{
 // Re-read when the Lab's phase, session or pending record moved since the list was read, or when the finished session's
 // row was listed mid-capture (so its manifest, actions, stop state and auto-attach see the finished session).
 if(!Busy&&TIOClenchSessionListStale(self.sessions,self.listKey,Lab()))[self readSessions];
 NSString *shape=[self currentShape];if(![shape isEqual:self.shape]){self.shape=shape;[self.tableView reloadData];return;}
 self.statusTitle.text=[self statusWord];self.statusDetail.text=[self statusText];
 if(self.markButton){UIButtonConfiguration *c=self.markButton.configuration;c.title=Fmt(@"clench.mark.count",(long)Lab().markCount);self.markButton.configuration=c;self.markButton.accessibilityValue=[NSString stringWithFormat:@"%lu",(unsigned long)Lab().markCount];}
}
- (void)pollOfficial{
 if(Lab().phase==TIOClenchPhaseCapturing||Busy)return;[Lab() observeOfficialStatus];ArmRestore();
 // A waiting manual Attach owns the settle readings until it attaches, is refused or times out.
 if(ManualAttach){NSURL *dir=ManualAttach;NSString *gate=[Lab() attachGate:dir];
  if(!gate){ManualAttach=nil;[self attach:dir automatic:NO];return;}
  if([gate isEqual:@"settling"]&&++ManualPolls<ManualAttachPolls)return;
  ManualAttach=nil;TIONotice(self,TIOText(@"hub.row.clenchLab"),[gate isEqual:@"dump-outstanding"]?TIOText(@"clench.pending.detail.dump"):TIOText(@"clench.attach.blocked"));return;}
 // Attach automatically once per session, after the official session has settled as stopped (several readings with the
 // session's own glasses connected) and the dump config is back. A partial attach is re-run by hand.
 NSDictionary *row=self.sessions.firstObject;NSDictionary *m=row[@"manifest"];NSString *sid=row[@"id"];if(!m||![m[@"officialAttach"] isEqual:@"waiting"]||[AutoAttached containsObject:sid])return;
 if([Lab() attachGate:row[@"url"]])return;
 [AutoAttached addObject:sid];[self attach:row[@"url"] automatic:YES];
}
- (TIODesignStatus)statusTone{if(Lab().phase==TIOClenchPhaseCapturing)return TIODesignStatusWarn;if(Lab().pending)return TIODesignStatusDanger;return Lab().phase==TIOClenchPhaseFinished?TIODesignStatusOk:TIODesignStatusNeutral;}
- (NSString *)statusWord{
 if(Lab().phase==TIOClenchPhaseCapturing)return Lab().stopRequested?TIOText(@"clench.phase.stopping"):TIOText(@"clench.phase.capturing");
 if(Lab().pending)return TIOText(@"clench.phase.pending");return Lab().phase==TIOClenchPhaseFinished?TIOText(@"clench.phase.saved"):TIOText(@"clench.phase.idle");
}
- (NSString *)statusText{
 TIOClenchSession *s=Lab();long left=(long)ceil(s.remaining);
 if(s.phase==TIOClenchPhaseCapturing){
  if(s.stopRequested)return Fmt(@"clench.status.stopping",left,(long)s.markCount);
  id rt=s.lastCounter[@"realtimePackets"];NSString *official=[rt isKindOfClass:NSNumber.class]?[rt stringValue]:TIOText(@"clench.status.officialUnavailable");
  return Fmt(@"clench.status.capturing",left,(long)s.markCount,(long)s.packetCount,(long)s.droppedPackets,official);
 }
 if(s.phase==TIOClenchPhaseFinished)return Fmt(@"clench.status.saved",LabelName(s.label),(long)lround(s.durationSeconds),(long)s.markCount,(long)s.packetCount);
 return TIOAOStatus()?TIOText(@"clench.status.idle"):TIOText(@"clench.status.officialUnavailable");
}
- (BOOL)locked{return Lab().phase==TIOClenchPhaseCapturing||Lab().pending!=nil;}
// The confirm row is offered for an unconfirmed stop, and also when a dump restore is outstanding but cannot be read back
// (official interface unavailable): confirming then records the waiver instead of blocking Start for good.
- (BOOL)offerConfirm{NSDictionary *p=Lab().pending;return p&&([p[@"stopPending"] boolValue]||(DumpOutstanding(p)&&!TIOClenchDumpConfig(TIOAOStatus())));}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 5;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{
 if(s==0){NSDictionary *p=Lab().pending;if(!p||Lab().phase==TIOClenchPhaseCapturing)return 1;return [self offerConfirm]?4:3;}if(s==1)return 2;if(s==2)return Lab().phase==TIOClenchPhaseCapturing?2:1;if(s==3)return MAX(1,(NSInteger)self.sessions.count);return 2;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[TIOText(@"clench.section.status"),TIOText(@"clench.section.setup"),TIOText(@"clench.section.capture"),TIOText(@"clench.section.sessions"),TIOText(@"clench.section.wake")][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
 if(s==1)return TIOText(@"clench.source.detail");if(s==2)return Lab().phase==TIOClenchPhaseCapturing?TIOText(@"clench.capture.footer.active"):TIOText(@"clench.capture.footer.idle");
 if(s==3)return TIOText(@"clench.footer.privacy");if(s==4)return TIOText(@"clench.wake.footer");return nil;
}
- (UITableViewCell *)subtitleCell{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;return c;}
- (UITableViewCell *)buttonCell:(NSString *)title role:(TIODesignButtonRole)role action:(SEL)action enabled:(BOOL)enabled tall:(BOOL)tall down:(BOOL)down{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];TIOStyleResearchCell(c);c.selectionStyle=UITableViewCellSelectionStyleNone;
 UIButtonConfiguration *cfg=[UIButtonConfiguration plainButtonConfiguration];cfg.title=title;UIButton *b=[UIButton buttonWithConfiguration:cfg primaryAction:nil];b.translatesAutoresizingMaskIntoConstraints=NO;TIODesignStyleButton(b,role);b.enabled=enabled;
 [b addTarget:self action:action forControlEvents:down?UIControlEventTouchDown:UIControlEventTouchUpInside];[c.contentView addSubview:b];UILayoutGuide *g=c.contentView.layoutMarginsGuide;
 [NSLayoutConstraint activateConstraints:@[[b.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[b.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],[b.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:TIOSpace2],
  [b.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-TIOSpace2],[b.heightAnchor constraintGreaterThanOrEqualToConstant:tall?TIOHitMin*2:TIOHitMin]]];return c;
}
- (UITableViewCell *)statusCell{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];TIOStyleResearchCell(c);c.selectionStyle=UITableViewCellSelectionStyleNone;
 UIView *pill=TIODesignStatusPill([self statusTone],[self statusWord]);UILabel *title=[UILabel new],*detail=[UILabel new];
 title.font=TIODesignFont(TIODesignTextStyleHeadline);title.textColor=TIODesignColor(TIODesignColorLabel);detail.font=TIODesignFont(TIODesignTextStyleSubheadline);detail.textColor=TIODesignColor(TIODesignColorLabelSecondary);
 for(UILabel *l in @[title,detail]){l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;}title.text=[self statusWord];detail.text=[self statusText];title.accessibilityTraits|=UIAccessibilityTraitUpdatesFrequently;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[pill,title,detail]];stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentLeading;stack.spacing=TIOSpace2;stack.translatesAutoresizingMaskIntoConstraints=NO;
 [c.contentView addSubview:stack];UILayoutGuide *g=c.contentView.layoutMarginsGuide;pill.isAccessibilityElement=NO;
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor]]];
 self.statusTitle=title;self.statusDetail=detail;return c;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
 TIOClenchSession *lab=Lab();BOOL capturing=lab.phase==TIOClenchPhaseCapturing;
 if(ip.section==0){
  if(ip.row==0)return [self statusCell];UITableViewCell *c=[self subtitleCell];NSDictionary *p=lab.pending;
  if(ip.row==1){BOOL dump=DumpOutstanding(p);c.textLabel.text=TIOText(@"clench.pending.title");c.textLabel.textColor=TIODesignColor(TIODesignColorStatusDanger);
   c.detailTextLabel.text=[p[@"stopPending"] boolValue]?(dump?[NSString stringWithFormat:@"%@\n%@",TIOText(@"clench.pending.detail.stop"),TIOText(@"clench.pending.detail.dump")]:TIOText(@"clench.pending.detail.stop")):TIOText(@"clench.pending.detail.dump");c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
  c.textLabel.text=ip.row==2?TIOText(@"clench.pending.retry"):TIOText(@"clench.pending.confirm");c.textLabel.textColor=TIODesignColor(TIODesignColorAccent);c.accessibilityTraits|=UIAccessibilityTraitButton;
  return c;
 }
 if(ip.section==1){
  UITableViewCell *c=[self subtitleCell];
  if(ip.row==0){c.textLabel.text=TIOText(@"clench.source.title");c.accessoryView=TIODesignValueAccessory(TIOText(@"clench.source.lifelog"));c.accessibilityValue=TIOText(@"clench.source.lifelog");c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
  c.textLabel.text=TIOText(@"clench.label.title");c.accessoryView=TIODesignValueAccessory(LabelName(self.label));c.accessibilityValue=LabelName(self.label);
  if([self locked]){c.textLabel.textColor=TIODesignColor(TIODesignColorLabelSecondary);c.accessibilityTraits|=UIAccessibilityTraitNotEnabled;}else c.accessibilityTraits|=UIAccessibilityTraitButton;return c;
 }
 if(ip.section==2){
  if(!capturing){BOOL can=self.label&&!lab.pending&&TIOProtocolDevice().length&&Ready()&&TIOAOStatus()!=nil&&!Busy;return [self buttonCell:TIOText(@"clench.start") role:TIODesignButtonPrimary action:@selector(start) enabled:can tall:NO down:NO];}
  if(ip.row==0){UITableViewCell *c=[self buttonCell:Fmt(@"clench.mark.count",(long)lab.markCount) role:TIODesignButtonPrimary action:@selector(markGesture) enabled:YES tall:YES down:YES];
   UIButton *b=c.contentView.subviews.lastObject;b.accessibilityLabel=TIOText(@"clench.mark");b.accessibilityValue=[NSString stringWithFormat:@"%lu",(unsigned long)lab.markCount];self.markButton=b;return c;}
  return [self buttonCell:TIOText(@"clench.stop") role:TIODesignButtonDestructive action:@selector(stopSession) enabled:!lab.stopRequested tall:NO down:NO];
 }
 if(ip.section==3){
  UITableViewCell *c=[self subtitleCell];if(!self.sessions.count){c.textLabel.text=TIOText(@"clench.sessions.empty");c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
  NSDictionary *row=self.sessions[ip.row],*m=row[@"manifest"];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  if(!m){c.textLabel.text=TIOText(@"clench.sessions.incompleteTitle");c.detailTextLabel.text=TIOText(@"clench.sessions.incomplete");return c;}
  NSString *dump=[m[@"officialAttach"] isEqual:@"done"]?([m[@"officialDump"] count]?Fmt(@"clench.sessions.dump.attached",(long)[m[@"officialDump"] count]):TIOText(@"clench.sessions.dump.none")):([m[@"officialAttach"] isEqual:@"retry"]?Fmt(@"clench.sessions.dump.retry",(long)[m[@"officialDump"] count]):TIOText(@"clench.sessions.dump.waiting"));
  c.textLabel.text=Fmt(@"clench.sessions.row",LabelName(m[@"label"]),(long)lround([m[@"durationSeconds"] doubleValue]));
  NSString *detail=Fmt(@"clench.sessions.detail",(long)[m[@"marks"] count],(long)[m[@"packets"] count],dump);
  // A checkpoint left by an app that ended mid-capture (not the capture running now).
  if([m[@"captureState"] isEqual:@"interrupted"]&&!(capturing&&[lab.sessionId isEqual:row[@"id"]]))detail=[NSString stringWithFormat:@"%@\n%@",detail,TIOText(@"clench.sessions.interrupted")];
  BOOL pending=[m[@"stopPending"] boolValue]||[lab.pending[@"sessionId"] isEqual:row[@"id"]];c.detailTextLabel.text=pending?[NSString stringWithFormat:@"%@\n%@",detail,TIOText(@"clench.sessions.stopPending")]:detail;return c;
 }
 UITableViewCell *c=[self subtitleCell];BOOL ready=WakeReady();NSDictionary *w=WakeState();
 NSString *last=w?Fmt(@"clench.wake.last",(long)[w[@"mode"] integerValue],Clock([w[@"at"] doubleValue])):TIOText(@"clench.wake.never");
 if(ip.row==0){c.textLabel.text=TIOText(@"clench.wake.off");c.detailTextLabel.text=TIOText(@"clench.wake.off.detail");c.textLabel.textColor=ready?TIODesignColor(TIODesignColorStatusDanger):TIODesignColor(TIODesignColorLabelSecondary);}
 else{c.textLabel.text=TIOText(@"clench.wake.restore");c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",TIOText(@"clench.wake.restore.detail"),last];c.textLabel.textColor=ready?TIODesignColor(TIODesignColorAccent):TIODesignColor(TIODesignColorLabelSecondary);}
 if(!ready)c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",c.detailTextLabel.text,WakeBlockedText()];
 c.accessibilityTraits|=UIAccessibilityTraitButton|(ready?0:UIAccessibilityTraitNotEnabled);return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
 [t deselectRowAtIndexPath:ip animated:YES];if(Busy)return;
 if(ip.section==0&&ip.row==2){BOOL ok=[Lab() retryPending];TIONotice(self,TIOText(@"hub.row.clenchLab"),ok?TIOText(@"clench.pending.resolved"):TIOText(@"clench.pending.unresolved"));return;}
 if(ip.section==0&&ip.row==3){TIOConfirm(self,TIOText(@"clench.pending.confirm.title"),TIOText(@"clench.pending.confirm.message"),TIOText(@"clench.pending.confirm.action"),NO,^{BOOL ok=[Lab() confirmPhysicalStop];TIONotice(self,TIOText(@"hub.row.clenchLab"),ok&&!Lab().pending?TIOText(@"clench.pending.resolved"):TIOText(@"clench.pending.unresolved"));});return;}
 if(ip.section==1&&ip.row==1&&![self locked]){NSArray *ids=TIOClenchLabels();NSMutableArray *names=[NSMutableArray new];for(NSString *l in ids)[names addObject:LabelName(l)];
  TIOChoose(self,TIOText(@"clench.label.title"),nil,names,self.label?(NSInteger)[ids indexOfObject:self.label]:-1,nil,^(NSInteger i){if(i>=0&&i<(NSInteger)ids.count&&![self locked]){self.label=ids[i];[self labChanged];}});return;}
 if(ip.section==3&&self.sessions.count&&ip.row<(NSInteger)self.sessions.count){[self sessionActions:self.sessions[ip.row]];return;}
 if(ip.section==4)[self wake:ip.row==0?0:1];
}
- (void)start{
 if(!self.label){TIONotice(self,TIOText(@"hub.row.clenchLab"),ErrorText(@"label"));return;}if(!Ready()){TIONotice(self,TIOText(@"hub.row.clenchLab"),ErrorText(@"inactive"));return;}
 TIOConfirm(self,TIOText(@"clench.consent.title"),TIOText(@"clench.consent.message"),TIOText(@"clench.consent.action"),NO,^{
  if(!Ready()){TIONotice(self,TIOText(@"hub.row.clenchLab"),ErrorText(@"inactive"));return;}
  NSDictionary *w=WakeState();Lab().context=@{@"lastSubmittedMode":w[@"mode"]?:NSNull.null,@"submittedAtEpochSeconds":w[@"at"]?:NSNull.null,@"glassesConfirmed":@NO};
  NSString *error=[Lab() startWithLabel:self.label source:@"lifelog"];if(error){TIONotice(self,TIOText(@"hub.row.clenchLab"),ErrorText(error));[self labChanged];return;}
  Arm();[self labChanged];TIONotice(self,TIOText(@"clench.started.title"),TIOText(@"clench.started.message"));
 });
}
- (void)markGesture{if([Lab() mark]){[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];[self labChanged];}}
- (void)stopSession{[Lab() requestStop:@"manual"];}
- (BOOL)pendingFor:(NSDictionary *)row{return [row[@"manifest"][@"stopPending"] boolValue]||[Lab().pending[@"sessionId"] isEqual:row[@"id"]];}
- (void)sessionActions:(NSDictionary *)row{
 NSURL *dir=row[@"url"];BOOL complete=[row[@"complete"] boolValue],current=Lab().phase==TIOClenchPhaseCapturing&&[Lab().sessionId isEqual:row[@"id"]];
 NSArray *options=complete?@[TIOText(@"clench.action.share"),TIOText(@"clench.action.attach"),TIOText(@"clench.action.delete")]:@[TIOText(@"clench.action.delete")];
 TIOChoose(self,TIOText(@"clench.section.sessions"),nil,options,-1,[NSIndexSet indexSetWithIndex:options.count-1],^(NSInteger i){
  if(i==(NSInteger)options.count-1){if(current)return;if([self deleteBlocked:dir]){TIONotice(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.delete.busy"));return;}
   TIOConfirm(self,TIOText(@"clench.delete.title"),TIOText(@"clench.delete.message"),TIOText(@"clench.delete.action"),YES,^{
    // Checked again at confirmation: an automatic attach may have started while the alert was up.
    if([self deleteBlocked:dir]||!TIOClenchDeleteSession(TIOClenchDefaultRoot(),dir)){TIONotice(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.delete.busy"));return;}[self reloadSessions];});return;}
  if(i==0)[self share:row];else if(i==1)[self requestAttach:dir];
 });
}
// Delete waits for any attach or zip (Busy is global) and for a manual Attach still waiting on this session.
- (BOOL)deleteBlocked:(NSURL *)dir{return Busy||TIOClenchSessionInUse(dir)||[ManualAttach.path isEqual:dir.path];}
- (void)share:(NSDictionary *)row{
 if(Busy)return;if(Lab().phase==TIOClenchPhaseCapturing||[self pendingFor:row]){TIONotice(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.share.blocked"));return;}
 NSURL *dir=row[@"url"];Busy=YES;Sharing=YES;[self labChanged];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSURL *zip=TIOClenchZipSession(dir,TIOClenchDefaultExportRoot());dispatch_async(dispatch_get_main_queue(),^{
  Busy=NO;[self labChanged];if(!zip){Sharing=NO;TIONotice(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.share.failed"));return;}NSURL *folder=zip.URLByDeletingLastPathComponent;
  // Popped or covered while the zip was built: a share sheet cannot appear, so drop the temporary zip now.
  if(!self.isViewLoaded||!self.view.window||self.presentedViewController){[NSFileManager.defaultManager removeItemAtURL:folder error:nil];Sharing=NO;return;}
  UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[zip] applicationActivities:nil];
  a.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *error){[NSFileManager.defaultManager removeItemAtURL:folder error:nil];Sharing=NO;};
  a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),TIOSpace8*3,1,1);[self presentViewController:a animated:YES completion:^{if(!a.presentingViewController){[NSFileManager.defaultManager removeItemAtURL:folder error:nil];Sharing=NO;}}];
 });});
}
// Manual Attach from the session menu: the same gate as the automatic attach (target glasses, link loss, settle). It
// attaches at once when the gate is already open, else waits on the 1 s poll for the settle, else says why not.
- (void)requestAttach:(NSURL *)dir{
 if(Busy)return;NSString *gate=[Lab() attachGate:dir];if(!gate){ManualAttach=nil;[self attach:dir automatic:NO];return;}
 if([gate isEqual:@"settling"]){ManualAttach=dir;ManualPolls=0;TIONotice(self,TIOText(@"hub.row.clenchLab"),TIOText(@"clench.attach.settling"));return;}
 TIONotice(self,TIOText(@"hub.row.clenchLab"),[gate isEqual:@"dump-outstanding"]?TIOText(@"clench.pending.detail.dump"):TIOText(@"clench.attach.blocked"));
}
// Callers have passed attachGate on this poll.
- (void)attach:(NSURL *)dir automatic:(BOOL)automatic{
 if(Busy||Lab().phase==TIOClenchPhaseCapturing)return;
 Busy=YES;[self labChanged];NSURL *home=Lab().config.officialHome;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *r=TIOClenchAttachOfficial(dir,home);dispatch_async(dispatch_get_main_queue(),^{
  Busy=NO;[self reloadSessions];if(automatic&&r&&![r[@"state"] isEqual:@"retry"])return;
  NSString *text=!r?TIOText(@"clench.attach.failed"):([r[@"alreadyAttached"] boolValue]?TIOText(@"clench.attach.already"):Fmt([r[@"state"] isEqual:@"retry"]?@"clench.attach.partial":@"clench.attach.done",(long)[r[@"files"] integerValue],(long)[r[@"events"] integerValue]));TIONotice(self,TIOText(@"hub.row.clenchLab"),text);
 });});
}
// Sent only; never shown as the glasses' state. Restore (mode 1) is always offered and needs no confirmation.
- (void)wake:(NSInteger)mode{
 if(!WakeReady()){TIONotice(self,TIOText(@"clench.section.wake"),WakeBlockedText());return;}
 void(^send)(void)=^{NSData *packet=TIOClenchWakeupPacket(mode);BOOL ok=packet&&WakeReady()&&TIOProtocolSendBusiness(15,packet);if(ok)SaveWake(mode);[self.tableView reloadData];TIONotice(self,TIOText(@"clench.section.wake"),ok?TIOText(@"clench.wake.sent"):TIOText(@"clench.wake.failed"));};
 if(mode==0)TIOConfirm(self,TIOText(@"clench.wake.confirm.title"),TIOText(@"clench.wake.confirm.message"),TIOText(@"clench.wake.confirm.action"),YES,send);else send();
}
@end
UIViewController *TIOClenchLabController(void){return [[TIOClenchLabPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
// Crash recovery without opening the panel: a record from an earlier run that says the Lab turned the official dump
// on is restored (read-back verified) at launch and whenever the app becomes active. Never sends a glasses command.
void TIOClenchLabInstallRecovery(void){
 static dispatch_once_t once;
 dispatch_once(&once,^{
  void(^run)(void)=^{TIOClenchSession *lab=Lab();[lab releaseIdleTimer];if(Busy)return;if(lab.phase!=TIOClenchPhaseCapturing&&RestoreOwed()&&![lab restorePendingDump])ArmRestore();};
  // A temporary share zip left by a share that was interrupted by termination is removed at launch.
  dispatch_async(dispatch_get_main_queue(),^{if(!Sharing)[NSFileManager.defaultManager removeItemAtURL:TIOClenchDefaultExportRoot() error:nil];run();});
  [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){run();}];
 });
}
#endif
