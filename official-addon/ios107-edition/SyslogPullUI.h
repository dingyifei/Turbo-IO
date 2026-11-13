#import <Foundation/Foundation.h>
// Sensor log hub row: one biz 0x10 A1/12 request through the stock send route, then passive
// observation of the 0x10 notices and the file-share bytes. Never consumes or answers anything.
void TIOSyslogObserveCall(id plugin,NSString *method,NSDictionary *args);
BOOL TIOSyslogCapturing(void);                   // cheap gate for the inbound hook
void TIOSyslogObserveEvent(NSDictionary *event); // main thread; reads only
@class UIViewController;
UIViewController *TIOSyslogPullController(void);
