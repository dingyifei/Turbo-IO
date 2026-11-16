#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Immutable verified payloads for a single explicitly authorized transfer.
NSDictionary<NSString *,NSData *> * _Nullable TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error);
// Fixed private TMG3 only. Integrity approval never means authorization to flash.
FOUNDATION_EXPORT NSString *TIOExperimentalOTASHA(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTA(NSData *data, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOReadExperimentalOTA(NSURL *file, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOImportExperimentalOTA(NSURL *source, NSURL *directory, NSError **error);
// Point-in-time read-only snapshot, NOT a frozen transfer session or flash approval.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTADirectory(NSURL *directory, NSError **error);
// The official ota/<folder> check: the same exact-member check, but when the folder exists and holds anything other
// than this build's release (for example RayNeo's own download of the same version, which uses the same folder
// name), the error says so: RayNeo may reuse those files instead of downloading the release. Never modifies them.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckOfficialOTADirectory(NSURL *directory, NSError **error);
// This build's release (a cN name from releases.json, today c21) and its official folder name (Strix_OS_<base>).
FOUNDATION_EXPORT NSString *TIOOTARelease(void);
FOUNDATION_EXPORT NSString *TIOOTAReleaseFolder(void);
// The number of members of this build's release ZIP, from the generated member pins (17 on the 1.0.6.11
// base); the manifest has one row less. Folder scan, manifest check and status counts use it.
FOUNDATION_EXPORT NSUInteger TIOExperimentalOTAMemberCount(void);
NS_ASSUME_NONNULL_END
