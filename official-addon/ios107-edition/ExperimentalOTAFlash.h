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
// Download-only 1.0.21/1 host: TIOOTAFlashBlockCall delegates to
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
// Dry-run bookkeeping after a refusal: records the refused business-9 frame's shape for
// TIOOTAFlashStatus (refusedFrames, lastRefusedFrame). Never changes a verdict; never throws.
void TIOOTAFlashNoteRefused(id call);
// Full 1.0.21 host (profile ios1021): TIOOTAFlashBlockCall sends every business-9 frame through
// the one gate there, whatever TIO_* flags the build has. At stage 0 the gate passes only the empty
// reads 1, 2, 11 and the size query 3 for the bundled ZIP; types 4 to 7 need TIOOTAFlashAuthorize.
// The 1021-full packager requires this marker in the addon.
FOUNDATION_EXPORT NSString *const TIOOTAFullHostGuardMarker;
// YES on the full 1.0.21 host: the pinned image with its profile marker, or the profile marker alone.
// NO on the download-only host and on any other build.
BOOL TIOOTAFullHost(void);
void TIOOTAFlashObserveEvent(NSDictionary *event);
// Stage 1 for 15 minutes: needs the exact full host and its pinned image, the feed, the hook protection,
// the interlocks, Auto Update read as off, an accepted version read, and every pinned member in the folder.
BOOL TIOOTAFlashAuthorize(NSError **error);
BOOL TIOOTAFlashCancel(void);
NSDictionary *TIOOTAFlashStatus(void);
BOOL TIOOTAFlashDisableAutoUpdate(void);
