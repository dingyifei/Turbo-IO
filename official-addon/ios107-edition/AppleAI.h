#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TIOAppleAILoaded(void);
FOUNDATION_EXPORT NSDictionary *TIOAppleAILoadStatus(void);
FOUNDATION_EXPORT NSDictionary *TIOAppleModelAvailability(void);
FOUNDATION_EXPORT id _Nullable TIOAppleModelRespond(NSString *question, NSArray *history, NSString *instructions, NSString *language, BOOL stream, void(^update)(NSString *text, BOOL done, NSString *_Nullable code));
FOUNDATION_EXPORT void TIOAppleAIProbe(void(^completion)(NSDictionary *report));
FOUNDATION_EXPORT NSString *TIOAppleAIStatusLine(void);
FOUNDATION_EXPORT UIViewController *TIOAppleAIController(void);
NS_ASSUME_NONNULL_END
