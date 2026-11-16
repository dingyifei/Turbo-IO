// The version policy of the phone release, written out by hand from releases.json (not from FirmwarePins.h),
// so a wrong generated value fails the tests that use it.
#import <Foundation/Foundation.h>
// C21, the only release (TMG12 on stock 1.0.6.11, for the 1.0.21 full host): flashes glasses that report 1.0.5.12
// (TMG11) or 1.0.6.11. Its releases.json entry must say the same, or these tests fail.
static inline NSArray *TRPAccepted(void){return @[@"Strix OS 1.0.5.12",@"Strix OS 1.0.6.11"];}
static NSString *const TRPTarget=@"Strix OS 1.0.6.11";
static NSString *const TRPFolder=@"Strix_OS_1.0.6.11";
// Every glasses version any release names, plus near misses: each one not in TRPAccepted() must be refused.
static inline NSArray *TRPKnown(void){return @[@"Strix OS 1.0.3.15",@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5",@"Strix OS 1.0.5.12",@"Strix OS 1.0.5.6",@"Strix OS 1.0.5.120",@"1.0.5.12",@"Strix OS 1.0.5.12 ",@"Strix OS 1.0.6.11",@"Strix OS 1.0.6.1",@"1.0.6.11"];}
