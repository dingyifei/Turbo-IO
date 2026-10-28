#import <Foundation/Foundation.h>
typedef void(^TIOGlassesFileSubmitted)(BOOL ok,NSString *nativeTask);
typedef BOOL(^TIOGlassesFileValidator)(NSData *packet);
FOUNDATION_EXPORT BOOL TIOGlassesFileIsScopedCall(NSString *method,NSDictionary *args);
@interface TIOGlassesFileTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call fileName:(NSString *)fileName validator:(TIOGlassesFileValidator)validator;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TIOGlassesFileSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
