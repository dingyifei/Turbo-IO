#if TIO_APPLE_AI
#import "AppleAI.h"
#import "AppleAICore.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
#import <objc/message.h>
@interface TIOApplePanel:UITableViewController
@property(nonatomic) NSDictionary *report;
@property(nonatomic) NSArray<NSString *> *keys;
@property(nonatomic) id modelTask;
@end
@implementation TIOApplePanel
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){self.title=TIOText(@"apple.title");_report=@{};_keys=@[];}return self;}
- (void)viewDidLoad{[super viewDidLoad];[self probe];}
- (void)probe{__weak typeof(self) weak=self;TIOAppleAIProbe(^(NSDictionary *report){typeof(self) s=weak;if(!s)return;s.report=report;s.keys=[[report allKeys] sortedArrayUsingSelector:@selector(compare:)];[s.tableView reloadData];});}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return section==0?_keys.count:6;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section{return TIOText(section==0?@"apple.section.status":@"apple.section.actions");}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{return section==1?[NSString stringWithFormat:@"%@\n%@",TIOText(@"apple.requirements"),TIOText(@"apple.fallback.detail")]:nil;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;if(path.section==0){NSString *key=_keys[path.row];cell.textLabel.text=key;id value=_report[key];cell.detailTextLabel.text=[key isEqual:@"fm.reason"]?TIOAppleErrorMessage(value):[value description];}else {cell.textLabel.text=TIOText(path.row==0?@"apple.action.probe":path.row==1?@"apple.action.copy":path.row==2?@"apple.fallback.title":path.row==3?@"apple.action.test":path.row==4?@"apple.speech.en":@"apple.speech.zh");if(path.row>=4)cell.detailTextLabel.text=TIOText([_report[path.row==4?@"speech.enInstalled":@"speech.zhInstalled"] boolValue]?@"apple.status.ready":@"apple.speech.prepare");if(path.row==2){UISwitch *toggle=[UISwitch new];toggle.on=[[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"] boolForKey:@"appleFallback"];[toggle addTarget:self action:@selector(fallbackChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}}return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];if(path.section!=1)return;if(path.row==0){[self probe];return;}if(path.row==2)return;if(path.row>=4){NSString *locale=path.row==4?@"en-US":@"zh-CN";__weak typeof(self) weak=self;TIOAppleSpeechPrepare(locale,^(double fraction){typeof(self) s=weak;s.title=[NSString stringWithFormat:@"%@ %.0f%%",TIOText(@"apple.speech.prepare"),fraction*100];},^(NSString *code){typeof(self) s=weak;if(!s)return;s.title=TIOText(@"apple.title");if(code)TIONotice(s,TIOText(@"apple.speech.prepare"),TIOAppleErrorMessage(code));[s probe];});return;}if(path.row==3){__weak typeof(self) weak=self;self.modelTask=TIOAppleModelRespond(@"Reply with one short sentence confirming the on-device model works.",@[],TIOAppleInstructions(@"en",nil),@"en",YES,^(NSString *text,BOOL done,NSString *code){typeof(self) s=weak;if(s&&done){s.modelTask=nil;TIONotice(s,TIOText(@"apple.action.test"),code?TIOAppleErrorMessage(code):text);}});if(!self.modelTask)TIONotice(self,TIOText(@"apple.model.unavailable"),TIOAppleErrorMessage(TIOAppleModelAvailability()[@"reason"]));return;}NSData *json=[NSJSONSerialization dataWithJSONObject:_report options:NSJSONWritingPrettyPrinted error:NULL];if(json)UIPasteboard.generalPasteboard.string=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];}
- (void)fallbackChanged:(UISwitch *)sender {[[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"] setBool:sender.on forKey:@"appleFallback"];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];SEL cancel=NSSelectorFromString(@"cancel");if([self.modelTask respondsToSelector:cancel])((void(*)(id,SEL))objc_msgSend)(self.modelTask,cancel);self.modelTask=nil;}
@end
UIViewController *TIOAppleAIController(void){return [TIOApplePanel new];}
#endif
