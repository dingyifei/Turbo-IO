#import "A2UIProbe.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
// All state transitions run on main. Passive observation never sends a packet.
static __weak id Plugin;
static NSDictionary *Route,*Baseline,*BeforeBaseline;
static NSString *Device,*Owned,*OwnedDevice,*Note=/*i18n:id*/@"请先在官方首页保持眼镜连接，再读取仪表盘基线";
static NSTimeInterval RouteAt,BaselineAt;
static uint32_t PendingSequence;
static NSString *PendingOperation;
static BOOL Injecting,ReadRequested,TextAccepted;
static NSMutableArray *Trace;
static id Get(id o,NSString *key){@try{return [o valueForKey:key];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Get(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSString *Dir(void){NSString *p=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/A2UIProbe"];[NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];return p;}
static void Save(NSString *name,id object){NSData *d=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];NSString *p=[Dir() stringByAppendingPathComponent:name];[d writeToFile:p options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:p error:nil];}
static void Changed(NSString *event,NSDictionary *values){
    if(!Trace)Trace=[NSMutableArray new];NSMutableDictionary *r=[values mutableCopy]?:[NSMutableDictionary new];r[@"event"]=event;r[@"time"]=@(NSDate.date.timeIntervalSince1970);[Trace addObject:r];if(Trace.count>60)[Trace removeObjectAtIndex:0];
    Save(@"status.json",@{@"state":TIOText(Note),@"trace":Trace,@"hasBaseline":@(Baseline!=nil),@"ownedId":Owned?:@"",@"pendingSequence":@(PendingSequence),@"displayVerified":@NO});
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIOA2UIChanged" object:nil];
}
static void LoadOwner(void){if(Owned)return;NSDictionary *o=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[Dir() stringByAppendingPathComponent:@"owner.json"]]?:NSData.data options:0 error:nil];if(TIOA2UIUninstall(o[@"id"])&&[o[@"device"] isKindOfClass:NSString.class]){Owned=o[@"id"];OwnedDevice=o[@"device"];NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[Dir() stringByAppendingPathComponent:@"before-components.json"]]?:NSData.data options:0 error:nil];if([saved[@"device"] isEqual:OwnedDevice]&&[saved[@"id"] isEqual:Owned]&&TIOA2UIBaselinePreservesOthers(saved[@"baseline"],saved[@"baseline"],Owned))BeforeBaseline=saved[@"baseline"];} }
static BOOL CanSend(BOOL query){return TIOA2UITransportAllowed(query,Plugin&&Route&&Device.length,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,NSDate.date.timeIntervalSince1970-RouteAt,PendingSequence!=0);}
static BOOL Ready(void){return CanSend(NO);}
void TIOA2UIObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(Injecting||![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@15]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(args[@"payload"]));if(!e)return;
    NSString *device=args[@"deviceId"];if(Device&&![Device isEqual:device]){Route=nil;Baseline=nil;TextAccepted=NO;ReadRequested=NO;PendingSequence=0;Note=TIOText(@"连接目标变化，请重新读取基线");}
    Device=device;Plugin=plugin;RouteAt=NSDate.date.timeIntervalSince1970;
    NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;
    // No outgoing/incoming official content is saved by passive observation.
}
static BOOL Send(NSDictionary *json,NSString *operation){
    if(![operation isEqual:@"query"]&&(!OwnedDevice||![OwnedDevice isEqual:Device])){Note=TIOText(@"未发送：测试卡所属眼镜与当前连接不一致");Changed(@"device_mismatch",@{});return NO;}
    if(!CanSend([operation isEqual:@"query"])||!json){Note=TIOText(@"未发送：先回官方首页建立连接；写入前须刷新基线，且上次请求不能仍在等待");Changed(@"not_sent",@{});return NO;}
    if(![operation isEqual:@"query"]&&(!Baseline||NSDate.date.timeIntervalSince1970-BaselineAt>=120)){Note=TIOText(@"未发送：确认期间基线已过期，请重新读取基线");Changed(@"stale_baseline",@{});return NO;}
    uint32_t seq=arc4random_uniform(0x3fffffff)+0x40000000;
    NSData *packet=TIOA2UIPacket(18,seq,json);Class typed=NSClassFromString(@"FlutterStandardTypedData"),callClass=NSClassFromString(@"FlutterMethodCall");SEL typedSEL=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(!packet||![typed respondsToSelector:typedSEL]||![callClass respondsToSelector:make]||![Plugin respondsToSelector:handle]){Note=TIOText(@"未发送：当前宿主缺少预期通信接口或测试包无效");Changed(@"host_unavailable",@{});return NO;}
    if(![operation isEqual:@"query"]&&![operation isEqual:@"uninstall"]&&!BeforeBaseline){
        if(!TIOA2UIBaselinePreservesOthers(Baseline,Baseline,Owned)){Note=TIOText(@"未发送：基线结构无法安全核对");Changed(@"invalid_baseline",@{});return NO;}
        BeforeBaseline=Baseline;Save(@"before-components.json",@{@"device":Device,@"id":Owned,@"baseline":BeforeBaseline});
    }
    NSMutableDictionary *args=[Route mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,typedSEL,packet);args[@"businessId"]=@15;
    id call=((id(*)(id,SEL,id,id))objc_msgSend)(callClass,make,@"rayneonet_sendMessage",args);
    PendingSequence=seq;PendingOperation=operation;Note=TIOText(@"已提交测试包，等待匹配序号的眼镜回执；尚不代表显示");
    Save([NSString stringWithFormat:@"request-%u.json",seq],@{@"businessId":@15,@"type":@18,@"sequence":@(seq),@"json":json});Changed(@"submit",@{@"sequence":@(seq),@"operation":operation,@"bytes":@(packet.length)});
    Injecting=YES;@try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,[^(id result){dispatch_async(dispatch_get_main_queue(),^{BOOL success=[result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@YES];Changed(@"transport_callback",@{@"sequence":@(seq),@"successField":@(success),@"resultClass":NSStringFromClass([result class])?:@"nil"});});} copy]);}@catch(NSException *e){PendingSequence=0;ReadRequested=NO;Note=TIOText(@"发送调用抛出异常；不要重复安装，请先读取配置核对");Changed(@"exception",@{});}Injecting=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(PendingSequence==seq){PendingSequence=0;ReadRequested=NO;Note=TIOText(@"20秒未收到匹配回执，结果未知；不自动重传。先刷新基线，再决定清理");Changed(@"timeout",@{@"sequence":@(seq)});}});return YES;
}
void TIOA2UIObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;NSDictionary *m=event[@"message"];
    if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"deviceId"] isEqual:Device])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(m[@"payload"]));if(![e[@"type"] isEqual:@19])return;NSDictionary *j=e[@"json"];
    if(ReadRequested&&[j[@"cmd"] isEqual:@"dashboard_config"]){
        id payload=j[@"payload"];id body=[payload isKindOfClass:NSDictionary.class]?payload[@"data"]:nil;if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if([body isKindOfClass:NSDictionary.class]&&[body[@"widgets_v2"] isKindOfClass:NSArray.class]){Baseline=body;BaselineAt=NSDate.date.timeIntervalSince1970;RouteAt=BaselineAt;ReadRequested=NO;PendingSequence=0;Save(@"dashboard-baseline.json",body);BOOL found=NO;for(id row in body[@"widgets_v2"])if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:Owned])found=YES;
            Note=found?TIOText(@"配置包含测试卡。请在眼镜仪表盘滚动查看；尚需镜片验收"):TIOText(@"仪表盘基线已保存，可安装独立文字测试卡");
            if(BeforeBaseline&&[OwnedDevice isEqual:Device]){
                BOOL preserved=TIOA2UIBaselinePreservesOthers(BeforeBaseline,body,Owned);
                Note=[TIOText(Note) stringByAppendingString:preserved?TIOText(@"；其他卡片配置与测试前一致"):TIOText(@"；警告：其他卡片配置发生变化，请检查，不自动覆盖恢复")];
                Changed(@"other_widgets_check",@{@"preserved":@(preserved),@"containsOwned":@(found)});
            }
            Changed(@"config_snapshot",@{@"count":@([body[@"widgets_v2"] count]),@"containsOwned":@(found)});}return;
    }
    uint32_t seq=[e[@"sequence"] unsignedIntValue];if(!PendingSequence||seq!=PendingSequence||[PendingOperation isEqual:@"query"])return;
    // Management response is {code,err_msg,data}, not legacy {cmd,payload.value}.
    if(![j[@"code"] isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)j[@"code"])==CFBooleanGetTypeID())return;
    Save([NSString stringWithFormat:@"response-%u.json",seq],e);NSInteger code=[j[@"code"] integerValue];
    if(code==0){if([PendingOperation isEqual:@"uninstall"])TextAccepted=NO;else if([PendingOperation isEqual:@"text"]||[PendingOperation isEqual:@"layout"])TextAccepted=YES;Note=[PendingOperation isEqual:@"uninstall"]?TIOText(@"眼镜确认卸载成功，请读取基线核对测试卡已移除"):TIOText(@"眼镜返回 code=0；请到仪表盘查看测试内容，不等同已显示");}
    else Note=[NSString stringWithFormat:TIOText(@"眼镜拒绝：code=%ld，%@。未自动重试"),(long)code,[j[@"err_msg"] isKindOfClass:NSString.class]?j[@"err_msg"]:TIOText(@"无错误说明")];
    PendingSequence=0;Changed(@"device_response",@{@"sequence":@(seq),@"code":@(code),@"operation":PendingOperation?:@""});
}
@interface TIOA2UIPanel:UITableViewController @end
@implementation TIOA2UIPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"hub.row.a2ui");LoadOwner();[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOA2UIChanged" object:nil];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return 9;}
- (NSString *)tableView:(UITableView *)v titleForFooterInSection:(NSInteger)s{return TIOText(@"仅新增/卸载本工具拥有的测试卡，不发送全量看板覆盖，不启用刷新订阅或传感器，不改固件。安装回执 ≠ 镜片可见。退出页面不会删除测试卡，可回来手动卸载。");}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=@[TIOText(@"当前状态 · COMPONENTS 01"),TIOText(@"1 · 读取仪表盘基线"),TIOText(@"2 · 安装文字卡 7392"),TIOText(@"3 · 更新排版卡 8642"),TIOText(@"4 · 卸载本次测试卡"),TIOText(@"5 · 柱状图 6111"),TIOText(@"6 · 折线图 6222"),TIOText(@"7 · 单子项容器 6333"),TIOText(@"8 · 三行列表 6444")][p.row];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;if(p.row==0)c.detailTextLabel.text=[NSString stringWithFormat:TIOText(@"%@\n官方发送上下文：%@"),TIOText(Note),Ready()?TIOText(@"可用"):TIOText(@"等待官方首页通信")];if(p.row==2)c.detailTextLabel.text=TIOText(@"单行文字，验证动态组件入口");if(p.row==3)c.detailTextLabel.text=TIOText(@"仅在你看见7392后测试：标题、分隔线、图标、横竖排");if(p.row>=5)c.detailTextLabel.text=TIOText(@"静态格式已核对，镜片未验。替换同一张测试卡；先读基线，一次只测一项。");c.accessibilityIdentifier=[NSString stringWithFormat:@"a2ui-probe-%ld",(long)p.row];return c;}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(p.row==0){[self refresh];return;}if(p.row==1){if(PendingSequence){Note=TIOText(@"上一次请求仍在等待回执，最多20秒；不重复发送");[self refresh];return;}ReadRequested=YES;if(!Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},@"query"))ReadRequested=NO;return;}
    LoadOwner();if(!Ready()||PendingSequence){Note=TIOText(@"请回官方首页确认连接，再读取基线");[self refresh];return;}
    if(OwnedDevice&&![OwnedDevice isEqual:Device]){Note=TIOText(@"测试卡属于另一副眼镜，拒绝跨设备操作");[self refresh];return;}
    if(p.row!=4){if(!Baseline||NSDate.date.timeIntervalSince1970-BaselineAt>=120){Note=TIOText(@"先读取最新仪表盘基线（两分钟内）");[self refresh];return;}if(p.row!=2&&!TextAccepted){Note=TIOText(@"先完成文字卡安装和镜片确认");[self refresh];return;}
        if(!Owned){Owned=[@"turbo_ui_" stringByAppendingString:[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""]];OwnedDevice=Device;Save(@"owner.json",@{@"id":Owned,@"device":Device});}
    }else if(!Owned){Note=TIOText(@"没有本工具创建的测试卡，不执行卸载");[self refresh];return;}
    NSString *operation=@[@"",@"query",@"text",@"layout",@"uninstall",@"bar",@"line",@"card",@"list"][p.row];
    TIOConfirm(self,p.row==4?TIOText(@"common.editor.a2uiUninstallTitle"):p.row==2?TIOText(@"common.editor.a2uiAddTitle"):TIOText(@"common.editor.a2uiContinueTitle"),TIOText(@"common.editor.a2uiPrompt"),TIOText(@"common.editor.a2uiAction"),NO,^{Send([operation isEqual:@"uninstall"]?TIOA2UIUninstall(Owned):TIOA2UIFixtureInstall(Owned,operation),operation);});
}
@end
UIViewController *TIOA2UIController(void){return [[TIOA2UIPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
