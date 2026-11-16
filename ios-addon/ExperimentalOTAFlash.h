#import <Foundation/Foundation.h>
// Separate opt-in build. PREPARE-02 cannot enable this gate.
NSDictionary *TIOOTAFrame(NSData *data);
BOOL TIOOTAAutoUpdateDisabled(NSDictionary *preferences);
@interface TIOOTAFlashGate:NSObject
// Stage 0 to 1. Captures the package selected at this moment (TIOOTASelectedPackage): its members read from the
// folder against its member pins, its manifest, its ZIP size (type 3) and its OtaVersion (type 5). From stage 1 on,
// every frame is compared with that capture only.
- (BOOL)prepareDirectory:(NSURL *)directory device:(NSString *)device uptime:(NSTimeInterval)now error:(NSError **)error;
// The same, refused unless the package at index is still the selected one at the moment of the capture.
- (BOOL)prepareDirectory:(NSURL *)directory package:(NSUInteger)index device:(NSString *)device uptime:(NSTimeInterval)now error:(NSError **)error;
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
// Stores the device and the reported OsVersion of the last type-1 reply, only when the last update is confirmed and
// at least one package accepts that version; every type-1 reply and every disconnect call clears the previous read.
void TIOOTAFlashObserveEvent(NSDictionary *event);
// Stage 1 for 15 minutes: needs the exact full host and its pinned image, the feed, the hook protection,
// the interlocks, Auto Update read as off, a version read that the selected package accepts, and every member
// of the selected package in the folder.
BOOL TIOOTAFlashAuthorize(NSError **error);
// The package the owner picked in the wizard: one in-memory selection for the process, the first package (the
// default) at every launch; nothing is stored. TIOOTASelectPackage is the only way it changes. It is refused once a
// transfer has started (stage 2 or 3); at stage 0 or 1 it cancels a stage-1 authorization, and the feed's download
// window and every cached check made for the previous selection are dropped (TIOOTASelectionGeneration counts the
// changes). Nothing else switches it: not the folder's contents, not a version read, not a feed request.
NSUInteger TIOOTASelectedPackageIndex(void);
NSDictionary *TIOOTASelectedPackage(void);
NSUInteger TIOOTASelectionGeneration(void);
BOOL TIOOTASelectPackage(NSUInteger index, NSError **error);
// The selected package's fields, for messages and tests (sizes as unsigned int, like the old literal pins). The gate
// never reads these: it reads the selected package at stage 0 and its capture from stage 1 on.
#define TIO_FW_NAME ((NSString *)TIOOTASelectedPackage()[@"name"])
#define TIO_FW_ZIP_BYTES ((unsigned int)[TIOOTASelectedPackage()[@"zipBytes"] unsignedIntegerValue])
#define TIO_FW_ZIP_SHA256 ((NSString *)TIOOTASelectedPackage()[@"zipSHA256"])
#define TIO_FW_AP_BYTES ((unsigned int)[TIOOTASelectedPackage()[@"apBytes"] unsignedIntegerValue])
#define TIO_FW_AP_MD5 ((NSString *)TIOOTASelectedPackage()[@"apMD5"])
#define TIO_FW_PAYLOAD_BYTES ((unsigned int)[TIOOTASelectedPackage()[@"payloadBytes"] unsignedIntegerValue])
#define TIO_FW_PAYLOAD_SLICES ((unsigned int)[TIOOTASelectedPackage()[@"payloadSlices"] unsignedIntegerValue])
#define TIO_FW_MEMBER_PINS ((NSDictionary *)TIOOTASelectedPackage()[@"memberPins"])
#define TIO_FW_ACCEPTED_OS_VERSIONS ((NSArray *)TIOOTASelectedPackage()[@"acceptOsVersions"])
#define TIO_FW_ACCEPTED_QUERY_CODES ((NSArray *)TIOOTASelectedPackage()[@"acceptQueryCodes"])
#define TIO_FW_ACCEPTED_VERSIONS_TEXT ((NSString *)TIOOTASelectedPackage()[@"acceptVersionsText"])
BOOL TIOOTAFlashCancel(void);
NSDictionary *TIOOTAFlashStatus(void);
BOOL TIOOTAFlashDisableAutoUpdate(void);
