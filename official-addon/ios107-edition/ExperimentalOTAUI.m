#import "ExperimentalOTAUI.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import "OTAWizardModel.h"
#import "ResearchUI.h"
#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdarg.h>

static NSDictionary *(^Inputs)(void);
static void (^RefreshReport)(void);
static BOOL (^OpenDownload)(NSError **);
static void (^CloseDownload)(void);
static BOOL (^Authorize)(NSError **);
static BOOL (^Revoke)(void);
static BOOL (^DisableAuto)(void);
static BOOL (^VerifyPackage)(NSError **);
static BOOL (^ImportPackage)(NSURL *,NSError **);
static BOOL (^CheckDirectory)(NSError **);
static BOOL FixtureMode;

static NSURL *StoreDirectory(void) {
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];
}

static NSString *FirmwareName(void) {
    id candidate=[NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTABuild"];
    if ([candidate isKindOfClass:NSString.class]) {
        NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^TMG[0-9]+$" options:0 error:NULL];
        if ([pattern numberOfMatchesInString:candidate options:0 range:NSMakeRange(0,[candidate length])]==1) return candidate;
    }
    return @"TMG3";
}

static NSString *StepName(NSInteger step) {
    return TIOText(step==1?@"ota.step.check":step==2?@"ota.step.download":@"ota.step.install");
}

static NSString *TIOFormat(NSString *key, ...) {
    va_list arguments;va_start(arguments,key);
    NSString *result=[[NSString alloc] initWithFormat:TIOText(key) arguments:arguments];
    va_end(arguments);
    return result;
}

static NSString *ShortStatus(NSString *value) {
    if (!value.length) return @"";
    NSUInteger limit=[TIOUILanguage() hasPrefix:@"zh"]?20:40;
    if (value.length<=limit) return value;
    NSUInteger budget=limit-1;
    __block NSUInteger boundary=0;
    [value enumerateSubstringsInRange:NSMakeRange(0,value.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(__unused NSString *substring,NSRange range,__unused NSRange enclosingRange,BOOL *stop) {
        if (NSMaxRange(range)>budget) { *stop=YES;return; }
        boundary=NSMaxRange(range);
    }];
    return [[value substringToIndex:boundary] stringByAppendingString:@"…"];
}

@interface TIOWizardStepControl : UIControl
@property(nonatomic) NSInteger step;
@property(nonatomic) UIImageView *icon;
@property(nonatomic) UILabel *caption;
@end
@implementation TIOWizardStepControl @end

@interface TIOOTAWizard : UIViewController<UITableViewDataSource,UITableViewDelegate,UIDocumentPickerDelegate>
@property(nonatomic) UITableView *tableView;
@property(nonatomic) UIView *header;
@property(nonatomic) UILabel *subtitle;
@property(nonatomic) UIStackView *stepStrip;
@property(nonatomic) NSArray<TIOWizardStepControl *> *stepControls;
@property(nonatomic) UIVisualEffectView *actionBar;
@property(nonatomic) UIButton *primary;
@property(nonatomic) UIButton *secondary;
@property(nonatomic) NSDictionary *snapshot;
@property(nonatomic) NSInteger step;
@property(nonatomic) BOOL choseStep;
@property(nonatomic) BOOL initializedStep;
@property(nonatomic) NSNumber *packageOK;
@property(nonatomic) NSNumber *directoryOK;
@property(nonatomic) NSError *packageError;
@property(nonatomic) NSError *directoryError;
@property(nonatomic) BOOL packageMissing;
@property(nonatomic) BOOL packageBusy;
@property(nonatomic) BOOL directoryBusy;
@property(nonatomic) BOOL actionBusy;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSUInteger renderedRows;
@property(nonatomic) TIOOTAPhase renderedPhase;
@property(nonatomic) NSInteger renderedStep;
- (void)refreshSnapshot;
- (void)startPackageVerification;
- (void)startDirectoryCheck;
@end

@implementation TIOOTAWizard
+ (void)initialize {
    if (self!=TIOOTAWizard.class) return;
    Inputs=^{ return @{@"flash":TIOOTAFlashStatus()?:@{},@"feed":TIOExperimentalOTAFeedStatus()?:@{},
                       @"guard":TIOOTAGuardStatus()?:@{},@"prefs":NSUserDefaults.standardUserDefaults.dictionaryRepresentation?:@{}}; };
    RefreshReport=^{ TIORefreshExperimentalOTAReport(); };
    OpenDownload=^BOOL(NSError **error){ return TIOBeginExperimentalOTAPreparation(error); };
    CloseDownload=^{ TIOCancelExperimentalOTAPreparation(); };
    Authorize=^BOOL(NSError **error){ return TIOOTAFlashAuthorize(error); };
    Revoke=^BOOL{ return TIOOTAFlashCancel(); };
    DisableAuto=^BOOL{ return TIOOTAFlashDisableAutoUpdate(); };
    VerifyPackage=^BOOL(NSError **error){
        NSURL *file=[StoreDirectory() URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
        if ([NSFileManager.defaultManager fileExistsAtPath:file.path]) return TIOReadExperimentalOTA(file,error)!=nil;
        for (NSString *name in @[@"TurboFirmwareCandidate",@"TurboWeReadCandidate",@"TurboMusicCandidate"]) {
            NSURL *bundled=[NSBundle.mainBundle URLForResource:name withExtension:@"zip"];
            if (bundled) return TIOImportExperimentalOTA(bundled,StoreDirectory(),error)!=nil;
        }
        if (error) *error=[NSError errorWithDomain:@"TIOOTAWizard" code:404 userInfo:nil];
        return NO;
    };
    ImportPackage=^BOOL(NSURL *source,NSError **error){ return TIOImportExperimentalOTA(source,StoreDirectory(),error)!=nil; };
    CheckDirectory=^BOOL(NSError **error){
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.5.5"] isDirectory:YES];
        return TIOCheckExperimentalOTADirectory(directory,error)!=nil;
    };
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=TIOText(@"ota.title");
    self.view.backgroundColor=TIOPaper();
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    TIOAttachInfo(self,TIOText(@"ota.info.title"),TIOFormat(@"ota.info.body",FirmwareName()));
    [self buildTable];
    [self buildActionBar];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didBecomeActive)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refreshSnapshot];
}

- (void)dealloc {
    [self.timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)buildTable {
    UITableView *table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView=table;
    table.translatesAutoresizingMaskIntoConstraints=NO;
    table.dataSource=self;
    table.delegate=self;
    table.backgroundColor=TIOPaper();
    table.separatorColor=[UIColor.separatorColor colorWithAlphaComponent:.35];
    table.rowHeight=UITableViewAutomaticDimension;
    table.estimatedRowHeight=56;
    table.sectionHeaderTopPadding=8;
    [self.view addSubview:table];
    [NSLayoutConstraint activateConstraints:@[
        [table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,table.bounds.size.width,104)];
    self.header=header;
    UILabel *subtitle=[UILabel new];self.subtitle=subtitle;
    subtitle.translatesAutoresizingMaskIntoConstraints=NO;
    subtitle.text=TIOFormat(@"ota.subtitle",FirmwareName());
    subtitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    subtitle.textColor=UIColor.secondaryLabelColor;
    subtitle.adjustsFontForContentSizeCategory=YES;
    subtitle.accessibilityIdentifier=@"ota-subtitle";
    [header addSubview:subtitle];
    [NSLayoutConstraint activateConstraints:@[
        [subtitle.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
        [subtitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [subtitle.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20]
    ]];
    NSMutableArray *controls=[NSMutableArray array];
    for (NSInteger n=1;n<=3;n++) {
        TIOWizardStepControl *control=[TIOWizardStepControl new];control.step=n;
        UIImageView *icon=[UIImageView new];control.icon=icon;icon.contentMode=UIViewContentModeScaleAspectFit;
        [icon.widthAnchor constraintEqualToConstant:28].active=YES;
        [icon.heightAnchor constraintEqualToConstant:28].active=YES;
        UILabel *caption=[UILabel new];control.caption=caption;
        caption.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        caption.adjustsFontForContentSizeCategory=YES;
        caption.textAlignment=NSTextAlignmentCenter;
        caption.text=StepName(n);
        UIStackView *column=[[UIStackView alloc] initWithArrangedSubviews:@[icon,caption]];
        column.axis=UILayoutConstraintAxisVertical;column.spacing=6;column.alignment=UIStackViewAlignmentCenter;
        column.userInteractionEnabled=NO;
        column.translatesAutoresizingMaskIntoConstraints=NO;
        [control addSubview:column];
        [NSLayoutConstraint activateConstraints:@[
            [column.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
            [column.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
            [column.leadingAnchor constraintGreaterThanOrEqualToAnchor:control.leadingAnchor],
            [column.trailingAnchor constraintLessThanOrEqualToAnchor:control.trailingAnchor]
        ]];
        control.isAccessibilityElement=YES;
        control.accessibilityIdentifier=[NSString stringWithFormat:@"ota-step-%ld",(long)n];
        [control addTarget:self action:@selector(selectStep:) forControlEvents:UIControlEventTouchUpInside];
        [controls addObject:control];
    }
    self.stepControls=controls;
    UIStackView *strip=[[UIStackView alloc] initWithArrangedSubviews:controls];self.stepStrip=strip;
    strip.translatesAutoresizingMaskIntoConstraints=NO;
    strip.axis=UILayoutConstraintAxisHorizontal;
    strip.distribution=UIStackViewDistributionFillEqually;
    [header addSubview:strip];
    [NSLayoutConstraint activateConstraints:@[
        [strip.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14],
        [strip.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [strip.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [strip.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4]
    ]];
    table.tableHeaderView=header;
}

- (void)buildActionBar {
    UIVisualEffectView *bar=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.actionBar=bar;bar.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:bar];
    UIView *hairline=[UIView new];hairline.translatesAutoresizingMaskIntoConstraints=NO;
    hairline.backgroundColor=UIColor.separatorColor;
    [bar.contentView addSubview:hairline];
    UIButton *primary=[UIButton buttonWithType:UIButtonTypeSystem];self.primary=primary;
    primary.accessibilityIdentifier=@"ota-primary";
    [primary.heightAnchor constraintGreaterThanOrEqualToConstant:50].active=YES;
    [primary addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *secondary=[UIButton buttonWithType:UIButtonTypeSystem];self.secondary=secondary;
    secondary.accessibilityIdentifier=@"ota-secondary";
    [secondary.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [secondary addTarget:self action:@selector(secondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[primary,secondary]];
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;
    [bar.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [hairline.topAnchor constraintEqualToAnchor:bar.contentView.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:bar.contentView.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:.5],
        [stack.topAnchor constraintEqualToAnchor:bar.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:bar.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (fabs(self.header.bounds.size.width-self.tableView.bounds.size.width)>.5) {
        CGRect frame=self.header.frame;frame.size.width=self.tableView.bounds.size.width;
        self.header.frame=frame;self.tableView.tableHeaderView=self.header;
    }
    CGFloat height=self.actionBar.hidden?0:CGRectGetHeight(self.actionBar.bounds);
    if (fabs(self.tableView.contentInset.bottom-height)>.5) {
        UIEdgeInsets inset=self.tableView.contentInset;inset.bottom=height;self.tableView.contentInset=inset;
        inset=self.tableView.verticalScrollIndicatorInsets;inset.bottom=height;self.tableView.verticalScrollIndicatorInsets=inset;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    RefreshReport();
    [self refreshSnapshot];
    [self runChecksIfNeeded];
    if (!FixtureMode && (self.step>=2 || [self.snapshot[@"suggestedStep"] integerValue]>=2)) [self startDirectoryCheck];
    [self.timer invalidate];
    self.timer=[NSTimer timerWithTimeInterval:1 target:self selector:@selector(timerTick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];self.timer=nil;
}

- (void)didBecomeActive {
    RefreshReport();
    [self refreshSnapshot];
    [self runChecksIfNeeded];
    if (!FixtureMode && (self.step>=2 || [self.snapshot[@"suggestedStep"] integerValue]>=2)) [self startDirectoryCheck];
}

- (void)timerTick { [self refreshSnapshot]; }

- (void)runChecksIfNeeded {
    if (FixtureMode) return;
    if (!self.packageOK && !self.packageBusy) [self startPackageVerification];
    if (!self.directoryOK && !self.directoryBusy && (self.step>=2 || [self.snapshot[@"suggestedStep"] integerValue]>=2)) {
        [self startDirectoryCheck];
    }
}

- (void)refreshSnapshot {
    NSMutableDictionary *inputs=[Inputs() mutableCopy]?:[NSMutableDictionary dictionary];
    if (self.packageOK) inputs[@"packageOK"]=self.packageOK;
    if (self.directoryOK) inputs[@"directoryOK"]=self.directoryOK;
    NSDictionary *next=TIOOTAWizardSnapshot(inputs);
    TIOOTAPhase phase=[next[@"phase"] integerValue];
    if (!self.initializedStep || !self.choseStep) {
        self.step=MAX(1,MIN(3,[next[@"suggestedStep"] integerValue]));
        self.initializedStep=YES;
    }
    NSUInteger oldRows=self.renderedRows;
    TIOOTAPhase oldPhase=self.renderedPhase;
    NSInteger oldStep=self.renderedStep;
    self.snapshot=next;
    NSUInteger rows=[self rowCount];
    self.renderedRows=rows;self.renderedPhase=phase;self.renderedStep=self.step;
    [self updateHeader];
    [self updateButtons];
    if (oldRows!=rows || oldPhase!=phase || oldStep!=self.step) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
            UITableViewCell *cell=[self.tableView cellForRowAtIndexPath:path];
            if (cell) [self configureCell:cell at:path];
        }
    }
    if (!FixtureMode && !self.choseStep && self.step>=2 && !self.directoryOK && !self.directoryBusy && !self.actionBusy) {
        [self startDirectoryCheck];
    }
}

- (NSInteger)maxReachable {
    if ([self.snapshot[@"stage"] integerValue]>=1) return 3;
    if (![self.snapshot[@"canContinueFromCheck"] boolValue]) return 1;
    return [self.snapshot[@"directory"] integerValue]==TIOOTACheckOK?3:2;
}

- (void)updateHeader {
    BOOL unavailable=[self.snapshot[@"phase"] integerValue]==TIOOTAPhaseUnavailable;
    CGFloat desired=unavailable?44:104;
    if (fabs(self.header.frame.size.height-desired)>.5) {
        CGRect frame=self.header.frame;frame.size.height=desired;
        self.header.frame=frame;self.tableView.tableHeaderView=self.header;
    }
    self.subtitle.text=TIOFormat(@"ota.subtitle",FirmwareName());
    self.stepStrip.hidden=unavailable;
    for (TIOWizardStepControl *control in self.stepControls) {
        NSInteger n=control.step;
        BOOL current=n==self.step,completed=n<self.step;
        NSString *symbol=completed?@"checkmark.circle.fill":[NSString stringWithFormat:current?@"%ld.circle.fill":@"%ld.circle",(long)n];
        UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:24];
        control.icon.image=[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:configuration];
        control.icon.tintColor=completed?UIColor.systemGreenColor:current?TIOAccent():UIColor.tertiaryLabelColor;
        control.caption.text=StepName(n);
        control.caption.font=[UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1].pointSize
                                           weight:current?UIFontWeightMedium:UIFontWeightRegular];
        control.caption.textColor=(current||completed)?UIColor.labelColor:UIColor.tertiaryLabelColor;
        control.enabled=n<=[self maxReachable];
        control.accessibilityTraits=UIAccessibilityTraitButton|(current?UIAccessibilityTraitSelected:0);
        control.accessibilityLabel=TIOFormat(@"ota.step.accessibility",(long)n,StepName(n));
    }
}

- (void)selectStep:(TIOWizardStepControl *)sender {
    if (sender.step>[self maxReachable]) return;
    self.choseStep=YES;
    if (sender.step==self.step) return;
    self.step=sender.step;
    [self refreshSnapshot];
    [self runChecksIfNeeded];
}

- (void)updateButtons {
    NSDictionary *s=self.snapshot;
    BOOL unavailable=[s[@"phase"] integerValue]==TIOOTAPhaseUnavailable;
    self.actionBar.hidden=unavailable;
    if (unavailable) return;
    NSInteger stage=[s[@"stage"] integerValue];
    BOOL armed=[s[@"downloadArmed"] boolValue];
    BOOL directoryOK=[s[@"directory"] integerValue]==TIOOTACheckOK;
    NSString *primaryTitle=nil,*secondaryTitle=nil;
    BOOL primaryEnabled=NO,primaryDestructive=NO,secondaryDestructive=NO;
    if (self.step==1) {
        primaryTitle=TIOText(@"ota.continue");
        primaryEnabled=[s[@"canContinueFromCheck"] boolValue];
    } else if (self.step==2) {
        if (directoryOK) { primaryTitle=TIOText(@"ota.continue");primaryEnabled=YES; }
        else if (armed) { primaryTitle=TIOText(@"common.goRayNeo");primaryEnabled=YES; }
        else { primaryTitle=TIOText(@"ota.download.open");primaryEnabled=[s[@"canDownload"] boolValue]; }
        if (armed) { secondaryTitle=TIOText(@"ota.download.stop");secondaryDestructive=YES; }
    } else {
        if (stage==0) {
            primaryTitle=TIOText(@"ota.install.authorize");
            primaryEnabled=[s[@"canAuthorize"] boolValue];primaryDestructive=YES;
        } else if (stage==2) {
            primaryTitle=TIOText(@"ota.hub.installing");
        } else {
            primaryTitle=TIOText(@"common.goRayNeo");primaryEnabled=YES;
        }
        if (stage==1) secondaryTitle=TIOText(@"ota.install.revoke");
    }
    [self.primary setTitle:primaryTitle forState:UIControlStateNormal];
    TIOStyleAction(self.primary,YES,primaryDestructive);
    BOOL authorizedExit=self.step==3 && (stage==1 || stage==3);
    self.primary.enabled=primaryEnabled&&!self.actionBusy&&
        (authorizedExit || (!self.packageBusy&&!self.directoryBusy));
    self.secondary.hidden=!secondaryTitle;
    if (secondaryTitle) {
        [self.secondary setTitle:secondaryTitle forState:UIControlStateNormal];
        TIOStyleAction(self.secondary,NO,secondaryDestructive);
        self.secondary.enabled=!self.actionBusy;
    }
    [self.view setNeedsLayout];
}

- (NSUInteger)rowCount {
    if ([self.snapshot[@"phase"] integerValue]==TIOOTAPhaseUnavailable) return 1;
    if (self.step==1) return 5;
    if (self.step==2) return 3;
    return [self.snapshot[@"stage"] integerValue]>=1?4:3;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return 1; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return [self rowCount]; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(__unused NSInteger)section {
    if ([self.snapshot[@"phase"] integerValue]==TIOOTAPhaseUnavailable) return TIOText(@"ota.title");
    return StepName(self.step);
}
- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    [self configureCell:cell at:path];
    return cell;
}
- (void)tableView:(__unused UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(__unused NSIndexPath *)path {
    TIOStyleResearchCell(cell);
    [self configureCell:cell at:path];
}

- (UIButton *)fixButton:(NSString *)title identifier:(NSString *)identifier tag:(NSInteger)tag {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration=UIButtonConfiguration.tintedButtonConfiguration;
    configuration.buttonSize=UIButtonConfigurationSizeSmall;
    configuration.title=title;
    configuration.baseBackgroundColor=TIOAccent();
    configuration.baseForegroundColor=TIOAccent();
    button.configuration=configuration;
    button.accessibilityIdentifier=identifier;
    button.tag=tag;
    [button addTarget:self action:@selector(fixTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button sizeToFit];
    return button;
}

- (void)configureCell:(UITableViewCell *)cell at:(NSIndexPath *)path {
    NSDictionary *s=self.snapshot;
    cell.accessoryView=nil;
    cell.imageView.image=nil;
    cell.textLabel.textColor=TIOInk();
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.numberOfLines=1;
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    cell.accessibilityIdentifier=nil;
    TIOOTACheck state=TIOOTACheckPending;
    NSString *title=nil,*detail=nil;
    NSInteger row=path.row;
    if ([s[@"phase"] integerValue]==TIOOTAPhaseUnavailable) {
        title=TIOText(@"ota.unavailable");
        detail=@"";
        cell.imageView.image=[UIImage systemImageNamed:@"info.circle"];
    } else if (self.step==1) {
        if (row==0) {
            title=TIOFormat(@"ota.check.package",FirmwareName());
            state=[s[@"package"] integerValue];
            detail=state==TIOOTACheckOK?TIOText(@"ota.package.ok"):
                   state==TIOOTACheckPending?TIOText(@"ota.package.checking"):
                   self.packageMissing?TIOText(@"ota.package.missing"):TIOText(@"ota.package.bad");
            if (state==TIOOTACheckFail && !self.actionBusy) cell.accessoryView=[self fixButton:TIOText(@"ota.package.import") identifier:@"ota-fix-package" tag:1];
            cell.accessibilityIdentifier=@"ota-check-package";
        } else if (row==1) {
            title=TIOText(@"ota.check.source");state=[s[@"source"] integerValue];
            detail=TIOText(state==TIOOTACheckOK?@"ota.source.ok":state==TIOOTACheckPending?@"ota.source.pending":@"ota.source.fail");
            cell.accessibilityIdentifier=@"ota-check-source";
        } else if (row==2) {
            title=TIOText(@"ota.check.protect");state=[s[@"protect"] integerValue];
            detail=TIOText(state==TIOOTACheckOK?@"ota.protect.ok":@"ota.protect.fail");
            cell.accessibilityIdentifier=@"ota-check-protect";
        } else if (row==3) {
            title=TIOText(@"ota.check.auto");state=[s[@"autoUpdate"] integerValue];
            TIOAutoUpdateState autoState=[s[@"autoUpdateState"] integerValue];
            detail=TIOText(autoState==TIOAutoUpdateOff?@"ota.auto.off":autoState==TIOAutoUpdateOn?@"ota.auto.on":@"ota.auto.missing");
            if (state==TIOOTACheckAction && !self.actionBusy) cell.accessoryView=[self fixButton:TIOText(@"ota.fix") identifier:@"ota-fix-autoUpdate" tag:2];
            cell.accessibilityIdentifier=@"ota-check-autoUpdate";
        } else {
            title=TIOText(@"ota.check.version");state=[s[@"version"] integerValue];
            detail=[self versionStatus];cell.accessibilityIdentifier=@"ota-check-version";
        }
    } else if (self.step==2) {
        if (row==0) {
            title=TIOText(@"ota.step.download");
            BOOL armed=[s[@"downloadArmed"] boolValue];
            detail=armed?TIOFormat(@"ota.download.window",TIOOTAFormatClock([s[@"downloadSecondsLeft"] integerValue])):TIOText(@"ota.download.closed");
            state=armed?TIOOTACheckOK:TIOOTACheckPending;
            cell.accessibilityIdentifier=@"ota-download-window";
        } else if (row==1) {
            cell.textLabel.text=TIOText(@"ota.download.how");
            cell.detailTextLabel.text=@"";
            cell.textLabel.numberOfLines=0;
            cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
            cell.textLabel.textColor=UIColor.secondaryLabelColor;
            cell.accessibilityIdentifier=@"ota-download-how";
            return;
        } else {
            title=TIOText(@"ota.download.verify");state=[s[@"directory"] integerValue];
            detail=[self directoryStatus];cell.accessibilityIdentifier=@"ota-download-directory";
        }
    } else {
        if (row==0) {
            title=TIOText(@"ota.check.version");state=[s[@"version"] integerValue];
            detail=[self versionStatus];
            if (state!=TIOOTACheckOK && !self.actionBusy) cell.accessoryView=[self fixButton:TIOText(@"ota.fix") identifier:@"ota-fix-version" tag:3];
            cell.accessibilityIdentifier=@"ota-install-version";
        } else if (row==1) {
            title=TIOText(@"ota.download.verify");state=[s[@"directory"] integerValue];
            detail=[self directoryStatus];cell.accessibilityIdentifier=@"ota-install-directory";
        } else if (row==2) {
            NSInteger stage=[s[@"stage"] integerValue];
            title=TIOText(@"ota.step.install");
            if (stage==1) {detail=TIOText(@"ota.install.authorized");state=TIOOTACheckOK;}
            else if (stage==2) {detail=TIOFormat(@"ota.install.sending",(unsigned long)[s[@"validatedSlices"] unsignedIntegerValue]);state=TIOOTACheckPending;}
            else if (stage==3) {
                detail=TIOFormat(@"ota.install.failed",s[@"failure"]?:@"");
                state=TIOOTACheckFail;cell.detailTextLabel.textColor=UIColor.systemRedColor;
            } else {detail=TIOText(@"ota.install.notAuthorized");state=TIOOTACheckPending;}
            cell.accessibilityIdentifier=@"ota-install-session";
        } else {
            cell.textLabel.text=TIOText(@"ota.install.after");
            cell.detailTextLabel.text=@"";
            cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
            cell.textLabel.textColor=UIColor.secondaryLabelColor;
            cell.accessibilityIdentifier=@"ota-install-after";
            return;
        }
    }
    cell.textLabel.text=title;
    cell.detailTextLabel.text=ShortStatus(detail);
    if (title && [s[@"phase"] integerValue]!=TIOOTAPhaseUnavailable) {
        NSString *symbol=state==TIOOTACheckOK?@"checkmark.circle.fill":
                         state==TIOOTACheckFail?@"xmark.circle.fill":
                         state==TIOOTACheckAction?@"exclamationmark.triangle.fill":@"clock";
        UIColor *color=state==TIOOTACheckOK?UIColor.systemGreenColor:
                       state==TIOOTACheckFail?UIColor.systemRedColor:UIColor.systemOrangeColor;
        UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:20];
        UIImage *image=[[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:configuration];
        cell.imageView.image=[[image imageWithTintColor:color] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
}

- (NSString *)versionStatus {
    NSDictionary *s=self.snapshot;
    if ([s[@"version"] integerValue]!=TIOOTACheckOK) return TIOText(@"ota.version.stale");
    return TIOFormat(@"ota.version.fresh",(long)[s[@"versionAge"] integerValue],(long)[s[@"versionSecondsLeft"] integerValue]);
}

- (NSString *)directoryStatus {
    TIOOTACheck state=[self.snapshot[@"directory"] integerValue];
    if (state==TIOOTACheckOK) return TIOFormat(@"ota.download.ok",FirmwareName());
    if (state==TIOOTACheckPending) return TIOText(@"ota.download.waiting");
    return ShortStatus(self.directoryError.localizedDescription?:TIOText(@"ota.download.waiting"));
}

- (void)startPackageVerification {
    if (FixtureMode || self.packageBusy || self.actionBusy) return;
    self.packageBusy=YES;self.packageOK=nil;self.packageError=nil;self.packageMissing=NO;
    [self refreshSnapshot];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil;BOOL ok=VerifyPackage(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.packageBusy=NO;self.packageOK=@(ok);self.packageError=error;
            self.packageMissing=!ok && [error.domain isEqual:@"TIOOTAWizard"] && error.code==404;
            [self refreshSnapshot];
        });
    });
}

- (void)startDirectoryCheck {
    if (FixtureMode || self.directoryBusy || self.actionBusy) return;
    self.directoryBusy=YES;self.directoryOK=nil;self.directoryError=nil;
    [self refreshSnapshot];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil;BOOL ok=CheckDirectory(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.directoryBusy=NO;self.directoryOK=@(ok);self.directoryError=error;
            [self refreshSnapshot];
        });
    });
}

- (void)runAction:(BOOL(^)(NSError **error))action completion:(void(^)(BOOL ok,NSError *error))completion {
    if (self.actionBusy) return;
    self.actionBusy=YES;[self updateButtons];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil;BOOL ok=action(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.actionBusy=NO;
            RefreshReport();
            [self refreshSnapshot];
            if (completion) completion(ok,error);
        });
    });
}

- (void)fixTapped:(UIButton *)sender {
    if (self.actionBusy) return;
    if (sender.tag==1) {
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
        picker.allowsMultipleSelection=NO;picker.delegate=self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (sender.tag==2) {
        [self fixAutoUpdate];
    } else if (sender.tag==3) {
        [self openVersionInstructions];
    }
}

- (void)fixAutoUpdate {
    if ([self.snapshot[@"autoUpdateState"] integerValue]==TIOAutoUpdateOn && [self.snapshot[@"autoUpdateFixable"] boolValue]) {
        TIOConfirm(self,TIOText(@"ota.fix.autoOn.title"),TIOText(@"ota.fix.autoOn.message"),
                   TIOText(@"ota.fix.autoOn.action"),NO,^{
            [self runAction:^BOOL(__unused NSError **error){return DisableAuto();} completion:^(BOOL wrote,__unused NSError *error){
                if (!wrote) [self showAutoUpdateInstructions];
            }];
        });
    } else {
        [self showAutoUpdateInstructions];
    }
}

- (void)showAutoUpdateInstructions {
    TIOConfirm(self,TIOText(@"ota.fix.autoMissing.title"),TIOText(@"ota.fix.autoMissing.message"),
               TIOText(@"common.goRayNeo"),NO,^{TIOCloseResearch(self);});
}

- (void)openVersionInstructions {
    TIOConfirm(self,TIOText(@"ota.fix.version.title"),TIOText(@"ota.fix.version.message"),
               TIOText(@"common.goRayNeo"),NO,^{TIOCloseResearch(self);});
}

- (void)primaryTapped {
    if (self.actionBusy) return;
    NSDictionary *s=self.snapshot;
    NSInteger stage=[s[@"stage"] integerValue];
    if (self.step==3 && (stage==1 || stage==3)) { TIOCloseResearch(self);return; }
    if (self.packageBusy || self.directoryBusy) return;
    if (self.step==1) {
        if (![s[@"canContinueFromCheck"] boolValue]) return;
        self.step=2;self.choseStep=YES;[self refreshSnapshot];[self runChecksIfNeeded];
        return;
    }
    if (self.step==2) {
        if ([s[@"directory"] integerValue]==TIOOTACheckOK) {
            self.step=3;self.choseStep=YES;[self refreshSnapshot];return;
        }
        if ([s[@"downloadArmed"] boolValue]) { TIOCloseResearch(self);return; }
        if (![s[@"canDownload"] boolValue]) return;
        [self runAction:^BOOL(NSError **error){return OpenDownload(error);} completion:^(BOOL ok,NSError *error){
            if (!ok) TIONotice(self,TIOText(@"ota.download.failed"),error.localizedDescription);
        }];
        return;
    }
    if (stage==2 || ![s[@"canAuthorize"] boolValue]) return;
    TIOConfirm(self,TIOFormat(@"ota.install.confirm.title",FirmwareName()),
               TIOText(@"ota.install.confirm.message"),TIOText(@"ota.install.confirm.action"),YES,^{
        // TIOOTAFlashAuthorize calls the main-thread-only TDPPhonePauseForOTA.
        if (self.actionBusy) return;
        self.actionBusy=YES;[self updateButtons];
        NSError *error=nil;BOOL ok=Authorize(&error);
        self.actionBusy=NO;
        RefreshReport();
        [self refreshSnapshot];
        if (!ok) TIONotice(self,TIOText(@"ota.install.notAuthorized"),error.localizedDescription);
    });
}

- (void)secondaryTapped {
    if (self.actionBusy) return;
    if (self.step==2 && [self.snapshot[@"downloadArmed"] boolValue]) {
        [self runAction:^BOOL(__unused NSError **error){CloseDownload();return YES;} completion:nil];
    } else if (self.step==3 && [self.snapshot[@"stage"] integerValue]==1) {
        [self runAction:^BOOL(__unused NSError **error){return Revoke();} completion:^(BOOL ok,__unused NSError *error){
            if (ok) TIONotice(self,TIOText(@"ota.install.revoked"),nil);
        }];
    }
}

- (void)documentPicker:(__unused UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count!=1 || self.actionBusy || self.packageBusy) return;
    NSURL *source=urls.firstObject;
    self.packageBusy=YES;self.packageOK=nil;self.packageError=nil;
    [self refreshSnapshot];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        BOOL access=[source startAccessingSecurityScopedResource];
        NSError *error=nil;BOOL ok=ImportPackage(source,&error);
        if (access) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.packageBusy=NO;self.packageError=error;
            if (ok) [self startPackageVerification];
            else {self.packageOK=@NO;self.packageMissing=NO;[self refreshSnapshot];}
        });
    });
}
@end

UIViewController *TIOExperimentalOTAController(void) { return [TIOOTAWizard new]; }

#if TIO_UI_PREVIEW
void TIOOTAWizardUseFixture(NSString *name) {
    [TIOOTAWizard class]; // Force +initialize before replacing the action blocks.
    FixtureMode=YES;
    NSString *fixture=[name copy];
    Inputs=^{ return TIOOTAWizardFixture(fixture); };
    RefreshReport=^{};
    OpenDownload=^BOOL(__unused NSError **error){return YES;};
    CloseDownload=^{};
    Authorize=^BOOL(__unused NSError **error){return YES;};
    Revoke=^BOOL{return YES;};
    DisableAuto=^BOOL{return YES;};
    VerifyPackage=^BOOL(__unused NSError **error){return YES;};
    ImportPackage=^BOOL(__unused NSURL *source,__unused NSError **error){return YES;};
    CheckDirectory=^BOOL(__unused NSError **error){return YES;};
}
#endif
