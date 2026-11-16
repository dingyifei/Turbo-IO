#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Every pinned member read by name from the folder (a regular file of the pinned size whose SHA-256 is the
// member pin), held in memory; nil with one plain message when a member is missing or different.
NSDictionary<NSString *,NSData *> * _Nullable TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error);
// Fixed private TMG3 only. Integrity approval never means authorization to flash.
FOUNDATION_EXPORT NSString *TIOExperimentalOTASHA(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTA(NSData *data, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOReadExperimentalOTA(NSURL *file, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOImportExperimentalOTA(NSURL *source, NSURL *directory, NSError **error);
// The official ota/<folder> check: TIOCopyExperimentalOTAPayloads succeeds. A summary, NOT a flash approval.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckOfficialOTADirectory(NSURL *directory, NSError **error);
// This build's release (a cN name from releases.json, today c21) and its official folder name (Strix_OS_<base>).
FOUNDATION_EXPORT NSString *TIOOTARelease(void);
FOUNDATION_EXPORT NSString *TIOOTAReleaseFolder(void);
// The number of members of this build's release ZIP, from the generated member pins (17 on the 1.0.6.11
// base). The archive summary and the feed's update text use it.
FOUNDATION_EXPORT NSUInteger TIOExperimentalOTAMemberCount(void);
NS_ASSUME_NONNULL_END
