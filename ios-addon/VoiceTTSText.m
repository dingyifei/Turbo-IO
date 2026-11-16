#import "VoiceTTSText.h"
NSInteger TIOVoiceTTSSpeedStep(NSUserDefaults *prefs){id value=[prefs objectForKey:@"ttsSpeedStep"];if(![value isKindOfClass:NSNumber.class]||[value doubleValue]!=[value integerValue]||[value integerValue]<0||[value integerValue]>4)return 2;return [value integerValue];}
double TIOVoiceTTSSpeedMultiplier(NSUserDefaults *prefs){static const double rates[]={.9,1.,1.2,1.35,1.5};return rates[TIOVoiceTTSSpeedStep(prefs)];}

static BOOL TIOScriptPeriodIsStop(NSString *text, NSUInteger index, BOOL final) {
    if(index<3)return NO;
    if(index+1<text.length) {
        if(![NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[text characterAtIndex:index+1]])return NO;
    } else if(!final)return NO;
    NSUInteger start=index;
    while(start>0) {
        unichar c=[text characterAtIndex:start-1];
        if(c!='.'&&![NSCharacterSet.letterCharacterSet characterIsMember:c])break;
        start--;
    }
    NSString *word=[[text substringWithRange:NSMakeRange(start,index-start)] lowercaseString];
    NSArray *abbreviations=@[@"mr",@"mrs",@"ms",@"dr",@"prof",@"st",@"vs",@"jr",@"sr",@"e.g",@"i.e"];
    return !(word.length==1||[abbreviations containsObject:word]);
}

NSString *TIOVoiceTTSChunk(NSString *pending, BOOL final, NSUInteger *consumed) {
    if(consumed)*consumed=0;
    if(![pending isKindOfClass:NSString.class]||!pending.length)return nil;
    NSUInteger limit=MIN(pending.length,180),cut=NSNotFound;
    NSCharacterSet *stop=[NSCharacterSet characterSetWithCharactersInString:/*i18n:keep*/@"。！？!?；;\n…"];
    NSCharacterSet *soft=[NSCharacterSet characterSetWithCharactersInString:/*i18n:keep*/@"，,、：:"];
    for(NSUInteger i=0;i<limit;i++) {
        unichar c=[pending characterAtIndex:i];
        if(([stop characterIsMember:c]&&i>=3)||(c=='.'&&TIOScriptPeriodIsStop(pending,i,final))){cut=i+1;break;}
        if((i>=65&&[soft characterIsMember:c])||(i>=120&&c==' ')){cut=i+1;break;}
    }
    if(cut==NSNotFound){if(limit>=140)cut=limit;else if(final)cut=limit;else return nil;}
    if(cut<pending.length&&cut>0){unichar a=[pending characterAtIndex:cut-1],b=[pending characterAtIndex:cut];
        if(a>=0xD800&&a<=0xDBFF&&b>=0xDC00&&b<=0xDFFF)cut++;}
    if(consumed)*consumed=cut;
    return [[pending substringToIndex:cut] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSArray<NSDictionary<NSString *,NSString *> *> *TIOVoiceTTSRuns(NSString *chunk, NSString *fallbackLanguage) {
    NSString *text=[chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length)return @[];
    BOOL hasHan=NO,hasLatin=NO;
    NSMutableArray<NSMutableDictionary *> *runs=[NSMutableArray new];
    NSMutableString *leading=[NSMutableString new];
    for(NSUInteger i=0;i<text.length;) {
        NSRange range=[text rangeOfComposedCharacterSequenceAtIndex:i];
        unichar c=[text characterAtIndex:i];
        BOOL han=TIOScriptIsHan(c),latin=TIOScriptIsLatinLetter(c);
        hasHan|=han;hasLatin|=latin;
        NSString *part=[text substringWithRange:range],*lang=han?@"zh":latin?@"en":nil;
        NSMutableDictionary *current=runs.lastObject;
        if(!lang) {
            if(current)[current[@"text"] appendString:part];
            else [leading appendString:part];
        } else if([current[@"lang"] isEqual:lang]) {
            [current[@"text"] appendString:part];
        } else {
            NSMutableString *runText=[NSMutableString stringWithString:leading];
            [runText appendString:part];[leading setString:@""];
            [runs addObject:[@{@"lang":lang,@"text":runText} mutableCopy]];
        }
        i=NSMaxRange(range);
    }
    if(!hasHan)return @[@{@"lang":hasLatin?@"en":(TIOScriptLanguageIsChinese(fallbackLanguage)?@"zh":@"en"),@"text":text}];
    for(NSMutableDictionary *run in runs) {
        if(![run[@"lang"] isEqual:@"en"])continue;
        NSString *runText=run[@"text"];
        NSUInteger words=0,letters=0;BOOL inWord=NO;
        for(NSUInteger i=0;i<runText.length;i++) {
            BOOL latin=TIOScriptIsLatinLetter([runText characterAtIndex:i]);
            if(latin){letters++;if(!inWord)words++;}inWord=latin;
        }
        if(words<3&&letters<12)run[@"lang"]=@"zh";
    }
    NSMutableArray<NSMutableDictionary *> *merged=[NSMutableArray new];
    for(NSDictionary *run in runs) {
        NSMutableDictionary *last=merged.lastObject;
        if([last[@"lang"] isEqual:run[@"lang"]])[last[@"text"] appendString:run[@"text"]];
        else [merged addObject:[@{@"lang":run[@"lang"],@"text":[run[@"text"] mutableCopy]} mutableCopy]];
    }
    NSMutableArray *result=[NSMutableArray new];
    for(NSDictionary *run in merged) {
        NSString *runText=[run[@"text"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(runText.length)[result addObject:@{@"lang":run[@"lang"],@"text":runText}];
    }
    return result.count>6?@[@{@"lang":@"zh",@"text":text}]:result;
}

static NSUInteger TIOScriptVoiceTier(NSDictionary *voice, BOOL chinese) {
    NSString *lang=[[voice[@"lang"] stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
    NSArray *tiers=chinese?@[@"zh-cn",@"zh-tw"]:@[@"en-us",@"en-gb",@"en-au",@"en-ie",@"en-za",@"en-in"];
    NSUInteger tier=[tiers indexOfObject:lang];
    if(tier==NSNotFound&&!chinese&&[lang hasPrefix:@"en-"])return tiers.count;
    return tier;
}
NSDictionary *TIOVoiceTTSPickVoice(NSArray<NSDictionary *> *voices, NSString *language) {
    BOOL chinese=TIOScriptLanguageIsChinese(language);
    NSMutableArray *eligible=[NSMutableArray new];
    for(NSDictionary *voice in voices) {
        if([voice[@"novelty"] boolValue]||[voice[@"personal"] boolValue]||
            [voice[@"id"] containsString:@"speech.synthesis.voice."]||TIOScriptVoiceTier(voice,chinese)==NSNotFound)continue;
        [eligible addObject:voice];
    }
    [eligible sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger at=TIOScriptVoiceTier(a,chinese),bt=TIOScriptVoiceTier(b,chinese);
        if(at!=bt)return at<bt?NSOrderedAscending:NSOrderedDescending;
        NSInteger aq=[a[@"quality"] integerValue],bq=[b[@"quality"] integerValue];
        if(aq!=bq)return aq>bq?NSOrderedAscending:NSOrderedDescending;
        BOOL ae=[a[@"id"] containsString:@".eloquence."],be=[b[@"id"] containsString:@".eloquence."];
        if(ae!=be)return ae?NSOrderedDescending:NSOrderedAscending;
        BOOL ad=[a[@"systemDefault"] boolValue],bd=[b[@"systemDefault"] boolValue];
        if(ad!=bd)return ad?NSOrderedAscending:NSOrderedDescending;
        return [a[@"id"] compare:b[@"id"]];
    }];
    return eligible.firstObject;
}

NSString *TIOVoiceTTSStatusText(NSString *state, BOOL bluetooth, NSString *language) {
    BOOL chinese=TIOScriptLanguageIsChinese(language);
    NSDictionary *states=@{
        @"idle":@[@"Idle",/*i18n:keep*/@"待命"],
        @"speaking":@[@"Speaking",/*i18n:keep*/@"本机正在朗读"],
        @"done":@[@"Finished",/*i18n:keep*/@"播放完成"],
        @"interrupted":@[@"Interrupted",/*i18n:keep*/@"本机朗读已中断"],
        @"noAudio":@[@"Glasses audio not connected",/*i18n:keep*/@"眼镜音频未连接"],
        @"notAppended":@[@"Text not appended",/*i18n:keep*/@"TTS 文本未追加"]};
    NSString *label=states[state]?[states[state] objectAtIndex:chinese?1:0]:state;
    NSString *route=bluetooth?(chinese?/*i18n:keep*/@"蓝牙眼镜/耳机":@"Bluetooth glasses/headphones"):
        (chinese?/*i18n:keep*/@"未连接蓝牙音频输出":@"No Bluetooth audio output");
    return [NSString stringWithFormat:@"%@ · %@",label,route];
}
