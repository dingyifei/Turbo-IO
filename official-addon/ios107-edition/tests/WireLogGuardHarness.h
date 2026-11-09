// Wire log on, guard unchanged. Included by the guard sweeps (Host1011GuardTests.m and
// StockTeleprompterSendTests.m) only when test.py builds them with -DTIO_WIRE_LOG=1.
// Every TIOOTAFlashBlockCall(call) in the including file then runs the MethodHook path
// with the recorder recording: wrap the result, ask the guard (with the D5 snapshot and
// the @try), note a forwarded teleprompter call, and answer a blocked call through the
// wrapper. It returns the guard's own decision, so the sweep digest the file prints must
// equal the digest of the builds without the recorder (test.py compares them).
// At exit it checks that the recorder fired for every call, recorded each blocked call
// with the guard's reply, dropped nothing and never switched itself off.
#import "WireLog.h"
#import "ExperimentalOTAFlash.h"
#include <assert.h>
#include <stdlib.h>
static NSUInteger WireHarnessCalls,WireHarnessBlocked,WireHarnessForwarded,WireHarnessNoForwardClass;
static NSURL *WireHarnessDir;
static NSString *const WireHarnessReply=@"Turbo IO transfer gate: not authorized or packet mismatch";
static NSArray<NSDictionary *> *WireHarnessRecords(void){
    NSMutableArray *out=[NSMutableArray new];
    for(NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:WireHarnessDir.path error:nil]){
        NSString *text=[NSString stringWithContentsOfFile:[WireHarnessDir.path stringByAppendingPathComponent:n] encoding:NSUTF8StringEncoding error:nil];
        for(NSString *line in [text componentsSeparatedByString:@"\n"]){
            if(!line.length)continue;
            NSDictionary *j=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            assert([j isKindOfClass:NSDictionary.class]);if(!j[@"type"])[out addObject:j];
        }
    }
    return out;
}
static void WireHarnessFinish(void){
    if(!WireHarnessDir)return;
    assert(TIOWireLogActive());
    TIOWireLogStop();TIOWireLogDrainForTest();
    NSDictionary *status=TIOWireLogStatus();
    assert([status[@"dropped"] unsignedLongLongValue]==0&&[status[@"disabledReason"] length]==0);
    NSUInteger calls=0,blockedReplies=0,forwarded=0;
    for(NSDictionary *r in WireHarnessRecords()){
        if([r[@"dir"] isEqual:@"d2n.call"])calls++;
        else if([r[@"dir"] isEqual:@"d2n.forwarded"])forwarded++;
        else if([r[@"dir"] isEqual:@"d2n.result"]&&[r[@"value"][@"message"] isEqual:WireHarnessReply]&&[r[@"value"][@"success"] isEqual:@NO])blockedReplies++;
    }
    assert(WireHarnessCalls>0&&calls==WireHarnessCalls);
    assert(WireHarnessBlocked>0&&blockedReplies==WireHarnessBlocked);
    assert(forwarded==WireHarnessForwarded);
    [NSFileManager.defaultManager removeItemAtURL:WireHarnessDir error:nil];
    NSLog(@"wirelog harness: %lu calls recorded, %lu blocked replies recorded, %lu forwarded calls recorded, %lu allowed snapshots without a FlutterMethodCall class",
        (unsigned long)WireHarnessCalls,(unsigned long)WireHarnessBlocked,(unsigned long)WireHarnessForwarded,(unsigned long)WireHarnessNoForwardClass);
}
static BOOL WireHarnessBlockCall(id call){
    if(!WireHarnessDir){
        WireHarnessDir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wirelog-guard-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        TIOWireLogConfigure(WireHarnessDir,0,0);assert(TIOWireLogStart());atexit(WireHarnessFinish);
    }
    __block NSUInteger delivered=0;__block id seen=nil;
    void(^stock)(id)=^(id value){delivered++;seen=value;};
    id result=TIOWireLogWrapBridgeResult(@"com.rayneo/sdk",call,stock);
    assert(result&&result!=(id)stock); // the recorder really wrapped this call
    NSDictionary *teleprompter=nil;BOOL blocked=YES;
    @try{blocked=TIOOTAFlashBlockCallSnapshot(call,&teleprompter);}@catch(__unused id e){blocked=YES;teleprompter=nil;}
    if(!blocked&&teleprompter){
        id checked=TIOStockTeleprompterForwardCall(teleprompter);
        if(checked){TIOWireLogBridgeForwarded(result,checked);WireHarnessForwarded++;}
        else WireHarnessNoForwardClass++; // the hook would refuse here; the sweep records the guard's own decision
    }
    if(blocked){
        NSDictionary *reply=@{@"success":@NO,@"message":WireHarnessReply};
        ((void(^)(id))result)(reply);
        assert(delivered==1&&seen==reply); // forwarded once, the very same object
        WireHarnessBlocked++;
    }else assert(delivered==0);
    // Keep the writer caught up so the backlog bound never drops a record during a long sweep.
    if(++WireHarnessCalls%256==0)TIOWireLogDrainForTest();
    return blocked;
}
// Variadic, so an Objective-C literal with commas still counts as one argument.
#define TIOOTAFlashBlockCall(...) WireHarnessBlockCall((__VA_ARGS__))
