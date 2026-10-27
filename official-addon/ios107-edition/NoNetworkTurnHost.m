#import "NoNetworkTurn.h"
#import "Core.h"
#import <Network/Network.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>

static id NNGet(id value,NSString *key){@try{return [value valueForKey:key];}@catch(NSException *e){return nil;}}
static NSString *NNString(id value){return [value isKindOfClass:NSString.class]?value:@"";}
@class NNHost;
@interface NNIngress:NSObject
@property(nonatomic) id listener;
@property(nonatomic,copy) NSString *sid,*text;
@property(nonatomic) BOOL final,duplicate,veto;
@property(nonatomic) NSUInteger before;
@end
@implementation NNIngress @end
@interface NNErrorHook:NSObject
@property(nonatomic) IMP original, replacement;
@property(nonatomic) BOOL objectCode;
@property(atomic,weak) NNHost *owner;
@end
@implementation NNErrorHook @end
@interface NNHeld:NSObject
@property(nonatomic) TIONoNetworkEvent kind;
@property(nonatomic) id listener,value,message,objectCode;
@property(nonatomic) uintptr_t code;
@property(nonatomic) IMP error;
@end
@implementation NNHeld @end

@interface NNHost:NSObject { _Atomic(bool) _routing; }
@property(nonatomic) TIONoNetworkState *core;
@property(nonatomic) NNIngress *ingress;
@property(nonatomic) NSMutableArray<NNHeld *> *held;
@property(nonatomic) NSMutableArray<dispatch_block_t> *events;
@property(nonatomic) TIONoNetworkReadState readState;
@property(nonatomic) TIONoNetworkTakeover takeover;
@property(nonatomic) TIONoNetworkReplayNlp replay;
@property(nonatomic) TIONoNetworkReplayComplete complete;
@property(nonatomic) dispatch_block_t stopHost;
@property(nonatomic) TIONoNetworkScheduler scheduler;
@property(nonatomic) NSTimeInterval (^clock)(void);
@property(nonatomic) Class (^lookup)(NSString *);
@property(nonatomic) Class voice;
@property(nonatomic) BOOL installed,testing,known,satisfied,pumpScheduled,spill,failedOpen,overflowPending;
@property(nonatomic) NSUInteger depth,spillPending,life,protectEpoch,protectGeneration;
@property(nonatomic,weak) id protectListener;
@property(nonatomic) BOOL protecting,protectionScheduled;
@property(nonatomic) double protectionBegan;
@property(nonatomic) TIOIdleExitGate *stopGate;
@property(nonatomic) NSUInteger stopToken;
@property(nonatomic) nw_path_monitor_t monitor;
- (BOOL)needsRouting;
- (void)submit:(TIONoNetworkEvent)kind listener:(id)listener tool:(BOOL)tool work:(dispatch_block_t)work;
- (BOOL)routeError:(NNHeld *)entry;
@end

@implementation NNHost
- (instancetype)init {if((self=[super init])){_life=1;[self resetFields];}return self;}
- (void)resetFields {
    _core=[TIONoNetworkState new];_held=[NSMutableArray new];_events=[NSMutableArray new];_stopGate=[TIOIdleExitGate new];
    _clock=^{return NSProcessInfo.processInfo.systemUptime;};_lookup=^Class(NSString *name){return NSClassFromString(name);};
    atomic_store(&_routing,false);
}
- (TIONoNetworkSnapshot *)snapshot {return _readState?_readState():[TIONoNetworkSnapshot new];}
- (double)now {return _clock?_clock():NSProcessInfo.processInfo.systemUptime;}
- (void)log:(NSString *)event {[_core record:event at:self.now sid:_core.sid];}
- (BOOL)mode:(TIONoNetworkSnapshot *)s {return TIONoNetworkModeEligible(s.mode,s.appleFallback);}
- (void)publish {atomic_store_explicit(&_routing,_ingress||_depth||_core.phase!=TIONoNetworkIdle||_protecting||_events.count||_spillPending||_pumpScheduled,memory_order_release);}
- (BOOL)needsRouting {return atomic_load_explicit(&_routing,memory_order_acquire);}
- (void)after:(double)delay work:(dispatch_block_t)work {
    NSUInteger life=_life;dispatch_block_t guarded=^{if(self.life==life)work();};
    if(_scheduler)_scheduler(delay,guarded);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),guarded);
}
- (void)transaction:(dispatch_block_t)work {
    _depth++;[self publish];@try{work();}@finally{_depth--;[self publish];}
}
- (void)replayEntries:(NSArray<NNHeld *> *)entries {
    if(!entries.count)return;[self log:@"replay-held"];
    [self transaction:^{for(NNHeld *e in entries){
        if(e.kind==TIONoNetworkNlpEvent){if(self.replay)self.replay(e.listener,e.value);}
        else if(e.kind==TIONoNetworkCompleteEvent){if(self.complete)self.complete(e.listener);}
        else if(e.error)((void(*)(id,SEL,uintptr_t,id))e.error)(e.listener,NSSelectorFromString(@"onError:message:"),e.objectCode?(uintptr_t)(__bridge void *)e.objectCode:e.code,e.message);
    }}];
}
- (void)cancel:(NSString *)reason {
    NSArray *entries=[_held copy];[_held removeAllObjects];[self log:reason];[_core clear];[_stopGate cancel];[self publish];[self replayEntries:entries];
}
- (void)applyOverflow {
    if(!_overflowPending)return;_overflowPending=NO;
    [self cancel:@"skip:overflow"];
    // The unfinished controller generation stays protected after interception ends.
    [self scheduleProtection:0];
}
- (void)enqueue:(dispatch_block_t)work {
    if(!_spill&&_events.count<64){
        [_events addObject:[work copy]];
        if(!_pumpScheduled){_pumpScheduled=YES;[self after:0 work:^{
            self.pumpScheduled=NO;[self applyOverflow];
            NSArray<dispatch_block_t> *batch=[self.events copy];[self.events removeAllObjects];
            [self transaction:^{for(dispatch_block_t event in batch)event();}];[self publish];
        }];}
    }else{
        if(!_spill){_spill=YES;_failedOpen=YES;_overflowPending=YES;[self log:@"skip:overflow"];}
        _spillPending++;
        __block BOOL consumed=NO;
        [self after:0 work:^{if(consumed)return;consumed=YES;@try{[self applyOverflow];[self transaction:work];}@finally{self.spillPending--;[self publish];}}];
    }
    [self publish];
}
- (void)submit:(TIONoNetworkEvent)kind listener:(id)listener tool:(BOOL)tool work:(dispatch_block_t)work {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self submit:kind listener:listener tool:tool work:work];});return;}
    if(kind==TIONoNetworkNlpEvent&&tool){work();return;}
    if(_ingress&&_ingress.listener==listener&&(kind==TIONoNetworkNlpEvent||kind==TIONoNetworkCompleteEvent||kind==TIONoNetworkErrorEvent))_ingress.veto=YES;
    BOOL intercept=_core.phase==TIONoNetworkTaking||_core.phase==TIONoNetworkOwned||_core.phase==TIONoNetworkTail;
    if(_depth||intercept||_protecting||_events.count||_spillPending||_pumpScheduled){[self enqueue:work];return;}
    TIONoNetworkSnapshot *s=self.snapshot;
    if(_installed&&!_failedOpen&&[self mode:s]&&s.verified&&s.hooksReady&&s.voiceExitReady)[self transaction:work];else work();
}
- (void)scheduleProtection:(double)delay {
    if(!_protecting||_protectionScheduled)return;_protectionScheduled=YES;
    NSUInteger token=_protectEpoch;
    [self after:delay work:^{
        if(token!=self.protectEpoch)return;self.protectionScheduled=NO;if(!self.protecting)return;
        TIONoNetworkSnapshot *s=self.snapshot;
        if(s.generation!=self.protectGeneration||s.listener!=self.protectListener||s.responseDone){self.protecting=NO;self.protectListener=nil;[self publish];return;}
        // Poll work is finite; subsequent ingress can request another safe check.
        if(delay>0&&self.now-self.protectionBegan<180)[self scheduleProtection:0.5];
    }];
}
- (void)protect:(TIONoNetworkSnapshot *)s {
    _protecting=YES;_protectionBegan=self.now;_protectGeneration=s.generation;_protectListener=s.listener;++_protectEpoch;_protectionScheduled=NO;
    [self publish];[self scheduleProtection:0.5];
}
- (void)refresh {
    if(_protecting)[self scheduleProtection:0];
    if(_core.phase==TIONoNetworkIdle||_core.phase==TIONoNetworkTaking)return;
    TIONoNetworkSnapshot *s=self.snapshot;
    BOOL matches=s.generation==_core.controllerGeneration&&s.listener==_core.listener;
    if(!matches||s.voiceExited||![self mode:s]||!s.verified||!s.hooksReady||!s.voiceExitReady){[self cancel:s.voiceExited?@"cancel:exit":@"cancel:speech"];return;}
    if(_core.phase==TIONoNetworkArmed&&s.ownsTurn){[self cancel:@"skip:owned"];return;}
    if(_core.phase==TIONoNetworkOwned&&s.responseDone){
        [_core finishAt:self.now];
        [_stopGate responseFinishedForToken:_stopToken];
        if(s.stopHost&&[_stopGate beginWaitingForToken:_stopToken atTime:self.now delay:2]){
            NSUInteger epoch=_core.epoch,token=_stopToken;
            [self after:2 work:^{TIONoNetworkSnapshot *current=self.snapshot;
                if(self.core.epoch!=epoch||current.generation!=self.core.controllerGeneration||current.listener!=self.core.listener||current.voiceExited||![self mode:current]||!current.stopHost)return;
                if([self.stopGate shouldExitForToken:token atTime:self.now]){[self.stopGate cancel];[self log:@"stop-host"];if(self.stopHost)[self transaction:self.stopHost];}
            }];
        }
    }
    if(_core.phase==TIONoNetworkTail&&self.now>=_core.tailUntil){[self log:@"tail-end"];[_core clear];[self publish];}
}
- (void)poll:(NSUInteger)epoch began:(double)began {
    [self after:0.5 work:^{if(self.core.epoch!=epoch)return;[self refresh];
        if(self.core.epoch==epoch&&(self.core.phase==TIONoNetworkOwned||self.core.phase==TIONoNetworkTail)&&self.now-began<180)[self poll:epoch began:began];
        else if(self.now-began>=180)[self.stopGate cancel];
    }];
}
- (BOOL)ensureErrorHook {
    static char association;
    NNErrorHook *record=objc_getAssociatedObject(_voice,&association);
    SEL selector=NSSelectorFromString(@"onError:message:");Method method=class_getInstanceMethod(_voice,selector);
    if(record){if(method_getImplementation(method)!=record.replacement){[self log:@"error-hook:skip"];return NO;}record.owner=self;return YES;}
    BOOL valid=method&&method_getNumberOfArguments(method)==4;char *r=NULL,*a=NULL,*b=NULL;
    if(valid){r=method_copyReturnType(method);a=method_copyArgumentType(method,2);b=method_copyArgumentType(method,3);valid=r&&r[0]=='v'&&a&&strchr("qQlLiI@",a[0])&&b&&b[0]=='@';}
    BOOL objectCode=a&&a[0]=='@';free(r);free(a);free(b);
    if(!valid){[self log:@"error-hook:skip"];return NO;}
    record=[NNErrorHook new];record.original=method_getImplementation(method);record.objectCode=objectCode;record.owner=self;
    IMP replacement=imp_implementationWithBlock(^(id listener,uintptr_t code,id message){
        NNHost *owner=record.owner;
        if(!owner||![owner needsRouting]){((void(*)(id,SEL,uintptr_t,id))record.original)(listener,selector,code,message);return;}
        NNHeld *entry=[NNHeld new];entry.kind=TIONoNetworkErrorEvent;entry.listener=listener;entry.code=code;entry.message=message;entry.error=record.original;
        if(record.objectCode)entry.objectCode=(__bridge id)(void *)code;
        [owner submit:TIONoNetworkErrorEvent listener:listener tool:NO work:^{if(![owner routeError:entry])((void(*)(id,SEL,uintptr_t,id))entry.error)(entry.listener,selector,entry.objectCode?(uintptr_t)(__bridge void *)entry.objectCode:entry.code,entry.message);}];
    });record.replacement=replacement;
    objc_setAssociatedObject(_voice,&association,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Add a class-local override for an inherited method; never mutate its superclass.
    if(!class_addMethod(_voice,selector,replacement,method_getTypeEncoding(method)))method_setImplementation(method,replacement);
    [self log:@"error-hook:on"];return YES;
}
- (BOOL)hold:(NNHeld *)entry {
    if(_held.count==8){[self cancel:@"takeover-refused"];return NO;}
    [_held addObject:entry];[self log:@"hold"];return YES;
}
- (BOOL)routeError:(NNHeld *)entry {
    [self refresh];
    if(entry.listener!=_core.listener)return NO;
    if(_core.phase==TIONoNetworkArmed)return [self hold:entry];
    if(_core.phase==TIONoNetworkOwned||_core.phase==TIONoNetworkTail){[self log:@"swallow-error"];return YES;}return NO;
}
- (id)beginAsr:(id)listener text:(NSString *)text final:(BOOL)final sid:(NSString *)sid duplicate:(BOOL)duplicate generation:(NSUInteger)generation {
    [self refresh];TIONoNetworkSnapshot *s=self.snapshot;
    if(!_installed||_failedOpen||![self mode:s]||!s.verified||!s.hooksReady||!s.voiceExitReady)return nil;
    NNIngress *token=[NNIngress new];token.listener=listener;token.text=[text copy];token.sid=[sid copy];token.final=final;token.duplicate=duplicate;token.before=generation;_ingress=token;[self publish];
    if(final&&!duplicate&&text.length&&_core.phase!=TIONoNetworkIdle)[self cancel:@"cancel:speech"];
    return token;
}
- (void)willAsr:(NSString *)text {
    if(_ingress.duplicate)return;
    if(text.length){[_stopGate cancel];if(_core.phase!=TIONoNetworkIdle&&![_core.text isEqual:text])[self cancel:@"cancel:speech"];}
}
- (void)accepted:(NNIngress *)token listener:(id)listener text:(NSString *)text final:(BOOL)final sid:(NSString *)sid {
    if(!final)return;
    TIONoNetworkSnapshot *s=self.snapshot;
    if(_failedOpen){[self log:@"skip:overflow"];return;}
    if(![self mode:s]){[self log:@"skip:mode"];return;}
    if(!s.verified){[self log:@"skip:unverified"];return;}
    if(!s.hooksReady||!s.voiceExitReady){[self log:@"skip:hooks"];return;}
    if(!token||token!=_ingress||token.duplicate||[_core hasSeenSid:sid text:text]){[self log:@"skip:dup"];return;}
    if(token.veto){[self log:@"skip:ingress"];return;}
    if(s.voiceExited||s.listener!=listener||s.generation==token.before||![s.sid isEqual:sid]||![s.asr isEqual:text])return;
    if(s.ownsTurn){[self log:@"skip:owned"];return;}
    if(!TIONoNetworkQuestion(text).length){[self log:@"skip:empty"];return;}
    if(![self ensureErrorHook])return;
    [_core rememberSid:sid text:text];[_core arm:listener sid:sid text:text generation:s.generation];[self log:@"arm"];[self publish];
    NSUInteger epoch=_core.epoch;[self after:TIONoNetworkDelay(_known,_satisfied,s.timeout) work:^{[self fire:epoch];}];
}
- (void)fire:(NSUInteger)epoch {
    if(_core.epoch!=epoch||_core.phase!=TIONoNetworkArmed)return;[self refresh];
    if(_core.epoch!=epoch||_core.phase!=TIONoNetworkArmed)return;
    TIONoNetworkSnapshot *s=self.snapshot;
    if(_failedOpen||![s.sid isEqual:_core.sid]||![s.asr isEqual:_core.text]){[self cancel:@"takeover-refused"];return;}
    [self log:@"fire"];
    [self transaction:^{
        id wrapper=nil;
        @try{Class cls=self.lookup(@"RayNeoNlpResultWrapper");if(cls)wrapper=[cls new];
            if(wrapper){NSDictionary *fields=@{@"domain":@"chat",@"intent":@"chat",@"sub":@"workflow",@"sessionId":self.core.sid?:@"",@"offline":@NO,@"finished":@NO,@"answer":@"",@"spoken":@""};
                for(NSString *key in fields)[wrapper setValue:fields[key] forKey:key];
                for(NSString *key in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"command",@"hasNextRound",@"rawData"])[wrapper valueForKey:key];
            }
        }@catch(NSException *e){wrapper=nil;}
        if(!wrapper){[self cancel:@"wrapper-missing"];return;}
        [self.core beginTakeover];[self protect:s];
        BOOL acquired=NO;@try{if(self.takeover)acquired=self.takeover(wrapper,TIONoNetworkQuestion(self.core.text),self.core.listener);}@catch(NSException *e){[self log:@"takeover-refused"];}
        TIONoNetworkSnapshot *after=self.snapshot;
        acquired=acquired||(after.generation==s.generation&&after.listener==s.listener&&after.ownsTurn);
        if(acquired){[self.held removeAllObjects];[self.core acquire];self.stopToken=[self.stopGate beginTurn];[self log:@"takeover-ok"];[self refresh];[self poll:self.core.epoch began:self.now];}
        else {self.protecting=NO;self.protectListener=nil;[self cancel:@"takeover-refused"];}
        [self publish];
    }];
}
- (BOOL)nlp:(id)listener value:(id)value {
    [self refresh];if(listener!=_core.listener)return NO;
    if(_core.phase==TIONoNetworkArmed){
        BOOL command=NNGet(value,@"command")!=nil,offline=[NNGet(value,@"offline") boolValue];
        BOOL eligible=TIOIsEligibleChat(NNString(NNGet(value,@"domain")),NNString(NNGet(value,@"intent")),NNString(NNGet(value,@"sub")),offline,command);
        if(eligible||command||!offline){[self cancel:eligible?@"cancel:nlp-eligible":command?@"cancel:nlp-command":@"cancel:nlp-online"];return NO;}
        NNHeld *e=[NNHeld new];e.kind=TIONoNetworkNlpEvent;e.listener=listener;e.value=value;return [self hold:e];
    }
    if(_core.phase==TIONoNetworkOwned||_core.phase==TIONoNetworkTail){NSString *sid=NNString(NNGet(value,@"sessionId"));if(!sid.length||[sid isEqual:_core.sid]){[self log:@"drop-nlp"];return YES;}}
    return NO;
}
- (BOOL)completion:(id)listener {
    [self refresh];if(listener!=_core.listener)return NO;
    if(_core.phase==TIONoNetworkArmed){NNHeld *e=[NNHeld new];e.kind=TIONoNetworkCompleteEvent;e.listener=listener;return [self hold:e];}
    return _core.phase==TIONoNetworkOwned||_core.phase==TIONoNetworkTail;
}
- (void)foreground {
    if(!self.snapshot.forceForeground)return;
    for(NSString *name in @[@"RayNeoAppStateAdapterImpl",@"rayneo_venus_sdk_plugin.RayNeoAppStateAdapterImpl"]){
        Class cls=_lookup(name);SEL selector=NSSelectorFromString(@"isAppInForeground");Method m=class_getInstanceMethod(cls,selector);
        if(!m||method_getNumberOfArguments(m)!=2)continue;char *r=method_copyReturnType(m);BOOL valid=r&&(r[0]=='B'||r[0]=='c');free(r);if(!valid)continue;
        IMP original=method_getImplementation(m);if(!original)continue;
        IMP replacement=imp_implementationWithBlock(^BOOL(id object){return YES;});
        if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(m)))method_setImplementation(m,replacement);
        [self log:@"fg:on"];return;
    }[self log:@"fg:fail"];
}
- (void)install:(Class)voice takeover:(TIONoNetworkTakeover)takeover replay:(TIONoNetworkReplayNlp)replay complete:(TIONoNetworkReplayComplete)complete state:(TIONoNetworkReadState)state stop:(dispatch_block_t)stop {
    if(_installed)return;_installed=YES;_voice=voice;_takeover=[takeover copy];_replay=[replay copy];_complete=[complete copy];_readState=[state copy];_stopHost=[stop copy];
    [self foreground];
    if(!_testing){_monitor=nw_path_monitor_create();nw_path_monitor_set_queue(_monitor,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        __weak NNHost *weak=self;nw_path_monitor_set_update_handler(_monitor,^(nw_path_t path){BOOL satisfied=nw_path_get_status(path)==nw_path_status_satisfied;dispatch_async(dispatch_get_main_queue(),^{NNHost *host=weak;if(!host)return;host.known=YES;host.satisfied=satisfied;[host log:satisfied?@"net:sat":@"net:unsat"];});});nw_path_monitor_start(_monitor);
    }
}
@end

static NNHost *NNShared(void){static NNHost *host;static dispatch_once_t once;dispatch_once(&once,^{host=[NNHost new];});return host;}
void TIONoNetworkInstall(Class voice,TIONoNetworkTakeover takeover,TIONoNetworkReplayNlp replay,TIONoNetworkReplayComplete complete,TIONoNetworkReadState state,dispatch_block_t stopHost){[NNShared() install:voice takeover:takeover replay:replay complete:complete state:state stop:stopHost];}
void TIONoNetworkSubmit(TIONoNetworkEvent kind,id listener,BOOL toolDispatch,dispatch_block_t work){[NNShared() submit:kind listener:listener tool:toolDispatch work:work];}
id TIONoNetworkBeginAsr(id listener,NSString *text,BOOL final,NSString *sid,BOOL duplicate,NSUInteger generation){return [NNShared() beginAsr:listener text:text final:final sid:sid duplicate:duplicate generation:generation];}
void TIONoNetworkWillAsr(NSString *text){[NNShared() willAsr:text];}
void TIONoNetworkDidAcceptAsr(id token,id listener,NSString *text,BOOL final,NSString *sid){[NNShared() accepted:token listener:listener text:text final:final sid:sid];}
void TIONoNetworkEndAsr(id token){NNHost *h=NNShared();if(h.ingress==token)h.ingress=nil;[h refresh];[h publish];}
void TIONoNetworkAudioStart(void){[NNShared() cancel:@"cancel:audio"];}
BOOL TIONoNetworkNlp(id listener,id value){return [NNShared() nlp:listener value:value];}
BOOL TIONoNetworkComplete(id listener){return [NNShared() completion:listener];}
NSArray<NSDictionary *> *TIONoNetworkTimeline(void){return [NNShared().core timeline];}
BOOL TIONoNetworkFailedOpen(void){return NNShared().failedOpen;}
void TIONoNetworkSetScheduler(TIONoNetworkScheduler scheduler){NNShared().scheduler=[scheduler copy];}
void TIONoNetworkSetClock(NSTimeInterval (^clock)(void)){NNShared().clock=[clock copy];}
#if TIO_NO_NETWORK_TESTING
void TIONoNetworkTestReset(void){NNHost *h=NNShared();NSCAssert(!h.depth&&!h.spillPending&&!h.events.count,@"reset only between drained fixtures");if(h.monitor)nw_path_monitor_cancel(h.monitor);h.monitor=nil;h.life++;h.installed=NO;h.testing=YES;h.known=NO;h.satisfied=NO;h.pumpScheduled=NO;h.spill=NO;h.failedOpen=NO;h.overflowPending=NO;h.protecting=NO;h.protectionScheduled=NO;h.ingress=nil;h.scheduler=nil;h.readState=nil;h.takeover=nil;h.replay=nil;h.complete=nil;h.stopHost=nil;h.spillPending=0;[h resetFields];}
void TIONoNetworkTestNetwork(BOOL known,BOOL satisfied){NNShared().known=known;NNShared().satisfied=satisfied;}
void TIONoNetworkTestClassLookup(Class (^lookup)(NSString *)){NNShared().lookup=[lookup copy];}
NSDictionary *TIONoNetworkTestStatus(void){NNHost *h=NNShared();return @{@"phase":@(h.core.phase),@"epoch":@(h.core.epoch),@"held":@(h.held.count),@"fifo":@(h.events.count),@"spill":@(h.spillPending),@"protected":@(h.protecting),@"protectionScheduled":@(h.protectionScheduled),@"failedOpen":@(h.failedOpen)};}
#endif
