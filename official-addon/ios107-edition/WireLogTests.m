#import "WireLog.h"
#include <assert.h>

// Stand-ins for the Flutter classes the recorder recognises by name.
@interface FlutterStandardTypedData : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic) NSUInteger type;
@end
@implementation FlutterStandardTypedData
@end
@interface FlutterError : NSObject
@property (nonatomic, copy) NSString *code, *message;
@property (nonatomic, strong) id details;
@end
@implementation FlutterError
@end
@interface FakeCall : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, strong) id arguments;
@end
@implementation FakeCall
@end
@interface Poison : NSObject
@end
@implementation Poison
- (NSString *)description { @throw [NSException exceptionWithName:@"Poison" reason:@"description" userInfo:nil]; }
@end

// ---- a tiny StandardMessageCodec encoder, independent of the decoder under test ----
static void PutSize(NSMutableData *d, NSUInteger n) {
    if (n < 254) { uint8_t b = (uint8_t)n; [d appendBytes:&b length:1]; }
    else if (n <= 0xffff) { uint8_t b = 254; uint16_t v = (uint16_t)n; [d appendBytes:&b length:1]; [d appendBytes:&v length:2]; }
    else { uint8_t b = 255; uint32_t v = (uint32_t)n; [d appendBytes:&b length:1]; [d appendBytes:&v length:4]; }
}
static void PutByte(NSMutableData *d, uint8_t b) { [d appendBytes:&b length:1]; }
static void PutValue(NSMutableData *d, id v);
static void PutAlign(NSMutableData *d, NSUInteger a) { while (d.length % a) PutByte(d, 0); }
static void PutValue(NSMutableData *d, id v) {
    if (v == NSNull.null) PutByte(d, 0);
    else if ([v isKindOfClass:NSString.class]) { NSData *u = [(NSString *)v dataUsingEncoding:NSUTF8StringEncoding]; PutByte(d, 6); PutSize(d, u.length); [d appendData:u]; }
    else if ([v isKindOfClass:NSData.class]) { PutByte(d, 7); PutSize(d, [(NSData *)v length]); [d appendData:v]; }
    else if ([v isKindOfClass:NSArray.class]) { PutByte(d, 11); PutSize(d, [(NSArray *)v count]); for (id e in v) PutValue(d, e); }
    else if ([v isKindOfClass:NSDictionary.class]) { PutByte(d, 12); PutSize(d, [(NSDictionary *)v count]); for (id k in [[v allKeys] sortedArrayUsingSelector:@selector(compare:)]) { PutValue(d, k); PutValue(d, v[k]); } }
    else if ([v isKindOfClass:NSNumber.class]) {
        const char *t = [v objCType];
        if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) PutByte(d, [v boolValue] ? 1 : 2);
        else if (t[0] == 'd') { PutByte(d, 5); PutAlign(d, 8); double x = [v doubleValue]; [d appendBytes:&x length:8]; }
        else if (t[0] == 'q') { PutByte(d, 4); int64_t x = [v longLongValue]; [d appendBytes:&x length:8]; }
        else { PutByte(d, 3); int32_t x = [v intValue]; [d appendBytes:&x length:4]; }
    }
}
static NSData *MethodCall(NSString *m, id args) { NSMutableData *d = [NSMutableData new]; PutValue(d, m); PutValue(d, args); return d; }
static NSData *Envelope(id value) { NSMutableData *d = [NSMutableData new]; PutByte(d, 0); PutValue(d, value); return d; }

static NSURL *TempDir(void) {
    NSURL *u = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wirelog-test-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    return u;
}
static NSArray<NSDictionary *> *ReadAll(NSURL *dir, NSMutableArray<NSNumber *> *sizes) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *n in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSData *d = [NSData dataWithContentsOfFile:[dir.path stringByAppendingPathComponent:n]];
        [sizes addObject:@(d.length)];
        for (NSString *line in [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"]) {
            if (!line.length) continue;
            id j = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            assert([j isKindOfClass:NSDictionary.class]); // every line is a JSON object
            [out addObject:j];
        }
    }
    return out;
}
static NSArray<NSDictionary *> *Records(NSURL *dir) {
    NSMutableArray *r = [NSMutableArray new];
    for (NSDictionary *d in ReadAll(dir, [NSMutableArray new])) if (!d[@"type"]) [r addObject:d];
    return r;
}
static void Fresh(NSURL *dir, unsigned long long rotate, unsigned long long cap) { TIOWireLogConfigure(dir, rotate, cap); }

static void TestRedactionMore(void);
static void TestRedaction(void) {
    for (NSString *k in @[@"token", @"accessToken", @"access_token", @"refresh-token", @"Authorization", @"password", @"apiKey", @"API_KEY", @"APIKey",
                          @"cookie", @"Cookies", @"signature", @"ticket", @"credential", @"secret", @"clientSecret", @"authToken", @"jwt",
                          @"appkey", @"authcode", @"authCode", @"appKey", @"sessionKey", @"secret_key", @"pushkey", @"clientkey", @"sessionToken", @"oauthcode"])
        assert(TIOWireLogKeyIsSensitive(k));
    // False hits that must stay readable: glasses business fields.
    for (NSString *k in @[@"businessId", @"customId", @"keyboard", @"monkey", @"design", @"signal", @"assign", @"author", @"tokenizer",
                          @"eventType", @"deviceId", @"payload", @"message", @"taskId", @"fileName", @"cmd", @"data", @"value", @"mode", @"turkey", @"ticketing",
                          @"key", @"keys", @"session", @"sign", @"keyCode", @"keyName", @"sessionId", @"hotkey", @"hockey"])
        assert(!TIOWireLogKeyIsSensitive(k));
    assert(!TIOWireLogKeyIsSensitive(@"") && !TIOWireLogKeyIsSensitive(nil));

    NSDictionary *j = TIOWireLogJSON(@{@"businessId": @22, @"token": @"abcdef", @"nested": @{@"password": @"hunter2", @"customId": @7, @"list": @[@{@"Authorization": @"Bearer abc"}]},
                                       @"note": @"curl -H 'Authorization: Bearer abcdefghijklmnop' x", @"jwt": @"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2ln",
                                       @"text": @"here eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl inside", @"plain": @"hello world, nothing secret"});
    assert([j[@"businessId"] isEqual:@22]);
    assert([j[@"token"] isEqualToString:@"<redacted len=6>"]);
    assert([j[@"nested"][@"password"] isEqualToString:@"<redacted len=7>"]);
    assert([j[@"nested"][@"customId"] isEqual:@7]);
    assert([j[@"nested"][@"list"][0][@"Authorization"] isEqualToString:@"<redacted len=10>"]);
    assert([j[@"note"] hasPrefix:@"curl -H 'Authorization: <redacted len="]); // bearer value replaced inside free text
    assert([j[@"note"] rangeOfString:@"abcdefghijklmnop"].location == NSNotFound);
    assert([j[@"jwt"] hasPrefix:@"<redacted"]);
    assert([j[@"text"] rangeOfString:@"eyJhbGci"].location == NSNotFound && [j[@"text"] hasPrefix:@"here <redacted len="] && [j[@"text"] hasSuffix:@"> inside"]);
    assert([j[@"plain"] isEqualToString:@"hello world, nothing secret"]);
    // A bare word that merely starts like a bearer header stays readable.
    assert([TIOWireLogJSON(@"Bearer of good news, long text") hasPrefix:@"Bearer of"]);
    // Redacting a value that is not a string still reports a length.
    assert([TIOWireLogJSON(@{@"secret": @[@1, @2, @3]})[@"secret"] isEqualToString:@"<redacted len=3>"]);
    assert([TIOWireLogJSON(@{@"apiKey": [NSData dataWithBytes:"abcd" length:4]})[@"apiKey"] isEqualToString:@"<redacted len=4>"]);
    TestRedactionMore();
}


static void TestRedactionMore(void) {
    // Bare "key" / "session" / "sign" are credentials only when the value looks like one.
    NSDictionary *soft = TIOWireLogJSON(@{@"key": @"brightness", @"session": @"short", @"sign": @"x", @"keyCode": @4, @"sessionId": @"0123456789abcdef0123456789abcdef"});
    assert([soft[@"key"] isEqualToString:@"brightness"] && [soft[@"session"] isEqualToString:@"short"] && [soft[@"sign"] isEqualToString:@"x"]);
    assert([soft[@"keyCode"] isEqual:@4] && [soft[@"sessionId"] isEqualToString:@"0123456789abcdef0123456789abcdef"]);
    assert([TIOWireLogJSON(@{@"key": @"0123456789abcdef0123"})[@"key"] isEqualToString:@"<redacted len=20>"]);
    assert([TIOWireLogJSON(@{@"session": @"0123456789abcdef0123456789abcdef"})[@"session"] isEqualToString:@"<redacted len=32>"]);
    assert([TIOWireLogJSON(@{@"key": @"has spaces in it, long enough to count"})[@"key"] hasPrefix:@"has spaces"]);

    // JSON carried inside a string value.
    NSString *inner = @"{\"accessToken\":\"abcdef123456\",\"businessId\":22,\"nested\":\"{\\\"password\\\":\\\"hunter2hunter2\\\"}\"}";
    NSDictionary *j = TIOWireLogJSON(@{@"payload": inner, @"other": @"{\"a\": 1, \"b\" : 2}"});
    assert([j[@"payload"] rangeOfString:@"abcdef123456"].location == NSNotFound && [j[@"payload"] rangeOfString:@"hunter2"].location == NSNotFound);
    NSDictionary *back = [NSJSONSerialization JSONObjectWithData:[j[@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    assert([back[@"accessToken"] isEqualToString:@"<redacted len=12>"] && [back[@"businessId"] isEqual:@22]);
    assert([j[@"other"] isEqualToString:@"{\"a\": 1, \"b\" : 2}"]);               // JSON with nothing to hide is left byte-for-byte
    // Fragments that are not valid JSON, query strings, headers.
    NSString *cut = [TIOWireLogJSON(@"{\"token\":\"abcdefghijkl\", \"x\":") description];
    assert([cut rangeOfString:@"abcdefghijkl"].location == NSNotFound);
    NSString *url = TIOWireLogJSON(@"https://h.example/x?access_token=abc123def456&foo=1&appKey=zzzzzzzz");
    assert([url rangeOfString:@"abc123def456"].location == NSNotFound && [url rangeOfString:@"zzzzzzzz"].location == NSNotFound && [url containsString:@"foo=1"]);
    NSString *hdr = TIOWireLogJSON(@"Authorization: Bearer abcdefghijklmnop and more text");
    assert([hdr rangeOfString:@"abcdefghijklmnop"].location == NSNotFound && [hdr containsString:@"and more text"]);
    assert([TIOWireLogJSON(@"the token count is high, nothing to hide here")  isEqualToString:@"the token count is high, nothing to hide here"]);
}

static void TestJSON(void) {
    FlutterStandardTypedData *typed = [FlutterStandardTypedData new]; typed.data = [NSData dataWithBytes:"\x01\x02\xff" length:3]; typed.type = 0;
    FlutterError *err = [FlutterError new]; err.code = @"E1"; err.message = @"boom"; err.details = @{@"a": @1};
    id nested = @{@"b": @YES, @"n": NSNull.null, @"f": @2.5, @"i": @-3, @"nan": @(NAN), @"d": [NSData dataWithBytes:"\x00\x10\xab" length:3], @"t": typed,
                  @"e": err, @"sentinel": [NSObject new], @"arr": @[@1, @[@"x", @{@"y": NSNull.null}]], @1: @"numeric key", @"date": [NSDate dateWithTimeIntervalSince1970:5]};
    NSDictionary *j = TIOWireLogJSON(nested);
    assert([NSJSONSerialization isValidJSONObject:j]);
    assert([NSJSONSerialization dataWithJSONObject:j options:0 error:nil].length > 0);
    assert([j[@"b"] isEqual:@YES] && j[@"n"] == NSNull.null && [j[@"f"] isEqual:@2.5] && [j[@"i"] isEqual:@-3]);
    assert([j[@"nan"] isKindOfClass:NSString.class]);
    assert([j[@"d"][@"$hex"] isEqualToString:@"0010ab"] && [j[@"d"][@"len"] isEqual:@3]);
    assert([j[@"t"][@"$hex"] isEqualToString:@"0102ff"] && [j[@"t"][@"kind"] isEqualToString:@"typed:uint8"]);
    assert([j[@"e"][@"$error"][@"code"] isEqualToString:@"E1"] && [j[@"e"][@"$error"][@"details"][@"a"] isEqual:@1]);
    assert([j[@"sentinel"][@"$"] hasPrefix:@"sentinel"]);
    assert(j[@"arr"][1][1][@"y"] == NSNull.null);
    assert([j[@"1"] isEqualToString:@"numeric key"]);
    assert([j[@"date"][@"$date"] isEqual:@5]);
    // Big blobs are length-capped with the real length kept.
    NSMutableData *big = [NSMutableData dataWithLength:70000];
    NSDictionary *b = TIOWireLogJSON(big);
    assert([b[@"len"] isEqual:@70000] && [b[@"truncated"] boolValue] && [b[@"$hex"] length] == 131072);
    // Depth is bounded.
    id deep = @"leaf"; for (int i = 0; i < 40; i++) deep = @[deep];
    assert([NSJSONSerialization dataWithJSONObject:TIOWireLogJSON(deep) options:0 error:nil].length < 400);
}

static void TestDecoder(void) {
    NSDictionary *args = @{@"businessId": @22, @"token": @"s3cret", @"list": @[@YES, NSNull.null, @2.5, @"é"], @"blob": [NSData dataWithBytes:"\x01\x02" length:2], @"big": @(1LL << 40)};
    NSDictionary *call = TIOWireLogDecodeMessage(MethodCall(@"rayneonet_sendMessage", args), NO);
    assert([call[@"codec"] isEqualToString:@"methodCall"] && [call[@"method"] isEqualToString:@"rayneonet_sendMessage"]);
    assert([call[@"arguments"][@"businessId"] isEqual:@22] && [call[@"arguments"][@"token"] isEqualToString:@"<redacted len=6>"]);
    assert([call[@"arguments"][@"list"][2] isEqual:@2.5] && [call[@"arguments"][@"list"][3] isEqualToString:@"é"]);
    assert([call[@"arguments"][@"blob"][@"$hex"] isEqualToString:@"0102"] && [call[@"arguments"][@"big"] isEqual:@(1LL << 40)]);

    NSDictionary *ev = TIOWireLogDecodeMessage(Envelope(@{@"eventType": @"messageReceived", @"message": @{@"businessId": @20, @"payload": [NSData dataWithBytes:"\xde\xad" length:2]}}), YES);
    assert([ev[@"codec"] isEqualToString:@"envelope"] && [ev[@"value"][@"message"][@"payload"][@"$hex"] isEqualToString:@"dead"]);

    NSMutableData *errEnv = [NSMutableData new]; PutByte(errEnv, 1); PutValue(errEnv, @"code"); PutValue(errEnv, @"msg"); PutValue(errEnv, NSNull.null);
    assert([TIOWireLogDecodeMessage(errEnv, YES)[@"codec"] isEqualToString:@"errorEnvelope"]);

    // A plain message, a long (>253) string, and a list of 300 ints use the extended size encodings.
    assert([TIOWireLogDecodeMessage(MethodCall(@"x", @[]), NO)[@"arguments"] isEqual:@[]]);
    NSString *longS = [@"" stringByPaddingToLength:300 withString:@"ab" startingAtIndex:0];
    NSMutableData *msg = [NSMutableData new]; PutValue(msg, longS);
    NSDictionary *m = TIOWireLogDecodeMessage(msg, NO);
    assert([m[@"codec"] isEqualToString:@"message"] && [m[@"value"] isEqualToString:longS]);
    NSMutableArray *ints = [NSMutableArray new]; for (int i = 0; i < 300; i++) [ints addObject:@(i)];
    NSMutableData *list = [NSMutableData new]; PutValue(list, ints);
    assert([[TIOWireLogDecodeMessage(list, NO)[@"value"] lastObject] isEqual:@299]);

    // Typed lists keep their alignment padding (int32 list after one byte of header).
    NSMutableData *typedList = [NSMutableData new];
    PutByte(typedList, 8); PutSize(typedList, 2); PutAlign(typedList, 4); int32_t a = 7, b = -9; [typedList appendBytes:&a length:4]; [typedList appendBytes:&b length:4];
    BOOL ok = NO; id v = TIOWireLogDecodeStandard(typedList, &ok);
    assert(ok && [v[@"values"] isEqual:(@[@7, @-9])] && [v[@"$typed"] isEqualToString:@"int32"]);

    // Custom (pigeon) types, truncation, trailing garbage, and a size that points past the end all fall back to raw hex.
    NSData *pigeon = [NSData dataWithBytes:"\x80\x01\x02" length:3];
    NSDictionary *raw = TIOWireLogDecodeMessage(pigeon, NO);
    assert([raw[@"codec"] isEqualToString:@"raw"] && [raw[@"data"][@"$hex"] isEqualToString:@"800102"] && [raw[@"len"] isEqual:@3]);
    NSData *whole = MethodCall(@"m", @{@"a": @"hello"});
    assert([TIOWireLogDecodeMessage([whole subdataWithRange:NSMakeRange(0, whole.length - 2)], NO)[@"codec"] isEqualToString:@"raw"]);
    NSMutableData *trailing = [whole mutableCopy]; PutByte(trailing, 0);
    assert([TIOWireLogDecodeMessage(trailing, NO)[@"codec"] isEqualToString:@"raw"]);
    assert([TIOWireLogDecodeMessage([NSData dataWithBytes:"\x06\xfd" length:2], NO)[@"codec"] isEqualToString:@"raw"]);
    assert([TIOWireLogDecodeMessage([NSData data], NO)[@"codec"] isEqualToString:@"empty"]);
    // Every prefix of a valid buffer must be handled without crashing (the sanitizers watch this).
    for (NSUInteger n = 0; n < whole.length; n++) (void)TIOWireLogDecodeMessage([whole subdataWithRange:NSMakeRange(0, n)], NO);
}

static void TestChannelPolicy(void) {
    assert(TIOWireLogClassifyChannel(@"com.rayneo/sdk") == TIOWireLogChannelFull);
    assert(TIOWireLogClassifyChannel(@"com.rayneo/sdk/rayneonet") == TIOWireLogChannelFull);
    assert(TIOWireLogClassifyChannel(@"rayneo_venus_sdk_plugin/asr") == TIOWireLogChannelFull);
    assert(TIOWireLogClassifyChannel(@"voice_assistant_events") == TIOWireLogChannelFull);
    assert(TIOWireLogClassifyChannel(@"flutter/platform") == TIOWireLogChannelIgnored);
    assert(TIOWireLogClassifyChannel(@"") == TIOWireLogChannelIgnored && TIOWireLogClassifyChannel(nil) == TIOWireLogChannelIgnored);
    assert(TIOWireLogClassifyChannel(@"rayneo/account/login") == TIOWireLogChannelOpaque);
    assert(TIOWireLogClassifyChannel(@"rayneo_http_client") == TIOWireLogChannelOpaque);
    assert(TIOWireLogClassifyChannel(@"com.rayneo.venus/push") == TIOWireLogChannelOpaque);
    assert(TIOWireLogClassifyChannel(@"com.rayneo.venus/push/msg") == TIOWireLogChannelOpaque);
    assert(TIOWireLogClassifyChannel(@"rayneo_native_plugin/analytics_delivery") == TIOWireLogChannelOpaque);
    assert(TIOWireLogMethodIsSizeOnly(@"refreshToken") && TIOWireLogMethodIsSizeOnly(@"login") && TIOWireLogMethodIsSizeOnly(@"getAuthInfo") && TIOWireLogMethodIsSizeOnly(@"LOGIN_BY_CODE"));
    assert(!TIOWireLogMethodIsSizeOnly(@"rayneonet_sendMessage") && !TIOWireLogMethodIsSizeOnly(@"startAsr") && !TIOWireLogMethodIsSizeOnly(nil));
}

static void TestWriter(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 4000, 16000);
    assert(!TIOWireLogActive());
    assert(TIOWireLogStart() && TIOWireLogActive());
    for (int i = 0; i < 400; i++) TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"eventType": @"messageReceived", @"i": @(i), @"pad": @"xxxxxxxxxxxxxxxxxxxxxxxx"}));
    TIOWireLogStop();
    assert(!TIOWireLogActive());
    TIOWireLogDrainForTest();
    NSMutableArray *sizes = [NSMutableArray new];
    NSArray *all = ReadAll(dir, sizes);
    unsigned long long total = 0;
    for (NSNumber *s in sizes) { total += s.unsignedLongLongValue; assert(s.unsignedLongLongValue <= 4000); }   // rotation keeps every file within its limit
    assert(sizes.count > 1);
    assert(total <= 16000);                                                                                     // the cap holds for the whole directory
    assert(sizes.count <= 4);
    NSArray *recs = Records(dir);
    assert(recs.count > 20 && recs.count < 400);                                                                // the oldest files were dropped
    assert([recs.lastObject[@"i"] isEqual:@399] == NO); // i lives inside value, not at top level
    assert([recs.lastObject[@"value"][@"i"] isEqual:@399]);                                                    // the newest survive
    assert([recs.lastObject[@"eventType"] isEqualToString:@"messageReceived"]);
    NSNumber *prev = @0;
    for (NSDictionary *r in recs) { assert([r[@"seq"] longLongValue] > prev.longLongValue); prev = r[@"seq"]; }
    assert([all.firstObject[@"type"] isEqualToString:@"header"]);                                              // every file starts with a header
    assert([all.lastObject[@"type"] isEqualToString:@"footer"]);
    for (NSDictionary *r in recs) {
        assert([r[@"dir"] isEqualToString:@"n2d.message"] && [r[@"channel"] isEqualToString:@"com.rayneo/sdk/rayneonet"]);
        assert([r[@"codec"] isEqualToString:@"envelope"] && [r[@"thread"] length] && [r[@"mono"] doubleValue] > 0);
        assert([r[@"wall"] hasSuffix:@"Z"] && [r[@"wall"] length] == 24);
    }
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil]) assert([n hasPrefix:@"wirelog-"] && [n hasSuffix:@".jsonl"]);
    NSDictionary *st = TIOWireLogStatus();
    assert(![st[@"active"] boolValue] && [st[@"records"] unsignedLongLongValue] == 400 && [st[@"files"] unsignedIntegerValue] == sizes.count);

    // A record bigger than the rotation size still gets written, alone, instead of looping on rotation.
    Fresh(dir = TempDir(), 1000, 100000);
    TIOWireLogStart();
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"blob": [NSMutableData dataWithLength:2000]}));
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"small": @1}));
    TIOWireLogStop(); TIOWireLogDrainForTest();
    assert(Records(dir).count == 2);

    // Ignored and opaque channels.
    Fresh(dir = TempDir(), 0, 0);
    TIOWireLogStart();
    TIOWireLogNativeToDart(@"flutter/platform", MethodCall(@"x", @{}));
    TIOWireLogNativeToDart(@"rayneo/account/login", MethodCall(@"signIn", @{@"user": @"a", @"password": @"b"}));
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", [NSData dataWithBytes:"\x80\x01\x02" length:3]);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(r.count == 2);
    assert([r[0][@"opaque"] boolValue] && [r[0][@"bytes"] isEqual:@(MethodCall(@"signIn", @{@"user": @"a", @"password": @"b"}).length)] && !r[0][@"arguments"] && !r[0][@"data"]);
    assert([r[1][@"codec"] isEqualToString:@"raw"] && [r[1][@"data"][@"$hex"] isEqualToString:@"800102"]);

    // Off means off: nothing is written while stopped, and a stopped recorder writes no file at all.
    Fresh(dir = TempDir(), 0, 0);
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"a": @1}));
    TIOWireLogDrainForTest();
    assert(![NSFileManager.defaultManager fileExistsAtPath:dir.path]);
}

static void TestPassivity(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    FakeCall *call = [FakeCall new]; call.method = @"rayneonet_sendMessage"; call.arguments = @{@"businessId": @22, @"payload": [NSData dataWithBytes:"\x01" length:1], @"token": @"zzz"};
    __block int hits = 0; __block id seen = nil;
    id result = ^(id value) { hits++; seen = value; };

    // Inactive: the very same block comes back, so nothing can have changed.
    assert(TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, result) == result);
    assert(TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, nil) == nil);

    TIOWireLogStart();
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, result);
    assert(wrapped != result && hits == 0);                    // recording the call must not run the result
    NSDictionary *value = @{@"success": @YES, @"data": [NSData dataWithBytes:"\xaa" length:1]};
    ((void (^)(id))wrapped)(value);
    assert(hits == 1 && seen == value);                        // exactly once, with the original object
    ((void (^)(id))wrapped)(@"again");
    assert(hits == 2 && [seen isEqual:@"again"]);              // later calls are forwarded too, never swallowed
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *recs = Records(dir);
    assert(recs.count == 2);                                   // one call, one result (the repeat is not recorded twice)
    assert([recs[0][@"dir"] isEqualToString:@"d2n.call"] && [recs[0][@"method"] isEqualToString:@"rayneonet_sendMessage"]);
    assert([recs[0][@"arguments"][@"token"] isEqualToString:@"<redacted len=3>"] && [recs[0][@"arguments"][@"payload"][@"$hex"] isEqualToString:@"01"]);
    assert([recs[1][@"dir"] isEqualToString:@"d2n.result"] && [recs[1][@"callSeq"] isEqual:recs[0][@"seq"]] && [recs[1][@"latencyMs"] doubleValue] >= 0);
    assert([recs[1][@"value"][@"data"][@"$hex"] isEqualToString:@"aa"] && [recs[1][@"value"][@"success"] boolValue]);

    // An exception inside the observer (injected fault) does not reach the caller; the recorder switches itself off.
    Fresh(dir = TempDir(), 0, 0);
    hits = 0; TIOWireLogStart();
    TIOWireLogInjectFaultForTest();
    id out = nil;
    @try { out = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, result); } @catch (__unused id e) { assert(!"observer exception reached the caller"); }
    assert(out == result);                                     // the caller still holds its own, unwrapped block
    ((void (^)(id))out)(@1);
    assert(hits == 1 && !TIOWireLogActive() && [TIOWireLogStatus()[@"disabledReason"] length] > 0);
    TIOWireLogDrainForTest();

    // Same for an argument whose description throws: the calling thread only takes a structural snapshot, so the
    // failure shows up on the writer queue. The caller is never touched and the recorder switches itself off.
    Fresh(dir = TempDir(), 0, 0);
    hits = 0; TIOWireLogStart();
    call.arguments = @{@"x": [Poison new]};
    @try { out = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, result); } @catch (__unused id e) { assert(!"observer exception reached the caller"); }
    ((void (^)(id))out)(@2);
    assert(hits == 1);
    TIOWireLogDrainForTest();
    assert(!TIOWireLogActive() && [TIOWireLogStatus()[@"disabledReason"] length] > 0);
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"a": @1})); // inactive: a no-op, not a crash
    TIOWireLogDrainForTest();

    // Generic handler wrapper: same handler call count, same message object, same reply object and value.
    Fresh(dir = TempDir(), 0, 0);
    TIOWireLogStart();
    NSData *message = MethodCall(@"startAsr", @{@"lang": @"en"});
    NSData *response = Envelope(@{@"ok": @YES});
    __block int handlerCalls = 0, replyCalls = 0; __block NSData *gotMessage = nil, *gotReply = nil;
    void (^handler)(NSData *, void (^)(NSData *)) = ^(NSData *m, void (^reply)(NSData *)) { handlerCalls++; gotMessage = m; reply(response); };
    void (^wrappedHandler)(NSData *, void (^)(NSData *)) = TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/asr", handler);
    assert((id)wrappedHandler != (id)handler);
    wrappedHandler(message, ^(NSData *r) { replyCalls++; gotReply = r; });
    assert(handlerCalls == 1 && replyCalls == 1 && gotMessage == message && gotReply == response);
    assert(TIOWireLogWrapHandler(@"flutter/platform", handler) == (id)handler);               // other channels are not touched at all
    assert([TIOWireLogStatus()[@"wrappedChannels"] containsObject:@"rayneo_venus_sdk_plugin/asr"]);
    // A handler that is also the bridge: the bridge claim suppresses the generic record (no duplicates).
    void (^bridgeHandler)(NSData *, void (^)(NSData *)) = ^(NSData *m, void (^reply)(NSData *)) {
        NSString *ch = TIOWireLogClaimBridgeCall();
        assert([ch isEqualToString:@"com.rayneo/sdk"]);
        id res = TIOWireLogWrapBridgeResult(ch, call, ^(id v) { reply(response); });
        ((void (^)(id))res)(@{@"success": @YES});
    };
    call.arguments = @{@"businessId": @1};
    ((void (^)(NSData *, void (^)(NSData *)))TIOWireLogWrapHandler(@"com.rayneo/sdk", bridgeHandler))(message, ^(NSData *r) {});
    // A handler with no reply, and an opaque channel.
    ((void (^)(NSData *, void (^)(NSData *)))TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/always_on", ^(NSData *m, void (^reply)(NSData *)) { assert(reply == nil); }))(message, nil);
    ((void (^)(NSData *, void (^)(NSData *)))TIOWireLogWrapHandler(@"rayneo/account", ^(NSData *m, void (^reply)(NSData *)) { reply(m); }))(message, ^(NSData *r) {});
    TIOWireLogStop(); TIOWireLogDrainForTest();
    recs = Records(dir);
    NSMutableArray *dirs = [NSMutableArray new]; for (NSDictionary *x in recs) [dirs addObject:[NSString stringWithFormat:@"%@@%@", x[@"dir"], x[@"channel"]]];
    NSArray *want = @[@"d2n.call@rayneo_venus_sdk_plugin/asr", @"d2n.result@rayneo_venus_sdk_plugin/asr",
                      @"d2n.call@com.rayneo/sdk", @"d2n.result@com.rayneo/sdk",
                      @"d2n.call@rayneo_venus_sdk_plugin/always_on", @"d2n.call@rayneo/account", @"d2n.result@rayneo/account"];
    NSArray *sorted = [recs sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"seq"] compare:b[@"seq"]]; }];
    NSMutableArray *got = [NSMutableArray new]; for (NSDictionary *x in sorted) [got addObject:[NSString stringWithFormat:@"%@@%@", x[@"dir"], x[@"channel"]]];
    assert([[got sortedArrayUsingSelector:@selector(compare:)] isEqual:[want sortedArrayUsingSelector:@selector(compare:)]]);
    for (NSDictionary *x in recs) {
        if ([x[@"channel"] isEqual:@"rayneo_venus_sdk_plugin/asr"] && [x[@"dir"] isEqual:@"d2n.call"]) assert([x[@"method"] isEqualToString:@"startAsr"] && [x[@"arguments"][@"lang"] isEqualToString:@"en"]);
        if ([x[@"channel"] isEqual:@"rayneo_venus_sdk_plugin/asr"] && [x[@"dir"] isEqual:@"d2n.result"]) assert([x[@"codec"] isEqualToString:@"envelope"] && [x[@"value"][@"ok"] boolValue]);
        if ([x[@"channel"] isEqual:@"rayneo/account"]) assert(!x[@"data"] && !x[@"arguments"] && [x[@"opaque"] boolValue]);
    }
}


static void TestSizeOnly(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    // Bridge: a token method records its name and nothing else, on the call and on the result.
    FakeCall *call = [FakeCall new]; call.method = @"refreshToken"; call.arguments = @{@"refreshToken": @"zzzzzzzzzzzz", @"uid": @7};
    __block int hits = 0;
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(id v) { hits++; });
    ((void (^)(id))wrapped)(@{@"accessToken": @"aaaaaaaaaaaa", @"expires": @3600});
    assert(hits == 1);
    // Generic handler: the method name is read from the bytes, the arguments and the reply stay out of the log.
    NSData *msg = MethodCall(@"loginWithPassword", @{@"user": @"someone", @"pw": @"hunter2hunter2"});
    NSData *rep = Envelope(@{@"session": @"0123456789abcdef0123456789abcdef"});
    void (^h)(NSData *, void (^)(NSData *)) = TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/user_center", ^(NSData *m, void (^reply)(NSData *)) { reply(rep); });
    h(msg, ^(NSData *r) { hits++; });
    assert(hits == 2);
    // A channel that is size-only as a whole.
    ((void (^)(NSData *, void (^)(NSData *)))TIOWireLogWrapHandler(@"com.rayneo.venus/push", ^(NSData *m, void (^reply)(NSData *)) { reply(rep); }))(MethodCall(@"register", @"bare-device-token-0123456789"), ^(NSData *r) {});
    // Native to Dart: a method call whose name says token.
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", MethodCall(@"onTokenRefreshed", @{@"value": @"tttttttttttt"}));
    TIOWireLogNativeToDart(@"com.rayneo.venus/push", MethodCall(@"onPush", @"bare-device-token-0123456789"));
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSString *all = @"";
    for (NSURL *u in TIOWireLogFiles()) all = [all stringByAppendingString:[NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:nil]];
    for (NSString *secret in @[@"zzzzzzzzzzzz", @"aaaaaaaaaaaa", @"someone", @"hunter2", @"0123456789abcdef", @"bare-device-token", @"tttttttttttt"])
        assert([all rangeOfString:secret].location == NSNotFound);
    NSArray *recs = Records(dir);
    assert(recs.count == 8);
    NSInteger opaque = 0;
    for (NSDictionary *r in recs) { if ([r[@"opaque"] boolValue]) opaque++; assert(!r[@"arguments"] && !r[@"value"] && !r[@"data"]); }
    assert(opaque == 8);
    assert([recs[0][@"method"] isEqualToString:@"refreshToken"] && [recs[1][@"latencyMs"] doubleValue] >= 0);
    NSDictionary *login = nil; for (NSDictionary *r in recs) if ([r[@"method"] isEqual:@"loginWithPassword"] && [r[@"dir"] isEqual:@"d2n.call"]) login = r;
    assert(login && [login[@"bytes"] isEqual:@(msg.length)]);

    // Wrapping is idempotent (the two- and three-argument setters may call each other).
    id once = TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/asr", ^(NSData *m, void (^reply)(NSData *)) {});
    assert(TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/asr", once) == once);
    assert(TIOWireLogWrapHandler(@"rayneo_venus_sdk_plugin/asr", nil) == nil);
}

static void TestNaming(void) {
    // Tiny files and a tight cap force many rotations inside the same millisecond. Names must keep increasing, the
    // cap must delete the oldest file, and the newest record must always survive.
    NSURL *dir = TempDir();
    Fresh(dir, 420, 1300);
    TIOWireLogStart();
    const int n = 300;
    for (int i = 0; i < n; i++) TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"i": @(i), @"pad": @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}));
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray<NSString *> *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
    assert(names.count >= 2);
    long long lastFirstSeq = 0; unsigned long long total = 0;
    for (NSString *name in names) {
        NSData *d = [NSData dataWithContentsOfFile:[dir.path stringByAppendingPathComponent:name]];
        total += d.length;
        NSArray *lines = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
        long long first = 0;
        for (NSString *line in lines) {
            if (!line.length) continue;
            NSDictionary *r = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if (r[@"seq"]) { first = [r[@"seq"] longLongValue]; break; }
        }
        assert(first > lastFirstSeq);   // name order is creation order
        lastFirstSeq = first;
    }
    assert(total <= 1300);
    NSArray *recs = Records(dir);
    assert([recs.lastObject[@"value"][@"i"] isEqual:@(n - 1)]);   // the newest record is in the newest file, never deleted by the cap
    // A second session in the same directory sorts after everything already there.
    NSString *newest = names.lastObject;
    Fresh(dir, 420, 1300);
    TIOWireLogStart();
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"again": @1}));
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *after = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
    assert([after.lastObject compare:newest] == NSOrderedDescending);
}

static void TestBacklogBound(void) {
    // The estimate covers call arguments and results too: a 3 MB argument is counted (about 9 MB) and dropped, not queued.
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    FakeCall *call = [FakeCall new]; call.method = @"rayneonet_sendMessage";
    call.arguments = @{@"blob": [@"" stringByPaddingToLength:3u << 20 withString:@"ab" startingAtIndex:0]};
    __block int hits = 0;
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(id v) { hits++; });
    ((void (^)(id))wrapped)(@1);
    assert(hits == 1);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSDictionary *st = TIOWireLogStatus();
    assert([st[@"dropped"] unsignedLongLongValue] == 1);          // the call record
    assert([st[@"records"] unsignedLongLongValue] == 1);          // the small result record
}

int main(void) {
    @autoreleasepool {
        TestRedaction();
        TestJSON();
        TestDecoder();
        TestChannelPolicy();
        TestWriter();
        TestPassivity();
        TestSizeOnly();
        TestNaming();
        TestBacklogBound();
        puts("WireLogTests: PASS");
    }
    return 0;
}
