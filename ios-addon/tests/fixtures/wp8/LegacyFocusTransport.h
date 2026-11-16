// WP8 legacy reference: baseline transport, with test-only symbol names.
#import <Foundation/Foundation.h>
typedef void(^TIOLegacyTFSubmitted)(BOOL,NSString *);
BOOL TIOLegacyTFIsScopedCall(NSString *,NSDictionary *);
@interface TIOLegacyTFTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TIOLegacyTFSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
