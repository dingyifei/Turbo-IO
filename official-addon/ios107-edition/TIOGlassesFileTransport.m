#import "TIOGlassesFileTransport.h"
#import "DisplayDiagnostics.h"
static NSDictionary *ScopedArgs;
BOOL TIOGlassesFileIsScopedCall(NSString *method,NSDictionary *args){return NSThread.isMainThread&&ScopedArgs&&args==ScopedArgs&&[method isEqual:@"rayneonet_sendFile"];}
// Canonically rebuild every supported packet, rejecting mismatched lengths,
// reserved fields, CRCs, geometry and op-specific fields before SDK access.
static uint32_t U32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
@implementation TIOGlassesFileTransport {
 NSURL *_root;NSString *_device;NSString *(^_current)(void);BOOL(^_call)(NSString *,NSDictionary *,void(^)(id));NSString *_fileName;TIOGlassesFileValidator _validator;
}
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call fileName:(NSString *)fileName validator:(TIOGlassesFileValidator)validator{
 if(![fileName isKindOfClass:NSString.class]||!fileName.length||fileName.length>64||![fileName isEqual:fileName.lastPathComponent]||[fileName isEqual:@"."]||[fileName isEqual:@".."]||!validator)return nil;
 if((self=[super init])){_root=root;_device=[device copy];_current=[current copy];_call=[call copy];_fileName=[fileName copy];_validator=[validator copy];}return self;
}
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TIOGlassesFileSubmitted)done{
 NSAssert(NSThread.isMainThread,@"main only");if(!done)return;
 if(!([packet isKindOfClass:NSData.class]&&packet.length>=16&&_validator(packet))||!_root.isFileURL||!_device.length||!_current||![_current() isEqual:_device]||!_call||ScopedArgs||![task isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:task]){done(NO,nil);return;}
 NSFileManager *fm=NSFileManager.defaultManager;NSError *err=nil;
 if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&err]){done(NO,nil);return;}
 NSDictionary *attr=[fm attributesOfItemAtPath:_root.path error:&err];NSArray *items=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&err];
 if(err||![attr[NSFileType] isEqual:NSFileTypeDirectory]||!items||items.count>=512){done(NO,nil);return;}
 NSURL *dir=[_root URLByAppendingPathComponent:task isDirectory:YES];
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&err]){done(NO,nil);return;}
 NSURL *url=[dir URLByAppendingPathComponent:_fileName];
 if(![packet writeToURL:url options:NSDataWritingWithoutOverwriting error:&err]){done(NO,nil);return;}
 [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
 NSDictionary *args=@{@"deviceId":_device,@"filePath":url.path,@"taskId":task};
 __block BOOL completed=NO;
 TIOGlassesFileSubmitted finish=^(BOOL ok,NSString *nativeTask){NSString *pinned=[nativeTask copy];dispatch_async(dispatch_get_main_queue(),^{if(completed)return;completed=YES;done(ok,pinned);});};
 BOOL invoked=NO;ScopedArgs=args;
 TDPDiagRecord(@"native_before",@{@"bytes":@(packet.length),@"op":@(((const uint8_t *)packet.bytes)[5]),@"request":@(U32((const uint8_t *)packet.bytes+12))});
 @try{invoked=_call(@"rayneonet_sendFile",args,^(id result){
  BOOL dict=[result isKindOfClass:NSDictionary.class];NSMutableDictionary *n=[@{@"dictionary":@(dict),@"null":@(result==nil||result==NSNull.null),@"hasSuccess":@(dict&&result[@"success"]!=nil),@"success":@(dict&&[result[@"success"] isEqual:@YES])} mutableCopy];
  if(dict)for(NSString *key in @[@"code",@"errorCode"]){if([result[key] isKindOfClass:NSNumber.class])n[key]=result[key];}
  id nativeTask=dict?result[@"taskId"]:nil;
  BOOL validTask=[nativeTask isKindOfClass:NSString.class]&&[nativeTask length]>0&&[nativeTask length]<=256;
  n[@"hasTask"]=@(validTask);n[@"taskMatch"]=@(validTask&&[nativeTask isEqual:task]);
  TDPDiagRecord(@"native_result",n);finish(dict&&[result[@"success"] isEqual:@YES]&&validTask,validTask?nativeTask:nil);
 });}
 @catch(NSException *e){TDPDiagRecord(@"native_exception",@{});invoked=NO;}@finally{ScopedArgs=nil;}
 TDPDiagRecord(@"native_return",@{@"invoked":@(invoked)});
 if(!invoked)finish(NO,nil);
 // Keep bounded files for uncertain native ownership. Never delete on timeout.
}
- (void)cleanup:(NSString *)task{if(![[NSUUID alloc]initWithUUIDString:task])return;NSURL *dir=[_root URLByAppendingPathComponent:task isDirectory:YES];[NSFileManager.defaultManager removeItemAtURL:dir error:nil];}
@end
