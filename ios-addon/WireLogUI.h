#import <UIKit/UIKit.h>
// Developer-hub screen for wirelog plus the always-visible recording pill. Compiled only with TIO_WIRE_LOG=1.
FOUNDATION_EXPORT UIViewController *TIOWireLogController(void);
// Keeps the "REC" pill in step with the recorder (also when logging was auto-started before any UI exists).
FOUNDATION_EXPORT void TIOWireLogUIInstall(void);
// One-line hub status: "Recording · 123 records" or "Off".
FOUNDATION_EXPORT NSString *TIOWireLogStatusLine(void);
