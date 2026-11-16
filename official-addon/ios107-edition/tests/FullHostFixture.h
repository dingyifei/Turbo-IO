// The full host the full-host tests run against: RayNeo AI 1.0.21/1 with the packager's full-profile
// marker (ios1021, C20 onward). The TFH_* names keep the tests independent of the host's spelling.
#import "OTAHost.h"
#define TFH_D "1021"
#define TFH_N 1021
#define TFH_FULLWIDTH @"ｉｏｓ１０２１"
#define TFH_NAME "1.0.21"
#define TFH_VERSION @"1.0.21"
#define TFH_BUILD @"1"
#define TFH_NEXT_BUILD @"2"
#define TFH_PROFILE @"ios1021"
#define TFH_UUID @"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"
#define TFH_HOST_MATCHES TIOOTA1021HostMatches
// Values that must never select this host: a neighbouring profile name and app versions that are not this host's.
#define TFH_NEAR_PROFILE @"ios1022"
#define TFH_NEAR_VERSION @"1.0.20"
#define TFH_NEAR_BUILD @"0"
// Near misses of this host's profile marker: case, padding, a NUL, an O for a 0,
// full-width, a zero-width space, suffixes, a prefix, other types, and neighbouring and retired names.
static inline NSArray *TFHMarkerMisses(void){
    return @[@"IOS" TFH_D,@"Ios" TFH_D,@"ios" TFH_D " ",@" ios" TFH_D,@"ios" TFH_D "\n",[TFH_PROFILE stringByAppendingFormat:@"%C",(unichar)0],
        [TFH_PROFILE stringByReplacingOccurrencesOfString:@"0" withString:@"O"],TFH_FULLWIDTH,[TFH_PROFILE stringByAppendingString:@"​"],
        @"ios" TFH_D "-full",@"ios" TFH_D "0",[TFH_PROFILE substringToIndex:6],@"",@"ios1020",TFH_NEAR_PROFILE,@"ios1021-download",@"ios1011",
        NSNull.null,@TFH_N,@YES,@[TFH_PROFILE],@{TFH_PROFILE:@YES},[TFH_PROFILE dataUsingEncoding:NSUTF8StringEncoding],[NSURL URLWithString:TFH_PROFILE]];
}
static inline NSDictionary *TFHFullInfo(void){
    return @{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":TFH_VERSION,@"CFBundleVersion":TFH_BUILD,
        @"TIOHostProfile":TFH_PROFILE};
}
