#import <Foundation/Foundation.h>
#import "TDPhoneStore.h"
/* Main executor; owns the session independently of any view controller.
 * Does not start automatically, reconnect, reset OTA state or renew leases. */
@interface TDPhoneRun : NSObject
- (instancetype)initWithStore:(TDPhoneStore *)store root:(NSURL *)root
 clock:(NSTimeInterval(^)(void))clock sendStart:(BOOL(^)(uint32_t,uint32_t))start
 sendStop:(void(^)(void))stop;
- (BOOL)start;
- (void)poll;
- (void)stop:(NSString *)reason;
- (BOOL)receive:(NSData *)packet device:(NSString *)device;
- (void)event:(NSString *)code fields:(NSDictionary *)fields;
- (void)checkpoint;
@property(nonatomic,readonly) TDPhoneStore *store;
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) NSString *status;
@property(nonatomic,readonly) NSString *saveStatus;
@property(nonatomic,readonly) NSTimeInterval remaining;
@property(nonatomic,readonly) NSURL *reportDirectory;
- (NSData *)reportJSON;
- (NSString *)reportMarkdown;
/* Test/offline verification only; do not block the UI with this. */
- (void)waitForWrites;
@end

#include "command.h"
// One-shot metadata and calibration ownership, independent of periodic samples.
@interface TDRuntimeSession:NSObject
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(NSTimeInterval(^)(void))clock send:(BOOL(^)(TDCommand))send;
- (BOOL)query;
- (BOOL)beginCalibration;
- (void)finishCalibration;
- (void)cancelCalibration;
- (void)invalidate;
- (void)poll;
- (void)transportFailed;
// Passive guard: never polls, cancels, or sends a queued command.
- (BOOL)idleForOTA;
- (BOOL)receive:(NSData *)packet device:(NSString *)device;
/* Capability bits (diagnostics.h TD_CAP_*) from the last validated status sample of the current peer; 0 until one arrives
 * and again as soon as the peer changes. A TMG7 or older peer never sets TD_CAP_MENU_CAROUSEL (the TMG8 bit). */
- (uint32_t)glassesCaps;
/* YES when the connected glasses report the TMG8 caps bit ("glasses report TMG8 caps"). */
- (BOOL)glassesReportTMG8Caps;
@property(nonatomic) BOOL fileBusy;
@property(nonatomic,readonly) BOOL pending,holdsLease;
@property(nonatomic,readonly) NSDictionary *status;
@end
