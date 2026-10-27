#import "NoNetworkTurn.h"
#import <objc/runtime.h>
#include <assert.h>
#include <math.h>
static TIONoNetworkSnapshot *State;
static NSMutableArray<NSDictionary *> *Jobs;
static NSMutableArray *Events;
static NSMutableSet *ControllerSeen;
static double Now;
static NSUInteger Takes,Stops,Completions,Cases;
static id Voice,LastWrapper,ObjectSeen;
static NSString *LastQuestion;
static BOOL Accept,ThrowSet,ThrowGet,ErrorWasMain;
static dispatch_block_t DuringAsr,DuringTake,DuringReplay;
static NSString *CaseName;
#define CHECK(...) do {if(!(__VA_ARGS__)){fprintf(stderr,"FAIL %s:%d %s\n",CaseName.UTF8String,__LINE__,#__VA_ARGS__);abort();}}while(0)
#define CASE(n) do {CaseName=@n;Cases++;}while(0)
@interface RayNeoNlpResultWrapper:NSObject
@property(nonatomic) id sub,dialogId,sessionId,domain,intent,round,query,spoken,answer,finished,offline,command,hasNextRound,rawData;
@end
@implementation RayNeoNlpResultWrapper
- (void)setValue:(id)v forKey:(NSString *)key {if(ThrowSet)[NSException raise:@"fixture" format:@"setter"];[super setValue:v forKey:key];}
- (id)valueForKey:(NSString *)key {if(ThrowGet&&[key isEqual:@"rawData"])[NSException raise:@"fixture" format:@"getter"];return [super valueForKey:key];}
@end
@interface NNVoice:NSObject
- (void)onError:(uintptr_t)code message:(id)message;
@end
@implementation NNVoice
- (void)onError:(uintptr_t)code message:(id)message {ErrorWasMain=NSThread.isMainThread;[Events addObject:[NSString stringWithFormat:@"E:%lu",(unsigned long)code]];}
@end
@interface NNObjectVoice:NSObject
- (void)onError:(id)code message:(id)message;
@end
@implementation NNObjectVoice
- (void)onError:(id)code message:(id)message {ObjectSeen=code;[Events addObject:@"object-error"];}
@end
@interface NNBadVoice:NSObject
- (NSInteger)onError:(uintptr_t)code message:(id)message;
@end
@implementation NNBadVoice
- (NSInteger)onError:(uintptr_t)code message:(id)message{return 0;}
@end
@interface NNForeground:NSObject
- (BOOL)isAppInForeground;
@end
@implementation NNForeground
- (BOOL)isAppInForeground{return NO;}
@end
@interface NNForegroundTwo:NSObject
- (BOOL)isAppInForeground;
@end
@implementation NNForegroundTwo
- (BOOL)isAppInForeground{return NO;}
@end
@interface NNForegroundWrong:NSObject
- (NSInteger)isAppInForeground;
@end
@implementation NNForegroundWrong
- (NSInteger)isAppInForeground{return 0;}
@end
static void Advance(double seconds) {
    double end=Now+seconds;NSUInteger loops=0;
    for(;;){NSDictionary *next=nil;for(NSDictionary *j in Jobs)if([j[@"at"] doubleValue]<=end+0.0000001&&(!next||[j[@"at"] doubleValue]<[next[@"at"] doubleValue]))next=j;
        if(!next)break;CHECK(++loops<10000);[Jobs removeObjectIdenticalTo:next];Now=[next[@"at"] doubleValue];((dispatch_block_t)next[@"work"])();}
    Now=end;
}
static void Setup(NSInteger mode,BOOL fallback,Class cls,BOOL force) {
    if(Jobs)Advance(0);[Jobs removeAllObjects];TIONoNetworkTestReset();Now=0;Takes=0;Stops=0;Completions=0;
    Jobs=[NSMutableArray new];Events=[NSMutableArray new];ControllerSeen=[NSMutableSet new];ObjectSeen=nil;LastWrapper=nil;LastQuestion=nil;
    DuringAsr=nil;DuringTake=nil;DuringReplay=nil;ThrowSet=NO;ThrowGet=NO;Accept=YES;
    State=[TIONoNetworkSnapshot new];State.mode=mode;State.appleFallback=fallback;State.verified=YES;State.hooksReady=YES;State.voiceExitReady=YES;State.forceForeground=force;
    Voice=[cls new];State.listener=Voice;
    TIONoNetworkSetClock(^{return Now;});
    TIONoNetworkSetScheduler(^(double delay,dispatch_block_t work){[Jobs addObject:@{@"at":@(Now+delay),@"work":[work copy]}];});
    TIONoNetworkTestClassLookup(^Class(NSString *name){if([name isEqual:@"RayNeoAppStateAdapterImpl"])return NNForeground.class;return NSClassFromString(name);});
    TIONoNetworkInstall(cls, ^BOOL(id wrapper,NSString *q,id l){
        Takes++;LastWrapper=wrapper;LastQuestion=q;if(Accept){State.ownsTurn=YES;State.asr=q;}if(DuringTake)DuringTake();return Accept;
    },^(id l,id v){[Events addObject:[@"N:" stringByAppendingString:[v answer]?:@""]];if(DuringReplay)DuringReplay();},^(id l){[Events addObject:@"C"];},^{return State;},^{Stops++;});
    TIONoNetworkTestNetwork(YES,NO);
}
static void ArmAt(id listener,NSString *text,NSString *sid) {
    TIONoNetworkSubmit(TIONoNetworkAsrEvent,listener,NO,^{
        NSString *key=[NSString stringWithFormat:@"%@|%@",sid,text];BOOL dup=[ControllerSeen containsObject:key];
        id token=TIONoNetworkBeginAsr(listener,text,YES,sid,dup,State.generation);
        @try{TIONoNetworkWillAsr(text);[Events addObject:@"A"];if(DuringAsr)DuringAsr();
            if(State.mode&&text.length&&!dup){if(ControllerSeen.count>=256)[ControllerSeen removeAllObjects];[ControllerSeen addObject:key];State.generation++;State.listener=listener;State.sid=sid;State.asr=text;State.ownsTurn=NO;State.responseDone=NO;}
            TIONoNetworkDidAcceptAsr(token,listener,text,YES,sid);
        }@finally{TIONoNetworkEndAsr(token);}
    });
}
static void Arm(NSString *text,NSString *sid){ArmAt(Voice,text,sid);}
static RayNeoNlpResultWrapper *Reply(NSString *sid,BOOL offline,BOOL command) {
    RayNeoNlpResultWrapper *v=[RayNeoNlpResultWrapper new];v.sessionId=sid;v.domain=@"chat";v.intent=@"chat";v.sub=@"workflow";v.offline=@(offline);v.command=command?@{}:nil;v.answer=@"n";return v;
}
static void NlpAt(id listener,id value,BOOL tool) {
    TIONoNetworkSubmit(TIONoNetworkNlpEvent,listener,tool,^{if(tool){[Events addObject:@"tool"];return;}if(!TIONoNetworkNlp(listener,value))[Events addObject:[@"N:" stringByAppendingString:[value answer]?:@""]];});
}
static void CompleteAt(id listener){TIONoNetworkSubmit(TIONoNetworkCompleteEvent,listener,NO,^{Completions++;if(!TIONoNetworkComplete(listener))[Events addObject:@"C"];});}
static void Audio(void){TIONoNetworkSubmit(TIONoNetworkAudioEvent,Voice,NO,^{TIONoNetworkAudioStart();[Events addObject:@"audio"];});}
static void Error(void){[(NNVoice *)Voice onError:17 message:@"SENSITIVE_ERROR_938"];}
static void EmitKind(NSString *kind){if([kind isEqual:@"N"]){NlpAt(Voice,Reply(State.sid,YES,NO),NO);}else if([kind isEqual:@"E"])Error();else CompleteAt(Voice);}

int main(void){@autoreleasepool{
    CASE("pure normalization and delay");
    NSArray *normal=@[@[@"WHAT IS THE CAPITAL OF FRANCE",@"What is the capital of france"],@[@"I'M GOING HOME. WHAT TIME IS IT",@"I'm going home. What time is it"],@[@"I'LL GO! I'VE SAID I'D GO",@"I'll go! I've said I'd go"],@[@" Hello ",@"Hello"],@[@"你好",@"你好"],@[@"用 SWIFT 写",@"用 SWIFT 写"],@[@"A",@"A"],@[@"\u3400 ABC",@"\u3400 ABC"],@[@"\uf900 ABC",@"\uf900 ABC"]];
    for(NSArray *pair in normal)CHECK([TIONoNetworkQuestion(pair[0]) isEqual:pair[1]]);
    CHECK(TIONoNetworkDelay(YES,NO,@20)==0.7);CHECK(TIONoNetworkDelay(NO,NO,nil)==6);CHECK(TIONoNetworkDelay(YES,YES,@1)==3);CHECK(TIONoNetworkDelay(YES,YES,@20)==15);CHECK(TIONoNetworkDelay(YES,YES,@(NAN))==6);
    CHECK(!TIONoNetworkModeEligible(0,YES));CHECK(!TIONoNetworkModeEligible(2,NO));CHECK(TIONoNetworkModeEligible(2,YES));CHECK(TIONoNetworkModeEligible(3,NO));
    TIONoNetworkState *pure=[TIONoNetworkState new];id owner=[NSObject new];[pure arm:owner sid:@"s" text:@"q" generation:7];NSUInteger epoch=pure.epoch;[pure beginTakeover];[pure acquire];[pure finishAt:10];[pure finishAt:20];CHECK(pure.tailUntil==13);[pure clear];CHECK(pure.epoch>epoch);
    for(NSUInteger i=0;i<257;i++)[pure rememberSid:[@(i) description] text:@"q"];
    CHECK(![pure hasSeenSid:@"0" text:@"q"]);CHECK([pure hasSeenSid:@"256" text:@"q"]);
    for(NSUInteger i=0;i<100;i++)[pure record:@"arm" at:1.234 sid:@"SENSITIVE_QUESTION_938"];
    [pure record:@"SENSITIVE_ANSWER_938" at:1 sid:@"s"];CHECK(pure.timeline.count==64);
    for(NSDictionary *row in pure.timeline){CHECK(row.count==3);CHECK([row[@"sid"] length]==4);CHECK([row[@"t"] doubleValue]==1.23);}
    NSString *ring=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:pure.timeline options:0 error:NULL] encoding:NSUTF8StringEncoding];CHECK(![ring containsString:@"SENSITIVE"]);

    CASE("ineligible-only paths preserve error IMP");
    IMP before=class_getMethodImplementation(NNVoice.class,@selector(onError:message:));
    for(NSArray *m in @[@[@0,@YES],@[@2,@NO]]){Setup([m[0] integerValue],[m[1] boolValue],NNVoice.class,NO);Arm(@"HELLO THERE",@"s");CHECK(!TIONoNetworkNlp(Voice,Reply(@"s",NO,NO)));Error();Advance(16);CHECK(Takes==0);CHECK(class_getMethodImplementation(NNVoice.class,@selector(onError:message:))==before);CHECK([Events containsObject:@"E:17"]);}
    CHECK(![[NNForeground new] isAppInForeground]);

    CASE("no-network wrapper and grace");Setup(3,YES,NNVoice.class,NO);Arm(@"WHAT IS THE CAPITAL OF FRANCE",@"one");Advance(0.69);CHECK(Takes==0);Advance(0.01);CHECK(Takes==1);CHECK([LastQuestion isEqual:@"What is the capital of france"]);
    CHECK([[LastWrapper domain] isEqual:@"chat"]&&[[LastWrapper intent] isEqual:@"chat"]&&[[LastWrapper sub] isEqual:@"workflow"]);CHECK([[LastWrapper sessionId] isEqual:@"one"]);CHECK(![[LastWrapper offline] boolValue]&&![[LastWrapper finished] boolValue]);CHECK([[LastWrapper answer] isEqual:@""]&&[[LastWrapper spoken] isEqual:@""]);CHECK(![LastWrapper command]&&![LastWrapper rawData]&&![LastWrapper dialogId]&&![LastWrapper round]&&![LastWrapper query]);

    CASE("late NLP errors completions and fixed tail");[Events removeAllObjects];
    CHECK(TIONoNetworkNlp(Voice,Reply(@"one",NO,NO)));CHECK(TIONoNetworkNlp(Voice,Reply(@"one",YES,NO)));CHECK(TIONoNetworkNlp(Voice,Reply(@"",NO,NO)));CHECK(!TIONoNetworkNlp([NNVoice new],Reply(@"one",NO,NO)));CHECK(!TIONoNetworkNlp(Voice,Reply(@"other",NO,NO)));
    Error();CompleteAt(Voice);Advance(0);CHECK(Events.count==0);State.responseDone=YES;CHECK(TIONoNetworkComplete(Voice));Advance(2.9);Error();CompleteAt(Voice);Advance(0);CHECK(Events.count==0);Advance(0.2);CHECK(!TIONoNetworkComplete(Voice));CHECK(!TIONoNetworkNlp(Voice,Reply(@"one",YES,NO)));Error();CHECK([Events containsObject:@"E:17"]);
    ErrorWasMain=YES;dispatch_semaphore_t sem=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{Error();dispatch_semaphore_signal(sem);});CHECK(dispatch_semaphore_wait(sem,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);CHECK(!ErrorWasMain);

    CASE("early eligible and command cancel");for(NSNumber *cmd in @[@NO,@YES]){Setup(3,YES,NNVoice.class,NO);Arm(@"HELLO THERE",@"s");Advance(.3);NlpAt(Voice,Reply(@"s",!cmd.boolValue?NO:YES,cmd.boolValue),NO);Advance(1);CHECK(Takes==0);CHECK([Events containsObject:@"N:n"]);}

    CASE("all held subsets orders and outcomes");
    NSArray *orders=@[@[@"N",@"E",@"C"],@[@"N",@"C",@"E"],@[@"E",@"N",@"C"],@[@"E",@"C",@"N"],@[@"C",@"N",@"E"],@[@"C",@"E",@"N"]];
    for(NSUInteger mask=1;mask<8;mask++)for(NSArray *order in orders)for(NSUInteger outcome=0;outcome<3;outcome++){
        Setup(3,YES,NNVoice.class,NO);Accept=outcome!=1;Arm(@"HELLO THERE",@"s");[Events removeAllObjects];NSMutableArray *expected=[NSMutableArray new];
        for(NSString *kind in order){NSUInteger bit=[kind isEqual:@"N"]?1:[kind isEqual:@"E"]?2:4;if(!(mask&bit))continue;EmitKind(kind);[expected addObject:[kind isEqual:@"N"]?@"N:n":[kind isEqual:@"E"]?@"E:17":@"C"];}
        CHECK(Events.count==0);if(outcome==2){Audio();[expected addObject:@"audio"];}else Advance(.7);
        CHECK([Events isEqual:outcome==0?@[]:expected]);CHECK(Takes==(outcome==2?0:1));CHECK(Completions==((mask&4)?1:0));CHECK([TIONoNetworkTestStatus()[@"held"] integerValue]==0);
    }

    CASE("held queue overflow replays eight then ninth");Setup(3,YES,NNVoice.class,NO);Arm(@"HELLO THERE",@"s");[Events removeAllObjects];for(NSUInteger i=0;i<9;i++)NlpAt(Voice,Reply(@"s",YES,NO),NO);CHECK(Events.count==9);Advance(1);CHECK(Takes==0);

    CASE("audio new final stale timer and duplicate metadata");Setup(3,YES,NNVoice.class,NO);Arm(@"FIRST QUESTION",@"a");dispatch_block_t stale=[Jobs.firstObject[@"work"] copy];Audio();Arm(@"SECOND QUESTION",@"b");stale();Advance(.7);CHECK(Takes==1&&[LastQuestion isEqual:@"Second question"]);
    for(NSNumber *owned in @[@NO,@YES]){Setup(3,YES,NNVoice.class,NO);Arm(@"FIRST QUESTION",@"a");Arm(@"SECOND QUESTION",@"b");if(owned.boolValue)Advance(.7);else NlpAt(Voice,Reply(@"b",YES,NO),NO);NSUInteger epoch2=[TIONoNetworkTestStatus()[@"epoch"] unsignedIntegerValue];NSUInteger held=[TIONoNetworkTestStatus()[@"held"] unsignedIntegerValue];[Events removeAllObjects];Arm(@"FIRST QUESTION",@"a");Advance(0);CHECK([TIONoNetworkTestStatus()[@"epoch"] unsignedIntegerValue]==epoch2);CHECK([TIONoNetworkTestStatus()[@"held"] unsignedIntegerValue]==held);CHECK(![Events containsObject:@"N:n"]);}
    Setup(2,NO,NNVoice.class,NO);Arm(@"OLD QUESTION",@"a");State.appleFallback=YES;Arm(@"NEW QUESTION",@"b");NSUInteger e=[TIONoNetworkTestStatus()[@"epoch"] unsignedIntegerValue];ArmAt([NNVoice new],@"OLD QUESTION",@"a");CHECK([TIONoNetworkTestStatus()[@"epoch"] unsignedIntegerValue]==e);
    Setup(3,YES,NNVoice.class,NO);Arm(@"SAME QUESTION",@"a");NlpAt(Voice,Reply(@"a",YES,NO),NO);[Events removeAllObjects];Arm(@"SAME QUESTION",@"b");CHECK([Events isEqual:@[@"N:n",@"A"]]);Advance(.7);CHECK(Takes==1);

    CASE("delay prefs unknown and network up");for(NSArray *pair in @[@[[NSNull null],@6],@[@1,@3],@[@20,@15]]){Setup(3,YES,NNVoice.class,NO);TIONoNetworkTestNetwork(NO,NO);State.timeout=pair[0]==NSNull.null?nil:pair[0];Arm(@"HELLO THERE",@"s");Advance([pair[1] doubleValue]-.01);CHECK(Takes==0);Advance(.01);CHECK(Takes==1);}
    Setup(3,YES,NNVoice.class,NO);TIONoNetworkTestNetwork(YES,YES);Arm(@"HELLO THERE",@"s");Advance(5.99);CHECK(!Takes);Advance(.01);CHECK(Takes==1);

    CASE("unverified hooks exits empty and unsupported error ABI");for(NSUInteger branch=0;branch<5;branch++){Setup(3,YES,branch==4?NNBadVoice.class:NNVoice.class,NO);if(branch==0)State.verified=NO;if(branch==1)State.hooksReady=NO;if(branch==2)State.voiceExited=YES;Arm(branch==3?@"   ":@"HELLO THERE",@"s");Advance(16);CHECK(Takes==0);CHECK(State.verified==(branch!=0));}

    CASE("wrapper absence setter getter and takeover refusal replay");for(NSUInteger branch=0;branch<4;branch++){Setup(3,YES,NNVoice.class,NO);Arm(@"HELLO THERE",@"s");NlpAt(Voice,Reply(@"s",YES,NO),NO);CompleteAt(Voice);[Events removeAllObjects];if(branch==0)TIONoNetworkTestClassLookup(^Class(NSString *name){return Nil;});if(branch==1)ThrowSet=YES;if(branch==2)ThrowGet=YES;if(branch==3)Accept=NO;Advance(.7);CHECK([Events isEqual:@[@"N:n",@"C"]]);CHECK(Takes==(branch==3?1:0));ThrowSet=NO;ThrowGet=NO;}

    CASE("object error arguments retained through hold");Setup(3,YES,NNObjectVoice.class,NO);Accept=NO;Arm(@"HELLO THERE",@"s");__weak id weakCode;
    @autoreleasepool{id code=[NSObject new];weakCode=code;[(NNObjectVoice *)Voice onError:code message:@"message"];}
    CHECK(weakCode!=nil);Advance(.7);CHECK(ObjectSeen==weakCode&&ObjectSeen!=nil);CHECK([Events containsObject:@"object-error"]);

    CASE("preaccept callbacks veto including reused listener and tool exception");for(NSUInteger reuse=0;reuse<2;reuse++)for(NSUInteger kind=0;kind<4;kind++){
        Setup(3,YES,NNVoice.class,NO);if(!reuse)State.listener=nil;
        DuringAsr=^{if(kind==0)NlpAt(Voice,Reply(@"s",NO,NO),NO);if(kind==1)NlpAt(Voice,Reply(@"s",YES,YES),NO);if(kind==2)CompleteAt(Voice);if(kind==3)Error();};Arm(@"HELLO THERE",@"s");DuringAsr=nil;Advance(7);CHECK(Takes==0);CHECK(Events.count==2);
    }
    Setup(3,YES,NNVoice.class,NO);DuringAsr=^{NlpAt(Voice,Reply(@"s",NO,YES),YES);};Arm(@"HELLO THERE",@"s");DuringAsr=nil;Advance(.7);CHECK(Takes==1&&[Events containsObject:@"tool"]);

    CASE("takeover synchronous emitter cannot mutate next generation");Setup(3,YES,NNVoice.class,NO);DuringTake=^{NSUInteger old=State.generation;DuringTake=nil;Arm(@"SECOND QUESTION",@"b");CHECK(State.generation==old);State.responseDone=YES;};Arm(@"FIRST QUESTION",@"a");Advance(.7);CHECK(Takes==1);CHECK([State.sid isEqual:@"b"]&&!State.responseDone);Advance(.7);CHECK(Takes==2);
    CASE("replay drains before reentrant new ASR");Setup(3,YES,NNVoice.class,NO);Arm(@"FIRST QUESTION",@"a");NlpAt(Voice,Reply(@"a",YES,NO),NO);Error();CompleteAt(Voice);[Events removeAllObjects];DuringReplay=^{DuringReplay=nil;Arm(@"SECOND QUESTION",@"b");};Audio();Advance(0);CHECK([Events isEqual:@[@"N:n",@"E:17",@"C",@"audio",@"A"]]);
    CASE("future asynchronous emitter protected across mode changes");Setup(3,YES,NNVoice.class,NO);Arm(@"FIRST QUESTION",@"a");Advance(.7);NSUInteger old=State.generation;State.mode=0;Arm(@"SECOND QUESTION",@"b");CHECK(State.generation==old);State.responseDone=YES;Advance(0);CHECK(State.generation==old); // official mode does not accept the final
    State.mode=3;Arm(@"THIRD QUESTION",@"c");Advance(0);CHECK(!State.responseDone&&State.generation==old+1);

    CASE("old protection closure cannot clear the new scheduled check");Setup(3,YES,NNVoice.class,NO);Arm(@"FIRST QUESTION",@"a");Advance(.7);dispatch_block_t oldProtection=[Jobs.firstObject[@"work"] copy];Arm(@"SECOND QUESTION",@"b");Advance(0);Advance(.7);CHECK([TIONoNetworkTestStatus()[@"protectionScheduled"] boolValue]);oldProtection();CHECK([TIONoNetworkTestStatus()[@"protectionScheduled"] boolValue]);
    CASE("65 callbacks ordered spill and process fail-open latch");Setup(3,YES,NNVoice.class,NO);NSMutableArray *order=[NSMutableArray new];__block BOOL emitter=NO;
    DuringTake=^{emitter=YES;for(NSUInteger i=1;i<=65;i++)TIONoNetworkSubmit(TIONoNetworkCompleteEvent,Voice,NO,^{CHECK(!emitter);[order addObject:@(i)];if(i==1)TIONoNetworkSubmit(TIONoNetworkAudioEvent,Voice,NO,^{CHECK(!emitter);[order addObject:@66];});});CHECK(order.count==0);emitter=NO;DuringTake=nil;};
    Arm(@"FIRST QUESTION",@"a");Advance(.7);CHECK(order.count==66);for(NSUInteger i=0;i<66;i++)CHECK([order[i] unsignedIntegerValue]==i+1);CHECK(TIONoNetworkFailedOpen());CHECK([TIONoNetworkTestStatus()[@"phase"] integerValue]==TIONoNetworkIdle);CHECK([TIONoNetworkTestStatus()[@"protected"] boolValue]);
    __block BOOL ran=NO;emitter=YES;TIONoNetworkSubmit(TIONoNetworkAsrEvent,Voice,NO,^{CHECK(!emitter);ran=YES;});CHECK(!ran);emitter=NO;State.responseDone=YES;Advance(0);CHECK(ran);Arm(@"NEXT QUESTION",@"b");Advance(16);CHECK(Takes==1);

    CASE("polling bounded without inventing response completion");Setup(3,YES,NNVoice.class,NO);Arm(@"HELLO THERE",@"s");Advance(181);CHECK(!State.responseDone);CHECK([TIONoNetworkTestStatus()[@"phase"] integerValue]==TIONoNetworkOwned);CHECK(Jobs.count==0);Audio();Advance(0);
    CASE("optional stop default off and cancellation");Setup(3,YES,NNVoice.class,NO);DuringTake=^{State.responseDone=YES;};Arm(@"HELLO THERE",@"s");Advance(4);CHECK(Stops==0);
    for(NSNumber *cancel in @[@NO,@YES]){Setup(3,YES,NNVoice.class,NO);State.stopHost=YES;DuringTake=^{State.responseDone=YES;};Arm(@"HELLO THERE",@"s");Advance(.7);if(cancel.boolValue){Audio();Advance(0);}Advance(1.99);CHECK(Stops==0);Advance(.01);CHECK(Stops==(cancel.boolValue?0:1));}
    CASE("optional foreground explicit and signature checked");Setup(3,YES,NNVoice.class,YES);CHECK([[NNForeground new] isAppInForeground]);
    Setup(3,YES,NNVoice.class,NO); // recreate only the test installation to select prefixed fallback
    TIONoNetworkTestReset();State.forceForeground=YES;TIONoNetworkTestClassLookup(^Class(NSString *name){if([name isEqual:@"RayNeoAppStateAdapterImpl"])return NNForegroundWrong.class;if([name hasSuffix:@"RayNeoAppStateAdapterImpl"])return NNForegroundTwo.class;return NSClassFromString(name);});
    TIONoNetworkInstall(NNVoice.class,^BOOL(id w,NSString *q,id l){return NO;},^(id l,id v){},^(id l){},^{return State;},^{});CHECK([[NNForegroundTwo new] isAppInForeground]);CHECK([[NNForegroundWrong new] isAppInForeground]==0);
    printf("PASS no-network-turn: %lu case groups, 126 hold permutations, no device I/O\n",(unsigned long)Cases);
    return 0;
}}
