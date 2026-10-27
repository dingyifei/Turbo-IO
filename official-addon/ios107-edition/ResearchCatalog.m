#import "ResearchCatalog.h"
#import "TIOLanguage.h"
#if TIO_MAPKIT_ENABLED
static NSString *const NavigationTitle=@"Navigation (Apple Maps)",*const NavigationName=@"Navigation";
#else
static NSString *const NavigationTitle=@"Navigation (MapKit build only)",*const NavigationName=@"Navigation";
#endif
static NSDictionary *Row(NSString *key,NSString *title,NSString *icon,NSInteger section,NSInteger row){return @{@"key":key,@"title":title,@"icon":icon,@"section":@(section),@"row":@(row)};}
NSArray<NSDictionary *> *LegacySections(NSString *page){
    if([page isEqual:@"model"])return @[
        @{@"title":TIOText(@"实时字幕与翻译 · 本机验收"),@"rows":@[Row(@"localTranslation",TIOText(@"Apple / Hy-MT2 本地翻译"),@"character.bubble",-2,22)]},
        @{@"title":TIOText(@"自定义 Agents 控制"),@"rows":@[Row(@"agent",TIOText(@"执行 Agent"),@"cpu",-2,0),Row(@"knowledge",TIOText(@"知识库与来源"),@"books.vertical",-2,1)]},
        @{@"title":TIOText(@"回答方式"),@"rows":@[Row(@"mode",TIOText(@"当前回答方式"),@"square.stack.3d.up",0,0),Row(@"uiLanguage",TIOText(@"界面语言"),@"globe",-2,40)]},
        @{@"title":TIOText(@"自有模型"),@"rows":@[Row(@"api",TIOText(@"接口与密钥"),@"cube",0,1),Row(@"thinking",TIOText(@"关闭深度思考"),@"bolt",0,3)]},
        @{@"title":TIOText(@"眼镜语音播报 · 实验"),@"rows":@[Row(@"tts",TIOText(@"回答同步朗读"),@"waveform.circle",-2,13),Row(@"ttsTest",TIOText(@"播放测试语音"),@"play.circle",-2,15)]},
        @{@"title":TIOText(@"联网与工具"),@"rows":@[Row(@"search",TIOText(@"允许联网搜索"),@"globe",0,7),Row(@"searchKey",TIOText(@"搜索服务配置"),@"key",0,8),Row(@"tools",TIOText(@"模型可用工具"),@"wrench.and.screwdriver",0,11)]},
        @{@"title":TIOText(@"语音与上下文"),@"rows":@[Row(@"exit",TIOText(@"语音退出"),@"waveform",0,6),Row(@"prompt",TIOText(@"系统提示词"),@"text.bubble",0,5),Row(@"aboutMe",@"关于我" /*i18n:keep*/,@"person.text.rectangle",-2,31),Row(@"history",TIOText(@"本次对话上下文"),@"clock.arrow.circlepath",0,4)]}];
    if([page isEqual:@"library"])return @[

        @{@"title":TIOText(@"遥控拍照"),@"rows":@[Row(@"camera",TIOText(@"遥控拍照 · TCM1"),@"camera",-2,29)]},
        @{@"title":TIOText(@"music.title"),@"rows":@[Row(@"music",TIOText(@"music.catalog.row"),@"music.note",-2,20)]},
        @{@"title":TIOText(@"录音与整理"),@"rows":@[Row(@"recordings",TIOText(@"录音与文件分享"),@"waveform",-1,0),Row(@"summary",TIOText(@"转写文字整理"),@"text.badge.star",-1,1)]},
        @{@"title":TIOText(@"全天智记"),@"rows":@[Row(@"lifelogText",TIOText(@"已保存文字"),@"doc.text",-1,2),Row(@"lifelogAudio",TIOText(@"音频保存与分享"),@"waveform.circle",-1,3),Row(@"capture",TIOText(@"保存之后的最终文字"),@"square.and.arrow.down",1,0),Row(@"archive",TIOText(@"导出文字归档"),@"square.and.arrow.up",1,1)]},
        @{@"title":TIOText(@"出行"),@"rows":@[Row(@"navigation",NavigationTitle,@"location.north.line",-2,4)]}];
    if([page isEqual:@"diagnostics"])return @[
        @{@"title":TIOText(@"开发者诊断"),@"rows":@[Row(@"diagnosticsRuntime",TIOText(@"眼镜运行状态 · TDG1"),@"gauge.with.dots.needle.67percent",-2,21)]},
        @{@"title":TIOText(@"导航显示实验"),@"rows":@[Row(@"subtitleHUD",TIOText(@"字幕导航 · 常亮与换文"),@"text.bubble",-2,5)]},
        @{@"title":TIOText(@"运行状态"),@"rows":@[Row(@"status",TIOText(@"适配与回调"),@"checkmark.shield",2,0),Row(@"glassesLog",TIOText(@"眼镜日志 · 仅本机"),@"doc.text.magnifyingglass",-2,3),Row(@"languageStatus",TIOText(@"语言与眼镜标签"),@"character.bubble",-2,41)]},
        @{@"title":TIOText(@"手动测试"),@"rows":@[Row(@"developerApps",TIOText(@"我的应用 · SDK"),@"square.stack.3d.up",-2,26),Row(@"dashboardEditor",TIOText(@"我的仪表盘 · 可视化编辑"),@"rectangle.3.group",-2,25),Row(@"dashboardCard",TIOText(@"开发者仪表盘 · TDC1"),@"chart.bar.xaxis",-2,24),Row(@"a2ui",TIOText(@"自定义 UI 真机验收"),@"rectangle.3.group",-2,2),Row(@"apiTest",TIOText(@"测试模型接口"),@"bubble.left.and.bubble.right",0,2),Row(@"searchTest",TIOText(@"测试联网搜索"),@"globe",0,9),Row(@"todoTest",TIOText(@"待办协议验收"),@"checklist",0,10)]},
        @{@"title":TIOText(@"固件研究"),@"rows":@[
#if TIO_DISPLAY_PHONE
        Row(@"displayPhone",TIOText(@"灵活显示 · PHONE 06"),@"rectangle.connected.to.line.below",-2,8),
#endif
#if TIO_IMAGE_RX_LAB
        Row(@"imageRXLab",TIOText(@"N8W 单张传图 · FIX 01"),@"photo",-2,7),
#endif
#if TIO_DISPLAY_FLASH
        Row(@"experimentalOTA",TIOText(@"TMG2 · 可选排数菜单 · 默认锁定"),@"shippingbox",-2,6)]}];
#else
        Row(@"experimentalOTA",TIOText(@"实验固件 · 仅校验"),@"shippingbox",-2,6)]}];
#endif
    return @[];
}

NSArray<NSDictionary *> *TIOResearchSections(NSString *page){
 NSMutableDictionary *lookup=[NSMutableDictionary new];for(NSString *p in @[@"model",@"library",@"diagnostics"])for(NSDictionary *section in LegacySections(p))for(NSDictionary *r in section[@"rows"])lookup[r[@"key"]]=r;
 NSArray *groups=nil;
 if([page isEqual:@"model"])groups=@[@[TIOText(@"日常对话"),@"mode",@"uiLanguage",@"tts",@"search"],@[TIOText(@"模型与接口"),@"api",@"thinking"],@[TIOText(@"语音设置"),@"ttsTest",@"exit"],@[TIOText(@"Agent 与工具"),@"agent",@"knowledge",@"tools",@"searchKey"],@[TIOText(@"提示词与记忆"),@"prompt",@"aboutMe",@"history"]];
 if([page isEqual:@"library"])groups=@[@[TIOText(@"遥控拍照"),@"camera"],@[TIOText(@"随身应用"),@"music",@"navigation",@"localTranslation",@"recordings"],@[TIOText(@"文字整理"),@"summary"],@[TIOText(@"全天智记"),@"lifelogText",@"lifelogAudio",@"capture",@"archive"]];
 if([page isEqual:@"diagnostics"])groups=@[@[TIOText(@"运行与日志"),@"diagnosticsRuntime",@"glassesLog",@"status",@"languageStatus"],@[TIOText(@"协议实验"),@"subtitleHUD",@"dashboardCard",@"a2ui",@"apiTest",@"searchTest",@"todoTest"],@[TIOText(@"显示实验"),@"displayPhone",@"imageRXLab"],@[TIOText(@"实验固件 · 有风险"),@"experimentalOTA"]];
 if([page isEqual:@"homeTools"])groups=@[@[TIOText(@"首页工具"),@"dashboardEditor",@"developerApps"]];
 if(!groups)return @[];NSMutableArray *sections=[NSMutableArray new];NSDictionary *names=@{@"dashboardEditor":TIOText(@"仪表盘"),@"developerApps":TIOText(@"应用广场"),@"music":TIOText(@"music.title"),@"navigation":NavigationName,@"localTranslation":TIOText(@"本地翻译与字幕"),@"recordings":TIOText(@"录音与分享")};
 for(NSArray *group in groups){NSMutableArray *rows=[NSMutableArray new];for(NSUInteger i=1;i<group.count;i++){NSDictionary *r=lookup[group[i]];if(r){NSMutableDictionary *m=[r mutableCopy];if(names[group[i]])m[@"title"]=names[group[i]];[rows addObject:m];}}if(rows.count)[sections addObject:@{@"title":group[0],@"rows":rows}];}return sections;
}
