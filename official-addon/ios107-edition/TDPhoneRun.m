#import "TDPhoneRun.h"
#import "TIOLanguage.h"
#include <math.h>
#include <sys/stat.h>
@implementation TDPhoneRun {
 TDPhoneStore *_store;NSURL *_root,*_reportDirectory;NSTimeInterval(^_clock)(void);
 BOOL(^_start)(uint32_t,uint32_t);void(^_stop)(void);BOOL _active;
 NSTimeInterval _began,_deadline,_lastReceipt,_lastSave;NSString *_reason,*_runID;
 NSMutableArray *_events;NSUInteger _droppedEvents,_revision;BOOL _received;
 dispatch_queue_t _writer;NSDictionary *_pending;BOOL _writing;NSString *_saveStatus;
}
- (instancetype)initWithStore:(TDPhoneStore *)store root:(NSURL *)root clock:(NSTimeInterval(^)(void))clock sendStart:(BOOL(^)(uint32_t,uint32_t))start sendStop:(void(^)(void))stop{
 if((self=[super init])){_store=store;_root=root;_clock=[clock copy];_start=[start copy];_stop=[stop copy];_events=[NSMutableArray new];_writer=dispatch_queue_create("io.turboio.diagnostics.archive",DISPATCH_QUEUE_SERIAL);_saveStatus=TIOText(@"尚未采集");}return self;
}
- (TDPhoneStore *)store{return _store;}
- (BOOL)active{return _active;}
- (NSURL *)reportDirectory{return _reportDirectory;}
- (NSString *)saveStatus{@synchronized(self){return _saveStatus;}}
- (NSTimeInterval)remaining{return _active?MAX(0,_deadline-_clock()):0;}
- (NSString *)status{
 if(_active)return !_received?TIOText(@"等待眼镜首条采样"):(_clock()-_lastReceipt>5?TIOText(@"采样暂时中断 · 原因未知"):TIOText(@"正在采集 · 可返回使用其他功能"));
 NSDictionary *names=@{@"user_stop":TIOText(@"已手动结束"),@"lease_elapsed":TIOText(@"10 分钟到期 · 本轮结束"),@"first_sample_timeout":TIOText(@"10 秒未收到首条采样"),@"telemetry_silent":TIOText(@"20 秒无新采样 · 原因未知，已结束"),@"submit_failed":TIOText(@"采集请求提交失败"),@"transfer_failed":TIOText(@"诊断文件传输失败"),@"probe_slow":TIOText(@"眼镜因采样耗时超标停止"),@"peer_context_changed":TIOText(@"设备上下文改变 · 已结束"),@"archive_unavailable":TIOText(@"无法创建本机报告 · 未开始")};
 return names[_reason]?:TIOText(@"未开始");
}
static BOOL Directory(NSURL *url){struct stat s;return url.isFileURL&&lstat(url.path.fileSystemRepresentation,&s)==0&&S_ISDIR(s.st_mode);}
- (BOOL)start{
 NSAssert(NSThread.isMainThread,@"main only");if(_active||!_clock||!_start||!isfinite(_clock()))return NO;
 NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(!_root.isFileURL||![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]||!Directory(_root)){_reason=@"archive_unavailable";return NO;}
 NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
 if(!entries||entries.count>=100){_reason=@"archive_unavailable";return NO;} // bounded disk, never delete old reports automatically
 NSURL *next=[_root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
 if(![fm createDirectoryAtURL:next withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){_reason=@"archive_unavailable";return NO;}
 [next setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 uint32_t sid;do{sid=arc4random();}while(!sid);
 if(![_store begin:sid]){[fm removeItemAtURL:next error:nil];return NO;}
 _reportDirectory=next;_runID=next.lastPathComponent;_reason=nil;_events=[NSMutableArray new];_droppedEvents=_revision=0;
 _began=_clock();_deadline=_began+600;_lastSave=_began;_lastReceipt=0;_received=NO;_active=YES;
 [self event:@"start_requested" fields:@{@"lease_ms":@600000}];[self checkpoint];
 if(!_start(sid,600000)){[self stop:@"submit_failed"];return NO;}return YES;
}
- (void)poll{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;NSTimeInterval now=_clock();
 if(now>=_deadline){[self stop:@"lease_elapsed"];return;}
 if(!_received&&now-_began>=10){[self stop:@"first_sample_timeout"];return;}
 if(_received&&now-_lastReceipt>=20){[self stop:@"telemetry_silent"];return;}
 if(now-_lastSave>=5)[self checkpoint];
}
- (BOOL)receive:(NSData *)packet device:(NSString *)device{
 NSAssert(NSThread.isMainThread,@"main only");[self poll];if(!_active||![_store receive:packet fromDevice:device])return NO;
 _lastReceipt=_clock();if(!_received){_received=YES;[self event:@"first_sample" fields:@{}];}
 if([_store.latest[@"probe_stopped_for_latency"]boolValue])[self stop:@"probe_slow"];
 else if(_lastReceipt-_lastSave>=5)[self checkpoint];return YES;
}
- (void)stop:(NSString *)reason{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *allowed=[NSSet setWithArray:@[@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed"]];
 _reason=[allowed containsObject:reason]?reason:@"user_stop";
 [self event:_reason fields:@{}];_active=NO;[_store end];if(_stop)_stop();[self checkpoint];
}
- (void)event:(NSString *)code fields:(NSDictionary *)fields{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *events=[NSSet setWithArray:@[@"start_requested",@"first_sample",@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed",@"app_background",@"app_foreground",@"music_reply",@"navigation_reply",@"file_submitted",@"file_finished",@"file_failed",@"peer_context_same",@"reply_rejected"]];
 if(![events containsObject:code])return;
 NSMutableDictionary *row=[@{@"event":code,@"phone_uptime_s":@(_clock()),@"elapsed_s":@(MAX(0,_clock()-_began)),@"wall_time_s":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
 NSSet *keys=[NSSet setWithArray:@[@"lease_ms",@"event_code",@"result",@"active",@"awake",@"stale",@"success",@"sequence",@"mode"]];
 if([fields isKindOfClass:NSDictionary.class])for(NSString *key in keys){id value=fields[key];if([value isKindOfClass:NSNumber.class]&&isfinite([value doubleValue])&&fabs([value doubleValue])<=UINT32_MAX)row[key]=value;}
 if(_events.count==512){[_events removeObjectAtIndex:0];_droppedEvents++;}[_events addObject:row];
}
- (NSData *)reportJSON{
 NSMutableDictionary *r=[[NSJSONSerialization JSONObjectWithData:[_store reportJSON] options:NSJSONReadingMutableContainers error:nil]mutableCopy];
 r[@"phone_build"]=@"DIAGNOSTICS-PHONE-02";r[@"run_id"]=_runID?:@"";r[@"process_id"]=@(NSProcessInfo.processInfo.processIdentifier);
 r[@"requested_seconds"]=@600;r[@"active"]=@(_active);r[@"stop_reason"]=_reason?:NSNull.null;r[@"revision"]=@(_revision);
 r[@"updated_wall_time_s"]=@(NSDate.date.timeIntervalSince1970);r[@"events"]=[_events copy];r[@"events_dropped"]=@(_droppedEvents);
 r[@"evidence_note"]=TIOText(@"操作事件来自已校验的协议回执，不等于镜片视觉确认；采样静默不能确认为蓝牙断开。关闭/崩溃后最后存盘状态可能为 active，不能视为仍在运行。");
 return [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
- (NSString *)reportMarkdown{
 return [NSString stringWithFormat:TIOText(@"%@\n## 自动记录\n\n运行：%@；手机版：DIAGNOSTICS-PHONE-02；进程：%d；快照版本：%lu。\n\n状态：%@；停止原因：%@；事件：%lu；事件淘汰：%lu。\n\n完整时间线见 JSON。协议回执不等于镜片视觉确认；采样静默的原因可能未知。报告不是崩溃转储。\n"),[_store reportMarkdown],_runID?:TIOText(@"未开始"),NSProcessInfo.processInfo.processIdentifier,(unsigned long)_revision,self.status,_reason?:TIOText(@"尚未停止"),(unsigned long)_events.count,(unsigned long)_droppedEvents];
}
- (void)checkpoint{
 NSAssert(NSThread.isMainThread,@"main only");if(!_reportDirectory)return;_lastSave=_clock();_revision++;
 NSData *json=[self reportJSON],*md=[[self reportMarkdown]dataUsingEncoding:NSUTF8StringEncoding];
 if(!json||json.length>4*1024*1024||md.length>1024*1024){@synchronized(self){_saveStatus=TIOText(@"报告超限 · 保存失败");}return;}
 NSDictionary *job=@{@"dir":_reportDirectory,@"json":json,@"md":md};
 // Ordered jobs are bounded by the ten-minute 5s cadence; coalesce only the same run.
 @synchronized(self){
  if(_pending&&![_pending[@"dir"]isEqual:_reportDirectory]){NSDictionary *old=_pending;dispatch_async(_writer,^{[self write:old];});}
  _pending=job;if(_writing)return;_writing=YES;
 }
 dispatch_async(_writer,^{for(;;){NSDictionary *next;@synchronized(self){next=self->_pending;self->_pending=nil;if(!next){self->_writing=NO;break;}}[self write:next];}});
}
- (void)write:(NSDictionary *)job{
 @autoreleasepool{NSURL *dir=job[@"dir"];NSFileManager *fm=NSFileManager.defaultManager;BOOL ok=Directory(_root)&&Directory(dir);
 for(NSString *name in @[@"json",@"md"]){if(!ok)break;NSURL *url=[dir URLByAppendingPathComponent:[@"diagnostics."stringByAppendingString:name]];
  ok=[job[name]writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
  if(ok)ok=[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];}
 @synchronized(self){_saveStatus=ok?TIOText(@"报告已自动保存到本机"):TIOText(@"自动保存失败 · 可手动分享");}
 }
}
- (void)waitForWrites{dispatch_sync(_writer,^{});}
@end

static NSDictionary *RuntimeSample(const TDSample *s){
 NSMutableString *hash=[NSMutableString new];for(unsigned i=0;i<32;i++)[hash appendFormat:@"%02x",s->build_sha[i]];
 NSArray *names=@[@"lv_configured_bytes",@"lv_used_bytes",@"lv_peak_bytes",@"lv_free_bytes",@"lv_largest_free_bytes",@"system_arena_bytes",@"system_used_bytes",@"system_peak_bytes",@"system_free_bytes",@"system_largest_free_bytes",@"instrumented_owned_bytes",@"instrumented_owned_peak_bytes",@"allocation_failures",@"rx_packets",@"rx_bytes",@"rx_max_ms",@"render_submissions",@"render_max_ms",@"errors"];
 NSMutableDictionary *metrics=[NSMutableDictionary new];for(NSUInteger i=0;i<names.count;i++)metrics[names[i]]=(s->valid&(1u<<i))?@(s->values[i]):NSNull.null;
 return @{@"firmware":s->build==TD_BUILD_TMG6?@"TMG6":s->build==TD_BUILD_TMG5?@"TMG5":@"TMG4",@"build":hash,@"caps":@(s->caps),@"nand_total":(s->extension_valid&TD_EXT_NAND)?@(s->nand_total):NSNull.null,@"nand_available":(s->extension_valid&TD_EXT_NAND)?@(s->nand_available):NSNull.null,@"language":(s->extension_valid&TD_EXT_LANGUAGE)?@(s->language):NSNull.null,@"language_source":(s->extension_valid&TD_EXT_LANGUAGE)?@(s->language_source):NSNull.null,@"tile_generation":(s->extension_valid&TD_EXT_TILES)?@(s->tile_generation):NSNull.null,@"detent":@(s->detent),@"settings_flags":@(s->settings_flags),@"metrics":metrics};
}
static NSDictionary *RuntimeCalibration(const TDSample *s){
 if(!(s->extension_valid&TD_EXT_CALIBRATION))return @{};
 return @{@"window":@(s->calibration_window),@"state":@(s->calibration_state),@"elapsed_ms":@(s->calibration_elapsed),@"samples":@(s->calibration_samples),@"net":@(s->calibration_net),@"absolute":@(s->calibration_absolute),@"sequence":@(s->calibration_sequence)};
}
@implementation TDRuntimeSession {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);NSTimeInterval(^_clock)(void);BOOL(^_send)(TDCommand);
 NSString *_peer,*_state;NSDictionary *_sample,*_calibration;NSNumber *_estimate;
 BOOL _fileBusy,_pending,_holdsLease,_finishRequested,_cancelRequested,_startDeliveryUncertain;TDCommand _command;
 uint32_t _window;NSUInteger _epoch;NSTimeInterval _sentAt,_deadline,_leaseDeadline,_sampleAt;
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(NSTimeInterval(^)(void))clock send:(BOOL(^)(TDCommand))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_send=[send copy];_peer=[peer()copy]?:@"";_state=@"idle";_sample=_calibration=@{};}return self;
}
- (void)invalidate{
 _pending=NO;_finishRequested=_cancelRequested=NO;_estimate=nil;_state=@"canceled";_calibration=@{};_epoch++;
 if(![_peer isEqual:_peerNow()]){_holdsLease=NO;_startDeliveryUncertain=NO;_sample=@{};_sampleAt=0;}
}
- (BOOL)context{return _peer.length&&[_peer isEqual:_peerNow()]&&_allowed()&&isfinite(_clock());}
- (BOOL)sendCommand:(TDCommand)q{
 if(![self context]||_pending||_fileBusy)return NO;NSTimeInterval now=_clock();_command=q;_pending=YES;_sentAt=now;_deadline=now+3;NSUInteger epoch=++_epoch;
 _state=q.op==TDQ_STATUS?@"querying":q.op==TDQ_KNOB_START?@"starting":_cancelRequested?@"canceling":@"finishing";
 BOOL sent=_send(q);if(!sent&&_epoch==epoch&&_pending){_pending=NO;_state=@"unavailable";_finishRequested=NO;if(q.op==TDQ_KNOB_START&&!_fileBusy){_holdsLease=NO;_startDeliveryUncertain=NO;}}
 return sent;
}
- (void)pumpFinish{
 if(!_finishRequested||!_holdsLease||_pending||_fileBusy||![self context])return;_finishRequested=NO;(void)[self sendCommand:(TDCommand){TDQ_KNOB_STOP,_window,2,0}];
}
- (void)poll{
 NSAssert(NSThread.isMainThread,@"main only");NSTimeInterval now=_clock();if(!isfinite(now)||![_peer isEqual:_peerNow()]||!_allowed()){[self invalidate];return;}
 if(_holdsLease&&now>=_leaseDeadline){_holdsLease=NO;_finishRequested=NO;_estimate=nil;if([@[@"starting",@"rotating",@"finishing",@"canceling"]containsObject:_state])_state=@"expired";}
 if(_pending&&(now<_sentAt||now>=_deadline)){_pending=NO;_finishRequested=NO;_estimate=nil;_state=@"unavailable";_epoch++;}
 [self pumpFinish];
}
- (BOOL)sampleFresh{NSTimeInterval now=_clock();return _sampleAt>0&&isfinite(now)&&now>=_sampleAt&&now-_sampleAt<=TDGlassesCapsFreshSeconds;}
- (uint32_t)glassesCaps{NSNumber *caps=[_peer isEqual:_peerNow()]&&[self sampleFresh]?_sample[@"caps"]:nil;return [caps isKindOfClass:NSNumber.class]?caps.unsignedIntValue:0;}
- (BOOL)glassesReportTMG8Caps{return (self.glassesCaps&TD_CAP_MENU_CAROUSEL)!=0;}
- (NSString *)glassesFirmware{NSString *name=[_peer isEqual:_peerNow()]&&[self sampleFresh]?_sample[@"firmware"]:nil;return [name isKindOfClass:NSString.class]&&name.length?name:nil;}
- (BOOL)idleForOTA{NSTimeInterval now=_clock();if(!isfinite(now))return NO;BOOL lease=_holdsLease&&now<_leaseDeadline,request=_pending&&(now<_sentAt||now<_deadline);return !_fileBusy&&!lease&&!request;}
- (BOOL)pending{[self poll];return _pending;}
- (BOOL)holdsLease{[self poll];return _holdsLease;}
- (BOOL)fileBusy{return _fileBusy;}
- (void)setFileBusy:(BOOL)busy{
 BOOL terminal=_fileBusy&&!busy;_fileBusy=busy;
 // An unacknowledged START may execute as late as the native terminal callback.
 // A validated ACK already supplies its deadline and must never be renewed here.
 if(terminal&&_startDeliveryUncertain){_startDeliveryUncertain=NO;_holdsLease=YES;_leaseDeadline=_clock()+30;}
 if(!busy)[self poll];
}
- (NSDictionary *)status{
 [self poll];NSTimeInterval age=_sampleAt?_clock()-_sampleAt:-1;
 return @{@"state":_state,@"sample":_sample?:@{},@"calibration":_calibration?:@{},@"estimate":_estimate?:NSNull.null,@"pending":@(_pending),@"fileBusy":@(_fileBusy),@"holdsLease":@(_holdsLease),@"sampleAge":@(age>=0?age:-1)};
}
- (BOOL)query{[self poll];if(_pending||_fileBusy||![self context])return NO;uint32_t request=arc4random_uniform(UINT32_MAX-1)+1;return [self sendCommand:(TDCommand){TDQ_STATUS,request,1,0}];}
- (BOOL)beginCalibration{
 [self poll];if(_pending||_fileBusy||_holdsLease||![self context])return NO;uint32_t next=arc4random_uniform(UINT32_MAX-1)+1;if(next==_window){next++;if(!next)next=1;}_window=next;_holdsLease=YES;_startDeliveryUncertain=YES;_leaseDeadline=_clock()+30;_finishRequested=_cancelRequested=NO;_estimate=nil;_calibration=@{};
 return [self sendCommand:(TDCommand){TDQ_KNOB_START,_window,1,TK_MAX_LEASE_MS}];
}
- (void)finishCalibration{[self poll];if(!_holdsLease)return;_finishRequested=YES;_cancelRequested=NO;[self pumpFinish];}
- (void)cancelCalibration{[self poll];_estimate=nil;if(!_holdsLease){_state=@"canceled";return;}_finishRequested=_cancelRequested=YES;[self pumpFinish];}
- (void)transportFailed{_pending=NO;_finishRequested=NO;_estimate=nil;_state=@"unavailable";_epoch++;}
- (BOOL)receive:(NSData *)packet device:(NSString *)device{
 [self poll];TDSample s;if(!_pending||![device isEqual:_peer]||![packet isKindOfClass:NSData.class]||!td_decode(packet.bytes,packet.length,&s)||s.kind==TD_SAMPLE||s.session!=_command.session||s.sequence!=_command.sequence||s.kind!=(_command.op==TDQ_STATUS?TD_STATUS:TD_CALIBRATION))return NO;
 TDCommand command=_command;_pending=NO;_epoch++;
 if(s.calibration_result==TK_OK&&command.op!=TDQ_STATUS){
  if(!(s.extension_valid&TD_EXT_CALIBRATION)||s.calibration_window!=_window||s.calibration_sequence!=command.sequence||(command.op==TDQ_KNOB_STOP&&s.calibration_state==TK_ACTIVE)){_state=@"unavailable";_estimate=nil;return NO;}
 }
 if(command.op==TDQ_KNOB_START){_startDeliveryUncertain=NO;if(s.calibration_result!=TK_OK){_holdsLease=NO;_finishRequested=_cancelRequested=NO;}}
 _calibration=RuntimeCalibration(&s);
 if(![_calibration[@"window"]isEqual:@(_window)])_estimate=nil;
 if(s.calibration_result!=TK_OK){_state=s.calibration_result==TK_BLOCKED?(command.op==TDQ_STATUS?@"blocked":@"menuRequired"):s.calibration_result==TK_BUSY?@"busy":s.calibration_result==TK_OVERFLOW_RESULT?@"overflow":@"unavailable";_estimate=nil;if(s.calibration_window==_window&&s.calibration_state!=TK_ACTIVE)_holdsLease=NO;return YES;}
 if(command.op==TDQ_STATUS){_sample=RuntimeSample(&s);_sampleAt=_clock();if(_holdsLease&&(s.calibration_window!=_window||s.calibration_state!=TK_ACTIVE))_holdsLease=NO;_state=_holdsLease?@"rotating":@"ready";}
 else if(s.calibration_state==TK_ACTIVE){_holdsLease=YES;_leaseDeadline=_clock()+(TK_MAX_LEASE_MS-s.calibration_elapsed)/1000.0;_state=_finishRequested?(_cancelRequested?@"canceling":@"finishing"):@"rotating";}
 else{
  _holdsLease=NO;_state=_cancelRequested?@"canceled":s.calibration_state==TK_FINISHED?@"finished":s.calibration_state==TK_EXPIRED?@"expired":s.calibration_state==TK_OVERFLOW?@"overflow":@"canceled";
  TKState knob={.state=s.calibration_state,.samples=s.calibration_samples,.net=s.calibration_net,.absolute=s.calibration_absolute};uint64_t value;if(command.op==TDQ_KNOB_STOP&&!_cancelRequested&&tk_estimate(&knob,&value))_estimate=@(value);else _estimate=nil;_cancelRequested=NO;
 }
 [self pumpFinish];return YES;
}
@end
