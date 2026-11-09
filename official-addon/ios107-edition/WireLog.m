#import "WireLog.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <pthread.h>
#import <stdatomic.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <math.h>
#import <errno.h>
#import <CommonCrypto/CommonDigest.h>

// ============================================================ constants and state
static const unsigned long long kDefaultRotate = 20ull << 20;   // 20 MB per file
static const unsigned long long kDefaultCap = 200ull << 20;     // 200 MB in total
static const NSUInteger kFlushBytes = 64 * 1024;
static const NSUInteger kMaxPending = 8u << 20;                  // queued estimate; beyond it records are dropped and counted
static const NSUInteger kHeadBytes = 32;                         // bytes kept as hex; the rest only as length and SHA-256
static const NSUInteger kItemCap = 4096;
static const int kDepthCap = 16;
static NSString *const kAutoStartKey = @"TIOWireLogAutoStart";

static atomic_bool gActive;
static atomic_ullong gSeq, gRecords, gDropped, gPending, gBytes;
static atomic_bool gFault, gFailed; // gFailed: the observer threw; queued records are discarded
static NSLock *Lock(void) { static NSLock *l; static dispatch_once_t o; dispatch_once(&o, ^{ l = [NSLock new]; }); return l; }
static NSString *gDisabledReason;       // under Lock
static NSMutableSet<NSString *> *gWrapped; // under Lock
static NSString *gBridgeChannel;        // under Lock
static NSString *gCurrentFile;          // under Lock
static NSURL *gDirOverride;             // under Lock

static dispatch_queue_t Q(void) {
    static dispatch_queue_t q; static dispatch_once_t o;
    dispatch_once(&o, ^{ q = dispatch_queue_create("org.turboio.wirelog", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// ============================================================ redaction
static NSArray<NSString *> *Words(NSString *key) {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    NSMutableString *cur = [NSMutableString new];
    NSUInteger n = key.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [key characterAtIndex:i];
        BOOL upper = c >= 'A' && c <= 'Z', lower = c >= 'a' && c <= 'z', digit = c >= '0' && c <= '9';
        if (!upper && !lower && !digit) { if (cur.length) { [out addObject:[cur copy]]; [cur setString:@""]; } continue; }
        if (upper && cur.length) {
            // Word boundaries: fooBar -> foo|Bar, APIKey -> API|Key. cur holds lowercase, so look at the source.
            unichar src = [key characterAtIndex:i - 1];
            BOOL prevUpper = src >= 'A' && src <= 'Z';
            BOOL nextLower = i + 1 < n && [key characterAtIndex:i + 1] >= 'a' && [key characterAtIndex:i + 1] <= 'z';
            if (!prevUpper || nextLower) { [out addObject:[cur copy]]; [cur setString:@""]; }
        }
        [cur appendFormat:@"%C", (unichar)(upper ? c + 32 : c)];
    }
    if (cur.length) [out addObject:[cur copy]];
    return out;
}

// Hard: the key alone marks the value as a credential. Soft: a bare "key", "session" or "sign" is only
// a credential when its value looks like one (long, no spaces), so {key:"brightness"} stays readable.
static NSSet<NSString *> *HardWords(void) {
    static NSSet *w; static dispatch_once_t o;
    dispatch_once(&o, ^{
        w = [NSSet setWithArray:@[@"token", @"tokens", @"auth", @"authorization", @"authorisation", @"secret", @"secrets",
                                  @"password", @"passwd", @"pwd", @"cookie", @"cookies", @"signature", @"signatures",
                                  @"ticket", @"tickets", @"credential", @"credentials", @"bearer", @"jwt"]];
    });
    return w;
}
// Words that name a device or person identifier: sn, serial(Number), mac(Address), uuid.
static NSSet<NSString *> *IdentifierWords(void) {
    static NSSet *w; static dispatch_once_t o;
    dispatch_once(&o, ^{ w = [NSSet setWithArray:@[@"sn", @"serial", @"mac", @"uuid", @"udid", @"imei"]]; });
    return w;
}
BOOL TIOWireLogKeyIsSensitive(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return NO;
    static NSArray<NSString *> *suffixes; static NSSet<NSString *> *benignKey; static dispatch_once_t o;
    dispatch_once(&o, ^{
        suffixes = @[@"token", @"secret", @"password", @"passwd", @"cookie", @"credential", @"credentials", @"signature",
                     @"authcode", @"authkey", @"apikey", @"appkey", @"accesskey", @"secretkey", @"privatekey", @"signkey", @"sessionkey"];
        benignKey = [NSSet setWithArray:@[@"monkey", @"turkey", @"hockey", @"donkey", @"whiskey", @"jockey", @"hotkey"]];
    });
    NSArray<NSString *> *words = Words(key);
    NSMutableString *joined = [NSMutableString new];
    for (NSString *w in words) {
        if ([HardWords() containsObject:w] || [IdentifierWords() containsObject:w]) return YES;
        [joined appendString:w];
    }
    // Device, account and user identifiers: deviceId, device_id, accountId, userId, bindDeviceIdList.
    for (NSString *t in @[@"deviceid", @"accountid", @"userid"]) if ([joined containsString:t]) return YES;
    // apiKey, sessionKey, secret_key: "key" closing a longer name. keyCode, keyName and keyboard are left alone.
    NSString *last = words.lastObject;
    if (words.count >= 2 && ([last isEqualToString:@"key"] || [last isEqualToString:@"keys"])) return YES;
    for (NSString *s in suffixes) if ([joined hasSuffix:s]) return YES;
    // All-lowercase compounds such as "pushkey" or "clientkey".
    if (joined.length > 3 && [joined hasSuffix:@"key"] && ![benignKey containsObject:joined]) return YES;
    return NO;
}
static BOOL KeyIsSoft(NSString *key) {
    NSArray<NSString *> *w = Words(key);
    return w.count == 1 && ([w[0] isEqualToString:@"key"] || [w[0] isEqualToString:@"keys"] || [w[0] isEqualToString:@"session"] ||
                            [w[0] isEqualToString:@"sessions"] || [w[0] isEqualToString:@"sign"]);
}
static BOOL LooksLikeCredential(id v) {
    if ([v isKindOfClass:NSData.class]) return [(NSData *)v length] >= 8;
    if (![v isKindOfClass:NSString.class]) return NO;
    NSString *s = v;
    return s.length >= 16 && [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound;
}

static NSString *RedactedMarker(NSUInteger len) { return [NSString stringWithFormat:@"<redacted len=%lu>", (unsigned long)len]; }

static NSUInteger ValueLength(id v) {
    if ([v isKindOfClass:NSString.class]) return [(NSString *)v length];
    if ([v isKindOfClass:NSData.class]) return [(NSData *)v length];
    if ([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSDictionary.class]) return [(id)v count];
    if (!v || v == NSNull.null) return 0;
    @try { return [[v description] length]; } @catch (__unused id e) { return 0; }
}

static id JV(id v, int depth);

// Calling-thread copies of Flutter's typed data and error, made by Snap and encoded by JV on the writer queue.
@interface TIOWireSnapTyped : NSObject
@property (nonatomic, copy) NSData *data;
@property (nonatomic) NSUInteger type;
@end
@implementation TIOWireSnapTyped
@end
@interface TIOWireSnapError : NSObject
@property (nonatomic, strong) id code, message, details;
@end
@implementation TIOWireSnapError
@end
static NSString *TypedName(NSUInteger t) {
    static NSArray *names; static dispatch_once_t o;
    dispatch_once(&o, ^{ names = @[@"uint8", @"int32", @"int64", @"float32", @"float64"]; });
    return t < names.count ? names[t] : @"?";
}

// The owner's numeric user folder (user_<digits>) and app container UUIDs in paths are masked in every
// recorded string, whatever its length.
NSString *TIOWireLogScrubIdentifiers(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length < 6) return s;
    BOOL user = [s rangeOfString:@"user_"].location != NSNotFound;
    BOOL container = [s rangeOfString:@"/Application/"].location != NSNotFound || [s rangeOfString:@"/AppGroup/"].location != NSNotFound || [s rangeOfString:@"/PluginKitPlugin/"].location != NSNotFound;
    if (!user && !container) return s;
    static NSRegularExpression *userRe, *containerRe; static dispatch_once_t o;
    dispatch_once(&o, ^{
        userRe = [NSRegularExpression regularExpressionWithPattern:@"(?<![A-Za-z0-9])user_[0-9]+" options:0 error:nil];
        containerRe = [NSRegularExpression regularExpressionWithPattern:@"(/(?:Application|AppGroup|PluginKitPlugin)/)[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:nil];
    });
    NSString *out = s;
    if (user) out = [userRe stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"user_<n>"];
    if (container) out = [containerRe stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"$1<uuid>"];
    return out;
}

static NSString *RedactStringAt(NSString *s, int depth) {
    s = TIOWireLogScrubIdentifiers(s);
    if (s.length < 12 || s.length > 262144) return s;
    static NSRegularExpression *bearer, *jwt, *pair; static dispatch_once_t o;
    dispatch_once(&o, ^{
        bearer = [NSRegularExpression regularExpressionWithPattern:@"\\bBearer\\s+[A-Za-z0-9._~+/=-]{8,}" options:NSRegularExpressionCaseInsensitive error:nil];
        jwt = [NSRegularExpression regularExpressionWithPattern:@"\\beyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]*" options:0 error:nil];
        // name=value, name: value, "name":"value" and the same with escaped quotes, for names that contain a credential word.
        pair = [NSRegularExpression regularExpressionWithPattern:
            @"([A-Za-z0-9_-]*(?:token|secret|password|passwd|cookie|signature|credential|ticket|authorization|authcode|api_?key|app_?key|access_?key|secret_?key|device_?id|account_?id|user_?id|serial(?:_?number)?|mac_?address|uuid)[A-Za-z0-9_-]*)(\\\\?\"?\\s*[:=]\\s*\\\\?\"?)(?!<redacted)([^\"&\\s,}\\\\\\]]{4,})"
            options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *out = s;
    // JSON carried inside a string value: parse it, redact it as a tree, and keep the result only if something changed.
    NSUInteger first = 0;
    while (first < out.length && [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[out characterAtIndex:first]]) first++;
    if (first < out.length && ([out characterAtIndex:first] == '{' || [out characterAtIndex:first] == '[') && depth < kDepthCap) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[out dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (parsed) {
            id red = JV(parsed, depth + 1);
            NSData *a = [NSJSONSerialization dataWithJSONObject:parsed options:NSJSONWritingSortedKeys error:nil];
            NSData *b = [NSJSONSerialization isValidJSONObject:red] ? [NSJSONSerialization dataWithJSONObject:red options:NSJSONWritingSortedKeys error:nil] : nil;
            if (b && ![a isEqualToData:b]) out = [[NSString alloc] initWithData:b encoding:NSUTF8StringEncoding] ?: out;
        }
    }
    for (NSRegularExpression *re in @[bearer, jwt]) {
        NSArray<NSTextCheckingResult *> *hits = [re matchesInString:out options:0 range:NSMakeRange(0, out.length)];
        if (!hits.count) continue;
        NSMutableString *m = [out mutableCopy];
        for (NSTextCheckingResult *hit in hits.reverseObjectEnumerator) [m replaceCharactersInRange:hit.range withString:RedactedMarker(hit.range.length)];
        out = [m copy];
    }
    NSArray<NSTextCheckingResult *> *pairs = [pair matchesInString:out options:0 range:NSMakeRange(0, out.length)];
    if (pairs.count) {
        NSMutableString *m = [out mutableCopy];
        for (NSTextCheckingResult *hit in pairs.reverseObjectEnumerator) { NSRange r = [hit rangeAtIndex:3]; [m replaceCharactersInRange:r withString:RedactedMarker(r.length)]; }
        out = [m copy];
    }
    return out;
}

// ============================================================ JSON-safe tree
static id KVC(id o, NSString *k) { @try { return [o valueForKey:k]; } @catch (__unused id e) { return nil; } }

static NSString *Hex(NSData *d, BOOL *truncated) {
    static const char digits[] = "0123456789abcdef";
    NSUInteger n = MIN(d.length, kHeadBytes);
    *truncated = d.length > n;
    char *buf = malloc(n * 2 + 1);
    const uint8_t *p = d.bytes;
    for (NSUInteger i = 0; i < n; i++) { buf[2 * i] = digits[p[i] >> 4]; buf[2 * i + 1] = digits[p[i] & 15]; }
    NSString *s = [[NSString alloc] initWithBytesNoCopy:buf length:n * 2 encoding:NSASCIIStringEncoding freeWhenDone:YES];
    return s ?: @"";
}

static NSString *SHA256Hex(NSData *d) {
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, md);
    NSMutableString *out = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", md[i]];
    return out;
}

// Bytes are written as their length, SHA-256 and at most the first 32 bytes as hex ($hex), never in full.
static NSDictionary *BytesObject(NSData *d, NSString *kind) {
    BOOL t = NO; NSString *hex = Hex(d, &t);
    NSMutableDictionary *m = [@{@"$hex": hex, @"len": @(d.length), @"sha256": SHA256Hex(d)} mutableCopy];
    if (kind) m[@"kind"] = kind;
    if (t) m[@"truncated"] = @YES;
    return m;
}

static id JVDictionary(NSDictionary *d, int depth) {
    NSMutableArray<NSArray *> *pairs = [NSMutableArray new];
    for (id k in d) {
        NSString *ks = [k isKindOfClass:NSString.class] ? k : [NSString stringWithFormat:@"%@", k];
        [pairs addObject:@[ks, d[k]]];
    }
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:pairs.count];
    NSUInteger count = 0;
    for (NSArray *p in pairs) {
        if (++count > kItemCap) { out[@"$truncated"] = @(pairs.count - kItemCap); break; }
        id val = p[1];
        BOOL hide = val != NSNull.null && (TIOWireLogKeyIsSensitive(p[0]) || (KeyIsSoft(p[0]) && LooksLikeCredential(val)));
        NSString *outKey = TIOWireLogScrubIdentifiers(p[0]);
        if (out[outKey]) outKey = [NSString stringWithFormat:@"%@#%lu", outKey, (unsigned long)count];
        out[outKey] = hide ? RedactedMarker(ValueLength(val)) : JV(val, depth + 1);
    }
    return out;
}

static id JV(id v, int depth) {
    if (!v || v == NSNull.null) return NSNull.null;
    if (depth > kDepthCap) return @"<depth limit>";
    if ([v isKindOfClass:NSString.class]) return RedactStringAt(v, depth);
    if ([v isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return v;
        double dv = [v doubleValue];
        if (isnan(dv) || isinf(dv)) return [v description];
        return v;
    }
    if ([v isKindOfClass:NSData.class]) return BytesObject(v, @"bytes");
    if ([v isKindOfClass:NSDictionary.class]) return JVDictionary(v, depth);
    if ([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSSet.class]) {
        NSArray *a = [v isKindOfClass:NSSet.class] ? [(NSSet *)v allObjects] : v;
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:MIN(a.count, kItemCap)];
        for (id e in a) {
            if (out.count >= kItemCap) { [out addObject:@{@"$truncated": @(a.count - kItemCap)}]; break; }
            [out addObject:JV(e, depth + 1)];
        }
        return out;
    }
    if ([v isKindOfClass:NSDate.class]) return @{@"$date": @([(NSDate *)v timeIntervalSince1970])};
    if ([v isKindOfClass:TIOWireSnapTyped.class]) {
        TIOWireSnapTyped *t = v;
        return BytesObject(t.data, [@"typed:" stringByAppendingString:TypedName(t.type)]);
    }
    if ([v isKindOfClass:TIOWireSnapError.class]) {
        TIOWireSnapError *e = v;
        return @{@"$error": @{@"code": JV(e.code, depth + 1), @"message": JV(e.message, depth + 1), @"details": JV(e.details, depth + 1)}};
    }
    NSString *cls = NSStringFromClass([v class]);
    if ([cls isEqualToString:@"FlutterStandardTypedData"]) {
        id data = KVC(v, @"data"), type = KVC(v, @"type");
        NSUInteger t = [type isKindOfClass:NSNumber.class] ? [type unsignedIntegerValue] : NSNotFound;
        if ([data isKindOfClass:NSData.class]) return BytesObject(data, [@"typed:" stringByAppendingString:TypedName(t)]);
    }
    if ([cls isEqualToString:@"FlutterError"])
        return @{@"$error": @{@"code": JV(KVC(v, @"code"), depth + 1), @"message": JV(KVC(v, @"message"), depth + 1), @"details": JV(KVC(v, @"details"), depth + 1)}};
    if ([cls isEqualToString:@"NSObject"]) return @{@"$": @"sentinel (FlutterMethodNotImplemented)"};
    // An unknown class (a newer plugin's reply type, say) is kept as its class and a short description.
    // A description that throws is not the recorder's problem: the record keeps the class name only.
    NSString *desc = nil;
    @try { desc = [v description]; } @catch (__unused id e) { desc = nil; }
    if (![desc isKindOfClass:NSString.class]) return @{@"$class": cls, @"$desc": @"<description unavailable>"};
    if (desc.length > 256) desc = [desc substringToIndex:256];
    return @{@"$class": cls, @"$desc": RedactStringAt(desc, depth)};
}

id TIOWireLogJSON(id value) { return JV(value, 0); }

// ============================================================ standard codec decoder (no Flutter dependency)
typedef struct { const uint8_t *p; NSUInteger n, i; BOOL bad; int depth; } Reader;
static uint8_t RB(Reader *r) { if (r->i >= r->n) { r->bad = YES; return 0; } return r->p[r->i++]; }
static const uint8_t *RBytes(Reader *r, NSUInteger len) {
    if (r->bad || len > r->n - r->i) { r->bad = YES; return NULL; }
    const uint8_t *q = r->p + r->i; r->i += len; return q;
}
static NSUInteger RSize(Reader *r) {
    uint8_t b = RB(r);
    if (b < 254) return b;
    const uint8_t *q = RBytes(r, b == 254 ? 2 : 4);
    if (!q) return 0;
    uint32_t v = 0; memcpy(&v, q, b == 254 ? 2 : 4);
    return b == 254 ? (uint16_t)v : v;
}
static void Align(Reader *r, NSUInteger a) { NSUInteger m = r->i % a; if (m) r->i += a - m; if (r->i > r->n) r->bad = YES; }

static id RV(Reader *r);
static id RTyped(Reader *r, NSString *name, NSUInteger width, NSUInteger align, int kind) {
    NSUInteger count = RSize(r);
    Align(r, align);
    if (r->bad || count > (r->n - r->i) / width) { r->bad = YES; return nil; }
    const uint8_t *q = RBytes(r, count * width);
    if (!q) return nil;
    NSMutableArray *vals = [NSMutableArray new];
    for (NSUInteger k = 0; k < count && k < kItemCap; k++) {
        const uint8_t *e = q + k * width;
        if (kind == 0) { int32_t x; memcpy(&x, e, 4); [vals addObject:@(x)]; }
        else if (kind == 1) { int64_t x; memcpy(&x, e, 8); [vals addObject:@(x)]; }
        else if (kind == 2) { double x; memcpy(&x, e, 8); [vals addObject:@(x)]; }
        else { float x; memcpy(&x, e, 4); [vals addObject:@(x)]; }
    }
    return @{@"$typed": name, @"len": @(count), @"values": vals};
}

static id RV(Reader *r) {
    if (r->bad) return nil;
    if (++r->depth > 48) { r->bad = YES; return nil; }
    id out = nil;
    uint8_t t = RB(r);
    switch (t) {
        case 0: out = NSNull.null; break;
        case 1: out = @YES; break;
        case 2: out = @NO; break;
        case 3: { const uint8_t *q = RBytes(r, 4); if (q) { int32_t x; memcpy(&x, q, 4); out = @(x); } break; }
        case 4: { const uint8_t *q = RBytes(r, 8); if (q) { int64_t x; memcpy(&x, q, 8); out = @(x); } break; }
        case 5: { Align(r, 8); const uint8_t *q = r->bad ? NULL : RBytes(r, 8); if (q) { double x; memcpy(&x, q, 8); out = @(x); } break; }
        case 6: {
            NSUInteger len = RSize(r); const uint8_t *q = RBytes(r, len);
            if (q) { out = [[NSString alloc] initWithBytes:q length:len encoding:NSUTF8StringEncoding]; if (!out) r->bad = YES; }
            break;
        }
        case 7: { NSUInteger len = RSize(r); const uint8_t *q = RBytes(r, len); if (q) out = [NSData dataWithBytes:q length:len]; break; }
        case 8: out = RTyped(r, @"int32", 4, 4, 0); break;
        case 9: out = RTyped(r, @"int64", 8, 8, 1); break;
        case 10: out = RTyped(r, @"float64", 8, 8, 2); break;
        case 14: out = RTyped(r, @"float32", 4, 4, 3); break;
        case 11: {
            NSUInteger count = RSize(r);
            if (r->bad || count > r->n - r->i) { r->bad = YES; break; }
            NSMutableArray *a = [NSMutableArray new];
            for (NSUInteger k = 0; k < count && !r->bad; k++) { id e = RV(r); if (r->bad) break; [a addObject:e ?: NSNull.null]; }
            if (!r->bad) out = a;
            break;
        }
        case 12: {
            NSUInteger count = RSize(r);
            if (r->bad || count > (r->n - r->i) / 2) { r->bad = YES; break; }
            NSMutableDictionary *m = [NSMutableDictionary new];
            for (NSUInteger k = 0; k < count && !r->bad; k++) {
                id key = RV(r), val = RV(r);
                if (r->bad) break;
                NSString *ks = [key isKindOfClass:NSString.class] ? key : [NSString stringWithFormat:@"%@", key];
                m[ks] = val ?: NSNull.null;
            }
            if (!r->bad) out = m;
            break;
        }
        default: r->bad = YES; break; // custom (pigeon) types start at 128
    }
    r->depth--;
    if (!out) r->bad = YES;
    return out;
}

id TIOWireLogDecodeStandard(NSData *data, BOOL *ok) {
    Reader r = {data.bytes, data.length, 0, NO, 0};
    id v = data.length ? RV(&r) : nil;
    BOOL good = v && !r.bad && r.i == r.n;
    if (ok) *ok = good;
    return good ? v : nil;
}

static NSDictionary *TryMethodCall(NSData *d) {
    if (d.length < 3 || ((const uint8_t *)d.bytes)[0] != 6) return nil;
    Reader r = {d.bytes, d.length, 0, NO, 0};
    id method = RV(&r);
    if (r.bad || ![method isKindOfClass:NSString.class]) return nil;
    id args = RV(&r);
    if (r.bad || r.i != r.n) return nil;
    return @{@"codec": @"methodCall", @"method": method, @"arguments": args};
}
static NSDictionary *TryEnvelope(NSData *d) {
    if (d.length < 2) return nil;
    uint8_t first = ((const uint8_t *)d.bytes)[0];
    Reader r = {d.bytes, d.length, 1, NO, 0};
    if (first == 0) {
        id v = RV(&r);
        if (r.bad || r.i != r.n) return nil;
        return @{@"codec": @"envelope", @"value": v};
    }
    if (first == 1) {
        id code = RV(&r), msg = RV(&r), det = RV(&r);
        if (r.bad || r.i != r.n || ![code isKindOfClass:NSString.class]) return nil;
        return @{@"codec": @"errorEnvelope", @"code": code, @"message": msg, @"details": det};
    }
    return nil;
}
static NSDictionary *TryMessage(NSData *d) {
    BOOL ok = NO; id v = TIOWireLogDecodeStandard(d, &ok);
    return ok ? @{@"codec": @"message", @"value": v} : nil;
}

NSDictionary *TIOWireLogDecodeMessage(NSData *data, BOOL preferEnvelope) {
    if (!data.length) return @{@"codec": @"empty", @"len": @0};
    NSDictionary *hit = nil;
    if (preferEnvelope) hit = TryEnvelope(data) ?: TryMethodCall(data) ?: TryMessage(data);
    else hit = TryMethodCall(data) ?: TryEnvelope(data) ?: TryMessage(data);
    if (!hit) hit = @{@"codec": @"raw", @"data": data};
    NSMutableDictionary *out = [JV(hit, 0) mutableCopy];
    out[@"len"] = @(data.length);
    return out;
}

// ============================================================ channel policy
TIOWireLogChannelClass TIOWireLogClassifyChannel(NSString *channel) {
    if (![channel isKindOfClass:NSString.class] || !channel.length) return TIOWireLogChannelIgnored;
    NSString *l = channel.lowercaseString;
    BOOL ours = NO;
    for (NSString *t in @[@"rayneo", @"venus", @"voice_assistant", @"ask_ai", @"always_on"]) if ([l containsString:t]) { ours = YES; break; }
    if (!ours) return TIOWireLogChannelIgnored;
    for (NSString *t in @[@"http", @"login", @"account", @"oauth", @"passport", @"auth", @"cloud", @"userinfo", @"push", @"analytics"])
        if ([l containsString:t]) return TIOWireLogChannelOpaque;
    return TIOWireLogChannelFull;
}

// Methods that carry credentials or account state are logged by name and size only, whatever the channel.
BOOL TIOWireLogMethodIsSizeOnly(NSString *method) {
    if (![method isKindOfClass:NSString.class]) return NO;
    NSString *l = method.lowercaseString;
    for (NSString *t in @[@"token", @"login", @"auth", @"password", @"credential", @"secret"]) if ([l containsString:t]) return YES;
    return NO;
}

// ============================================================ writer (all state below lives on Q())
static int wFd = -1;
static unsigned long long wSize, wRotate = 20ull << 20, wCap = 200ull << 20;
static NSUInteger wRecordsInFile;
static NSMutableData *wBuf;
static dispatch_source_t wTimer;
static NSString *wPath;
static NSURL *wDir;
static NSDateFormatter *wISO, *wName;

NSURL *TIOWireLogDirectory(void) {
    [Lock() lock]; NSURL *o = gDirOverride; [Lock() unlock];
    if (o) return o;
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    return [NSURL fileURLWithPath:[docs stringByAppendingPathComponent:@"turbo-wirelog"] isDirectory:YES];
}

static NSDateFormatter *Formatter(NSString *format) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = format;
    return f;
}
static NSString *ISOString(NSTimeInterval t) {
    if (!wISO) wISO = Formatter(@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
    return [wISO stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static void FlushBuffer(void) {
    if (wFd < 0 || !wBuf.length) return;
    const uint8_t *p = wBuf.bytes; NSUInteger left = wBuf.length;
    while (left) {
        ssize_t w = write(wFd, p, left);
        if (w < 0) { if (errno == EINTR) continue; break; }
        p += w; left -= (NSUInteger)w;
    }
    wSize += wBuf.length - left;
    [wBuf setLength:0];
}

static void EnforceCap(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:wDir.path error:nil] ?: @[];
    NSMutableArray<NSString *> *old = [NSMutableArray new];
    for (NSString *n in names) if ([n hasPrefix:@"wirelog-"] && [n hasSuffix:@".jsonl"] && ![wPath.lastPathComponent isEqualToString:n]) [old addObject:n];
    [old sortUsingSelector:@selector(compare:)];
    unsigned long long total = 0; NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary new];
    for (NSString *n in old) { struct stat st; unsigned long long s = stat([wDir.path stringByAppendingPathComponent:n].fileSystemRepresentation, &st) == 0 ? (unsigned long long)st.st_size : 0; sizes[n] = @(s); total += s; }
    // Leave room for the file being written so the whole directory stays at or under the cap.
    unsigned long long limit = wCap > wRotate ? wCap - wRotate : 0;
    for (NSString *n in old) {
        if (total <= limit) break;
        if (unlink([wDir.path stringByAppendingPathComponent:n].fileSystemRepresentation) == 0) total -= sizes[n].unsignedLongLongValue;
    }
}

static void CloseFile(NSDictionary *footer) {
    if (wFd < 0) return;
    if (footer) {
        NSData *j = [NSJSONSerialization dataWithJSONObject:footer options:NSJSONWritingSortedKeys error:nil];
        if (j) { [wBuf appendData:j]; [wBuf appendBytes:"\n" length:1]; }
    }
    FlushBuffer();
    close(wFd); wFd = -1; wSize = 0; wRecordsInFile = 0;
    [Lock() lock]; gCurrentFile = nil; [Lock() unlock];
}

static NSDictionary *HeaderRecord(void) {
    return @{@"type": @"header", @"schema": @1, @"tool": @"wirelog", @"started": ISOString(NSDate.date.timeIntervalSince1970),
             @"mono": @(NSProcessInfo.processInfo.systemUptime),
             @"note": @"records are written by one queue; sort by seq. mono is systemUptime seconds. Redacted values read <redacted len=N>."};
}

// File names carry a UTC millisecond stamp that only ever increases within the process and never falls behind the
// newest file already on disk. Name order is therefore creation order, which is what the cap deletes by, and a name
// freed by the cap can never be handed to a newer file.
static int64_t wLastNameMs;
static BOOL OpenFile(void) {
    if (!wDir) wDir = TIOWireLogDirectory();
    if (!wBuf) wBuf = [NSMutableData new];
    [NSFileManager.defaultManager createDirectoryAtURL:wDir withIntermediateDirectories:YES attributes:nil error:nil];
    // Kept out of iCloud and computer backups; the in-app export shares the files directly.
    [wDir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    if (!wName) wName = Formatter(@"yyyyMMdd'T'HHmmss.SSS'Z'");
    for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:wDir.path error:nil] ?: @[]) {
        if (![n hasPrefix:@"wirelog-"] || ![n hasSuffix:@".jsonl"]) continue;
        NSDate *d = [wName dateFromString:[n substringWithRange:NSMakeRange(8, n.length - 8 - 6)]];
        if (d) wLastNameMs = MAX(wLastNameMs, (int64_t)llround(d.timeIntervalSince1970 * 1000));
    }
    NSString *path = nil;
    for (int tries = 0; tries < 1000; tries++) {
        wLastNameMs = MAX((int64_t)llround(NSDate.date.timeIntervalSince1970 * 1000), wLastNameMs + 1);
        path = [wDir.path stringByAppendingPathComponent:[NSString stringWithFormat:@"wirelog-%@.jsonl", [wName stringFromDate:[NSDate dateWithTimeIntervalSince1970:(wLastNameMs + 0.5) / 1000.0]]]];
        wFd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (wFd >= 0 || errno != EEXIST) break;
    }
    if (wFd < 0) return NO;
    wPath = path; wSize = 0; wRecordsInFile = 0; [wBuf setLength:0];
    [Lock() lock]; gCurrentFile = path.lastPathComponent; [Lock() unlock];
    NSData *h = [NSJSONSerialization dataWithJSONObject:HeaderRecord() options:NSJSONWritingSortedKeys error:nil];
    [wBuf appendData:h]; [wBuf appendBytes:"\n" length:1];
    EnforceCap();
    return YES;
}

static void StartTimer(void) {
    if (wTimer) return;
    wTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, Q());
    dispatch_source_set_timer(wTimer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(wTimer, ^{ @try { FlushBuffer(); } @catch (__unused id e) {} });
    dispatch_resume(wTimer);
}
static void StopTimer(void) { if (wTimer) { dispatch_source_cancel(wTimer); wTimer = nil; } }

static void AppendLine(NSData *line) {
    if (wFd < 0 && !OpenFile()) @throw [NSException exceptionWithName:@"WireLogOpen" reason:@"cannot open the log file" userInfo:nil];
    StartTimer();
    if (wRecordsInFile > 0 && wSize + wBuf.length + line.length + 1 > wRotate) {
        CloseFile(nil);
        if (!OpenFile()) @throw [NSException exceptionWithName:@"WireLogOpen" reason:@"cannot rotate the log file" userInfo:nil];
    }
    [wBuf appendData:line]; [wBuf appendBytes:"\n" length:1];
    wRecordsInFile++;
    if (wBuf.length >= kFlushBytes) FlushBuffer();
}

static NSDictionary *FooterRecord(void) {
    [Lock() lock]; NSString *why = gDisabledReason; NSArray *wrapped = gWrapped.allObjects; [Lock() unlock];
    return @{@"type": @"footer", @"records": @(atomic_load(&gRecords)), @"dropped": @(atomic_load(&gDropped)),
             @"wrappedChannels": [wrapped sortedArrayUsingSelector:@selector(compare:)] ?: @[], @"disabledReason": why ?: NSNull.null,
             @"wall": ISOString(NSDate.date.timeIntervalSince1970)};
}

// ============================================================ records
// Runs on Q(). The recorder must never take the host app down, so nothing here may throw.
static void CloseSession(void) { @try { StopTimer(); CloseFile(FooterRecord()); } @catch (__unused id e) { if (wFd >= 0) { close(wFd); wFd = -1; } } }
static void Fail(NSString *reason) {
    atomic_store(&gFailed, YES);
    atomic_store(&gActive, NO);
    [Lock() lock]; if (!gDisabledReason) gDisabledReason = reason ?: @"error"; [Lock() unlock];
    dispatch_async(Q(), ^{ CloseSession(); });
}

static NSString *ThreadTag(void) {
    if (NSThread.isMainThread) return @"main";
    NSString *name = NSThread.currentThread.name;
    return [NSString stringWithFormat:@"bg-%x%@%@", pthread_mach_thread_np(pthread_self()), name.length ? @":" : @"", name ?: @""];
}

static NSMutableDictionary *NewRecordSeq(NSString *dir, NSString *channel, NSNumber *reserved) {
    if (atomic_exchange(&gFault, NO)) @throw [NSException exceptionWithName:@"WireLogFault" reason:@"injected" userInfo:nil];
    return [@{@"seq": reserved ?: @(atomic_fetch_add(&gSeq, 1) + 1), @"mono": @(NSProcessInfo.processInfo.systemUptime),
              @"wallEpoch": @(NSDate.date.timeIntervalSince1970), @"dir": dir, @"channel": channel ?: @"?", @"thread": ThreadTag()} mutableCopy];
}

static NSMutableDictionary *NewRecord(NSString *dir, NSString *channel) { return NewRecordSeq(dir, channel, nil); }

// rec may carry _raw (NSData) and _env (NSNumber): decoded on the writer queue, not on the caller.
static void WLEnqueue(NSMutableDictionary *rec) {
    if (!atomic_load(&gActive)) return;
    NSData *raw = rec[@"_raw"];
    // Raw bytes and the structural snapshots both end up as hex or JSON, so the backlog estimate counts them tripled.
    NSUInteger estimate = 512 + (raw.length + [rec[@"_est"] unsignedIntegerValue]) * 3;
    if (atomic_load(&gPending) + estimate > kMaxPending) { atomic_fetch_add(&gDropped, 1); return; }
    atomic_fetch_add(&gPending, estimate);
    dispatch_async(Q(), ^{
        @try {
            if (!atomic_load(&gFailed)) { // a normal Stop still drains what was queued before it
                NSMutableDictionary *r = rec;
                NSData *bytes = r[@"_raw"];
                // Snapshots taken on the calling thread (_jv_x) are encoded and redacted here, off that thread.
                for (NSString *k in [r.allKeys copy]) {
                    if (![k hasPrefix:@"_jv_"]) continue;
                    id field = nil;
                    @try { field = JV(r[k], 0); } @catch (__unused id e) { field = @{@"$unencodable": @YES}; }
                    r[[k substringFromIndex:4]] = field;
                    [r removeObjectForKey:k];
                }
                [r removeObjectForKey:@"_est"];
                if (bytes) {
                    // Unknown shapes (newer plugin builders, custom codec types) end up as raw hex, never as a lost session.
                    NSDictionary *d = nil;
                    @try { d = TIOWireLogDecodeMessage(bytes, [r[@"_env"] boolValue]); } @catch (__unused id e) { d = nil; }
                    if (![d isKindOfClass:NSDictionary.class]) d = @{@"codec": @"raw", @"data": BytesObject(bytes, nil), @"len": @(bytes.length)};
                    [r removeObjectForKey:@"_raw"]; [r removeObjectForKey:@"_env"];
                    BOOL sizeOnly = [d[@"codec"] isEqual:@"methodCall"] && TIOWireLogMethodIsSizeOnly(d[@"method"]);
                    for (NSString *k in d) {
                        if (sizeOnly && ([k isEqualToString:@"arguments"] || [k isEqualToString:@"value"])) continue;
                        if (!r[k]) r[k] = d[k]; else if (![k isEqualToString:@"len"]) r[[@"decoded_" stringByAppendingString:k]] = d[k];
                    }
                    if (sizeOnly) r[@"opaque"] = @YES;
                    id v = d[@"value"];
                    if ([v isKindOfClass:NSDictionary.class] && [v[@"eventType"] isKindOfClass:NSString.class] && !r[@"eventType"]) r[@"eventType"] = v[@"eventType"];
                }
                r[@"wall"] = ISOString([r[@"wallEpoch"] doubleValue]);
                [r removeObjectForKey:@"wallEpoch"];
                NSData *line = [NSJSONSerialization isValidJSONObject:r] ? [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:nil] : nil;
                if (!line) line = [NSJSONSerialization dataWithJSONObject:@{@"seq": r[@"seq"] ?: @0, @"dir": r[@"dir"] ?: @"?", @"error": @"unencodable record"} options:0 error:nil];
                AppendLine(line);
                atomic_fetch_add(&gRecords, 1); atomic_fetch_add(&gBytes, line.length + 1);
            }
        } @catch (NSException *e) {
            Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]);
        }
        atomic_fetch_sub(&gPending, estimate);
    });
}

// ============================================================ session control
BOOL TIOWireLogActive(void) { return atomic_load(&gActive); }

BOOL TIOWireLogStart(void) {
    if (atomic_load(&gActive)) return YES;
    [Lock() lock]; gDisabledReason = nil; [Lock() unlock];
    atomic_store(&gSeq, 0); atomic_store(&gRecords, 0); atomic_store(&gDropped, 0); atomic_store(&gBytes, 0); atomic_store(&gFailed, NO);
    atomic_store(&gActive, YES); // the file opens lazily on the writer queue; the caller never waits on I/O
    return YES;
}

void TIOWireLogStop(void) {
    if (!atomic_exchange(&gActive, NO)) return;
    dispatch_async(Q(), ^{ CloseSession(); });
}

void TIOWireLogFlush(void (^done)(void)) {
    dispatch_async(Q(), ^{ @try { FlushBuffer(); } @catch (__unused id e) {} if (done) dispatch_async(dispatch_get_main_queue(), done); });
}

NSArray<NSURL *> *TIOWireLogFiles(void) {
    NSURL *dir = TIOWireLogDirectory();
    NSMutableArray<NSURL *> *out = [NSMutableArray new];
    for (NSString *n in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir.path error:nil] sortedArrayUsingSelector:@selector(compare:)])
        if ([n hasPrefix:@"wirelog-"] && [n hasSuffix:@".jsonl"]) [out addObject:[dir URLByAppendingPathComponent:n]];
    return out;
}

NSDictionary *TIOWireLogLiveStatus(void) {
    [Lock() lock];
    NSDictionary *s = @{@"active": @(atomic_load(&gActive)), @"records": @(atomic_load(&gRecords)), @"dropped": @(atomic_load(&gDropped)),
                        @"bytes": @(atomic_load(&gBytes)), @"file": gCurrentFile ?: @"", @"disabledReason": gDisabledReason ?: @"",
                        @"wrappedChannels": [gWrapped.allObjects sortedArrayUsingSelector:@selector(compare:)] ?: @[]};
    [Lock() unlock];
    return s;
}

NSDictionary *TIOWireLogStatus(void) {
    unsigned long long total = 0;
    NSArray<NSURL *> *files = TIOWireLogFiles();
    for (NSURL *u in files) { struct stat st; if (stat(u.fileSystemRepresentation, &st) == 0) total += (unsigned long long)st.st_size; }
    NSMutableDictionary *s = [TIOWireLogLiveStatus() mutableCopy];
    s[@"files"] = @(files.count); s[@"totalBytes"] = @(total);
    return s;
}

BOOL TIOWireLogAutoStartEnabled(void) { return [NSUserDefaults.standardUserDefaults boolForKey:kAutoStartKey]; }
void TIOWireLogSetAutoStart(BOOL on) { [NSUserDefaults.standardUserDefaults setBool:on forKey:kAutoStartKey]; }
void TIOWireLogMaybeAutoStart(void) { if (TIOWireLogAutoStartEnabled()) TIOWireLogStart(); }

static void ObserveBackground(void) {
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        // Plain notification names: no UIKit import, so the host tests link against Foundation only.
        [NSNotificationCenter.defaultCenter addObserverForName:@"UIApplicationDidEnterBackgroundNotification" object:nil queue:nil usingBlock:^(__unused NSNotification *n) {
            dispatch_async(Q(), ^{ @try { FlushBuffer(); } @catch (__unused id e) {} });
        }];
    });
}

// ============================================================ hook entry points
@interface TIOWireLogContext : NSObject
@property (nonatomic) BOOL claimed;
@property (nonatomic, copy) NSString *channel;
@end
@implementation TIOWireLogContext
@end
static __thread __unsafe_unretained TIOWireLogContext *tlsContext;

static void NoteWrapped(NSString *channel) {
    [Lock() lock]; if (!gWrapped) gWrapped = [NSMutableSet new]; [gWrapped addObject:channel]; [Lock() unlock];
}

NSString *TIOWireLogClaimBridgeCall(void) {
    TIOWireLogContext *ctx = tlsContext;
    if (!ctx && !atomic_load(&gActive)) return nil; // idle cost: two loads
    [Lock() lock];
    NSString *ch = ctx.channel;
    if (ch) gBridgeChannel = ch; else ch = gBridgeChannel ?: @"com.rayneo/sdk";
    [Lock() unlock];
    if (ctx) ctx.claimed = YES;
    return ch;
}

// Plain: an object of Foundation's or CoreFoundation's own classes (what the Flutter codec builds), or of
// Flutter's typed-data and error classes themselves (matched by exact class name, so never a subclass).
// Decided from the runtime class alone, without sending the object a message, so an object that answers
// differently per read (a subclass or a proxy) is never read by the recorder, and the guard after it sees
// exactly what it would have seen without the recorder.
static BOOL WLPlain(id o) {
    if (!o) return NO;
    Class c = object_getClass(o);
    const char *image = c ? class_getImageName(c) : NULL;
    if (image && !strncmp(image, "/System/Library/Frameworks/", 27) && (strstr(image, "/CoreFoundation.framework/") || strstr(image, "/Foundation.framework/"))) return YES;
    const char *name = c ? class_getName(c) : "";
    return !strcmp(name, "FlutterStandardTypedData") || !strcmp(name, "FlutterError");
}
// The call itself: a plain dictionary or Flutter's own FlutterMethodCall class (not a subclass).
static BOOL WLCallReadable(id call) { return call && (WLPlain(call) || !strcmp(class_getName(object_getClass(call)), "FlutterMethodCall")); }
static id WLCallField(id call, NSString *key) { return WLCallReadable(call) ? KVC(call, key) : nil; }
static NSDictionary *WLClassOnly(id o) { return @{@"$class": @(class_getName(object_getClass(o))), @"$unread": @YES}; }

// A structural copy taken on the calling thread: containers are rebuilt, immutable strings and data are shared,
// nothing is encoded, redacted or described here. `bytes` accumulates a size estimate for the backlog bound.
// Objects that are not plain are recorded by class name only and never messaged.
static id Snap(id v, NSUInteger *bytes, int depth) {
    *bytes += 16;
    if (!v) return nil;
    if (!WLPlain(v)) return WLClassOnly(v);
    if (depth > kDepthCap) return @"<depth limit>";
    // Shared leaves: immutable value objects only.
    if ([v isKindOfClass:NSNumber.class] || v == NSNull.null || [v isKindOfClass:NSDate.class]) return v;
    if ([v isKindOfClass:NSString.class]) { *bytes += [(NSString *)v length]; return [[NSString alloc] initWithString:v]; }
    if ([v isKindOfClass:NSData.class]) { *bytes += [(NSData *)v length]; return [[NSData alloc] initWithData:v]; }
    if ([v isKindOfClass:NSDictionary.class]) {
        // One internal enumeration: no keyed lookups, and a key is checked before anything is sent to it.
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:MIN([(NSDictionary *)v count], kItemCap)];
        __block NSUInteger n = 0;
        [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k, id val, BOOL *stop) {
            if (++n > kItemCap) { *stop = YES; return; }
            id key;
            if (WLPlain(k) && [k isKindOfClass:NSString.class]) key = [[NSString alloc] initWithString:k];
            else if (WLPlain(k) && [k isKindOfClass:NSNumber.class]) key = [NSString stringWithFormat:@"%@", k];
            else key = [NSString stringWithFormat:@"$key:%s#%lu", class_getName(object_getClass(k)), (unsigned long)n];
            if (m[key]) key = [NSString stringWithFormat:@"%@#%lu", key, (unsigned long)n];
            m[key] = Snap(val, bytes, depth + 1) ?: NSNull.null;
        }];
        return m;
    }
    if ([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSSet.class] || [v isKindOfClass:NSOrderedSet.class]) {
        // Sets and ordered sets become arrays, element by element; each element is checked by Snap itself.
        NSMutableArray *a = [NSMutableArray new];
        for (id e in (id<NSFastEnumeration>)v) { if (a.count >= kItemCap) break; [a addObject:Snap(e, bytes, depth + 1) ?: NSNull.null]; }
        return a;
    }
    const char *name = class_getName(object_getClass(v));
    if (!strcmp(name, "FlutterStandardTypedData")) {
        id data = KVC(v, @"data"), type = KVC(v, @"type");
        if (![data isKindOfClass:NSData.class] || !WLPlain(data)) return WLClassOnly(v);
        TIOWireSnapTyped *t = [TIOWireSnapTyped new];
        t.data = [[NSData alloc] initWithData:data]; t.type = WLPlain(type) && [type isKindOfClass:NSNumber.class] ? [type unsignedIntegerValue] : NSNotFound;
        *bytes += t.data.length;
        return t;
    }
    if (!strcmp(name, "FlutterError")) {
        TIOWireSnapError *e = [TIOWireSnapError new];
        e.code = Snap(KVC(v, @"code"), bytes, depth + 1); e.message = Snap(KVC(v, @"message"), bytes, depth + 1); e.details = Snap(KVC(v, @"details"), bytes, depth + 1);
        return e;
    }
    return WLClassOnly(v); // any other plain class (NSURL, NSValue, ...) is named, not read
}

static const void *kBridgeLink = &kBridgeLink;

id TIOWireLogWrapBridgeResult(NSString *channel, id call, id result) {
    if (!atomic_load(&gActive) || !result) return result;
    @try {
        id method = WLCallField(call, @"method");
        NSString *methodName = WLPlain(method) && [method isKindOfClass:NSString.class] ? [method copy] : @"?";
        BOOL sizeOnly = TIOWireLogMethodIsSizeOnly(methodName);
        NSMutableDictionary *rec = NewRecord(@"d2n.call", channel);
        NSNumber *callSeq = rec[@"seq"];
        rec[@"method"] = methodName;
        NSUInteger bytes = 0;
        if (sizeOnly) rec[@"opaque"] = @YES;
        else { rec[@"_jv_arguments"] = Snap(WLCallField(call, @"arguments"), &bytes, 0); rec[@"_est"] = @(bytes); }
        WLEnqueue(rec);
        NSTimeInterval t0 = NSProcessInfo.processInfo.systemUptime;
        void (^original)(id) = result;
        __block atomic_flag recorded = ATOMIC_FLAG_INIT;
        id wrapper = [^(id value) {
            original(value); // first and unchanged: the observer only looks afterwards
            if (!atomic_load(&gActive) || atomic_flag_test_and_set(&recorded)) return;
            @try {
                NSMutableDictionary *r = NewRecord(@"d2n.result", channel);
                r[@"callSeq"] = callSeq; r[@"method"] = methodName;
                r[@"latencyMs"] = @(round((NSProcessInfo.processInfo.systemUptime - t0) * 10000.0) / 10.0);
                if (sizeOnly) r[@"opaque"] = @YES;
                else { NSUInteger vb = 0; r[@"_jv_value"] = Snap(value, &vb, 0); r[@"_est"] = @(vb); }
                WLEnqueue(r);
            } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); }
        } copy];
        // Lets TIOWireLogBridgeForwarded link a forwarded call to this record.
        objc_setAssociatedObject(wrapper, kBridgeLink, @{@"callSeq": callSeq, @"channel": channel ?: @"?"}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return wrapper;
    } @catch (NSException *e) {
        Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]);
        return result;
    }
}

void TIOWireLogBridgeForwarded(id wrappedResult, id call) {
    if (!atomic_load(&gActive) || !wrappedResult) return;
    @try {
        NSDictionary *link = objc_getAssociatedObject(wrappedResult, kBridgeLink);
        if (!link) return; // not a recorder wrapper: the original call was not recorded either
        id method = WLCallField(call, @"method");
        NSString *methodName = WLPlain(method) && [method isKindOfClass:NSString.class] ? [method copy] : @"?";
        NSMutableDictionary *r = NewRecord(@"d2n.forwarded", link[@"channel"]);
        r[@"callSeq"] = link[@"callSeq"]; r[@"method"] = methodName;
        if (TIOWireLogMethodIsSizeOnly(methodName)) r[@"opaque"] = @YES;
        else { NSUInteger bytes = 0; r[@"_jv_arguments"] = Snap(WLCallField(call, @"arguments"), &bytes, 0); r[@"_est"] = @(bytes); }
        WLEnqueue(r);
    } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); }
}

static BOOL PrefersEnvelope(NSString *channel) {
    NSString *l = channel.lowercaseString;
    return [l containsString:@"event"] || [l containsString:@"rayneonet"];
}

void TIOWireLogNativeToDart(NSString *channel, NSData *message) {
    if (!atomic_load(&gActive)) return;
    @try {
        TIOWireLogChannelClass c = TIOWireLogClassifyChannel(channel);
        if (c == TIOWireLogChannelIgnored) return;
        NSMutableDictionary *rec = NewRecord(@"n2d.message", channel);
        if (c == TIOWireLogChannelOpaque) { rec[@"opaque"] = @YES; rec[@"bytes"] = @(message.length); }
        else if (message.length) { rec[@"_raw"] = [message isKindOfClass:NSData.class] ? [message copy] : [NSData data]; rec[@"_env"] = @(PrefersEnvelope(channel)); }
        else rec[@"len"] = @0;
        WLEnqueue(rec);
    } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); }
}

// The method name of a standard-codec method call, read without decoding the arguments.
static NSString *PeekMethod(NSData *d) {
    if (![d isKindOfClass:NSData.class] || d.length < 3 || ((const uint8_t *)d.bytes)[0] != 6) return nil;
    Reader r = {d.bytes, d.length, 0, NO, 0};
    id m = RV(&r);
    return !r.bad && [m isKindOfClass:NSString.class] ? m : nil;
}

typedef void (^TIOWireReply)(NSData *);
typedef void (^TIOWireHandler)(NSData *, TIOWireReply);
static const void *kWrappedHandler = &kWrappedHandler;

id TIOWireLogWrapHandler(NSString *channel, id handler) {
    if (!handler || TIOWireLogClassifyChannel(channel) == TIOWireLogChannelIgnored) return handler;
    // The two- and three-argument setters can call each other; never wrap a wrapper.
    if (objc_getAssociatedObject(handler, kWrappedHandler)) return handler;
    NoteWrapped(channel);
    TIOWireHandler original = handler;
    BOOL channelOpaque = TIOWireLogClassifyChannel(channel) == TIOWireLogChannelOpaque;
    TIOWireHandler wrapper = [^(NSData *message, TIOWireReply reply) {
        if (!atomic_load(&gActive)) { original(message, reply); return; }
        NSString *peek = nil;
        BOOL sizeOnly = channelOpaque;
        @try { peek = PeekMethod(message); sizeOnly = sizeOnly || TIOWireLogMethodIsSizeOnly(peek); } @catch (__unused id e) { sizeOnly = YES; }
        TIOWireLogContext *ctx = [TIOWireLogContext new];
        ctx.channel = channel;
        NSNumber *callSeq = nil; NSTimeInterval t0 = NSProcessInfo.processInfo.systemUptime;
        TIOWireReply wrapped = reply;
        @try {
            callSeq = @(atomic_fetch_add(&gSeq, 1) + 1); // reserved now so the result can point at its call
            if (reply) {
                __block atomic_flag recorded = ATOMIC_FLAG_INIT;
                wrapped = [^(NSData *response) {
                    reply(response); // forwarded first and unchanged
                    if (ctx.claimed || !atomic_load(&gActive) || atomic_flag_test_and_set(&recorded)) return;
                    @try {
                        NSMutableDictionary *r = NewRecord(@"d2n.result", channel);
                        r[@"callSeq"] = callSeq;
                        r[@"latencyMs"] = @(round((NSProcessInfo.processInfo.systemUptime - t0) * 10000.0) / 10.0);
                        if (sizeOnly) { r[@"opaque"] = @YES; r[@"bytes"] = @(response.length); if (peek) r[@"method"] = peek; }
                        else if (response.length) { r[@"_raw"] = [response copy]; r[@"_env"] = @YES; } else r[@"len"] = @0;
                        WLEnqueue(r);
                    } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); }
                } copy];
            }
        } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); wrapped = reply; }
        TIOWireLogContext *previous = tlsContext;
        tlsContext = ctx;
        @try { original(message, wrapped); }
        @finally { tlsContext = previous; }
        if (ctx.claimed || !atomic_load(&gActive)) return; // the bridge hook recorded this call itself
        @try {
            NSMutableDictionary *r = NewRecordSeq(@"d2n.call", channel, callSeq);
            if (sizeOnly) { r[@"opaque"] = @YES; r[@"bytes"] = @(message.length); if (peek) r[@"method"] = peek; }
            else if (message.length) { r[@"_raw"] = [message copy]; r[@"_env"] = @NO; } else r[@"len"] = @0;
            WLEnqueue(r);
        } @catch (NSException *e) { Fail([NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""]); }
    } copy];
    objc_setAssociatedObject(wrapper, kWrappedHandler, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return wrapper;
}

static int64_t (*PriorSetHandler)(id, SEL, id, id);
static int64_t SetHandlerHook(id self, SEL cmd, id channel, id handler) {
    id h = handler;
    @try { h = TIOWireLogWrapHandler(channel, handler); } @catch (__unused id e) { h = handler; }
    return PriorSetHandler(self, cmd, channel, h);
}
// Same with a task queue (background plugins such as activity_recognition use it). A nil handler removes a
// handler and passes straight through.
static int64_t (*PriorSetHandlerQ)(id, SEL, id, id, id);
static int64_t SetHandlerQHook(id self, SEL cmd, id channel, id handler, id queue) {
    id h = handler;
    @try { h = TIOWireLogWrapHandler(channel, handler); } @catch (__unused id e) { h = handler; }
    return PriorSetHandlerQ(self, cmd, channel, h, queue);
}

static Method CheckedSetter(NSString *selector, unsigned args) {
    Method m = class_getInstanceMethod(NSClassFromString(@"FlutterEngine"), NSSelectorFromString(selector));
    if (!m || method_getNumberOfArguments(m) != args) return NULL;
    for (unsigned i = 2; i < args; i++) { char *t = method_copyArgumentType(m, i); BOOL ok = t && t[0] == '@'; free(t); if (!ok) return NULL; }
    char *r = method_copyReturnType(m); BOOL okReturn = r && (r[0] == 'v' || r[0] == 'q' || r[0] == 'l' || r[0] == 'Q'); free(r);
    return okReturn ? m : NULL;
}

BOOL TIOInstallWireLogHook(void) {
    static BOOL installed2, installed3;
    ObserveBackground();
    if (!installed2) {
        Method m = CheckedSetter(@"setMessageHandlerOnChannel:binaryMessageHandler:", 4);
        if (m) { PriorSetHandler = (void *)method_setImplementation(m, (IMP)SetHandlerHook); installed2 = YES; }
    }
    if (!installed3) {
        Method m = CheckedSetter(@"setMessageHandlerOnChannel:binaryMessageHandler:taskQueue:", 5);
        if (m) { PriorSetHandlerQ = (void *)method_setImplementation(m, (IMP)SetHandlerQHook); installed3 = YES; }
    }
    return installed2 || installed3;
}

// ============================================================ test support
void TIOWireLogConfigure(NSURL *directory, unsigned long long rotateBytes, unsigned long long capBytes) {
    atomic_store(&gActive, NO);
    dispatch_sync(Q(), ^{ StopTimer(); CloseFile(nil); wDir = directory; wRotate = rotateBytes ?: kDefaultRotate; wCap = capBytes ?: kDefaultCap; });
    [Lock() lock]; gDirOverride = directory; gDisabledReason = nil; gWrapped = nil; [Lock() unlock];
    atomic_store(&gSeq, 0); atomic_store(&gRecords, 0); atomic_store(&gDropped, 0); atomic_store(&gBytes, 0); atomic_store(&gPending, 0); atomic_store(&gFailed, NO);
}
void TIOWireLogDrainForTest(void) { dispatch_sync(Q(), ^{ FlushBuffer(); }); }
void TIOWireLogInjectFaultForTest(void) { atomic_store(&gFault, YES); }
