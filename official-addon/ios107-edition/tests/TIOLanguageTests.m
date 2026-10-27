#import "TIOLanguage.h"
#include <assert.h>
#include <stdio.h>

static void Equal(NSString *actual, NSString *expected) {
    if (![actual isEqualToString:expected]) fprintf(stderr,"expected=%s actual=%s\n",expected.UTF8String,actual.UTF8String);
    assert([actual isEqualToString:expected]);
}
static void DrainMain(void) {
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:0.025];
    while ([until timeIntervalSinceNow]>0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
}
static void Resolution(void) {
    // A lower-priority Chinese value must not override an earlier English/non-Chinese value.
    Equal(TIOResolveUILanguage(@"en",@"zh-Hans-CN",@[@"zh-Hant"],@[@"zh-HK"]),@"en");
    Equal(TIOResolveUILanguage(@"zh",@"en",@[@"en"],@[@"en"]),@"zh");
    Equal(TIOResolveUILanguage(@"auto",@"zh-Hans-CN",@[@"en"],@[@"en"]),@"zh");
    Equal(TIOResolveUILanguage(nil,@"de",@[@"zh-Hans"],@[@"zh"]),@"en");
    Equal(TIOResolveUILanguage(nil,nil,nil,nil),@"en");
    Equal(TIOResolveUILanguage(nil,nil,@[],@[@"zh-HK"]),@"zh");
    Equal(TIOResolveUILanguage(nil,nil,@[@"en",@"zh-Hans"],@[@"zh"]),@"en");
    Equal(TIOResolveUILanguage(nil,nil,@[@"ZH-Hant"],@[@"en"]),@"zh");
    Equal(TIOResolveUILanguage(@"invalid",@"",@[@"zh-Hans"],@[@"zh"]),@"en");
}
static void HostProbe(void) {
    NSString *suite=@"io.turboio.test.lang";
    NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:suite];
    [d removePersistentDomainForName:suite];
    @try {
        NSString *key=@"stale";
        assert(TIOHostAppLanguageTag(d,&key)==nil && key==nil);
        [d setObject:@"zh-Hans-CN" forKey:@"flutter.appLanguage"];
        Equal(TIOHostAppLanguageTag(d,&key),@"zh-Hans-CN"); Equal(key,@"flutter.appLanguage");
        [d setObject:@"en_US" forKey:@"flutter.language_app"];
        Equal(TIOHostAppLanguageTag(d,&key),@"en_US"); Equal(key,@"flutter.language_app");
        for (id junk in @[@23,@[@"zh"],@"",@" auto",@"zh-",@"zh-Hans-123456789",@"zh-Hans-CN-x-y",@"zh\nen",@"zh\n",@"system",@"auto"]) {
            [d setObject:junk forKey:@"flutter.language_app"];
            Equal(TIOHostAppLanguageTag(d,&key),@"zh-Hans-CN"); Equal(key,@"flutter.appLanguage");
        }
        [d setObject:@YES forKey:@"flutter.language_app_follows_system"];
        assert(TIOHostAppLanguageTag(d,&key)==nil && key==nil);
        [d setObject:@NO forKey:@"flutter.language_app_follows_system"];
        [d removeObjectForKey:@"flutter.appLanguage"];
        [d setObject:@"zh_Hant_TW" forKey:@"flutter.app_language"];
        [d setObject:@"en" forKey:@"flutter.appLang"];
        Equal(TIOHostAppLanguageTag(d,NULL),@"zh_Hant_TW");
        [d removeObjectForKey:@"flutter.app_language"];
        Equal(TIOHostAppLanguageTag(d,NULL),@"en");
    } @finally { [d removePersistentDomainForName:suite]; }
}
static void Text(void) {
    Equal(TIOTextForLanguage(@"missing.wp1.language.test",@"en"),@"missing.wp1.language.test");
    Equal(TIOTextForLanguage(@"missing.wp1.language.test",@"zh"),@"missing.wp1.language.test");
    Equal(TIOText(@""),@"");
    // nil is accepted at runtime for callers crossing untyped boundaries.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    Equal(TIOText(nil),@""); Equal(TIOTextForLanguage(nil,@"en"),@"");
#pragma clang diagnostic pop
    Equal(TIOLanguageForText(@"Hello there",nil),@"en");
    Equal(TIOLanguageForText(/*i18n:keep*/@"你好",nil),@"zh");
    Equal(TIOLanguageForText(@"OK",nil),@"en");
    Equal(TIOLanguageForText(/*i18n:keep*/@"打开 Maps 导航",nil),@"zh");
    Equal(TIOLanguageForText(/*i18n:keep*/@"中 one two",nil),@"en");
    Equal(TIOLanguageForText(/*i18n:keep*/@"中 one",nil),@"zh");
    Equal(TIOLanguageForText(@"",@"en"),@"en");
    Equal(TIOLanguageForText(@"123!?",@"zh"),@"zh");
    Equal(TIOLanguageForText(@"123!?",nil),TIOUILanguage());
    NSString *mixed=TIOLanguageForText(/*i18n:keep*/@"Please 打开 Apple Maps 导航",nil);
    assert(([@[@"en",@"zh"] containsObject:mixed]));
    assert(TIOHanCount(@"A\u3400\u4DBF\u4E00\u9FFF\uF900\uFAFF\U00020000\U0002FFFFZ")==8);
    assert(TIOHanCount(@"\u33FF\u4DC0\uFA00\uFB00\U0001FFFF\U00030000")==1);
    unichar invalid[]={0xD840,'A',0xDC00};
    assert(TIOHanCount([NSString stringWithCharacters:invalid length:3])==0);
    assert(TIOGlassesLanguageCode(@"zh")==1 && TIOGlassesLanguageCode(@"en")==0 && TIOGlassesLanguageCode(@"de")==0);
    Equal(TIOReplyLanguageInstruction(@"zh"),@"Reply in Simplified Chinese.");
    Equal(TIOReplyLanguageInstruction(@"en"),@"Reply in English.");
}
static void TestOverrideAndCache(void) {
#if TIO_TEST_UI_LANGUAGE_ZH
#if TIO_UI_PREVIEW
    NSString *suite=@"io.turboio.research.preview";
#else
    NSString *suite=@"io.turboio.official-private-addon";
#endif
    NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:suite];
    NSDictionary *before=[prefs persistentDomainForName:suite];
    Equal(TIOUILanguageOverride(),@"auto"); Equal(TIOUILanguage(),@"zh");
    __block NSUInteger changes=0;
    id observer=[[NSNotificationCenter defaultCenter] addObserverForName:TIOUILanguageDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        assert(NSThread.isMainThread); changes++; assert(TIOUILanguage().length==2);
    }];
    @try {
        TIOSetUILanguageOverride(@"en"); Equal(TIOUILanguageOverride(),@"en");
        DrainMain(); assert(changes==0); // Invalidation is lazy, never a setter notification.
        Equal(TIOUILanguage(),@"en"); DrainMain(); assert(changes==1);
        TIOSetUILanguageOverride(@"en"); Equal(TIOUILanguage(),@"en"); DrainMain(); assert(changes==1);
        [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        Equal(TIOUILanguage(),@"en"); DrainMain(); assert(changes==1);
        [[NSNotificationCenter defaultCenter] postNotificationName:NSCurrentLocaleDidChangeNotification object:nil];
        Equal(TIOUILanguage(),@"en"); DrainMain(); assert(changes==1);
        TIOSetUILanguageOverride(@"auto"); Equal(TIOUILanguage(),@"zh"); DrainMain(); assert(changes==2);
        TIOSetUILanguageOverride(@"invalid"); Equal(TIOUILanguageOverride(),@"auto"); Equal(TIOUILanguage(),@"zh"); DrainMain(); assert(changes==2);
        dispatch_apply(64,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i) { Equal(TIOUILanguage(),@"zh"); });
        NSDictionary *after=[prefs persistentDomainForName:suite];
        assert((before==nil && after==nil) || [before isEqual:after]);
        NSDictionary *diag=TIOLanguageDiagnostics();
        Equal(diag[@"resolved"],@"zh"); Equal(diag[@"override"],@"auto");
        for (NSString *key in diag[@"hostLanguageKeys"]) { assert([key hasPrefix:@"flutter."]); assert([key rangeOfString:@"lang" options:NSCaseInsensitiveSearch].location!=NSNotFound || [key rangeOfString:@"locale" options:NSCaseInsensitiveSearch].location!=NSNotFound); }
    } @finally { [[NSNotificationCenter defaultCenter] removeObserver:observer]; TIOSetUILanguageOverride(@"auto"); }
#endif
}
int main(void) { @autoreleasepool {
    Resolution(); HostProbe(); Text(); TestOverrideAndCache();
    puts("TIOLanguageTests: PASS");
} return 0; }
