#import <Foundation/Foundation.h>
NSString *TDCIdentifier(void);
NSString *TDCDemoText(BOOL alternate);
NSData *TDCRequest(uint32_t sequence,NSDictionary *json);
NSDictionary *TDCInstall(NSString *text);
NSDictionary *TDCMoveFirst(NSDictionary *snapshot);
BOOL TDCOrderVerified(NSDictionary *before,NSDictionary *after);
BOOL TDCValidSnapshot(NSDictionary *snapshot);
void TDCObserveEvent(NSDictionary *event);
// Glasses test bench (ds3 p2), implemented in DashboardPhone.m. Main thread, explicit user action only. TDCBenchInstall takes the card text
// ("TDC1;..."), refuses anything dc_parse refuses and sends nothing during an OTA stage; the other calls report on the same sequence.
BOOL TDCBenchInstall(NSString *text);
BOOL TDCBenchRemove(void);
BOOL TDCBenchBusy(void);
NSString *TDCBenchNote(void);
@class UIViewController;
UIViewController *TDCDashboardController(void);
