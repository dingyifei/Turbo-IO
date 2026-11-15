// The full host a full-host test runs against. test.py builds the same test files twice:
// without TIO_TEST_HOST_1021 for the full 1.0.11/259 host (ios1011, C15-C18), and with
// -DTIO_TEST_HOST_1021=1 for the full 1.0.21/1 host (ios1021, C20). Every assertion is the
// same on both; only the host's identity below differs. The OTHER_* values name the other
// full host, whose markers must never select or arm this one.
#import "OTAHost.h"
#if TIO_TEST_HOST_1021
#define TFH_D "1021"
#define TFH_N 1021
#define TFH_FULLWIDTH @"ｉｏｓ１０２１"
#define TFH_NAME "1.0.21"
#define TFH_VERSION @"1.0.21"
#define TFH_BUILD @"1"
#define TFH_NEXT_BUILD @"2"
#define TFH_PROFILE @"ios1021"
#define TFH_ROUTING TIO_OTA_1021_ROUTING_MARKER
#define TFH_UUID @"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"
#define TFH_ARM_KEY @"otaFlashArmRecord.ios1021"
#define TFH_HOST_MATCHES TIOOTA1021HostMatches
#define TFH_OTHER_PROFILE @"ios1011"
#define TFH_OTHER_ROUTING TIO_OTA_1011_ROUTING_MARKER
#define TFH_OTHER_ARM_KEY @"otaFlashArmRecord.ios1011"
#define TFH_OTHER_HOST_MATCHES TIOOTA1011HostMatches
#else
#define TFH_D "1011"
#define TFH_N 1011
#define TFH_FULLWIDTH @"ｉｏｓ１０１１"
#define TFH_NAME "1.0.11"
#define TFH_VERSION @"1.0.11"
#define TFH_BUILD @"259"
#define TFH_NEXT_BUILD @"260"
#define TFH_PROFILE @"ios1011"
#define TFH_ROUTING TIO_OTA_1011_ROUTING_MARKER
#define TFH_UUID @"22724C97-2EF9-388D-8E6A-6E051855A555"
#define TFH_ARM_KEY @"otaFlashArmRecord.ios1011"
#define TFH_HOST_MATCHES TIOOTA1011HostMatches
#define TFH_OTHER_PROFILE @"ios1021"
#define TFH_OTHER_ROUTING TIO_OTA_1021_ROUTING_MARKER
#define TFH_OTHER_ARM_KEY @"otaFlashArmRecord.ios1021"
#define TFH_OTHER_HOST_MATCHES TIOOTA1021HostMatches
#endif
// Near misses of this host's profile marker (and arm record host): case, padding, a NUL, an O for a 0,
// full-width, a zero-width space, suffixes, a prefix, other types, and the other hosts' names.
static inline NSArray *TFHMarkerMisses(void){
    return @[@"IOS" TFH_D,@"Ios" TFH_D,@"ios" TFH_D " ",@" ios" TFH_D,@"ios" TFH_D "\n",[TFH_PROFILE stringByAppendingFormat:@"%C",(unichar)0],
        [TFH_PROFILE stringByReplacingOccurrencesOfString:@"0" withString:@"O"],TFH_FULLWIDTH,[TFH_PROFILE stringByAppendingString:@"\u200B"],
        @"ios" TFH_D "-full",@"ios" TFH_D "0",[TFH_PROFILE substringToIndex:6],@"",@"ios107",TFH_OTHER_PROFILE,@"ios1021-download",@"ios1011-download",
        NSNull.null,@TFH_N,@YES,@[TFH_PROFILE],@{TFH_PROFILE:@YES},[TFH_PROFILE dataUsingEncoding:NSUTF8StringEncoding],[NSURL URLWithString:TFH_PROFILE]];
}
// The arm refusal for a build that is not a full host (ExperimentalOTAFlash.m TIOOTAFlashArm).
#define TFH_ARM_REFUSED @"只有完整版 1.0.11 或 1.0.21 宿主需要并允许启用 TMG 刷写；未启用。"
static inline NSDictionary *TFHFullInfo(void){
    return @{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":TFH_VERSION,@"CFBundleVersion":TFH_BUILD,
        @"TIOHostProfile":TFH_PROFILE,@"TIOExperimentalOTAQueryRouting":TFH_ROUTING};
}
