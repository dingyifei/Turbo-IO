#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Pure safety state for the download-only 1.0.11/259 host. Foundation and the
// Objective-C runtime only, so the host tests link it without UIKit or Addon.m.
NS_ASSUME_NONNULL_BEGIN

// G2. Why the rayneonet channel hook cannot be installed, or nil when both
// targets resolve: bridge -handleMethodCall:result: (void, two object
// arguments) and engine -sendOnChannel:message:binaryReply: (void, three
// object arguments). A nil class counts as missing.
FOUNDATION_EXPORT NSString *_Nullable TIOChannelHookTargetFailure(Class _Nullable bridge, Class _Nullable engine);

// G2. YES only on the download-only profile with the hook installed and the
// transport hook recorded ready. No build flag takes part.
FOUNDATION_EXPORT BOOL TIODownloadOnlyGuardActiveFor(NSString *_Nullable profile, BOOL hookInstalled, BOOL transportHookReady);

// G2. Runtime evidence that the stock rayneonet path goes through the hook.
// A call counts as stock when its result block was compiled in an image of the
// app bundle other than the addon's own (the stock FlutterResult comes from
// Flutter.framework or the Runner). The addon's senders pass their own blocks
// (or nil), so they never count. Paths are compared after dropping a leading
// "/private"; images named Turbo* belong to Turbo IO and never count.
FOUNDATION_EXPORT BOOL TIOChannelResultImageIsStock(NSString *_Nullable imagePath, NSString *_Nullable addonImagePath, NSString *_Nullable bundlePath);

// G2. The guard row's three states:
//   "danger" no download-only guard (TIODownloadOnlyGuardActiveFor is NO)
//   "warn"   guard installed but no stock rayneonet call has passed the hook yet
//   "ok"     guard installed and a stock rayneonet call has passed the hook
FOUNDATION_EXPORT NSString *TIODownloadOnlyGuardLevelFor(NSString *_Nullable profile, BOOL hookInstalled, BOOL transportHookReady, BOOL stockTrafficSeen);

// G3. RayNeo's Auto Update switch, read from preference keys ending in
// _ota_firmware_auto_update (the parsing of TIOOTAAutoUpdateDisabled).
// Off: every such key is the string "false" or a boolean NO.
// On: any such key holds anything else (worst key wins).
// Missing: no such key (the app treats that as off, but nothing confirms it).
typedef NS_ENUM(NSInteger, TIOAutoUpdateReading) {
    TIOAutoUpdateReadingOff = 0,
    TIOAutoUpdateReadingMissing = 1,
    TIOAutoUpdateReadingOn = 2,
};
FOUNDATION_EXPORT TIOAutoUpdateReading TIOAutoUpdateReadingFor(NSDictionary *_Nullable preferences);
FOUNDATION_EXPORT NSString *TIOAutoUpdateReadingName(TIOAutoUpdateReading state); // "off", "missing", "on"

// Export panel model. Keys:
//   guardActive  NSNumber BOOL (TIODownloadOnlyGuardActiveFor)
//   stockTrafficSeen NSNumber BOOL, as passed in
//   guardLevel   TIODownloadOnlyGuardLevelFor: "ok", "warn" or "danger"
//   guardKey     localization key of the guard row title
//   guardDetail  localization key of the guard row detail
//   autoUpdate   TIOAutoUpdateReadingName
//   autoLevel    "ok", "warn" or "danger"
//   autoKey      localization key of the Auto Update row title
//   autoDetail   localization key of the Auto Update row detail
//   safe         NSNumber BOOL: guard level ok and Auto Update explicitly off
//   level        worst of guardLevel and autoLevel
//   bannerKey    localization key of the header banner, or absent when safe
// The panel never writes the host's preferences; it only reads them.
FOUNDATION_EXPORT NSDictionary *TIOFirmwareExportSafetyModel(NSString *_Nullable profile, BOOL hookInstalled, BOOL transportHookReady, BOOL stockTrafficSeen, NSDictionary *_Nullable preferences);

NS_ASSUME_NONNULL_END
