#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TIOAppleAILoaded(void);
FOUNDATION_EXPORT NSDictionary *TIOAppleAILoadStatus(void);
FOUNDATION_EXPORT NSDictionary *TIOAppleModelAvailability(void);
FOUNDATION_EXPORT id _Nullable TIOAppleModelRespond(NSString *question, NSArray *history, NSString *instructions, NSString *language, BOOL stream, void(^update)(NSString *text, BOOL done, NSString *_Nullable code));
FOUNDATION_EXPORT void TIOAppleAIProbe(void(^completion)(NSDictionary *report));
FOUNDATION_EXPORT NSString *TIOAppleAIStatusLine(void);
FOUNDATION_EXPORT UIViewController *TIOAppleAIController(void);
FOUNDATION_EXPORT void TIOAppleSpeechStatus(NSString *locale, void(^completion)(NSDictionary *));
FOUNDATION_EXPORT void TIOAppleSpeechPrepare(NSString *locale, void(^progress)(double), void(^completion)(NSString *_Nullable));
FOUNDATION_EXPORT id _Nullable TIOAppleSpeechTranscribe(NSURL *file, NSString *locale, void(^progress)(double), void(^completion)(NSString *_Nullable, NSString *_Nullable));
NS_ASSUME_NONNULL_END
