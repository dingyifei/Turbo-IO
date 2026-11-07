#import <UIKit/UIKit.h>

// Stock firmware export panel for the download-only 1.0.11 host (FirmwareExport.h).
FOUNDATION_EXPORT UIViewController *TIOFirmwareExportController(void);
// One-line hub status: download-only and blocked, or a guard warning.
FOUNDATION_EXPORT NSString *TIOFirmwareExportHubStatus(void);
