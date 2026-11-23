#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// The release's packages (FirmwarePins.h TIO_FW_PACKAGES), in order: the first is the default the phone selects at
// every launch. Each entry holds its name, kind (TMG or STOCK), bundle resource, ZIP size and SHA-256, AP and manifest
// pins, payload totals, member pins, OtaVersion and accepted versions. nil for an index past the end or an entry
// whose member pins are unusable. Which one is selected is kept by ExperimentalOTAFlash.m (TIOOTASelectedPackage).
FOUNDATION_EXPORT NSUInteger TIOOTAPackageCount(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOOTAPackageAt(NSUInteger index);
// The name a person reads for a package: the TMG label, or "Stock <base>" for the stock package.
FOUNDATION_EXPORT NSString *TIOOTAPackageDisplayName(NSDictionary * _Nullable package);
// The file name of a package's ZIP in the addon's own store: <its SHA-256>.zip.
FOUNDATION_EXPORT NSString *TIOOTAPackageArchiveName(NSDictionary * _Nullable package);
// Every member of the package read by name from the folder (a regular file of the pinned size whose SHA-256 is the
// member pin), held in memory; nil with one plain message when a member is missing or different.
NSDictionary<NSString *,NSData *> * _Nullable TIOCopyExperimentalOTAPayloads(NSURL *directory,NSDictionary * _Nullable package,NSError **error);
// The package's exact ZIP bytes (size and SHA-256). Integrity approval never means authorization to flash.
// The payloads of a package whose pins differ from the bundled stock package's, sorted (the manifest excluded); with no
// stock package, a TMG package's AP. Empty for the stock package itself.
FOUNDATION_EXPORT NSArray<NSString *> *TIOOTAChangedPayloads(NSDictionary * _Nullable package);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckExperimentalOTA(NSData *data, NSDictionary * _Nullable package, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOReadExperimentalOTA(NSURL *file, NSDictionary * _Nullable package, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOImportExperimentalOTA(NSURL *source, NSURL *directory, NSDictionary * _Nullable package, NSError **error);
// The official ota/<folder> check for the package: TIOCopyExperimentalOTAPayloads succeeds. A summary, NOT a flash approval.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOCheckOfficialOTADirectory(NSURL *directory, NSDictionary * _Nullable package, NSError **error);
// This build's release (a cN name from releases.json, today c25) and its official folder name (Strix_OS_<base>),
// the same for every package of the release.
FOUNDATION_EXPORT NSString *TIOOTARelease(void);
FOUNDATION_EXPORT NSString *TIOOTAReleaseFolder(void);
NS_ASSUME_NONNULL_END
