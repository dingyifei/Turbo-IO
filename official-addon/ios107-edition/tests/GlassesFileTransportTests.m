#import <Foundation/Foundation.h>
#import "TIOGlassesFileTransport.h"
#import "tests/fixtures/wp8/LegacyFocusTransport.h"
#import "tests/fixtures/wp8/LegacyMusicTransport.h"
#import "tests/fixtures/wp8/LegacyTDTransport.h"
#import "focus.h"
#import "music.h"
#import "command.h"
#include <assert.h>
static void Pump(void){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:.05];while(end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];}
typedef BOOL(*Scoped)(NSString *,NSDictionary *);
static BOOL OldUnion(NSString *m,NSDictionary *a){return TIOLegacyTMIsScopedCall(m,a)||TIOLegacyTFIsScopedCall(m,a)||TIOLegacyTDIsScopedCall(m,a);}
static void ScopeCases(Scoped check,NSString *method,NSDictionary *args){
 assert(check(method,args));
 NSArray *methods=@[@"rayneonet_startOTA",@"rayneonet_sendData",@"rayneonet_sendfile",@"sendFile",@"",NSNull.null,@15];
 for(id m in methods)assert(!check(m,args));
 assert(!check(nil,args));assert(!check(method,nil));
 NSMutableDictionary *missing=[args mutableCopy];[missing removeObjectForKey:@"deviceId"];
 NSMutableDictionary *extra=[args mutableCopy];extra[@"extra"]=@1;
 NSMutableDictionary *malformed=[args mutableCopy];malformed[@"filePath"]=@12;
 for(id a in @[[args mutableCopy],@{},missing,extra,malformed,@[],NSNull.null,@"invalid"])assert(!check(method,a));
 __block BOOL background=YES;dispatch_semaphore_t signal=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{background=check(method,args);dispatch_semaphore_signal(signal);});assert(dispatch_semaphore_wait(signal,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);assert(!background);
}
static NSData *Packet(unsigned kind){
 uint8_t bytes[256]={0};size_t n=0;
 if(kind==0){TFCommand p={.op=TF_QUERY,.sid=1,.seq=1};n=tf_encode(bytes,sizeof bytes,&p);}
 else if(kind==1)n=tm_encode(bytes,sizeof bytes,TM_QUERY,0,1,1,1,0,NULL,0);
 else{assert(td_command_encode((TDCommand){.op=TDQ_START,.session=1,.sequence=1,.lease_ms=1000},bytes,24));n=24;}
 assert(n>=24);return [NSData dataWithBytes:bytes length:n];
}
static void Equivalence(NSURL *root){
 NSArray *classes=@[TIOLegacyTFTransport.class,TIOLegacyTMTransport.class,TIOLegacyTDTransport.class];
 NSArray *names=@[@"turbo-focus.tfp",@"turbo-music.tmu",@"turbo-diagnostics.tdg"];
 for(unsigned i=0;i<3;i++){
  NSData *packet=Packet(i);TIOGlassesFileValidator validator=^BOOL(NSData *d){if(i==0){TFCommand p;return tf_decode(d.bytes,d.length,&p);}if(i==1){TMPacket p;return tm_decode(d.bytes,d.length,&p);}TDCommand p;return td_command_decode(d.bytes,d.length,&p);};
  for(unsigned modern=0;modern<2;modern++){
   __block unsigned calls=0,done=0;__block NSDictionary *saved;__block NSString *savedMethod;
   BOOL(^call)(NSString *,NSDictionary *,void(^)(id))=^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
    calls++;saved=a;savedMethod=m;ScopeCases(modern?TIOGlassesFileIsScopedCall:OldUnion,m,a);
    assert(!(modern?OldUnion(m,a):TIOGlassesFileIsScopedCall(m,a)));
    assert(a.count==3);assert([a[@"filePath"] hasSuffix:names[i]]);
    cb(@{@"success":@YES,@"taskId":a[@"taskId"]});return YES;
   };
   id transport=modern?[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:names[i] validator:validator]:[[classes[i] alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call];
   NSString *task=NSUUID.UUID.UUIDString;
   [transport send:packet task:task submitted:^(BOOL ok,NSString *native){assert(ok&&[native isEqual:task]);done++;}];Pump();assert(calls==1&&done==1);
   assert(!OldUnion(savedMethod,saved)&&!TIOGlassesFileIsScopedCall(savedMethod,saved));
   NSMutableData *bad=[packet mutableCopy];((uint8_t *)bad.mutableBytes)[0]^=1;
   [transport send:bad task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *native){assert(!ok&&!native);done++;}];assert(calls==1&&done==2);
   [transport cleanup:task];
  }
 }
}
int main(void){@autoreleasepool{
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 NSData *packet=[NSMutableData dataWithLength:24];
 BOOL(^call)(NSString *,NSDictionary *,void(^)(id))=^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){assert(!"unexpected call");return NO;};
 TIOGlassesFileValidator yes=^BOOL(NSData *d){return YES;};
 for(id name in @[@"",@"a/b",@".",@"..",[@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0],@1])assert(![[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:name validator:yes]);
 assert(![[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:@"valid" validator:nil]);
 __block unsigned done=0;
 TIOGlassesFileTransport *wrong=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"other";} call:call fileName:@"valid" validator:yes];
 [wrong send:packet task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *n){assert(!ok&&!n);done++;}];assert(done==1);
 TIOGlassesFileTransport *valid=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:@"valid" validator:yes];
 [valid send:packet task:@"../x" submitted:^(BOOL ok,NSString *n){assert(!ok);done++;}];assert(done==2);
 TIOGlassesFileTransport *invalid=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:@"valid" validator:^BOOL(NSData *d){return NO;}];
 [invalid send:packet task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *n){assert(!ok);done++;}];assert(done==3);
 __block unsigned validations=0;
 TIOGlassesFileTransport *shortPacket=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:call fileName:@"valid" validator:^BOOL(NSData *d){validations++;return YES;}];
 [shortPacket send:[NSData dataWithBytes:"1234" length:4] task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *n){assert(!ok);done++;}];assert(done==4&&validations==0);
 __block unsigned callbacks=0,reentrant=0;__block NSDictionary *saved;
 NSString *task=NSUUID.UUID.UUIDString;
 TIOGlassesFileTransport *happy=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
  saved=a;ScopeCases(TIOGlassesFileIsScopedCall,m,a);assert(a.count==3);
  assert([[a[@"filePath"] lastPathComponent] isEqual:@"turbo-focus.tfp"]);
  assert([[NSData dataWithContentsOfFile:a[@"filePath"]] isEqual:packet]);
  NSDictionary *file=[NSFileManager.defaultManager attributesOfItemAtPath:a[@"filePath"] error:nil];
  NSDictionary *dir=[NSFileManager.defaultManager attributesOfItemAtPath:[a[@"filePath"] stringByDeletingLastPathComponent] error:nil];
  assert([file[NSFilePosixPermissions] unsignedIntValue]==0600&&[dir[NSFilePosixPermissions] unsignedIntValue]==0700);
  [valid send:packet task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *n){assert(!ok);reentrant++;}];assert(reentrant==1);
  cb(@{@"success":@YES,@"taskId":task});cb(@{@"success":@YES,@"taskId":task});return YES;
 } fileName:@"turbo-focus.tfp" validator:yes];
 [happy send:packet task:task submitted:^(BOOL ok,NSString *n){assert(ok&&[n isEqual:task]);callbacks++;}];Pump();assert(callbacks==1&&!TIOGlassesFileIsScopedCall(@"rayneonet_sendFile",saved));
 [happy cleanup:@"../x"];assert([NSFileManager.defaultManager fileExistsAtPath:[root URLByAppendingPathComponent:task].path]);
 [happy cleanup:task];assert(![NSFileManager.defaultManager fileExistsAtPath:[root URLByAppendingPathComponent:task].path]);
 for(unsigned throwing=0;throwing<2;throwing++){
  __block unsigned finished=0;__block NSDictionary *last;
  TIOGlassesFileTransport *t=[[TIOGlassesFileTransport alloc]initWithRoot:root device:@"peer" currentDevice:^{return @"peer";} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
   last=a;if(throwing)@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];cb(@{@"success":@YES});return YES;
  } fileName:@"turbo-diagnostics.tdg" validator:yes];
  NSString *idTask=NSUUID.UUID.UUIDString;[t send:packet task:idTask submitted:^(BOOL ok,NSString *n){assert(!ok&&!n);finished++;}];Pump();assert(finished==1&&!TIOGlassesFileIsScopedCall(@"rayneonet_sendFile",last));[t cleanup:idTask];
 }
 Equivalence(root);
 assert([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
 puts("PASS glasses file transport: legacy scoped-call equivalence, malformed calls, protocol validators, permissions and completion lifecycle");
}return 0;}
