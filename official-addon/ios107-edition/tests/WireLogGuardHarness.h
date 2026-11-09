// Wire log on, guard unchanged. Included by the guard sweeps (Host1011GuardTests.m and
// StockTeleprompterSendTests.m) only when test.py builds them with -DTIO_WIRE_LOG=1.
// Every TIOOTAFlashBlockCall(call) in the including file then runs the hook's own
// TIOMethodHookGuardStage (MethodHookStages.h: wire log wrap, guard with its @try, D5
// forward, forwarded note, blocked reply) with a stub prior method that answers once.
// It returns the guard's own verdict, so the sweep digest the file prints must equal the
// digest of the builds without the recorder (test.py compares them).
// At exit it checks that the recorder recorded every call and every answer, recorded each
// refused call with the guard's reply, dropped nothing and never switched itself off.
#import "WireLog.h"
#import "MethodHookStages.h"
#include <assert.h>
#include <stdlib.h>
static NSUInteger WireHarnessCalls,WireHarnessBlocked,WireHarnessAllowed,WireHarnessForwarded,WireHarnessNoForwardClass;
static NSURL *WireHarnessDir;
static NSString *const WireHarnessPrior=@"harness prior method";
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
    NSUInteger calls=0,blockedReplies=0,priorReplies=0,forwarded=0;
    for(NSDictionary *r in WireHarnessRecords()){
        if([r[@"dir"] isEqual:@"d2n.call"])calls++;
        else if([r[@"dir"] isEqual:@"d2n.forwarded"])forwarded++;
        else if([r[@"dir"] isEqual:@"d2n.result"]&&[r[@"value"] isEqual:WireHarnessPrior])priorReplies++;
        else if([r[@"dir"] isEqual:@"d2n.result"]&&[r[@"value"] isKindOfClass:NSDictionary.class]&&[r[@"value"][@"message"] isEqual:TIOMethodHookBlockedMessage]&&[r[@"value"][@"success"] isEqual:@NO])blockedReplies++;
    }
    assert(WireHarnessCalls>0&&calls==WireHarnessCalls);
    assert(WireHarnessBlocked>0&&blockedReplies==WireHarnessBlocked);
    assert(priorReplies==WireHarnessAllowed&&WireHarnessBlocked+WireHarnessAllowed==WireHarnessCalls);
    assert(forwarded==WireHarnessForwarded);
    [NSFileManager.defaultManager removeItemAtURL:WireHarnessDir error:nil];
    NSLog(@"wirelog harness: %lu calls recorded, %lu blocked replies recorded, %lu prior-method replies recorded, %lu forwarded calls recorded, %lu allowed snapshots without a FlutterMethodCall class",
        (unsigned long)WireHarnessCalls,(unsigned long)WireHarnessBlocked,(unsigned long)WireHarnessAllowed,(unsigned long)WireHarnessForwarded,(unsigned long)WireHarnessNoForwardClass);
}
static BOOL WireHarnessBlockCall(id call){
    if(!WireHarnessDir){
        WireHarnessDir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wirelog-guard-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        TIOWireLogConfigure(WireHarnessDir,0,0);assert(TIOWireLogStart());atexit(WireHarnessFinish);
    }
    __block NSUInteger delivered=0,priorCalls=0,verdicts=0;__block id seen=nil,forwardedCall=nil;__block BOOL verdict=YES;
    void(^stock)(id)=^(id value){delivered++;seen=value;};
    BOOL refused=TIOMethodHookGuardStage(@"com.rayneo/sdk",call,stock,^(BOOL blocked){verdicts++;verdict=blocked;},^(id forwarded,id reply){
        priorCalls++;forwardedCall=forwarded;((void(^)(id))reply)(WireHarnessPrior); // the stub prior method answers once
    });
    assert(verdicts==1&&delivered==1); // one verdict, one answer reaching the stock block
    if(refused){
        assert(priorCalls==0&&[seen[@"message"] isEqual:TIOMethodHookBlockedMessage]&&[seen[@"success"] isEqual:@NO]);
        WireHarnessBlocked++;
        if(!verdict)WireHarnessNoForwardClass++; // allowed by the guard, refused because no forward call could be built
    }else{
        assert(!verdict&&priorCalls==1&&seen==WireHarnessPrior);
        WireHarnessAllowed++;
        if(forwardedCall!=call)WireHarnessForwarded++;
    }
    BOOL blocked=verdict; // the guard's own verdict, as TIOOTAFlashBlockCall returns it
    // Keep the writer caught up so the backlog bound never drops a record during a long sweep.
    if(++WireHarnessCalls%256==0)TIOWireLogDrainForTest();
    return blocked;
}
// Variadic, so an Objective-C literal with commas still counts as one argument.
#define TIOOTAFlashBlockCall(...) WireHarnessBlockCall((__VA_ARGS__))
