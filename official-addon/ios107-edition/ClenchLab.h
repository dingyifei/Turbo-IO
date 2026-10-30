#import <Foundation/Foundation.h>
// Clench Lab (CLENCH-A Lane P): debug-only, TIO_IMAGE_RX_LAB builds. Passive LifeLog capture only.
// The Lab never sends A2/A6/A8, life_log_guide or life_log_switch; the user starts and stops LifeLog in the
// official app and the Lab only prompts. Session schema 1 plus Amendment 1 (120 s stop prompt, 125 s cutoff).
// Storage is local only (0700/0600, file protection, excluded from backup). Foundation only: macOS tests link it.
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const TIOClenchLabChangedNotification;
FOUNDATION_EXPORT NSArray<NSString *> *TIOClenchLabels(void);
// "voice" stays a reserved enum value; only "lifelog" is selectable.
FOUNDATION_EXPORT NSArray<NSString *> *TIOClenchSources(void);
FOUNDATION_EXPORT BOOL TIOClenchSourceSelectable(NSString *source);
// Build-time short SHA (+"-dirty") from build.sh, or "unknown".
FOUNDATION_EXPORT NSString *TIOClenchBuildCommit(void);
// BusinessEnvelopeMetadata rules (fields 1-4 singular, wire types, 10-byte varints, <=256 fields, <=1 MiB).
// Returns type, messageBytes, dataBytes and vpuMask/vadMask (NSNull when absent or not an integer).
FOUNDATION_EXPORT NSDictionary *_Nullable TIOClenchParseEnvelope(NSData *envelope);
// uint32 little-endian byte length followed by the original envelope.
FOUNDATION_EXPORT NSData *_Nullable TIOClenchFrame(NSData *envelope);
// set_ai_voice_wakeup on business 15, modes 0 (voice wake-up off) and 1 (on) only. Mode 1 equals
// LauncherControlPrototype.encode(.enableVoiceWakeup), including the trailing empty field 4.
FOUNDATION_EXPORT NSData *_Nullable TIOClenchWakeupPacket(NSInteger mode);
// {enabled,realtime,cached,events} from an official getStatus dictionary, or nil if any flag is missing.
FOUNDATION_EXPORT NSDictionary *_Nullable TIOClenchDumpConfig(NSDictionary *_Nullable status);
// Allow-listed copy of one official events.jsonl object if its timestamp lies inside [start,end]; else nil.
// Only timing, event type/source, VPU/VAD flags and masks, frame/byte/packet counts and taskId survive, with Lane T's
// types: counts are booleans or integers (an integral float becomes an integer; a fractional one is dropped), tags are
// short safe strings or integers 0...UINT32_MAX.
FOUNDATION_EXPORT NSDictionary *_Nullable TIOClenchFilterOfficialEvent(id event, NSDate *start, NSDate *end);
FOUNDATION_EXPORT NSURL *TIOClenchDefaultRoot(void);
FOUNDATION_EXPORT NSURL *TIOClenchDefaultExportRoot(void);
// Newest first: {id,url,complete,manifest?}. Sessions without a manifest are incomplete and never exported. A capture
// writes a checkpoint manifest (captureState "interrupted") at Start and every 5 s, so a session whose process died
// mid-capture is still listed complete with its marks, packets and window up to the last checkpoint.
// Every session folder is ordered by its creation (folder birth time, made at Start) before the 200-row cap, so the
// newest sessions are never dropped; only the kept rows read their manifest.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOClenchListSessions(NSURL *root);
// Refuses (NO) while the session is in use: an attach running on it, or work the UI registered (zip, a pending attach).
FOUNDATION_EXPORT BOOL TIOClenchDeleteSession(NSURL *root, NSURL *session);
// Counted in-use registry keyed by session folder name. Begin/End pairs must balance.
FOUNDATION_EXPORT void TIOClenchBeginSessionWork(NSURL *session);
FOUNDATION_EXPORT void TIOClenchEndSessionWork(NSURL *session);
FOUNDATION_EXPORT BOOL TIOClenchSessionInUse(NSURL *session);
// Copies official Ogg/Opus dump files that are new since Start (path+inode not in the start snapshot), were born inside
// the session's wall-clock window (5 s slack), were last written no later than startWallMs + the effective receive
// deadline (receive limit, or an earlier stop plus its tail) + 5 s flush slack (else skipped "written-after-session"),
// are not cached-kind (provenance unverified: skipped "cached-provenance-unverified") and are not listed by another Lab
// session, up to 64 files and
// 64 MiB (Lane T's bounds; the rest are skipped with reason "dump-cap-64-files" or "dump-cap-64MiB"), into
// <session>/official-dump/ with alignment "unaligned", and writes <session>/official-events.jsonl (Lab window only).
// A file already open at Start (same path and inode in the snapshot; the dump was on and LifeLog running) is never copied:
// it holds official audio from before Start, which the user did not consent to share. One that grew during the window is
// skipped with reason "pre-existing-file-grown" (its size at Start recorded), one that changed otherwise with
// "pre-existing-file-changed".
// .pcm debug files are never copied (officialDumpSkipped reason "not-ogg-opus"). Copies are verbatim (TIOAOAudioCopyVerbatim:
// the official bytes, legacy granule clock included, granuleMode recorded); copyFinalized means a stable copy that passed
// the Ogg structure check.
// Its own uncapped listing (bounded walk; earliest-born in-window candidates first) records any truncation.
// officialAttach becomes "done", or "retry" when a file failed to copy (the stable-copy check): a later attach then
// adds only files not attached yet (at most 5 attempts). After "done" it copies nothing and returns alreadyAttached=YES.
// Caller checks that the official session stopped (alwaysOnRunning==NO) and the dump config was restored.
FOUNDATION_EXPORT NSDictionary *_Nullable TIOClenchAttachOfficial(NSURL *session, NSURL *officialHome);
// Stored (method 0) zip of manifest.json, envelopes.rnp, official-events.jsonl and official-dump/* under
// clench-<id>/ in <exportRoot>/<uuid>/. The caller deletes the returned file's folder after sharing.
FOUNDATION_EXPORT NSURL *_Nullable TIOClenchZipSession(NSURL *session, NSURL *exportRoot);
// Read-modify-write of manifest.json, atomic rename. Used for post-capture status updates.
FOUNDATION_EXPORT BOOL TIOClenchMergeManifest(NSURL *session, NSDictionary *updates);

typedef NS_ENUM(NSInteger, TIOClenchPhase) {TIOClenchPhaseIdle, TIOClenchPhaseCapturing, TIOClenchPhaseFinished};

@interface TIOClenchConfig : NSObject
@property(nonatomic,strong) NSURL *root;
@property(nonatomic,strong) NSURL *officialHome;          // app home holding Documents/always_on_debug
@property(nonatomic,strong) NSUserDefaults *defaults;
@property(nonatomic,copy) NSTimeInterval (^clock)(void);          // monotonic seconds
@property(nonatomic,copy) NSDate *(^wallClock)(void);             // createdAt and the official events window only
@property(nonatomic,copy) NSDictionary *_Nullable (^dumpStatus)(void);
@property(nonatomic,copy) BOOL (^dumpConfigure)(NSDictionary *config);
@property(nonatomic,copy) NSString *_Nullable (^device)(void);
@property(nonatomic,copy) NSString *appVersion;
@property(nonatomic,copy) NSString *appCommit;
@property(nonatomic) NSTimeInterval stopRequestLimit;   // 120
@property(nonatomic) NSTimeInterval receiveLimit;       // 125
@property(nonatomic) NSTimeInterval stopTail;           // 5 s of tail after an early stop
@property(nonatomic) NSUInteger maxPackets;             // 4096
@property(nonatomic) unsigned long long maxEnvelopeBytes; // 8 MiB including prefixes
@property(nonatomic) BOOL synthetic;                    // test fixtures only
// UIApplication.idleTimerDisabled, injected so the model stays Foundation-only. Auto-lock resigns the app, which ends a
// capture; the Lab keeps the idle timer disabled while capturing. It turns it on only if it is off (at Start, or when another
// holder turned it off mid-capture), and at the end turns it off only if the Lab turned it on and it is still on.
// Known limitation, the same as between the MapKit navigation and camera holders (save at start, restore at end): a holder
// that starts while the Lab holds the flag saves the Lab's "on" and writes it back when it ends, so auto-lock can stay off
// after both have ended. idleTimerHeldElsewhere (optional) returns YES while such a holder is active (camera live or
// navigation running on screen); the Lab then leaves the flag to it at the end instead of turning auto-lock back on under it.
@property(nonatomic,copy,nullable) BOOL (^idleTimerDisabled)(void);
@property(nonatomic,copy,nullable) void (^setIdleTimerDisabled)(BOOL disabled);
@property(nonatomic,copy,nullable) BOOL (^idleTimerHeldElsewhere)(void);
+ (instancetype)standardConfig;
@end

@interface TIOClenchSession : NSObject
- (instancetype)initWithConfig:(TIOClenchConfig *)config NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic,readonly) TIOClenchConfig *config;
@property(nonatomic,readonly) TIOClenchPhase phase;
@property(nonatomic,readonly,copy,nullable) NSString *sessionId,*label,*source,*stopBasis,*lastStopReason;
@property(nonatomic,readonly,nullable) NSURL *directory;
@property(nonatomic,readonly) NSUInteger markCount,packetCount,droppedPackets;
@property(nonatomic,readonly) BOOL stopRequested,offObserved,stopPending,dumpRestored,holdsIdleTimer;
@property(nonatomic,readonly) NSTimeInterval elapsed,remaining,durationSeconds;
@property(nonatomic,readonly,nullable) NSDictionary *lastCounter;
// Persisted record of an unresolved LifeLog stop or dump restore. Blocks Start; never auto-starts anything.
@property(nonatomic,readonly,nullable) NSDictionary *pending;
@property(nonatomic,copy,nullable) NSDictionary *context;   // wake-word snapshot etc., copied into the manifest
// The wake-word context is read once at Start, so a set_ai_voice_wakeup send is refused while capturing (NO).
@property(nonatomic,readonly) BOOL wakeCommandAllowed;
// A dump restore the user waived (official interface unavailable when they confirmed). It no longer blocks Start, but
// restorePendingDump keeps trying it (guarded, read-back verified) until the official interface reads back; Start
// resolves it first and refuses with "pending" when it cannot.
@property(nonatomic,readonly,nullable) NSDictionary *restoreOwed;
@property(nonatomic,copy,nullable) void (^changed)(void);
@property(nonatomic,copy,nullable) void (^stopPrompt)(BOOL dumpRestored);
// nil on success, else busy|pending|label|source|device|dump-unavailable|dump-enable-failed|storage.
- (nullable NSString *)startWithLabel:(NSString *)label source:(NSString *)source;
- (BOOL)mark;
- (void)tick;
- (void)requestStop:(NSString *)reason;
- (void)lifecycleStop:(NSString *)reason;
- (void)receiveBusiness:(NSInteger)business payload:(nullable NSData *)payload device:(nullable NSString *)device arrival:(NSTimeInterval)arrival;
- (void)noteChannel:(NSString *)channel bytes:(NSUInteger)bytes;
- (void)noteEventType:(NSString *)eventType;
// Re-prompt path: restores the dump config with read-back and re-checks official alwaysOnRunning once (only with the
// session's glasses connected). YES when resolved.
- (BOOL)retryPending;
// Launch and panel recovery: restores the prior dump config of an unresolved record, or of a waived one (restoreOwed),
// with read-back. Leaves the stop state alone and sends nothing to the glasses. YES when no dump restore is outstanding
// afterwards.
- (BOOL)restorePendingDump;
// Passive check only (no configure call): clears the stop after two consecutive alwaysOnRunning==NO readings taken
// with the session's glasses connected.
- (void)observeOfficialStatus;
// Auto-attach gate for a finished session folder, called once per poll: YES after three consecutive alwaysOnRunning==NO
// readings spanning at least 2 s with the session's own glasses connected (link loss never counts). Records the first of
// those readings as officialStopObservedMs in the manifest unless the capture already observed the stop.
- (BOOL)officialSettledForAttach:(NSURL *)session;
// One gate for automatic and manual attach, called once per poll: nil when the attach may run now, else
// capturing|dump-outstanding|not-stopped|settling. A session already attached ("done") passes at once (it copies
// nothing); anything else needs officialSettledForAttach (target glasses, link loss, settle). "settling" means the
// readings are counting; "not-stopped" means LifeLog runs, the status is unknown or the glasses are not the session's.
- (nullable NSString *)attachGate:(NSURL *)session;
// Ends the Lab's idle-timer hold (see TIOClenchConfig). No-op unless held and the capture has ended (finish calls it).
- (void)releaseIdleTimer;
// The user checked the official app or glasses. Writes stop-confirmation.json; clears the stop part. A dump restore that
// cannot be read back (official interface unavailable) is waived for Start only and moves to restoreOwed.
- (BOOL)confirmPhysicalStop;
- (NSDictionary *)manifest;
@end

// The panel's cached session list (TIOClenchListSessions rows read under listedKey = TIOClenchListStateKey at that time)
// is stale when the Lab's phase, session or pending record changed since, or when the row of the Lab's session that is
// no longer capturing still has no manifest (listed mid-capture).
FOUNDATION_EXPORT NSString *TIOClenchListStateKey(TIOClenchSession *session);
FOUNDATION_EXPORT BOOL TIOClenchSessionListStale(NSArray<NSDictionary *> *rows, NSString *_Nullable listedKey, TIOClenchSession *session);
// GlassesChannelHook entry points. Non-consuming; idle cost is one atomic load. A business envelope that arrived while
// capturing (arrival read at Send entry) but is processed on the main queue after the capture ended is counted in the
// manifest's droppedPackets as "arrived-before-finish-unprocessed" (or "after-window" past the deadline), never lost.
FOUNDATION_EXPORT BOOL TIOClenchTapActive(void);
FOUNDATION_EXPORT void TIOClenchTapChannel(id _Nullable channel, NSUInteger bytes);
FOUNDATION_EXPORT void TIOClenchTapEvent(NSDictionary *_Nullable event, NSTimeInterval arrival);
NS_ASSUME_NONNULL_END
