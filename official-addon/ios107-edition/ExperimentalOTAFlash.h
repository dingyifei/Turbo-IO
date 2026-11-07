#import <Foundation/Foundation.h>
// Separate opt-in build. PREPARE-02 cannot enable this gate.
NSDictionary *TIOOTAFrame(NSData *data);
BOOL TIOOTAAutoUpdateDisabled(NSDictionary *preferences);
@interface TIOOTAFlashGate:NSObject
- (BOOL)prepareDirectory:(NSURL *)directory device:(NSString *)device uptime:(NSTimeInterval)now error:(NSError **)error;
- (BOOL)allows:(NSData *)payload device:(NSString *)device uptime:(NSTimeInterval)now;
- (NSDictionary *)status;
- (BOOL)cancel;
@end
BOOL TIOOTAFlashBuild(void);
NSUInteger TIOOTAScopedSenderCount(void);
BOOL TIOOTAFlashProtected(void);
BOOL TIOOTAFlashBlockCall(id call);
// Download-only 1.0.11/259 host: TIOOTAFlashBlockCall delegates to
// TIOOTADownloadOnlyBlockCall there, whatever TIO_* flags the build has.
FOUNDATION_EXPORT NSString *const TIOOTADownloadOnlyGuardMarker;
BOOL TIOOTADownloadOnlyHost(void);
BOOL TIOOTADownloadOnlyBlockCall(id call);
BOOL TIOOTAFileCallBlocked(NSString *method, BOOL scopedImage, NSUInteger stage);
BOOL TIOPhoneOTAReadAllowed(NSData *data);
void TIOOTAFlashObserveEvent(NSDictionary *event);
BOOL TIOOTAFlashAuthorize(NSError **error);
BOOL TIOOTAFlashCancel(void);
NSDictionary *TIOOTAFlashStatus(void);
BOOL TIOOTAFlashDisableAutoUpdate(void);
