#import <UIKit/UIKit.h>
UIViewController *TDDiagnosticsController(void);
BOOL TDDiagnosticsConsume(NSDictionary *event);
BOOL TDDiagnosticsPauseForOTA(void);
/* The capability bits the connected glasses reported in their last status sample (0 when unknown or another peer). */
uint32_t TDGlassesCaps(void);
/* YES when the connected glasses report the TMG8 caps bit (carousel menu layout). TMG7 and older glasses never do. */
BOOL TDGlassesReportTMG8Caps(void);
/* Asks the glasses for a status sample so the two calls above can answer; false when a request cannot start now. */
BOOL TDGlassesCapsRefresh(void);
