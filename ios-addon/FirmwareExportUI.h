#import <UIKit/UIKit.h>

// Stock firmware export panel for the 1.0.21 host, download-only and full (FirmwareExport.h).
FOUNDATION_EXPORT UIViewController *TIOFirmwareExportController(void);
// One-line hub status: download-only and blocked, or a guard warning.
FOUNDATION_EXPORT NSString *TIOFirmwareExportHubStatus(void);
