// WP8 legacy reference: baseline transport, with test-only symbol names.
#import <Foundation/Foundation.h>
typedef void(^TIOLegacyTMSubmitted)(BOOL,NSString *);
BOOL TIOLegacyTMIsScopedCall(NSString *,NSDictionary *);
@interface TIOLegacyTMTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TIOLegacyTMSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
