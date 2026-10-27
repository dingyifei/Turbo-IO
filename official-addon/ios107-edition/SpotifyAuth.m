#import "SpotifyAuth.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSString *const TMSpotifyDefaultRedirect=@"io.turboio.spotify://callback";
NSString *const TMSpotifyLoopbackRedirect=@"http://127.0.0.1:43821/callback";
NSString *const TMSpotifyScopes=@"user-read-playback-state user-read-currently-playing user-modify-playback-state";
NSString *const TMSpotifyAuthChanged=@"TurboSpotifyAuthChangedV1";
static const NSUInteger TMTokenLimit=262144;
static void TMOnMain(void(^block)(void)){if(NSThread.isMainThread)block();else dispatch_async(dispatch_get_main_queue(),block);}
static void TMSyncMain(void(^block)(void)){if(NSThread.isMainThread)block();else dispatch_sync(dispatch_get_main_queue(),block);}
static BOOL TMString(id x,NSUInteger max){return [x isKindOfClass:NSString.class]&&[x length]>0&&[x length]<=max&&[x rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound;}
static BOOL TMMatches(NSString *s,NSString *pattern){if(![s isKindOfClass:NSString.class])return NO;NSRange r=[s rangeOfString:pattern options:NSRegularExpressionSearch];return r.location==0&&r.length==s.length;}
NSString *TMSpotifyBase64URL(NSData *data){if(![data isKindOfClass:NSData.class])return nil;NSString *s=[data base64EncodedStringWithOptions:0];s=[s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];s=[s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];}
NSString *TMSpotifyRandomURLSafe(NSUInteger bytes){if(!bytes||bytes>1024)return nil;NSMutableData *data=[NSMutableData dataWithLength:bytes];if(SecRandomCopyBytes(kSecRandomDefault,bytes,data.mutableBytes)!=errSecSuccess)return nil;return TMSpotifyBase64URL(data);}
NSString *TMSpotifyNewVerifier(void){return TMSpotifyRandomURLSafe(64);}
NSString *TMSpotifyChallenge(NSString *verifier){NSData *data=[verifier dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];if(!data||!TMMatches(verifier,@"^[A-Za-z0-9._~-]{43,128}$"))return nil;unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);return TMSpotifyBase64URL([NSData dataWithBytes:hash length:sizeof(hash)]);}
BOOL TMSpotifyValidClientID(NSString *s){return TMMatches(s,@"^[0-9a-fA-F]{32}$");}
static NSURLComponents *TMRedirect(NSString *s){
    if(!TMString(s,4096)||[s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:s];NSString *scheme=c.scheme.lowercaseString;
    if(!c.URL||!TMMatches(scheme,@"^[a-z][a-z0-9+.-]*$")||c.user||c.password||c.query||c.fragment)return nil;
    if([@[@"https",@"file",@"javascript"] containsObject:scheme])return nil;
    if([scheme isEqual:@"http"]){if(![c.host isEqual:@"127.0.0.1"]||!c.port||c.port.integerValue<1024||c.port.integerValue>65535||![c.path hasPrefix:@"/"]||c.path.length<2)return nil;
        NSString *prefix=[NSString stringWithFormat:@"http://127.0.0.1:%@/",c.port];if(![s hasPrefix:prefix])return nil;
    }else if((!c.host.length&&!c.path.length)||c.port)return nil;
    return c;
}
NSString *TMSpotifyRedirectScheme(NSString *redirect){return TMRedirect(redirect).scheme.lowercaseString;}
uint16_t TMSpotifyLoopbackPort(NSString *redirect){NSURLComponents *c=TMRedirect(redirect);return [c.scheme.lowercaseString isEqual:@"http"]?(uint16_t)c.port.unsignedIntegerValue:0;}
NSURL *TMSpotifyAuthorizeURL(NSString *clientID,NSString *redirect,NSString *challenge,NSString *state){
    if(!TMSpotifyValidClientID(clientID)||!TMRedirect(redirect)||!TMMatches(challenge,@"^[A-Za-z0-9_-]{43}$")||!TMString(state,512))return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:@"https://accounts.spotify.com/authorize"];
    c.queryItems=@[[NSURLQueryItem queryItemWithName:@"client_id" value:clientID],[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],[NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirect],[NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],[NSURLQueryItem queryItemWithName:@"code_challenge" value:challenge],[NSURLQueryItem queryItemWithName:@"scope" value:TMSpotifyScopes],[NSURLQueryItem queryItemWithName:@"state" value:state]];
    c.percentEncodedQuery=[c.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];return c.URL;
}
NSDictionary *TMSpotifyCallbackResult(NSURL *callback,NSString *redirect,NSString *state){
    if(![callback isKindOfClass:NSURL.class])return @{@"error":@"mismatch"};
    NSURLComponents *r=TMRedirect(redirect),*c=[NSURLComponents componentsWithURL:callback resolvingAgainstBaseURL:NO];
    if(!r||!c||callback.absoluteString.length>16384||c.user||c.password||c.fragment||![c.scheme.lowercaseString isEqual:r.scheme.lowercaseString]||![(c.host?:@"") isEqual:(r.host?:@"")]||![(c.port?:@0) isEqual:(r.port?:@0)]||![(c.percentEncodedPath?:@"") isEqual:(r.percentEncodedPath?:@"")]||c.percentEncodedQuery.length>8192)return @{@"error":@"mismatch"};
    NSMutableDictionary *q=[NSMutableDictionary dictionary];
    for(NSURLQueryItem *item in c.queryItems){if(!item.name.length||q[item.name]||!item.value||item.value.length>4096)return @{@"error":@"missing"};q[item.name]=item.value;}
    if(!TMString(state,512)||![q[@"state"] isEqual:state])return @{@"error":@"state"};
    if(q[@"code"]&&q[@"error"])return @{@"error":@"missing"};
    if(q[@"error"])return @{@"error":[q[@"error"] isEqual:@"access_denied"]?@"access_denied":@"missing"};
    return TMString(q[@"code"],4096)?@{@"code":q[@"code"]}:@{@"error":@"missing"};
}
NSURL *TMSpotifyLoopbackRequestURL(NSData *head,uint16_t port){
    if(port<1024||!head.length||head.length>8192)return nil;NSString *s=[[NSString alloc]initWithData:head encoding:NSASCIIStringEncoding];
    if(!s||![s hasSuffix:@"\r\n\r\n"]||[s rangeOfString:@"\r\n\r\n"].location!=s.length-4)return nil;
    NSArray *lines=[s componentsSeparatedByString:@"\r\n"],*parts=[lines[0] componentsSeparatedByString:@" "];
    if(parts.count!=3||![parts[0] isEqual:@"GET"]||![parts[2] isEqual:@"HTTP/1.1"])return nil;
    NSString *target=parts[1];if(![target hasPrefix:@"/"]||[target hasPrefix:@"//"]||target.length>4096||[target containsString:@"#"]||[target rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound||[target rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound||[target.lowercaseString containsString:@"%0d"]||[target.lowercaseString containsString:@"%0a"])return nil;
    NSMutableSet *names=[NSMutableSet set];
    for(NSUInteger i=1;i+2<lines.count;i++){NSString *line=lines[i];NSRange colon=[line rangeOfString:@":"];if(colon.location==NSNotFound||!colon.location)return nil;NSString *name=[[line substringToIndex:colon.location] lowercaseString];NSString *value=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(!TMMatches(name,@"^[a-z0-9!#$%&'*+.^_`|~-]+$")||[names containsObject:name]||[value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;[names addObject:name];if([name isEqual:@"host"]&&![value isEqual:[NSString stringWithFormat:@"127.0.0.1:%u",port]])return nil;if([name isEqual:@"transfer-encoding"]||([name isEqual:@"content-length"]&&![value isEqual:@"0"]))return nil;}
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u%@",port,target]];return [url.host isEqual:@"127.0.0.1"]&&url.port.unsignedIntegerValue==port&&!url.fragment?url:nil;
}
NSURLRequest *TMSpotifyTokenRequest(NSDictionary<NSString *,NSString *> *form){
    NSCharacterSet *set=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];NSMutableArray *parts=[NSMutableArray array];
    if(![form isKindOfClass:NSDictionary.class])return nil;for(id key in form){if(!TMString(key,128)||!TMString(form[key],65536))return nil;}
    for(NSString *key in [[form allKeys] sortedArrayUsingSelector:@selector(compare:)]){[parts addObject:[NSString stringWithFormat:@"%@=%@",[key stringByAddingPercentEncodingWithAllowedCharacters:set],[form[key] stringByAddingPercentEncodingWithAllowedCharacters:set]]];}
    NSData *body=[[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];if(body.length>TMTokenLimit)return nil;
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"]];r.HTTPMethod=@"POST";[r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];r.HTTPBody=body;return r;
}
NSDictionary *TMSpotifyParseToken(NSData *body,NSInteger status,NSDate *now){
    id j=body.length<=TMTokenLimit&&body.length?[NSJSONSerialization JSONObjectWithData:body options:0 error:NULL]:nil;NSDictionary *d=[j isKindOfClass:NSDictionary.class]?j:nil;
    if(status==200&&TMString(d[@"access_token"],65536)&&[now isKindOfClass:NSDate.class]){
        id exp=d[@"expires_in"];double seconds=[exp isKindOfClass:NSNumber.class]?[exp doubleValue]:3600;if(!isfinite(seconds)||seconds<=0||seconds>604800)return @{@"error":@"bad_response"};
        NSMutableDictionary *out=[@{@"access_token":d[@"access_token"],@"expires_at":[now dateByAddingTimeInterval:seconds]} mutableCopy];
        for(NSString *k in @[@"refresh_token",@"scope"]){if(d[k]&&!TMString(d[k],65536))return @{@"error":@"bad_response"};if(d[k])out[k]=d[k];}return out;
    }
    NSString *e=d[@"error"];return @{@"error":TMMatches(e,@"^[a-z][a-z0-9_]{0,63}$")?e:[NSString stringWithFormat:@"http_%ld",(long)status]};
}
static NSDictionary *TMStoredData(id input){if(![input isKindOfClass:NSDictionary.class]||!TMString(input[@"refresh_token"],65536)||!TMSpotifyValidClientID(input[@"client_id"]))return nil;NSMutableDictionary *d=[@{@"refresh_token":input[@"refresh_token"],@"client_id":input[@"client_id"]} mutableCopy];if(TMString(input[@"scope"],65536))d[@"scope"]=input[@"scope"];return d;}
@implementation TMSpotifyTokenStore {BOOL _keychain;NSDictionary *_memory;}
+ (instancetype)keychain{TMSpotifyTokenStore *s=[self new];s->_keychain=YES;return s;}
+ (instancetype)memory{return [self new];}
- (NSMutableDictionary *)query{return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"TurboIOSpotifyV1",(__bridge id)kSecAttrAccount:@"default"} mutableCopy];}
- (NSDictionary *)load{if(!_keychain)return _memory;NSMutableDictionary *q=[self query];q[(__bridge id)kSecReturnData]=@YES;q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef value=NULL;OSStatus result=SecItemCopyMatching((__bridge CFDictionaryRef)q,&value);id data=CFBridgingRelease(value);if(result!=errSecSuccess||![data isKindOfClass:NSData.class]||[data length]>TMTokenLimit)return nil;return TMStoredData([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]);}
- (BOOL)save:(NSDictionary *)input{NSDictionary *d=TMStoredData(input);if(!d)return NO;if(!_keychain){_memory=[d copy];return YES;}NSData *data=[NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];if(!data||data.length>TMTokenLimit)return NO;NSMutableDictionary *q=[self query];NSDictionary *attrs=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);if(result==errSecItemNotFound){[q addEntriesFromDictionary:attrs];result=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return result==errSecSuccess;}
- (void)remove{if(_keychain)SecItemDelete((__bridge CFDictionaryRef)[self query]);else _memory=nil;}
@end
@implementation TMSpotifyAuth {TMSpotifyHTTP _http;TMSpotifyTokenStore *_store;NSUserDefaults *_defaults;NSDate *(^_clock)(void);BOOL _loaded;NSDictionary *_stored,*_pending;NSString *_access;NSDate *_expires;NSUInteger _epoch;BOOL _refreshing;NSMutableArray *_waiters;}
+ (instancetype)shared{static TMSpotifyAuth *s;static dispatch_once_t once;dispatch_once(&once,^{s=[[self alloc]initWithHTTP:TMSpotifyDefaultHTTP() store:TMSpotifyTokenStore.keychain defaults:NSUserDefaults.standardUserDefaults clock:^{return NSDate.date;}];});return s;}
- (instancetype)initWithHTTP:(TMSpotifyHTTP)http store:(TMSpotifyTokenStore *)store defaults:(NSUserDefaults *)defaults clock:(NSDate *(^)(void))clock{if((self=[super init])){_http=[http copy];_store=store;_defaults=defaults;_clock=[clock copy];_waiters=[NSMutableArray array];}return self;}
- (NSString *)clientID{__block NSString *s;TMSyncMain(^{id v=[self->_defaults objectForKey:@"TurboSpotifyClientIDV1"];s=[v isKindOfClass:NSString.class]?v:@"";});return s;}
- (NSString *)redirect{__block NSString *s;TMSyncMain(^{id v=[self->_defaults objectForKey:@"TurboSpotifyRedirectV1"];s=TMSpotifyRedirectScheme(v)?v:TMSpotifyDefaultRedirect;});return s;}
- (void)changed{[NSNotificationCenter.defaultCenter postNotificationName:TMSpotifyAuthChanged object:self];}
- (void)finishWaiters:(NSString *)token error:(NSString *)error{NSArray *a=[_waiters copy];[_waiters removeAllObjects];_refreshing=NO;NSUInteger epoch=_epoch;NSString *client=self.clientID;for(void(^b)(NSString *,NSString *) in a)dispatch_async(dispatch_get_main_queue(),^{if(epoch!=self->_epoch||![client isEqual:self.clientID])b(nil,@"signed_out");else b(token,error);});}
- (void)advance{_epoch++;_pending=nil;_access=nil;_expires=nil;[self finishWaiters:nil error:@"signed_out"];}
- (BOOL)setClientIDString:(NSString *)value{if(![value isKindOfClass:NSString.class])return NO;NSString *s=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!TMSpotifyValidClientID(s))return NO;TMSyncMain(^{if(![self.clientID isEqual:s]){[self advance];[self->_defaults setObject:s forKey:@"TurboSpotifyClientIDV1"];[self changed];}});return YES;}
- (void)setRedirect:(NSString *)value{if(!TMSpotifyRedirectScheme(value))return;TMSyncMain(^{if(![self.redirect isEqual:value]){[self advance];[self->_defaults setObject:value forKey:@"TurboSpotifyRedirectV1"];[self changed];}});}
- (BOOL)signedIn{__block BOOL yes;TMSyncMain(^{if(!self->_loaded){self->_stored=TMStoredData([self->_store load]);self->_loaded=YES;}yes=TMString(self->_stored[@"refresh_token"],65536)&&[self->_stored[@"client_id"] isEqual:self.clientID];});return yes;}
- (NSURL *)beginSignIn{__block NSURL *url;TMSyncMain(^{[self advance];NSString *client=self.clientID;if(!TMSpotifyValidClientID(client))return;NSString *verifier=TMSpotifyNewVerifier(),*state=TMSpotifyRandomURLSafe(16),*redirect=self.redirect;url=TMSpotifyAuthorizeURL(client,redirect,TMSpotifyChallenge(verifier),state);if(url)self->_pending=@{@"verifier":verifier,@"state":state,@"redirect":redirect,@"client_id":client};});return url;}
- (void)cancelPendingSignIn{TMSyncMain(^{[self advance];});}
- (void)finishSignInWithCallback:(NSURL *)url done:(void(^)(NSString *))done{TMOnMain(^{NSDictionary *pending=self->_pending;self->_pending=nil;if(!pending){done(@"missing");return;}NSDictionary *cb=TMSpotifyCallbackResult(url,pending[@"redirect"],pending[@"state"]);if(cb[@"error"]){done(cb[@"error"]);return;}NSUInteger epoch=self->_epoch;NSString *client=pending[@"client_id"];NSURLRequest *request=TMSpotifyTokenRequest(@{@"grant_type":@"authorization_code",@"code":cb[@"code"],@"redirect_uri":pending[@"redirect"],@"client_id":client,@"code_verifier":pending[@"verifier"]});if(!request){done(@"bad_response");return;}self->_http(request,^(NSData *body,NSHTTPURLResponse *r,NSError *e){TMOnMain(^{if(epoch!=self->_epoch||![client isEqual:self.clientID]){done(@"cancelled");return;}if(e||r.statusCode>=500){done(@"network");return;}NSDictionary *token=TMSpotifyParseToken(body,r.statusCode,self->_clock());if(token[@"error"]){done(token[@"error"]);return;}NSMutableDictionary *stored=[@{@"client_id":client} mutableCopy];if(token[@"refresh_token"])stored[@"refresh_token"]=token[@"refresh_token"];if(token[@"scope"])stored[@"scope"]=token[@"scope"];if(!TMStoredData(stored)){done(@"bad_response");return;}if(![self->_store save:stored]){done(@"storage");return;}self->_stored=[stored copy];self->_loaded=YES;self->_access=token[@"access_token"];self->_expires=token[@"expires_at"];[self changed];done(epoch==self->_epoch?nil:@"cancelled");});});});}
- (void)accessToken:(void(^)(NSString *,NSString *))done{TMOnMain(^{NSString *client=self.clientID;if(!TMSpotifyValidClientID(client)){done(nil,@"not_configured");return;}if(!self.signedIn){done(nil,@"signed_out");return;}if(self->_access&&[self->_expires timeIntervalSinceDate:self->_clock()]>60){done(self->_access,nil);return;}[self->_waiters addObject:[done copy]];if(self->_refreshing)return;self->_refreshing=YES;NSUInteger epoch=self->_epoch;NSDictionary *old=self->_stored;NSURLRequest *request=TMSpotifyTokenRequest(@{@"grant_type":@"refresh_token",@"refresh_token":old[@"refresh_token"],@"client_id":client});if(!request){[self finishWaiters:nil error:@"bad_response"];return;}self->_http(request,^(NSData *body,NSHTTPURLResponse *r,NSError *e){TMOnMain(^{if(epoch!=self->_epoch||![client isEqual:self.clientID])return;if(e||r.statusCode>=500){[self finishWaiters:nil error:@"network"];return;}NSDictionary *token=TMSpotifyParseToken(body,r.statusCode,self->_clock());if([token[@"error"] isEqual:@"invalid_grant"]){[self->_store remove];self->_stored=nil;self->_loaded=YES;self->_access=nil;self->_expires=nil;[self changed];[self finishWaiters:nil error:@"signed_out"];return;}if(token[@"error"]){[self finishWaiters:nil error:token[@"error"]];return;}NSMutableDictionary *stored=[old mutableCopy];for(NSString *key in @[@"refresh_token",@"scope"])if(token[key])stored[key]=token[key];if(![self->_store save:stored]){[self finishWaiters:nil error:@"storage"];return;}self->_stored=[stored copy];self->_access=token[@"access_token"];self->_expires=token[@"expires_at"];[self finishWaiters:self->_access error:nil];});});});}
- (void)invalidateAccessToken{TMSyncMain(^{self->_access=nil;self->_expires=nil;});}
- (void)signOut{TMSyncMain(^{[self advance];[self->_store remove];self->_stored=nil;self->_loaded=YES;[self changed];});}
@end
