#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const TIOLangEnglish;
FOUNDATION_EXPORT NSString *const TIOLangChinese;
FOUNDATION_EXPORT NSString *const TIOUILanguagePrefKey;
FOUNDATION_EXPORT NSString *const TIOUILanguageDidChangeNotification;
FOUNDATION_EXPORT NSString *TIOUILanguage(void);
FOUNDATION_EXPORT NSString *TIOUILanguageOverride(void);
FOUNDATION_EXPORT void TIOSetUILanguageOverride(NSString *value);
FOUNDATION_EXPORT NSString *TIOResolveUILanguage(NSString *_Nullable override, NSString *_Nullable hostTag,
    NSArray<NSString *> *_Nullable bundleMatches, NSArray<NSString *> *_Nullable preferredLanguages);
FOUNDATION_EXPORT NSString *_Nullable TIOHostAppLanguageTag(NSUserDefaults *defaults, NSString *_Nullable *_Nullable matchedKey);
FOUNDATION_EXPORT NSString *TIOText(NSString *key) NS_FORMAT_ARGUMENT(1);
FOUNDATION_EXPORT NSString *TIOTextForLanguage(NSString *key, NSString *lang) NS_FORMAT_ARGUMENT(1);
FOUNDATION_EXPORT uint8_t TIOGlassesLanguageCode(NSString *lang);
FOUNDATION_EXPORT NSDictionary *TIOLanguageDiagnostics(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSArray<NSString *> *> *TIOStringTable(void);
FOUNDATION_EXPORT NSString *TIOLanguageForText(NSString *text, NSString *_Nullable fallback);
FOUNDATION_EXPORT NSUInteger TIOHanCount(NSString *text);
FOUNDATION_EXPORT NSString *TIOReplyLanguageInstruction(NSString *lang);
NS_ASSUME_NONNULL_END
