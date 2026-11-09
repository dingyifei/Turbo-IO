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
// Also: no ZIP end-of-central-directory signature in the last 65557 bytes, deviceId
// at most 256 characters, at most 20 digits after user_, plain Foundation objects only.
BOOL TIOStockTeleprompterSendAllowed(NSString *method, id args, NSUInteger otaStage);
// The same check against an explicit container (tests); the app uses NSHomeDirectory().
BOOL TIOStockTeleprompterSendAllowedIn(NSString *container, NSString *method, id args, NSUInteger otaStage);
// The checked snapshot of args (a fresh immutable dictionary of fresh strings,
// read once from plain Foundation objects) when allowed, otherwise nil. Never throws.
NSDictionary *TIOStockTeleprompterSendSnapshotIn(NSString *container, NSString *method, id args, NSUInteger otaStage);
// A new FlutterMethodCall from the literal method name and that snapshot, or nil.
id TIOStockTeleprompterForwardCall(NSDictionary *snapshot);
// TIOOTAFlashBlockCall, and when the call passes as the stock teleprompter send,
// *teleprompterArgs (if given) receives the snapshot the hook must forward instead
// of the caller's arguments; it is nil for every other call.
BOOL TIOOTAFlashBlockCallSnapshot(id call, NSDictionary *_Nullable *_Nullable teleprompterArgs);
BOOL TIOPhoneOTAReadAllowed(NSData *data);
// Full 1.0.11 host (profile ios1011, C15): TMG flashing is disarmed until armed.
// TIOOTAFlashBlockCall delegates to TIOOTADisarmedBlockCall there while disarmed,
// whatever TIO_* flags the build has; armed, it takes the 1.0.7 gate path.
FOUNDATION_EXPORT NSString *const TIOOTAArmGuardMarker;
// YES on the full 1.0.11 host: its pinned image with the ios1011 profile marker, or either
// of its Info.plist markers alone. NO on the download-only and the 1.0.7 hosts.
BOOL TIOOTAArmRequired(void);
// While disarmed: business 9 passes only the empty reads 1, 2, 11 and the size query 3 for the bundled ZIP.
BOOL TIOOTADisarmedReadAllowed(NSData *data);
BOOL TIOOTADisarmedBlockCall(id call);
// The arm record (addon prefs, bound to this addon image). Arm needs the full host, its
// routing marker, the pinned image and transfer protection; it authorizes nothing by itself.
BOOL TIOOTAFlashArmed(void);
BOOL TIOOTAFlashArm(NSError **error);
// Refused (NO) while a transfer runs (gate stage 2); otherwise revokes a stage 1 grant and clears the record.
BOOL TIOOTAFlashDisarm(void);
// armRequired, armed, armedForTransfer (armed plus flash build, host marker and image), armedAt.
NSDictionary *TIOOTAFlashArmStatus(void);
void TIOOTAFlashObserveEvent(NSDictionary *event);
BOOL TIOOTAFlashAuthorize(NSError **error);
BOOL TIOOTAFlashCancel(void);
NSDictionary *TIOOTAFlashStatus(void);
BOOL TIOOTAFlashDisableAutoUpdate(void);
