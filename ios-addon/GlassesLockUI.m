#import "GlassesLockUI.h"
#import "TIOLanguage.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import "TIODesign.h"
#import "TIOConfirm.h"
#import "TDPhoneBridge.h"
#import "TDPhoneRun.h"
#include "lock_codec.h"
#include "diagnostics.h"

static TIOGlassesLockLink *Link(void){
 static TIOGlassesLockLink *link;static dispatch_once_t once;
 dispatch_once(&once,^{link=[[TIOGlassesLockLink alloc]initWithPeer:^{return TIOProtocolDevice();} allowed:^BOOL{
  id stage=TIOOTAFlashStatus()[@"stage"];return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;
 } clock:^{return NSProcessInfo.processInfo.systemUptime;} caps:^uint32_t{return TDGlassesCaps();} send:^BOOL(NSData *data){return TIOProtocolSendBusiness(15,data);}];
 link.seen=[[NSUserDefaults alloc]initWithSuiteName:@"org.turboio.addon.lock"];
 [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[link cancel];}];
 });return link;
}
static TIOLockMotion *Motion(void){
 static TIOLockMotion *motion;static dispatch_once_t once;
 dispatch_once(&once,^{motion=[[TIOLockMotion alloc]initWithDefaults:[[NSUserDefaults alloc]initWithSuiteName:@"org.turboio.addon.lock"] clock:^{return NSProcessInfo.processInfo.systemUptime;}];});return motion;
}
BOOL TIOGlassesLockConsume(NSDictionary *e){return [Link() consume:e];}
BOOL TIOGlassesLockHubVisible(void){TIOGlassesLockLink *l=Link();return l.supported||l.undecided;}
NSString *TIOGlassesLockHubStatus(void){NSString *key=TIOLockPhaseTextId(Link().model.phase);return key?TIOText(key):nil;}
void TIOGlassesLockHubRefresh(void){
 static double asked;double now=NSProcessInfo.processInfo.systemUptime;
 if(!TIOProtocolDevice().length||TDGlassesCaps()||(asked>0&&now-asked<TDGlassesCapsRefreshSeconds))return;
 asked=now;if(!TDGlassesCapsRefresh())return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{TIOHubReload();});   /* the subtitle may change */
}
/* Sends MOTION_ON to the connected glasses when the switch is on; counts the answer for the early-drop rule. */
static void SendMotion(TIOGlassesLockLink *link,TIOLockMotion *motion,void(^done)(void)){
 if(!motion.wanted){if(done)done();return;}
 [link motionOn:^{
  if(link.lastOp==TLK_OP_MOTION_ON&&link.lastResult==TLK_R_OK){
   [motion motionAccepted];NSString *peer=TIOProtocolDevice();
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((TIOLockEarlyDropSeconds+1)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if([TIOProtocolDevice() isEqual:peer])[motion linkSurvived];});
  }
  if(done)done();
 }];
}
void TIOGlassesLockStart(void){
 NSCAssert(NSThread.isMainThread,@"main only");static dispatch_once_t once;
 dispatch_once(&once,^{
  __block NSString *last=[TIOProtocolDevice() copy];__block NSUInteger epoch=0;
  [NSNotificationCenter.defaultCenter addObserverForName:TIOProtocolDeviceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
   (void)n;NSString *peer=[TIOProtocolDevice() copy];if([peer isEqual:last]||(!peer.length&&!last.length))return;
   if(last.length)[Motion() linkDropped];
   last=peer;NSUInteger mine=++epoch;if(!peer.length||!Motion().wanted)return;
   /* Give the connection a moment, make sure the capability bits are known, then send it once. */
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    if(mine!=epoch||![TIOProtocolDevice() isEqual:peer])return;
    if(TIOGlassesLockHubVisible()){SendMotion(Link(),Motion(),nil);return;}
    if(!TDGlassesCapsRefresh())return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(mine==epoch&&[TIOProtocolDevice() isEqual:peer]&&TIOGlassesLockHubVisible())SendMotion(Link(),Motion(),nil);});
   });
  }];
 });
}

typedef NS_ENUM(NSInteger,TIOLockRow){RowEnable,RowStatus,RowUnlock,RowLockNow,RowFold,RowIdle,RowWorn,RowChangePin};
static NSString *const RowIds[]={@"lock-enable",@"lock-status",@"lock-unlock",@"lock-lock-now",@"lock-fold",@"lock-idle",@"lock-worn",@"lock-change-pin"};
static NSString *Minutes(unsigned minutes){NSString *format=TIOText(@"lock.minutes");return [NSString stringWithFormat:format,minutes];}

@interface TIOGlassesLockUI:UITableViewController
@property(nonatomic,strong) TIOGlassesLockLink *link;
@property(nonatomic,strong) TIOLockMotion *motion;
@property(nonatomic,copy) NSArray<NSDictionary *> *layout; /* sections: rows (TIOLockRow), header, footer */
@end
@implementation TIOGlassesLockUI
- (void)viewDidLoad{
 [super viewDidLoad];self.title=TIOText(@"hub.row.glassesLock");TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=62;
 if(!self.link)self.link=Link();
 if(!self.motion)self.motion=Motion();
 UIRefreshControl *pull=[UIRefreshControl new];[pull addTarget:self action:@selector(pulled:) forControlEvents:UIControlEventValueChanged];self.refreshControl=pull;
 [self rebuild];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self refresh];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.link cancel];}
- (void)pulled:(UIRefreshControl *)control{[control endRefreshing];[self refresh];}
/* The state is read from the glasses on every visit; with the switch on, glasses that can use head motion get MOTION_ON. */
- (void)refresh{
 __weak typeof(self) w=self;
 [self.link query:^{typeof(self) s=w;if(!s)return;TIOLockModel m=s.link.model;
  if(s.link.lastResult==TLK_R_OK&&s.motion.wanted&&m.lockOn&&m.motionSupported&&!m.motionOn)SendMotion(s.link,s.motion,^{[w rebuild];});
  [s rebuild];}];
 [self rebuild];
}
- (void)rebuild{
 TIOLockModel m=self.link.model;NSMutableArray *layout=[NSMutableArray new];
 /* No glasses, or glasses without the lock (and none seen on them): the explanation page, no controls. */
 if(!self.link.known&&!self.link.supported&&!self.link.undecided){
  NSString *why=TIOText(self.link.connected?@"lock.note.unsupported":@"lock.note.connect");
  [layout addObject:@{@"rows":@[],@"header":TIOText(@"lock.header.unavailable"),@"footer":[NSString stringWithFormat:@"%@\n\n%@",why,TIOText(@"lock.footer.main")]}];
  self.layout=layout;[self.tableView reloadData];return;
 }
 [layout addObject:@{@"rows":@[@(RowEnable),@(RowStatus)],@"footer":self.link.note?:@""}];
 if(m.showUnlock)[layout addObject:@{@"rows":@[@(RowUnlock)]}];
 else if(m.showLockNow)[layout addObject:@{@"rows":@[@(RowLockNow)]}];
 if(m.lockOn){
  /* Firmware without the motion hook counts knob and key input only, so worn glasses lock at the idle time: say so under
   * the idle setting and leave out the switch that could not work. */
  if(m.motionSupported){
   [layout addObject:@{@"rows":@[@(RowFold),@(RowIdle)],@"header":TIOText(@"lock.header.auto")}];
   NSString *worn=TIOText(@"lock.footer.worn");if(self.motion.offAfterDrops)worn=[NSString stringWithFormat:@"%@\n\n%@",TIOText(@"lock.worn.offAfterDrops"),worn];
   [layout addObject:@{@"rows":@[@(RowWorn)],@"footer":worn}];
  }else [layout addObject:@{@"rows":@[@(RowFold),@(RowIdle)],@"header":TIOText(@"lock.header.auto"),@"footer":TIOText(@"lock.footer.idleNoMotion")}];
  [layout addObject:@{@"rows":@[@(RowChangePin)],@"footer":TIOText(@"lock.footer.main")}];
 }else if(self.link.known)[layout addObject:@{@"rows":@[],@"footer":TIOText(@"lock.footer.main")}];
 self.layout=layout;[self.tableView reloadData];
}
- (TIOLockRow)rowAt:(NSIndexPath *)p{return (TIOLockRow)[self.layout[p.section][@"rows"][p.row] integerValue];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{(void)t;return (NSInteger)self.layout.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{(void)t;return (NSInteger)[self.layout[s][@"rows"] count];}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{(void)t;return self.layout[s][@"header"];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{(void)t;NSString *f=self.layout[s][@"footer"];return f.length?f:nil;}
- (UISwitch *)toggle:(BOOL)on enabled:(BOOL)enabled label:(NSString *)label action:(SEL)action{
 UISwitch *s=[UISwitch new];s.on=on;s.enabled=enabled;s.onTintColor=TIODesignColor(TIODesignColorAccentFill);s.accessibilityLabel=label;[s addTarget:self action:action forControlEvents:UIControlEventValueChanged];return s;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 (void)t;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 TIOLockRow row=[self rowAt:p];TIOLockModel m=self.link.model;BOOL idle=!self.link.busy,known=self.link.known;c.accessibilityIdentifier=RowIds[row];
 switch(row){
  case RowEnable:c.textLabel.text=TIOText(@"lock.row.enable");c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessoryView=[self toggle:m.lockOn enabled:known&&idle label:c.textLabel.text action:@selector(enableChanged:)];break;
  case RowStatus:[self styleStatus:c model:m];break;
  case RowUnlock:[self styleAction:c title:TIOText(@"lock.action.unlock") primary:YES enabled:idle];break;
  case RowLockNow:[self styleAction:c title:TIOText(@"lock.action.lockNow") primary:NO enabled:idle];break;
  case RowFold:case RowIdle:{
   NSString *value=Minutes(row==RowFold?m.foldMin:m.idleMin);c.textLabel.text=TIOText(row==RowFold?@"lock.row.fold":@"lock.row.idle");
   c.accessoryView=TIODesignValueAccessory(value);c.accessibilityValue=value;c.accessibilityTraits|=UIAccessibilityTraitButton;c.userInteractionEnabled=idle;break;}
  case RowWorn:c.textLabel.text=TIOText(@"lock.row.worn");c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessoryView=[self toggle:self.motion.wanted enabled:idle label:c.textLabel.text action:@selector(wornChanged:)];break;
  case RowChangePin:c.textLabel.text=TIOText(@"lock.row.changePin");c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.userInteractionEnabled=idle;break;
 }
 return c;
}
/* Symbol plus word, never color alone. Wrong tries since the last unlock are a status-warn line with a Dismiss action. */
- (void)styleStatus:(UITableViewCell *)c model:(TIOLockModel)m{
 NSString *symbol;TIODesignColorToken tone;NSString *word=TIOLockPhaseTextId(m.phase)?TIOText(TIOLockPhaseTextId(m.phase)):TIOText(@"lock.state.unknown");
 switch(m.phase){
  case TIOLockPhaseLocked:symbol=@"lock.fill";tone=TIODesignColorAccent;break;
  case TIOLockPhaseUnlocked:symbol=@"lock.open.fill";tone=TIODesignColorStatusOk;break;
  case TIOLockPhaseOff:symbol=@"lock.open";tone=TIODesignColorLabelSecondary;break;
  default:symbol=@"arrow.clockwise";tone=TIODesignColorAccent;break;
 }
 c.textLabel.text=word;c.detailTextLabel.text=nil;
 if(m.damaged){symbol=@"xmark.octagon.fill";tone=TIODesignColorStatusDanger;c.textLabel.text=TIOText(@"lock.damaged");c.detailTextLabel.text=word;}
 else if(m.wrong){
  symbol=@"exclamationmark.triangle.fill";tone=TIODesignColorStatusWarn;
  NSString *many=TIOText(@"lock.wrong.many");c.textLabel.text=m.wrong==1?TIOText(@"lock.wrong.one"):[NSString stringWithFormat:many,m.wrong];c.detailTextLabel.text=word;
  UIButton *dismiss=[UIButton buttonWithType:UIButtonTypeSystem];[dismiss setTitle:TIOText(@"lock.action.dismiss") forState:UIControlStateNormal];dismiss.titleLabel.font=TIODesignFont(TIODesignTextStyleBody);dismiss.titleLabel.adjustsFontForContentSizeCategory=YES;
  dismiss.tintColor=TIODesignColor(TIODesignColorAccent);dismiss.enabled=!self.link.busy;dismiss.accessibilityIdentifier=@"lock-dismiss";[dismiss addTarget:self action:@selector(dismissFailures) forControlEvents:UIControlEventTouchUpInside];
  [dismiss sizeToFit];CGRect frame=dismiss.frame;frame.size.height=MAX(frame.size.height,TIOHitMin);frame.size.width=MAX(frame.size.width,TIOHitMin);dismiss.frame=frame;c.accessoryView=dismiss;
 }
 c.imageView.image=[UIImage systemImageNamed:symbol];c.imageView.tintColor=TIODesignColor(tone);c.imageView.isAccessibilityElement=NO;
 if(!self.link.known){c.accessibilityTraits|=UIAccessibilityTraitButton;c.userInteractionEnabled=!self.link.busy;}else c.selectionStyle=UITableViewCellSelectionStyleNone;
}
/* The one filled button (Unlock glasses) or the secondary one (Lock now), as capsules. */
- (void)styleAction:(UITableViewCell *)c title:(NSString *)title primary:(BOOL)primary enabled:(BOOL)enabled{
 c.textLabel.text=title;c.textLabel.hidden=YES;c.detailTextLabel.text=nil;c.backgroundColor=UIColor.clearColor;c.backgroundView=nil;c.selectedBackgroundView=nil;c.selectionStyle=UITableViewCellSelectionStyleNone;
 UIColor *ink=!enabled?TIODesignColor(TIODesignColorLabelTertiary):primary?TIODesignColor(TIODesignColorOnAccent):TIODesignColor(TIODesignColorAccent);
 UIView *capsule=[UIView new];capsule.translatesAutoresizingMaskIntoConstraints=NO;capsule.userInteractionEnabled=NO;capsule.layer.cornerRadius=TIOButtonHeight/2;capsule.layer.cornerCurve=kCACornerCurveContinuous;
 capsule.backgroundColor=!enabled?TIODesignColor(TIODesignColorBgSunken):primary?TIODesignColor(TIODesignColorAccentFill):TIODesignColor(TIODesignColorAccentSoft);
 UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.text=title;label.textAlignment=NSTextAlignmentCenter;label.numberOfLines=0;label.textColor=ink;label.font=TIODesignFont(TIODesignTextStyleHeadline);label.adjustsFontForContentSizeCategory=YES;label.isAccessibilityElement=NO;
 [capsule addSubview:label];[c.contentView insertSubview:capsule atIndex:0];
 [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:TIOSpace4],[label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-TIOSpace4],[label.topAnchor constraintEqualToAnchor:capsule.topAnchor constant:TIOSpace3],[label.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor constant:-TIOSpace3],
  [capsule.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:TIOSpace4],[capsule.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-TIOSpace4],[capsule.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:TIOSpace1],[capsule.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-TIOSpace1],
  [capsule.heightAnchor constraintGreaterThanOrEqualToConstant:primary?TIOButtonHeight:TIOHitMin]]];
 c.userInteractionEnabled=enabled;c.accessibilityTraits=UIAccessibilityTraitButton|(enabled?0:UIAccessibilityTraitNotEnabled);c.accessibilityLabel=title;
}
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)p{(void)t;TIOLockRow row=[self rowAt:p];if(row==RowUnlock||row==RowLockNow)cell.separatorInset=UIEdgeInsetsMake(0,cell.bounds.size.width,0,0);}
- (void)done{[self rebuild];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(self.link.busy)return;__weak typeof(self) w=self;TIOLockRow row=[self rowAt:p];
 if(row==RowStatus){if(!self.link.known)[self refresh];}
 else if(row==RowUnlock){[self.link unlock:^{[w done];}];[self rebuild];}
 else if(row==RowLockNow){[self.link lockNow:^{[w done];}];[self rebuild];}
 else if(row==RowFold||row==RowIdle)[self chooseMinutes:row==RowFold];
 else if(row==RowChangePin)[self askPin];
}
- (void)chooseMinutes:(BOOL)fold{
 TIOLockModel m=self.link.model;unsigned current=fold?m.foldMin:m.idleMin;
 NSMutableArray<NSNumber *> *values=[@[@1,@2,@5,@10,@15,@30,@60,@120,@240]mutableCopy];if(![values containsObject:@(current)]){[values addObject:@(current)];[values sortUsingSelector:@selector(compare:)];}
 NSMutableArray<NSString *> *titles=[NSMutableArray new];for(NSNumber *v in values)[titles addObject:Minutes(v.unsignedIntValue)];
 __weak typeof(self) w=self;
 TIOChoose(self,TIOText(fold?@"lock.row.fold":@"lock.row.idle"),nil,titles,(NSInteger)[values indexOfObject:@(current)],nil,^(NSInteger index){
  typeof(self) s=w;if(!s||index<0||index>=(NSInteger)values.count)return;unsigned v=values[index].unsignedIntValue;TIOLockModel now=s.link.model;
  [s.link setFold:fold?v:now.foldMin idle:fold?now.idleMin:v done:^{[w done];}];[s rebuild];
 });
}
/* A new 4-digit PIN, twice. Used to turn the lock on and for Change PIN, which never asks for the old one. */
- (void)askPin{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:TIOText(@"lock.pin.title") message:TIOText(@"lock.pin.message") preferredStyle:UIAlertControllerStyleAlert];
 for(NSString *placeholder in @[TIOText(@"lock.pin.field"),TIOText(@"lock.pin.again")])[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=placeholder;f.secureTextEntry=YES;f.keyboardType=UIKeyboardTypeNumberPad;f.textContentType=UITextContentTypeOneTimeCode;}];
 [a addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
 __weak UIAlertController *weakAlert=a;__weak typeof(self) w=self;
 [a addAction:[UIAlertAction actionWithTitle:TIOText(@"lock.pin.set") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
  (void)action;typeof(self) s=w;NSString *first=weakAlert.textFields[0].text?:@"",*second=weakAlert.textFields[1].text?:@"";uint8_t pin[4];
  if(!s)return;
  if(![first isEqual:second]||!TIOLockParsePin(first,pin)){TIONotice(s,TIOText(@"lock.pin.title"),TIOText(@"lock.pin.mismatch"));return;}
  [s.link setPin:first done:^{[w done];}];[s rebuild];
 }]];
 [self presentViewController:a animated:YES completion:nil];
}
- (void)enableChanged:(UISwitch *)sender{
 BOOL on=sender.on;sender.on=self.link.model.lockOn; /* the switch follows the glasses' answer, never the tap */
 if(self.link.busy||on==self.link.model.lockOn)return;
 if(on){[self askPin];return;}
 __weak typeof(self) w=self;
 TIOConfirm(self,TIOText(@"lock.off.title"),TIOText(@"lock.off.message"),TIOText(@"lock.off.action"),YES,^{typeof(self) s=w;[s.link disable:^{[w done];}];[s rebuild];});
}
- (void)wornChanged:(UISwitch *)sender{
 self.motion.wanted=sender.on;
 if(sender.on){__weak typeof(self) w=self;SendMotion(self.link,self.motion,^{[w done];});}
 [self rebuild];
}
- (void)dismissFailures{__weak typeof(self) w=self;[self.link acknowledgeFailures:^{[w done];}];[self rebuild];}
@end
UIViewController *TIOGlassesLockController(void){return [[TIOGlassesLockUI alloc]initWithStyle:UITableViewStyleInsetGrouped];}

#if TIO_UI_PREVIEW
/* Canned glasses for the preview gate. The real link, codec and token session answer from a local state. */
UIViewController *TIOGlassesLockPreviewController(NSString *fixture){
 __block TLKSession session={0};__block uint32_t nonce=0;__block uint8_t flags=0,unacked=0,wrong=0,fold=5,idle=5;
 if([fixture isEqual:@"unlocked"])flags=TLK_F_ENABLED;
 else if([fixture isEqual:@"locked"])flags=TLK_F_ENABLED|TLK_F_LOCKED;
 else if([fixture isEqual:@"wrong"]){flags=TLK_F_ENABLED|TLK_F_LOCKED;wrong=3;unacked=3;}
 /* "unsupported": glasses without the lock; "none": no glasses connected (the explanation page, device feedback 5). */
 uint32_t caps=[fixture isEqual:@"unsupported"]?TD_CAPS_TMG9:[fixture isEqual:@"none"]?0:TD_CAP_PIN_LOCK;
 __block __weak TIOGlassesLockLink *weak=nil;NSString *peer=[fixture isEqual:@"none"]?@"":@"preview-lock";
 TIOGlassesLockLink *link=[[TIOGlassesLockLink alloc]initWithPeer:^{return peer;} allowed:^BOOL{return YES;} clock:^{return NSProcessInfo.processInfo.systemUptime;} caps:^uint32_t{return caps;} send:^BOOL(NSData *data){
  uint8_t raw[32],wire[74];TLKCommand q;if(!tlk_uncarrier(data.bytes,data.length,raw,false)||!tlk_decode(raw,32,&q))return NO;
  unsigned r=tlk_session(&session,&q,(uint32_t)(NSProcessInfo.processInfo.systemUptime*1000),++nonce);
  if(r==TLK_R_OK)switch(q.op){
   case TLK_OP_UNLOCK:flags&=~TLK_F_LOCKED;wrong=0;break;
   case TLK_OP_LOCK_NOW:flags|=TLK_F_LOCKED;break;
   case TLK_OP_SET_PIN:flags|=TLK_F_ENABLED;wrong=0;break;
   case TLK_OP_SET_TIME:fold=q.fold_min;idle=q.idle_min;break;
   case TLK_OP_DISABLE:flags&=~(TLK_F_ENABLED|TLK_F_LOCKED);break;
   case TLK_OP_ACK_FAILURES:unacked=0;break;
   case TLK_OP_MOTION_ON:r=TLK_R_REFUSED;break;   /* as milestone 2 firmware answers */
  }
  TLKReply reply={.request=q.request,.client=q.client,.op=q.op,.result=(uint8_t)r,.flags=flags,.token=q.op==TLK_OP_QUERY&&r==TLK_R_OK?session.token:0,.fold_min=fold,.idle_min=idle,.wrong=wrong,.unacked=unacked,.delay_left=wrong>=3&&(flags&TLK_F_LOCKED)?30:0};
  tlk_reply_encode(raw,&reply);tlk_carrier(wire,raw,true);
  [weak consume:@{@"eventType":@"messageReceived",@"message":@{@"deviceId":peer,@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}}];return YES;
 }];weak=link;
 NSString *suite=@"io.turboio.preview.lock";NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:suite];[defaults removePersistentDomainForName:suite];
 TIOGlassesLockUI *c=[[TIOGlassesLockUI alloc]initWithStyle:UITableViewStyleInsetGrouped];c.link=link;c.motion=[[TIOLockMotion alloc]initWithDefaults:defaults clock:^{return NSProcessInfo.processInfo.systemUptime;}];return c;
}
#endif
