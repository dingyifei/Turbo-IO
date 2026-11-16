#import "VoiceTTSText.h"

NS_ASSUME_NONNULL_BEGIN
@interface TIOVoiceTTS : NSObject
@property(nonatomic,copy) NSString *fallbackLanguage;
@property(nonatomic,copy,nullable) void (^willBeginTurn)(void);
- (void)beginTurn;
- (void)appendFullText:(NSString *)text finished:(BOOL)finished;
- (void)cancel;
- (NSString *)status;
- (NSString *)statusForLanguage:(nullable NSString *)language;
- (NSString *)voiceSummaryForLanguage:(nullable NSString *)language;
+ (BOOL)bluetoothRouteActive;
@end
NS_ASSUME_NONNULL_END
