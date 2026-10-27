#import "SpotifyAPI.h"
#import <math.h>
static void TMAPIOnMain(void(^block)(void)){if(NSThread.isMainThread)block();else dispatch_async(dispatch_get_main_queue(),block);}
static id TMJSON(NSData *body){return body.length&&body.length<=4*1024*1024?[NSJSONSerialization JSONObjectWithData:body options:0 error:NULL]:nil;}
static NSString *TMAPIString(id value){return [value isKindOfClass:NSString.class]?value:nil;}
static NSDictionary *TMAPIDict(id value){return [value isKindOfClass:NSDictionary.class]?value:nil;}
static NSArray *TMAPIArray(id value){return [value isKindOfClass:NSArray.class]?value:nil;}
static NSNumber *TMMilliseconds(id value,double cap){if(![value isKindOfClass:NSNumber.class])return nil;double d=[value doubleValue];if(!isfinite(d))return nil;return @(fmin(cap,fmax(0,d)));}
TMSpotifyErrorKind TMSpotifyClassify(NSData *body,NSHTTPURLResponse *r,NSError *e,NSTimeInterval *retryAfter){
    if(retryAfter)*retryAfter=0;if(e)return TMSpotifyNetwork;if(![r isKindOfClass:NSHTTPURLResponse.class])return TMSpotifyBadResponse;NSInteger status=r.statusCode;
    if(status==200||status==201||status==202||status==204)return TMSpotifyOK;
    if(status==401)return TMSpotifySignedOut;
    if(status==403){NSDictionary *j=TMAPIDict(TMJSON(body));NSString *reason=TMAPIString(TMAPIDict(j[@"error"])[@"reason"]);return [reason isEqual:@"PREMIUM_REQUIRED"]?TMSpotifyPremiumRequired:TMSpotifyRestricted;}
    if(status==404)return TMSpotifyNoActiveDevice;
    if(status==429){NSString *s;for(id key in r.allHeaderFields)if([key isKindOfClass:NSString.class]&&[key caseInsensitiveCompare:@"Retry-After"]==NSOrderedSame){id value=r.allHeaderFields[key];s=[value isKindOfClass:NSString.class]?value:[value isKindOfClass:NSNumber.class]?[value stringValue]:nil;break;}
        double seconds=5;if(s.length&&[s rangeOfString:@"^[-+]?[0-9]+$" options:NSRegularExpressionSearch].location!=NSNotFound){double parsed=s.doubleValue;seconds=isfinite(parsed)?parsed:120;}if(retryAfter)*retryAfter=fmin(120,fmax(1,seconds));return TMSpotifyRateLimited;}
    if(status>=500&&status<=599)return TMSpotifyServer;return TMSpotifyBadResponse;
}
NSURL *TMSpotifyImageURL(NSArray *images){
    if(![images isKindOfClass:NSArray.class])return nil;NSURL *bestAbove,*bestBelow;double above=INFINITY,below=-1;
    for(id entry in images){NSDictionary *d=TMAPIDict(entry);NSString *s=TMAPIString(d[@"url"]);NSURLComponents *c=s.length>0&&s.length<=8192?[NSURLComponents componentsWithString:s]:nil;NSString *host=c.host.lowercaseString;
        BOOL allowed=[host isEqual:@"i.scdn.co"]||[host isEqual:@"mosaic.scdn.co"]||[host hasSuffix:@".scdn.co"]||[host hasSuffix:@".spotifycdn.com"];
        if(!allowed||![c.scheme.lowercaseString isEqual:@"https"]||c.user||c.password||c.fragment||(c.port&&c.port.integerValue!=443)||!c.URL)continue;
        NSNumber *w=TMMilliseconds(d[@"width"],100000);if(!w)continue;double width=w.doubleValue;if(width>=144&&width<above){above=width;bestAbove=c.URL;}else if(width<144&&width>below){below=width;bestBelow=c.URL;}
    }return bestAbove?:bestBelow;
}
NSDictionary *TMSpotifyStateFromPlayer(NSDictionary *json){
    NSDictionary *j=TMAPIDict(json),*item=TMAPIDict(j[@"item"]);if(!item)return nil;NSMutableDictionary *s=[NSMutableDictionary dictionary];
    for(NSString *key in @[@"id",@"type"]){NSString *v=TMAPIString(item[key]);if(v)s[key]=v;}NSString *title=TMAPIString(item[@"name"]);if(title)s[@"title"]=title;
    BOOL episode=[TMAPIString(item[@"type"]) isEqual:@"episode"];NSDictionary *album=TMAPIDict(item[episode?@"show":@"album"]);NSString *albumName=TMAPIString(album[@"name"]);if(albumName)s[@"album"]=albumName;
    if(episode){if(albumName)s[@"artist"]=albumName;}else{NSArray *artists=TMAPIArray(item[@"artists"]);if(artists){NSMutableArray *names=[NSMutableArray array];for(id a in artists){NSString *name=TMAPIString(TMAPIDict(a)[@"name"]);if(name.length)[names addObject:name];}s[@"artist"]=[names componentsJoinedByString:@", "];}}
    NSNumber *duration=TMMilliseconds(item[@"duration_ms"],86400000);if(duration)s[@"duration_ms"]=duration;
    NSNumber *progress=TMMilliseconds(j[@"progress_ms"],duration?duration.doubleValue:86400000);if(progress)s[@"progress_ms"]=progress;
    if([j[@"is_playing"] isKindOfClass:NSNumber.class])s[@"playing"]=@([j[@"is_playing"] boolValue]);
    NSString *device=TMAPIString(TMAPIDict(j[@"device"])[@"name"]);if(device)s[@"device"]=device;else if(!j[@"device"]||j[@"device"]==NSNull.null)s[@"device"]=@"";
    NSURL *image=TMSpotifyImageURL(TMAPIArray(episode?item[@"images"]:album[@"images"]));if(image)s[@"image"]=image;return s;
}
NSString *TMSpotifyPickDevice(NSArray *devices){if(![devices isKindOfClass:NSArray.class])return nil;NSString *fallback;for(id entry in devices){NSDictionary *d=TMAPIDict(entry);NSString *identifier=TMAPIString(d[@"id"]);if(!identifier.length||![d[@"is_restricted"] isKindOfClass:NSNumber.class]||[d[@"is_restricted"] boolValue])continue;if(!fallback)fallback=identifier;if([TMAPIString(d[@"type"]) isEqual:@"Smartphone"])return identifier;}return fallback;}
@implementation TMSpotifyAPI {TMSpotifyAuth *_auth;TMSpotifyHTTP _http;NSTimeInterval(^_uptime)(void);NSTimeInterval _backoffUntil;NSUInteger _generation;id _observer;}
+ (instancetype)shared{static TMSpotifyAPI *s;static dispatch_once_t once;dispatch_once(&once,^{s=[[self alloc]initWithAuth:TMSpotifyAuth.shared http:TMSpotifyDefaultHTTP() clock:^{return NSProcessInfo.processInfo.systemUptime;}];});return s;}
- (instancetype)initWithAuth:(TMSpotifyAuth *)auth http:(TMSpotifyHTTP)http clock:(NSTimeInterval(^)(void))uptime{if((self=[super init])){_auth=auth;_http=[http copy];_uptime=[uptime copy];__weak TMSpotifyAPI *weak=self;_observer=[NSNotificationCenter.defaultCenter addObserverForName:TMSpotifyAuthChanged object:auth queue:nil usingBlock:^(NSNotification *n){(void)n;TMAPIOnMain(^{TMSpotifyAPI *strong=weak;if(strong){strong->_generation++;strong->_backoffUntil=0;}});}];}return self;}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:_observer];}
- (NSTimeInterval)backoffUntil{__block NSTimeInterval value;if(NSThread.isMainThread)value=_backoffUntil;else dispatch_sync(dispatch_get_main_queue(),^{value=self->_backoffUntil;});return value;}
- (void)send:(NSString *)method path:(NSString *)path query:(NSDictionary *)q json:(id)body retry:(BOOL)retried done:(void(^)(NSData *,TMSpotifyErrorKind,NSTimeInterval))done{
    TMAPIOnMain(^{NSTimeInterval remaining=self->_backoffUntil-self->_uptime();if(remaining>0){done(nil,TMSpotifyRateLimited,remaining);return;}NSUInteger generation=self->_generation;NSString *client=self->_auth.clientID;
    [self->_auth accessToken:^(NSString *token,NSString *error){TMAPIOnMain(^{if(generation!=self->_generation||![client isEqual:self->_auth.clientID]){done(nil,TMSpotifySignedOut,0);return;}if(!token){TMSpotifyErrorKind kind=[error isEqual:@"not_configured"]?TMSpotifyNotConfigured:[error isEqual:@"signed_out"]?TMSpotifySignedOut:[error isEqual:@"network"]?TMSpotifyNetwork:TMSpotifyBadResponse;done(nil,kind,0);return;}
        NSURLComponents *c=[NSURLComponents componentsWithString:@"https://api.spotify.com"];c.path=path;NSMutableArray *items=[NSMutableArray array];for(NSString *key in [[q allKeys] sortedArrayUsingSelector:@selector(compare:)])[items addObject:[NSURLQueryItem queryItemWithName:key value:[q[key] description]]];if(items.count)c.queryItems=items;
        if(![c.host isEqual:@"api.spotify.com"]||![c.scheme isEqual:@"https"]||![path hasPrefix:@"/v1/me/player"]){done(nil,TMSpotifyBadResponse,0);return;}
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:c.URL];request.HTTPMethod=method;[request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        if(body){if(![NSJSONSerialization isValidJSONObject:body]){done(nil,TMSpotifyBadResponse,0);return;}request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];}
        else if([method isEqual:@"PUT"]||[method isEqual:@"POST"]){request.HTTPBody=NSData.data;[request setValue:@"0" forHTTPHeaderField:@"Content-Length"];}
        self->_http(request,^(NSData *data,NSHTTPURLResponse *response,NSError *failure){TMAPIOnMain(^{if(generation!=self->_generation||![client isEqual:self->_auth.clientID]){done(nil,TMSpotifySignedOut,0);return;}NSTimeInterval retry=0;TMSpotifyErrorKind kind=TMSpotifyClassify(data,response,failure,&retry);if(kind==TMSpotifySignedOut&&!retried){[self->_auth invalidateAccessToken];[self send:method path:path query:q json:body retry:YES done:done];return;}if(kind==TMSpotifyRateLimited)self->_backoffUntil=self->_uptime()+retry;if(data.length>4*1024*1024){done(nil,TMSpotifyBadResponse,0);return;}done(response.statusCode==204?nil:data,kind,retry);});});
    });}];});
}
- (void)player:(void(^)(NSDictionary *,TMSpotifyErrorKind,NSTimeInterval))done{[self send:@"GET" path:@"/v1/me/player" query:@{@"additional_types":@"track,episode"} json:nil retry:NO done:^(NSData *data,TMSpotifyErrorKind kind,NSTimeInterval retry){if(kind!=TMSpotifyOK||!data.length){done(nil,kind,retry);return;}NSDictionary *j=TMAPIDict(TMJSON(data));if(!j){done(nil,TMSpotifyBadResponse,0);return;}done(TMSpotifyStateFromPlayer(j),kind,retry);}];}
- (void)devices:(void(^)(NSArray<NSDictionary *> *,TMSpotifyErrorKind))done{[self send:@"GET" path:@"/v1/me/player/devices" query:nil json:nil retry:NO done:^(NSData *data,TMSpotifyErrorKind kind,NSTimeInterval retry){(void)retry;NSArray *a=TMAPIArray(TMAPIDict(TMJSON(data))[@"devices"]);if(kind==TMSpotifyOK&&!a){done(nil,TMSpotifyBadResponse);return;}NSMutableArray *devices=[NSMutableArray array];for(id d in a)if(TMAPIDict(d))[devices addObject:d];done(kind==TMSpotifyOK?devices:nil,kind);}];}
- (void)command:(NSString *)method path:(NSString *)path query:(NSDictionary *)q json:(id)body done:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self send:method path:path query:q json:body retry:NO done:^(NSData *data,TMSpotifyErrorKind kind,NSTimeInterval retry){(void)data;done(kind,retry);}];}
- (void)play:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self command:@"PUT" path:@"/v1/me/player/play" query:nil json:nil done:done];}
- (void)pause:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self command:@"PUT" path:@"/v1/me/player/pause" query:nil json:nil done:done];}
- (void)next:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self command:@"POST" path:@"/v1/me/player/next" query:nil json:nil done:done];}
- (void)previous:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self command:@"POST" path:@"/v1/me/player/previous" query:nil json:nil done:done];}
- (void)seek:(uint32_t)ms done:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{[self command:@"PUT" path:@"/v1/me/player/seek" query:@{@"position_ms":[@(ms) stringValue]} json:nil done:done];}
- (void)transfer:(NSString *)deviceID play:(BOOL)play done:(void(^)(TMSpotifyErrorKind,NSTimeInterval))done{if(![deviceID isKindOfClass:NSString.class]||!deviceID.length||deviceID.length>512){TMAPIOnMain(^{done(TMSpotifyBadResponse,0);});return;}[self command:@"PUT" path:@"/v1/me/player" query:nil json:@{@"device_ids":@[deviceID],@"play":@(play)} done:done];}
@end
