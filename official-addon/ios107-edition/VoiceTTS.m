#import "VoiceTTS.h"
#import <AVFAudio/AVFAudio.h>
#import "TIOScript.h"

@interface TIOVoiceTTS () <AVSpeechSynthesizerDelegate>
@property(nonatomic,strong) AVSpeechSynthesizer *localSynth;
@property(nonatomic,strong) NSMutableArray<NSString *> *queue;
@property(nonatomic,copy) NSString *full;
@property(nonatomic,copy) NSString *pending;
@property(nonatomic,copy) NSString *state;
@property(nonatomic) NSUInteger generation,segments,totalCharacters;
@property(nonatomic) NSUInteger localOutstanding;
@property(nonatomic) BOOL finalRequested;
@property(nonatomic,strong) NSMutableDictionary *voiceCache;
@end

@implementation TIOVoiceTTS
- (void)setState:(NSString *)state {
    _state=[state copy];
    NSUserDefaults *prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];
    NSMutableArray *trace=[[prefs arrayForKey:@"ttsTrace"] mutableCopy]?:[NSMutableArray new];
    [trace addObject:@{@"at":@((NSInteger)(NSDate.date.timeIntervalSince1970*1000)),@"state":_state?:@""}];
    if(trace.count>24)[trace removeObjectsInRange:NSMakeRange(0,trace.count-24)];
    [prefs setObject:trace forKey:@"ttsTrace"];
}
- (instancetype)init {
    if((self=[super init])) {
        _queue=[NSMutableArray new];_full=@"";_pending=@"";_state=@"idle";
        _fallbackLanguage=@"en";_voiceCache=[NSMutableDictionary new];
    }return self;
}
- (void)cancel {
    NSAssert(NSThread.isMainThread,@"TTS state belongs to the main queue");
    self.generation++;
    self.localSynth.delegate=nil;[self.localSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];self.localSynth=nil;self.localOutstanding=0;
    [self.queue removeAllObjects];self.full=@"";self.pending=@"";
    self.segments=0;self.totalCharacters=0;self.finalRequested=NO;
    [self.voiceCache removeAllObjects];self.state=@"idle";
}
- (void)beginTurn {if(self.willBeginTurn)self.willBeginTurn();[self cancel];}
+ (BOOL)bluetoothRouteActive {
    for(AVAudioSessionPortDescription *out in AVAudioSession.sharedInstance.currentRoute.outputs)
        if([out.portType isEqual:AVAudioSessionPortBluetoothA2DP]||[out.portType isEqual:AVAudioSessionPortBluetoothHFP])return YES;
    return NO;
}
- (NSString *)status {return [self statusForLanguage:self.fallbackLanguage];}
- (NSString *)statusForLanguage:(NSString *)language {
    return TIOVoiceTTSStatusText(self.state,TIOVoiceTTS.bluetoothRouteActive,language);
}
- (void)appendFullText:(NSString *)text finished:(BOOL)finished {
    NSAssert(NSThread.isMainThread,@"TTS state belongs to the main queue");
    BOOL valid=[text isKindOfClass:NSString.class],prefix=valid&&(!self.full.length||[text hasPrefix:self.full]),wasFinal=self.finalRequested;
    NSUserDefaults *diag=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];
    [diag setObject:@{@"textLength":@(text.length),@"fullLength":@(self.full.length),@"prefix":@(prefix),@"wasFinal":@(wasFinal)} forKey:@"ttsAppendEntry"];
    if(!valid||!prefix||wasFinal){self.state=@"notAppended";return;}
    NSString *newText=[text substringFromIndex:self.full.length];self.full=[text copy];
    if(newText.length){NSUInteger left=1800>self.totalCharacters?1800-self.totalCharacters:0;
        if(left){NSString *part=[newText substringToIndex:MIN(newText.length,left)];self.pending=[self.pending stringByAppendingString:part];self.totalCharacters+=part.length;}}
    if(finished)self.finalRequested=YES;
    NSUInteger used=0;
    while(self.segments<18){NSString *part=TIOVoiceTTSChunk(self.pending,finished,&used);if(!used)break;
        self.pending=[self.pending substringFromIndex:used];if(part.length){[self.queue addObject:part];self.segments++;}}
    if(self.segments>=18)self.pending=@"";
    [diag setObject:@{@"pendingLength":@(self.pending.length),@"queueCount":@(self.queue.count),@"segments":@(self.segments),@"used":@(used)} forKey:@"ttsAppendResult"];
    if(self.queue.count)[self speakLocalQueue];
    else if(self.finalRequested&&!self.localOutstanding&&self.full.length)self.state=@"done";
}
- (void)speakLocalQueue {
    if(!self.queue.count)return;
    NSError *activationError=nil;[AVAudioSession.sharedInstance setActive:YES error:&activationError];
    if(!TIOVoiceTTS.bluetoothRouteActive){self.state=@"noAudio";[self.queue removeAllObjects];return;}
    if(!self.localSynth){self.localSynth=[AVSpeechSynthesizer new];self.localSynth.delegate=self;
        self.localSynth.usesApplicationAudioSession=YES;}
    while(self.queue.count) {
        NSString *part=self.queue.firstObject;[self.queue removeObjectAtIndex:0];
        for(NSDictionary *run in TIOVoiceTTSRuns(part,self.fallbackLanguage)) {
            AVSpeechUtterance *utterance=[[AVSpeechUtterance alloc]initWithString:run[@"text"]];
            utterance.voice=[self voiceForLanguage:run[@"lang"]];
            NSUserDefaults *prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];
            utterance.rate=MIN(AVSpeechUtteranceMaximumSpeechRate,MAX(AVSpeechUtteranceMinimumSpeechRate,AVSpeechUtteranceDefaultSpeechRate*TIOVoiceTTSSpeedMultiplier(prefs)));utterance.volume=1.0;
            self.localOutstanding++;[self.localSynth speakUtterance:utterance];
        }
    }
    self.state=@"speaking";
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(synth!=self.localSynth)return;
    if(self.localOutstanding)self.localOutstanding--;
    if(self.finalRequested&&!self.localOutstanding)self.state=@"done";
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(synth!=self.localSynth)return;
    if(self.localOutstanding)self.localOutstanding--;
    if(!self.localOutstanding)self.state=@"interrupted";
}
- (AVSpeechSynthesisVoice *)voiceForLanguage:(NSString *)language {
    BOOL chinese=TIOScriptLanguageIsChinese(language);
    NSString *key=chinese?@"zh":@"en";
    NSDictionary *cached=self.voiceCache[key];
    if(cached)return cached[@"voice"];
    NSString *defaultLanguage=chinese?@"zh-CN":@"en-US";
    AVSpeechSynthesisVoice *defaultVoice=[AVSpeechSynthesisVoice voiceWithLanguage:defaultLanguage];
    NSMutableArray *descriptors=[NSMutableArray new];
    for(AVSpeechSynthesisVoice *voice in AVSpeechSynthesisVoice.speechVoices) {
        BOOL novelty=NO,personal=NO;
        if(@available(iOS 17.0,*)) {
            novelty=(voice.voiceTraits&AVSpeechSynthesisVoiceTraitIsNoveltyVoice)!=0;
            personal=(voice.voiceTraits&AVSpeechSynthesisVoiceTraitIsPersonalVoice)!=0;
        }
        [descriptors addObject:@{@"id":voice.identifier,@"lang":voice.language,@"quality":@(voice.quality),
            @"name":voice.name,@"novelty":@(novelty),@"personal":@(personal),
            @"systemDefault":@([voice.identifier isEqual:defaultVoice.identifier])}];
    }
    NSDictionary *picked=TIOVoiceTTSPickVoice(descriptors,language);
    AVSpeechSynthesisVoice *voice=picked?[AVSpeechSynthesisVoice voiceWithIdentifier:picked[@"id"]]:nil;
    if(!voice)voice=defaultVoice;
    if(voice)self.voiceCache[key]=@{@"voice":voice,@"name":voice.name,@"quality":@(voice.quality)};
    return voice;
}
- (NSString *)voiceSummaryForLanguage:(NSString *)language {
    BOOL chinese=TIOScriptLanguageIsChinese(language),needsDownload=NO;
    NSArray *qualities=chinese?@[/*i18n:keep*/@"默认",/*i18n:keep*/@"增强",/*i18n:keep*/@"高级"]:@[@"Default",@"Enhanced",@"Premium"];
    NSMutableArray *parts=[NSMutableArray new];
    for(NSString *key in @[@"en",@"zh"]) {
        NSDictionary *cached=self.voiceCache[key];
        NSString *detail=@"—";
        if(cached) {
            NSUInteger quality=[cached[@"quality"] unsignedIntegerValue];
            NSString *qualityText=qualities[quality>=1&&quality<=3?quality-1:0];
            detail=[NSString stringWithFormat:@"%@ (%@)",cached[@"name"],qualityText];
            if(quality==1)needsDownload=YES;
        }
        [parts addObject:[NSString stringWithFormat:@"%@ %@",key.uppercaseString,detail]];
    }
    NSString *summary=[parts componentsJoinedByString:@" · "];
    if(needsDownload)summary=[summary stringByAppendingString:chinese?
        /*i18n:keep*/@" · 更好音色：设置 › 辅助功能 › 朗读内容 › 声音":
        @" · Better voices: Settings › Accessibility › Spoken Content › Voices"];
    return summary;
}
@end
