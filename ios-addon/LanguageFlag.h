#import <Foundation/Foundation.h>
#include <stdint.h>
// Main-queue only. The clock is monotonic seconds; send reports submission, not ACK.
@interface TIOLanguageFlagLink : NSObject
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) NSDictionary *status;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send;
- (void)pushLanguage:(uint8_t)lang;
// Explicit user retry; automatic pushes keep their existing suppression.
- (void)syncLanguage:(uint8_t)lang;
- (BOOL)consume:(NSDictionary *)event;
// Drops in-flight and queued values. A later explicit push is a new attempt.
- (void)cancel;
@end
BOOL TIOLanguageFlagIsReply(NSDictionary *);
BOOL TIOLanguageFlagConsume(NSDictionary *);
void TIOLanguageFlagStart(void);
NSDictionary *TIOLanguageFlagStatus(void);

void TIOLanguageFlagSync(void);
