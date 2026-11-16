#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TIONoNetworkPhase) {
    TIONoNetworkIdle, TIONoNetworkArmed, TIONoNetworkTaking,
    TIONoNetworkOwned, TIONoNetworkTail
};
typedef NS_ENUM(NSUInteger, TIONoNetworkEvent) {
    TIONoNetworkAsrEvent, TIONoNetworkNlpEvent,
    TIONoNetworkAudioEvent, TIONoNetworkCompleteEvent, TIONoNetworkErrorEvent
};

@interface TIONoNetworkSnapshot : NSObject
@property(nonatomic) NSInteger mode;
@property(nonatomic) BOOL appleFallback, verified, hooksReady, voiceExitReady;
@property(nonatomic) BOOL ownsTurn, responseDone, voiceExited, stopHost, forceForeground;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,strong) id listener;
@property(nonatomic,copy) NSString *sid, *asr;
@property(nonatomic,strong) NSNumber *timeout;
@end

// Foundation-only state. Payloads live only in the host, never in the ring.
@interface TIONoNetworkState : NSObject
@property(nonatomic,readonly) TIONoNetworkPhase phase;
@property(nonatomic,readonly) NSUInteger epoch, controllerGeneration;
@property(nonatomic,weak,readonly) id listener;
@property(nonatomic,copy,readonly) NSString *sid, *text;
@property(nonatomic,readonly) NSTimeInterval tailUntil;
- (void)arm:(id)listener sid:(NSString *)sid text:(NSString *)text generation:(NSUInteger)generation;
- (void)beginTakeover;
- (void)acquire;
- (void)finishAt:(NSTimeInterval)now;
- (void)clear;
- (BOOL)hasSeenSid:(NSString *)sid text:(NSString *)text;
- (void)rememberSid:(NSString *)sid text:(NSString *)text;
- (void)record:(NSString *)event at:(NSTimeInterval)now sid:(NSString *)sid;
- (NSArray<NSDictionary *> *)timeline;
@end

FOUNDATION_EXPORT NSString *TIONoNetworkQuestion(NSString *text);
FOUNDATION_EXPORT NSTimeInterval TIONoNetworkDelay(BOOL known, BOOL satisfied, NSNumber *preference);
FOUNDATION_EXPORT BOOL TIONoNetworkModeEligible(NSInteger mode, BOOL fallback);

typedef BOOL (^TIONoNetworkTakeover)(id wrapper, NSString *question, id listener);
typedef void (^TIONoNetworkReplayNlp)(id listener, id value);
typedef void (^TIONoNetworkReplayComplete)(id listener);
typedef TIONoNetworkSnapshot *(^TIONoNetworkReadState)(void);
typedef void (^TIONoNetworkScheduler)(NSTimeInterval delay, dispatch_block_t work);
FOUNDATION_EXPORT void TIONoNetworkInstall(Class voice, TIONoNetworkTakeover takeover,
    TIONoNetworkReplayNlp replay, TIONoNetworkReplayComplete complete,
    TIONoNetworkReadState state, dispatch_block_t stopHost);
// Submit on main, or enqueue a submission to main. Tool NLP is synchronous.
FOUNDATION_EXPORT void TIONoNetworkSubmit(TIONoNetworkEvent kind, id listener, BOOL toolDispatch, dispatch_block_t work);
FOUNDATION_EXPORT id TIONoNetworkBeginAsr(id listener, NSString *text, BOOL final, NSString *sid, BOOL controllerDuplicate, NSUInteger generation);
FOUNDATION_EXPORT void TIONoNetworkWillAsr(NSString *text);
FOUNDATION_EXPORT void TIONoNetworkDidAcceptAsr(id token, id listener, NSString *text, BOOL final, NSString *sid);
FOUNDATION_EXPORT void TIONoNetworkEndAsr(id token);
FOUNDATION_EXPORT void TIONoNetworkAudioStart(void);
FOUNDATION_EXPORT BOOL TIONoNetworkNlp(id listener, id value);
FOUNDATION_EXPORT BOOL TIONoNetworkComplete(id listener);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIONoNetworkTimeline(void);
FOUNDATION_EXPORT BOOL TIONoNetworkFailedOpen(void);
FOUNDATION_EXPORT void TIONoNetworkSetScheduler(TIONoNetworkScheduler scheduler);
FOUNDATION_EXPORT void TIONoNetworkSetClock(NSTimeInterval (^clock)(void));
#if TIO_NO_NETWORK_TESTING
FOUNDATION_EXPORT void TIONoNetworkTestReset(void);
FOUNDATION_EXPORT void TIONoNetworkTestNetwork(BOOL known, BOOL satisfied);
FOUNDATION_EXPORT void TIONoNetworkTestClassLookup(Class (^lookup)(NSString *name));
FOUNDATION_EXPORT NSDictionary *TIONoNetworkTestStatus(void);
#endif
