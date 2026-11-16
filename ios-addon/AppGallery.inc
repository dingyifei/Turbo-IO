// User-server recipes. All bundled packages are explicit offline examples.
static NSArray *GalleryItems(void){static NSArray *items;static dispatch_once_t once;dispatch_once(&once,^{NSString *p=[NSBundle.mainBundle pathForResource:@"catalog" ofType:@"json" inDirectory:@"TurboIOGallery"];NSDictionary *d=p?[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:p] options:0 error:nil]:nil;items=[d[@"entries"] isKindOfClass:NSArray.class]?d[@"entries"]:@[];});return items;}
static NSData *GalleryBytes(NSDictionary *item){NSString *p=[NSBundle.mainBundle pathForResource:item[@"resource"] ofType:@"zip" inDirectory:@"TurboIOGallery"];if(!p)return nil;NSFileHandle *f=[NSFileHandle fileHandleForReadingAtPath:p];NSData *data=[f readDataUpToLength:24577 error:nil];[f closeAndReturnError:nil];return data;}
static NSDictionary *GalleryPackage(NSDictionary *item,NSString **error){NSDictionary *p=TAPReadPackage(GalleryBytes(item),error);if(p&&![p[@"zipSHA256"]isEqual:item[@"sha256"]]){if(error)*error=TIOText(@"目录校验值不匹配，未加载应用。");return nil;}return p;}
static NSString *DeveloperPrompt(void){return TIOText(@"请使用 Turbo IO 的 turboio-developer Skill，阅读 https://github.com/Turbo1123/Turbo-IO/blob/main/docs/DEVELOPER_ECOSYSTEM.md 。在我的 Server 连接我授权的 MCP，只读获取我选择的数据，密钥留在 Server。仪表盘使用 TCE1 API 的草稿/发布/手机批准；小应用使用 TAP1 540×180 原生组件、20KiB 解压预算、最多4页，生成 ZIP 并校验/预览。先离线演示，再接真实数据；不要假装联网、自动安装、刷机或执行付款等写操作。交付源码、ZIP、SHA256、测试、部署配置和手机导入步骤。App v1 是数据快照包，自动刷新和按钮后端回流尚未接入。");}
static void CopyPrompt(UIViewController *vc,NSString *text){UIPasteboard.generalPasteboard.string=text;Notice(vc,TIOText(@"已复制。粘贴给你的 Agent，按提示连接自己的 Server。密钥无需填进提示词。"));}
// A table header laid out with Auto Layout: fit it to the table width whenever the width or text size changes.
static void TAPFitHeader(UITableView *table){
 UIView *header=table.tableHeaderView;CGFloat width=table.bounds.size.width;if(!header||width<=0)return;
 CGSize size=[header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
 CGFloat height=ceil(size.height);
 if(fabs(header.frame.size.height-height)>.5||fabs(header.frame.size.width-width)>.5){header.frame=CGRectMake(0,0,width,height);table.tableHeaderView=header;}
}
@interface TAPRecipe:UITableViewController
@property NSDictionary *item,*package;
@end
@implementation TAPRecipe
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];TAPFitHeader(self.tableView);}
- (void)viewDidLoad{[super viewDidLoad];self.title=_item[@"name"];TIOStyleResearchTable(self);NSString *error;self.package=GalleryPackage(_item,&error);
 TAPPreview *p=[TAPPreview new];p.translatesAutoresizingMaskIntoConstraints=NO;p.document=_package[@"document"];p.layer.cornerRadius=12;p.clipsToBounds=YES;[p.heightAnchor constraintEqualToAnchor:p.widthAnchor multiplier:180.0/540].active=YES;
 p.isAccessibilityElement=YES;p.accessibilityLabel=TIOText(@"apps.recipe.preview");
 UILabel *note=[UILabel new];note.numberOfLines=0;note.font=TIODesignFont(TIODesignTextStyleCaption);note.adjustsFontForContentSizeCategory=YES;note.textColor=TIODesignColor(TIODesignColorLabelSecondary);note.text=_package?TIOText(@"可安装的离线示例 · 真实数据由你自己的 Server 提供"):(error?:TIOText(@"示例包未附带"));
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[p,note]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=TIOSpace2;stack.translatesAutoresizingMaskIntoConstraints=NO;
 UIView *header=[UIView new];[header addSubview:stack];header.layoutMargins=UIEdgeInsetsMake(TIOSpace4,TIOSpace5,TIOSpace2,TIOSpace5);
 [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:header.layoutMarginsGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:header.layoutMarginsGuide.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor]]];
 self.tableView.tableHeaderView=header;TAPFitHeader(self.tableView);}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s?3:3;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s?TIOText(@"接入你的 Server"):TIOText(@"从这个模板开始");}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s?TIOText(@"这里只引用上游项目，不附带其服务或账号。ZIP 不含 MCP、JS 执行器或密钥；快照不是自动实时更新。"):nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;if(!p.section){NSArray *names=@[TIOText(@"预览并安装示例"),TIOText(@"复制 Agent 开发提示词"),TIOText(@"导出示例 ZIP")],*icons=@[@"play.rectangle",@"doc.on.doc",@"square.and.arrow.up"];c.textLabel.text=names[p.row];c.imageView.image=[UIImage systemImageNamed:icons[p.row]];c.accessibilityIdentifier=[NSString stringWithFormat:@"recipe-action-%ld",(long)p.row];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.detailTextLabel.text=p.row==0?TIOText(@"检查内容与权限后再确认，不自动安装"):p.row==1?TIOText(@"包含来源、数据映射、限制和验收要求"):TIOText(@"可交给 Agent 修改，也可保存到文件");}else{c.textLabel.text=@[TIOText(@"只读能力"),TIOText(@"配置要求"),TIOText(@"参考项目")][(NSUInteger)p.row];c.detailTextLabel.text=@[_item[@"purpose"],_item[@"setup"],_item[@"source"]][(NSUInteger)p.row];}return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.section)return;if(p.row==1){CopyPrompt(self,_item[@"prompt"]);return;}if(!_package){Notice(self,TIOText(@"包未通过校验，无法继续。"));return;}if(p.row==0){TAPReview *v=[TAPReview new];v.package=_package;[self.navigationController pushViewController:v animated:YES];return;}
 NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"TurboGalleryExports"] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];NSURL *file=[dir URLByAppendingPathComponent:[_item[@"id"]stringByAppendingString:@".zip"]];if(![GalleryBytes(_item)writeToURL:file options:NSDataWritingAtomic error:nil]){Notice(self,TIOText(@"导出失败，未修改眼镜。"));return;}UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];share.popoverPresentationController.sourceView=self.view;share.popoverPresentationController.sourceRect=[t rectForRowAtIndexPath:p];[self presentViewController:share animated:YES completion:nil];}
@end
