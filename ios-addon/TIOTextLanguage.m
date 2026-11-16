#import "TIOLanguage.h"
#import <NaturalLanguage/NaturalLanguage.h>

static uint32_t NextScalar(NSString *text, NSUInteger *offset) {
    unichar first=[text characterAtIndex:(*offset)++];
    if (first>=0xD800 && first<=0xDBFF && *offset<text.length) {
        unichar second=[text characterAtIndex:*offset];
        if (second>=0xDC00 && second<=0xDFFF) { (*offset)++; return 0x10000+((first-0xD800)<<10)+(second-0xDC00); }
    }
    return first;
}
static BOOL IsHan(uint32_t c) {
    return (c>=0x3400 && c<=0x4DBF) || (c>=0x4E00 && c<=0x9FFF) ||
        (c>=0xF900 && c<=0xFAFF) || (c>=0x20000 && c<=0x2FFFF);
}
NSUInteger TIOHanCount(NSString *text) {
    NSUInteger count=0;
    for (NSUInteger offset=0;offset<text.length;) if (IsHan(NextScalar(text,&offset))) count++;
    return count;
}
NSString *TIOLanguageForText(NSString *text, NSString *fallback) {
    NSUInteger han=TIOHanCount(text),latinWords=0;
    BOOL inWord=NO;
    for (NSUInteger offset=0;offset<text.length;) {
        uint32_t c=NextScalar(text,&offset);
        BOOL latin=(c>='A' && c<='Z') || (c>='a' && c<='z');
        if (latin && !inWord) latinWords++;
        inWord=latin;
    }
    if (!han && !latinWords) return fallback ?: TIOUILanguage();
    if (!latinWords) return TIOLangChinese;
    if (!han) return TIOLangEnglish;
    if (text.length>=12) {
        NLLanguageRecognizer *recognizer=[NLLanguageRecognizer new];
        recognizer.languageConstraints=@[NLLanguageEnglish,NLLanguageSimplifiedChinese,NLLanguageTraditionalChinese];
        [recognizer processString:text];
        NSDictionary<NLLanguage,NSNumber *> *hypotheses=[recognizer languageHypothesesWithMaximum:1];
        NLLanguage top=hypotheses.allKeys.firstObject;
        if (top && [hypotheses[top] doubleValue]>=0.6) {
            if ([top hasPrefix:@"zh"]) return TIOLangChinese;
            if ([top isEqual:NLLanguageEnglish]) return TIOLangEnglish;
        }
    }
    return han>=latinWords ? TIOLangChinese : TIOLangEnglish;
}
NSString *TIOReplyLanguageInstruction(NSString *lang) {
    return [lang isEqual:TIOLangChinese] ? @"Reply in Simplified Chinese." : @"Reply in English.";
}
