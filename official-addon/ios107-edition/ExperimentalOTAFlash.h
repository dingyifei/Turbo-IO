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
// D5: YES only for the stock teleprompter's rayneonet_sendFile: exactly
// {deviceId, filePath, taskId}, filePath a regular file of 1 byte to 1 MiB (not a
// ZIP) at <container>/Library/Application Support/user_<digits>/teleprompter/<UUID>
// or <container>/Documents/user_<digits>/teleprompter/<UUID> with no symlink,
// taskId that UUID, and OTA stage 0. Flag-independent; both host profiles use it.
BOOL TIOStockTeleprompterSendAllowed(NSString *method, id args, NSUInteger otaStage);
// The same check against an explicit container (tests); the app uses NSHomeDirectory().
BOOL TIOStockTeleprompterSendAllowedIn(NSString *container, NSString *method, id args, NSUInteger otaStage);
BOOL TIOPhoneOTAReadAllowed(NSData *data);
void TIOOTAFlashObserveEvent(NSDictionary *event);
BOOL TIOOTAFlashAuthorize(NSError **error);
BOOL TIOOTAFlashCancel(void);
NSDictionary *TIOOTAFlashStatus(void);
BOOL TIOOTAFlashDisableAutoUpdate(void);
