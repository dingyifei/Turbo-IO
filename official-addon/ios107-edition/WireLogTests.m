#import "WireLog.h"
#import "MethodHookStages.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
static NSString *SHA(NSData *d) {
    unsigned char md[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes, (CC_LONG)d.length, md);
    NSMutableString *s = [NSMutableString new]; for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", md[i]];
    return s;
}

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
// The recorder reads a call only through a plain dictionary or this exact class name.
@interface FlutterMethodCall : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, strong) id arguments;
@end
@implementation FlutterMethodCall
@end
@interface Poison : NSObject
@end
@implementation Poison
- (NSString *)description { @throw [NSException exceptionWithName:@"Poison" reason:@"description" userInfo:nil]; }
@end
// Counts every message that reaches it. The recorder must send it none: a proxy or subclass could answer
// differently per read, and the OTA guard reads the same arguments after the recorder.
static NSUInteger ProxyMessages;
@interface CountingProxy : NSProxy
@end
@implementation CountingProxy
+ (instancetype)make { return [CountingProxy alloc]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { ProxyMessages++; return [NSObject instanceMethodSignatureForSelector:@selector(description)]; }
- (void)forwardInvocation:(NSInvocation *)inv { ProxyMessages++; __unsafe_unretained NSString *r = @"proxy"; [inv setReturnValue:&r]; }
@end
// A dictionary key (or set element) that counts every message the recorder could send it.
static NSUInteger KeyMessages;
@interface CountingKey : NSObject <NSCopying>
@end
@implementation CountingKey
- (NSUInteger)hash { KeyMessages++; return 7; }
- (BOOL)isEqual:(id)o { KeyMessages++; return o == self; }
- (id)copyWithZone:(NSZone *)z { KeyMessages++; return self; }
- (NSString *)description { KeyMessages++; return @"key"; }
@end
// A dictionary subclass that counts reads.
static NSUInteger SubclassReads;
@interface CountingDictionary : NSDictionary
@end
@implementation CountingDictionary { NSDictionary *_inner; }
- (instancetype)initWithInner:(NSDictionary *)d { if ((self = [super init])) _inner = d; return self; }
- (NSUInteger)count { SubclassReads++; return _inner.count; }
- (id)objectForKey:(id)k { SubclassReads++; return _inner[k]; }
- (NSEnumerator *)keyEnumerator { SubclassReads++; return _inner.keyEnumerator; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)st objects:(id __unsafe_unretained [])b count:(NSUInteger)n { SubclassReads++; return [_inner countByEnumeratingWithState:st objects:b count:n]; }
@end

// ---- a tiny StandardMessageCodec encoder, independent of the decoder under test; TestDecoder pins its bytes to the spec ----
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
    else if ([v isKindOfClass:NSString.class]) { NSData *u = [(NSString *)v dataUsingEncoding:NSUTF8StringEncoding]; PutByte(d, 7); PutSize(d, u.length); [d appendData:u]; }
    else if ([v isKindOfClass:NSData.class]) { PutByte(d, 8); PutSize(d, [(NSData *)v length]); [d appendData:v]; }
    else if ([v isKindOfClass:NSArray.class]) { PutByte(d, 12); PutSize(d, [(NSArray *)v count]); for (id e in v) PutValue(d, e); }
    else if ([v isKindOfClass:NSDictionary.class]) { PutByte(d, 13); PutSize(d, [(NSDictionary *)v count]); for (id k in [[v allKeys] sortedArrayUsingSelector:@selector(compare:)]) { PutValue(d, k); PutValue(d, v[k]); } }
    else if ([v isKindOfClass:NSNumber.class]) {
        const char *t = [v objCType];
        if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) PutByte(d, [v boolValue] ? 1 : 2);
        else if (t[0] == 'd') { PutByte(d, 6); PutAlign(d, 8); double x = [v doubleValue]; [d appendBytes:&x length:8]; }
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
                          @"eventType", @"payload", @"message", @"taskId", @"fileName", @"cmd", @"data", @"value", @"mode", @"turkey", @"ticketing",
                          @"key", @"keys", @"session", @"sign", @"keyCode", @"keyName", @"sessionId", @"hotkey", @"hockey"])
        assert(!TIOWireLogKeyIsSensitive(k));
    assert(!TIOWireLogKeyIsSensitive(@"") && !TIOWireLogKeyIsSensitive(nil));
    // Device, account and user identifiers, any case or separator.
    for (NSString *k in @[@"deviceId", @"DEVICE_ID", @"device_id", @"peerDeviceId", @"bindDeviceIdList", @"sn", @"SN", @"deviceSn", @"serial", @"serialNumber",
                          @"mac", @"macAddress", @"MAC_ADDRESS", @"uuid", @"UUID", @"deviceUUID", @"accountId", @"account_id", @"userId", @"USERID", @"Token"])
        assert(TIOWireLogKeyIsSensitive(k));
    for (NSString *k in @[@"machine", @"snapshot", @"serialize", @"businessId", @"taskId", @"sessionId", @"streamId"]) assert(!TIOWireLogKeyIsSensitive(k));
    NSDictionary *ids = TIOWireLogJSON(@{@"deviceId": @"AA:BB:CC:DD:EE:FF", @"sn": @"R1234", @"businessId": @9, @"q": @"device_id=ABCDEF12&x=1"});
    assert([ids[@"deviceId"] isEqualToString:@"<redacted len=17>"] && [ids[@"sn"] isEqualToString:@"<redacted len=5>"] && [ids[@"businessId"] isEqual:@9]);
    assert([ids[@"q"] isEqualToString:@"device_id=<redacted len=8>&x=1"]);
    // The owner's user folder and app container UUIDs are masked in every string, short or long, and in keys.
    assert([TIOWireLogScrubIdentifiers(@"user_123") isEqualToString:@"user_<n>"]);
    assert([TIOWireLogScrubIdentifiers(@"/var/mobile/Containers/Data/Application/0A1B2C3D-4E5F-6789-ABCD-EF0123456789/Documents/user_98765/teleprompter/11111111-2222-3333-4444-555555555555")
            isEqualToString:@"/var/mobile/Containers/Data/Application/<uuid>/Documents/user_<n>/teleprompter/11111111-2222-3333-4444-555555555555"]);
    assert([TIOWireLogScrubIdentifiers(@"/private/var/containers/Bundle/Application/0a1b2c3d-4e5f-6789-abcd-ef0123456789/Runner.app") isEqualToString:@"/private/var/containers/Bundle/Application/<uuid>/Runner.app"]);
    assert([TIOWireLogScrubIdentifiers(@"superuser_1 and user_") isEqualToString:@"superuser_1 and user_"]);
    NSDictionary *paths = TIOWireLogJSON(@{@"user_42": @"user_42", @"list": @[@"Documents/user_7/x"]});
    assert([paths[@"user_<n>"] isEqualToString:@"user_<n>"] && [paths[@"list"][0] isEqualToString:@"Documents/user_<n>/x"]);

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
    // Bytes: length, SHA-256 and at most the first 32 bytes as hex.
    NSMutableData *big = [NSMutableData dataWithLength:70000]; ((uint8_t *)big.mutableBytes)[0] = 0xab;
    NSDictionary *b = TIOWireLogJSON(big);
    assert([b[@"len"] isEqual:@70000] && [b[@"truncated"] boolValue] && [b[@"$hex"] length] == 64 && [b[@"$hex"] hasPrefix:@"ab00"]);
    assert([b[@"sha256"] isEqualToString:SHA(big)]);
    NSDictionary *small = TIOWireLogJSON([NSData dataWithBytes:"\x01\x02" length:2]);
    assert([small[@"$hex"] isEqualToString:@"0102"] && !small[@"truncated"] && [small[@"sha256"] isEqualToString:SHA([NSData dataWithBytes:"\x01\x02" length:2])]);
    FlutterStandardTypedData *bigTyped = [FlutterStandardTypedData new]; bigTyped.data = big; bigTyped.type = 0;
    NSDictionary *bt = TIOWireLogJSON(bigTyped);
    assert([bt[@"$hex"] length] == 64 && [bt[@"len"] isEqual:@70000] && [bt[@"kind"] isEqualToString:@"typed:uint8"] && [bt[@"sha256"] isEqualToString:SHA(big)]);
    NSMutableData *rawBig = [NSMutableData dataWithLength:100]; memset(rawBig.mutableBytes, 0x80, 100);
    NSDictionary *rawRec = TIOWireLogDecodeMessage(rawBig, NO);
    assert([rawRec[@"codec"] isEqualToString:@"raw"] && [rawRec[@"data"][@"$hex"] length] == 64 && [rawRec[@"data"][@"len"] isEqual:@100] && [rawRec[@"data"][@"sha256"] isEqualToString:SHA(rawBig)]);
    // Depth is bounded.
    id deep = @"leaf"; for (int i = 0; i < 40; i++) deep = @[deep];
    assert([NSJSONSerialization dataWithJSONObject:TIOWireLogJSON(deep) options:0 error:nil].length < 400);
}

// ---- fixtures written by hand from the StandardMessageCodec spec, independent of both the decoder and PutValue ----
// Type bytes: 0 null, 1 true, 2 false, 3 int32, 4 int64, 5 largeInt, 6 float64 (8-aligned), 7 string, 8 Uint8List,
// 9 Int32List (4-aligned), 10 Int64List (8), 11 Float64List (8), 12 list, 13 map, 14 Float32List (4).
static NSData *Hex(NSString *hex) {
    NSMutableData *d = [NSMutableData new];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) { unsigned x = 0; sscanf([hex substringWithRange:NSMakeRange(i, 2)].UTF8String, "%2x", &x); uint8_t b = (uint8_t)x; [d appendBytes:&b length:1]; }
    return d;
}
static void Lit(NSMutableData *d, const char *bytes, NSUInteger n) { [d appendBytes:bytes length:n]; }
// A rayneonet receive event as captured on the owner's phone (the first 32 bytes below are the capture, verbatim),
// completed with a "message" map: businessId int32 9, deviceId, a container path and a 300-byte Uint8List payload.
static NSData *CapturedEvent(NSData *payload) {
    NSMutableData *d = [Hex(@"000d0207096576656e745479706507126d65737361676553656e645375636365") mutableCopy];
    Lit(d, "ss", 2);                                                              // "messageSendSuccess" (0x12 bytes)
    Lit(d, "\x07\x07" "message" "\x0d\x04", 11);                                  // key "message", map of 4
    Lit(d, "\x07\x0a" "businessId" "\x03\x09\x00\x00\x00", 17);                   // int32 9
    Lit(d, "\x07\x08" "deviceId" "\x07\x11" "AA:BB:CC:DD:EE:FF", 29);
    NSString *path = @"/var/mobile/Containers/Data/Application/0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9/Documents/user_4242/x";
    NSData *utf8 = [path dataUsingEncoding:NSUTF8StringEncoding]; assert(utf8.length < 254);
    Lit(d, "\x07\x04" "note" "\x07", 7); uint8_t n = (uint8_t)utf8.length; [d appendBytes:&n length:1]; [d appendData:utf8];
    assert(payload.length >= 254 && payload.length <= 0xffff);
    Lit(d, "\x07\x07" "payload" "\x08\xfe", 11); uint16_t len = (uint16_t)payload.length; [d appendBytes:&len length:2]; [d appendData:payload];
    return d;
}
static NSData *Bytes300(void);
static NSString *HexOf(NSData *d);
static BOOL IsFull(NSDictionary *b, NSData *d);
static void TestSpecFixtures(void) {
    // Every type byte, with the alignment padding the spec asks for (offsets count from the message start).
    NSData *all = [NSData dataWithBytes:"\x0c\x0f\x00\x01\x02\x03\xfe\xff\xff\xff\x04\x00\x00\x00\x00\x00\x01\x00\x00\x05\x02\x31\x66\x06\x00\x00\x00\x00\x00\x00\x04\x40\x07\x02\xc3\xa9\x08\x02\xde\xad\x09\x02\x00\x00\x07\x00\x00\x00\xf7\xff\xff\xff\x0a\x01\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x0b\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf8\x3f\x0e\x01\x00\x00\x00\x00\x00\x3f\x0d\x01\x07\x01\x6b\x03\x01\x00\x00\x00\x0c\x00" length:100];
    BOOL ok = NO; NSArray *v = TIOWireLogDecodeStandard(all, &ok);
    assert(ok && [v isKindOfClass:NSArray.class] && v.count == 15);
    assert(v[0] == NSNull.null && [v[1] isEqual:@YES] && [v[2] isEqual:@NO] && [v[3] isEqual:@-2] && [v[4] isEqual:@(1LL << 40)]);
    assert([v[5] isEqual:@"1f"] && [v[6] isEqual:@2.5] && [v[7] isEqual:@"é"] && [v[8] isEqual:[NSData dataWithBytes:"\xde\xad" length:2]]);
    assert([v[9][@"$typed"] isEqual:@"int32"] && [v[9][@"values"] isEqual:(@[@7, @-9])]);
    assert([v[10][@"$typed"] isEqual:@"int64"] && [v[10][@"values"] isEqual:@[@5]]);
    assert([v[11][@"$typed"] isEqual:@"float64"] && [v[11][@"values"] isEqual:@[@1.5]]);
    assert([v[12][@"$typed"] isEqual:@"float32"] && [v[12][@"values"] isEqual:@[@0.5]]);
    assert([v[13] isEqual:@{@"k": @1}] && [v[14] isEqual:@[]]);
    // A float64 that needs padding: its type byte sits at offset 2, so five zero bytes precede the value.
    NSData *padded = [NSData dataWithBytes:"\x0c\x01\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf8\x3f" length:16];
    v = TIOWireLogDecodeStandard(padded, &ok); assert(ok && [v isEqual:@[@1.5]]);
    // A method call and an error envelope, by hand.
    NSData *call = [NSData dataWithBytes:"\x07\x15" "rayneonet_sendMessage" "\x0d\x01\x07\x0a" "businessId" "\x03\x16\x00\x00\x00" length:42];
    NSDictionary *c = TIOWireLogDecodeMessage(call, NO);
    assert([c[@"codec"] isEqual:@"methodCall"] && [c[@"method"] isEqual:@"rayneonet_sendMessage"] && [c[@"arguments"][@"businessId"] isEqual:@22]);
    NSDictionary *err = TIOWireLogDecodeMessage([NSData dataWithBytes:"\x01\x07\x01" "E" "\x07\x02" "no" "\x00" length:9], YES);
    assert([err[@"codec"] isEqual:@"errorEnvelope"] && [err[@"code"] isEqual:@"E"] && [err[@"message"] isEqual:@"no"]);
    // The old off-by-one numbering is not the codec: a "string" under byte 6 is a float64 here and fails.
    assert([TIOWireLogDecodeMessage([NSData dataWithBytes:"\x00\x0c\x01\x06\x01k\x03\x01\x00\x00\x00" length:11], YES)[@"codec"] isEqual:@"raw"]);

    // The captured rayneonet receive event decodes as an envelope, on its own and through the recorder.
    NSData *frame = Bytes300(), *event = CapturedEvent(frame);
    assert([HexOf([event subdataWithRange:NSMakeRange(0, 32)]) isEqualToString:@"000d0207096576656e745479706507126d65737361676553656e645375636365"]);
    NSDictionary *e = TIOWireLogDecodeMessage(event, YES);
    assert([e[@"codec"] isEqual:@"envelope"] && [e[@"value"][@"eventType"] isEqual:@"messageSendSuccess"] && [e[@"value"][@"message"][@"businessId"] isEqual:@9]);
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", event);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(r.count == 1 && [r[0][@"codec"] isEqual:@"envelope"] && [r[0][@"eventType"] isEqual:@"messageSendSuccess"]);
    NSDictionary *message = r[0][@"value"][@"message"];
    assert(IsFull(message[@"payload"], frame));                                         // promoted in full, not cut to 32 bytes
    assert([message[@"deviceId"] isEqualToString:@"<redacted len=17>"]);
    assert([message[@"note"] isEqualToString:@"/var/mobile/Containers/Data/Application/<uuid>/Documents/user_<n>/x"]);
    assert([r[0][@"len"] isEqual:@(event.length)]);
}

static void TestDecoder(void) {
    // PutValue writes the spec's bytes (checked against hand-written ones, not against the decoder).
    NSMutableData *pin = [NSMutableData new]; PutValue(pin, @{@"k": @[@1, @"é", [NSData dataWithBytes:"\xff" length:1], NSNull.null, @YES, @(1LL << 40), @0.5]});
    assert([pin isEqualToData:[NSData dataWithBytes:"\x0d\x01\x07\x01\x6b\x0c\x07\x03\x01\x00\x00\x00\x07\x02\xc3\xa9\x08\x01\xff\x00\x01\x04\x00\x00\x00\x00\x00\x01\x00\x00\x06\x00\x00\x00\x00\x00\x00\x00\xe0\x3f" length:40]]);
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
    PutByte(typedList, 9); PutSize(typedList, 2); PutAlign(typedList, 4); int32_t a = 7, b = -9; [typedList appendBytes:&a length:4]; [typedList appendBytes:&b length:4];
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
    assert([TIOWireLogDecodeMessage([NSData dataWithBytes:"\x07\xfd" length:2], NO)[@"codec"] isEqualToString:@"raw"]);
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
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendMessage"; call.arguments = @{@"businessId": @22, @"payload": [NSData dataWithBytes:"\x01" length:1], @"token": @"zzz"};
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

    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"a": @1})); // inactive: a no-op, not a crash
    TIOWireLogDrainForTest();

    // An argument that is not a plain Foundation object (here one whose description throws) is recorded by its
    // class name only and never messaged; the caller is untouched and the recorder stays on.
    Fresh(dir = TempDir(), 0, 0);
    hits = 0; TIOWireLogStart();
    call.arguments = @{@"x": [Poison new]};
    @try { out = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, result); } @catch (__unused id e) { assert(!"observer exception reached the caller"); }
    ((void (^)(id))out)([Poison new]);
    assert(hits == 1);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    recs = Records(dir);
    assert(recs.count == 2 && [TIOWireLogStatus()[@"disabledReason"] length] == 0);
    assert([recs[0][@"arguments"][@"x"][@"$class"] isEqualToString:@"Poison"] && [recs[0][@"arguments"][@"x"][@"$unread"] boolValue]);
    assert([recs[1][@"value"][@"$class"] isEqualToString:@"Poison"]);
    // Reached directly (the JSON helper), a throwing description is kept as the class name, not a thrown exception.
    NSDictionary *poison = TIOWireLogJSON([Poison new]);
    assert([poison[@"$class"] isEqualToString:@"Poison"] && [poison[@"$desc"] isEqualToString:@"<description unavailable>"]);

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
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"refreshToken"; call.arguments = @{@"refreshToken": @"zzzzzzzzzzzz", @"uid": @7};
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
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendMessage";
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

// Arguments and results that are not plain Foundation objects are recorded by class name and never messaged.
static void TestUnreadObjects(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    ProxyMessages = 0; SubclassReads = 0;
    CountingDictionary *sub = [[CountingDictionary alloc] initWithInner:@{@"path": @"/x", @"taskId": @"y"}];
    id proxy = [CountingProxy make];
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendFile";
    call.arguments = @{@"nested": sub, @"proxy": proxy, @"plain": @"ok", @"list": @[proxy, @1]};
    __block int hits = 0;
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(__unused id v) { hits++; });
    ((void (^)(id))wrapped)(proxy);
    // A whole-argument subclass and a call that is neither a dictionary nor FlutterMethodCall are not read either.
    FlutterMethodCall *call2 = [FlutterMethodCall new]; call2.method = @"rayneonet_sendFile"; call2.arguments = sub;
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call2, ^(__unused id v) { hits++; }))(sub);
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", proxy, ^(__unused id v) { hits++; }))(@YES);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    assert(hits == 3 && ProxyMessages == 0 && SubclassReads == 0);
    NSArray *r = Records(dir);
    assert(r.count == 6);
    assert([r[0][@"arguments"][@"plain"] isEqualToString:@"ok"] && [r[0][@"arguments"][@"nested"][@"$class"] isEqualToString:@"CountingDictionary"]);
    assert([r[0][@"arguments"][@"proxy"][@"$class"] isEqualToString:@"CountingProxy"] && [r[0][@"arguments"][@"list"][0][@"$unread"] boolValue]);
    assert([r[1][@"value"][@"$class"] isEqualToString:@"CountingProxy"]);
    assert([r[2][@"arguments"][@"$class"] isEqualToString:@"CountingDictionary"] && [r[3][@"value"][@"$class"] isEqualToString:@"CountingDictionary"]);
    assert([r[4][@"method"] isEqualToString:@"?"] && !r[4][@"arguments"]);
}

// D5 forwards an allowed teleprompter send as a new call built from the checked snapshot. The recorder keeps the
// original d2n.call and adds the call the plugin received as d2n.forwarded with the same callSeq.
static void TestForwarded(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendFile";
    call.arguments = [@{@"path": @"/a", @"taskId": @"t"} mutableCopy];
    __block int hits = 0;
    id stock = ^(__unused id v) { hits++; };
    TIOWireLogBridgeForwarded(stock, call); // inactive: nothing
    TIOWireLogStart();
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, stock);
    FlutterMethodCall *checked = [FlutterMethodCall new]; checked.method = @"rayneonet_sendFile"; checked.arguments = @{@"path": @"/a", @"taskId": @"t", @"name": @"n"};
    TIOWireLogBridgeForwarded(wrapped, checked);
    TIOWireLogBridgeForwarded(stock, checked);   // not a recorder wrapper: ignored
    TIOWireLogBridgeForwarded(nil, checked);
    ((void (^)(id))wrapped)(@{@"success": @YES});
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(hits == 1 && r.count == 3);
    assert([r[0][@"dir"] isEqualToString:@"d2n.call"] && !r[0][@"arguments"][@"name"]);
    assert([r[1][@"dir"] isEqualToString:@"d2n.forwarded"] && [r[1][@"callSeq"] isEqual:r[0][@"seq"]] && [r[1][@"arguments"][@"name"] isEqualToString:@"n"]);
    assert([r[2][@"dir"] isEqualToString:@"d2n.result"] && [r[2][@"callSeq"] isEqual:r[0][@"seq"]]);
}

// 1.0.11 (RayneoNet 1.4.0) builds new send_success / send_error / received shapes and assembles streams. The
// recorder assumes no shape: unknown values, unknown event types and undecodable bytes are kept raw.
@interface RayneoSendResult : NSObject
@end
@implementation RayneoSendResult
@end
static void TestNewerShapes(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendMessage";
    call.arguments = @{@"businessId": @300, @"deviceId": @"fixture-peer", @"payload": [NSData dataWithBytes:"\x01\x02" length:2], @"streamId": @7, @"chunk": @[@0, @3]};
    __block int hits = 0;
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(__unused id v) { hits++; });
    ((void (^)(id))wrapped)(@{@"type": @"send_success", @"result": [RayneoSendResult new], @"lost": @[]});
    ((void (^)(id))wrapped)(@{@"type": @"send_error", @"code": @-3}); // a second answer is forwarded, recorded once
    // Events: a new event type, a pigeon value (custom type 0x80) inside an envelope, a cut envelope, and garbage.
    NSData *received = Envelope(@{@"eventType": @"received", @"message": @{@"businessId": @265, @"seq": @1, @"payload": [NSData dataWithBytes:"\xff" length:1]}});
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet_event", received);
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet_event", [NSData dataWithBytes:"\x00\x0d\x01\x07\x01k\x80\x00" length:8]);
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet_event", [received subdataWithRange:NSMakeRange(0, received.length - 3)]);
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet_event", [NSData dataWithBytes:"\xfe\xfe\xfe" length:3]);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(hits == 2 && r.count == 6 && [TIOWireLogStatus()[@"disabledReason"] length] == 0);
    assert([r[0][@"arguments"][@"businessId"] isEqual:@300] && [r[0][@"arguments"][@"chunk"] isEqual:(@[@0, @3])]);
    assert([r[1][@"value"][@"type"] isEqualToString:@"send_success"] && [r[1][@"value"][@"result"][@"$class"] isEqualToString:@"RayneoSendResult"]);
    assert([r[2][@"eventType"] isEqualToString:@"received"] && [r[2][@"value"][@"message"][@"payload"][@"$hex"] isEqualToString:@"ff"]);
    for (NSUInteger i = 3; i < 6; i++) assert([r[i][@"codec"] isEqualToString:@"raw"] && [r[i][@"data"][@"$hex"] length] > 0);
}

// Snap copies containers element by element and reads keys only after checking their class.
static void TestSnapContainers(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    CountingKey *k1 = [CountingKey new], *k2 = [CountingKey new];
    NSDictionary *byKey = @{k1: @"a", @"plain": @"b", @5: @"five"};
    NSSet *set = [NSSet setWithObjects:k2, @"s", nil];
    NSOrderedSet *ordered = [NSOrderedSet orderedSetWithArray:@[@"o1", @"o2"]];
    NSMutableString *mutableString = [@"before" mutableCopy];
    KeyMessages = 0;
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_x";
    call.arguments = @{@"map": byKey, @"set": set, @"ordered": ordered, @"url": [NSURL URLWithString:@"https://example.invalid/"], @"s": mutableString, @"n": @1, @"date": [NSDate dateWithTimeIntervalSince1970:5]};
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(__unused id v) {}))(nil);
    [mutableString setString:@"after"]; // the snapshot was taken before this
    TIOWireLogStop(); TIOWireLogDrainForTest();
    assert(KeyMessages == 0);
    NSDictionary *a = Records(dir)[0][@"arguments"];
    assert([a[@"map"][@"plain"] isEqualToString:@"b"] && [a[@"map"][@"5"] isEqualToString:@"five"]);
    BOOL keyMarked = NO; for (NSString *k in a[@"map"]) if ([k hasPrefix:@"$key:CountingKey#"]) keyMarked = YES;
    assert(keyMarked && [a[@"map"] count] == 3);
    assert([a[@"set"] isKindOfClass:NSArray.class] && [a[@"set"] count] == 2 && [a[@"set"] containsObject:@"s"]);
    assert([a[@"ordered"] isEqual:(@[@"o1", @"o2"])]);
    assert([a[@"url"][@"$class"] length] > 0 && [a[@"url"][@"$unread"] boolValue]);
    assert([a[@"s"] isEqualToString:@"before"] && [a[@"n"] isEqual:@1] && [a[@"date"][@"$date"] isEqual:@5]);
}

// Privacy: identifiers in d2n.call and d2n.forwarded, bytes as length + SHA-256 + head, folder out of backups.
static void TestPrivacy(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    NSString *path = @"/var/mobile/Containers/Data/Application/0A1B2C3D-4E5F-6789-ABCD-EF0123456789/Documents/user_98765/teleprompter/11111111-2222-3333-4444-555555555555";
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendFile";
    call.arguments = @{@"filePath": path, @"deviceId": @"AA:BB:CC:DD:EE:FF", @"blob": [NSMutableData dataWithLength:40]};
    id wrapped = TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(__unused id v) {});
    FlutterMethodCall *checked = [FlutterMethodCall new]; checked.method = @"rayneonet_sendFile"; checked.arguments = @{@"filePath": path, @"taskId": @"11111111-2222-3333-4444-555555555555"};
    TIOWireLogBridgeForwarded(wrapped, checked);
    ((void (^)(id))wrapped)(@{@"path": path});
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", Envelope(@{@"eventType": @"x", @"file": @"Documents/user_5/a", @"userId": @"12345678"}));
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(r.count == 4);
    NSString *masked = @"/var/mobile/Containers/Data/Application/<uuid>/Documents/user_<n>/teleprompter/11111111-2222-3333-4444-555555555555";
    assert([r[0][@"arguments"][@"filePath"] isEqualToString:masked] && [r[0][@"arguments"][@"deviceId"] isEqualToString:@"<redacted len=17>"]);
    assert([r[0][@"arguments"][@"blob"][@"$hex"] length] == 64 && [r[0][@"arguments"][@"blob"][@"truncated"] boolValue] && [r[0][@"arguments"][@"blob"][@"sha256"] length] == 64);
    assert([r[1][@"dir"] isEqualToString:@"d2n.forwarded"] && [r[1][@"arguments"][@"filePath"] isEqualToString:masked]);
    assert([r[2][@"value"][@"path"] isEqualToString:masked]);
    assert([r[3][@"value"][@"file"] isEqualToString:@"Documents/user_<n>/a"] && [r[3][@"value"][@"userId"] isEqualToString:@"<redacted len=8>"]);
    // Nothing in the files mentions the raw identifiers.
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil]) {
        NSString *text = [NSString stringWithContentsOfFile:[dir.path stringByAppendingPathComponent:n] encoding:NSUTF8StringEncoding error:nil];
        assert([text rangeOfString:@"98765"].location == NSNotFound && [text rangeOfString:@"0A1B2C3D"].location == NSNotFound && [text rangeOfString:@"AA:BB"].location == NSNotFound);
    }
    // The folder is excluded from iCloud and computer backups (a fresh URL, so no cached value is read).
    NSNumber *excluded = nil;
    assert([[NSURL fileURLWithPath:dir.path isDirectory:YES] getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil] && excluded.boolValue);
}

// The hook's off-main sendFile hop (TIOMethodHookHopToMain): a call made on a background queue re-enters on
// main, the stock result block runs once and the recorder records the call and its result once, on main.
static void TestMainThreadHop(void) {
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    __block int stockCalls = 0, entries = 0, hops = 0;
    id stock = ^(__unused id v) { stockCalls++; };
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendFile"; call.arguments = @{@"path": @"/a"};
    __block void (^hook)(id, id);
    hook = ^(id c, id r) { // the first stages of MethodHook, in its order
        entries++;
        NSString *channel = TIOWireLogClaimBridgeCall();
        if (TIOMethodHookHopToMain(c, ^{ hook(c, r); })) { hops++; return; }
        assert(NSThread.isMainThread);
        id wrapped = TIOWireLogWrapBridgeResult(channel, c, r);
        ((void (^)(id))wrapped)(@{@"success": @YES});
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ hook(call, stock); });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (stockCalls == 0 && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    hook = nil;
    // Other methods never hop, even off main.
    FlutterMethodCall *other = [FlutterMethodCall new]; other.method = @"rayneonet_sendMessage";
    __block BOOL otherHopped = YES;
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ otherHopped = TIOMethodHookHopToMain(other, ^{ assert(!"hopped"); }); });
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(stockCalls == 1 && entries == 2 && hops == 1 && !otherHopped);
    assert(r.count == 2 && [r[0][@"dir"] isEqualToString:@"d2n.call"] && [r[1][@"dir"] isEqualToString:@"d2n.result"]);
    assert([r[0][@"thread"] isEqualToString:@"main"] && [r[1][@"callSeq"] isEqual:r[0][@"seq"]]);
}

// Glasses protocol frames are recorded in full; the same bytes anywhere else keep only head + SHA-256 + len.
static NSData *Bytes300(void) { NSMutableData *d = [NSMutableData dataWithLength:300]; for (int i = 0; i < 300; i++) ((uint8_t *)d.mutableBytes)[i] = (uint8_t)(i * 7 + 1); return d; }
static NSString *HexOf(NSData *d) { NSMutableString *s = [NSMutableString new]; const uint8_t *p = d.bytes; for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", p[i]]; return s; }
static BOOL IsFull(NSDictionary *b, NSData *d) { return [b[@"$hex"] isEqualToString:HexOf(d)] && [b[@"len"] isEqual:@(d.length)] && !b[@"truncated"] && [b[@"sha256"] isEqualToString:SHA(d)]; }
static BOOL IsHead(NSDictionary *b, NSData *d) { return [b[@"$hex"] isEqualToString:HexOf([d subdataWithRange:NSMakeRange(0, 32)])] && [b[@"len"] isEqual:@(d.length)] && [b[@"truncated"] boolValue] && [b[@"sha256"] isEqualToString:SHA(d)]; }
static void TestProtocolBytes(void) {
    NSData *frame = Bytes300();
    assert(TIOWireLogIsProtocolCall(@"com.rayneo/sdk", @"rayneonet_sendMessage") && !TIOWireLogIsProtocolCall(@"com.rayneo/sdk", @"rayneonet_sendFile"));
    assert(!TIOWireLogIsProtocolCall(@"com.example/sdk", @"rayneonet_sendMessage") && !TIOWireLogIsProtocolCall(@"rayneo/account/login", @"rayneonet_sendMessage"));
    assert(TIOWireLogIsProtocolEventChannel(@"com.rayneo/sdk/rayneonet") && !TIOWireLogIsProtocolEventChannel(@"rayneo_venus_sdk_plugin/asr"));
    NSURL *dir = TempDir();
    Fresh(dir, 0, 0);
    TIOWireLogStart();
    // 1. A business-9 sendMessage with a 300-byte payload, and its reply with a 300-byte data field: in full.
    FlutterMethodCall *call = [FlutterMethodCall new]; call.method = @"rayneonet_sendMessage";
    call.arguments = @{@"businessId": @9, @"deviceId": @"AA:BB:CC:DD:EE:FF", @"payload": frame};
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", call, ^(__unused id v) {}))(@{@"success": @YES, @"data": frame, @"blob": frame});
    // 2. A Uint8List payload (typed data) on the same call: in full, with its kind.
    FlutterStandardTypedData *typed = [FlutterStandardTypedData new]; typed.data = frame; typed.type = 0;
    FlutterMethodCall *typedCall = [FlutterMethodCall new]; typedCall.method = @"rayneonet_sendMessage"; typedCall.arguments = @{@"businessId": @9, @"payload": typed};
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", typedCall, ^(__unused id v) {}))(nil);
    // 3. The same bytes in another method on the bridge: head + hash.
    FlutterMethodCall *other = [FlutterMethodCall new]; other.method = @"rayneonet_sendFile"; other.arguments = @{@"payload": frame};
    ((void (^)(id))TIOWireLogWrapBridgeResult(@"com.rayneo/sdk", other, ^(__unused id v) {}))(nil);
    // 4. A receive event on the rayneonet channel: the frame in full. The same event on a non-protocol channel: head.
    NSData *event = Envelope(@{@"eventType": @"messageReceived", @"message": @{@"businessId": @9, @"deviceId": @"AA:BB:CC:DD:EE:FF", @"payload": frame, @"note": @"Documents/user_77/x"}});
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", event);
    TIOWireLogNativeToDart(@"rayneo_venus_sdk_plugin/asr", event);
    // 5. An undecodable 300-byte buffer on the rayneonet channel: head + hash.
    NSMutableData *garbage = [frame mutableCopy]; ((uint8_t *)garbage.mutableBytes)[0] = 0xfe;
    TIOWireLogNativeToDart(@"com.rayneo/sdk/rayneonet", garbage);
    TIOWireLogStop(); TIOWireLogDrainForTest();
    NSArray *r = Records(dir);
    assert(r.count == 9);
    assert(IsFull(r[0][@"arguments"][@"payload"], frame) && [r[0][@"arguments"][@"deviceId"] isEqualToString:@"<redacted len=17>"]);
    assert(IsFull(r[1][@"value"][@"data"], frame) && IsHead(r[1][@"value"][@"blob"], frame));
    assert(IsFull(r[2][@"arguments"][@"payload"], frame) && [r[2][@"arguments"][@"payload"][@"kind"] isEqualToString:@"typed:uint8"]);
    assert(IsHead(r[4][@"arguments"][@"payload"], frame));
    assert(IsFull(r[6][@"value"][@"message"][@"payload"], frame) && [r[6][@"value"][@"message"][@"note"] isEqualToString:@"Documents/user_<n>/x"]);
    assert([r[6][@"value"][@"message"][@"deviceId"] isEqualToString:@"<redacted len=17>"]);
    assert(IsHead(r[7][@"value"][@"message"][@"payload"], frame));
    assert([r[8][@"codec"] isEqualToString:@"raw"] && IsHead(r[8][@"data"], garbage));
}

int main(void) {
    @autoreleasepool {
        TestRedaction();
        TestJSON();
        TestSpecFixtures();
        TestDecoder();
        TestChannelPolicy();
        TestWriter();
        TestPassivity();
        TestSizeOnly();
        TestNaming();
        TestBacklogBound();
        TestUnreadObjects();
        TestForwarded();
        TestNewerShapes();
        TestSnapContainers();
        TestPrivacy();
        TestMainThreadHop();
        TestProtocolBytes();
        puts("WireLogTests: PASS");
    }
    return 0;
}
