#import "MusicPlayer.h"
#import "MusicBridge.h"
#import "MusicClock.h"
#import "SpotifyAPI.h"
#import "SpotifyLyrics.h"
#import "SpotifyCover.h"
#import "NativeNavigationUI.h"
#import "ExperimentalOTAFlash.h"
#import "TIOLanguage.h"
#import "music.h"
#import <ImageIO/ImageIO.h>
#import <Security/Security.h>

static void TMPlayerOnMain(void(^block)(void)){if(NSThread.isMainThread)block();else dispatch_async(dispatch_get_main_queue(),block);}
static NSString *TMPlayerString(id value){return [value isKindOfClass:NSString.class]?value:@"";}
static NSTimeInterval TMPlayerUptime(void){return NSProcessInfo.processInfo.systemUptime;}
static NSString *TMPlayerStatus(TMSpotifyErrorKind kind){
 switch(kind){
  case TMSpotifyNotConfigured:return TIOText(@"music.status.config");
  case TMSpotifySignedOut:return TIOText(@"music.status.signin");
  case TMSpotifyPremiumRequired:return TIOText(@"music.status.premium");
  case TMSpotifyRestricted:return TIOText(@"music.status.restricted");
  case TMSpotifyNoActiveDevice:return TIOText(@"music.status.noDevice");
  case TMSpotifyRateLimited:return TIOText(@"music.status.rate");
  case TMSpotifyNetwork:case TMSpotifyServer:case TMSpotifyBadResponse:return TIOText(@"music.status.network");
  case TMSpotifyOK:return nil;
 }
 return TIOText(@"music.status.network");
}
static NSString *TMPlayerTrackKey(NSDictionary *state){
 NSString *identifier=TMPlayerString(state[@"id"]);if(identifier.length)return identifier;
 // Local tracks can omit id. Their metadata still distinguishes generations.
 return [@[TMPlayerString(state[@"type"]),TMPlayerString(state[@"title"]),TMPlayerString(state[@"artist"]),TMPlayerString(state[@"album"])] componentsJoinedByString:@"\x1f"];
}
@implementation TMPlayer{
 TMMusicBridge *_bridge;NSTimer *_timer;NSDictionary *_state;NSTimeInterval _fetchedAt;TMClockSample _sample;
 NSString *_trackID;NSUInteger _ticket,_sentTicket;UIImage *_cover;NSData *_gray;NSArray *_lyrics;NSString *_status;
 NSInteger _mode;BOOL _glasses,_panelVisible;uint32_t _request;NSTimeInterval _pollAt;BOOL _inflight;
 // Track/asset generations and command/auth revisions have different lifetimes.
 // Poll ownership prevents an obsolete callback from releasing a newer request.
 NSUInteger _revision,_pollSerial,_viewRevision,_resumeRevision,_resumeViewRevision;
 BOOL _resumePending,_lyricsEnabled,_coverLoading,_lyricsLoading;
}
+ (instancetype)shared{static TMPlayer *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p;}
- (instancetype)init{
 if((self=[super init])){
  NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
  [defaults registerDefaults:@{@"TurboSpotifyLyricsV1":@YES}];
  if(![defaults boolForKey:@"TurboMusicNetEaseCleanedV1"]){
   for(NSString *key in @[@"TurboMusicPlaybackV2",@"TurboMusicLastSongV1",@"TurboMusicLocalHistoryV2",@"TurboMusicLibraryKindV2",@"TurboMusicLibraryQueryV2",@"TurboMusicPageV2",@"TurboMusicAccountIDV2"])[defaults removeObjectForKey:key];
   SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"TurboIOMusicCookiesV1",(__bridge id)kSecAttrAccount:@"netease"});
   [defaults setBool:YES forKey:@"TurboMusicNetEaseCleanedV1"];
  }
  _bridge=[TMMusicBridge new];_ticket=1;_revision=1;
  _mode=MAX(0,MIN(2,[defaults integerForKey:@"TurboMusicDisplayModeV1"]));
  _glasses=[defaults boolForKey:@"TurboMusicGlassesV1"];
  _lyricsEnabled=[defaults boolForKey:@"TurboSpotifyLyricsV1"];
  _status=TMSpotifyAuth.shared.signedIn?TIOText(@"music.nothing"):TMPlayerStatus(TMSpotifyAuth.shared.clientID.length?TMSpotifySignedOut:TMSpotifyNotConfigured);
  __weak typeof(self) weak=self;
  _bridge.snapshot=^NSDictionary *{
   TMPlayer *s=weak;if(!s)return @{};
   return @{@"title":s->_state?TMPlayerString(s->_state[@"title"]):TIOText(@"music.glasses.idleTitle"),
            @"artist":s->_state?TMPlayerString(s->_state[@"artist"]):TIOText(@"music.glasses.idleArtist"),
            @"position":@((uint32_t)(s.position*1000)),@"duration":@((uint32_t)(s.duration*1000)),
            @"playing":@(s.playing),@"mode":@(s.mode),@"request":@(s->_request)};
  };
  _bridge.command=^(NSDictionary *q){
   TMPlayer *s=weak;if(!s)return;
   unsigned event=[q[@"event"] unsignedIntValue];s->_request=[q[@"request"] unsignedIntValue];
   if(event==TM_VIEW_CLOSED){++s->_viewRevision;s->_resumePending=NO;return;}
   if(event==TM_RESUME){[s resumeFromGlasses];return;}
   if(event==TM_PLAY){
    // The glasses can resume an existing context; only an explicit phone action
    // may discover a device and initiate a fresh transfer.
    if(!s->_state){[s resumeFromGlasses];return;}
    [s play:YES allowTransfer:NO];
   }else if(event==TM_PAUSE)[s play:NO allowTransfer:NO];
   else if(event==TM_NEXT)[s step:1];else if(event==TM_PREV)[s step:-1];
  };
  _timer=[NSTimer scheduledTimerWithTimeInterval:.15 repeats:YES block:^(NSTimer *timer){
   TMPlayer *s=weak;if(!s)return;[s->_bridge pump];NSTimeInterval now=TMPlayerUptime();
   if(TMSpotifyAuth.shared.signedIn&&(s->_panelVisible||(s->_glasses&&s->_bridge.active))&&now>=s->_pollAt&&!s->_inflight&&now>=TMSpotifyAPI.shared.backoffUntil)[s poll];
  }];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:UIApplicationWillEnterForegroundNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(authChanged:) name:TMSpotifyAuthChanged object:TMSpotifyAuth.shared];
 }
 return self;
}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (NSDictionary *)song{
 if(!_state)return nil;
 return @{@"id":TMPlayerString(_state[@"id"]),@"name":TMPlayerString(_state[@"title"]),@"artist":TMPlayerString(_state[@"artist"]),@"album":TMPlayerString(_state[@"album"])};
}
- (NSArray *)lyrics{return _lyrics?:@[];}
- (UIImage *)cover{return _cover;}
- (BOOL)playing{return [_state[@"playing"] boolValue];}
- (double)position{
 if(!_state)return 0;
 double milliseconds=[_state[@"progress_ms"] doubleValue]+(self.playing?MAX(0,TMPlayerUptime()-_fetchedAt)*1000:0);
 return MAX(0,MIN([_state[@"duration_ms"] doubleValue],milliseconds))/1000;
}
- (double)duration{return [_state[@"duration_ms"] doubleValue]/1000;}
- (NSString *)status{return _status?:TIOText(@"music.nothing");}
- (NSString *)bridgeStatus{return _bridge.note;}
- (NSInteger)mode{return _mode;}
- (void)setMode:(NSInteger)value{_mode=MAX(0,MIN(2,value));[NSUserDefaults.standardUserDefaults setInteger:_mode forKey:@"TurboMusicDisplayModeV1"];}
- (BOOL)glasses{return _glasses;}
- (void)setGlasses:(BOOL)value{_glasses=value;[NSUserDefaults.standardUserDefaults setBool:value forKey:@"TurboMusicGlassesV1"];if(value)[self showOnGlasses];else [self hideGlasses];}
- (BOOL)panelVisible{return _panelVisible;}
- (void)setPanelVisible:(BOOL)value{_panelVisible=value;if(value)[self refreshNow];}
- (NSArray *)idleLyrics{return @[@{@"ms":@0,@"text":TIOText(@"music.glasses.idleArtist")}];}
- (void)invalidateRequests{
 ++_revision;++_pollSerial;_inflight=NO;_resumePending=NO;_coverLoading=_lyricsLoading=NO;
}
- (BOOL)validTicket:(NSUInteger)ticket revision:(NSUInteger)revision client:(NSString *)client{
 return ticket==_ticket&&revision==_revision&&TMSpotifyAuth.shared.signedIn&&[client isEqual:TMSpotifyAuth.shared.clientID];
}
- (void)foreground:(NSNotification *)notification{__weak typeof(self) weak=self;TMPlayerOnMain(^{[weak refreshNow];});}
- (void)authChanged:(NSNotification *)notification{
 __weak typeof(self) weak=self;TMPlayerOnMain(^{
  TMPlayer *s=weak;if(!s)return;[s invalidateRequests];++s->_ticket;++s->_viewRevision;
  s->_state=nil;s->_trackID=nil;s->_cover=nil;s->_gray=nil;s->_lyrics=nil;s->_sample=(TMClockSample){0};s->_fetchedAt=TMPlayerUptime();s->_pollAt=0;
  [s->_bridge close];
  s->_status=TMSpotifyAuth.shared.signedIn?TIOText(@"music.nothing"):TMPlayerStatus(TMSpotifyAuth.shared.clientID.length?TMSpotifySignedOut:TMSpotifyNotConfigured);
  if(TMSpotifyAuth.shared.signedIn)[s refreshNow];
 });
}
- (void)syncLyricsPreference{
 BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"TurboSpotifyLyricsV1"];if(enabled==_lyricsEnabled)return;
 _lyricsEnabled=enabled;[self invalidateRequests];++_ticket;_lyrics=nil;
 // The bridge accepts each asset only once per generation, so replacing a
 // previously sent lyric asset requires a new generation even on the same track.
 if(_state)[self fetchAssets];else _lyrics=[self idleLyrics];
 if(_bridge.active)[self showOnGlasses];
}
- (void)refreshNow{
 [self syncLyricsPreference];_pollAt=0;
 if(!TMSpotifyAuth.shared.signedIn){_status=TMPlayerStatus(TMSpotifyAuth.shared.clientID.length?TMSpotifySignedOut:TMSpotifyNotConfigured);[self finishResume];return;}
 if(TMPlayerUptime()<TMSpotifyAPI.shared.backoffUntil){_status=TMPlayerStatus(TMSpotifyRateLimited);[self finishResume];return;}
 if(!_inflight)[self poll];
}
- (void)resumeFromGlasses{
 [self syncLyricsPreference];_resumePending=YES;_resumeRevision=_revision;_resumeViewRevision=++_viewRevision;
 [self refreshNow];
}
- (BOOL)finishResume{
 if(!_resumePending)return NO;_resumePending=NO;
 if(_resumeRevision!=_revision||_resumeViewRevision!=_viewRevision)return NO;
 [self showOnGlasses];return YES;
}
- (void)poll{
 if(_inflight||!TMSpotifyAuth.shared.signedIn||TMPlayerUptime()<TMSpotifyAPI.shared.backoffUntil)return;
 _inflight=YES;_pollAt=TMPlayerUptime()+3;
 NSUInteger serial=++_pollSerial,ticket=_ticket,revision=_revision;NSString *client=[TMSpotifyAuth.shared.clientID copy];
 __weak typeof(self) weak=self;
 [TMSpotifyAPI.shared player:^(NSDictionary *state,TMSpotifyErrorKind kind,NSTimeInterval retry){TMPlayerOnMain(^{
  TMPlayer *s=weak;if(!s||serial!=s->_pollSerial||![s validTicket:ticket revision:revision client:client])return;
  s->_inflight=NO;
  if(kind!=TMSpotifyOK){s->_status=TMPlayerStatus(kind);[s finishResume];return;}
  NSTimeInterval now=TMPlayerUptime();BOOL wasActive=s->_bridge.active;
  if(!state){
   BOOL hadState=s->_state!=nil;
   if(hadState){++s->_ticket;s->_trackID=nil;s->_cover=nil;s->_gray=nil;s->_coverLoading=s->_lyricsLoading=NO;}
   s->_state=nil;s->_sample=(TMClockSample){.at=now};s->_fetchedAt=now;s->_lyrics=[s idleLyrics];s->_status=TIOText(@"music.nothing");
   BOOL resumed=[s finishResume];if(hadState&&wasActive&&!resumed)[s showOnGlasses];
   return;
  }
  TMClockSample cur={.playing=[state[@"playing"] boolValue],.position_ms=[state[@"progress_ms"] unsignedIntValue],.duration_ms=[state[@"duration_ms"] unsignedIntValue],.at=now};
  NSString *track=TMPlayerTrackKey(state);BOOL changed=![track isEqual:s->_trackID];BOOL drifted=TMClockDrifted(s->_sample,cur);
  if(changed){++s->_ticket;s->_trackID=[track copy];s->_cover=nil;s->_gray=nil;s->_lyrics=nil;s->_coverLoading=s->_lyricsLoading=NO;}
  // Commit all snapshot fields BEFORE openWithCover: can synchronously pump an
  // OPEN packet. The original pseudocode opened the preceding track here.
  s->_sample=cur;s->_state=[state copy];s->_fetchedAt=now;s->_status=cur.playing?TIOText(@"music.status.playing"):TIOText(@"music.status.paused");
  [s fetchAssets];
  BOOL resumed=[s finishResume];
  if(changed&&s->_glasses&&!resumed)[s showOnGlasses];
  else if(!changed&&drifted)[s->_bridge changed];
 });}];
}
- (void)fetchAssets{
 if(!_state)return;
 NSUInteger ticket=_ticket,revision=_revision;NSString *client=[TMSpotifyAuth.shared.clientID copy];NSDictionary *state=_state;__weak typeof(self) weak=self;
 NSURL *image=[state[@"image"] isKindOfClass:NSURL.class]?state[@"image"]:nil;
 if(image&&!_cover&&!_coverLoading){
  _coverLoading=YES;
  TMSpotifyDefaultHTTP()([NSURLRequest requestWithURL:image],^(NSData *data,NSHTTPURLResponse *response,NSError *error){TMPlayerOnMain(^{
   TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;
   if(error||response.statusCode!=200||!data.length||data.length>8*1024*1024){s->_coverLoading=NO;return;}
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
    CGImageRef thumbnail=TMSpotifyThumbnail(data,360);NSData *gray=thumbnail?TMGrayCover(thumbnail):nil;
    dispatch_async(dispatch_get_main_queue(),^{
     TMPlayer *current=weak;
     if(current&&[current validTicket:ticket revision:revision client:client]){
      current->_coverLoading=NO;
      if(thumbnail&&gray.length==TM_COVER_BYTES){current->_cover=[UIImage imageWithCGImage:thumbnail];current->_gray=gray;if(current->_sentTicket==current->_ticket)[current->_bridge assetsCover:gray lyrics:nil];}
     }
     if(thumbnail)CGImageRelease(thumbnail);
    });
   });
  });});
 }
 if(_lyrics.count||_lyricsLoading)return;
 if(!_lyricsEnabled){_lyrics=@[@{@"ms":@0,@"text":TIOText(@"music.lyrics.off")}];if(_sentTicket==_ticket)[_bridge assetsCover:nil lyrics:_lyrics];return;}
 _lyricsLoading=YES;
 [TMSpotifyLyrics.shared lyricsForID:TMPlayerString(state[@"id"]) title:TMPlayerString(state[@"title"]) artist:TMPlayerString(state[@"artist"]) album:TMPlayerString(state[@"album"]) durationMs:[state[@"duration_ms"] unsignedIntValue] done:^(NSArray *rows,NSString *kind,BOOL failed){TMPlayerOnMain(^{
  TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;s->_lyricsLoading=NO;
  if(!failed&&[kind isEqual:@"synced"]&&rows.count)s->_lyrics=[rows copy];
  else s->_lyrics=@[@{@"ms":@0,@"text":failed?TIOText(@"music.lyrics.error"):[kind isEqual:@"instrumental"]?TIOText(@"music.lyrics.instrumental"):TIOText(@"music.lyrics.none")}];
  if(s->_sentTicket==s->_ticket)[s->_bridge assetsCover:nil lyrics:s->_lyrics];
 });}];
}
- (BOOL)beginControl{
 if(!TMSpotifyAuth.shared.signedIn){_status=TMPlayerStatus(TMSpotifyAuth.shared.clientID.length?TMSpotifySignedOut:TMSpotifyNotConfigured);return NO;}
 [self syncLyricsPreference];[self invalidateRequests];_pollAt=TMPlayerUptime()+.5;
 return YES;
}
- (void)followUpForTicket:(NSUInteger)ticket revision:(NSUInteger)revision client:(NSString *)client{
 _pollAt=TMPlayerUptime()+.5;__weak typeof(self) weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;[s refreshNow];});
}
- (void)optimisticPlaying:(BOOL)value{
 if(!_state)return;
 NSTimeInterval now=TMPlayerUptime();uint32_t position=(uint32_t)(self.position*1000);
 TMClockSample cur={.playing=value,.position_ms=position,.duration_ms=[_state[@"duration_ms"] unsignedIntValue],.at=now};BOOL drifted=TMClockDrifted(_sample,cur);
 NSMutableDictionary *state=[_state mutableCopy];state[@"playing"]=@(value);state[@"progress_ms"]=@(position);
 _state=state;_fetchedAt=now;_sample=cur;_status=value?TIOText(@"music.status.playing"):TIOText(@"music.status.paused");
 if(drifted)[_bridge changed];
}
- (void)play:(BOOL)value{[self play:value allowTransfer:YES];}
- (void)play:(BOOL)value allowTransfer:(BOOL)allowTransfer{
 if(![self beginControl])return;[self optimisticPlaying:value];[self fetchAssets];
 NSUInteger ticket=_ticket,revision=_revision;NSString *client=[TMSpotifyAuth.shared.clientID copy];__weak typeof(self) weak=self;
 [self followUpForTicket:ticket revision:revision client:client];
 void(^done)(TMSpotifyErrorKind,NSTimeInterval)=^(TMSpotifyErrorKind kind,NSTimeInterval retry){TMPlayerOnMain(^{
  TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;
  if(kind==TMSpotifyNoActiveDevice&&value&&allowTransfer){
   [TMSpotifyAPI.shared devices:^(NSArray *devices,TMSpotifyErrorKind deviceKind){TMPlayerOnMain(^{
    TMPlayer *current=weak;if(!current||![current validTicket:ticket revision:revision client:client])return;
    if(deviceKind!=TMSpotifyOK){current->_status=TMPlayerStatus(deviceKind);return;}
    NSString *device=TMSpotifyPickDevice(devices);if(!device.length){current->_status=TIOText(@"music.status.noDevice");return;}
    [TMSpotifyAPI.shared transfer:device play:YES done:^(TMSpotifyErrorKind transferKind,NSTimeInterval transferRetry){TMPlayerOnMain(^{
     TMPlayer *latest=weak;if(!latest||![latest validTicket:ticket revision:revision client:client])return;
     if(transferKind!=TMSpotifyOK)latest->_status=TMPlayerStatus(transferKind);
     [latest followUpForTicket:ticket revision:revision client:client];
    });}];
   });}];
  }else if(kind!=TMSpotifyOK)s->_status=TMPlayerStatus(kind);
 });};
 if(value)[TMSpotifyAPI.shared play:done];else [TMSpotifyAPI.shared pause:done];
}
- (void)step:(NSInteger)delta{
 if(!delta||![self beginControl])return;[self fetchAssets];
 NSUInteger ticket=_ticket,revision=_revision;NSString *client=[TMSpotifyAuth.shared.clientID copy];__weak typeof(self) weak=self;
 [self followUpForTicket:ticket revision:revision client:client];
 void(^done)(TMSpotifyErrorKind,NSTimeInterval)=^(TMSpotifyErrorKind kind,NSTimeInterval retry){TMPlayerOnMain(^{TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;if(kind!=TMSpotifyOK)s->_status=TMPlayerStatus(kind);});};
 if(delta>0)[TMSpotifyAPI.shared next:done];else [TMSpotifyAPI.shared previous:done];
}
- (void)seek:(double)seconds{
 if(!isfinite(seconds)||!_state||![self beginControl])return;
 uint32_t milliseconds=(uint32_t)(MAX(0,MIN(self.duration,seconds))*1000);[self fetchAssets];
 NSUInteger ticket=_ticket,revision=_revision;NSString *client=[TMSpotifyAuth.shared.clientID copy];__weak typeof(self) weak=self;
 [self followUpForTicket:ticket revision:revision client:client];
 [TMSpotifyAPI.shared seek:milliseconds done:^(TMSpotifyErrorKind kind,NSTimeInterval retry){TMPlayerOnMain(^{
  TMPlayer *s=weak;if(!s||![s validTicket:ticket revision:revision client:client])return;
  if(kind!=TMSpotifyOK){s->_status=TMPlayerStatus(kind);return;}
  NSTimeInterval now=TMPlayerUptime();TMClockSample cur={.playing=s.playing,.position_ms=milliseconds,.duration_ms=[s->_state[@"duration_ms"] unsignedIntValue],.at=now};BOOL drifted=TMClockDrifted(s->_sample,cur);
  NSMutableDictionary *state=[s->_state mutableCopy];state[@"progress_ms"]=@(milliseconds);s->_state=state;s->_sample=cur;s->_fetchedAt=now;
  if(drifted)[s->_bridge changed];
 });}];
}
- (void)showOnGlasses{
 if(!TNVPauseForOTA()||[TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue]){_status=TIOText(@"music.status.blocked");return;}
 if(!_state){_cover=nil;_gray=nil;_lyrics=[self idleLyrics];}
 if(_sentTicket==_ticket)[_bridge reopen];else{_sentTicket=_ticket;[_bridge openWithCover:_gray lyrics:_lyrics];if(!_bridge.active)_sentTicket=0;}
}
- (void)hideGlasses{++_viewRevision;_resumePending=NO;[_bridge close];}
#if TIO_UI_PREVIEW
- (void)previewState:(NSDictionary *)state cover:(UIImage *)cover{
 [_timer invalidate];_timer=nil;[self invalidateRequests];++_ticket;_sentTicket=0;
 _state=[state copy];_trackID=state?TMPlayerTrackKey(state):nil;_fetchedAt=TMPlayerUptime();
 _sample=(TMClockSample){.playing=[state[@"playing"] boolValue],.position_ms=[state[@"progress_ms"] unsignedIntValue],.duration_ms=[state[@"duration_ms"] unsignedIntValue],.at=_fetchedAt};
 _cover=cover;_gray=cover.CGImage?TMGrayCover(cover.CGImage):nil;
 _lyrics=state?@[@{@"ms":@0,@"text":TIOText(@"music.lyrics.none")}]:[self idleLyrics];
 _glasses=NO;_panelVisible=NO;_request=0;_pollAt=0;
 _status=state?(_sample.playing?TIOText(@"music.status.playing"):TIOText(@"music.status.paused")):(TMSpotifyAuth.shared.signedIn?TIOText(@"music.nothing"):TMPlayerStatus(TMSpotifyAuth.shared.clientID.length?TMSpotifySignedOut:TMSpotifyNotConfigured));
}
#endif

- (BOOL)consume:(NSDictionary *)e{return [_bridge consume:e];}
- (BOOL)watchRemoteAvailable{return _glasses&&_state&&_bridge.active&&!_bridge.busy;}
- (BOOL)otaIdle{return !_bridge.busy&&!_bridge.active;}
- (void)pauseForVoice{}
@end
BOOL TMMusicConsume(NSDictionary *e){return [[TMPlayer shared]consume:e];}
BOOL TMMusicPauseForOTA(void){return [[TMPlayer shared]otaIdle];}
void TMMusicPauseForVoice(void){[[TMPlayer shared]pauseForVoice];}
