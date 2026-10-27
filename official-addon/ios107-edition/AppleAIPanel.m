#if TIO_APPLE_AI
#import "AppleAI.h"
#import "AppleAICore.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
@interface TIOApplePanel:UITableViewController
@property(nonatomic) NSDictionary *report;
@property(nonatomic) NSArray<NSString *> *keys;
@end
@implementation TIOApplePanel
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){self.title=TIOText(@"apple.title");_report=@{};_keys=@[];}return self;}
- (void)viewDidLoad{[super viewDidLoad];[self probe];}
- (void)probe{__weak typeof(self) weak=self;TIOAppleAIProbe(^(NSDictionary *report){typeof(self) s=weak;if(!s)return;s.report=report;s.keys=[[report allKeys] sortedArrayUsingSelector:@selector(compare:)];[s.tableView reloadData];});}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return section==0?_keys.count:2;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section{return TIOText(section==0?@"apple.section.status":@"apple.section.actions");}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{return section==1?TIOText(@"apple.requirements"):nil;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;if(path.section==0){NSString *key=_keys[path.row];cell.textLabel.text=key;id value=_report[key];cell.detailTextLabel.text=[key isEqual:@"fm.reason"]?TIOAppleErrorMessage(value):[value description];}else cell.textLabel.text=TIOText(path.row==0?@"apple.action.probe":@"apple.action.copy");return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];if(path.section!=1)return;if(path.row==0){[self probe];return;}NSData *json=[NSJSONSerialization dataWithJSONObject:_report options:NSJSONWritingPrettyPrinted error:NULL];if(json)UIPasteboard.generalPasteboard.string=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];}
@end
UIViewController *TIOAppleAIController(void){return [TIOApplePanel new];}
#endif
