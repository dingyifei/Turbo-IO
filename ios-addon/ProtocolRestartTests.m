#import "ProtocolContext.h"
#import "TodoProtocol.h"
#include <assert.h>
static NSString *Root;
// test.py defines NSHomeDirectory=TIOTestHome for every linked source.
NSString *NSHomeDirectory(void){assert(Root.length);return Root;}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==3);Root=@(argv[2]);NSString *mode=@(argv[1]);
    assert(Root.isAbsolutePath);
    assert([NSHomeDirectory() isEqual:Root]);
    assert([mode isEqual:@"write"]||[mode isEqual:@"read"]);
    // TodoProtocol remains independently covered without a transport plugin.
    NSDictionary *intent=TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":@"  synthetic todo  "}});
    assert([intent[@"title"] isEqual:@"synthetic todo"]);
    assert(!TIOTodoCreateIntent(@"other",@"create_task",@{@"task":@{@"content":@"synthetic todo"}}));
    const uint8_t malformed[]={0x08};
    assert(!TIOTodoEnvelope([NSData dataWithBytes:malformed length:sizeof malformed]));
    if([mode isEqual:@"write"]){
        NSDictionary *sub=@{@"config":@{@"font_size":@2,@"content_width":@100,@"max_lines":@5,@"position":@"center",@"is_display":@YES,@"straight_view":@"original"}};assert(TIOProtocolSaveTemplate(@"subtitle",@"device-test",sub));
        for(NSNumber *n in @[@2,@3]){NSDictionary *p=@{@"did":@"PRIVATE-OLD-ID",@"total":@999,@"checksum":@"deadbeef",@"action":@1,@"scroll":n,@"speed":@120,@"countdown":@3,@"gear":@1,@"depth":@0,@"size":@2,@"width":@80,@"leading":@1};NSString *kind=n.integerValue==2?@"tele-auto":@"tele-manual";assert(TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":p,@"start":p,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));
            for(id bad in @[@"unknown",@100001,NSNull.null]){NSMutableDictionary *broken=[p mutableCopy];broken[@"depth"]=bad;assert(!TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":broken,@"start":p,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));}
            NSMutableDictionary *unknown=[p mutableCopy];unknown[@"unreviewed"]=@1;assert(!TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":p,@"start":unknown,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));
        }
        assert(!TIOProtocolSaveTemplate(@"subtitle",@"device-test",@{@"config":@{@"is_display":@YES,@"apiKey":@"must-not-store"}}));
        assert(!TIOProtocolTemplate(@"subtitle",@"another-device"));
        assert(!TIOProtocolPlugin()&&!TIOProtocolDevice());
        for(NSString *p in [NSFileManager.defaultManager subpathsAtPath:Root]){if(![p hasSuffix:@".json"])continue;NSString *s=[NSString stringWithContentsOfFile:[Root stringByAppendingPathComponent:p] encoding:NSUTF8StringEncoding error:nil];assert(![s containsString:@"PRIVATE-OLD-ID"]&&![s containsString:@"deadbeef"]&&![s containsString:@"must-not-store"]&&![s containsString:@"device-test"]);}
        NSLog(@"PASS: sanitized protocol persistence, no raw device/session/private fields");
    }else{
        // A new process restores only sanitized templates, never live context.
        assert(!TIOProtocolDevice()&&!TIOProtocolPlugin());
        NSDictionary *subtitle=TIOProtocolTemplate(@"subtitle",@"device-test");
        assert([subtitle[@"config"][@"font_size"] isEqual:@2]);
        assert([subtitle[@"config"][@"is_display"] isEqual:@YES]);
        assert(!TIOProtocolTemplate(@"subtitle",@"another-device"));
        for(NSString *kind in @[@"tele-auto",@"tele-manual"]){
            NSDictionary *saved=TIOProtocolTemplate(kind,@"device-test");
            assert([saved[@"prepare"][@"did"] isEqual:@"template"]);
            assert([saved[@"prepare"][@"total"] isEqual:@1]);
            assert([saved[@"prepare"][@"checksum"] isEqual:@"00000000"]);
            assert([saved[@"start"][@"width"] isEqual:@80]);
            assert([saved[@"start"][@"scroll"] isEqual:([kind isEqual:@"tele-auto"]?@2:@3)]);
        }
        NSObject *plugin=[NSObject new];
        TIOProtocolObserveCall(plugin,@"rayneonet_sendMessage",@{@"businessId":@15,@"deviceId":@"device-test"});
        assert(TIOProtocolPlugin()==plugin&&[TIOProtocolDevice() isEqual:@"device-test"]);
        assert([TIOProtocolRoute(22)[@"businessId"] isEqual:@22]);
        TIOProtocolObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"another-device"}});
        assert(!TIOProtocolDevice()&&!TIOProtocolPlugin()&&!TIOProtocolRoute(22));
        NSLog(@"PASS: fresh process restores sanitized templates; live context is absent until observed and invalidated by a foreign device");
    }return 0;
}}
