#import "NoNetworkTurn.h"
#include <math.h>

@implementation TIONoNetworkSnapshot
- (instancetype)init { if((self=[super init])){_sid=@"";_asr=@"";}return self; }
@end

BOOL TIONoNetworkModeEligible(NSInteger mode, BOOL fallback) { return mode==3||(mode==2&&fallback); }
NSTimeInterval TIONoNetworkDelay(BOOL known, BOOL satisfied, NSNumber *preference) {
    if(known&&!satisfied)return 0.7;
    double value=[preference isKindOfClass:NSNumber.class]?preference.doubleValue:6;
    if(!isfinite(value))value=6;
    return fmin(15,fmax(3,value));
}
NSString *TIONoNetworkQuestion(NSString *text) {
    NSString *trim=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]?:@"";
    NSUInteger capitals=0;
    for(NSUInteger i=0;i<trim.length;i++){
        unichar c=[trim characterAtIndex:i];
        if((c>=0x3400&&c<=0x4dbf)||(c>=0x4e00&&c<=0x9fff)||(c>=0xf900&&c<=0xfaff)||(c>='a'&&c<='z'))return trim;
        if(c>='A'&&c<='Z')capitals++;
    }
    if(capitals<2)return trim;
    NSMutableString *result=[trim.lowercaseString mutableCopy];
    BOOL sentence=YES, punctuation=NO;
    NSCharacterSet *space=NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for(NSUInteger i=0;i<result.length;i++){
        unichar c=[result characterAtIndex:i];
        if(sentence&&c>='a'&&c<='z'){
            [result replaceCharactersInRange:NSMakeRange(i,1) withString:[[result substringWithRange:NSMakeRange(i,1)] uppercaseString]];
            sentence=NO;
        }
        if(c=='.'||c=='?'||c=='!')punctuation=YES;
        else if([space characterIsMember:c]){if(punctuation)sentence=YES;}
        else punctuation=NO;
    }
    NSRegularExpression *pronoun=[NSRegularExpression regularExpressionWithPattern:@"\\bi\\b" options:0 error:NULL];
    return [pronoun stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0,result.length) withTemplate:@"I"];
}

@interface TIONoNetworkState ()
@property(nonatomic,readwrite) TIONoNetworkPhase phase;
@property(nonatomic,readwrite) NSUInteger epoch, controllerGeneration;
@property(nonatomic,weak,readwrite) id listener;
@property(nonatomic,copy,readwrite) NSString *sid, *text;
@property(nonatomic,readwrite) NSTimeInterval tailUntil;
@property(nonatomic) NSMutableArray<NSArray *> *seen;
@property(nonatomic) NSMutableSet<NSArray *> *identities;
@property(nonatomic) NSMutableArray<NSDictionary *> *ring;
@end
@implementation TIONoNetworkState
- (instancetype)init {if((self=[super init])){_seen=[NSMutableArray new];_identities=[NSMutableSet new];_ring=[NSMutableArray new];_sid=@"";_text=@"";}return self;}
- (void)arm:(id)listener sid:(NSString *)sid text:(NSString *)text generation:(NSUInteger)generation {
    ++_epoch;_phase=TIONoNetworkArmed;_listener=listener;_sid=[sid copy];_text=[text copy];_controllerGeneration=generation;_tailUntil=0;
}
- (void)beginTakeover {if(_phase==TIONoNetworkArmed)_phase=TIONoNetworkTaking;}
- (void)acquire {if(_phase==TIONoNetworkTaking)_phase=TIONoNetworkOwned;}
- (void)finishAt:(NSTimeInterval)now {if(_phase==TIONoNetworkOwned){_phase=TIONoNetworkTail;_tailUntil=now+3;}}
- (void)clear {++_epoch;_phase=TIONoNetworkIdle;_listener=nil;_sid=@"";_text=@"";_tailUntil=0;}
- (BOOL)hasSeenSid:(NSString *)sid text:(NSString *)text {return [_identities containsObject:@[sid?:@"",text?:@""]];}
- (void)rememberSid:(NSString *)sid text:(NSString *)text {
    NSArray *key=@[[sid copy]?:@"",[text copy]?:@""];if([_identities containsObject:key])return;
    if(_seen.count==256){[_identities removeObject:_seen.firstObject];[_seen removeObjectAtIndex:0];}
    [_seen addObject:key];[_identities addObject:key];
}
- (void)record:(NSString *)event at:(NSTimeInterval)now sid:(NSString *)sid {
    static NSSet *allowed;static dispatch_once_t once;dispatch_once(&once,^{allowed=[NSSet setWithArray:@[
        @"arm",@"skip:mode",@"skip:unverified",@"skip:hooks",@"skip:dup",@"skip:empty",@"skip:owned",@"skip:ingress",@"skip:overflow",
        @"cancel:speech",@"cancel:audio",@"cancel:nlp-eligible",@"cancel:nlp-command",@"cancel:nlp-online",@"cancel:exit",
        @"hold",@"fire",@"takeover-ok",@"takeover-refused",@"wrapper-missing",@"drop-nlp",@"swallow-error",@"replay-held",@"tail-end",
        @"net:sat",@"net:unsat",@"error-hook:on",@"error-hook:skip",@"fg:on",@"fg:fail",@"stop-host"]];});
    if(![allowed containsObject:event])return;
    uint32_t hash=2166136261u;NSData *bytes=[(sid?:@"") dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p=bytes.bytes;for(NSUInteger i=0;i<bytes.length;i++){hash^=p[i];hash*=16777619u;}
    if(!isfinite(now)||now<0)now=0;
    NSDictionary *row=@{@"t":@(round(now*100)/100),@"ev":[event copy],@"sid":[NSString stringWithFormat:@"%04x",hash&0xffff]};
    if(_ring.count==64)[_ring removeObjectAtIndex:0];[_ring addObject:row];
}
- (NSArray<NSDictionary *> *)timeline {return [_ring copy];}
@end
