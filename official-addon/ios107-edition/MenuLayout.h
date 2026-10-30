#import <Foundation/Foundation.h>
/* Capability bits (diagnostics.h TD_CAP_*) the connected glasses reported in their last validated status sample, 0 when
 * none is known for the current peer. TMG7 and older glasses never set TD_CAP_MENU_CAROUSEL (the TMG8 bit). */
typedef uint32_t (^TIOGlassesCapsSource)(void);
/* Installed once by the diagnostics bridge; the four-argument initializer below reads it. */
void TIOMenuLayoutSetCapsSource(TIOGlassesCapsSource source);

@interface TIOMenuLayoutLink:NSObject
@property(nonatomic,readonly) BOOL busy,ready;
/* The stored layout the glasses confirmed: 1 carousel (TMG8 only), 2 or 3 grid rows; 0 when unknown. */
@property(nonatomic,readonly) NSUInteger rows;
@property(nonatomic,readonly) NSString *note;
/* YES when the connected glasses report the TMG8 caps bit. The carousel (layout 1) is offered and written only then. */
@property(nonatomic,readonly) BOOL glassesReportTMG8Caps;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock caps:(TIOGlassesCapsSource)caps send:(BOOL(^)(NSData *))send;
- (void)query:(void(^)(void))done;
- (void)choose:(NSUInteger)rows done:(void(^)(void))done;
- (BOOL)consume:(NSDictionary *)event;
- (void)cancel;
@end
BOOL TIOMenuLayoutIsReply(NSDictionary *);
BOOL TIOMenuLayoutConsume(NSDictionary *);

// Same one-shot transaction ownership as row settings; no optimistic save.
@interface TIOTileLayoutLink:NSObject
@property(nonatomic,readonly) BOOL busy,ready;
@property(nonatomic,readonly) NSArray<NSNumber *> *order;
@property(nonatomic,readonly) NSUInteger hide;
@property(nonatomic,readonly) NSString *note;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send;
- (void)query:(void(^)(void))done;
- (void)saveOrder:(NSArray<NSNumber *> *)order hide:(NSUInteger)hide done:(void(^)(void))done;
- (BOOL)consume:(NSDictionary *)event;
- (void)cancel;
@end
BOOL TIOTileLayoutIsReply(NSDictionary *);
