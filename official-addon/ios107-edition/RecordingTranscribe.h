#if TIO_APPLE_AI
#import <Foundation/Foundation.h>
@interface TIORecordingTranscriber:NSObject
- (void)transcribeFile:(NSURL *)source language:(NSString *)language progress:(void(^)(NSString *stage,double fraction))progress completion:(void(^)(NSString *markdown,NSString *error))completion;
- (void)cancel;
@end
#endif
