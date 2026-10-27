#import "SpotifySignIn.h"
#import "SpotifyAuth.h"
#import "TIOLanguage.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <Network/Network.h>

@class TMSpotifyBrowserAttempt;
@interface TMSpotifyLoopbackPeer:NSObject
@property(nonatomic,strong) nw_connection_t connection;
@property(nonatomic,weak) TMSpotifyBrowserAttempt *owner;
@property(nonatomic,strong) NSMutableData *head;
@property(nonatomic,strong) dispatch_source_t timer;
@property(nonatomic,copy) void(^afterReply)(void);
@property(nonatomic) BOOL closed,responding;
- (void)start;
- (void)read;
- (void)close;
- (void)finishReply;
- (void)reply:(NSInteger)status text:(NSString *)text after:(void(^)(void))after;
@end
@interface TMSpotifyBrowserAttempt:NSObject<ASWebAuthenticationPresentationContextProviding>
@property(nonatomic,strong) TMSpotifyAuth *auth;
@property(nonatomic,strong) NSURL *authorizeURL;
@property(nonatomic,copy) NSString *redirect,*state;
@property(nonatomic,weak) UIViewController *from;
@property(nonatomic,strong) ASWebAuthenticationSession *session;
@property(nonatomic,strong) nw_listener_t listener;
@property(nonatomic,strong) dispatch_source_t timeout;
@property(nonatomic,strong) NSMutableSet<TMSpotifyLoopbackPeer *> *peers;
@property(nonatomic,strong) id observer;
@property(nonatomic,copy) void(^done)(NSString *);
@property(nonatomic) uint16_t port;
@property(nonatomic) NSUInteger connections;
@property(nonatomic) BOOL finished,claimed,started,delivered;
- (void)start;
- (void)startBrowser;
- (void)acceptURL:(NSURL *)url peer:(TMSpotifyLoopbackPeer *)peer;
- (void)finishURL:(NSURL *)url error:(NSString *)error;
- (void)complete:(NSString *)error;
@end
static TMSpotifyBrowserAttempt *TMSpotifyActiveAttempt;
static NSString *TMSpotifyHTML(NSString *text){NSString *s=text?:@"";for(NSArray *pair in @[@[@"&",@"&amp;"],@[@"<",@"&lt;"],@[@">",@"&gt;"],@[@"\"",@"&quot;"],@[@"'",@"&#39;"]])s=[s stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];return [NSString stringWithFormat:@"<!doctype html><meta charset=\"utf-8\"><p>%@</p>",s];}
@implementation TMSpotifyLoopbackPeer
- (void)start{self.head=[NSMutableData data];__weak TMSpotifyLoopbackPeer *weak=self;self.timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(self.timer,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),DISPATCH_TIME_FOREVER,NSEC_PER_SEC/10);dispatch_source_set_event_handler(self.timer,^{[weak finishReply];});dispatch_resume(self.timer);nw_connection_set_queue(self.connection,dispatch_get_main_queue());nw_connection_set_state_changed_handler(self.connection,^(nw_connection_state_t state,nw_error_t error){(void)error;if(state==nw_connection_state_ready)[weak read];else if(state==nw_connection_state_failed||state==nw_connection_state_cancelled)[weak finishReply];});nw_connection_start(self.connection);}
- (void)read{if(self.closed||self.responding)return;NSUInteger remaining=8192-self.head.length;if(!remaining){[self close];return;}__weak TMSpotifyLoopbackPeer *weak=self;nw_connection_receive(self.connection,1,(uint32_t)remaining,^(dispatch_data_t content,nw_content_context_t context,bool complete,nw_error_t error){(void)context;TMSpotifyLoopbackPeer *peer=weak;if(!peer||peer.closed||peer.responding)return;if(content){size_t length=dispatch_data_get_size(content);if(length>8192-peer.head.length){[peer close];return;}dispatch_data_apply(content,^bool(dispatch_data_t region,size_t offset,const void *buffer,size_t size){(void)region;(void)offset;[peer.head appendBytes:buffer length:size];return true;});}
        const char delimiter[]="\r\n\r\n";NSRange end=[peer.head rangeOfData:[NSData dataWithBytes:delimiter length:4] options:0 range:NSMakeRange(0,peer.head.length)];
        if(end.location!=NSNotFound){NSURL *url=TMSpotifyLoopbackRequestURL(peer.head,peer.owner.port);if(url)[peer.owner acceptURL:url peer:peer];else [peer reply:404 text:TIOText(@"music.loopbackRejected") after:nil];return;}
        if(error||complete||peer.head.length>=8192){[peer close];return;}[peer read];});}
- (void)reply:(NSInteger)status text:(NSString *)text after:(void(^)(void))after{if(self.closed||self.responding)return;self.responding=YES;self.afterReply=after;NSData *body=[TMSpotifyHTML(text) dataUsingEncoding:NSUTF8StringEncoding];NSString *headers=[NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\n\r\n",(long)status,status==200?@"OK":@"Not Found",(unsigned long)body.length];NSMutableData *response=[[headers dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];[response appendData:body];dispatch_source_set_timer(self.timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),DISPATCH_TIME_FOREVER,NSEC_PER_SEC/10);dispatch_data_t bytes=dispatch_data_create(response.bytes,response.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);__weak TMSpotifyLoopbackPeer *weak=self;nw_connection_send(self.connection,bytes,NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(nw_error_t error){(void)error;[weak finishReply];});}
- (void)finishReply{if(self.closed)return;void(^after)(void)=self.afterReply;self.afterReply=nil;[self close];if(after)after();}
- (void)close{if(self.closed)return;self.closed=YES;self.afterReply=nil;if(self.timer){dispatch_source_cancel(self.timer);self.timer=nil;}nw_connection_cancel(self.connection);[self.owner.peers removeObject:self];self.connection=nil;}
@end
@implementation TMSpotifyBrowserAttempt
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session{(void)session;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){if(scene.activationState!=UISceneActivationStateForegroundActive||![scene isKindOfClass:UIWindowScene.class])continue;for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow)return window;}return self.from.view.window;}
- (void)start{self.peers=[NSMutableSet set];__weak TMSpotifyBrowserAttempt *weak=self;self.observer=[NSNotificationCenter.defaultCenter addObserverForName:TMSpotifyAuthChanged object:self.auth queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[weak finishURL:nil error:@"cancelled"];}];self.timeout=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(self.timeout,dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_SEC),DISPATCH_TIME_FOREVER,NSEC_PER_SEC);dispatch_source_set_event_handler(self.timeout,^{[weak finishURL:nil error:@"timeout"];});dispatch_resume(self.timeout);
    if(!self.port){[self startBrowser];return;}
    nw_parameters_t parameters=nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION);NSString *port=[NSString stringWithFormat:@"%u",self.port];nw_parameters_set_local_endpoint(parameters,nw_endpoint_create_host("127.0.0.1",port.UTF8String));self.listener=nw_listener_create(parameters);if(!self.listener){[self finishURL:nil error:@"loopback_port_busy"];return;}nw_listener_set_queue(self.listener,dispatch_get_main_queue());
    nw_listener_set_new_connection_handler(self.listener,^(nw_connection_t connection){TMSpotifyBrowserAttempt *attempt=weak;if(!attempt||attempt.finished||attempt.claimed||attempt.connections>=4){nw_connection_cancel(connection);return;}attempt.connections++;TMSpotifyLoopbackPeer *peer=[TMSpotifyLoopbackPeer new];peer.connection=connection;peer.owner=attempt;[attempt.peers addObject:peer];[peer start];});
    nw_listener_set_state_changed_handler(self.listener,^(nw_listener_state_t state,nw_error_t error){(void)error;TMSpotifyBrowserAttempt *attempt=weak;if(!attempt||attempt.finished)return;if(state==nw_listener_state_ready)[attempt startBrowser];else if(state==nw_listener_state_failed)[attempt finishURL:nil error:@"loopback_port_busy"];});nw_listener_start(self.listener);
}
- (void)startBrowser{if(self.finished||self.started)return;self.started=YES;__weak TMSpotifyBrowserAttempt *weak=self;NSString *scheme=TMSpotifyRedirectScheme(self.redirect);self.session=[[ASWebAuthenticationSession alloc]initWithURL:self.authorizeURL callbackURLScheme:self.port?nil:scheme completionHandler:^(NSURL *callback,NSError *error){dispatch_async(dispatch_get_main_queue(),^{TMSpotifyBrowserAttempt *attempt=weak;if(!attempt||attempt.finished||attempt.claimed)return;if(callback)[attempt finishURL:callback error:nil];else [attempt finishURL:nil error:([error.domain isEqual:ASWebAuthenticationSessionErrorDomain]&&error.code==ASWebAuthenticationSessionErrorCodeCanceledLogin)?@"cancelled":@"signin_failed"];});}];self.session.prefersEphemeralWebBrowserSession=NO;self.session.presentationContextProvider=self;if(![self.session start])[self finishURL:nil error:@"start_failed"];}
- (void)acceptURL:(NSURL *)url peer:(TMSpotifyLoopbackPeer *)peer{if(self.finished||self.claimed){[peer close];return;}NSDictionary *result=TMSpotifyCallbackResult(url,self.redirect,self.state);if(!result[@"code"]&&![result[@"error"] isEqual:@"access_denied"]){[peer reply:404 text:TIOText(@"music.loopbackRejected") after:nil];return;}self.claimed=YES;[self.session cancel];for(TMSpotifyLoopbackPeer *other in self.peers.copy)if(other!=peer)[other close];[peer reply:200 text:TIOText(@"music.loopbackComplete") after:^{[self finishURL:url error:nil];}];}
- (void)finishURL:(NSURL *)url error:(NSString *)error{if(self.finished)return;self.finished=YES;if(self.timeout){dispatch_source_cancel(self.timeout);self.timeout=nil;}if(self.observer){[NSNotificationCenter.defaultCenter removeObserver:self.observer];self.observer=nil;}if(self.listener){nw_listener_cancel(self.listener);self.listener=nil;}for(TMSpotifyLoopbackPeer *peer in self.peers.copy)[peer close];[self.peers removeAllObjects];[self.session cancel];self.session=nil;
    if(url){[self.auth finishSignInWithCallback:url done:^(NSString *e){[self complete:e];}];}else{[self.auth cancelPendingSignIn];[self complete:error?:@"cancelled"];}
}
- (void)complete:(NSString *)error{if(self.delivered)return;self.delivered=YES;void(^done)(NSString *)=self.done;self.done=nil;if(TMSpotifyActiveAttempt==self)TMSpotifyActiveAttempt=nil;if(done)done(error);}
@end
void TMSpotifySignIn(UIViewController *from,void(^done)(NSString *error)){if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TMSpotifySignIn(from,done);});return;}if(TMSpotifyActiveAttempt){done(@"busy");return;}TMSpotifyAuth *auth=TMSpotifyAuth.shared;NSURL *url=[auth beginSignIn];if(!url){[auth cancelPendingSignIn];done(@"not_configured");return;}TMSpotifyBrowserAttempt *attempt=[TMSpotifyBrowserAttempt new];attempt.auth=auth;attempt.authorizeURL=url;attempt.redirect=auth.redirect;attempt.port=TMSpotifyLoopbackPort(attempt.redirect);attempt.from=from;attempt.done=done;for(NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)if([item.name isEqual:@"state"])attempt.state=item.value;TMSpotifyActiveAttempt=attempt;[attempt start];}
