#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary * _Nullable TIOAOStatus(void);
FOUNDATION_EXPORT BOOL TIOAOSetAudioSaving(BOOL enabled);
// Exact {enabled,realtime,cached,events} BOOL dictionary passed to the official configureDump. No read-back:
// callers verify with TIOAOStatus. Clench Lab uses it to enable events for one session and restore the prior config.
FOUNDATION_EXPORT BOOL TIOAOConfigureDump(NSDictionary *config);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOAOAudioFiles(NSURL *home);
FOUNDATION_EXPORT NSURL * _Nullable TIOAOAudioCopy(NSURL *home,NSURL *source,NSError **error);
// Ogg/Opus only. The same stable copy and Ogg structure check as TIOAOAudioCopy, but the copy keeps the official bytes
// (no granule rewrite). *granules is "official-legacy-20ms" or "toc-correct". Clench Lab research copies use it.
FOUNDATION_EXPORT NSURL * _Nullable TIOAOAudioCopyVerbatim(NSURL *home,NSURL *source,NSString * _Nullable * _Nullable granules,NSError **error);
FOUNDATION_EXPORT void TIOInstallAlwaysOnAudioMenu(void);
NS_ASSUME_NONNULL_END
