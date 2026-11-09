// The stages of the RayneoNet bridge hook (MethodHook in GlassesChannelHook.m) that the host
// tests can run: the off-main sendFile hop, and wire log -> OTA guard -> D5 forward -> blocked
// reply. MethodHook and the guard sweeps (tests/WireLogGuardHarness.h) call these same
// functions, so the sweeps test the hook's own code rather than a copy of it.
// The wire log steps are compiled only with TIO_WIRE_LOG=1; without it nothing here
// refers to the recorder.
#import <Foundation/Foundation.h>
#import "ExperimentalOTAFlash.h"
#if TIO_WIRE_LOG
#import "WireLog.h"
#endif

static NSString *const TIOMethodHookBlockedMessage=@"Turbo IO transfer gate: not authorized or packet mismatch";

static inline id TIOMethodHookRead(id o,NSString *k){@try{return [o valueForKey:k];}@catch(__unused NSException *e){return nil;}}

// An off-main rayneonet_sendFile goes on on the main queue: `again` re-enters the hook there.
// Returns YES when the call was re-dispatched and the caller must return.
static inline BOOL TIOMethodHookHopToMain(id call,dispatch_block_t again){
    if([TIOMethodHookRead(call,@"method") isEqual:@"rayneonet_sendFile"]&&!NSThread.isMainThread){
        dispatch_async(dispatch_get_main_queue(),again);return YES;
    }
    return NO;
}

// Runs after the stock-traffic evidence has read the original result block. In order:
// the wire log wraps the result (passive; a refused call is then recorded with the reply
// below), the OTA guard decides (a guard that throws counts as a refusal), `decided` sees
// that verdict (may be nil), an allowed stock teleprompter send is replaced by a new call
// built from the checked snapshot (D5) and the wire log notes it, and a refused call is
// answered and stops here. Otherwise `allowed` runs the rest of the hook with the call to
// forward and the result block to hand on. Returns YES when the call was refused.
static inline BOOL TIOMethodHookGuardStage(NSString *wireChannel,id call,id result,void(^decided)(BOOL blocked),void(^allowed)(id call,id result)){
#if TIO_WIRE_LOG
    result=TIOWireLogWrapBridgeResult(wireChannel,call,result); // forwards unchanged; records the call, the value and the latency
#else
    (void)wireChannel;
#endif
    NSDictionary *teleprompter=nil;BOOL otaBlocked=YES;
    @try{otaBlocked=TIOOTAFlashBlockCallSnapshot(call,&teleprompter);}@catch(__unused id e){otaBlocked=YES;teleprompter=nil;}
    if(decided)decided(otaBlocked);
    // D5: the plugin reads exactly what the guard checked. Every other call is forwarded unchanged.
    if(!otaBlocked&&teleprompter){id checked=TIOStockTeleprompterForwardCall(teleprompter);if(checked)call=checked;else otaBlocked=YES;}
#if TIO_WIRE_LOG
    if(!otaBlocked&&teleprompter)TIOWireLogBridgeForwarded(result,call); // what the plugin actually receives, linked to the recorded original
#endif
    if(otaBlocked){if(result)((void(^)(id))result)(@{@"success":@NO,@"message":TIOMethodHookBlockedMessage});return YES;}
    allowed(call,result);
    return NO;
}
