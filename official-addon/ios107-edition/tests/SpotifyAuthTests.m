#import "SpotifyAuth.h"
#import <assert.h>
static NSString *const FakeClient=@"00000000000000000000000000000001";
static NSString *const OtherFakeClient=@"00000000000000000000000000000002";
@interface CountingStore:TMSpotifyTokenStore
@property(nonatomic,strong) TMSpotifyTokenStore *inner;
@property(nonatomic) NSUInteger loads;
@end
@implementation CountingStore
- (NSDictionary *)load{self.loads++;return [self.inner load];}
- (BOOL)save:(NSDictionary *)d{return [self.inner save:d];}
- (void)remove{[self.inner remove];}
@end
static void Spin(BOOL(^condition)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];while(!condition()&&end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];assert(condition());}
static NSData *Fixture(NSString *root,NSString *name){NSData *d=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:name]];assert(d);return d;}
static NSHTTPURLResponse *Response(NSInteger status){return [[NSHTTPURLResponse alloc]initWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];}
static NSURL *Callback(NSURL *authorize){NSURLComponents *c=[NSURLComponents componentsWithURL:authorize resolvingAgainstBaseURL:NO];NSString *state;for(NSURLQueryItem *q in c.queryItems)if([q.name isEqual:@"state"])state=q.value;assert(state);return [NSURL URLWithString:[NSString stringWithFormat:@"io.turboio.spotify://callback?code=FAKE_CODE&state=%@",state]];}
static void TestOversizedEncodedForms(void){
 // Synthetic opaque UTF-8 data fits the JSON store limit but expands past the encoded form limit.
 const unsigned char unit[]={0xf0,0x9f,0x98,0x80};NSMutableData *bytes=[NSMutableData dataWithCapacity:131072];for(NSUInteger i=0;i<32768;i++)[bytes appendBytes:unit length:sizeof(unit)];NSString *opaque=[[NSString alloc]initWithData:bytes encoding:NSUTF8StringEncoding];assert(opaque.length==65536);
 NSDictionary *seed=@{@"refresh_token":opaque,@"client_id":FakeClient};NSData *json=[NSJSONSerialization dataWithJSONObject:seed options:0 error:NULL];assert(json.length<262144);
 assert((!TMSpotifyTokenRequest(@{@"grant_type":@"refresh_token",@"refresh_token":opaque,@"client_id":FakeClient})));
 assert((!TMSpotifyTokenRequest(@{@"grant_type":@"authorization_code",@"code":opaque,@"client_id":FakeClient})));
 NSString *suite=@"TurboSpotifyOversizedFormTests";NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:suite];[defaults removePersistentDomainForName:suite];[defaults setObject:FakeClient forKey:@"TurboSpotifyClientIDV1"];TMSpotifyTokenStore *store=TMSpotifyTokenStore.memory;assert([store save:seed]);
 __block NSUInteger httpCalls=0;TMSpotifyAuth *auth=[[TMSpotifyAuth alloc]initWithHTTP:^(NSURLRequest *request,TMSpotifyHTTPDone done){httpCalls++;assert(request!=nil);done(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil]);} store:store defaults:defaults clock:^{return NSDate.date;}];
 __block NSUInteger replies=0,changes=0;id observer=[NSNotificationCenter.defaultCenter addObserverForName:TMSpotifyAuthChanged object:auth queue:nil usingBlock:^(NSNotification *n){(void)n;changes++;}];
 for(NSUInteger i=0;i<2;i++)[auth accessToken:^(NSString *token,NSString *error){assert(!token&&[error isEqual:@"bad_response"]&&NSThread.isMainThread);replies++;}];Spin(^BOOL{return replies==2;});assert(httpCalls==0&&changes==0&&auth.signedIn&&[[store load] isEqual:seed]);
 // A later request must complete too: a failed construction cannot leave a refresh flight stuck.
 [auth accessToken:^(NSString *token,NSString *error){assert(!token&&[error isEqual:@"bad_response"]);replies++;}];Spin(^BOOL{return replies==3;});assert(httpCalls==0&&auth.signedIn&&[[store load] isEqual:seed]);
 // Oversized callback data is rejected before exchange; credentials stay untouched.
 NSURL *start=[auth beginSignIn];NSURLComponents *authorize=[NSURLComponents componentsWithURL:start resolvingAgainstBaseURL:NO];NSString *state;for(NSURLQueryItem *q in authorize.queryItems)if([q.name isEqual:@"state"])state=q.value;NSURLComponents *callback=[NSURLComponents componentsWithString:TMSpotifyDefaultRedirect];callback.queryItems=@[[NSURLQueryItem queryItemWithName:@"code" value:opaque],[NSURLQueryItem queryItemWithName:@"state" value:state]];__block BOOL completed=NO;[auth finishSignInWithCallback:callback.URL done:^(NSString *error){assert(error.length&&NSThread.isMainThread);completed=YES;}];Spin(^{return completed;});assert(httpCalls==0&&changes==0&&auth.signedIn&&[[store load] isEqual:seed]);
 [NSNotificationCenter.defaultCenter removeObserver:observer];[defaults removePersistentDomainForName:suite];
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);TestOversizedEncodedForms();NSString *root=@(argv[1]);
 assert([TMSpotifyChallenge(@"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") isEqual:@"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"]);
 NSString *v=TMSpotifyNewVerifier();assert(v.length==86);assert([v rangeOfString:@"^[A-Za-z0-9_-]+$" options:NSRegularExpressionSearch].location!=NSNotFound);
 assert(!TMSpotifyValidClientID([FakeClient stringByAppendingString:@"\n"]));assert(!TMSpotifyChallenge(@"short"));assert(!TMSpotifyValidClientID(@"missing"));
 assert([TMSpotifyRedirectScheme(TMSpotifyDefaultRedirect) isEqual:@"io.turboio.spotify"]);assert(TMSpotifyLoopbackPort(TMSpotifyLoopbackRedirect)==43821);
 for(NSString *r in @[@"https://x.com/cb",@"http://localhost:43821/callback",@"javascript:alert(1)",@"http://127.0.0.1:1/callback",@"http://127.0.0.1:65536/callback",@"http://127.0.0.1:43821/callback?q=x",@"io.turboio.spotify://u:p@callback",@"io.turboio.spotify://callback#x",@"http://127.1:43821/callback"] )assert(!TMSpotifyRedirectScheme(r));
 NSURL *authURL=TMSpotifyAuthorizeURL(FakeClient,TMSpotifyDefaultRedirect,TMSpotifyChallenge(v),@"state+value");NSURLComponents *ac=[NSURLComponents componentsWithURL:authURL resolvingAgainstBaseURL:NO];assert(ac.queryItems.count==7);assert([ac.percentEncodedQuery containsString:@"state%2Bvalue"]);
 assert([TMSpotifyCallbackResult([NSURL URLWithString:@"io.turboio.spotify://callback?code=fake&state=s"],TMSpotifyDefaultRedirect,@"s")[@"code"] isEqual:@"fake"]);
 NSArray *bad=@[@[@"io.turboio.spotify://callback?code=fake&state=t",@"state"],@[@"io.turboio.spotify://callback?error=access_denied&state=s",@"access_denied"],@[@"io.turboio.spotify://evil?code=fake&state=s",@"mismatch"],@[@"io.turboio.spotify://callback?code=fake&state=s&state=s",@"missing"],@[@"io.turboio.spotify://callback?code=a&code=b&state=s",@"missing"],@[@"io.turboio.spotify://callback?code=a&error=access_denied&state=s",@"missing"]];for(NSArray *pair in bad)assert([TMSpotifyCallbackResult([NSURL URLWithString:pair[0]],TMSpotifyDefaultRedirect,@"s")[@"error"] isEqual:pair[1]]);
 NSString *head=@"GET /callback?code=fake&state=s HTTP/1.1\r\nHost: 127.0.0.1:43821\r\n\r\n";assert(TMSpotifyLoopbackRequestURL([head dataUsingEncoding:NSASCIIStringEncoding],43821));
 for(NSString *h in @[@"POST /callback HTTP/1.1\r\n\r\n",@"GET /callback%0d%0aX:x HTTP/1.1\r\n\r\n",@"GET //evil/callback HTTP/1.1\r\n\r\n",@"GET /callback HTTP/1.1\r\nHost: evil\r\n\r\n",@"GET /callback HTTP/1.1\r\n\r\nJUNK"])assert(!TMSpotifyLoopbackRequestURL([h dataUsingEncoding:NSASCIIStringEncoding],43821));
 assert(!TMSpotifyLoopbackRequestURL([NSMutableData dataWithLength:8193],43821));
 NSURLRequest *form=TMSpotifyTokenRequest(@{@"b":@"a+b /",@"a":@"z"});assert([[[NSString alloc]initWithData:form.HTTPBody encoding:NSUTF8StringEncoding] isEqual:@"a=z&b=a%2Bb%20%2F"]);assert([form.URL.host isEqual:@"accounts.spotify.com"]);
 assert(TMSpotifyParseToken([NSMutableData dataWithLength:262145],200,NSDate.date)[@"error"]);
 assert(TMSpotifyParseToken([@"{\"access_token\":[],\"expires_in\":3600}" dataUsingEncoding:NSUTF8StringEncoding],200,NSDate.date)[@"error"]);
 NSString *suite=@"TurboSpotifyTests";NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:suite];[defaults removePersistentDomainForName:suite];
 CountingStore *store=[CountingStore new];store.inner=TMSpotifyTokenStore.memory;
 __block NSDate *now=[NSDate dateWithTimeIntervalSince1970:1000];__block NSUInteger requests=0;__block TMSpotifyHTTPDone held;__block NSURLRequest *last;
 TMSpotifyAuth *auth=[[TMSpotifyAuth alloc]initWithHTTP:^(NSURLRequest *r,TMSpotifyHTTPDone d){requests++;last=r;held=[d copy];} store:store defaults:defaults clock:^{return now;}];
 assert(!auth.signedIn);NSUInteger loads=store.loads;for(int i=0;i<100;i++)assert(!auth.signedIn);assert(store.loads==loads);assert([auth setClientIDString:[@" \n" stringByAppendingString:FakeClient]]);
 __block BOOL completed=NO;__block NSString *error;NSURL *start=[auth beginSignIn];[auth finishSignInWithCallback:Callback(start) done:^(NSString *e){error=e;completed=YES;}];assert(requests==1);assert([last.HTTPMethod isEqual:@"POST"]);held(Fixture(root,@"token_exchange.json"),Response(200),nil);Spin(^{return completed;});assert(!error&&auth.signedIn);assert([[store load][@"refresh_token"] isEqual:@"RT1"]);
 NSUInteger before=requests;__block NSString *access;[auth accessToken:^(NSString *t,NSString *e){access=t;assert(!e);}];assert([access isEqual:@"AT1"]&&requests==before);
 now=[now dateByAddingTimeInterval:4000];__block int calls=0;[auth accessToken:^(NSString *t,NSString *e){assert(t&&!e);calls++;}];[auth accessToken:^(NSString *t,NSString *e){assert(t&&!e);calls++;}];assert(requests==before+1);held(Fixture(root,@"token_refresh_rotated.json"),Response(200),nil);Spin(^BOOL{return calls==2;});assert([[store load][@"refresh_token"] isEqual:@"RT2"]);
 [auth invalidateAccessToken];completed=NO;[auth accessToken:^(NSString *t,NSString *e){assert(t&&!e);completed=YES;}];held(Fixture(root,@"token_refresh_same.json"),Response(200),nil);Spin(^{return completed;});assert([[store load][@"refresh_token"] isEqual:@"RT2"]);
 [auth invalidateAccessToken];completed=NO;[auth accessToken:^(NSString *t,NSString *e){assert(!t&&[e isEqual:@"network"]);completed=YES;}];held(nil,Response(503),nil);Spin(^{return completed;});assert(auth.signedIn);
 __block int changes=0;id observer=[NSNotificationCenter.defaultCenter addObserverForName:TMSpotifyAuthChanged object:auth queue:nil usingBlock:^(NSNotification *n){(void)n;changes++;}];completed=NO;[auth accessToken:^(NSString *t,NSString *e){assert(!t&&[e isEqual:@"signed_out"]);completed=YES;}];held(Fixture(root,@"token_invalid_grant.json"),Response(400),nil);Spin(^{return completed;});assert(!auth.signedIn&&changes==1);[NSNotificationCenter.defaultCenter removeObserver:observer];
 // A late exchange cannot repopulate a signed-out or reconfigured session.
 for(int mode=0;mode<3;mode++){assert([auth setClientIDString:FakeClient]);start=[auth beginSignIn];completed=NO;[auth finishSignInWithCallback:Callback(start) done:^(NSString *e){assert([e isEqual:@"cancelled"]);completed=YES;}];TMSpotifyHTTPDone late=held;if(mode==0)[auth signOut];else if(mode==1)[auth setClientIDString:OtherFakeClient];else [auth beginSignIn];late(Fixture(root,@"token_exchange.json"),Response(200),nil);Spin(^{return completed;});assert(!auth.signedIn);}
 [auth cancelPendingSignIn];[auth setClientIDString:FakeClient];start=[auth beginSignIn];completed=NO;[auth finishSignInWithCallback:Callback(start) done:^(NSString *e){assert(!e);completed=YES;}];held(Fixture(root,@"token_exchange.json"),Response(200),nil);Spin(^{return completed;});assert(auth.signedIn);[auth invalidateAccessToken];completed=NO;[auth accessToken:^(NSString *t,NSString *e){assert(!t&&[e isEqual:@"signed_out"]);completed=YES;}];TMSpotifyHTTPDone late=held;[auth signOut];late(Fixture(root,@"token_refresh_rotated.json"),Response(200),nil);Spin(^{return completed;});assert(!auth.signedIn&&![store load]);
 // Even a refresh that completed before sign-out cannot deliver a queued credential afterwards.
 [auth setClientIDString:FakeClient];start=[auth beginSignIn];completed=NO;[auth finishSignInWithCallback:Callback(start) done:^(NSString *e){assert(!e);completed=YES;}];held(Fixture(root,@"token_exchange.json"),Response(200),nil);Spin(^{return completed;});[auth invalidateAccessToken];completed=NO;[auth accessToken:^(NSString *t,NSString *e){assert(!t&&[e isEqual:@"signed_out"]);completed=YES;}];held(Fixture(root,@"token_refresh_same.json"),Response(200),nil);[auth signOut];Spin(^{return completed;});assert(!auth.signedIn);
 [auth setClientIDString:OtherFakeClient];assert(!auth.signedIn);[defaults removePersistentDomainForName:suite];puts("PASS spotify-auth: PKCE, callback bounds, rotation, cache, single-flight, stale completions, encoded-form bounds");
}return 0;}
