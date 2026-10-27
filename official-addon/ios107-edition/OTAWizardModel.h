#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TIOAutoUpdateState) {
    TIOAutoUpdateMissing = 0,
    TIOAutoUpdateOn = 1,
    TIOAutoUpdateOff = 2,
};

typedef NS_ENUM(NSInteger, TIOOTACheck) {
    TIOOTACheckOK = 0,
    TIOOTACheckFail = 1,
    TIOOTACheckPending = 2,
    TIOOTACheckAction = 3,
};

typedef NS_ENUM(NSInteger, TIOOTAPhase) {
    TIOOTAPhaseUnavailable = 0,
    TIOOTAPhaseReady = 1,
    TIOOTAPhaseAuthorized = 2,
    TIOOTAPhaseInstalling = 3,
    TIOOTAPhaseFailed = 4,
};

FOUNDATION_EXPORT TIOAutoUpdateState TIOOTAAutoUpdateState(NSDictionary *prefs);
FOUNDATION_EXPORT NSUInteger TIOOTAAutoUpdateKeyCount(NSDictionary *prefs);
FOUNDATION_EXPORT BOOL TIOOTAAutoUpdateFixable(NSDictionary *prefs);
FOUNDATION_EXPORT NSDictionary *TIOOTAWizardSnapshot(NSDictionary *inputs);
FOUNDATION_EXPORT NSString *TIOOTAWizardHubStatusKey(NSDictionary *snapshot);
FOUNDATION_EXPORT NSString *TIOOTAFormatClock(NSInteger seconds);
FOUNDATION_EXPORT NSArray<NSString *> *TIOOTAWizardFixtureNames(void);
FOUNDATION_EXPORT NSDictionary *TIOOTAWizardFixture(NSString *name);
