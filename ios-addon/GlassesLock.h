#import <Foundation/Foundation.h>
#include "lock_codec.h"
/* The glasses PIN lock on the phone (docs/lock-design.md §4, §5). The TLK:/TKA: records come from lock_codec.c, which is
 * byte-identical with the firmware copy. Nothing about the lock is kept on the phone except the "Stay unlocked while worn"
 * switch and its early-drop counter (TIOLockMotion) and which glasses have shown the lock (TIOGlassesLockLink.seen); the
 * state shown is the glasses' last reply, read again on every visit. */

typedef NS_ENUM(NSUInteger,TIOLockPhase){TIOLockPhaseUnknown,TIOLockPhaseOff,TIOLockPhaseUnlocked,TIOLockPhaseLocked};
/* The page as the last reply describes it. */
typedef struct {
 TIOLockPhase phase;
 BOOL lockOn;                 /* the "Lock with PIN" switch */
 BOOL damaged;                /* both copies of the lock record damaged: the glasses stay locked until the phone unlocks or sets a PIN */
 BOOL showUnlock,showLockNow; /* the filled "Unlock glasses" while locked, the secondary "Lock now" while unlocked */
 unsigned wrong;              /* wrong tries since the last unlock not yet dismissed on the phone; 0 hides the warning */
 unsigned foldMin,idleMin;
 BOOL motionSupported,motionOn;
} TIOLockModel;
/* NULL: nothing read yet (phase Unknown, every action hidden). */
TIOLockModel TIOLockModelFromReply(const TLKReply *reply);
/* String id of the phase word ("Off", "Unlocked", "Locked"); nil for Unknown. */
NSString *TIOLockPhaseTextId(TIOLockPhase phase);
/* YES when caps (diagnostics TD_CAP_*) carry TD_CAP_PIN_LOCK. */
BOOL TIOLockCapsSupported(uint32_t caps);
/* Four ASCII digits into pin[4]; NO for anything else. */
BOOL TIOLockParsePin(NSString *text,uint8_t pin[4]);

/* lastResult when the command never reached the glasses or no reply came. */
enum {TIOLockResultNotSent=0xff,TIOLockResultNoReply=0xfe};
extern const double TIOLockReplySeconds;   /* a command without a reply after this is ended as unknown; never resent */
extern const double TIOLockTokenUseSeconds; /* a QUERY token is used only this long (the glasses accept it for 120 s) */

@interface TIOGlassesLockLink:NSObject
@property(nonatomic,readonly) BOOL busy;
/* The connected glasses report TD_CAP_PIN_LOCK, or this phone has seen the lock on them before (seen). Without either
 * nothing is encoded or sent. The glasses refuse the diagnostics status read while locked, so the caps sample goes stale
 * exactly when Unlock is needed (device feedback 5): once seen, the TLK: QUERY answer is the live state. A fresh sample
 * without the bit (other firmware) forgets them again. */
@property(nonatomic,readonly) BOOL supported;
/* Where the glasses that have shown the lock are remembered (key "lockPeers"); nil: the live caps only. */
@property(nonatomic,strong) NSUserDefaults *seen;
/* Glasses are connected (a peer). */
@property(nonatomic,readonly) BOOL connected;
/* A reply from the connected glasses is known; state and model describe it. */
@property(nonatomic,readonly) BOOL known;
@property(nonatomic,readonly) TLKReply state;
@property(nonatomic,readonly) TIOLockModel model;
/* The outcome of the last command as a sentence for the page footer; nil after a plain successful read. */
@property(nonatomic,readonly) NSString *note;
@property(nonatomic,readonly) unsigned lastOp,lastResult;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock caps:(uint32_t(^)(void))caps send:(BOOL(^)(NSData *))send;
- (void)query:(void(^)(void))done;
/* Every change reads a fresh token first (QUERY), then sends the one command with it. A refused or lost command is never resent. */
- (void)unlock:(void(^)(void))done;
- (void)lockNow:(void(^)(void))done;
- (void)setPin:(NSString *)digits done:(void(^)(void))done;
- (void)setFold:(NSUInteger)fold idle:(NSUInteger)idle done:(void(^)(void))done;
- (void)disable:(void(^)(void))done;
- (void)acknowledgeFailures:(void(^)(void))done;
/* Only when the glasses report "motion supported"; otherwise it ends at once with lastResult TLK_R_REFUSED and nothing sent. */
- (void)motionOn:(void(^)(void))done;
- (BOOL)consume:(NSDictionary *)event;
- (void)cancel;
@end
BOOL TIOGlassesLockIsReply(NSDictionary *event);

/* "Stay unlocked while worn": the phone's switch and its early-drop counter (§7). When the link drops within 60 s of a
 * MOTION_ON that the glasses accepted, that counts; two such drops in a row switch it off and leave a reason. A link that
 * stays up 60 s, or the user turning the switch on again, starts the count over. */
extern const double TIOLockEarlyDropSeconds;
@interface TIOLockMotion:NSObject
@property(nonatomic) BOOL wanted;
@property(nonatomic,readonly) NSUInteger earlyDrops;
/* YES after the switch was turned off by two early drops, until the user turns it on again. */
@property(nonatomic,readonly) BOOL offAfterDrops;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults clock:(double(^)(void))clock;
- (void)motionAccepted;   /* the glasses answered OK to MOTION_ON */
- (void)linkDropped;      /* the glasses link went away (peer changed or gone) */
- (void)linkSurvived;     /* call when the link is still up: 60 s after an accepted MOTION_ON the count starts over */
@end
