#import <UIKit/UIKit.h>
#import "GlassesLock.h"
/* The "Glasses lock" page (docs/lock-design.md §4). */
UIViewController *TIOGlassesLockController(void);
/* Replies (TKA:) are routed to the app's one lock link through this. */
BOOL TIOGlassesLockConsume(NSDictionary *event);
/* Hub row: shown only when the connected glasses report TD_CAP_PIN_LOCK; the subtitle is the state of the last QUERY
 * (nil before one). TIOGlassesLockHubRefresh asks for a status sample when no capability bits are known, at most every
 * TDGlassesCapsRefreshSeconds, and reloads the hub once it may have arrived. */
BOOL TIOGlassesLockHubVisible(void);
NSString *TIOGlassesLockHubStatus(void);
void TIOGlassesLockHubRefresh(void);
/* "Stay unlocked while worn": on every connection, while the switch is on, send MOTION_ON to glasses that report
 * "motion supported", and count early link drops (§7). Nothing is sent while the switch is off. */
void TIOGlassesLockStart(void);
#if TIO_UI_PREVIEW
/* fixture: @"off", @"unlocked", @"locked" or @"wrong" (locked, 3 wrong tries since the last unlock). The page, link and codec
 * are the real ones; only the glasses are simulated. */
UIViewController *TIOGlassesLockPreviewController(NSString *fixture);
#endif
