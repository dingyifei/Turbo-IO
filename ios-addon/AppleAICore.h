#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT void TAISetUILanguage(NSString *language);
FOUNDATION_EXPORT void TAISetLanguageProvider(NSString *(^_Nullable provider)(void));
FOUNDATION_EXPORT NSString *TAIText(NSString *english, NSString *chinese);
FOUNDATION_EXPORT BOOL TIOAppleShouldUseAppleMode(NSInteger mode, BOOL voiceTurn);
FOUNDATION_EXPORT BOOL TIOAppleShouldFallback(NSInteger mode, BOOL voiceTurn, BOOL enabled, BOOL failed, NSUInteger emittedLength);
FOUNDATION_EXPORT NSString *TIOAppleLanguageForText(NSString *text);
FOUNDATION_EXPORT NSString *TIOAppleInstructions(NSString *language, NSString *_Nullable aboutMe);
FOUNDATION_EXPORT NSString *TIOAppleErrorMessage(NSString *code);
FOUNDATION_EXPORT NSString *TIOAppleFallbackMarker(NSString *language);
FOUNDATION_EXPORT BOOL TIOTranscribeNeedsTranscode(NSString *extension);
FOUNDATION_EXPORT NSArray<NSString *> *_Nullable TIOTranscodeArguments(NSString *input, NSString *output);
FOUNDATION_EXPORT NSString *TIOTranscriptLocaleFromProbe(NSString *probe);
FOUNDATION_EXPORT NSString *TIOTranscriptMarkdown(NSArray<NSDictionary *> *segments);
NS_ASSUME_NONNULL_END
