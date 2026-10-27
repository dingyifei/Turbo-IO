#import "Brightness.h"
#import "TIOLanguage.h"
#import "ResearchUI.h"
/* No brightness, LifeLog, or other device-setting writes. */
void TIOBrightnessObserveEvent(NSDictionary *event) {}
@interface TIOCoexistInfo:UITableViewController @end
@implementation TIOCoexistInfo
- (void)viewDidLoad {
    [super viewDidLoad];self.title=TIOText(@"hub.row.brightness");TIOStyleResearchTable(self);
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=100;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 2;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);
    c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;c.selectionStyle=UITableViewCellSelectionStyleNone;
    if(p.row==0){c.textLabel.text=TIOText(@"亮度实验仍暂停");c.detailTextLabel.text=TIOText(@"本版不包含 TBL1 亮度锁定和平滑补丁，保留 TGR1 的原厂亮度与抬头逻辑。不会更改你当前的设置。");}
    else{c.textLabel.text=TIOText(@"范围与限制");c.detailTextLabel.text=TIOText(@"音乐、读书、番茄、导航、滴滴和小应用不再仅因后台智记开关开启而被拒绝。前台应用占用和助手活动检查仍保留；真实采集、音频资源与唤醒共存需要实机验证。不是纯原厂固件；刷写可能失败，不保证救砖。");}
    return c;
}
@end
UIViewController *TIOBrightnessController(void){return [[TIOCoexistInfo alloc]initWithStyle:UITableViewStyleInsetGrouped];}
