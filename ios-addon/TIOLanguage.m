#import "TIOLanguage.h"
#import <os/lock.h>

#if defined(TIO_TEST_UI_LANGUAGE_ZH) && defined(TIO_TARGET_BUNDLE_ID)
#error TIO_TEST_UI_LANGUAGE_ZH must never be used in a shipping target
#endif

NSString *const TIOLangEnglish=@"en";
NSString *const TIOLangChinese=@"zh";
NSString *const TIOUILanguagePrefKey=@"uiLanguage";
NSString *const TIOUILanguageDidChangeNotification=@"TIOUILanguageDidChange";

static os_unfair_lock LanguageLock=OS_UNFAIR_LOCK_INIT;
// Only canonical constant strings are stored here. No Objective-C messages or
// callbacks occur under LanguageLock, including equality checks and defaults IO.
static NSString *CachedLanguage;
static NSString *LastResolvedLanguage;
static uint64_t LanguageGeneration;
#if TIO_TEST_UI_LANGUAGE_ZH
static NSString *TestOverride;
#endif

static NSString *NormalizedOverride(NSString *value) {
    if ([value isEqual:TIOLangEnglish]) return TIOLangEnglish;
    if ([value isEqual:TIOLangChinese]) return TIOLangChinese;
    return @"auto";
}
#if !TIO_TEST_UI_LANGUAGE_ZH
static NSUserDefaults *LanguagePreferences(void) {
    static NSUserDefaults *prefs;
    static dispatch_once_t once;
    dispatch_once(&once,^{
#if TIO_UI_PREVIEW
        prefs=[[NSUserDefaults alloc] initWithSuiteName:@"io.turboio.research.preview"];
#else
        prefs=[[NSUserDefaults alloc] initWithSuiteName:@"io.turboio.official-private-addon"];
#endif
    });
    return prefs;
}
#endif
static void InvalidateLanguage(void) {
    os_unfair_lock_lock(&LanguageLock);
    CachedLanguage=nil;
    LanguageGeneration++;
    os_unfair_lock_unlock(&LanguageLock);
}
static void ObserveLanguageInputs(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
        [center addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) { InvalidateLanguage(); }];
        [center addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) { InvalidateLanguage(); }];
    });
}
NSString *TIOResolveUILanguage(NSString *override, NSString *hostTag, NSArray<NSString *> *bundleMatches, NSArray<NSString *> *preferredLanguages) {
    NSString *choice=NormalizedOverride(override);
    if ([choice isEqual:TIOLangEnglish] || [choice isEqual:TIOLangChinese]) return choice;
    NSString *tag=hostTag ?: bundleMatches.firstObject ?: preferredLanguages.firstObject;
    return [tag.lowercaseString hasPrefix:@"zh"] ? TIOLangChinese : TIOLangEnglish;
}
NSString *TIOHostAppLanguageTag(NSUserDefaults *defaults, NSString **matchedKey) {
    if (matchedKey) *matchedKey=nil;
    id follows=[defaults objectForKey:@"flutter.language_app_follows_system"];
    if ([follows isKindOfClass:NSNumber.class] && [follows boolValue]) return nil;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once,^{ pattern=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8}){0,3}$" options:0 error:NULL]; });
    for (NSString *key in @[@"flutter.language_app",@"flutter.appLanguage",@"flutter.app_language",@"flutter.appLang"]) {
        id value=[defaults objectForKey:key];
        if (![value isKindOfClass:NSString.class]) continue;
        if ([value caseInsensitiveCompare:@"system"]==NSOrderedSame || [value caseInsensitiveCompare:@"auto"]==NSOrderedSame) continue;
        NSRange whole=NSMakeRange(0,[value length]);
        NSTextCheckingResult *match=[pattern firstMatchInString:value options:0 range:whole];
        // '$' may match before a final newline. Require the entire input range.
        if (!match || !NSEqualRanges(match.range,whole)) continue;
        if (matchedKey) *matchedKey=key;
        return value;
    }
    return nil;
}
NSString *TIOUILanguageOverride(void) {
#if TIO_TEST_UI_LANGUAGE_ZH
    os_unfair_lock_lock(&LanguageLock);
    NSString *value=TestOverride;
    os_unfair_lock_unlock(&LanguageLock);
    return value ?: @"auto";
#else
    return NormalizedOverride([LanguagePreferences() objectForKey:TIOUILanguagePrefKey]);
#endif
}
void TIOSetUILanguageOverride(NSString *value) {
    ObserveLanguageInputs();
    NSString *normalized=NormalizedOverride(value);
#if TIO_TEST_UI_LANGUAGE_ZH
    os_unfair_lock_lock(&LanguageLock);
    TestOverride=normalized;
    CachedLanguage=nil;
    LanguageGeneration++;
    os_unfair_lock_unlock(&LanguageLock);
#else
    [LanguagePreferences() setObject:normalized forKey:TIOUILanguagePrefKey];
    InvalidateLanguage();
#endif
}
NSString *TIOUILanguage(void) {
    ObserveLanguageInputs();
    for (;;) {
        os_unfair_lock_lock(&LanguageLock);
        NSString *cached=CachedLanguage;
        uint64_t generation=LanguageGeneration;
#if TIO_TEST_UI_LANGUAGE_ZH
        NSString *override=TestOverride;
#endif
        os_unfair_lock_unlock(&LanguageLock);
        if (cached) return cached;
#if TIO_TEST_UI_LANGUAGE_ZH
        NSString *resolved=override==TIOLangEnglish ? TIOLangEnglish : TIOLangChinese;
#else
        NSArray<NSString *> *preferred=NSLocale.preferredLanguages;
        NSArray<NSString *> *matches=[NSBundle preferredLocalizationsFromArray:@[@"en",@"zh-Hans",@"zh-Hant"] forPreferences:preferred];
        NSString *resolved=TIOResolveUILanguage(TIOUILanguageOverride(),TIOHostAppLanguageTag(NSUserDefaults.standardUserDefaults,NULL),matches,preferred);
#endif
        os_unfair_lock_lock(&LanguageLock);
        if (generation!=LanguageGeneration) { os_unfair_lock_unlock(&LanguageLock); continue; }
        cached=CachedLanguage;
        BOOL changed=NO;
        if (!cached) {
            CachedLanguage=resolved;
            changed=LastResolvedLanguage && LastResolvedLanguage!=resolved;
            LastResolvedLanguage=resolved;
            cached=resolved;
        }
        os_unfair_lock_unlock(&LanguageLock);
        if (changed) dispatch_async(dispatch_get_main_queue(),^{
            [NSNotificationCenter.defaultCenter postNotificationName:TIOUILanguageDidChangeNotification object:nil];
        });
        return cached;
    }
}
NSString *TIOTextForLanguage(NSString *key, NSString *lang) {
    if (!key.length) return key ?: @"";
    NSArray<NSString *> *row=TIOStringTable()[key];
    NSUInteger index=[lang isEqual:TIOLangEnglish] ? 0 : 1;
    return row.count>index ? row[index] : key;
}
NSString *TIOText(NSString *key) {
    if (!key.length) return key ?: @"";
    return TIOTextForLanguage(key,TIOUILanguage());
}
uint8_t TIOGlassesLanguageCode(NSString *lang) { return [lang isEqual:TIOLangChinese] ? 1 : 0; }
NSDictionary *TIOLanguageDiagnostics(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *hostKey=nil;
    NSString *hostTag=TIOHostAppLanguageTag(defaults,&hostKey);
    NSMutableArray<NSString *> *names=[NSMutableArray array];
    for (NSString *key in defaults.dictionaryRepresentation) {
        if ([key hasPrefix:@"flutter."] && ([key rangeOfString:@"lang" options:NSCaseInsensitiveSearch].location!=NSNotFound || [key rangeOfString:@"locale" options:NSCaseInsensitiveSearch].location!=NSNotFound)) [names addObject:key];
    }
    NSArray<NSString *> *preferred=NSLocale.preferredLanguages;
    NSArray<NSString *> *matches=[NSBundle preferredLocalizationsFromArray:@[@"en",@"zh-Hans",@"zh-Hant"] forPreferences:preferred];
    return @{@"override":TIOUILanguageOverride(),@"hostKey":hostKey ?: @"",@"hostTag":hostTag ?: @"",
        @"hostLanguageKeys":[names sortedArrayUsingSelector:@selector(compare:)],@"bundleMatch":matches.firstObject ?: @"",
        @"preferredLanguage":preferred.firstObject ?: @"",@"resolved":TIOUILanguage()};
}
