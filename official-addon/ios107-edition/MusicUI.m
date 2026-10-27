#import "MusicPlayer.h"
#import "TIOConfirm.h"
#import "ResearchUI.h"
#import "SpotifyAuth.h"
#import "SpotifySignIn.h"
#import "TIOLanguage.h"

@interface TMMusicPanel : UITableViewController
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,strong) id authObserver;
@property(nonatomic,copy) NSString *footerError;
@property(nonatomic) BOOL previousSignedIn;
@property(nonatomic) BOOL previousConfigured;
@end

@implementation TMMusicPanel

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TIOText(@"music.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    __weak typeof(self) weakSelf = self;
    self.authObserver = [NSNotificationCenter.defaultCenter addObserverForName:TMSpotifyAuthChanged
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            TMMusicPanel *panel = weakSelf;
            if (!panel) return;
            panel.footerError = nil;
            [panel syncStructureAndReload];
        }];
}

- (void)dealloc {
    [self.refreshTimer invalidate];
    if (self.authObserver) [NSNotificationCenter.defaultCenter removeObserver:self.authObserver];
}

- (BOOL)isConfigured {
    return TMSpotifyValidClientID(TMSpotifyAuth.shared.clientID);
}

- (void)syncStructureAndReload {
    self.previousSignedIn = TMSpotifyAuth.shared.signedIn;
    self.previousConfigured = self.isConfigured;
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    TMPlayer.shared.panelVisible = YES;
    [self syncStructureAndReload];
    [TMPlayer.shared refreshNow];
    [self.refreshTimer invalidate];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
        selector:@selector(refreshNowPlayingRows) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    TMPlayer.shared.panelVisible = NO;
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)refreshNowPlayingRows {
    BOOL signedIn = TMSpotifyAuth.shared.signedIn;
    BOOL configured = self.isConfigured;
    if (signedIn != self.previousSignedIn || configured != self.previousConfigured) {
        [self syncStructureAndReload];
        return;
    }
    if (!signedIn || self.tableView.numberOfSections < 2 || [self.tableView numberOfRowsInSection:1] != 3) return;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1],
        [NSIndexPath indexPathForRow:1 inSection:1], [NSIndexPath indexPathForRow:2 inSection:1]]
        withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return TMSpotifyAuth.shared.signedIn ? 5 : 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    BOOL signedIn = TMSpotifyAuth.shared.signedIn;
    BOOL configured = self.isConfigured;
    if (section == 0) return configured && signedIn ? 2 : 1;
    if (signedIn && section == 1) return 3;
    NSInteger offset = signedIn ? 1 : 0;
    if (section == 1 + offset) return 2;
    if (section == 2 + offset) return 1;
    if (section == 3 + offset) return 2;
    return 0;
}

- (NSInteger)nowPlayingSection { return 1; }
- (NSInteger)glassesSection { return TMSpotifyAuth.shared.signedIn ? 2 : 1; }
- (NSInteger)lyricsSection { return TMSpotifyAuth.shared.signedIn ? 3 : 2; }
- (NSInteger)advancedSection { return TMSpotifyAuth.shared.signedIn ? 4 : 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return TIOText(@"music.spotify");
    if (TMSpotifyAuth.shared.signedIn && section == 1) return TIOText(@"music.nowPlaying");
    if (section == self.glassesSection) return TIOText(@"music.glasses");
    if (section == self.lyricsSection) return TIOText(@"music.lyrics");
    if (section == self.advancedSection) return TIOText(@"music.advanced");
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if (self.footerError.length) return self.footerError;
        NSString *redirect = TMSpotifyAuth.shared.redirect ?: TMSpotifyDefaultRedirect;
        NSString *help = TIOText(@"music.clientID.help");
        return [NSString stringWithFormat:help, redirect];
    }
    if (section == self.lyricsSection) return TIOText(@"music.lyrics.footer");
    return nil;
}

- (UITableViewCell *)basicCell:(NSString *)reuse {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger s = indexPath.section, r = indexPath.row;
    BOOL signedIn = TMSpotifyAuth.shared.signedIn;
    if (s == 0) {
        if (!self.isConfigured) {
            UITableViewCell *cell = [self basicCell:@"client-id"];
            cell.textLabel.text = TIOText(@"music.clientID");
            cell.detailTextLabel.text = TIOText(@"music.clientID.notSet");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        if (!signedIn) {
            UITableViewCell *cell = [self basicCell:@"connect"];
            cell.textLabel.text = TIOText(@"music.connect");
            cell.textLabel.textColor = self.view.tintColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        UITableViewCell *cell = [self basicCell:@"account"];
        if (r == 0) {
            cell.textLabel.text = TIOText(@"music.connected");
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = TIOText(@"music.signOut");
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }
    if (signedIn && s == 1) {
        TMPlayer *player = TMPlayer.shared;
        if (r == 0) {
            UITableViewCell *cell = [self basicCell:@"now-playing"];
            NSDictionary *song = player.song;
            cell.textLabel.text = [song[@"name"] isKindOfClass:NSString.class] ? song[@"name"] : TIOText(@"music.nothing");
            NSString *artist = [song[@"artist"] isKindOfClass:NSString.class] ? song[@"artist"] : @"";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ / %@", artist,
                [self clockString:player.position], [self clockString:player.duration]];
            UIImage *cover = player.cover;
            if (cover) {
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(56, 56), NO, 0);
                [cover drawInRect:CGRectMake(0, 0, 56, 56)];
                UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                cell.imageView.image = scaled;
            } else {
                cell.imageView.image = [UIImage systemImageNamed:@"music.note"];
                cell.imageView.tintColor = UIColor.secondaryLabelColor;
            }
            cell.imageView.layer.cornerRadius = 8;
            cell.imageView.clipsToBounds = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        if (r == 1) {
            UITableViewCell *cell = [self basicCell:@"controls"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UIView *oldStack = [cell.contentView viewWithTag:7404];
            [oldStack removeFromSuperview];
            UIStackView *stack = [[UIStackView alloc] init];
            stack.tag = 7404;
            stack.axis = UILayoutConstraintAxisHorizontal;
            stack.distribution = UIStackViewDistributionFillEqually;
            stack.alignment = UIStackViewAlignmentCenter;
            stack.spacing = 12;
            NSArray *symbols = @[@"backward.end.fill", player.playing ? @"pause.fill" : @"play.fill", @"forward.end.fill"];
            NSArray *labels = @[TIOText(@"music.prev"), TIOText(@"music.playPause"), TIOText(@"music.next")];
            for (NSUInteger i = 0; i < symbols.count; i++) {
                UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
                [button setImage:[UIImage systemImageNamed:symbols[i]] forState:UIControlStateNormal];
                button.accessibilityLabel = labels[i];
                button.tag = i;
                button.tintColor = self.view.tintColor;
                [button addTarget:self action:@selector(controlTapped:) forControlEvents:UIControlEventTouchUpInside];
                [stack addArrangedSubview:button];
            }
            cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 20, 8, 20);
            stack.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:stack];
            [NSLayoutConstraint activateConstraints:@[
                [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                [stack.topAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
                [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
                [stack.heightAnchor constraintEqualToConstant:40]
            ]];
            return cell;
        }
        UITableViewCell *cell = [self basicCell:@"status"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", player.status ?: TIOText(@"music.status.network"), player.bridgeStatus ?: @""];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 2;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSInteger glassesSection = self.glassesSection;
    if (s == glassesSection && r == 0) {
        UITableViewCell *cell = [self basicCell:@"glasses"];
        cell.textLabel.text = TIOText(@"music.showOnGlasses");
        UISwitch *toggle = [UISwitch new];
        toggle.on = TMPlayer.shared.glasses;
        toggle.accessibilityLabel = TIOText(@"music.showOnGlasses");
        [toggle addTarget:self action:@selector(glassesChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (s == glassesSection && r == 1) {
        UITableViewCell *cell = [self basicCell:@"timeout"];
        cell.textLabel.text = TIOText(@"music.timeout");
        UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:@[
            TIOText(@"music.timeout.always"), TIOText(@"music.timeout.30"), TIOText(@"music.timeout.60")]];
        segments.selectedSegmentIndex = MAX(0, MIN(2, TMPlayer.shared.mode));
        segments.accessibilityLabel = TIOText(@"music.timeout");
        [segments addTarget:self action:@selector(timeoutChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = segments;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (s == self.lyricsSection) {
        UITableViewCell *cell = [self basicCell:@"lyrics-toggle"];
        cell.textLabel.text = TIOText(@"music.lyrics.toggle");
        UISwitch *toggle = [UISwitch new];
        toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:@"TurboSpotifyLyricsV1"];
        toggle.accessibilityLabel = TIOText(@"music.lyrics.toggle");
        [toggle addTarget:self action:@selector(lyricsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (s == self.advancedSection && r == 0) {
        UITableViewCell *cell = [self basicCell:@"advanced-client-id"];
        cell.textLabel.text = TIOText(@"music.clientID");
        NSString *value = TMSpotifyAuth.shared.clientID ?: @"";
        cell.detailTextLabel.text = value.length >= 8 ? [NSString stringWithFormat:@"%@…%@", [value substringToIndex:4], [value substringFromIndex:value.length - 4]] : TIOText(@"music.clientID.notSet");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (s == self.advancedSection && r == 1) {
        UITableViewCell *cell = [self basicCell:@"redirect"];
        cell.textLabel.text = TIOText(@"music.redirect");
        cell.detailTextLabel.text = TMSpotifyAuth.shared.redirect ?: TMSpotifyDefaultRedirect;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    return [self basicCell:@"empty"];
}

- (NSString *)clockString:(double)value {
    NSInteger seconds = (NSInteger)MAX(0, value);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)controlTapped:(UIButton *)sender {
    if (sender.tag == 0) [TMPlayer.shared step:-1];
    else if (sender.tag == 1) [TMPlayer.shared play:!TMPlayer.shared.playing];
    else [TMPlayer.shared step:1];
}

- (void)glassesChanged:(UISwitch *)sender { TMPlayer.shared.glasses = sender.isOn; }
- (void)timeoutChanged:(UISegmentedControl *)sender { TMPlayer.shared.mode = sender.selectedSegmentIndex; }
- (void)lyricsChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:@"TurboSpotifyLyricsV1"];
    [TMPlayer.shared refreshNow];
}

- (void)showClientIDEditor {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TIOText(@"music.clientID")
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = TMSpotifyAuth.shared.clientID;
        field.placeholder = TIOText(@"music.clientID");
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:TIOText(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:TIOText(@"music.save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = alert.textFields.firstObject.text ?: @"";
        self.footerError = [TMSpotifyAuth.shared setClientIDString:value] ? nil : TIOText(@"music.clientID.invalid");
        [self syncStructureAndReload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmSignOut {
    TIOConfirm(self,TIOText(@"common.ui.music.signOut.title"),nil,TIOText(@"common.ui.music.signOut.action"),YES,^{
        [TMSpotifyAuth.shared signOut];
    });
}

- (void)chooseRedirect {
    NSArray *options=@[TIOText(@"common.ui.music.redirect.custom"),TIOText(@"common.ui.music.redirect.loopback")];NSInteger selected=[TMSpotifyAuth.shared.redirect isEqual:TMSpotifyLoopbackRedirect]?1:0;TIOChoose(self,TIOText(@"common.ui.music.redirect.title"),nil,options,selected,nil,^(NSInteger index){if(index==0){
        TMSpotifyAuth.shared.redirect = TMSpotifyDefaultRedirect;
        [self syncStructureAndReload];
    }else if(index==1){
        TMSpotifyAuth.shared.redirect = TMSpotifyLoopbackRedirect;
        [self syncStructureAndReload];
    }});
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger s = indexPath.section, r = indexPath.row;
    if (s == 0) {
        if (!self.isConfigured) { [self showClientIDEditor]; return; }
        if (!TMSpotifyAuth.shared.signedIn) {
            __weak typeof(self) weakSelf = self;
            TMSpotifySignIn(self, ^(NSString *error) {
                TMMusicPanel *panel = weakSelf;
                if (!panel || !error.length) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                NSString *failure = TIOText(@"music.signin.failed");
                panel.footerError = [error isEqual:@"cancelled"] ? TIOText(@"music.signin.cancelled") :
                    [NSString stringWithFormat:failure, error];
                [panel syncStructureAndReload];
                });
            });
            return;
        }
        if (r == 1) [self confirmSignOut];
        return;
    }
    if (s == self.advancedSection) {
        if (r == 0) [self showClientIDEditor];
        else [self chooseRedirect];
    }
}

@end

UIViewController *TMMusicController(void) {
    return [[TMMusicPanel alloc] initWithStyle:UITableViewStyleInsetGrouped];
}
