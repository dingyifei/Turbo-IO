#pragma once
#import <Foundation/Foundation.h>
#import "TIOScript.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSInteger TIOVoiceTTSSpeedStep(NSUserDefaults *prefs);
FOUNDATION_EXPORT double TIOVoiceTTSSpeedMultiplier(NSUserDefaults *prefs);
FOUNDATION_EXPORT NSString * _Nullable TIOVoiceTTSChunk(NSString *pending, BOOL final, NSUInteger * _Nullable consumed);
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *,NSString *> *> *TIOVoiceTTSRuns(NSString *chunk, NSString * _Nullable fallbackLanguage);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOVoiceTTSPickVoice(NSArray<NSDictionary *> *voices, NSString * _Nullable language);
FOUNDATION_EXPORT NSString *TIOVoiceTTSStatusText(NSString *state, BOOL bluetooth, NSString * _Nullable language);
NS_ASSUME_NONNULL_END
