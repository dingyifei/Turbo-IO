#import "SpotifyHTTP.h"
#include <stdint.h>
static const NSUInteger TMSpotifyHTTPMaxBody=4*1024*1024;
static NSError *TMSpotifyHTTPError(NSInteger code){return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil];}
@interface TMSpotifyHTTPTransaction:NSObject
- (instancetype)initWithDone:(TMSpotifyHTTPDone)done cancel:(dispatch_block_t)cancel;
- (BOOL)acceptResponse:(NSURLResponse *)response;
- (void)appendData:(NSData *)data;
- (void)finishWithError:(NSError *)error;
- (void)refuseRedirect;
- (NSUInteger)bufferedLength;
@end
@implementation TMSpotifyHTTPTransaction{
 NSMutableData *_body;NSHTTPURLResponse *_response;TMSpotifyHTTPDone _done;dispatch_block_t _cancel;BOOL _finished;NSUInteger _bufferedLengthAtFinish;
}
- (instancetype)initWithDone:(TMSpotifyHTTPDone)done cancel:(dispatch_block_t)cancel{if((self=[super init])){_body=[NSMutableData data];_done=[done copy];_cancel=[cancel copy];}return self;}
- (void)finishOnceWithError:(NSError *)error{if(_finished)return;_finished=YES;NSError *e=error;if(!e&&!_response)e=TMSpotifyHTTPError(NSURLErrorBadServerResponse);NSData *data=e?nil:_body;_bufferedLengthAtFinish=_body.length;NSHTTPURLResponse *response=_response;TMSpotifyHTTPDone done=_done;_done=nil;_cancel=nil;_body=nil;dispatch_async(dispatch_get_main_queue(),^{if(done)done(data,response,e);});}
- (void)abortWithError:(NSError *)error{if(_finished)return;dispatch_block_t cancel=_cancel;[self finishOnceWithError:error];if(cancel)cancel();}
- (BOOL)acceptResponse:(NSURLResponse *)response{if(_finished)return NO;if(![response isKindOfClass:NSHTTPURLResponse.class]){[self abortWithError:TMSpotifyHTTPError(NSURLErrorBadServerResponse)];return NO;}if(response.expectedContentLength>=0&&(uint64_t)response.expectedContentLength>TMSpotifyHTTPMaxBody){[self abortWithError:TMSpotifyHTTPError(NSURLErrorDataLengthExceedsMaximum)];return NO;}_response=(id)response;return YES;}
- (void)appendData:(NSData *)data{if(_finished||!data.length)return;if(data.length>TMSpotifyHTTPMaxBody-_body.length){[self abortWithError:TMSpotifyHTTPError(NSURLErrorDataLengthExceedsMaximum)];return;}[_body appendData:data];}
- (void)finishWithError:(NSError *)error{[self finishOnceWithError:error];}
- (NSUInteger)bufferedLength{return _body?_body.length:_bufferedLengthAtFinish;}
- (void)refuseRedirect{[self abortWithError:TMSpotifyHTTPError(NSURLErrorHTTPTooManyRedirects)];}
@end
@interface TMSpotifyHTTPDelegate:NSObject<NSURLSessionDataDelegate>
- (void)registerTransaction:(TMSpotifyHTTPTransaction *)transaction forTask:(NSURLSessionTask *)task;
@end
@implementation TMSpotifyHTTPDelegate{NSMutableDictionary<NSNumber *,TMSpotifyHTTPTransaction *> *_transactions;dispatch_queue_t _stateQueue;}
- (instancetype)init{if((self=[super init])){_transactions=[NSMutableDictionary new];_stateQueue=dispatch_queue_create("io.turboio.spotify.http.state",DISPATCH_QUEUE_SERIAL);}return self;}
- (NSNumber *)key:(NSURLSessionTask *)task{return @(task.taskIdentifier);}
- (void)registerTransaction:(TMSpotifyHTTPTransaction *)transaction forTask:(NSURLSessionTask *)task{dispatch_sync(_stateQueue,^{self->_transactions[[self key:task]]=transaction;});}
- (TMSpotifyHTTPTransaction *)transactionForTask:(NSURLSessionTask *)task{__block TMSpotifyHTTPTransaction *tx;dispatch_sync(_stateQueue,^{tx=self->_transactions[[self key:task]];});return tx;}
- (void)removeTransactionForTask:(NSURLSessionTask *)task{dispatch_sync(_stateQueue,^{[self->_transactions removeObjectForKey:[self key:task]];});}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler{[[self transactionForTask:task] refuseRedirect];completionHandler(nil);}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler{TMSpotifyHTTPTransaction *tx=[self transactionForTask:task];completionHandler(tx&&[tx acceptResponse:response]?NSURLSessionResponseAllow:NSURLSessionResponseCancel);}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data{[[self transactionForTask:task] appendData:data];}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error{TMSpotifyHTTPTransaction *tx=[self transactionForTask:task];[tx finishWithError:error];[self removeTransactionForTask:task];}
@end
TMSpotifyHTTP TMSpotifyDefaultHTTP(void){static NSURLSession *session;static TMSpotifyHTTPDelegate *delegate;static dispatch_once_t once;dispatch_once(&once,^{NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPShouldSetCookies=NO;c.HTTPCookieStorage=nil;c.URLCache=nil;c.timeoutIntervalForRequest=15;c.timeoutIntervalForResource=30;delegate=[TMSpotifyHTTPDelegate new];session=[NSURLSession sessionWithConfiguration:c delegate:delegate delegateQueue:NSOperationQueue.mainQueue];});return ^(NSURLRequest *request,TMSpotifyHTTPDone done){NSURLSessionDataTask *task=[session dataTaskWithRequest:request];TMSpotifyHTTPTransaction *tx=[[TMSpotifyHTTPTransaction alloc]initWithDone:done cancel:^{[task cancel];}];[delegate registerTransaction:tx forTask:task];[task resume];};}
