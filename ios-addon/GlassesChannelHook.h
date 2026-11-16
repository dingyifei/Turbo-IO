#import <Foundation/Foundation.h>
// Sole owner of the rayneonet Flutter channel interception. Carries the OTA flash gate.
FOUNDATION_EXPORT BOOL TIOInstallGlassesChannelHook(void);
FOUNDATION_EXPORT BOOL TIOGlassesChannelHookInstalled(void);
// nil once installed; otherwise why not ("not attempted", or the failed target check).
FOUNDATION_EXPORT NSString *TIOGlassesChannelHookFailure(void);
// Runtime evidence that the stock app's rayneonet calls pass through the hook in
// this launch: YES once a stock call whose method starts with "rayneonet_" has
// reached MethodHook. The addon's own senders never count (see TIOChannelResultImageIsStock).
FOUNDATION_EXPORT NSString *const TIOGlassesChannelStockTrafficNotification; // posted on main, once
FOUNDATION_EXPORT BOOL TIOGlassesChannelStockTrafficSeen(void);
// stockSeen, stockCalls, addonCalls, and once seen firstStockUptime (systemUptime) and firstStockMethod.
FOUNDATION_EXPORT NSDictionary *TIOGlassesChannelTrafficStatus(void);
