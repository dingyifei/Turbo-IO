#import "ClenchLab.h"
#if TIO_IMAGE_RX_LAB
#import "A2UIProbe.h"
#import "AlwaysOnAudio.h"
#import <CommonCrypto/CommonDigest.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#include <zlib.h>
#include <math.h>
// build.sh passes the short SHA (+"-dirty"); preview, tests and other builds fall back to "unknown".
#ifndef TIO_BUILD_COMMIT
#define TIO_BUILD_COMMIT "unknown"
#endif

NSString *const TIOClenchLabChangedNotification=@"TIOClenchLabChanged";
static NSString *const PendingKey=@"clenchLab.pending.v1";
// A dump restore the user waived while the official interface was unavailable: kept trying, never blocks Start.
static NSString *const OwedKey=@"clenchLab.restoreOwed.v1";
// Crash insurance: a capture rewrites its manifest (marked interrupted) this often.
static const NSTimeInterval CheckpointSeconds=5;
static const unsigned long long DumpCap=64ULL*1024*1024;
// Lane T reads at most this many officialDump entries; the rest are skipped with a reason, never attached.
static const NSUInteger DumpFileCap=64;
// Official files and events.jsonl count only when they fall inside the session's wall-clock window plus this slack.
static const double WindowSlackMs=5000;
// Passive automatic paths need this many consecutive alwaysOnRunning==NO readings with the target glasses connected.
static const NSUInteger NotRunningReadings=2;
// Auto-attach waits for this many consecutive alwaysOnRunning==NO readings spanning at least this long, so the official
// writer can flush and close its Ogg first.
static const NSUInteger AttachSettleReadings=3;
static const NSTimeInterval AttachSettleSeconds=2;
// S2-01: an official file is copied only if it was last written by the session's effective receive deadline in wall time
// (startWallMs + deadline s x 1000) plus this flush slack. The restored dump may keep the writer going after the session;
// anything written later holds audio the user did not agree to put in the session ("written-after-session").
static const double FlushSlackMs=5000;
// Official listing bounds: entries walked, and new files born inside the window per attach (earliest born first).
static const NSUInteger EnumerationCap=20000,CandidateCap=256;
// An attach that could not copy a file (it failed the stable-copy check) may run again this many times in total.
static const NSInteger MaxAttachAttempts=5;
static NSString *DeviceKey(NSString *d){if(![d isKindOfClass:NSString.class]||!d.length)return nil;NSData *b=[d dataUsingEncoding:NSUTF8StringEncoding];unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,h);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<8;i++)[s appendFormat:@"%02x",h[i]];return s;}
NSArray<NSString *> *TIOClenchLabels(void){return @[@"double-tap",@"single-tap",@"true-clench",@"chew",@"talk",@"walk",@"tap-temple",@"silence"];}
NSArray<NSString *> *TIOClenchSources(void){return @[@"lifelog",@"voice"];}
BOOL TIOClenchSourceSelectable(NSString *s){return [s isKindOfClass:NSString.class]&&[s isEqual:@"lifelog"];}
NSString *TIOClenchBuildCommit(void){NSString *c=@TIO_BUILD_COMMIT;NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{7,40}(-dirty)?$" options:0 error:nil];return [r firstMatchInString:c options:0 range:NSMakeRange(0,c.length)]?c:@"unknown";}

#pragma mark Values
static BOOL IsCFBool(id v){return [v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID();}
static NSNumber *Integer(id v){
 if(![v isKindOfClass:NSNumber.class]||IsCFBool(v))return nil;const char *t=[v objCType];
 if(t[0]=='f'||t[0]=='d'){double d=[v doubleValue];return isfinite(d)&&d==floor(d)&&fabs(d)<9.0e15?@((long long)d):nil;}
 return t[0]=='Q'?v:@([v longLongValue]);
}
static double R6(double t){return round(t*1e6)/1e6;}
static NSString *ISO(NSDate *d,BOOL fraction){NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];f.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];if(fraction)f.formatOptions|=NSISO8601DateFormatWithFractionalSeconds;return [f stringFromDate:d?:NSDate.date];}
static BOOL Safe(NSString *s,NSUInteger max){static NSCharacterSet *bad;static dispatch_once_t once;dispatch_once(&once,^{bad=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-"].invertedSet;});return [s isKindOfClass:NSString.class]&&s.length&&s.length<=max&&[s rangeOfCharacterFromSet:bad].location==NSNotFound;}

#pragma mark Envelope
static BOOL Varint(const uint8_t *b,NSUInteger n,NSUInteger *at,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(*at>=n)return NO;uint8_t x=b[(*at)++];if(i==9&&x>1)return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return YES;}return NO;}
// Port of BusinessEnvelopeMetadata.inspect: the shipping A2UI/Todo decoders reject a non-empty field 4.
static BOOL Envelope(NSData *d,uint64_t *version,uint64_t *type,NSRange *json,NSRange *data){
 if(![d isKindOfClass:NSData.class]||!d.length||d.length>1048576)return NO;
 const uint8_t *b=d.bytes;NSUInteger n=d.length,at=0,fields=0;unsigned seen=0;*version=0;*type=0;*json=*data=NSMakeRange(NSNotFound,0);
 while(at<n){
  if(++fields>256)return NO;uint64_t key,v;if(!Varint(b,n,&at,&key))return NO;uint64_t field=key>>3,wire=key&7;if(!field||field>0x1fffffff)return NO;
  if(field<=4){
   if(seen&(1u<<field))return NO;seen|=1u<<field;if(wire!=(field<=2?0:2))return NO;
   if(field<=2){if(!Varint(b,n,&at,&v)||v>UINT32_MAX)return NO;if(field==1)*version=v;else *type=v;}
   else{if(!Varint(b,n,&at,&v)||v>n-at)return NO;NSRange r=NSMakeRange(at,(NSUInteger)v);at+=(NSUInteger)v;if(field==3)*json=r;else *data=r;}
  }else{
   switch(wire){
    case 0:if(!Varint(b,n,&at,&v))return NO;break;
    case 1:if(n-at<8)return NO;at+=8;break;
    case 2:if(!Varint(b,n,&at,&v)||v>n-at)return NO;at+=(NSUInteger)v;break;
    case 5:if(n-at<4)return NO;at+=4;break;
    default:return NO;
   }
  }
 }
 // Business envelopes in this protocol are version 1 with a type; fields are bounded like Lane T's reader.
 return *version==1&&(seen&4)&&json->length<=65536&&data->length<=65536;
}
static NSDictionary *EnvelopeJSON(NSData *d){uint64_t v,t;NSRange j,b;if(!Envelope(d,&v,&t,&j,&b)||j.location==NSNotFound||!j.length)return nil;id o=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:j] options:0 error:nil];return [o isKindOfClass:NSDictionary.class]?o:nil;}
NSDictionary *TIOClenchParseEnvelope(NSData *d){
 uint64_t version,type;NSRange json,data;if(!Envelope(d,&version,&type,&json,&data))return nil;
 NSMutableDictionary *r=[@{@"type":@(type),@"messageBytes":json.location==NSNotFound?NSNull.null:@(json.length),@"dataBytes":data.location==NSNotFound?NSNull.null:@(data.length),@"vpuMask":NSNull.null,@"vadMask":NSNull.null} mutableCopy];
 NSDictionary *j=EnvelopeJSON(d);
 if(j){NSNumber *vpu=Integer(j[@"vpuMask"]),*vad=Integer(j[@"vadMask"]),*frames=Integer(j[@"frameCount"]),*mode=Integer(j[@"mode"]);
  if(vpu)r[@"vpuMask"]=vpu;if(vad)r[@"vadMask"]=vad;if(frames&&frames.longLongValue>=0&&frames.longLongValue<=1000000)r[@"frameCount"]=frames;if(mode)r[@"mode"]=mode;if(Safe(j[@"taskId"],128))r[@"taskId"]=j[@"taskId"];}
 return r;
}
NSData *TIOClenchFrame(NSData *e){if(![e isKindOfClass:NSData.class]||!e.length||e.length>UINT32_MAX)return nil;uint32_t n=(uint32_t)e.length;uint8_t p[4]={n&255,(n>>8)&255,(n>>16)&255,(n>>24)&255};NSMutableData *d=[NSMutableData dataWithBytes:p length:4];[d appendData:e];return d;}
NSData *TIOClenchWakeupPacket(NSInteger mode){
 if(mode!=0&&mode!=1)return nil;
 NSMutableData *d=[TIOA2UIPacket(16,0,@{@"cmd":@"set_ai_voice_wakeup",@"payload":@{@"data":@"",@"mode":@(mode),@"value":@0}}) mutableCopy];if(!d)return nil;
 const uint8_t tail[2]={0x22,0x00};[d appendBytes:tail length:2];return d;
}

#pragma mark Official dump config and events
NSDictionary *TIOClenchDumpConfig(NSDictionary *s){
 if(![s isKindOfClass:NSDictionary.class])return nil;NSArray *keys=@[@"dumpEnabled",@"dumpRealtimeAudio",@"dumpCachedAudio",@"dumpEvents"],*names=@[@"enabled",@"realtime",@"cached",@"events"];
 NSMutableDictionary *c=[NSMutableDictionary new];for(NSUInteger i=0;i<keys.count;i++){id v=s[keys[i]];if(![v isKindOfClass:NSNumber.class])return nil;c[names[i]]=@([v boolValue]);}return c;
}
// S2-03: cached-kind files have unverified provenance and are never attached, so the Lab does not force cached audio on;
// it keeps the user's prior cached setting.
static NSDictionary *LabDump(NSDictionary *prior){return @{@"enabled":@YES,@"realtime":@YES,@"cached":@([prior[@"cached"] boolValue]),@"events":@YES};}
static NSDictionary *ValidConfig(id c){if(![c isKindOfClass:NSDictionary.class]||[c count]!=4)return nil;NSMutableDictionary *o=[NSMutableDictionary new];for(NSString *k in @[@"enabled",@"realtime",@"cached",@"events"]){if(![c[k] isKindOfClass:NSNumber.class])return nil;o[k]=@([c[k] boolValue]);}return o;}
static NSArray *TimeKeys(void){return @[@"eventTsMs",@"eventTs",@"timestampMs",@"timestamp",@"tsMs",@"ts",@"timeMs",@"time"];}
static NSSet *CountKeys(void){static NSSet *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSSet setWithArray:@[@"vpuMask",@"vadMask",@"vpuOn",@"vadStart",@"hasVpuVad",@"frameCount",@"frames",@"bytes",@"byteCount",@"dataBytes",@"audioBytes",@"packetBytes",@"encodedBytes",@"opusBytes",@"packetCount",@"packets",@"realtimePackets",@"cachedPackets",@"seq",@"sequence",@"index"]];});return s;}
static NSSet *TagKeys(void){static NSSet *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSSet setWithArray:@[@"type",@"event",@"eventType",@"source",@"kind",@"taskId"]];});return s;}
// The key name decides the unit before the value's magnitude: ...Ms is epoch milliseconds only, ...Sec/...Secs/...Seconds
// is epoch seconds only, and only a unit-less name (eventTs, timestamp, ts, time) falls back to magnitude. ISO 8601
// strings carry their own unit. *rank (optional) scores how anchorable the reading is: 4 epoch ms under an ms name,
// 3 epoch-ms magnitude under a unit-less name, 2 epoch seconds, 1 ISO string, 0 unusable.
static double EventMs(NSString *key,id v,int *rank){
 if(rank)*rank=0;BOOL ms=[key hasSuffix:@"Ms"],sec=[key hasSuffix:@"Sec"]||[key hasSuffix:@"Secs"]||[key hasSuffix:@"Seconds"];
 if([v isKindOfClass:NSNumber.class]&&!IsCFBool(v)){double d=[v doubleValue];if(!isfinite(d))return NAN;BOOL msRange=d>1e11&&d<1e14,secRange=d>1e8&&d<1e11;
  if(ms){if(!msRange)return NAN;if(rank)*rank=4;return d;}
  if(sec){if(!secRange)return NAN;if(rank)*rank=2;return d*1000;}
  if(msRange){if(rank)*rank=3;return d;}if(secRange){if(rank)*rank=2;return d*1000;}return NAN;}
 if([v isKindOfClass:NSString.class]&&[v length]<=40){NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];NSDate *t=[f dateFromString:v];if(!t){f.formatOptions|=NSISO8601DateFormatWithFractionalSeconds;t=[f dateFromString:v];}if(!t)return NAN;if(rank)*rank=1;return t.timeIntervalSince1970*1000;}
 return NAN;
}
// The best time key of an event: highest rank, then TimeKeys order. nil when none is usable.
static NSString *BestTimeKey(NSDictionary *e,double *outMs){
 NSString *best=nil;int bestRank=0;double bestMs=NAN;
 for(NSString *k in TimeKeys()){if(!e[k])continue;int r=0;double ms=EventMs(k,e[k],&r);if(!isnan(ms)&&r>bestRank){best=k;bestRank=r;bestMs=ms;}}
 if(outMs)*outMs=bestMs;return best;
}
// Allow list, never a block list: anything not named here (text, payload, nested objects) is dropped. Only the best time
// key is kept, so a reader that takes the first time key present (Lane T) reads the same timestamp the window used.
// Kept values carry Lane T's types, so one odd event never makes the whole session undecodable: counts are booleans or
// integers (int64/uint64; an integral float is written as an integer, a fractional one is dropped), tags are safe strings
// up to 64 characters or integers 0...UINT32_MAX.
static NSDictionary *FilterEvent(id e,double startMs,double endMs,NSMutableDictionary *dropped,NSString **why){
 if(![e isKindOfClass:NSDictionary.class]){if(why)*why=@"unparseable";return nil;}
 double ms=NAN;NSString *timeKey=BestTimeKey(e,&ms);
 if(!timeKey){if(why)*why=@"withoutTime";return nil;}
 if(ms<startMs||ms>endMs){if(why)*why=@"outsideWindow";return nil;}
 NSMutableDictionary *o=[NSMutableDictionary new];
 for(id key in e){id v=e[key];BOOL keep=NO;
  if([key isKindOfClass:NSString.class]&&[TimeKeys() containsObject:key])keep=[key isEqual:timeKey];
  else if([CountKeys() containsObject:key]){if(IsCFBool(v))keep=YES;else if((v=Integer(v)))keep=YES;}
  else if([TagKeys() containsObject:key]){if(Safe(v,64))keep=YES;else{NSNumber *n=Integer(v);keep=n&&n.doubleValue>=0&&n.doubleValue<=UINT32_MAX;if(keep)v=n;}}
  if(keep)o[key]=v;else if(dropped){NSString *name=Safe(key,64)?key:@"(other)";if(dropped.count<64||dropped[name])dropped[name]=@([dropped[name] integerValue]+1);}
 }
 return o;
}
NSDictionary *TIOClenchFilterOfficialEvent(id e,NSDate *start,NSDate *end){return FilterEvent(e,start.timeIntervalSince1970*1000,end.timeIntervalSince1970*1000,nil,NULL);}

#pragma mark Local storage (0700/0600, O_EXCL|O_NOFOLLOW, file protection, excluded from backup)
static void Protect(NSURL *u,BOOL dir){
 [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:u.path error:nil];
 if(dir)[u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
}
static BOOL RealDir(NSURL *u){struct stat s;return u&&!lstat(u.fileSystemRepresentation,&s)&&S_ISDIR(s.st_mode);}
static BOOL SecureRoot(NSURL *root){
 if(!root.isFileURL)return NO;NSURL *parent=root.URLByDeletingLastPathComponent;
 if(!RealDir(parent)&&![NSFileManager.defaultManager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return NO;
 if(!RealDir(root)){struct stat s;if(!lstat(root.fileSystemRepresentation,&s))return NO;if(mkdir(root.fileSystemRepresentation,0700))return NO;}
 if(chmod(root.fileSystemRepresentation,0700))return NO;Protect(root,YES);return RealDir(root);
}
static BOOL NewDir(NSURL *u){if(mkdir(u.fileSystemRepresentation,0700)||chmod(u.fileSystemRepresentation,0700))return NO;Protect(u,YES);return RealDir(u);}
static int NewFile(NSURL *u){int fd=open(u.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(fd>=0){fchmod(fd,0600);Protect(u,NO);}return fd;}
static BOOL WriteAll(int fd,const void *bytes,size_t n){const uint8_t *p=bytes;while(n){ssize_t k=write(fd,p,n);if(k<0&&errno==EINTR)continue;if(k<=0)return NO;p+=k;n-=(size_t)k;}return YES;}
static BOOL WriteAtomic(NSURL *dir,NSString *name,NSData *data){
 if(!data||!RealDir(dir))return NO;NSURL *tmp=[dir URLByAppendingPathComponent:[NSString stringWithFormat:@".%@.%@.tmp",name,NSUUID.UUID.UUIDString]],*final=[dir URLByAppendingPathComponent:name];
 int fd=NewFile(tmp);if(fd<0)return NO;BOOL ok=WriteAll(fd,data.bytes,data.length)&&!fsync(fd);close(fd);
 ok=ok&&!rename(tmp.fileSystemRepresentation,final.fileSystemRepresentation);if(!ok)unlink(tmp.fileSystemRepresentation);else Protect(final,NO);return ok;
}
static NSData *JSONData(id o){return [NSJSONSerialization isValidJSONObject:o]?[NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil]:nil;}
static NSData *ReadSmall(NSURL *u,off_t limit){
 int fd=open(u.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);struct stat s;if(fd<0)return nil;if(fstat(fd,&s)||!S_ISREG(s.st_mode)||s.st_size>limit){close(fd);return nil;}
 NSMutableData *d=[NSMutableData dataWithLength:(NSUInteger)s.st_size];size_t got=0;while(got<(size_t)s.st_size){ssize_t k=read(fd,(uint8_t *)d.mutableBytes+got,(size_t)s.st_size-got);if(k<0&&errno==EINTR)continue;if(k<=0)break;got+=(size_t)k;}close(fd);return got==(size_t)s.st_size?d:nil;
}
static NSDictionary *ReadJSON(NSURL *u){NSData *d=ReadSmall(u,4*1024*1024);id o=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;return [o isKindOfClass:NSDictionary.class]?o:nil;}
static NSString *SHA256File(NSURL *u){
 int fd=open(u.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return nil;CC_SHA256_CTX c;CC_SHA256_Init(&c);uint8_t buf[65536];ssize_t k;BOOL ok=YES;
 while((k=read(fd,buf,sizeof buf))!=0){if(k<0){if(errno==EINTR)continue;ok=NO;break;}CC_SHA256_Update(&c,buf,(CC_LONG)k);}close(fd);if(!ok)return nil;
 unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(h,&c);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof h;i++)[s appendFormat:@"%02x",h[i]];return s;
}
static BOOL SessionName(NSString *n){return [n isKindOfClass:NSString.class]&&n.length==36&&[n isEqual:n.lowercaseString]&&[[NSUUID alloc]initWithUUIDString:n]!=nil;}
NSURL *TIOClenchDefaultRoot(void){return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ClenchLab"] isDirectory:YES];}
NSURL *TIOClenchDefaultExportRoot(void){return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/TurboIOPrivateAddon/ClenchExports"] isDirectory:YES];}
// Every post-capture manifest update (UI status, retry, attach) is one read-modify-write under one process-wide lock,
// so two panels or a background attach cannot overwrite each other's keys.
static NSObject *ManifestLock(void){static NSObject *o;static dispatch_once_t once;dispatch_once(&once,^{o=[NSObject new];});return o;}
static NSObject *AttachLock(void){static NSObject *o;static dispatch_once_t once;dispatch_once(&once,^{o=[NSObject new];});return o;}
static BOOL EditManifest(NSURL *dir,void(^edit)(NSMutableDictionary *m)){
 @synchronized(ManifestLock()){NSDictionary *m=ReadJSON([dir URLByAppendingPathComponent:@"manifest.json"]);if(!m)return NO;NSMutableDictionary *x=[m mutableCopy];edit(x);return WriteAtomic(dir,@"manifest.json",JSONData(x));}
}
BOOL TIOClenchMergeManifest(NSURL *dir,NSDictionary *updates){if(![updates isKindOfClass:NSDictionary.class])return NO;return EditManifest(dir,^(NSMutableDictionary *m){[m addEntriesFromDictionary:updates];});}

// Session in-use registry (attach, zip, a pending attach): a delete is refused while a session is registered.
static NSObject *WorkLock(void){static NSObject *o;static dispatch_once_t once;dispatch_once(&once,^{o=[NSObject new];});return o;}
static NSCountedSet *Work(void){static NSCountedSet *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSCountedSet new];});return s;}
static NSString *WorkKey(NSURL *u){NSString *n=u.lastPathComponent;return SessionName(n)?n:nil;}
void TIOClenchBeginSessionWork(NSURL *u){NSString *k=WorkKey(u);if(!k)return;@synchronized(WorkLock()){[Work() addObject:k];}}
void TIOClenchEndSessionWork(NSURL *u){NSString *k=WorkKey(u);if(!k)return;@synchronized(WorkLock()){[Work() removeObject:k];}}
BOOL TIOClenchSessionInUse(NSURL *u){NSString *k=WorkKey(u);if(!k)return NO;@synchronized(WorkLock()){return [Work() countForObject:k]>0;}}
#pragma mark Official files
static NSURL *OfficialSessions(NSURL *home){NSURL *docs=[home URLByAppendingPathComponent:@"Documents"],*base=[docs URLByAppendingPathComponent:@"always_on_debug"],*root=[base URLByAppendingPathComponent:@"sessions"];return RealDir(docs)&&RealDir(base)&&RealDir(root)?root:nil;}
static NSString *Relative(NSURL *u,NSURL *root){NSString *p=[u URLByResolvingSymlinksInPath].path,*r=[[root URLByResolvingSymlinksInPath].path stringByAppendingString:@"/"];return [p hasPrefix:r]?[p substringFromIndex:r.length]:nil;}
static NSDictionary *Identity(NSURL *u){struct stat s;if(lstat(u.fileSystemRepresentation,&s)||!S_ISREG(s.st_mode))return nil;return @{@"ino":@((unsigned long long)s.st_ino),@"size":@((long long)s.st_size),@"mtime":@((double)s.st_mtimespec.tv_sec+s.st_mtimespec.tv_nsec/1e9),@"birth":@((double)s.st_birthtimespec.tv_sec+s.st_birthtimespec.tv_nsec/1e9)};}
// Official audio in the same scope as TIOAOAudioFiles (sessions/ up to two folders deep, no hidden or symlinked entries,
// ogg/opus/pcm regular files up to 1 GiB) without its 500-row display cap, earliest born first. The walk is bounded by
// EnumerationCap entries; hitting it sets *truncated.
static NSArray<NSDictionary *> *OfficialAudio(NSURL *home,BOOL *truncated){
 *truncated=NO;NSMutableArray *rows=[NSMutableArray new];NSURL *root=OfficialSessions(home);if(!root)return rows;NSArray *keys=@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey];
 NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *u,NSError *x){return NO;}];NSUInteger seen=0;
 for(NSURL *f in e){if(++seen>EnumerationCap){*truncated=YES;break;}NSDictionary *v=[f resourceValuesForKeys:keys error:nil];NSString *rel=Relative(f,root);
  if([v[NSURLIsSymbolicLinkKey] boolValue]||!rel){[e skipDescendants];continue;}if([v[NSURLIsDirectoryKey] boolValue]){if(e.level>2)[e skipDescendants];continue;}
  if(![@[@"ogg",@"opus",@"pcm"] containsObject:f.pathExtension.lowercaseString])continue;NSDictionary *i=Identity(f);
  if(!i||[i[@"size"] longLongValue]<=0||[i[@"size"] longLongValue]>1024LL*1024*1024)continue;
  [rows addObject:@{@"url":f,@"name":f.lastPathComponent,@"rel":rel,@"identity":i}];}
 [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult r=[a[@"identity"][@"birth"] compare:b[@"identity"][@"birth"]];return r!=NSOrderedSame?r:[a[@"rel"] compare:b[@"rel"]];}];return rows;
}
// Start snapshot of every official audio file (bounded walk; a hit bound is recorded as truncated). Files missing from a
// truncated snapshot are still refused at attach time by their birth time, which predates the session window.
// targetKey (hashed glasses id) stays in this local sidecar, never in the exported manifest.
static NSDictionary *OfficialSnapshot(NSURL *home,NSString *device){
 NSMutableDictionary *files=[NSMutableDictionary new];BOOL truncated=NO;for(NSDictionary *row in OfficialAudio(home,&truncated))files[row[@"rel"]]=row[@"identity"];
 NSMutableDictionary *snap=[@{@"files":files,@"truncated":@(truncated)} mutableCopy];if(DeviceKey(device))snap[@"targetKey"]=DeviceKey(device);return snap;
}
// Every candidate is enumerated first (bounded). Only files modified at or after the window start can hold this
// session's events; the newest 32 of those are read. Either bound being hit is reported, never silent.
static NSArray<NSURL *> *EventFiles(NSURL *root,double sinceMs,BOOL *truncated){
 *truncated=NO;NSMutableArray *found=[NSMutableArray new];if(!root)return found;NSArray *keys=@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLContentModificationDateKey];
 NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *u,NSError *x){return NO;}];NSUInteger seen=0;
 for(NSURL *f in e){if(++seen>4000){*truncated=YES;break;}NSDictionary *v=[f resourceValuesForKeys:keys error:nil];
  if([v[NSURLIsSymbolicLinkKey] boolValue]){[e skipDescendants];continue;}if([v[NSURLIsDirectoryKey] boolValue]){if(e.level>2)[e skipDescendants];continue;}
  NSDate *date=v[NSURLContentModificationDateKey];if(![f.pathExtension.lowercaseString isEqual:@"jsonl"]||!Relative(f,root)||!date||date.timeIntervalSince1970*1000<sinceMs)continue;[found addObject:@[f,date]];}
 [found sortUsingComparator:^NSComparisonResult(NSArray *a,NSArray *b){return [b[1] compare:a[1]];}];
 if(found.count>32){*truncated=YES;[found removeObjectsInRange:NSMakeRange(32,found.count-32)];}
 NSMutableArray *out=[NSMutableArray new];for(NSArray *x in found)[out addObject:x[0]];
 [out sortUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){return [a.path compare:b.path];}];return out;
}
static NSDictionary *CopyEvents(NSURL *home,NSURL *dir,double startMs,double endMs){
 NSMutableData *out=[NSMutableData new];NSMutableDictionary *dropped=[NSMutableDictionary new],*why=[@{@"outsideWindow":@0,@"withoutTime":@0,@"unparseable":@0} mutableCopy];NSUInteger lines=0,count=0;BOOL truncated=NO;NSArray *files=EventFiles(OfficialSessions(home),startMs-WindowSlackMs,&truncated);
 for(NSURL *f in files){NSData *d=ReadSmall(f,16*1024*1024);if(!d){why[@"unparseable"]=@([why[@"unparseable"] integerValue]+1);continue;}
  const uint8_t *b=d.bytes;NSUInteger start=0;
  for(NSUInteger i=0;i<=d.length&&lines<200000&&count<100000;i++){if(i<d.length&&b[i]!='\n')continue;NSUInteger len=i-start;NSRange r=NSMakeRange(start,len);start=i+1;if(!len)continue;lines++;
   id o=len<=65536?[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:r] options:0 error:nil]:nil;NSString *reason=nil;NSDictionary *kept=FilterEvent(o,startMs,endMs,dropped,&reason);
   if(!kept){why[reason?:@"unparseable"]=@([why[reason?:@"unparseable"] integerValue]+1);continue;}
   NSData *j=[NSJSONSerialization dataWithJSONObject:kept options:NSJSONWritingSortedKeys error:nil];if(!j)continue;[out appendData:j];[out appendBytes:"\n" length:1];count++;}
 }
 if(!WriteAtomic(dir,@"official-events.jsonl",out))return nil;
 return @{@"state":@"attached",@"file":@"official-events.jsonl",@"count":@(count),@"scannedLines":@(lines),@"sourceFiles":@(files.count),@"sourceFilesTruncated":@(truncated),@"excluded":why,@"droppedKeyCounts":dropped,@"window":@{@"startMs":@(startMs),@"endMs":@(endMs)},@"filter":@"allow-list: timestamps, type/source tags, VPU/VAD flags and masks, frame/byte/packet counts, taskId"};
}
// Official files already listed by another Lab session (same path, and same inode when recorded) are never copied again.
static NSDictionary<NSString *,NSMutableSet *> *ClaimedElsewhere(NSURL *dir){
 NSMutableDictionary *claimed=[NSMutableDictionary new];
 for(NSDictionary *row in TIOClenchListSessions(dir.URLByDeletingLastPathComponent)){
  if([row[@"id"] isEqual:dir.lastPathComponent])continue;id list=row[@"manifest"][@"officialDump"];if(![list isKindOfClass:NSArray.class])continue;
  for(NSDictionary *e in list){if(![e isKindOfClass:NSDictionary.class]||![e[@"sourcePath"] isKindOfClass:NSString.class])continue;NSMutableSet *inos=claimed[e[@"sourcePath"]];if(!inos){inos=[NSMutableSet new];claimed[e[@"sourcePath"]]=inos;}[inos addObject:[e[@"sourceIno"] isKindOfClass:NSNumber.class]?e[@"sourceIno"]:NSNull.null];}
 }
 return claimed;
}
static void ExcludeFromBackup(NSURL *u){if(RealDir(u))[u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];}
// Only copy failures are retried (the writer may still have held the file); timing reasons are final.
static NSSet *RetryableSkips(void){return [NSSet setWithArray:@[@"copy-failed",@"move-failed",@"hash-failed"]];}
// The session's effective receive deadline in seconds from the manifest: the receive limit, or an earlier stop plus its
// tail (the capture's own -deadline). NAN when the manifest does not carry the receive limit.
static double SessionDeadline(NSDictionary *m){
 id limit=m[@"receiveLimitSeconds"],stop=m[@"stopRequestedAtSeconds"],limits=m[@"limits"],tail=[limits isKindOfClass:NSDictionary.class]?limits[@"stopTailSeconds"]:nil;if(![limit isKindOfClass:NSNumber.class]||IsCFBool(limit))return NAN;
 double d=[limit doubleValue];if([stop isKindOfClass:NSNumber.class]&&!IsCFBool(stop))d=MIN(d,[stop doubleValue]+([tail isKindOfClass:NSNumber.class]&&!IsCFBool(tail)?MAX(0,[tail doubleValue]):0));return isfinite(d)?MAX(0,d):NAN;
}
static NSDictionary *Attach(NSURL *dir,NSURL *home){
 NSDictionary *m=ReadJSON([dir URLByAppendingPathComponent:@"manifest.json"]),*snap=ReadJSON([dir URLByAppendingPathComponent:@"official-snapshot.json"]);NSDictionary *window=m[@"wallClockWindow"];
 if(!m||![window isKindOfClass:NSDictionary.class]||![window[@"startMs"] isKindOfClass:NSNumber.class]||![window[@"endMs"] isKindOfClass:NSNumber.class]||![snap[@"files"] isKindOfClass:NSDictionary.class]||isnan(SessionDeadline(m)))return nil;
 // Done means done: a repeat never copies anything, however much later it runs. "retry" (a copy failed last time)
 // runs again, keeps what was attached and adds only files not attached yet.
 NSInteger attempts=[m[@"officialAttachAttempts"] isKindOfClass:NSNumber.class]?[m[@"officialAttachAttempts"] integerValue]:0;BOOL retry=[m[@"officialAttach"] isEqual:@"retry"]&&attempts<MaxAttachAttempts;
 if([m[@"officialAttach"] isEqual:@"done"]||([m[@"officialAttach"] isEqual:@"retry"]&&!retry)){id events=m[@"officialEvents"];return @{@"files":@([m[@"officialDump"] count]),@"events":[events isKindOfClass:NSDictionary.class]&&[events[@"count"] isKindOfClass:NSNumber.class]?events[@"count"]:@0,@"skipped":@([m[@"officialDumpSkipped"] count]),@"alignment":@"unaligned",@"alreadyAttached":@YES,@"state":@"done"};}
 double startMs=[window[@"startMs"] doubleValue],endMs=[window[@"endMs"] doubleValue],fromMs=startMs-WindowSlackMs,toMs=endMs+WindowSlackMs;
 // S2-01: last writes count only up to the session's effective receive deadline in wall time (startWallMs + deadline x
 // 1000) plus FlushSlackMs, however long the restored dump kept the official writer going. When the official session was
 // seen stopped (else this attach's own time) is recorded as a diagnostic only; it never widens what is copied.
 double deadline=SessionDeadline(m),anchorMs=[m[@"startWallMs"] isKindOfClass:NSNumber.class]?[m[@"startWallMs"] doubleValue]:startMs,writeLimitMs=anchorMs+deadline*1000+FlushSlackMs;
 id observed=m[@"officialStopObservedMs"];BOOL seen=[observed isKindOfClass:NSNumber.class];double stopMs=seen?[observed doubleValue]:NSDate.date.timeIntervalSince1970*1000;
 NSURL *root=OfficialSessions(home);NSDictionary *before=snap[@"files"];NSDictionary *claimed=ClaimedElsewhere(dir);NSMutableArray *dump=[NSMutableArray new],*skipped=[NSMutableArray new];NSMutableSet *done=[NSMutableSet new];unsigned long long total=0;
 if(retry&&[m[@"officialDump"] isKindOfClass:NSArray.class])for(NSDictionary *e in m[@"officialDump"]){if(![e isKindOfClass:NSDictionary.class]||![e[@"sourcePath"] isKindOfClass:NSString.class])continue;[dump addObject:e];[done addObject:e[@"sourcePath"]];total+=[e[@"bytes"] unsignedLongLongValue];}
 BOOL truncated=NO;NSArray *rows=OfficialAudio(home,&truncated);NSUInteger candidates=0;NSURL *folder=[dir URLByAppendingPathComponent:@"official-dump" isDirectory:YES];
 NSURL *staging=[home URLByAppendingPathComponent:@"Documents/TurboIOAlwaysOnExports" isDirectory:YES];
 for(NSDictionary *row in rows){NSURL *u=row[@"url"];NSString *rel=root?row[@"rel"]:nil,*name=row[@"name"];NSDictionary *now=Identity(u),*old=rel?before[rel]:nil;if(!rel||!now||[done containsObject:rel])continue;
  double birthMs=[now[@"birth"] doubleValue]*1000,mtimeMs=[now[@"mtime"] doubleValue]*1000;
  // Open at Start (same path and inode): unchanged means none of this session's audio. When the dump was already on and
  // LifeLog already running, the official writer kept appending to this file during the window, but everything before
  // its size at Start is official audio from before the session (up to hours of LifeLog), which the user never agreed to
  // put in a Lab session or its share zip. Such a file is never copied; it is skipped with its reason and size at Start.
  if(old&&[old[@"ino"] isEqual:now[@"ino"]]){
   if([old isEqual:now])continue;
   BOOL grown=[now[@"size"] longLongValue]>[old[@"size"] longLongValue]&&mtimeMs>=fromMs;
   [skipped addObject:grown?@{@"originalName":name,@"reason":@"pre-existing-file-grown",@"sourceBytesAtStart":old[@"size"],@"containsAudioBeforeSession":@YES}:@{@"originalName":name,@"reason":@"pre-existing-file-changed"}];continue;
  }
  // Rows are earliest born first, so the cap on in-window candidates keeps this session's own files.
  if(birthMs>=fromMs&&++candidates>CandidateCap){truncated=YES;break;}
  // Only audio recorded for this session: born inside the window and last written by the effective deadline plus flush slack.
  NSString *outside=birthMs<fromMs?@"created-before-session":(birthMs>toMs?@"created-after-session":(mtimeMs>writeLimitMs?@"written-after-session":nil));
  if(outside){[skipped addObject:[outside isEqual:@"written-after-session"]?@{@"originalName":name,@"reason":outside,@"sourceModifiedMs":@(llround(mtimeMs))}:@{@"originalName":name,@"reason":outside}];continue;}
  NSSet *inos=claimed[rel];BOOL claimedElsewhere=[inos containsObject:NSNull.null]||[inos containsObject:now[@"ino"]];
  if(claimedElsewhere){[skipped addObject:@{@"originalName":name,@"reason":@"attached-to-another-session"}];continue;}
  // The session schema carries Ogg Opus copies only; raw PCM debug files are listed but not copied.
  if(![@[@"ogg",@"opus"] containsObject:u.pathExtension.lowercaseString]){[skipped addObject:@{@"originalName":name,@"reason":@"not-ogg-opus"}];continue;}
  // S2-03: a cached-kind file may hold audio the glasses cached before the session; its provenance is unverified, so it is
  // listed, never copied.
  NSString *lower=name.lowercaseString,*kind=[lower containsString:@"realtime"]?@"realtime":([lower containsString:@"cached"]?@"cached":@"unverified");
  if([kind isEqual:@"cached"]){[skipped addObject:@{@"originalName":name,@"reason":@"cached-provenance-unverified"}];continue;}
  if(dump.count>=DumpFileCap){[skipped addObject:@{@"originalName":name,@"reason":@"dump-cap-64-files"}];continue;}
  unsigned long long bytes=[now[@"size"] unsignedLongLongValue];if(total+bytes>DumpCap){[skipped addObject:@{@"originalName":name,@"reason":@"dump-cap-64MiB",@"bytes":@(bytes)}];continue;}
  if(!RealDir(folder)&&!NewDir(folder))return nil;
  // Verbatim research copy: the official bytes (sha256 equals the source's), legacy granule clock included; Lane T reads
  // either clock and takes durations from the packet TOC. It stages in Documents/TurboIOAlwaysOnExports/<uuid>/; keep
  // that staging area out of backups.
  ExcludeFromBackup(staging);NSError *error=nil;NSString *granules=nil;NSURL *copy=TIOAOAudioCopyVerbatim(home,u,&granules,&error);ExcludeFromBackup(staging);if(!copy){[skipped addObject:@{@"originalName":name,@"reason":@"copy-failed"}];continue;}
  NSString *ext=copy.pathExtension.lowercaseString;
  NSString *file=[NSString stringWithFormat:@"%02lu-%@.%@",(unsigned long)dump.count,kind,ext];NSURL *dest=[folder URLByAppendingPathComponent:file];
  BOOL moved=!rename(copy.fileSystemRepresentation,dest.fileSystemRepresentation);rmdir(copy.URLByDeletingLastPathComponent.fileSystemRepresentation);
  if(!moved){unlink(copy.fileSystemRepresentation);[skipped addObject:@{@"originalName":name,@"reason":@"move-failed"}];continue;}
  chmod(dest.fileSystemRepresentation,0600);Protect(dest,NO);NSDictionary *got=Identity(dest);NSString *sha=SHA256File(dest);if(!got||!sha){unlink(dest.fileSystemRepresentation);[skipped addObject:@{@"originalName":name,@"reason":@"hash-failed"}];continue;}
  total+=[got[@"size"] unsignedLongLongValue];[done addObject:rel];
  // Amendment 1a: always "unaligned". The decoder derives and reports its own alignment, never the manifest.
  [dump addObject:@{@"file":[@"official-dump/" stringByAppendingString:file],@"sourceKind":kind,@"bytes":got[@"size"],@"sha256":sha,@"copyFinalized":@([@[@"ogg",@"opus"] containsObject:ext]),@"alignment":@"unaligned",@"originalName":name,@"sourcePath":rel,@"sourceIno":now[@"ino"],@"sourceBirthMs":@(llround(birthMs)),@"sourceModifiedMs":@(llround(mtimeMs)),@"writtenAfterLabWindow":(mtimeMs>toMs?@YES:@NO),@"origin":@"new-in-window",@"copyVerbatim":@YES,@"granuleMode":granules?:NSNull.null}];
 }
 NSDictionary *events=CopyEvents(home,dir,startMs,endMs);if(!events)return nil;
 BOOL again=NO;for(NSDictionary *k in skipped)if([RetryableSkips() containsObject:k[@"reason"]])again=YES;attempts++;
 NSString *state=again&&attempts<MaxAttachAttempts?@"retry":@"done";
 NSDictionary *updates=@{@"officialDump":dump,@"officialDumpSkipped":skipped,@"officialEvents":events,@"officialAttach":state,@"officialAttachAttempts":@(attempts),@"officialAttachedAt":ISO(NSDate.date,NO),@"officialListingTruncated":@(truncated),
  @"officialAttachWindow":@{@"fromMs":@(fromMs),@"toMs":@(toMs),@"writeLimitMs":@(writeLimitMs),@"startWallMs":@(anchorMs),@"effectiveDeadlineSeconds":@(deadline),@"flushSlackMs":@(FlushSlackMs),@"officialStopMs":@(llround(stopMs)),@"officialStopSource":seen?@"observed":@"attach-time",@"slackMs":@(WindowSlackMs),
   @"rule":@"born inside the session wall-clock window; last written no later than startWallMs + effectiveDeadlineSeconds x 1000 + flushSlackMs; cached-kind files never copied; officialStopMs is a diagnostic only"},@"officialSnapshotTruncated":@([snap[@"truncated"] boolValue])};
 if(!TIOClenchMergeManifest(dir,updates))return nil;
 return @{@"files":@(dump.count),@"events":events[@"count"],@"skipped":@(skipped.count),@"alignment":@"unaligned",@"state":state};
}
// Attaches run one at a time process-wide, so two panels cannot copy into the same session concurrently.
// The session is registered in use for the whole attach, so a delete is refused until it ends.
NSDictionary *TIOClenchAttachOfficial(NSURL *dir,NSURL *home){
 NSString *k=WorkKey(dir);if(!k)return nil;
 @synchronized(WorkLock()){if(!RealDir(dir))return nil;[Work() addObject:k];}
 NSDictionary *r;@synchronized(AttachLock()){r=Attach(dir,home);}TIOClenchEndSessionWork(dir);return r;
}

#pragma mark Sessions, delete and zip
static const NSUInteger ListCap=200;
// Creation time of a session folder: its birth time (mkdir at Start, the same instant as createdAt). Manifest writes,
// attaches and status updates change the folder's modification time, never its birth time.
static double Birth(NSURL *u){struct stat s;if(lstat(u.fileSystemRepresentation,&s))return 0;double b=(double)s.st_birthtimespec.tv_sec+s.st_birthtimespec.tv_nsec/1e9;return b>0?b:(double)s.st_mtimespec.tv_sec+s.st_mtimespec.tv_nsec/1e9;}
NSArray<NSDictionary *> *TIOClenchListSessions(NSURL *root){
 NSMutableArray *found=[NSMutableArray new];if(!RealDir(root))return found;
 for(NSURL *u in [NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]?:@[]){
  if(!SessionName(u.lastPathComponent)||!RealDir(u))continue;[found addObject:@[@(Birth(u)),u]];}
 // Sort every folder by creation first, then cap: the newest sessions are always listed.
 [found sortUsingComparator:^NSComparisonResult(NSArray *a,NSArray *b){NSComparisonResult r=[b[0] compare:a[0]];return r!=NSOrderedSame?r:[[b[1] lastPathComponent] compare:[a[1] lastPathComponent]];}];
 if(found.count>ListCap)[found removeObjectsInRange:NSMakeRange(ListCap,found.count-ListCap)];
 NSMutableArray *rows=[NSMutableArray new];
 for(NSArray *x in found){NSURL *u=x[1];NSDictionary *m=ReadJSON([u URLByAppendingPathComponent:@"manifest.json"]);
  NSMutableDictionary *r=[@{@"id":u.lastPathComponent,@"url":u,@"complete":(m?@YES:@NO),@"createdEpoch":x[0]} mutableCopy];if(m)r[@"manifest"]=m;[rows addObject:r];}
 return rows;
}
BOOL TIOClenchDeleteSession(NSURL *root,NSURL *s){
 if(!RealDir(root)||!RealDir(s)||!SessionName(s.lastPathComponent))return NO;
 if(![[s URLByDeletingLastPathComponent].URLByResolvingSymlinksInPath.path isEqual:root.URLByResolvingSymlinksInPath.path])return NO;
 // Checked and removed under the registry lock, so an attach cannot begin on this folder halfway through the delete.
 @synchronized(WorkLock()){if([Work() countForObject:s.lastPathComponent])return NO;return [NSFileManager.defaultManager removeItemAtURL:s error:nil];}
}
static void Put16(NSMutableData *d,uint32_t v){uint8_t b[2]={v&255,(v>>8)&255};[d appendBytes:b length:2];}
static void Put32(NSMutableData *d,uint32_t v){uint8_t b[4]={v&255,(v>>8)&255,(v>>16)&255,(v>>24)&255};[d appendBytes:b length:4];}
static BOOL ZipHeader(NSMutableData *d,BOOL central,NSString *name,uint32_t crc,uint32_t size,uint32_t offset){
 NSData *n=[name dataUsingEncoding:NSASCIIStringEncoding];if(!n.length||n.length>255)return NO;
 Put32(d,central?0x02014b50:0x04034b50);if(central)Put16(d,(3<<8)|20);Put16(d,20);Put16(d,0);Put16(d,0);Put16(d,0);Put16(d,0x21);
 Put32(d,crc);Put32(d,size);Put32(d,size);Put16(d,(uint32_t)n.length);Put16(d,0);
 if(central){Put16(d,0);Put16(d,0);Put16(d,0);Put32(d,((uint32_t)(S_IFREG|0600))<<16);Put32(d,offset);}
 [d appendData:n];return YES;
}
// Each source is read twice (CRC pass, copy pass) and must not change in between.
static BOOL ZipEntry(int out,NSURL *src,NSString *name,uint64_t *offset,NSMutableData *central){
 int fd=open(src.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);struct stat a,b;if(fd<0)return NO;if(fstat(fd,&a)||!S_ISREG(a.st_mode)||a.st_size>96LL*1024*1024){close(fd);return NO;}
 uint8_t buf[65536];ssize_t k;uLong crc=crc32(0,Z_NULL,0);off_t seen=0;BOOL ok=YES;
 while((k=read(fd,buf,sizeof buf))!=0){if(k<0){if(errno==EINTR)continue;ok=NO;break;}crc=crc32(crc,buf,(uInt)k);seen+=k;}
 ok=ok&&seen==a.st_size&&lseek(fd,0,SEEK_SET)==0;NSMutableData *h=[NSMutableData new];ok=ok&&*offset+(uint64_t)a.st_size<UINT32_MAX&&ZipHeader(h,NO,name,(uint32_t)crc,(uint32_t)a.st_size,0)&&WriteAll(out,h.bytes,h.length);
 uLong again=crc32(0,Z_NULL,0);off_t copied=0;
 while(ok&&(k=read(fd,buf,sizeof buf))!=0){if(k<0){if(errno==EINTR)continue;ok=NO;break;}again=crc32(again,buf,(uInt)k);copied+=k;ok=WriteAll(out,buf,(size_t)k);}
 ok=ok&&!fstat(fd,&b)&&copied==a.st_size&&b.st_size==a.st_size&&again==crc;close(fd);
 if(ok){ok=ZipHeader(central,YES,name,(uint32_t)crc,(uint32_t)a.st_size,(uint32_t)*offset);*offset+=h.length+(uint64_t)a.st_size;}return ok;
}
static NSURL *Zip(NSURL *dir,NSURL *exportRoot){
 NSString *sid=dir.lastPathComponent;if(!SessionName(sid)||!RealDir(dir)||!ReadJSON([dir URLByAppendingPathComponent:@"manifest.json"]))return nil;
 NSMutableArray *entries=[NSMutableArray new];for(NSString *n in @[@"manifest.json",@"envelopes.rnp",@"official-events.jsonl"]){NSURL *u=[dir URLByAppendingPathComponent:n];struct stat s;if(!lstat(u.fileSystemRepresentation,&s)){if(!S_ISREG(s.st_mode))return nil;[entries addObject:@[u,n]];}else if(![n isEqual:@"official-events.jsonl"])return nil;}
 NSURL *folder=[dir URLByAppendingPathComponent:@"official-dump"];if(RealDir(folder)){NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
  for(NSString *n in names){if([n hasPrefix:@"."])continue;if(!Safe(n,64))return nil;NSURL *u=[folder URLByAppendingPathComponent:n];struct stat s;if(lstat(u.fileSystemRepresentation,&s)||!S_ISREG(s.st_mode))return nil;[entries addObject:@[u,[@"official-dump/" stringByAppendingString:n]]];}}
 if(!SecureRoot(exportRoot))return nil;NSURL *outDir=[exportRoot URLByAppendingPathComponent:NSUUID.UUID.UUIDString];if(!NewDir(outDir))return nil;
 NSURL *zip=[outDir URLByAppendingPathComponent:[NSString stringWithFormat:@"clench-%@.zip",sid]];int out=NewFile(zip);if(out<0){rmdir(outDir.fileSystemRepresentation);return nil;}
 NSMutableData *central=[NSMutableData new];uint64_t offset=0;BOOL ok=YES;
 for(NSArray *e in entries){ok=ZipEntry(out,e[0],[NSString stringWithFormat:@"clench-%@/%@",sid,e[1]],&offset,central);if(!ok)break;}
 if(ok){NSMutableData *end=[NSMutableData new];Put32(end,0x06054b50);Put16(end,0);Put16(end,0);Put16(end,(uint32_t)entries.count);Put16(end,(uint32_t)entries.count);Put32(end,(uint32_t)central.length);Put32(end,(uint32_t)offset);Put16(end,0);ok=WriteAll(out,central.bytes,central.length)&&WriteAll(out,end.bytes,end.length)&&!fsync(out);}
 close(out);if(!ok){[NSFileManager.defaultManager removeItemAtURL:outDir error:nil];return nil;}return zip;
}

// Registered in use while the zip is built, so a delete is refused until it ends.
NSURL *TIOClenchZipSession(NSURL *dir,NSURL *exportRoot){
 if(!WorkKey(dir))return nil;@synchronized(WorkLock()){if(!RealDir(dir))return nil;[Work() addObject:WorkKey(dir)];}
 NSURL *zip=Zip(dir,exportRoot);TIOClenchEndSessionWork(dir);return zip;
}

#pragma mark Tap (main-thread sink, atomic idle flag)
static _Atomic(bool) TapOn;
static __weak TIOClenchSession *TapSink;
BOOL TIOClenchTapActive(void){return atomic_load_explicit(&TapOn,memory_order_acquire);}
void TIOClenchTapChannel(id channel,NSUInteger bytes){
 if(!TIOClenchTapActive()||![channel isKindOfClass:NSString.class])return;NSString *name=[channel copy];
 void(^work)(void)=^{[TapSink noteChannel:name bytes:bytes];};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
void TIOClenchTapEvent(NSDictionary *event,NSTimeInterval arrival){
 if(!TIOClenchTapActive()||![event isKindOfClass:NSDictionary.class])return;
 id type=event[@"eventType"],m=event[@"message"];NSString *eventType=[type isKindOfClass:NSString.class]?[type copy]:@"(none)";NSNumber *business=nil;NSData *payload=nil;NSString *device=nil;
 if([eventType isEqual:@"messageReceived"]&&[m isKindOfClass:NSDictionary.class]){id b=m[@"businessId"],p=m[@"payload"],d=m[@"deviceId"];if(Integer(b))business=Integer(b);if([p isKindOfClass:NSData.class])payload=[p copy];if([d isKindOfClass:NSString.class])device=[d copy];}
 // Always hop asynchronously so file order equals arrival order; arrival was read at Send entry. The sink is taken now
 // (a weak load is thread-safe): a block that runs after finish still reaches the session, which counts the packet.
 TIOClenchSession *s=TapSink;if(!s)return;
 dispatch_async(dispatch_get_main_queue(),^{[s noteEventType:eventType];if(business)[s receiveBusiness:business.integerValue payload:payload device:device arrival:arrival];});
}

#pragma mark Session
@implementation TIOClenchConfig
+ (instancetype)standardConfig{
 TIOClenchConfig *c=[TIOClenchConfig new];c.root=TIOClenchDefaultRoot();c.officialHome=[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];c.defaults=NSUserDefaults.standardUserDefaults;
 c.clock=^{return NSProcessInfo.processInfo.systemUptime;};c.wallClock=^{return NSDate.date;};c.appCommit=TIOClenchBuildCommit();
 NSDictionary *i=NSBundle.mainBundle.infoDictionary;c.appVersion=[NSString stringWithFormat:@"%@ (%@)",i[@"CFBundleShortVersionString"]?:@"unknown",i[@"CFBundleVersion"]?:@"unknown"];return c;
}
- (instancetype)init{if((self=[super init])){_stopRequestLimit=120;_receiveLimit=125;_stopTail=5;_maxPackets=4096;_maxEnvelopeBytes=8ULL*1024*1024;_appVersion=@"unknown";_appCommit=@"unknown";}return self;}
@end

// A capture that died mid-session (crash, jetsam: no WillTerminate) left its last checkpoint manifest. envelopes.rnp may
// hold frames written after that checkpoint, which the manifest does not list (Lane T requires both to match), so the
// file is cut back to the checkpoint's byte count, once. A session in use (a live capture in this process) is never touched.
static void RecoverInterrupted(NSURL *root){
 for(NSDictionary *row in TIOClenchListSessions(root)){
  NSDictionary *m=row[@"manifest"],*cp=m[@"checkpoint"];NSURL *u=row[@"url"];
  if(![m[@"captureState"] isEqual:@"interrupted"]||![cp isKindOfClass:NSDictionary.class]||cp[@"recovered"]||![cp[@"envelopeFileBytes"] isKindOfClass:NSNumber.class]||TIOClenchSessionInUse(u))continue;
  unsigned long long keep=[cp[@"envelopeFileBytes"] unsignedLongLongValue];NSURL *rnp=[u URLByAppendingPathComponent:@"envelopes.rnp"];
  int fd=open(rnp.fileSystemRepresentation,O_WRONLY|O_NOFOLLOW|O_CLOEXEC);struct stat st;if(fd<0)continue;
  BOOL ok=!fstat(fd,&st)&&S_ISREG(st.st_mode)&&(unsigned long long)st.st_size>=keep&&((unsigned long long)st.st_size==keep||!ftruncate(fd,(off_t)keep))&&!fsync(fd);close(fd);if(!ok)continue;
  unsigned long long cut=(unsigned long long)st.st_size-keep;
  EditManifest(u,^(NSMutableDictionary *x){NSMutableDictionary *c=[x[@"checkpoint"] mutableCopy];c[@"recovered"]=@YES;c[@"envelopeBytesCut"]=@(cut);c[@"recoveredAt"]=ISO(NSDate.date,NO);x[@"checkpoint"]=c;});
 }
}

@interface TIOClenchSession(){
 int _fd;NSTimeInterval _t0,_stopAt,_lastArrival,_lastMark,_lastPacketAt,_lastCounterAt,_finalizedAt,_overrun,_lastCheckpoint;NSDate *_wallStart,*_wallEnd;
 NSMutableArray *_marks,*_packets,*_counters,*_log;NSMutableDictionary *_dropReasons,*_channels,*_eventTypes,*_business;
 unsigned long long _storedBytes;NSUInteger _clamped,_restoreAttempts;NSDictionary *_prior,*_restoreReadBack;BOOL _labDump,_restoreExact,_officialRunningSeen;NSString *_target,*_restoreOutcome;NSUInteger _notRunning,_observedNotRunning;
 NSDate *_officialStopWall;NSString *_settleDir;NSUInteger _settleCount;NSTimeInterval _settleT0;NSDate *_settleFirst;
 BOOL _idleHeld,_idlePrior,_idleUsed,_idleRestored,_idleSet;NSString *_idleOutcome;
}
@property(nonatomic,readwrite) TIOClenchPhase phase;
@property(nonatomic,readwrite,copy) NSString *sessionId,*label,*source,*stopBasis,*lastStopReason;
@property(nonatomic,readwrite) NSURL *directory;
@property(nonatomic,readwrite) BOOL offObserved,stopPending,dumpRestored;
@property(nonatomic,readwrite) NSTimeInterval durationSeconds;
@property(nonatomic,readwrite) NSDictionary *lastCounter,*pending,*restoreOwed;
@end
@implementation TIOClenchSession
- (instancetype)initWithConfig:(TIOClenchConfig *)config{
 if((self=[super init])){_config=config;_fd=-1;_stopAt=-1;id p=[config.defaults dictionaryForKey:PendingKey];_pending=[p isKindOfClass:NSDictionary.class]?p:nil;
  id o=[config.defaults dictionaryForKey:OwedKey];_restoreOwed=[o isKindOfClass:NSDictionary.class]?o:nil;if(config.root)RecoverInterrupted(config.root);}return self;
}
- (void)dealloc{
 if(_fd>=0)close(_fd);if(self.phase==TIOClenchPhaseCapturing&&self.directory)TIOClenchEndSessionWork(self.directory);if(!TapSink)atomic_store_explicit(&TapOn,false,memory_order_release);
 if(_idleHeld&&_idleSet&&self.config.setIdleTimerDisabled&&(!self.config.idleTimerDisabled||self.config.idleTimerDisabled()))self.config.setIdleTimerDisabled(NO);
}
- (BOOL)holdsIdleTimer{return _idleHeld;}
- (BOOL)wakeCommandAllowed{return self.phase!=TIOClenchPhaseCapturing;}
// Auto-lock would resign the app and end the capture; a real app switch or a manual lock still does. The Lab sets
// disabled=YES during capture (only when it is NO) and at the end sets it back to NO only if the Lab set it and it is still
// YES. Whatever ended the capture, the hold ends with it.
// Known limitation (C2-4/S2-02), shared with the MapKit navigation and camera holders, which save and restore the same
// flag: a holder that starts while the Lab holds it saves the Lab's YES and writes that back when it ends, so auto-lock
// can stay off after both have ended (until another holder or a relaunch resets it). If the Lab ends first it would turn
// auto-lock back on under that holder; idleTimerHeldElsewhere (camera live or navigation running on screen) makes the
// Lab leave the flag to it instead.
- (void)holdIdleTimer{
 if(_idleHeld||!self.config.setIdleTimerDisabled)return;_idlePrior=self.config.idleTimerDisabled?self.config.idleTimerDisabled():NO;_idleHeld=YES;_idleUsed=YES;_idleRestored=NO;_idleSet=NO;_idleOutcome=nil;
 if(_idlePrior){[self note:@"idle-timer already disabled by another holder; left alone"];return;}
 self.config.setIdleTimerDisabled(YES);_idleSet=YES;[self note:@"idle-timer disabled for capture"];
}
// Another holder that ended mid-capture put its saved "enabled" back: the Lab disables it again and now owns the hold.
- (void)keepIdleTimer{
 if(!_idleHeld||self.phase!=TIOClenchPhaseCapturing||!self.config.idleTimerDisabled||!self.config.setIdleTimerDisabled||self.config.idleTimerDisabled())return;
 self.config.setIdleTimerDisabled(YES);_idleSet=YES;[self note:@"idle-timer disabled again after another holder enabled it"];
}
- (void)releaseIdleTimer{
 if(!_idleHeld||self.phase==TIOClenchPhaseCapturing)return;_idleHeld=NO;_idleRestored=YES;
 if(!_idleSet){_idleOutcome=@"left-to-other-holder";[self note:@"idle-timer left to the holder that disabled it"];return;}
 BOOL still=self.config.idleTimerDisabled?self.config.idleTimerDisabled():YES;
 if(still&&self.config.idleTimerHeldElsewhere&&self.config.idleTimerHeldElsewhere()){_idleOutcome=@"left-to-active-holder";[self note:@"idle-timer left to the camera or navigation on screen"];return;}
 if(still&&self.config.setIdleTimerDisabled){self.config.setIdleTimerDisabled(NO);_idleOutcome=@"restored";[self note:@"idle-timer restored"];}
 else{_idleOutcome=@"already-enabled";[self note:@"idle-timer already enabled by another writer; left alone"];}
}
- (NSTimeInterval)now{return self.config.clock?self.config.clock():0;}
// C2-1 anchor: the monotonic clock and the wall clock read back to back, nothing in between, so the pair names one instant.
- (NSTimeInterval)nowWithWall:(NSDate **)wall{NSTimeInterval t=[self now];*wall=self.config.wallClock?self.config.wallClock():NSDate.date;return t;}
- (NSTimeInterval)deadline{NSTimeInterval d=self.config.receiveLimit;if(_stopAt>=0)d=MIN(d,_stopAt+self.config.stopTail);return d;}
- (NSUInteger)markCount{return _marks.count;}
- (NSUInteger)packetCount{return _packets.count;}
- (NSUInteger)droppedPackets{NSUInteger n=0;for(NSNumber *v in _dropReasons.allValues)n+=v.unsignedIntegerValue;return n;}
- (BOOL)stopRequested{return _stopAt>=0;}
- (NSTimeInterval)elapsed{return self.phase==TIOClenchPhaseCapturing?[self now]-_t0:self.durationSeconds;}
- (NSTimeInterval)remaining{if(self.phase!=TIOClenchPhaseCapturing)return 0;NSTimeInterval t=[self now]-_t0;return MAX(0,(_stopAt<0?self.config.stopRequestLimit:[self deadline])-t);}
- (void)changed_{if(self.changed)self.changed();}
- (void)note:(NSString *)what{if(_log.count<200)[_log addObject:@{@"t":@(R6(MAX(0,[self now]-_t0))),@"what":what}];}
- (void)drop:(NSString *)reason{_dropReasons[reason]=@([_dropReasons[reason] unsignedIntegerValue]+1);}
// Read-back is the truth: a configure call that returns YES but does not stick is a failed restore.
// Guarded (every restore except undoing a failed enable): the config is put back only while it is still the Lab's own.
// If the user changed official audio saving since Start, their latest choice stays and the outcome says so.
- (BOOL)restore:(NSDictionary *)prior guarded:(BOOL)guarded exact:(BOOL *)exact readBack:(NSDictionary **)readBack outcome:(NSString **)outcome{
 if(guarded){NSDictionary *cur=TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil);
  if(cur&&![cur isEqual:LabDump(prior)]){BOOL same=[cur isEqual:prior];if(readBack)*readBack=cur;if(exact)*exact=same;if(outcome)*outcome=same?@"already-prior":@"user-changed";return YES;}}
 _restoreAttempts++;BOOL called=self.config.dumpConfigure?self.config.dumpConfigure(prior):NO;(void)called;NSDictionary *now=TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil);
 if(readBack)*readBack=now;if(exact)*exact=now&&[now isEqual:prior];
 BOOL ok=now&&[now[@"enabled"] isEqual:prior[@"enabled"]]&&(![prior[@"enabled"] boolValue]||[now isEqual:prior]);if(outcome)*outcome=ok?@"restored":@"read-back-failed";return ok;
}
- (void)savePending:(NSDictionary *)p{
 BOOL open=p&&([p[@"stopPending"] boolValue]||([p[@"labDumpEnabled"] boolValue]&&![p[@"dumpRestored"] boolValue]&&!p[@"dumpRestoreWaived"]));
 self.pending=open?p:nil;if(open)[self.config.defaults setObject:p forKey:PendingKey];else [self.config.defaults removeObjectForKey:PendingKey];
}
- (void)syncPending{
 if(!self.sessionId)return;NSMutableDictionary *p=[@{@"sessionId":self.sessionId,@"prior":_prior?:@{},@"labDumpEnabled":@(_labDump),@"dumpRestored":@(self.dumpRestored),@"stopPending":@(self.stopPending),@"stopRequested":(_stopAt>=0?@YES:@NO)} mutableCopy];
 if(self.stopBasis)p[@"stopBasis"]=self.stopBasis;if(DeviceKey(_target))p[@"targetKey"]=DeviceKey(_target);[self savePending:p];
}
- (BOOL)targetConnected{NSString *d=self.config.device?self.config.device():nil;return _target.length&&[d isKindOfClass:NSString.class]&&[d isEqual:_target];}
// Post-capture: the official status counts only while the session's own glasses (hashed in the record) are connected.
- (BOOL)officialStoppedFor:(NSDictionary *)p{
 NSString *key=[p[@"targetKey"] isKindOfClass:NSString.class]?p[@"targetKey"]:nil,*now=DeviceKey(self.config.device?self.config.device():nil);if(!key||![now isEqual:key])return NO;
 id run=(self.config.dumpStatus?self.config.dumpStatus():nil)[@"alwaysOnRunning"];return [run isKindOfClass:NSNumber.class]&&![run boolValue];
}
- (NSString *)startWithLabel:(NSString *)label source:(NSString *)source{
 if(self.phase==TIOClenchPhaseCapturing)return @"busy";if(self.pending)return @"pending";
 if(![label isKindOfClass:NSString.class]||![TIOClenchLabels() containsObject:label])return @"label";if(!TIOClenchSourceSelectable(source))return @"source";
 NSString *device=self.config.device?self.config.device():nil;if(![device isKindOfClass:NSString.class]||!device.length)return @"device";
 NSDictionary *prior=TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil);if(!prior||!self.config.dumpConfigure)return @"dump-unavailable";
 // A waived restore is settled first: otherwise the config the Lab left on would be read as this session's prior. When it
 // cannot be read back, it becomes an open record again (retry path) and Start is refused.
 if(self.restoreOwed){if(![self settleOwed]){[self reopenOwed];return @"pending";}prior=TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil);if(!prior)return @"dump-unavailable";}
 NSString *sid=NSUUID.UUID.UUIDString.lowercaseString;NSURL *dir=[self.config.root URLByAppendingPathComponent:sid isDirectory:YES];
 if(!SecureRoot(self.config.root)||!NewDir(dir))return @"storage";
 int fd=NewFile([dir URLByAppendingPathComponent:@"envelopes.rnp"]);
 if(fd<0||!WriteAtomic(dir,@"official-snapshot.json",JSONData(OfficialSnapshot(self.config.officialHome,device)))){if(fd>=0)close(fd);[NSFileManager.defaultManager removeItemAtURL:dir error:nil];return @"storage";}
 // Persist before touching the official config so a crash between here and Stop leaves a recoverable record.
 // enableUnverified: a crash before the read-back below leaves a config that may be partly the Lab's; it is always undone.
 [self savePending:@{@"sessionId":sid,@"prior":prior,@"labDumpEnabled":@YES,@"dumpRestored":@NO,@"stopPending":@NO,@"stopRequested":@NO,@"targetKey":DeviceKey(device),@"enableUnverified":@YES}];
 _restoreAttempts=0;BOOL submitted=self.config.dumpConfigure(LabDump(prior));NSDictionary *after=TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil);
 if(!after||![after isEqual:LabDump(prior)]){
  close(fd);[NSFileManager.defaultManager removeItemAtURL:dir error:nil];BOOL exact=NO;BOOL restored=[self restore:prior guarded:NO exact:&exact readBack:NULL outcome:NULL];
  [self savePending:@{@"sessionId":sid,@"prior":prior,@"labDumpEnabled":@YES,@"dumpRestored":@(restored),@"stopPending":@NO,@"stopRequested":@NO,@"enableFailed":@YES}];return @"dump-enable-failed";
 }
 _fd=fd;_prior=prior;_labDump=YES;_restoreExact=NO;_restoreReadBack=nil;_stopAt=-1;_lastArrival=0;_lastMark=0;_lastPacketAt=-1;_lastCounterAt=-1;_overrun=0;_storedBytes=0;_clamped=0;_officialRunningSeen=NO;_notRunning=0;_observedNotRunning=0;_target=[device copy];_restoreOutcome=nil;_officialStopWall=nil;_settleDir=nil;_settleCount=0;_idleUsed=NO;_idleRestored=NO;
 _marks=[NSMutableArray new];_packets=[NSMutableArray new];_counters=[NSMutableArray new];_log=[NSMutableArray new];_dropReasons=[NSMutableDictionary new];_channels=[NSMutableDictionary new];_eventTypes=[NSMutableDictionary new];_business=[NSMutableDictionary new];
 self.directory=dir;self.sessionId=sid;self.label=label;self.source=source;self.offObserved=NO;self.stopPending=YES;self.dumpRestored=NO;self.stopBasis=nil;self.lastStopReason=nil;self.durationSeconds=0;self.lastCounter=nil;
 // C2-1: t0 and startWallMs come from one back-to-back read.
 NSDate *anchor=nil;_t0=[self nowWithWall:&anchor];_wallStart=anchor;_wallEnd=nil;self.phase=TIOClenchPhaseCapturing;TIOClenchBeginSessionWork(dir);
 [self note:submitted?@"dump-config lab (verified)":@"dump-config lab (verified; call returned NO)"];[self syncPending];[self holdIdleTimer];
 TapSink=self;atomic_store_explicit(&TapOn,true,memory_order_release);[self sample];[self checkpoint:0];[self changed_];return nil;
}
- (BOOL)mark{
 if(self.phase!=TIOClenchPhaseCapturing||_marks.count>=4096)return NO;NSTimeInterval t=[self now]-_t0;if(t<0||t>=[self deadline]||t>=self.config.receiveLimit)return NO;
 t=MAX(t,_lastMark);_lastMark=t;[_marks addObject:@{@"timeSeconds":@(R6(t))}];[self changed_];return YES;
}
// Counters are recorded only up to the effective deadline (the receive limit, or an earlier stop plus its tail), so every
// officialCounters[].t stays within durationSeconds. A later reading still informs the stop check below but is not stored.
// C2-1: the official status is read first, then the anchor pair (monotonic, wall) back to back; t and wallMs come from that
// pair, so a slow status call never skews wallMs-1000*t.
- (void)sample{
 NSDictionary *s=self.config.dumpStatus?self.config.dumpStatus():nil;id run=s[@"alwaysOnRunning"];NSDate *wall=nil;NSTimeInterval t=MAX(0,[self nowWithWall:&wall]-_t0);_lastCounterAt=t;
 if(t<=[self deadline]){
  NSDictionary *c=@{@"t":@(R6(t)),@"wallMs":@(llround(wall.timeIntervalSince1970*1000)),@"realtimePackets":Integer(s[@"realtimePackets"])?:NSNull.null,@"cachedPackets":Integer(s[@"cachedPackets"])?:NSNull.null,@"alwaysOnRunning":[run isKindOfClass:NSNumber.class]?@([run boolValue]):NSNull.null};
  if(_counters.count<1024)[_counters addObject:c];self.lastCounter=c;
 }
 // A NO reading clears the stop only after the prompt, with the session's glasses still connected, twice in a row.
 // After a link loss the phone-side state is not evidence that LifeLog stopped on the glasses.
 BOOL off=[run isKindOfClass:NSNumber.class]&&![run boolValue];if([run isKindOfClass:NSNumber.class]&&[run boolValue]){_officialRunningSeen=YES;_officialStopWall=nil;}
 if(off&&_stopAt>=0&&t>=_stopAt&&[self targetConnected]){if(!_officialStopWall)_officialStopWall=wall;if(++_notRunning>=NotRunningReadings)[self resolveStop:@"official-status-not-running"];}else _notRunning=0;
}
- (void)resolveStop:(NSString *)basis{if(!self.stopPending)return;self.stopPending=NO;if(!self.stopBasis)self.stopBasis=basis;[self note:[@"stop-resolved " stringByAppendingString:basis]];[self syncPending];}
- (void)tick{
 if(self.phase!=TIOClenchPhaseCapturing)return;NSTimeInterval t=[self now]-_t0;NSString *device=self.config.device?self.config.device():nil;
 if(![device isKindOfClass:NSString.class]||!device.length){[self lifecycleStop:@"device-lost"];return;}
 if(![device isEqual:_target]){[self lifecycleStop:@"device-changed"];return;}
 if(t-_lastCounterAt>=0.2)[self sample];[self keepIdleTimer];
 if(self.offObserved&&self.stopPending&&(_lastPacketAt<0||[self now]-_lastPacketAt>=3))[self resolveStop:@"protocol-life-log-switch-0"];
 if(_stopAt<0&&t>=self.config.stopRequestLimit)[self requestStop:@"limit-120s"];
 // A late tick catches up: the stop is requested once and storage still ends at the receive limit.
 if(self.phase==TIOClenchPhaseCapturing&&t>=[self deadline]){[self finish:t];return;}
 if(self.phase==TIOClenchPhaseCapturing&&t-_lastCheckpoint>=CheckpointSeconds)[self checkpoint:t];
 [self changed_];
}
- (void)requestStop:(NSString *)reason{
 if(self.phase!=TIOClenchPhaseCapturing||_stopAt>=0)return;_stopAt=MAX(0,[self now]-_t0);self.lastStopReason=reason;[self note:[@"stop-requested " stringByAppendingString:reason?:@""]];
 if(_labDump&&!self.dumpRestored){BOOL exact=NO;NSDictionary *rb=nil;NSString *outcome=nil;self.dumpRestored=[self restore:_prior guarded:YES exact:&exact readBack:&rb outcome:&outcome];_restoreExact=exact;_restoreReadBack=rb;_restoreOutcome=outcome;[self note:[@"dump-config " stringByAppendingString:outcome?:@"read-back-failed"]];}
 [self syncPending];if(self.stopPrompt)self.stopPrompt(self.dumpRestored);[self changed_];
}
- (void)lifecycleStop:(NSString *)reason{if(self.phase!=TIOClenchPhaseCapturing)return;[self requestStop:reason];[self finish:[self now]-_t0];}
// Crash insurance: the manifest as it stands, marked captureState "interrupted", with the wall-clock window up to now and
// the envelopes.rnp length it covers. A process that dies mid-capture (crash, jetsam) keeps its marks, packets, counters
// and window; the next launch cuts envelopes.rnp back to that length (RecoverInterrupted). finish overwrites it.
- (void)checkpoint:(NSTimeInterval)t{
 _lastCheckpoint=t;if(!self.directory||(_fd>=0&&fsync(_fd))){[self note:@"checkpoint-fsync-failed"];return;}
 NSMutableDictionary *m=[[self manifest] mutableCopy];NSDate *wall=self.config.wallClock?self.config.wallClock():NSDate.date;
 double lastPacket=[[_packets.lastObject objectForKey:@"arrivalSeconds"] doubleValue],lastCounter=[[_counters.lastObject objectForKey:@"t"] doubleValue];
 m[@"durationSeconds"]=@(R6(MIN([self deadline],MAX(MAX(MAX(0,t),_lastMark),MAX(lastPacket,lastCounter)))));m[@"captureState"]=@"interrupted";
 NSMutableDictionary *w=[m[@"wallClockWindow"] mutableCopy];w[@"endMs"]=@(ceil(wall.timeIntervalSince1970*1000));m[@"wallClockWindow"]=w;
 m[@"checkpoint"]=@{@"atSeconds":@(R6(t)),@"wallMs":@(llround(wall.timeIntervalSince1970*1000)),@"envelopeFileBytes":@(_storedBytes),@"everySeconds":@(CheckpointSeconds),@"note":@"written during capture: the capture never finished (the app ended). The window ends at this checkpoint; envelopes.rnp is cut back to envelopeFileBytes on the next launch."};
 if(!WriteAtomic(self.directory,@"manifest.json",JSONData(m)))[self note:@"checkpoint-write-failed"];
}
- (void)finish:(NSTimeInterval)t{
 if(self.phase!=TIOClenchPhaseCapturing)return;if(_stopAt<0)[self requestStop:@"finish"];
 // Storage ends at the effective deadline: the receive limit or an earlier stop plus its tail, whichever comes first.
 if(t-_lastCounterAt>=0.2)[self sample];
 if(TapSink==self){TapSink=nil;atomic_store_explicit(&TapOn,false,memory_order_release);}
 if(_fd>=0){if(fsync(_fd))[self note:@"fsync-failed"];close(_fd);_fd=-1;}
 double lastPacket=[[_packets.lastObject objectForKey:@"arrivalSeconds"] doubleValue];
 double lastCounter=[[_counters.lastObject objectForKey:@"t"] doubleValue];
 self.durationSeconds=R6(MAX(MIN(t,[self deadline]),MAX(MAX(lastPacket,_lastMark),lastCounter)));_overrun=MAX(0,t-[self deadline]);_finalizedAt=t;
 _wallEnd=self.config.wallClock?self.config.wallClock():NSDate.date;self.phase=TIOClenchPhaseFinished;[self releaseIdleTimer];
 if(self.offObserved&&(_lastPacketAt<0||[self now]-_lastPacketAt>=3))[self resolveStop:@"protocol-life-log-switch-0"];
 [self note:@"finished"];if(!WriteAtomic(self.directory,@"manifest.json",JSONData([self manifest])))[self note:@"manifest-write-failed"];
 TIOClenchEndSessionWork(self.directory);[self syncPending];[self changed_];
}
// A tap block queued while capturing can run after finish (the ticker, a deadline tick or a lifecycle stop ran first in
// that run-loop pass). An audio envelope that arrived before the capture ended is counted as a local drop in the written
// manifest, with the reason the capture would have given, or "arrived-before-finish-unprocessed". Later arrivals never count.
- (void)lateBusiness:(NSInteger)business device:(NSString *)device arrival:(NSTimeInterval)arrival{
 NSTimeInterval t=arrival-_t0;if(business!=13||!self.directory||t<0||t>=_finalizedAt)return;
 [self drop:device.length&&![device isEqual:_target]?@"other-device":(t>=[self deadline]?@"after-window":@"arrived-before-finish-unprocessed")];
 NSNumber *n=@(self.droppedPackets);NSDictionary *reasons=[_dropReasons copy];
 if(!EditManifest(self.directory,^(NSMutableDictionary *m){m[@"droppedPackets"]=n;m[@"dropReasons"]=reasons;}))return;[self changed_];
}
- (void)receiveBusiness:(NSInteger)business payload:(NSData *)payload device:(NSString *)device arrival:(NSTimeInterval)arrival{
 if(self.phase==TIOClenchPhaseFinished){[self lateBusiness:business device:device arrival:arrival];return;}
 if(self.phase!=TIOClenchPhaseCapturing)return;
 if(device.length&&![device isEqual:_target]){if(business==13)[self drop:@"other-device"];return;}
 NSString *key=[NSString stringWithFormat:@"%ld",(long)business];if(_business.count<64||_business[key])_business[key]=@([_business[key] unsignedIntegerValue]+1);
 NSTimeInterval t=arrival-_t0;if(t<0){if(business==13)[self drop:@"before-window"];return;}
 if(business==15){NSDictionary *j=EnvelopeJSON(payload);id cmd=j[@"cmd"],p=j[@"payload"];NSNumber *value=[p isKindOfClass:NSDictionary.class]?Integer(p[@"value"]):nil;
  if([cmd isKindOfClass:NSString.class]&&[cmd hasPrefix:@"life_log_"]&&Safe(cmd,64))[self note:[NSString stringWithFormat:@"inbound %@ value=%@",cmd,value?:@"none"]];
  // Protocol-proven off only: an inbound life_log_switch value 0 after the prompt. Results and send success never count.
  if([cmd isEqual:@"life_log_switch"]&&[value isEqual:@0]&&_stopAt>=0&&t>=_stopAt){self.offObserved=YES;if(_lastPacketAt<0||[self now]-_lastPacketAt>=3)[self resolveStop:@"protocol-life-log-switch-0"];}
  [self changed_];return;}
 if(business!=13)return;
 if(t>=[self deadline]){[self drop:@"after-window"];return;}
 if(!payload.length){[self drop:@"no-payload"];return;}
 NSDictionary *meta=TIOClenchParseEnvelope(payload);if(!meta){[self drop:@"unparseable"];return;}
 if(_packets.count>=self.config.maxPackets||_storedBytes+4+payload.length>self.config.maxEnvelopeBytes){[self drop:@"cap"];[self lifecycleStop:@"storage-cap"];return;}
 NSData *frame=TIOClenchFrame(payload);if(!frame||_fd<0||!WriteAll(_fd,frame.bytes,frame.length)){[self drop:@"write-error"];[self lifecycleStop:@"write-error"];return;}
 if(t<_lastArrival){t=_lastArrival;_clamped++;}_lastArrival=t;_storedBytes+=frame.length;_lastPacketAt=[self now];
 NSMutableDictionary *p=[@{@"index":@(_packets.count),@"arrivalSeconds":@(R6(t)),@"business":@13,@"envelopeBytes":@(payload.length)} mutableCopy];[p addEntriesFromDictionary:meta];[_packets addObject:p];[self changed_];
}
- (void)noteChannel:(NSString *)channel bytes:(NSUInteger)bytes{
 if(self.phase!=TIOClenchPhaseCapturing||![channel isKindOfClass:NSString.class])return;NSString *name=channel.length>96?[channel substringToIndex:96]:channel;if(_channels.count>=64&&!_channels[name])name=@"(other)";
 NSDictionary *c=_channels[name];_channels[name]=@{@"messages":@([c[@"messages"] unsignedIntegerValue]+1),@"bytes":@([c[@"bytes"] unsignedLongLongValue]+bytes)};
}
- (void)noteEventType:(NSString *)eventType{if(self.phase!=TIOClenchPhaseCapturing)return;NSString *name=Safe(eventType,64)?eventType:@"(other)";if(_eventTypes.count>=64&&!_eventTypes[name])name=@"(other)";_eventTypes[name]=@([_eventTypes[name] unsignedIntegerValue]+1);}
// restore (optional) is the outcome of a dump restore made for this record: {attempted, exact, readBack}. It is merged
// with dumpRestored so the manifest never says restored while keeping the failed read-back.
- (void)applyPending:(NSMutableDictionary *)p restore:(NSDictionary *)restore{
 NSString *sid=p[@"sessionId"];BOOL current=[sid isEqual:self.sessionId]&&self.phase==TIOClenchPhaseFinished;
 if(current){self.stopPending=[p[@"stopPending"] boolValue];self.dumpRestored=[p[@"dumpRestored"] boolValue];if(p[@"stopBasis"])self.stopBasis=p[@"stopBasis"];if(restore){_restoreExact=[restore[@"exact"] boolValue];_restoreReadBack=[restore[@"readBack"] isKindOfClass:NSDictionary.class]?restore[@"readBack"]:nil;if(restore[@"outcome"])_restoreOutcome=restore[@"outcome"];}}
 NSURL *dir=SessionName(sid)?[self.config.root URLByAppendingPathComponent:sid isDirectory:YES]:nil;
 if(dir&&RealDir(dir))EditManifest(dir,^(NSMutableDictionary *m){
  m[@"stopPending"]=@([p[@"stopPending"] boolValue]);m[@"dumpRestored"]=@([p[@"dumpRestored"] boolValue]);if(p[@"stopBasis"])m[@"stopBasis"]=p[@"stopBasis"];if(p[@"dumpRestoreWaived"])m[@"dumpRestoreWaived"]=p[@"dumpRestoreWaived"];
  if(restore){m[@"dumpRestoreExact"]=@([restore[@"exact"] boolValue]);NSMutableDictionary *c=[m[@"dumpConfig"] isKindOfClass:NSDictionary.class]?[m[@"dumpConfig"] mutableCopy]:[NSMutableDictionary new];
   c[@"restoreReadBack"]=restore[@"readBack"]?:NSNull.null;if([restore[@"configured"] boolValue])c[@"restoreAttempts"]=@([c[@"restoreAttempts"] integerValue]+1);m[@"dumpConfig"]=c;if(restore[@"outcome"])m[@"dumpRestoreOutcome"]=restore[@"outcome"];}
 });
 [self savePending:p];[self changed_];
}
// Restores the prior dump config of an unresolved record, with read-back. Never touches the stop state or the glasses.
- (NSDictionary *)restoreRecord:(NSMutableDictionary *)p{
 if(![p[@"labDumpEnabled"] boolValue]||[p[@"dumpRestored"] boolValue])return nil;NSDictionary *prior=ValidConfig(p[@"prior"]);BOOL exact=NO;NSDictionary *rb=nil;NSString *outcome=nil;NSUInteger calls=_restoreAttempts;
 // A failed enable is always undone; any other record restores only while the config is still the Lab's own.
 BOOL ok=prior&&[self restore:prior guarded:!([p[@"enableFailed"] boolValue]||[p[@"enableUnverified"] boolValue]) exact:&exact readBack:&rb outcome:&outcome];p[@"dumpRestored"]=@(ok);p[@"restoreRetries"]=@([p[@"restoreRetries"] integerValue]+1);if(outcome)p[@"dumpRestoreOutcome"]=outcome;
 NSMutableDictionary *r=[@{@"attempted":(prior?@YES:@NO),@"configured":(_restoreAttempts>calls?@YES:@NO),@"exact":(ok&&exact?@YES:@NO),@"readBack":rb?:NSNull.null} mutableCopy];if(outcome)r[@"outcome"]=outcome;return r;
}
- (BOOL)restorePendingDump{
 [self releaseIdleTimer]; // no-op unless a finished capture still held it
 if(self.phase==TIOClenchPhaseCapturing)return NO;BOOL clear=YES;NSMutableDictionary *p=[self.pending mutableCopy];
 if(p&&[p[@"labDumpEnabled"] boolValue]&&![p[@"dumpRestored"] boolValue]&&!p[@"dumpRestoreWaived"]){
  if(!TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil))clear=NO; // official interface not ready yet; try again later
  else{NSDictionary *r=[self restoreRecord:p];[self applyPending:p restore:r];clear=[p[@"dumpRestored"] boolValue];}
 }
 if(self.restoreOwed&&![self settleOwed])clear=NO;
 return clear;
}
// The waived restore (see restoreOwed): guarded like any other restore (put back only while the config is still the Lab's)
// unless the record was written before the enable was verified. YES when resolved: the record is dropped and the session
// manifest says so. NO while the official interface is unavailable or the read-back fails.
- (BOOL)settleOwed{
 NSDictionary *o=self.restoreOwed;if(!o)return YES;if(!TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil))return NO;
 NSDictionary *prior=ValidConfig(o[@"prior"]);BOOL exact=NO;NSDictionary *rb=nil;NSString *outcome=@"prior-unknown";
 if(prior&&![self restore:prior guarded:![o[@"unguarded"] boolValue] exact:&exact readBack:&rb outcome:&outcome])return NO;
 NSString *sid=o[@"sessionId"];NSURL *dir=SessionName(sid)?[self.config.root URLByAppendingPathComponent:sid isDirectory:YES]:nil;
 if(dir&&RealDir(dir))EditManifest(dir,^(NSMutableDictionary *m){
  m[@"dumpRestored"]=(prior?@YES:@NO);m[@"dumpRestoreExact"]=@(exact);m[@"dumpRestoreOutcome"]=outcome?:@"restored";m[@"dumpRestoredAfterWaiver"]=@YES;
  NSMutableDictionary *c=[m[@"dumpConfig"] isKindOfClass:NSDictionary.class]?[m[@"dumpConfig"] mutableCopy]:[NSMutableDictionary new];c[@"restoreReadBack"]=rb?:NSNull.null;m[@"dumpConfig"]=c;});
 if([sid isEqual:self.sessionId]&&self.phase==TIOClenchPhaseFinished)self.dumpRestored=prior!=nil;
 self.restoreOwed=nil;[self.config.defaults removeObjectForKey:OwedKey];[self changed_];return YES;
}
// Start found the waived restore still failing with the official interface available: it is an open record again, so the
// normal retry (and, should the interface vanish again, the waiver) applies.
- (void)reopenOwed{
 NSMutableDictionary *p=[self.restoreOwed[@"record"] isKindOfClass:NSDictionary.class]?[self.restoreOwed[@"record"] mutableCopy]:nil;if(!p)return;
 self.restoreOwed=nil;[self.config.defaults removeObjectForKey:OwedKey];[self savePending:p];[self changed_];
}
// Records the waived restore. An older owed record is kept: its prior is the user's own setting.
- (void)oweRestore:(NSDictionary *)p{
 if(self.restoreOwed)return;NSMutableDictionary *record=[p mutableCopy];[record removeObjectForKey:@"dumpRestoreWaived"];record[@"stopPending"]=@NO;
 NSDictionary *o=@{@"sessionId":p[@"sessionId"]?:@"",@"prior":p[@"prior"]?:@{},@"unguarded":([p[@"enableFailed"] boolValue]||[p[@"enableUnverified"] boolValue]?@YES:@NO),@"waived":p[@"dumpRestoreWaived"]?:@"",@"waivedAt":ISO(self.config.wallClock?self.config.wallClock():NSDate.date,NO),@"record":record};
 self.restoreOwed=o;[self.config.defaults setObject:o forKey:OwedKey];
}
- (BOOL)retryPending{
 if(!self.pending)return YES;if(self.phase==TIOClenchPhaseCapturing)return NO;NSMutableDictionary *p=[self.pending mutableCopy];
 NSDictionary *r=[self restoreRecord:p];
 // An explicit user retry reads the official status once, and only with the session's glasses connected.
 if([p[@"stopPending"] boolValue]&&[self officialStoppedFor:p]){p[@"stopPending"]=@NO;if(!p[@"stopBasis"])p[@"stopBasis"]=@"official-status-not-running";}
 [self applyPending:p restore:r];return self.pending==nil;
}
- (void)observeOfficialStatus{
 if(!self.pending||self.phase==TIOClenchPhaseCapturing||![self.pending[@"stopPending"] boolValue]){_observedNotRunning=0;return;}
 if(![self officialStoppedFor:self.pending]){_observedNotRunning=0;return;}if(++_observedNotRunning<NotRunningReadings)return;_observedNotRunning=0;
 NSMutableDictionary *p=[self.pending mutableCopy];p[@"stopPending"]=@NO;if(!p[@"stopBasis"])p[@"stopBasis"]=@"official-status-not-running";[self applyPending:p restore:nil];
}
- (BOOL)officialSettledForAttach:(NSURL *)dir{
 if(self.phase==TIOClenchPhaseCapturing||!RealDir(dir)){_settleDir=nil;return NO;}
 NSDictionary *snap=ReadJSON([dir URLByAppendingPathComponent:@"official-snapshot.json"]);NSString *key=[snap[@"targetKey"] isKindOfClass:NSString.class]?snap[@"targetKey"]:nil,*now=DeviceKey(self.config.device?self.config.device():nil);
 id run=(self.config.dumpStatus?self.config.dumpStatus():nil)[@"alwaysOnRunning"];BOOL off=[run isKindOfClass:NSNumber.class]&&![run boolValue];
 // A link loss reads NO on the phone while LifeLog may still run on the glasses: only the session's own glasses count.
 if(!off||!now||(key&&![key isEqual:now])){_settleDir=nil;_settleCount=0;return NO;}
 if(![_settleDir isEqual:dir.path]){_settleDir=dir.path;_settleCount=0;_settleT0=[self now];_settleFirst=self.config.wallClock?self.config.wallClock():NSDate.date;}
 if(++_settleCount<AttachSettleReadings||[self now]-_settleT0<AttachSettleSeconds)return NO;
 double ms=floor(_settleFirst.timeIntervalSince1970*1000);
 EditManifest(dir,^(NSMutableDictionary *m){if(![m[@"officialStopObservedMs"] isKindOfClass:NSNumber.class]){m[@"officialStopObservedMs"]=@(ms);m[@"officialStopObservedBy"]=@"attach-settle";}});
 return YES;
}
- (NSString *)attachGate:(NSURL *)dir{
 if(self.phase==TIOClenchPhaseCapturing)return @"capturing";NSDictionary *p=self.pending;
 if([p[@"sessionId"] isEqual:dir.lastPathComponent]&&[p[@"labDumpEnabled"] boolValue]&&![p[@"dumpRestored"] boolValue]&&!p[@"dumpRestoreWaived"])return @"dump-outstanding";
 if([self.restoreOwed[@"sessionId"] isEqual:dir.lastPathComponent])return @"dump-outstanding";
 NSDictionary *m=ReadJSON([dir URLByAppendingPathComponent:@"manifest.json"]);if(!m)return @"not-stopped";
 NSInteger attempts=[m[@"officialAttachAttempts"] isKindOfClass:NSNumber.class]?[m[@"officialAttachAttempts"] integerValue]:0;
 // Done (or retries used up): the attach only reports what is there and copies nothing, so no settle is needed.
 if([m[@"officialAttach"] isEqual:@"done"]||([m[@"officialAttach"] isEqual:@"retry"]&&attempts>=MaxAttachAttempts))return nil;
 if([self officialSettledForAttach:dir])return nil;return [_settleDir isEqual:dir.path]?@"settling":@"not-stopped";
}
- (BOOL)confirmPhysicalStop{
 if(!self.pending||self.phase==TIOClenchPhaseCapturing)return NO;NSMutableDictionary *p=[self.pending mutableCopy];NSString *sid=p[@"sessionId"];
 NSURL *dir=SessionName(sid)?[self.config.root URLByAppendingPathComponent:sid isDirectory:YES]:nil;
 if(dir&&RealDir(dir)&&!WriteAtomic(dir,@"stop-confirmation.json",JSONData(@{@"confirmedAt":ISO(self.config.wallClock?self.config.wallClock():NSDate.date,NO),@"source":@"user-observed-lifelog-off",@"protocolOffObserved":([sid isEqual:self.sessionId]&&self.offObserved?@YES:@NO),@"sessionId":sid})))return NO;
 if([p[@"stopPending"] boolValue]){p[@"stopPending"]=@NO;p[@"stopBasis"]=@"user-confirmed";}
 // Without the official interface a restore cannot be read back now; the waiver unblocks Start only. The restore stays
 // owed and is retried (launch, foreground, panel) until the official interface reads back.
 if([p[@"labDumpEnabled"] boolValue]&&![p[@"dumpRestored"] boolValue]&&!TIOClenchDumpConfig(self.config.dumpStatus?self.config.dumpStatus():nil)){p[@"dumpRestoreWaived"]=@"official-interface-unavailable-user-confirmed";[self oweRestore:p];}
 [self applyPending:p restore:nil];return YES;
}
- (NSDictionary *)manifest{
 NSMutableDictionary *m=[NSMutableDictionary new];
 m[@"schemaVersion"]=@1;m[@"sessionId"]=self.sessionId?:@"";m[@"source"]=self.source?:@"lifelog";m[@"label"]=self.label?:@"";m[@"createdAt"]=ISO(_wallStart,NO);
 m[@"appVersion"]=self.config.appVersion.length?self.config.appVersion:@"unknown";m[@"appCommit"]=self.config.appCommit.length?self.config.appCommit:@"unknown";m[@"clock"]=@"monotonic-seconds-from-session-start";
 m[@"marks"]=[_marks copy]?:@[];m[@"packets"]=[_packets copy]?:@[];m[@"durationSeconds"]=@(self.phase==TIOClenchPhaseFinished?self.durationSeconds:R6(MAX(0,MIN([self now]-_t0,[self deadline]))));
 m[@"stopRequestLimitSeconds"]=@(self.config.stopRequestLimit);m[@"receiveLimitSeconds"]=@(self.config.receiveLimit);m[@"stopPending"]=@(self.stopPending);m[@"offObserved"]=@(self.offObserved);
 m[@"droppedPackets"]=@(self.droppedPackets);m[@"dropReasons"]=[_dropReasons copy]?:@{};
 m[@"stopRequestedAtSeconds"]=_stopAt>=0?@(R6(_stopAt)):NSNull.null;m[@"stopReason"]=self.lastStopReason?:NSNull.null;m[@"stopBasis"]=self.stopBasis?:NSNull.null;m[@"finalizedAtSeconds"]=self.phase==TIOClenchPhaseFinished?@(R6(_finalizedAt)):NSNull.null;
 m[@"deadlineOverrunSeconds"]=@(R6(_overrun));m[@"endedAt"]=_wallEnd?ISO(_wallEnd,YES):NSNull.null;
 m[@"startWallMs"]=@(llround(_wallStart.timeIntervalSince1970*1000)); // Amendment 1a: wall time read at t=0, for mapping official timestamps only
 m[@"wallClockWindow"]=@{@"startMs":@(floor(_wallStart.timeIntervalSince1970*1000)),@"endMs":_wallEnd?@(ceil(_wallEnd.timeIntervalSince1970*1000)):NSNull.null,@"use":@"official events and official dump file window only; never used for packet or mark times"};
 m[@"officialCounters"]=[_counters copy]?:@[];m[@"officialDump"]=@[];m[@"officialDumpSkipped"]=@[];m[@"officialEvents"]=@{@"state":@"waiting"};m[@"officialAttach"]=@"waiting";
 m[@"dumpConfig"]=@{@"prior":_prior?:@{},@"lab":LabDump(_prior),@"labEnabled":@(_labDump),@"restoreAttempts":@(_restoreAttempts),@"restoreReadBack":_restoreReadBack?:NSNull.null};
 m[@"dumpRestored"]=@(self.dumpRestored);m[@"dumpRestoreExact"]=@(_restoreExact);m[@"dumpRestoreOutcome"]=_restoreOutcome?:NSNull.null;
 // First alwaysOnRunning==NO reading after the stop prompt with the session's glasses connected (wall ms), if seen.
 m[@"officialStopObservedMs"]=_officialStopWall?@(floor(_officialStopWall.timeIntervalSince1970*1000)):NSNull.null;if(_officialStopWall)m[@"officialStopObservedBy"]=@"capture-status";
 m[@"diagnostics"]=@{@"channelCounts":[_channels copy]?:@{},@"eventTypeCounts":[_eventTypes copy]?:@{},@"businessCounts":[_business copy]?:@{},@"arrivalClampedPackets":@(_clamped),@"officialRunningSeen":@(_officialRunningSeen),@"note":@"names and counts only, never payloads"};
 m[@"idleTimer"]=@{@"disabledDuringCapture":@(_idleUsed),@"priorDisabled":@(_idlePrior),@"restored":@(_idleRestored),@"setByLab":@(_idleSet),@"outcome":_idleOutcome?:NSNull.null,@"note":@"auto-lock disabled while capturing; the Lab re-enables it at the end only if the Lab disabled it, it is still disabled and no live camera or running navigation on screen holds it"};
 m[@"captureState"]=self.phase==TIOClenchPhaseFinished?@"finished":@"capturing";
 m[@"wakeWord"]=self.context?:NSNull.null;m[@"capture"]=@"passive-lifelog";m[@"format"]=@"uint32le length + original business-13 envelope (from the GlassesChannelHook tap)";
 m[@"limits"]=@{@"maxPackets":@(self.config.maxPackets),@"maxEnvelopeFileBytes":@(self.config.maxEnvelopeBytes),@"maxOfficialDumpBytes":@(DumpCap),@"stopTailSeconds":@(self.config.stopTail)};m[@"events"]=[_log copy]?:@[];
 // Fixtures only: the synthetic flag carries an explicit format so validators never infer one for real captures.
 if(self.config.synthetic){m[@"synthetic"]=@YES;m[@"audioFormat"]=@{@"provenance":@"synthetic",@"codec":@"opus",@"layout":@"mono",@"channels":@[[self.source stringByAppendingString:@"-mono-unassigned"]],@"sampleRate":@16000};}return m;
}
@end

NSString *TIOClenchListStateKey(TIOClenchSession *s){
 NSDictionary *p=s.pending,*o=s.restoreOwed;
 return [NSString stringWithFormat:@"%ld|%@|%@|%@|%@|%@|%@",(long)s.phase,s.sessionId?:@"-",p[@"sessionId"]?:@"-",p[@"stopPending"]?:@"-",p[@"dumpRestored"]?:@"-",p[@"dumpRestoreWaived"]?:@"-",o[@"sessionId"]?:@"-"];
}
BOOL TIOClenchSessionListStale(NSArray<NSDictionary *> *rows,NSString *listedKey,TIOClenchSession *s){
 if(![listedKey isEqual:TIOClenchListStateKey(s)])return YES;
 if(s.phase!=TIOClenchPhaseFinished||!s.sessionId)return NO;
 // Listed mid-capture (no manifest yet, or only the checkpoint): the finished manifest is on disk now.
 for(NSDictionary *r in rows)if([r[@"id"] isEqual:s.sessionId]){NSDictionary *m=r[@"manifest"];return ![m isKindOfClass:NSDictionary.class]||![m[@"captureState"] isEqual:@"finished"];}
 return NO; // the session's folder was deleted: nothing to refresh
}
#endif
