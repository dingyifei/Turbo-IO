#import "AppleAICore.h"
#include <math.h>
static NSString *TAILanguage;
static NSString *(^TAIProvider)(void);
static NSLock *TAILock(void){static NSLock *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSLock new];TAILanguage=[NSBundle.mainBundle.preferredLocalizations.firstObject hasPrefix:@"zh"]?@"zh":@"en";});return lock;}
void TAISetUILanguage(NSString *language){NSLock *lock=TAILock();[lock lock];TAILanguage=[language hasPrefix:@"zh"]?@"zh":@"en";[lock unlock];}
void TAISetLanguageProvider(NSString *(^provider)(void)){NSLock *lock=TAILock();[lock lock];TAIProvider=[provider copy];[lock unlock];}
NSString *TAIText(NSString *en,NSString *zh){NSLock *lock=TAILock();[lock lock];NSString *(^provider)(void)=[TAIProvider copy];NSString *language=TAILanguage;[lock unlock];if(provider)language=provider();return [language hasPrefix:@"zh"]?zh:en;}
BOOL TIOAppleShouldUseAppleMode(NSInteger mode,BOOL voiceTurn){return mode==3&&voiceTurn;}
BOOL TIOAppleShouldFallback(NSInteger mode,BOOL voiceTurn,BOOL enabled,BOOL failed,NSUInteger length){return mode==2&&voiceTurn&&enabled&&failed&&!length;}
NSString *TIOAppleLanguageForText(NSString *text){NSUInteger han=0,ascii=0;for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];if((c>=0x3400&&c<=0x4dbf)||(c>=0x4e00&&c<=0x9fff)||(c>=0xf900&&c<=0xfaff))han++;else if((c>='A'&&c<='Z')||(c>='a'&&c<='z'))ascii++;}return han&&han*4>=ascii?@"zh":@"en";}
NSString *TIOAppleInstructions(NSString *language,NSString *aboutMe){NSMutableString *s=[@"You are a concise assistant; answers are shown on smart glasses. Answer in at most 80 words of plain text, no Markdown tables or code blocks. You have no tools and no internet access in this on-device mode; if asked to search the web, create todos, or give live information, say that is unavailable on-device." mutableCopy];if(aboutMe.length){NSRange range=[aboutMe rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,MIN((NSUInteger)300,aboutMe.length))];[s appendFormat:@"\nAbout the user: %@",[aboutMe substringWithRange:range]];}[s appendString:[language hasPrefix:@"zh"]?/*i18n:keep*/@"\nYou MUST respond in Simplified Chinese (简体中文).":@"\nYou MUST respond in English."];return s;}
NSString *TIOAppleFallbackMarker(NSString *language){return [language hasPrefix:@"zh"]?/*i18n:keep*/@"[本机模型] ":@"[On-device] ";}
BOOL TIOTranscribeNeedsTranscode(NSString *ext){return [@[@"opus",@"ogg",@"aac"] containsObject:ext.lowercaseString];}
NSArray<NSString *> *TIOTranscodeArguments(NSString *input,NSString *output){if(!input.length||!output.length||![input hasPrefix:@"/"]||![output hasPrefix:@"/"])return nil;return @[@"-nostdin",@"-hide_banner",@"-y",@"-i",input,@"-vn",@"-ac",@"1",@"-ar",@"16000",@"-c:a",@"pcm_s16le",@"-t",@"14400",output];}
NSString *TIOTranscriptLocaleFromProbe(NSString *probe){return [TIOAppleLanguageForText(probe) isEqual:@"zh"]?@"zh-CN":@"en-US";}
NSString *TIOTranscriptMarkdown(NSArray<NSDictionary *> *segments){NSMutableArray *lines=[NSMutableArray new];for(NSDictionary *segment in segments){if(![segment isKindOfClass:NSDictionary.class]||![segment[@"text"] isKindOfClass:NSString.class])continue;NSString *text=[segment[@"text"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!text.length)continue;double t=[segment[@"t"] respondsToSelector:@selector(doubleValue)]?[segment[@"t"] doubleValue]:0;if(!isfinite(t)||t<0||t>=9223372036854775808.0)t=0;long long value=(long long)t;NSString *stamp=value>=3600?[NSString stringWithFormat:@"[%lld:%02lld:%02lld]",value/3600,value/60%60,value%60]:[NSString stringWithFormat:@"[%02lld:%02lld]",value/60,value%60];[lines addObject:[NSString stringWithFormat:@"%@ %@",stamp,text]];}return [lines componentsJoinedByString:@"\n"];}
NSString *TIOAppleErrorMessage(NSString *code){
if([code isEqual:@"moduleMissing"])return TAIText(@"Apple AI module is not installed.",/*i18n:keep*/@"未安装 Apple 智能模块。");
if([code isEqual:@"loadFailed"])return TAIText(@"Apple AI module could not load.",/*i18n:keep*/@"Apple 智能模块加载失败。");
if([code isEqual:@"moduleOld"])return TAIText(@"Update the Apple AI module.",/*i18n:keep*/@"请更新 Apple 智能模块。");
if([code isEqual:@"osTooOld"])return TAIText(@"Requires iOS 26 or later.",/*i18n:keep*/@"需要 iOS 26 或更新版本。");
if([code isEqual:@"deviceNotEligible"])return TAIText(@"This device does not support Apple Intelligence.",/*i18n:keep*/@"此设备不支持 Apple 智能。");
if([code isEqual:@"appleIntelligenceNotEnabled"])return TAIText(@"Turn on Apple Intelligence; device and Siri languages must match.",/*i18n:keep*/@"请开启 Apple 智能，并保持设备语言与 Siri 语言一致。");
if([code isEqual:@"modelNotReady"])return TAIText(@"The on-device model is not ready.",/*i18n:keep*/@"本机模型尚未就绪。");
if([code isEqual:@"rateLimited"])return TAIText(@"The model is busy; try again shortly.",/*i18n:keep*/@"模型繁忙，请稍后重试。");
if([code isEqual:@"guardrail"])return TAIText(@"The model safety guardrail stopped this answer.",/*i18n:keep*/@"模型安全限制已停止此回答。");
if([code isEqual:@"refusal"])return TAIText(@"The on-device model declined this request.",/*i18n:keep*/@"本机模型拒绝了此请求。");
if([code isEqual:@"contextSize"])return TAIText(@"This request exceeds the model context.",/*i18n:keep*/@"此请求超出模型上下文限制。");
if([code isEqual:@"unsupportedLanguage"])return TAIText(@"The model does not support this language.",/*i18n:keep*/@"模型不支持此语言。");
if([code isEqual:@"concurrentRequests"])return TAIText(@"Another model request is running.",/*i18n:keep*/@"另一个模型请求正在运行。");
if([code isEqual:@"cancelled"])return TAIText(@"Cancelled.",/*i18n:keep*/@"已取消。");
if([code isEqual:@"assetsMissing"])return TAIText(@"Prepare the speech or translation packs first.",/*i18n:keep*/@"请先准备语音或翻译资源。");
if([code isEqual:@"localeUnsupported"])return TAIText(@"On-device speech is unavailable for this language.",/*i18n:keep*/@"此语言的本机语音识别不可用。");
if([code isEqual:@"decodeFailed"])return TAIText(@"Audio decoding failed; FFmpegKit may be unavailable.",/*i18n:keep*/@"音频解码失败，FFmpegKit 可能不可用。");
if([code isEqual:@"notAuthorized"])return TAIText(@"Allow speech recognition and microphone access in Settings.",/*i18n:keep*/@"请在设置中允许语音识别和麦克风访问。");
if([code isEqual:@"other"])return TAIText(@"Apple AI could not complete this request.",/*i18n:keep*/@"Apple 智能无法完成此请求。");
return TIOAppleErrorMessage(@"other");}
