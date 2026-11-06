#import <Foundation/Foundation.h>
// wirelog: a passive recorder for the Dart <-> native channel traffic of the host app.
// Compiled only with TIO_WIRE_LOG=1. It never changes arguments, results, ordering, threading or call counts;
// every entry point catches its own exceptions and switches the recorder off for the session if one fires.

// ---- session control (any thread) ----
FOUNDATION_EXPORT BOOL TIOWireLogActive(void);
FOUNDATION_EXPORT BOOL TIOWireLogStart(void);
FOUNDATION_EXPORT void TIOWireLogStop(void);
// active, records, dropped, bytes, file, files, totalBytes, disabledReason, wrappedChannels
FOUNDATION_EXPORT NSDictionary *TIOWireLogStatus(void);
FOUNDATION_EXPORT NSURL *TIOWireLogDirectory(void);
// Asks the writer queue to flush, then calls done on the main queue.
FOUNDATION_EXPORT void TIOWireLogFlush(void (^done)(void));
FOUNDATION_EXPORT NSArray<NSURL *> *TIOWireLogFiles(void);
// Off unless the owner turns it on; start state does not otherwise survive a restart.
FOUNDATION_EXPORT BOOL TIOWireLogAutoStartEnabled(void);
FOUNDATION_EXPORT void TIOWireLogSetAutoStart(BOOL on);
FOUNDATION_EXPORT void TIOWireLogMaybeAutoStart(void);

// ---- hook entry points ----
// Call first thing in the bridge hook: marks the call as seen by the bridge (so the generic handler wrapper
// does not record it twice) and returns the channel name it arrived on.
FOUNDATION_EXPORT NSString *TIOWireLogClaimBridgeCall(void);
// Returns a block that forwards to `result` unchanged and records the call, the value and the latency.
// Returns `result` itself when recording is off or result is nil.
FOUNDATION_EXPORT id TIOWireLogWrapBridgeResult(NSString *channel, id call, id result);
// Native -> Dart message (FlutterEngine sendOnChannel). Cheap; decoding happens on the writer queue.
FOUNDATION_EXPORT void TIOWireLogNativeToDart(NSString *channel, NSData *message);
// Wraps a FlutterBinaryMessageHandler for a matching channel; returns it unchanged otherwise.
FOUNDATION_EXPORT id TIOWireLogWrapHandler(NSString *channel, id handler);
FOUNDATION_EXPORT BOOL TIOInstallWireLogHook(void);

// ---- channel policy ----
typedef NS_ENUM(NSInteger, TIOWireLogChannelClass) {
    TIOWireLogChannelIgnored = 0, // not a rayneo / venus channel: never recorded
    TIOWireLogChannelFull,        // recorded in full
    TIOWireLogChannelOpaque       // cloud, login or account traffic: channel name and byte count only
};
FOUNDATION_EXPORT TIOWireLogChannelClass TIOWireLogClassifyChannel(NSString *channel);

// ---- exposed for the host tests ----
FOUNDATION_EXPORT BOOL TIOWireLogKeyIsSensitive(NSString *key);
// A redacted, JSON-safe copy of a Foundation / Flutter value tree.
FOUNDATION_EXPORT id TIOWireLogJSON(id value);
// Decodes a Flutter StandardMessageCodec buffer. ok=NO when the bytes are not a complete standard value.
FOUNDATION_EXPORT id TIOWireLogDecodeStandard(NSData *data, BOOL *ok);
// {codec: methodCall|envelope|errorEnvelope|message|raw, ...decoded fields or hex}. hint prefers envelope for event channels.
FOUNDATION_EXPORT NSDictionary *TIOWireLogDecodeMessage(NSData *data, BOOL preferEnvelope);
// Redirects the writer. Resets the session counters. Test only.
FOUNDATION_EXPORT void TIOWireLogConfigure(NSURL *directory, unsigned long long rotateBytes, unsigned long long capBytes);
// Blocks until everything queued so far is written and flushed. Test only.
FOUNDATION_EXPORT void TIOWireLogDrainForTest(void);
// Makes the next observed record throw inside the observer. Test only.
FOUNDATION_EXPORT void TIOWireLogInjectFaultForTest(void);
