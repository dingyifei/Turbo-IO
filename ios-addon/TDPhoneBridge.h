#import <UIKit/UIKit.h>
UIViewController *TDDiagnosticsController(void);
BOOL TDDiagnosticsConsume(NSDictionary *event);
BOOL TDDiagnosticsPauseForOTA(void);
/* The capability bits the connected glasses reported in their last status sample (0 when unknown or another peer). */
uint32_t TDGlassesCaps(void);
/* YES when the connected glasses report the TMG8 caps bit (carousel menu layout). TMG7 and older glasses never do. */
BOOL TDGlassesReportTMG8Caps(void);
/* YES when the connected glasses report TD_CAP_KNOB_DETENT (the TMG9 bit): the knob detent is adjustable. TMG8 and older glasses never do. */
BOOL TDGlassesReportTMG9DetentCaps(void);
/* The detent of the last fresh status sample: the live D from TMG9 glasses (300..600 in steps of 50), the fixed 300 or 600 from older ones, 0 when unknown. */
uint32_t TDGlassesDetent(void);
/* Asks the glasses for a status sample so the two calls above can answer; false when a request cannot start now. */
BOOL TDGlassesCapsRefresh(void);
/* The firmware label of the connected glasses from their last status sample ("TMG6" covers TMG6 and TMG7), nil when unknown. */
NSString *TDGlassesFirmware(void);
