#if TIO_APPLE_AI
#import "AppleAI.h"
#import "AppleAICore.h"
#import "NoNetworkTurn.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
#import "TIODesign.h"
#import <objc/message.h>
@interface TIOApplePanel:UITableViewController
@property(nonatomic) NSDictionary *report;
@property(nonatomic) NSArray<NSString *> *keys;
@property(nonatomic) id modelTask;
@property(nonatomic,copy) NSString *timelineText;
@end
@implementation TIOApplePanel
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){self.title=TIOText(@"apple.title");_report=@{};_keys=@[];}return self;}
- (void)viewDidLoad{[super viewDidLoad];self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;[self probe];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];self.title=TIOText(@"apple.title");[self.tableView reloadData];}
- (void)probe{__weak typeof(self) weak=self;TIOAppleAIProbe(^(NSDictionary *report){typeof(self) s=weak;if(!s)return;s.report=report;s.keys=[[report allKeys] sortedArrayUsingSelector:@selector(compare:)];[s.tableView reloadData];});}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 4;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return section==0?_keys.count:section==1?6:section==2?2:3;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section{if(section==2)return TAIText(@"When the phone has no network",/*i18n:keep*/@"手机没有网络时");if(section==3)return TAIText(@"Developer",/*i18n:keep*/@"开发者");return TIOText(section==0?@"apple.section.status":@"apple.section.actions");}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{if(section==2)return TAIText(@"Needs the RayNeo app open on the phone. Locked-phone speech recognition may not run.",/*i18n:keep*/@"需要在手机上打开 RayNeo 应用。锁屏时语音识别可能无法运行。");if(section==3)return TAIText(@"Experimental switches are off by default.",/*i18n:keep*/@"实验开关默认关闭。");return section==1?[NSString stringWithFormat:@"%@\n%@",TIOText(@"apple.requirements"),TIOText(@"apple.fallback.detail")]:nil;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{if(path.section>=2)return [self noNetworkCell:path];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;if(path.section==0){NSString *key=_keys[path.row];cell.textLabel.text=key;id value=_report[key];if([key isEqual:@"fm.reason"])cell.detailTextLabel.text=[value isEqual:@"available"]?TIOText(@"apple.status.ready"):TIOAppleErrorMessage(value);
else if([key hasPrefix:@"translate."]&&[value isKindOfClass:NSString.class])cell.detailTextLabel.text=TIOText([@"apple.assets." stringByAppendingString:value]);
else if(CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())cell.detailTextLabel.text=TIOText([value boolValue]?@"apple.status.yes":@"apple.status.no");
else cell.detailTextLabel.text=[value description];}else {cell.textLabel.text=TIOText(path.row==0?@"apple.action.probe":path.row==1?@"apple.action.copy":path.row==2?@"apple.fallback.title":path.row==3?@"apple.action.test":path.row==4?@"apple.speech.en":@"apple.speech.zh");if(path.row>=4)cell.detailTextLabel.text=TIOText([_report[path.row==4?@"speech.enInstalled":@"speech.zhInstalled"] boolValue]?@"apple.status.ready":@"apple.speech.prepare");if(path.row==2){UISwitch *toggle=[UISwitch new];toggle.on=[[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"] boolForKey:@"appleFallback"];[toggle addTarget:self action:@selector(fallbackChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}}return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];if(path.section==3&&path.row==0){[self showNoNetworkTimeline];return;}if(path.section!=1)return;if(path.row==0){[self probe];return;}if(path.row==2)return;if(path.row>=4){NSString *locale=path.row==4?@"en-US":@"zh-CN";__weak typeof(self) weak=self;TIOAppleSpeechPrepare(locale,^(double fraction){typeof(self) s=weak;s.title=[NSString stringWithFormat:@"%@ %.0f%%",TIOText(@"apple.speech.prepare"),fraction*100];},^(NSString *code){typeof(self) s=weak;if(!s)return;s.title=TIOText(@"apple.title");if(code)TIONotice(s,TIOText(@"apple.speech.prepare"),TIOAppleErrorMessage(code));[s probe];});return;}if(path.row==3){__weak typeof(self) weak=self;self.modelTask=TIOAppleModelRespond(@"Reply with one short sentence confirming the on-device model works.",@[],TIOAppleInstructions(@"en",nil),@"en",YES,^(NSString *text,BOOL done,NSString *code){typeof(self) s=weak;if(s&&done){s.modelTask=nil;TIONotice(s,TIOText(@"apple.action.test"),code?TIOAppleErrorMessage(code):text);}});if(!self.modelTask)TIONotice(self,TIOText(@"apple.model.unavailable"),TIOAppleErrorMessage(TIOAppleModelAvailability()[@"reason"]));return;}NSData *json=[NSJSONSerialization dataWithJSONObject:_report options:NSJSONWritingPrettyPrinted error:NULL];if(json)UIPasteboard.generalPasteboard.string=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];}
- (void)fallbackChanged:(UISwitch *)sender {[[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"] setBool:sender.on forKey:@"appleFallback"];[self.tableView reloadData];}
- (NSUserDefaults *)settings {return [[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];}
- (UITableViewCell *)noNetworkCell:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    NSUserDefaults *prefs=self.settings;
    if(path.section==2&&path.row==0){
        cell.textLabel.text=TAIText(@"No-network answers",/*i18n:keep*/@"无网络回答");
        if(TIONoNetworkFailedOpen())cell.detailTextLabel.text=TAIText(@"Off: callback queue overflow; relaunch RayNeo",/*i18n:keep*/@"已关闭：回调队列溢出，请重新启动 RayNeo");
        else cell.detailTextLabel.text=TIONoNetworkModeEligible([prefs integerForKey:@"mode"],[prefs boolForKey:@"appleFallback"])?TAIText(@"On",/*i18n:keep*/@"已开启"):TAIText(@"Off: choose Apple on-device or endpoint with fallback",/*i18n:keep*/@"已关闭：请选择 Apple 本机模型或开启回退的接口");
    }else if(path.section==2){
        cell.textLabel.text=TAIText(@"Wait for the official reply",/*i18n:keep*/@"等待官方回复");
        id value=[prefs objectForKey:@"noNetworkTimeout"];
        double seconds=TIONoNetworkDelay(YES,YES,[value isKindOfClass:NSNumber.class]?value:nil);
        cell.detailTextLabel.text=[NSString stringWithFormat:TAIText(@"%.0f s",/*i18n:keep*/@"%.0f 秒"),seconds];
        UIStepper *stepper=[UIStepper new];stepper.minimumValue=3;stepper.maximumValue=15;stepper.stepValue=1;stepper.value=seconds;stepper.accessibilityLabel=cell.textLabel.text;stepper.accessibilityValue=cell.detailTextLabel.text;
        [stepper addTarget:self action:@selector(noNetworkTimeoutChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=stepper;
    }else if(path.row==0){
        cell.textLabel.text=TAIText(@"No-network timeline",/*i18n:keep*/@"无网络时间线");
        cell.detailTextLabel.text=TAIText(@"64 metadata events; no question or answer text",/*i18n:keep*/@"最多 64 条元数据事件，不含问题或回答文本");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }else{
        BOOL foreground=path.row==1;
        cell.textLabel.text=foreground?TAIText(@"Keep listening in background (experimental, next launch)",/*i18n:keep*/@"在后台继续监听（实验性，下次启动生效）"):TAIText(@"Stop the official workflow after the answer (experimental)",/*i18n:keep*/@"回答后停止官方工作流（实验性）");
        UISwitch *toggle=[UISwitch new];toggle.tag=path.row;toggle.on=[prefs boolForKey:foreground?@"noNetworkForceForeground":@"noNetworkStopHost"];
        toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(noNetworkExperimentalChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }
    return cell;
}
- (void)noNetworkTimeoutChanged:(UIStepper *)sender {[self.settings setDouble:sender.value forKey:@"noNetworkTimeout"];[self.tableView reloadData];}
- (void)noNetworkExperimentalChanged:(UISwitch *)sender {[self.settings setBool:sender.on forKey:sender.tag==1?@"noNetworkForceForeground":@"noNetworkStopHost"];}
- (void)showNoNetworkTimeline {
    NSData *json=[NSJSONSerialization dataWithJSONObject:TIONoNetworkTimeline() options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    self.timelineText=[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]?:@"[]";
    UIViewController *page=[UIViewController new];page.title=TAIText(@"No-network timeline",/*i18n:keep*/@"无网络时间线");
    UITextView *text=[[UITextView alloc]initWithFrame:page.view.bounds];text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;text.editable=NO;text.font=TIODesignMonospacedDigitFont(TIODesignTextStyleCaption);text.adjustsFontForContentSizeCategory=YES;text.textColor=TIODesignColor(TIODesignColorLabel);text.textContainerInset=UIEdgeInsetsMake(16,16,16,16);text.text=self.timelineText;text.backgroundColor=TIODesignColor(TIODesignColorBg);[page.view addSubview:text];
    page.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:TAIText(@"Copy",/*i18n:keep*/@"复制") style:UIBarButtonItemStylePlain target:self action:@selector(copyNoNetworkTimeline)];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)copyNoNetworkTimeline {UIPasteboard.generalPasteboard.string=self.timelineText?:@"[]";}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];SEL cancel=NSSelectorFromString(@"cancel");if([self.modelTask respondsToSelector:cancel])((void(*)(id,SEL))objc_msgSend)(self.modelTask,cancel);self.modelTask=nil;}
@end
UIViewController *TIOAppleAIController(void){return [TIOApplePanel new];}
#endif
