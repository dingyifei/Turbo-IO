#import <Foundation/Foundation.h>

// Read-only discovery and export of the firmware the stock RayNeo app downloaded.
// Pure Foundation; the host tests run it against a temporary container.
//
// Rules:
// - RayNeo's files are only opened for reading. Nothing here deletes, moves,
//   renames or writes them.
// - Symbolic links are never followed (roots, folders or files).
// - Enumeration is bounded: entries at most TIOFirmwareExportMaxDepth levels
//   below a root, at most TIOFirmwareExportMaxEntries entries in total.
// - The only writes go to TIOFirmwareExportOwnDirectory(home), which belongs
//   to the addon: re-zipped copies of an extracted folder, labelled as such.
NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger TIOFirmwareExportMaxDepth;   // 4
FOUNDATION_EXPORT const NSUInteger TIOFirmwareExportMaxEntries; // 500

// Container-relative folders that are always searched when present, in order.
FOUNDATION_EXPORT NSArray<NSString *> *TIOFirmwareExportRootPaths(void);
// <home>/Library/Application Support/TurboIOPrivateAddon/FirmwareExport
FOUNDATION_EXPORT NSURL *TIOFirmwareExportOwnDirectory(NSURL *home);

// Scans the container at home. Result keys:
//   entries      NSArray of entry dictionaries, sorted by root then path
//   roots        container-relative roots that exist and were searched
//   skippedLinks number of symbolic links seen and not followed
//   truncated    YES when the entry limit stopped the scan
//   depthLimited YES when a folder at the depth limit had children
// Entry keys: url, relative (container-relative path), name, root, kind
// ("file" or "folder"), depth (1 = directly in the root), bytes, modified,
// and for folders files (regular files listed below it) and extracted
// (name starts with "extracted").
FOUNDATION_EXPORT NSDictionary *TIOFirmwareExportScan(NSURL *home);

// Streams the file in 1 MiB chunks. Keys: sha256, md5 (lowercase hex), bytes.
// Refuses symbolic links and anything that is not a regular file.
FOUNDATION_EXPORT NSDictionary *_Nullable TIOFirmwareExportHash(NSURL *file, NSError *_Nullable *_Nullable error);

// Builds a stored (uncompressed) ZIP of a COPY of folder's regular files in
// TIOFirmwareExportOwnDirectory(home). folder must be a real folder inside home
// and outside the addon's own directory; links are skipped and the same depth
// and entry limits apply (a folder over the limits is refused, never cut short).
// Keys: url, bytes, files, sha256, md5, label = "rezipped".
// The result is NOT the server's package, and its hash will not match it.
FOUNDATION_EXPORT NSDictionary *_Nullable TIOFirmwareExportRezip(NSURL *folder, NSURL *home, NSError *_Nullable *_Nullable error);

// The addon's own re-zipped copies (url, name, bytes, modified), newest first.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOFirmwareExportOwnCopies(NSURL *home);
// Deletes one of the addon's own copies. Refuses anything else.
FOUNDATION_EXPORT BOOL TIOFirmwareExportDeleteOwnCopy(NSURL *file, NSURL *home);

NS_ASSUME_NONNULL_END
