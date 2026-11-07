#import <UIKit/UIKit.h>
#import "FirmwareExportUI.h"
#import "FirmwareExport.h"
#import "HostCompatibility.h"
#import "ResearchUI.h"
#import "TIOConfirm.h"
#import "TIODesign.h"
#import "TIOLanguage.h"

// Read-only: the panel lists, hashes and shares RayNeo's downloaded firmware.
// The only file it writes is a re-zipped copy in the addon's own folder.
typedef NS_ENUM(NSInteger, TIOFirmwareExportSection) {SectionStatus, SectionFound, SectionCopies, SectionRoots, SectionCount};

static NSURL *Home(void){return [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];}
// "Blocked" requires the download-only profile, the compiled-in guard and the
// installed rayneonet transport hook (TIOHostDownloadOnlyGuardActive).
static BOOL Guarded(void){return TIOHostDownloadOnlyGuardActive();}
NSString *TIOFirmwareExportHubStatus(void){return TIOText(Guarded()?@"hub.status.firmwareExport.guarded":@"hub.status.firmwareExport.unguarded");}
static NSString *SizeText(id bytes){return [NSByteCountFormatter stringFromByteCount:[bytes longLongValue] countStyle:NSByteCountFormatterCountStyleFile];}
// Localized format keys go through one va_list helper (as in ClenchLabUI.m).
static NSString *Fmt(NSString *key,...){va_list a;va_start(a,key);NSString *r=[[NSString alloc]initWithFormat:TIOText(key) arguments:a];va_end(a);return r;}
static NSString *Stamp(NSDate *date){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm:ss";return date?[f stringFromDate:date]:@"";}

@interface TIOFirmwareExportPanel:UITableViewController
@property(nonatomic) NSDictionary *scan;
@property(nonatomic) NSArray<NSDictionary *> *entries,*copies;
@property(nonatomic) NSMutableDictionary<NSString *,NSDictionary *> *hashes;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger generation;
@end
@implementation TIOFirmwareExportPanel
- (void)viewDidLoad{
    [super viewDidLoad];self.title=TIOText(@"fwexport.title");TIOStyleResearchTable(self);self.hashes=[NSMutableDictionary new];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    [self refresh];
}
- (void)refresh{
    if(self.busy)return;self.busy=YES;NSUInteger generation=++self.generation;[self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *scan=TIOFirmwareExportScan(Home());NSArray *copies=TIOFirmwareExportOwnCopies(Home());
        dispatch_async(dispatch_get_main_queue(),^{
            if(generation!=self.generation)return;
            self.scan=scan;self.entries=scan[@"entries"];self.copies=copies;self.busy=NO;[self.hashes removeAllObjects];[self.tableView reloadData];
            [self hashAll:generation];
        });
    });
}
// One file at a time on a serial queue; a refresh abandons the remaining work.
- (void)hashAll:(NSUInteger)generation{
    NSMutableArray<NSURL *> *files=[NSMutableArray new];
    for(NSDictionary *e in self.entries)if([e[@"kind"] isEqual:@"file"])[files addObject:e[@"url"]];
    for(NSDictionary *c in self.copies)[files addObject:c[@"url"]];
    static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("io.turboio.firmware-export.hash",DISPATCH_QUEUE_SERIAL);});
    __weak typeof(self) weak=self;
    for(NSURL *file in files)dispatch_async(queue,^{
        __block BOOL current=NO;dispatch_sync(dispatch_get_main_queue(),^{current=weak&&weak.generation==generation;});if(!current)return;
        NSError *error=nil;NSDictionary *hash=TIOFirmwareExportHash(file,&error);
        dispatch_async(dispatch_get_main_queue(),^{typeof(self) s=weak;if(!s||s.generation!=generation)return;
            s.hashes[file.path]=hash?:@{@"error":error.localizedDescription?:@""};[s.tableView reloadData];});
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return SectionCount;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{
    if(s==SectionStatus)return 2;
    if(s==SectionFound)return MAX(1,self.entries.count);
    if(s==SectionCopies)return MAX(1,self.copies.count);
    return MAX(1,[self.scan[@"roots"] count]);
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{
    return TIOText(@[@"fwexport.section.status",@"fwexport.section.found",@"fwexport.section.copies",@"fwexport.section.roots"][s]);
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
    if(s==SectionStatus)return TIOText(@"fwexport.status.footer");
    if(s==SectionFound)return TIOText(@"fwexport.found.footer");
    if(s==SectionCopies)return TIOText(@"fwexport.copies.footer");
    NSMutableString *text=[Fmt(@"fwexport.roots.footer",(unsigned long)TIOFirmwareExportMaxDepth,(unsigned long)TIOFirmwareExportMaxEntries,(unsigned long)[self.scan[@"skippedLinks"] unsignedIntegerValue]) mutableCopy];
    if([self.scan[@"truncated"] boolValue])[text appendFormat:@"\n%@",TIOText(@"fwexport.roots.truncated")];
    if([self.scan[@"depthLimited"] boolValue])[text appendFormat:@"\n%@",TIOText(@"fwexport.roots.deep")];
    return text;
}
- (NSString *)hashText:(NSURL *)file{
    NSDictionary *h=self.hashes[file.path];
    if(!h)return TIOText(@"fwexport.hashing");
    if(h[@"error"])return Fmt(@"fwexport.hash.failed",h[@"error"]);
    return [NSString stringWithFormat:@"SHA-256 %@\nMD5 %@",h[@"sha256"],h[@"md5"]];
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);
    c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;c.selectionStyle=UITableViewCellSelectionStyleNone;
    if(ip.section==SectionStatus){
        if(ip.row==0){
            NSString *profile=TIOHostProfile();
            c.textLabel.text=Fmt(@"fwexport.host",[profile isEqual:@"ios1011-download"]?TIOText(@"fwexport.host.download"):TIOText(@"fwexport.host.unknown"));
            c.detailTextLabel.text=profile?:@"none";c.accessibilityIdentifier=@"fwexport-host";
        }else if(Guarded()){
            c.textLabel.text=TIOText(@"fwexport.guard.on");c.detailTextLabel.text=TIOText(@"fwexport.guard.on.detail");
            c.textLabel.textColor=TIODesignColor(TIODesignColorStatusOk);c.imageView.image=[UIImage systemImageNamed:@"checkmark.shield.fill"];c.imageView.tintColor=TIODesignColor(TIODesignColorStatusOk);
            c.accessibilityIdentifier=@"fwexport-guard-on";
        }else{
            // Loud on purpose: without the hook nothing stops an OTA session from this app.
            // Danger fill with the on-accent token: white text in light mode, dark text on the lighter dark-mode red.
            c.backgroundColor=TIODesignColor(TIODesignColorStatusDanger);c.textLabel.textColor=TIODesignColor(TIODesignColorOnAccent);c.detailTextLabel.textColor=TIODesignColor(TIODesignColorOnAccent);
            c.textLabel.font=TIODesignFontWeight(TIODesignTextStyleHeadline,UIFontWeightBold);
            c.textLabel.text=TIOText(@"fwexport.guard.off");c.detailTextLabel.text=TIOText(@"fwexport.guard.off.detail");
            c.imageView.image=[UIImage systemImageNamed:@"exclamationmark.octagon.fill"];c.imageView.tintColor=TIODesignColor(TIODesignColorOnAccent);
            c.accessibilityIdentifier=@"fwexport-guard-off";
        }
        return c;
    }
    if(ip.section==SectionRoots){
        NSArray *roots=self.scan[@"roots"];
        c.textLabel.text=roots.count?roots[ip.row]:(self.busy?TIOText(@"fwexport.scanning"):TIOText(@"fwexport.roots.none"));
        if(!roots.count&&!self.busy)c.detailTextLabel.text=[TIOFirmwareExportRootPaths() componentsJoinedByString:@"\n"];
        return c;
    }
    NSArray *rows=ip.section==SectionFound?self.entries:self.copies;
    if(!rows.count){c.textLabel.text=self.busy?TIOText(@"fwexport.scanning"):(ip.section==SectionFound?TIOText(@"fwexport.empty"):TIOText(@"fwexport.copies.empty"));return c;}
    NSDictionary *row=rows[ip.row];c.selectionStyle=UITableViewCellSelectionStyleDefault;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    c.textLabel.text=ip.section==SectionFound?row[@"relative"]:row[@"name"];
    c.textLabel.font=TIODesignFont(TIODesignTextStyleSubheadline);
    if([row[@"kind"] isEqual:@"folder"]){
        c.imageView.image=[UIImage systemImageNamed:@"folder"];
        c.detailTextLabel.text=Fmt(@"fwexport.folder.detail",(unsigned long)[row[@"files"] unsignedIntegerValue],SizeText(row[@"bytes"]));
    }else{
        c.imageView.image=[UIImage systemImageNamed:ip.section==SectionCopies?@"doc.zipper":@"doc"];
        c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n%@",SizeText(row[@"bytes"]),Stamp(row[@"modified"]),[self hashText:row[@"url"]]];
        c.detailTextLabel.font=TIODesignMonospacedDigitFont(TIODesignTextStyleFootnote);
    }
    return c;
}
- (void)notice:(NSString *)message{TIONotice(self,TIOText(@"fwexport.title"),message);}
- (void)share:(NSURL *)file{
    UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)fileActions:(NSDictionary *)row ownCopy:(BOOL)ownCopy{
    NSURL *file=row[@"url"];NSDictionary *h=self.hashes[file.path];BOOL hashed=h[@"sha256"]!=nil;
    NSMutableArray *titles=[NSMutableArray arrayWithObject:TIOText(@"fwexport.action.share")];
    if(hashed){[titles addObject:TIOText(@"fwexport.action.copySHA")];[titles addObject:TIOText(@"fwexport.action.copyMD5")];}
    if(ownCopy)[titles addObject:TIOText(@"fwexport.action.delete")];
    NSIndexSet *destructive=ownCopy?[NSIndexSet indexSetWithIndex:titles.count-1]:nil;
    TIOChoose(self,row[@"name"],[self hashText:file],titles,NSNotFound,destructive,^(NSInteger index){
        if(index==0){[self share:file];return;}
        if(hashed&&(index==1||index==2)){UIPasteboard.generalPasteboard.string=h[index==1?@"sha256":@"md5"];[self notice:TIOText(@"fwexport.copied")];return;}
        if(ownCopy&&index==(NSInteger)titles.count-1)TIOConfirm(self,TIOText(@"fwexport.delete.title"),TIOText(@"fwexport.delete.message"),TIOText(@"fwexport.action.delete"),YES,^{
            if(!TIOFirmwareExportDeleteOwnCopy(file,Home()))[self notice:TIOText(@"fwexport.delete.failed")];[self refresh];});
    });
}
- (void)rezip:(NSDictionary *)row{
    TIOConfirm(self,TIOText(@"fwexport.rezip.title"),TIOText(@"fwexport.rezip.message"),TIOText(@"fwexport.action.rezip"),NO,^{
        if(self.busy)return;self.busy=YES;NSURL *folder=row[@"url"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSError *error=nil;NSDictionary *zip=TIOFirmwareExportRezip(folder,Home(),&error);
            dispatch_async(dispatch_get_main_queue(),^{
                self.busy=NO;[self refresh];
                if(!zip){[self notice:Fmt(@"fwexport.rezip.failed",error.localizedDescription?:@"")];return;}
                if(self.view.window&&!self.presentedViewController)[self share:zip[@"url"]];
            });
        });
    });
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];if(self.busy)return;
    NSArray *rows=ip.section==SectionFound?self.entries:ip.section==SectionCopies?self.copies:nil;
    if(ip.row>=(NSInteger)rows.count)return;NSDictionary *row=rows[ip.row];
    if([row[@"kind"] isEqual:@"folder"])[self rezip:row];else [self fileActions:row ownCopy:ip.section==SectionCopies];
}
@end
UIViewController *TIOFirmwareExportController(void){return [[TIOFirmwareExportPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
