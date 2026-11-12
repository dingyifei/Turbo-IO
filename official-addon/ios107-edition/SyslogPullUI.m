#import "SyslogPullUI.h"
#import "SyslogPull.h"
#import "TIOConfirm.h"
#import "TIOLanguage.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <stdatomic.h>
// Passive by construction: the only thing sent is the single request below. No 0x11 ack, no
// reply, no change to the stock receiver's acceptance or MD5 handling. Results stay in memory
// and in one local text file of probe lines; nothing is uploaded or shared from here.
static __weak id Plugin;static NSDictionary *Route;static NSTimeInterval RouteAt,Started;static BOOL Injecting;
static _Atomic(BOOL) Armed;
static NSString *Device,*TaskId,*Detail;
static TIOSyslogAssembler *Asm;static NSDictionary *Notice;static NSData *DoneRaw;static NSArray *Lines;
static NSUInteger ProgressEvents;static BOOL Decoded;static NSString *FileFailure;
static NSString *Hex(NSData *d){NSMutableString *s=[NSMutableString new];const uint8_t *b=d.bytes;for(NSUInteger i=0;i<d.length&&i<32;i++)[s appendFormat:@"%02x",b[i]];return s;}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;@try{id d=[o valueForKey:@"data"];return [d isKindOfClass:NSData.class]?d:nil;}@catch(NSException *e){return nil;}}
static void Changed(NSString *detail){Detail=detail;[NSNotificationCenter.defaultCenter postNotificationName:@"TIOSyslogPullChanged" object:nil];}
static void Save(void){
 NSURL *u=[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/SyslogPull" isDirectory:YES];
 [NSFileManager.defaultManager createDirectoryAtURL:u withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];[u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 NSURL *f=[u URLByAppendingPathComponent:@"probe-lines.txt"];NSString *body=[Lines componentsJoinedByString:@"\n"];
 if([body writeToURL:f atomically:YES encoding:NSUTF8StringEncoding error:nil])[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:f.path error:nil];
}
static void Finish(void){
 if(Decoded||!Asm)return;Decoded=YES;atomic_store(&Armed,NO);
 NSData *raw=Asm.data;NSData *text=TIOLZ4DecodeFrame(raw,64u<<20);
 if(!text){Changed([NSString stringWithFormat:TIOText(@"common.ui.sensorLog.state.nodecode"),(unsigned long)raw.length,(unsigned long long)Asm.expectedSize]);return;}
 Lines=TIOSyslogProbeLines(text);Save();
 Changed([NSString stringWithFormat:TIOText(@"common.ui.sensorLog.state.done"),(unsigned long)text.length,(unsigned long)Lines.count]);
}
BOOL TIOSyslogCapturing(void){return atomic_load(&Armed);}
void TIOSyslogObserveCall(id plugin,NSString *method,NSDictionary *args){
 if(Injecting||![method isEqual:@"rayneonet_sendMessage"]||![args[@"deviceId"] isKindOfClass:NSString.class]||![args[@"businessId"] isKindOfClass:NSNumber.class])return;
 Device=args[@"deviceId"];Plugin=plugin;NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;RouteAt=NSDate.date.timeIntervalSince1970;
}
void TIOSyslogObserveEvent(NSDictionary *event){
 if(!atomic_load(&Armed)||![event isKindOfClass:NSDictionary.class])return;
 NSString *type=event[@"eventType"];
 if([type isEqual:@"messageReceived"]){
  NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:Device])return;NSData *p=Bytes(m[@"payload"]);
  if([m[@"businessId"] isEqual:@16]){
   NSDictionary *n=TIOSyslogParseNotice(p);if(!n)return;
   if([n[@"sub"] isEqual:@0x13]){Notice=n;[Asm expectSize:[n[@"size"] unsignedLongLongValue] name:n[@"name"]];Changed([NSString stringWithFormat:TIOText(@"common.ui.sensorLog.state.notice"),n[@"name"],[n[@"size"] unsignedLongLongValue]]);}
   else{DoneRaw=n[@"raw"];if(!Notice){Changed(TIOText(@"common.ui.sensorLog.state.doneEarly"));return;}
    if(Asm.data.length)Finish();else Changed([NSString stringWithFormat:TIOText(@"common.ui.sensorLog.state.nodata"),Hex(DoneRaw)]);}
  }else if([m[@"businessId"] isEqual:@17]&&Notice&&!Asm.complete){ // raw file-share frame, if the bridge ever delivers one
   [Asm feedTransferMessage:p];if(Asm.complete)Finish();
  }
  return;
 }
 if(!Notice)return; // file events only count after the glasses announced the log
 if([type isEqual:@"fileShareProgress"]&&[event[@"role"] isEqual:@"receiver"]){
  NSString *task=event[@"taskId"];if(!TaskId&&[task isKindOfClass:NSString.class])TaskId=task;if(![TaskId isEqual:task])return;
  NSData *c=Bytes(event[@"chunkData"]);ProgressEvents++;
  if(c.length)[Asm appendChunk:c];
  Changed([NSString stringWithFormat:TIOText(@"common.ui.sensorLog.state.progress"),(unsigned long)Asm.data.length,(unsigned long long)Asm.expectedSize]);
  if(Asm.complete)Finish();
 }else if([type isEqual:@"fileShareFailed"]&&[event[@"role"] isEqual:@"receiver"]&&(!TaskId||[TaskId isEqual:event[@"taskId"]])){
  id e=event[@"error"];id msg=[e isKindOfClass:NSDictionary.class]?e[@"message"]:nil;FileFailure=[msg isKindOfClass:NSString.class]?msg:@"?";
  if(Asm.data.length&&!Decoded)Finish(); // the stock receiver may reject the advertised md5; the bytes were still delivered
 }
}
static BOOL Ready(void){return Plugin&&Route&&Device.length&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&NSDate.date.timeIntervalSince1970-RouteAt<120;}
static void Start(void){
 if(!Ready()){Changed(TIOText(@"common.ui.sensorLog.state.notready"));return;}
 Class typed=NSClassFromString(@"FlutterStandardTypedData"),cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),bytes=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(![typed respondsToSelector:bytes]||![cls respondsToSelector:make]||![Plugin respondsToSelector:handle]){Changed(TIOText(@"common.ui.sensorLog.state.abi"));return;}
 NSDictionary *req=TIOSyslogRequest();NSMutableDictionary *a=[Route mutableCopy];a[@"businessId"]=req[@"businessId"];a[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,bytes,req[@"payload"]);
 id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,@"rayneonet_sendMessage",a);
 Asm=[TIOSyslogAssembler new];Notice=nil;DoneRaw=nil;Lines=nil;TaskId=nil;FileFailure=nil;ProgressEvents=0;Decoded=NO;atomic_store(&Armed,YES);
 Started=NSDate.date.timeIntervalSince1970;NSTimeInterval round=Started;Changed(TIOText(@"common.ui.sensorLog.state.requested"));
 Injecting=YES;@try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,[^(id r){dispatch_async(dispatch_get_main_queue(),^{BOOL ok=[r isKindOfClass:NSDictionary.class]&&[r[@"success"] isEqual:@YES];if(!ok&&Started==round&&!Notice)Changed(TIOText(@"common.ui.sensorLog.state.notaccepted"));});} copy]);}
 @catch(NSException *e){Changed(TIOText(@"common.ui.sensorLog.state.exception"));}@finally{Injecting=NO;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  if(Started!=round||Decoded||!atomic_load(&Armed))return;
  if(Asm.data.length){Finish();return;}
  atomic_store(&Armed,NO);Changed(TIOText(@"common.ui.sensorLog.state.timeout"));});
}
@interface TIOSyslogPullPanel:UITableViewController @end
@implementation TIOSyslogPullPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=TIOText(@"hub.row.sensorLog");[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOSyslogPullChanged" object:nil];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)v{return 2;}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return s==0?2:MAX((NSInteger)Lines.count,1);}
- (NSString *)tableView:(UITableView *)v titleForHeaderInSection:(NSInteger)s{return s==1?TIOText(@"common.ui.sensorLog.lines"):nil;}
- (NSString *)tableView:(UITableView *)v titleForFooterInSection:(NSInteger)s{return s==0?TIOText(@"common.ui.sensorLog.footer"):nil;}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;
 if(p.section==0){c.accessibilityIdentifier=[NSString stringWithFormat:@"sensor-log-%ld",(long)p.row];
  if(p.row==0){c.textLabel.text=TIOText(@"common.ui.sensorLog.status");c.detailTextLabel.text=Detail?:TIOText(@"common.ui.sensorLog.state.idle");}
  else{c.textLabel.text=TIOText(@"common.ui.sensorLog.request");c.detailTextLabel.text=Ready()?TIOText(@"common.ui.sensorLog.ready"):TIOText(@"common.ui.sensorLog.notready");}
  return c;}
 c.textLabel.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];c.textLabel.text=Lines.count?Lines[p.row]:(Decoded?TIOText(@"common.ui.sensorLog.nomatch"):@"-");return c;
}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(p.section!=0||p.row!=1)return;
 TIOConfirm(self,TIOText(@"common.ui.sensorLog.confirm.title"),TIOText(@"common.ui.sensorLog.confirm.message"),TIOText(@"common.ui.sensorLog.confirm.action"),NO,^{Start();});}
@end
UIViewController *TIOSyslogPullController(void){return [[TIOSyslogPullPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
