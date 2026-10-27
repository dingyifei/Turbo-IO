#import <Foundation/Foundation.h>
// Transport hook readiness and the OS-version query matcher.
FOUNDATION_EXPORT BOOL TIOOTAIsEmptyVersionQuery(NSData *payload);
FOUNDATION_EXPORT void TIOOTARecordTransportHookReady(void);
FOUNDATION_EXPORT NSDictionary *TIOOTAGuardStatus(void);
