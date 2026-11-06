#import "WireLogUI.h"
#import "WireLog.h"
#import "TIOLanguage.h"
#import "TIOConfirm.h"
#import "TIODesign.h"
#import "ResearchUI.h"

// TIOText carries a format attribute; these keys hold printf formats, so they go through a plain NSString.
static NSString *Fmt(NSString *key) { NSString *f = TIOText(key); return f; }

// ---- recording pill: a click-through window above everything, shown while the recorder is active ----
static UIWindow *Pill;

static CGRect PillFrame(UIWindowScene *scene) {
    UIWindow *host = scene.keyWindow ?: scene.windows.firstObject;
    return CGRectMake(8 + host.safeAreaInsets.left, 2 + host.safeAreaInsets.top, 64, 18);
}

static void SyncPill(void) {
    BOOL on = TIOWireLogActive();
    if (!on) { Pill.hidden = YES; return; }
    if (Pill) { Pill.frame = PillFrame(Pill.windowScene); Pill.hidden = NO; return; }
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState != UISceneActivationStateUnattached) { scene = (UIWindowScene *)s; break; }
    if (!scene) return; // no scene yet: the poll below retries
    // The window is only as big as the pill and never key, so it cannot take over the status bar or any touches.
    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.frame = PillFrame(scene);
    w.windowLevel = UIWindowLevelAlert + 100;
    w.userInteractionEnabled = NO;
    w.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.userInteractionEnabled = NO;
    w.rootViewController = vc;
    UILabel *label = [[UILabel alloc] initWithFrame:vc.view.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = [NSString stringWithFormat:@"● %@", TIOText(@"wirelog.pill")];
    label.font = TIODesignFontWeight(TIODesignTextStyleCaption, UIFontWeightBold);
    label.textColor = TIODesignColor(TIODesignColorOnAccent);
    label.backgroundColor = TIODesignColor(TIODesignColorStatusDanger);
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 9; label.layer.masksToBounds = YES;
    label.isAccessibilityElement = YES;
    label.accessibilityLabel = TIOText(@"wirelog.pill.accessibility");
    label.accessibilityIdentifier = @"wirelog-pill";
    [vc.view addSubview:label];
    w.hidden = NO;
    Pill = w;
}

void TIOWireLogUIInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSTimer *poll;
        if (poll) return;
        SyncPill();
        poll = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { SyncPill(); }];
    });
}

NSString *TIOWireLogStatusLine(void) {
    NSDictionary *s = TIOWireLogLiveStatus(); // counters only; the hub asks for this on every redraw
    if (![s[@"active"] boolValue]) return TIOText(@"hub.status.wireLog.off");
    return [NSString stringWithFormat:Fmt(@"hub.status.wireLog.on"), (unsigned long)[s[@"records"] unsignedLongLongValue]];
}

// ---- screen ----
enum { SecRecord, SecStart, SecFiles, SecCount };

@interface TIOWireLogPanel : UITableViewController
@property (nonatomic, strong) NSTimer *refresh;
@property (nonatomic, copy) NSDictionary *cached; // full status; refreshed once a second off the main thread
@end

@implementation TIOWireLogPanel
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TIOText(@"hub.row.wireLog");
    self.tableView.accessibilityIdentifier = @"wirelog-table";
    self.cached = TIOWireLogStatus();
}
- (void)refreshStatus {
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *fresh = TIOWireLogStatus(); // lists the folder: never on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{ weak.cached = fresh; [weak.tableView reloadData]; });
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak typeof(self) weak = self;
    self.refresh = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [weak refreshStatus]; }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.refresh invalidate]; self.refresh = nil; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SecCount; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == SecFiles ? 2 : 1; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == SecRecord) return TIOText(@"wirelog.footer.privacy");
    if (s == SecStart) return TIOText(@"wirelog.footer.start");
    return TIOText(@"wirelog.footer.files");
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    // Live counters are cheap; the folder listing (files, totalBytes) comes from the once-a-second cache.
    NSMutableDictionary *s = [self.cached mutableCopy] ?: [NSMutableDictionary new];
    [s addEntriesFromDictionary:TIOWireLogLiveStatus()];
    BOOL active = [s[@"active"] boolValue];
    cell.detailTextLabel.numberOfLines = 0;
    if (ip.section == SecRecord) {
        cell.textLabel.text = TIOText(@"wirelog.record");
        NSString *why = s[@"disabledReason"];
        cell.detailTextLabel.text = why.length ? [NSString stringWithFormat:Fmt(@"wirelog.stopped.error"), why]
            : [NSString stringWithFormat:Fmt(@"wirelog.status"), (unsigned long)[s[@"records"] unsignedLongLongValue], (unsigned long)[s[@"dropped"] unsignedLongLongValue], [s[@"file"] length] ? s[@"file"] : @"-"];
        UISwitch *sw = [UISwitch new]; sw.on = active; sw.accessibilityLabel = cell.textLabel.text; sw.accessibilityIdentifier = @"wirelog-switch";
        [sw addTarget:self action:@selector(toggleRecording:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (ip.section == SecStart) {
        cell.textLabel.text = TIOText(@"wirelog.autostart");
        UISwitch *sw = [UISwitch new]; sw.on = TIOWireLogAutoStartEnabled(); sw.accessibilityLabel = cell.textLabel.text; sw.accessibilityIdentifier = @"wirelog-autostart";
        [sw addTarget:self action:@selector(toggleAutoStart:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (ip.row == 0) {
        cell.textLabel.text = TIOText(@"wirelog.export");
        cell.detailTextLabel.text = [NSString stringWithFormat:Fmt(@"wirelog.files"), (unsigned long)[s[@"files"] unsignedIntegerValue],
                                     [NSByteCountFormatter stringFromByteCount:(long long)[s[@"totalBytes"] unsignedLongLongValue] countStyle:NSByteCountFormatterCountStyleFile]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityIdentifier = @"wirelog-export";
    } else {
        cell.textLabel.text = TIOText(@"wirelog.delete");
        cell.textLabel.textColor = TIODesignColor(TIODesignColorStatusDanger);
        cell.accessibilityIdentifier = @"wirelog-delete";
    }
    TIOStyleResearchCell(cell);
    return cell;
}
- (void)toggleRecording:(UISwitch *)sw {
    if (sw.on) TIOWireLogStart(); else TIOWireLogStop();
    TIOWireLogUIInstall();
    [self refreshStatus];
}
- (void)toggleAutoStart:(UISwitch *)sw { TIOWireLogSetAutoStart(sw.on); }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != SecFiles) return;
    if (ip.row == 0) [self exportFromRect:[t rectForRowAtIndexPath:ip]];
    else [self deleteAll];
}
- (void)exportFromRect:(CGRect)rect {
    __weak typeof(self) weak = self;
    TIOWireLogFlush(^{
        NSArray<NSURL *> *files = TIOWireLogFiles();
        if (!files.count) { TIONotice(weak, TIOText(@"wirelog.export"), TIOText(@"wirelog.export.none")); return; }
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
        share.popoverPresentationController.sourceView = weak.tableView;
        share.popoverPresentationController.sourceRect = rect;
        [weak presentViewController:share animated:YES completion:nil];
    });
}
- (void)deleteAll {
    if (TIOWireLogActive()) { TIONotice(self, TIOText(@"wirelog.delete"), TIOText(@"wirelog.delete.running")); return; }
    __weak typeof(self) weak = self;
    TIOConfirm(self, TIOText(@"wirelog.delete"), TIOText(@"wirelog.delete.message"), TIOText(@"wirelog.delete"), YES, ^{
        for (NSURL *u in TIOWireLogFiles()) [NSFileManager.defaultManager removeItemAtURL:u error:nil];
        [weak.tableView reloadData];
    });
}
@end

UIViewController *TIOWireLogController(void) { return [[TIOWireLogPanel alloc] initWithStyle:UITableViewStyleInsetGrouped]; }
