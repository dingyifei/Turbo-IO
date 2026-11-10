// The version policy of each phone release, written out by hand from releases.json (not from FirmwarePins.h),
// so a wrong generated value fails the tests that use it. Selected like FirmwarePins.h: TIO_RELEASE_<NAME>.
#import <Foundation/Foundation.h>
#if defined(TIO_RELEASE_C16)
static inline NSArray *TRPAccepted(void){return @[@"Strix OS 1.0.5.5",@"Strix OS 1.0.5.12"];}
static NSString *const TRPTarget=@"Strix OS 1.0.5.12";
static NSString *const TRPFolder=@"Strix_OS_1.0.5.12";
#elif defined(TIO_RELEASE_C17)
static inline NSArray *TRPAccepted(void){return @[@"Strix OS 1.0.5.12"];}
static NSString *const TRPTarget=@"Strix OS 1.0.5.5";
static NSString *const TRPFolder=@"Strix_OS_1.0.5.5";
#else
static inline NSArray *TRPAccepted(void){return @[@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5"];}
static NSString *const TRPTarget=@"Strix OS 1.0.5.5";
static NSString *const TRPFolder=@"Strix_OS_1.0.5.5";
#endif
// Every glasses version any release names, plus near misses: each one not in TRPAccepted() must be refused.
static inline NSArray *TRPKnown(void){return @[@"Strix OS 1.0.3.15",@"Strix OS 1.0.4.12",@"Strix OS 1.0.5.5",@"Strix OS 1.0.5.12",@"Strix OS 1.0.5.6",@"Strix OS 1.0.5.120",@"1.0.5.12",@"Strix OS 1.0.5.12 "];}
