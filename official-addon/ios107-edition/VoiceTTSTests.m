#import "VoiceTTSText.h"
#include <assert.h>
#include <stdio.h>

static void Chunk(NSString *text, BOOL final, NSString *expected, NSUInteger consumed) {
    NSUInteger used=999;
    NSString *actual=TIOVoiceTTSChunk(text,final,&used);
    if(!(expected ? [actual isEqual:expected] : actual==nil)||used!=consumed)
        fprintf(stderr,"chunk input=%s final=%d expected=%s/%lu actual=%s/%lu\n",text.UTF8String,final,
            expected.UTF8String,(unsigned long)consumed,actual.UTF8String,(unsigned long)used);
    assert((expected ? [actual isEqual:expected] : actual==nil) && used==consumed);
}
static NSDictionary *Run(NSString *lang, NSString *text) { return @{@"lang":lang,@"text":text}; }
static NSDictionary *Voice(NSString *identifier, NSString *language, NSNumber *quality, BOOL novelty, BOOL personal, BOOL systemDefault) {
    return @{@"id":identifier,@"lang":language,@"quality":quality,@"name":identifier,
        @"novelty":@(novelty),@"personal":@(personal),@"systemDefault":@(systemDefault)};
}
int main(void) { @autoreleasepool {
    // These fixed vectors catch premature chunking and missing sentence boundaries.
    Chunk(/*i18n:keep*/@"正在说话",NO,nil,0);
    Chunk(/*i18n:keep*/@"第一句话。第二句",NO,/*i18n:keep*/@"第一句话。",5);
    Chunk(/*i18n:keep*/@"结束",YES,/*i18n:keep*/@"结束",2);
    Chunk(@"Hello there. Next",NO,@"Hello there.",12);
    Chunk(@"It costs 3.14 dollars",NO,nil,0);
    Chunk(@"Ends with a dot.",NO,nil,0);
    Chunk(@"Ends with a dot.",YES,@"Ends with a dot.",16);
    Chunk(@"Talk to Dr. Smith now. Bye",NO,@"Talk to Dr. Smith now.",22);
    Chunk(@"Use e.g. this one. Ok",NO,@"Use e.g. this one.",18);
    Chunk(@"Wait… what",NO,@"Wait…",5);
    Chunk([@"" stringByPaddingToLength:70 withString:@"word " startingAtIndex:0],NO,nil,0);
    NSUInteger used=0;
    TIOVoiceTTSChunk([@"" stringByPaddingToLength:130 withString:@"word " startingAtIndex:0],NO,&used);
    assert(used==125);
    TIOVoiceTTSChunk([[@"" stringByPaddingToLength:70 withString:/*i18n:keep*/@"汉" startingAtIndex:0] stringByAppendingString:/*i18n:keep*/@"，后面"],NO,&used);
    assert(used==71);

    // Exact runs pin neutral attachment, short names, and the six-run fallback.
    assert([TIOVoiceTTSRuns(@"Hello there.",nil) isEqual:@[Run(@"en",@"Hello there.")]]);
    assert([TIOVoiceTTSRuns(/*i18n:keep*/@"你好，世界。",nil) isEqual:@[Run(@"zh",/*i18n:keep*/@"你好，世界。")]]);
    assert([TIOVoiceTTSRuns(/*i18n:keep*/@"我用 iPhone 15 Pro 拍照。",nil) isEqual:@[Run(@"zh",/*i18n:keep*/@"我用 iPhone 15 Pro 拍照。")]]);
    assert(([TIOVoiceTTSRuns(/*i18n:keep*/@"这个功能叫 Apple Intelligence，很好用。",nil) isEqual:@[Run(@"zh",/*i18n:keep*/@"这个功能叫"),Run(@"en",/*i18n:keep*/@"Apple Intelligence，"),Run(@"zh",/*i18n:keep*/@"很好用。")]]));
    assert(([TIOVoiceTTSRuns(/*i18n:keep*/@"The capital of China is 北京.",nil) isEqual:@[Run(@"en",@"The capital of China is"),Run(@"zh",/*i18n:keep*/@"北京.")]]));
    assert([TIOVoiceTTSRuns(@"2026",@"zh-Hans") isEqual:@[Run(@"zh",@"2026")]]);
    assert([TIOVoiceTTSRuns(@"2026",nil) isEqual:@[Run(@"en",@"2026")]]);
    assert([TIOVoiceTTSRuns(@"",nil) isEqual:@[]]);
    assert([TIOVoiceTTSRuns(@"  12 apples",nil) isEqual:@[Run(@"en",@"12 apples")]]);
    NSArray *many=TIOVoiceTTSRuns(/*i18n:keep*/@"北京 Beijing Capital City 上海 Shanghai Pudong Area 广州 Guangzhou Tianhe District 深圳",nil);
    assert(many.count==1 && [many[0][@"lang"] isEqual:@"zh"]);

    NSDictionary *flo=Voice(@"com.apple.eloquence.en-US.Flo",@"en-US",@1,NO,NO,NO);
    NSDictionary *samantha=Voice(@"com.apple.voice.compact.en-US.Samantha",@"en-US",@1,NO,NO,YES);
    NSDictionary *daniel=Voice(@"com.apple.voice.enhanced.en-GB.Daniel",@"en-GB",@2,NO,NO,NO);
    NSDictionary *tingting=Voice(@"com.apple.voice.compact.zh-CN.Tingting",@"zh-CN",@1,NO,NO,NO);
    NSDictionary *sinji=Voice(@"com.apple.voice.compact.zh-HK.Sinji",@"zh-HK",@1,NO,NO,NO);
    NSDictionary *meijia=Voice(@"com.apple.voice.premium.zh-TW.Meijia",@"zh-TW",@3,NO,NO,NO);
    NSDictionary *bells=Voice(@"com.apple.speech.synthesis.voice.Bells",@"en-US",@1,YES,NO,NO);
    NSDictionary *personal=Voice(@"p.personal",@"en-US",@3,NO,YES,NO);
    NSArray *voices=@[flo,samantha,daniel,tingting,sinji,meijia,bells,personal];
    assert([TIOVoiceTTSPickVoice(voices,@"en-US") isEqual:samantha]);
    NSDictionary *ava=Voice(@"com.apple.voice.premium.en-US.Ava",@"en-US",@3,NO,NO,NO);
    assert([TIOVoiceTTSPickVoice([voices arrayByAddingObject:ava],@"en") isEqual:ava]);
    assert([TIOVoiceTTSPickVoice(voices,@"zh-Hans") isEqual:tingting]);
    assert([TIOVoiceTTSPickVoice(@[sinji,meijia],@"zh") isEqual:meijia]);
    assert(TIOVoiceTTSPickVoice(@[sinji],@"zh")==nil);
    assert([TIOVoiceTTSPickVoice(@[daniel,tingting,sinji,meijia],@"en") isEqual:daniel]);
    NSDictionary *underscored=Voice(@"underscore",@"en_US",@1,NO,NO,NO);
    assert([TIOVoiceTTSPickVoice(@[underscored],@"en") isEqual:underscored]);
    assert(TIOVoiceTTSPickVoice(@[],@"en")==nil);

    assert([TIOVoiceTTSStatusText(@"idle",YES,@"zh-Hans") isEqual:/*i18n:keep*/@"待命 · 蓝牙眼镜/耳机"]);
    assert([TIOVoiceTTSStatusText(@"speaking",NO,nil) isEqual:@"Speaking · No Bluetooth audio output"]);
    for(NSString *lang in @[@"zh-Hans",@"zh",@"ZH_CN"])
        assert([TIOVoiceTTSStatusText(@"done",YES,lang) hasPrefix:/*i18n:keep*/@"播放完成"]);
    assert([TIOVoiceTTSStatusText(@"done",YES,@"en-US") hasPrefix:@"Finished"]);
    assert([TIOVoiceTTSStatusText(@"done",YES,nil) hasPrefix:@"Finished"]);
    puts("PASS: voice tts text");
} return 0; }
