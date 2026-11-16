#import "AppleAICore.h"
#include <assert.h>
int main(void){@autoreleasepool{
for(NSInteger mode=0;mode<=3;mode++)for(int voice=0;voice<2;voice++)assert(TIOAppleShouldUseAppleMode(mode,voice)==(mode==3&&voice));
assert(TIOAppleShouldFallback(2,YES,YES,YES,0));assert(!TIOAppleShouldFallback(3,YES,YES,YES,0));assert(!TIOAppleShouldFallback(2,NO,YES,YES,0));assert(!TIOAppleShouldFallback(2,YES,NO,YES,0));assert(!TIOAppleShouldFallback(2,YES,YES,NO,0));assert(!TIOAppleShouldFallback(2,YES,YES,YES,1));
__block NSString *language=@"zh";TAISetLanguageProvider(^{return language;});assert([TAIText(@"English",@"Chinese") isEqual:@"Chinese"]);language=@"en";assert([TAIText(@"English",@"Chinese") isEqual:@"English"]);TAISetLanguageProvider(nil);
for(NSString *lang in @[@"en",@"zh"]){TAISetUILanguage(lang);for(NSString *code in @[@"moduleMissing",@"loadFailed",@"moduleOld",@"osTooOld",@"deviceNotEligible",@"appleIntelligenceNotEnabled",@"modelNotReady",@"rateLimited",@"guardrail",@"refusal",@"contextSize",@"unsupportedLanguage",@"concurrentRequests",@"cancelled",@"assetsMissing",@"localeUnsupported",@"decodeFailed",@"notAuthorized",@"other"]){assert(TIOAppleErrorMessage(code).length);}assert([TIOAppleErrorMessage(@"unknown") isEqual:TIOAppleErrorMessage(@"other")]);}
assert([TIOAppleLanguageForText(@"Hello world") isEqual:@"en"]);assert([TIOAppleLanguageForText(@"你好") isEqual:@"zh"]);assert([TIOAppleLanguageForText(@"用 Swift 写一个 app") isEqual:@"zh"]);assert([TIOAppleLanguageForText(@"What does 你好 mean in English") isEqual:@"en"]);
NSString *about=[@"x" stringByPaddingToLength:400 withString:@"x" startingAtIndex:0];NSString *en=TIOAppleInstructions(@"en",about);assert([en containsString:@"You MUST respond in English."]&&[en containsString:@"You have no tools"]&&![en containsString:about]);assert([TIOAppleInstructions(@"zh",nil) containsString:@"Simplified Chinese"]);
assert([TIOAppleFallbackMarker(@"en") isEqual:@"[On-device] "]);assert([TIOAppleFallbackMarker(@"zh") hasSuffix:@"] "]);
for(NSString *ext in @[@"opus",@"OGG",@"AAC"])assert(TIOTranscribeNeedsTranscode(ext));for(NSString *ext in @[@"mp3",@"wav",@"m4a"])assert(!TIOTranscribeNeedsTranscode(ext));
assert(!TIOTranscodeArguments(@"relative",@"/out"));assert(!TIOTranscodeArguments(@"/in",@""));NSArray *args=TIOTranscodeArguments(@"/in",@"/out");assert(args.count==15&&[args[4] isEqual:@"/in"]&&[args[14] isEqual:@"/out"]&&[args[11] isEqual:@"pcm_s16le"]);
assert([TIOTranscriptLocaleFromProbe(@"你好") isEqual:@"zh-CN"]);assert([TIOTranscriptLocaleFromProbe(@"hello") isEqual:@"en-US"]);
assert([TIOTranscriptMarkdown(@[@{@"t":@0,@"text":@" hi "},@{@"t":@3,@"text":@" "},@{@"t":@65,@"text":@"你好"}]) isEqual:@"[00:00] hi\n[01:05] 你好"]);
assert([TIOTranscriptMarkdown(@[@{@"t":@(NAN),@"text":@"x"},@{@"t":@3600,@"text":@"y"}]) isEqual:@"[00:00] x\n[1:00:00] y"]);
puts("PASS Apple AI core");}return 0;}
