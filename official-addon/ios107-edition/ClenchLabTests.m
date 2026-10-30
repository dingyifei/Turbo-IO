#import "ClenchLab.h"
#import "A2UIProbe.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#include <zlib.h>
#include <assert.h>
// Synthetic only: no device, network or official app. test.py defines NSHomeDirectory=TIOTestHome.
static NSString *Home;
NSString *NSHomeDirectory(void){assert(Home.length);return Home;}
static NSTimeInterval Now;
static NSURL *OfficialHome;
static NSMutableArray<NSString *> *Suites;
static const double Wall0=1800000000;

@interface Fake:NSObject
@property NSMutableDictionary *status;@property NSMutableArray *calls;@property NSString *device;@property BOOL sticks,returns,statusNil,ignoreEvents,idle;@property NSUInteger idleSets;
@end
@implementation Fake @end
static Fake *NewFake(BOOL enabled,BOOL events){Fake *f=[Fake new];f.status=[@{@"dumpEnabled":@(enabled),@"dumpRealtimeAudio":@YES,@"dumpCachedAudio":@YES,@"dumpEvents":@(events),@"alwaysOnRunning":@YES,@"realtimePackets":@0,@"cachedPackets":@0} mutableCopy];f.sticks=YES;f.returns=YES;f.calls=[NSMutableArray new];f.device=@"device-A";return f;}
static NSUserDefaults *Defaults(void){NSString *n=[@"io.turboio.clench.test." stringByAppendingString:NSUUID.UUID.UUIDString];[Suites addObject:n];return [[NSUserDefaults alloc]initWithSuiteName:n];}
static TIOClenchConfig *Config(Fake *f,NSURL *root,NSUserDefaults *d){
 TIOClenchConfig *c=[TIOClenchConfig new];c.root=root;c.officialHome=OfficialHome;c.defaults=d;c.clock=^{return Now;};c.wallClock=^{return [NSDate dateWithTimeIntervalSince1970:Wall0+Now];};
 c.dumpStatus=^NSDictionary *{return f.statusNil?nil:[f.status copy];};
 c.dumpConfigure=^BOOL(NSDictionary *x){[f.calls addObject:x];if(f.sticks){f.status[@"dumpEnabled"]=x[@"enabled"];f.status[@"dumpRealtimeAudio"]=x[@"realtime"];f.status[@"dumpCachedAudio"]=x[@"cached"];if(!f.ignoreEvents)f.status[@"dumpEvents"]=x[@"events"];}return f.returns;};
 c.device=^NSString *{return f.device;};
 c.idleTimerDisabled=^BOOL{return f.idle;};c.setIdleTimerDisabled=^(BOOL v){f.idle=v;f.idleSets++;};c.appVersion=@"1.0.7 (test)";c.appCommit=@"0123abcd-dirty";return c;
}
static NSURL *NewRoot(void){return [[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:[@"roots/" stringByAppendingString:NSUUID.UUID.UUIDString]];}
static void V(NSMutableData *d,uint64_t n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *Env(uint64_t version,uint64_t type,NSDictionary *json,NSData *bytes){
 NSMutableData *d=[NSMutableData new];V(d,8);V(d,version);V(d,16);V(d,type);
 if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];V(d,26);V(d,j.length);[d appendData:j];}
 if(bytes){V(d,34);V(d,bytes.length);[d appendData:bytes];}return d;
}
static NSData *A3(int tag){NSMutableData *audio=[NSMutableData dataWithLength:480];((uint8_t *)audio.mutableBytes)[0]=(uint8_t)tag;return Env(1,163,@{@"taskId":@"task-1",@"frameCount":@2,@"vpuMask":@3,@"vadMask":@1},audio);}
static NSData *Switch(NSString *cmd,int value){return Env(1,20,@{@"cmd":cmd,@"payload":@{@"data":@"",@"mode":@0,@"value":@(value)}},nil);}
static NSDictionary *Manifest(NSURL *dir){NSData *d=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"manifest.json"]];id m=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;assert([m isKindOfClass:NSDictionary.class]);return m;}
static BOOL IsBool(id v){return [v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID();}
static BOOL IsInt(id v){return [v isKindOfClass:NSNumber.class]&&!IsBool(v)&&[v doubleValue]==floor([v doubleValue]);}
static BOOL IsNum(id v){return [v isKindOfClass:NSNumber.class]&&!IsBool(v);}
static mode_t Mode(NSURL *u){struct stat s;assert(!lstat(u.fileSystemRepresentation,&s));return s.st_mode&0777;}
static BOOL RealDirExists(NSURL *u){struct stat s;return !lstat(u.fileSystemRepresentation,&s)&&S_ISDIR(s.st_mode);}
static void Drain(void){for(int i=0;i<5;i++)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];}
// Minimal Ogg Opus stream (mono, pre-skip 312, 60 ms SILK packets) like the official dump. Granules are TOC-correct
// (2880 per 60 ms packet), or with legacy=YES the official quirk: 960 (20 ms at 48 kHz) per packet plus pre-skip.
static NSData *OggPage(NSData *packet,uint8_t flags,uint32_t seq,uint64_t gp){NSMutableData *d=[NSMutableData dataWithLength:28];uint8_t *b=d.mutableBytes;memcpy(b,"OggS",4);b[5]=flags;for(int i=0;i<8;i++)b[6+i]=(uint8_t)(gp>>(8*i));b[14]=7;for(int i=0;i<4;i++)b[18+i]=(uint8_t)(seq>>(8*i));b[26]=1;b[27]=(uint8_t)packet.length;[d appendData:packet];b=d.mutableBytes;uint32_t c=0;for(NSUInteger i=0;i<d.length;i++){c^=(uint32_t)b[i]<<24;for(int j=0;j<8;j++)c=(c<<1)^((c&0x80000000)?0x04c11db7:0);}for(int i=0;i<4;i++)b[22+i]=(uint8_t)(c>>(8*i));return d;}
static NSData *OggG(int packets,uint8_t tag,BOOL legacy){
 NSMutableData *head=[NSMutableData dataWithLength:19];uint8_t *h=head.mutableBytes;memcpy(h,"OpusHead",8);h[8]=1;h[9]=1;h[10]=56;h[11]=1;h[12]=0x80;h[13]=0x3e;
 NSMutableData *file=[NSMutableData new];[file appendData:OggPage(head,2,0,0)];[file appendData:OggPage([@"OpusTags" dataUsingEncoding:NSUTF8StringEncoding],0,1,0)];
 for(int i=0;i<packets;i++){uint8_t toc[2]={0x18,tag};[file appendData:OggPage([NSData dataWithBytes:toc length:2],i==packets-1?4:0,(uint32_t)i+2,legacy?960ULL*(uint64_t)(i+1)+312:2880ULL*(uint64_t)(i+1))];}return file;
}
static NSData *Ogg(int packets,uint8_t tag){return OggG(packets,tag,NO);}
// Official files carry real birth and modification times; the fixtures place them on the synthetic wall clock.
static void Times(NSURL *u,double birth,double modified){NSFileManager *fm=NSFileManager.defaultManager;assert([fm setAttributes:@{NSFileCreationDate:[NSDate dateWithTimeIntervalSince1970:birth]} ofItemAtPath:u.path error:nil]);assert([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:modified]} ofItemAtPath:u.path error:nil]);
 struct stat st;assert(!lstat(u.fileSystemRepresentation,&st)&&st.st_birthtimespec.tv_sec==(time_t)floor(birth)&&st.st_mtimespec.tv_sec==(time_t)floor(modified));}
static NSURL *Put(NSURL *dir,NSString *name,NSData *data,double birth,double modified){NSURL *u=[dir URLByAppendingPathComponent:name];assert([data writeToURL:u atomically:NO]);Times(u,birth,modified);return u;}
static NSData *Lines(NSArray *rows){NSMutableData *d=[NSMutableData new];for(id r in rows){[d appendData:[r isKindOfClass:NSString.class]?[r dataUsingEncoding:NSUTF8StringEncoding]:[NSJSONSerialization dataWithJSONObject:r options:0 error:nil]];[d appendBytes:"\n" length:1];}return d;}

// Schema 1 with Amendment 1 (limits 120/125 read from the manifest, official sidecars, stopBasis, appCommit).
static void CheckManifest(NSDictionary *m,NSString *commit){
 assert(IsInt(m[@"schemaVersion"])&&[m[@"schemaVersion"] isEqual:@1]);assert([[NSUUID alloc]initWithUUIDString:m[@"sessionId"]]);
 assert([m[@"source"] isEqual:@"lifelog"]&&[TIOClenchLabels() containsObject:m[@"label"]]);assert([m[@"synthetic"] isEqual:@YES]==(m[@"audioFormat"]!=nil));
 NSRegularExpression *iso=[NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d(\\.\\d+)?Z$" options:0 error:nil];NSString *created=m[@"createdAt"];
 assert([iso numberOfMatchesInString:created options:0 range:NSMakeRange(0,created.length)]==1);
 assert([m[@"appVersion"] length]&&[m[@"appCommit"] isEqual:commit]);assert([m[@"clock"] isEqual:@"monotonic-seconds-from-session-start"]);
 double duration=[m[@"durationSeconds"] doubleValue];assert(IsNum(m[@"durationSeconds"])&&duration>=0&&duration<=125);
 assert([m[@"stopRequestLimitSeconds"] isEqual:@120]&&[m[@"receiveLimitSeconds"] isEqual:@125]);
 assert(IsBool(m[@"stopPending"])&&IsBool(m[@"offObserved"])&&IsInt(m[@"droppedPackets"])&&[m[@"droppedPackets"] integerValue]>=0);
 double last=-1;for(NSDictionary *mark in m[@"marks"]){double t=[mark[@"timeSeconds"] doubleValue];assert(IsNum(mark[@"timeSeconds"])&&t>=last&&t>=0&&t<=duration);last=t;}
 last=-1;NSInteger index=0;for(NSDictionary *p in m[@"packets"]){
  assert([p[@"index"] isEqual:@(index++)]);double t=[p[@"arrivalSeconds"] doubleValue];assert(IsNum(p[@"arrivalSeconds"])&&t>=last&&t>=0&&t<=duration);last=t;
  assert(IsInt(p[@"business"])&&IsInt(p[@"type"])&&[p[@"envelopeBytes"] integerValue]>=1);
  for(NSString *k in @[@"vpuMask",@"vadMask"]){id v=p[k];assert(v&&(v==NSNull.null||IsInt(v)));}
 }
 // Amendment 1a: counters within [0,durationSeconds] in order, each with an epoch-ms wallMs; startWallMs at t=0.
 assert(IsNum(m[@"startWallMs"])&&[m[@"startWallMs"] doubleValue]>=1.5e12&&[m[@"startWallMs"] doubleValue]<=2.5e12);
 last=-1;for(NSDictionary *c in m[@"officialCounters"]){double t=[c[@"t"] doubleValue];assert(IsNum(c[@"t"])&&t>=last&&t>=0&&t<=duration);last=t;assert(IsNum(c[@"wallMs"])&&[c[@"wallMs"] doubleValue]>=1.5e12&&[c[@"wallMs"] doubleValue]<=2.5e12);}
 NSRegularExpression *dumpName=[NSRegularExpression regularExpressionWithPattern:@"^official-dump/[A-Za-z0-9_-][A-Za-z0-9_.-]*\\.(ogg|opus)$" options:0 error:nil];
 for(NSDictionary *e in m[@"officialDump"]){assert([e[@"alignment"] isEqual:@"unaligned"]&&[dumpName numberOfMatchesInString:e[@"file"] options:0 range:NSMakeRange(0,[e[@"file"] length])]==1&&IsBool(e[@"copyFinalized"])&&IsInt(e[@"bytes"])&&[e[@"bytes"] integerValue]>=1);
  assert(IsBool(e[@"writtenAfterLabWindow"])&&IsBool(e[@"copyVerbatim"])&&![e[@"sourceKind"] isEqual:@"cached"]);} // C2-5: JSON booleans; S2-03: no cached-kind copies
 assert(IsBool(m[@"dumpRestored"])&&IsBool(m[@"dumpRestoreExact"]));
 assert([m[@"officialDump"] isKindOfClass:NSArray.class]&&[m[@"officialEvents"] isKindOfClass:NSDictionary.class]&&m[@"stopBasis"]);
 for(NSDictionary *c in m[@"officialCounters"])for(NSString *k in @[@"t",@"realtimePackets",@"cachedPackets",@"alwaysOnRunning"])assert(c[k]);
 assert([m[@"capture"] isEqual:@"passive-lifelog"]&&[m[@"wallClockWindow"][@"startMs"] isKindOfClass:NSNumber.class]);
}

static void TestValues(void){
 assert([TIOClenchBuildCommit() isEqual:@"unknown"]); // no TIO_BUILD_COMMIT define in this build
 assert([TIOClenchSources() containsObject:@"voice"]&&TIOClenchSourceSelectable(@"lifelog")&&!TIOClenchSourceSelectable(@"voice"));
 assert([TIOClenchLabels() isEqual:(@[@"double-tap",@"single-tap",@"true-clench",@"chew",@"talk",@"walk",@"tap-temple",@"silence"])]);
 assert([TIOClenchDefaultRoot().path hasPrefix:Home]&&[TIOClenchDefaultRoot().path hasSuffix:@"Library/Application Support/TurboIOPrivateAddon/ClenchLab"]);
 assert(!TIOClenchDumpConfig(nil)&&!TIOClenchDumpConfig(@{@"dumpEnabled":@YES,@"dumpRealtimeAudio":@YES,@"dumpCachedAudio":@YES}));
 assert([TIOClenchDumpConfig(@{@"dumpEnabled":@1,@"dumpRealtimeAudio":@YES,@"dumpCachedAudio":@NO,@"dumpEvents":@NO,@"other":@1}) isEqual:(@{@"enabled":@YES,@"realtime":@YES,@"cached":@NO,@"events":@NO})]);
}
static void TestEnvelope(void){
 NSDictionary *m=TIOClenchParseEnvelope(A3(1));
 assert([m[@"type"] isEqual:@163]&&[m[@"vpuMask"] isEqual:@3]&&[m[@"vadMask"] isEqual:@1]&&[m[@"dataBytes"] isEqual:@480]&&[m[@"frameCount"] isEqual:@2]&&[m[@"taskId"] isEqual:@"task-1"]);
 NSMutableData *unknown=[A3(1) mutableCopy];V(unknown,40);V(unknown,7);V(unknown,50);V(unknown,2);[unknown appendBytes:"xy" length:2];V(unknown,61);[unknown appendBytes:"abcd" length:4];
 assert([TIOClenchParseEnvelope(unknown)[@"vpuMask"] isEqual:@3]);
 assert(!TIOClenchParseEnvelope(Env(2,163,@{},nil)));                                   // version != 1
 NSMutableData *noVersion=[NSMutableData new];V(noVersion,16);V(noVersion,3);assert(!TIOClenchParseEnvelope(noVersion));
 NSMutableData *dup=[A3(1) mutableCopy];V(dup,16);V(dup,5);assert(!TIOClenchParseEnvelope(dup)); // duplicate field 2
 NSMutableData *wire=[Env(1,3,nil,nil) mutableCopy];V(wire,24);V(wire,1);assert(!TIOClenchParseEnvelope(wire)); // field 3 as a varint
 const uint8_t truncated[]={8,0x81};assert(!TIOClenchParseEnvelope([NSData dataWithBytes:truncated length:2]));
 const uint8_t overflow[]={8,1,16,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x02};assert(!TIOClenchParseEnvelope([NSData dataWithBytes:overflow length:sizeof overflow]));
 const uint8_t typeOverflow[]={8,1,16,0x80,0x80,0x80,0x80,0x10};assert(!TIOClenchParseEnvelope([NSData dataWithBytes:typeOverflow length:sizeof typeOverflow]));
 NSMutableData *fields=[Env(1,3,nil,nil) mutableCopy];for(int i=0;i<254;i++){V(fields,40);V(fields,0);}assert(TIOClenchParseEnvelope(fields));V(fields,40);V(fields,0);assert(!TIOClenchParseEnvelope(fields));
 assert(!TIOClenchParseEnvelope([NSMutableData dataWithLength:1048577]));
 assert(!TIOClenchParseEnvelope(Env(1,3,nil,[NSMutableData dataWithLength:65537])));
 NSDictionary *b=TIOClenchParseEnvelope(Env(1,163,@{@"vpuMask":@YES,@"vadMask":@1.5},nil));assert(b[@"vpuMask"]==NSNull.null&&b[@"vadMask"]==NSNull.null);
 NSDictionary *opus=TIOClenchParseEnvelope(Env(1,3,nil,[NSMutableData dataWithLength:80]));assert([opus[@"type"] isEqual:@3]&&opus[@"vpuMask"]==NSNull.null&&opus[@"vadMask"]==NSNull.null&&opus[@"messageBytes"]==NSNull.null&&[opus[@"dataBytes"] isEqual:@80]);
 // Framing: uint32le length + exact envelope bytes.
 NSData *e300=Env(1,3,nil,[NSMutableData dataWithLength:300-7]);assert(e300.length==300);NSData *f=TIOClenchFrame(e300);const uint8_t *p=f.bytes;
 assert(f.length==304&&p[0]==0x2C&&p[1]==0x01&&p[2]==0&&p[3]==0&&[[f subdataWithRange:NSMakeRange(4,300)] isEqual:e300]);assert(!TIOClenchFrame([NSData data]));
}
static void TestWake(void){
 NSString *body=@"{\"cmd\":\"set_ai_voice_wakeup\",\"payload\":{\"data\":\"\",\"mode\":1,\"value\":0}}";NSData *b=[body dataUsingEncoding:NSUTF8StringEncoding];
 const uint8_t head[]={8,1,16,16,26,(uint8_t)b.length},tail[]={34,0};NSMutableData *expected=[NSMutableData dataWithBytes:head length:6];[expected appendData:b];[expected appendBytes:tail length:2];
 NSData *one=TIOClenchWakeupPacket(1),*zero=TIOClenchWakeupPacket(0);assert([one isEqual:expected]); // LauncherControlPrototype.encode(.enableVoiceWakeup)
 assert(zero.length==one.length);NSUInteger diff=0,at=0;for(NSUInteger i=0;i<one.length;i++)if(((const uint8_t *)one.bytes)[i]!=((const uint8_t *)zero.bytes)[i]){diff++;at=i;}
 assert(diff==1&&((const uint8_t *)zero.bytes)[at]=='0'&&((const uint8_t *)one.bytes)[at]=='1');
 assert(!TIOClenchWakeupPacket(2)&&!TIOClenchWakeupPacket(-1));
}
static void TestFilter(void){
 NSDate *s=[NSDate dateWithTimeIntervalSince1970:Wall0],*e=[NSDate dateWithTimeIntervalSince1970:Wall0+130];
 NSDictionary *in=@{@"eventTsMs":@((Wall0+1)*1000),@"type":@"a3_batch",@"vpuMask":@3,@"vadMask":@1,@"vpuOn":@YES,@"frameCount":@2,@"bytes":@480,@"taskId":@"task-1",
  @"text":@"secret words",@"asr":@"hello",@"payload":@{@"x":@1},@"source":@"has space",@"kind":@{@"nested":@1},@"note":@"free text"};
 NSDictionary *out=TIOClenchFilterOfficialEvent(in,s,e);assert([[NSSet setWithArray:out.allKeys] isEqual:([NSSet setWithArray:@[@"eventTsMs",@"type",@"vpuMask",@"vadMask",@"vpuOn",@"frameCount",@"bytes",@"taskId"]])]);
 assert(!TIOClenchFilterOfficialEvent(@{@"eventTsMs":@((Wall0-1)*1000),@"vpuMask":@1},s,e));
 assert(!TIOClenchFilterOfficialEvent(@{@"eventTsMs":@((Wall0+131)*1000),@"vpuMask":@1},s,e));
 assert(TIOClenchFilterOfficialEvent(@{@"eventTs":@(Wall0+10),@"vadMask":@1},s,e));             // seconds
 NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];NSString *iso=[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:Wall0+5]];
 assert([TIOClenchFilterOfficialEvent(@{@"timestamp":iso,@"text":@"x"},s,e) isEqual:(@{@"timestamp":iso})]);
 assert(!TIOClenchFilterOfficialEvent(@{@"vpuMask":@1,@"text":@"no time"},s,e)&&!TIOClenchFilterOfficialEvent(@[@1],s,e)&&!TIOClenchFilterOfficialEvent(@{@"ts":@"yesterday"},s,e));
}
static TIOClenchSession *Started(Fake *f,NSURL *root,NSUserDefaults *d,NSString *label){TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert(![s startWithLabel:label source:@"lifelog"]);return s;}
static void TestCapture(void){
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];__block int prompts=0;s.stopPrompt=^(BOOL ok){prompts++;assert(ok);};
 Now=100;assert(![s mark]);assert(!TIOClenchTapActive());
 assert([[s startWithLabel:@"nope" source:@"lifelog"] isEqual:@"label"]&&[[s startWithLabel:@"double-tap" source:@"voice"] isEqual:@"source"]);
 f.device=nil;assert([[s startWithLabel:@"double-tap" source:@"lifelog"] isEqual:@"device"]);f.device=@"device-A";
 assert(!f.calls.count&&!s.pending);
 assert(![s startWithLabel:@"double-tap" source:@"lifelog"]);assert(s.phase==TIOClenchPhaseCapturing&&TIOClenchTapActive());
 assert(f.calls.count==1&&[f.calls[0] isEqual:(@{@"enabled":@YES,@"realtime":@YES,@"cached":@YES,@"events":@YES})]&&[f.status[@"dumpEvents"] boolValue]);
 assert([s.pending[@"stopPending"] isEqual:@YES]&&[d dictionaryForKey:@"clenchLab.pending.v1"]);
 assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"busy"]&&[s.label isEqual:@"double-tap"]);
 assert(Mode(s.directory)==0700&&Mode([s.directory URLByAppendingPathComponent:@"envelopes.rnp"])==0600);
 Now=101;assert([s mark]);Now=101.5;assert([s mark]);
 [s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:102];
 const uint8_t junk[]={8,1,16};[s receiveBusiness:13 payload:[NSData dataWithBytes:junk length:3] device:@"device-A" arrival:102.2];
 [s receiveBusiness:20 payload:Env(1,2,@{@"x":@1},nil) device:@"device-A" arrival:102.3];
 [s receiveBusiness:13 payload:A3(9) device:@"device-B" arrival:102.4];
 [s receiveBusiness:13 payload:A3(9) device:@"device-A" arrival:99];
 assert(s.packetCount==1&&s.droppedPackets==3);
 Now=219.99;[s tick];assert(!s.stopRequested&&prompts==0&&f.calls.count==1);
 Now=220;[s tick];assert(s.stopRequested&&prompts==1&&f.calls.count==2&&[f.calls[1] isEqual:(@{@"enabled":@NO,@"realtime":@YES,@"cached":@YES,@"events":@NO})]&&s.dumpRestored);
 Now=221;[s tick];assert(prompts==1&&f.calls.count==2);assert([s mark]);             // marks stay valid after the prompt
 [s receiveBusiness:13 payload:A3(2) device:@"device-A" arrival:224.99];[s receiveBusiness:13 payload:A3(3) device:@"device-A" arrival:225.0];
 assert(s.packetCount==2&&s.phase==TIOClenchPhaseCapturing);
 Now=225;[s tick];assert(s.phase==TIOClenchPhaseFinished&&!TIOClenchTapActive()&&s.durationSeconds==125);
 assert(![s mark]);[s receiveBusiness:13 payload:A3(4) device:@"device-A" arrival:225.5];Now=400;[s tick];assert(prompts==1&&f.calls.count==2);
 NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert([m[@"marks"] count]==3&&[m[@"packets"] count]==2&&[m[@"durationSeconds"] isEqual:@125]&&[m[@"stopRequestedAtSeconds"] isEqual:@120]&&[m[@"stopReason"] isEqual:@"limit-120s"]);
 assert([m[@"droppedPackets"] isEqual:@4]&&[m[@"dropReasons"] isEqual:(@{@"unparseable":@1,@"other-device":@1,@"before-window":@1,@"after-window":@1})]);
 NSDictionary *p0=m[@"packets"][0];assert([p0[@"arrivalSeconds"] isEqual:@2]&&[p0[@"type"] isEqual:@163]&&[p0[@"vpuMask"] isEqual:@3]&&[p0[@"envelopeBytes"] isEqual:@(A3(1).length)]&&[p0[@"business"] isEqual:@13]);
 assert([m[@"packets"][1][@"arrivalSeconds"] isEqual:@124.99]);
 NSMutableData *expected=[TIOClenchFrame(A3(1)) mutableCopy];[expected appendData:TIOClenchFrame(A3(2))];assert([[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"envelopes.rnp"]] isEqual:expected]);
 assert([m[@"stopPending"] isEqual:@YES]&&[m[@"offObserved"] isEqual:@NO]&&[m[@"dumpRestored"] isEqual:@YES]&&[m[@"dumpRestoreExact"] isEqual:@YES]); // official still running: stop unconfirmed
 assert([m[@"officialCounters"] count]>=3&&[m[@"diagnostics"][@"businessCounts"][@"20"] isEqual:@1]&&Mode([s.directory URLByAppendingPathComponent:@"manifest.json"])==0600);
 assert(s.pending&&[[[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)] startWithLabel:@"chew" source:@"lifelog"] isEqual:@"pending"]);
}
static void TestTiming(void){
 // The cutoff tick lands just after 125 s: no counter is stored past the receive limit, so all t <= durationSeconds.
 Now=0;TIOClenchSession *cut=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"chew");for(double t=0.25;t<125;t+=0.25){Now=t;[cut tick];}
 Now=125.05;[cut tick];assert(cut.phase==TIOClenchPhaseFinished&&cut.durationSeconds==125);NSDictionary *cm=Manifest(cut.directory);CheckManifest(cm,@"0123abcd-dirty");
 assert([[cm[@"officialCounters"] lastObject][@"t"] doubleValue]<=125&&[cm[@"officialCounters"] count]>=400);
 Now=0;cut=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"chew");Now=120;[cut requestStop:@"manual"];Now=125.2;[cut lifecycleStop:@"background"];cm=Manifest(cut.directory);CheckManifest(cm,@"0123abcd-dirty");assert([cm[@"durationSeconds"] isEqual:@125]);
 // A late tick catches up: one stop request, storage ends at the 125 s cutoff.
 Fake *f=NewFake(NO,NO);__block int prompts=0;Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");s.stopPrompt=^(BOOL ok){prompts++;};
 [s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:124.5];Now=300;[s tick];[s tick];
 assert(prompts==1&&s.phase==TIOClenchPhaseFinished&&s.durationSeconds==125&&f.calls.count==2);NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert([m[@"stopRequestedAtSeconds"] isEqual:@300]&&[m[@"deadlineOverrunSeconds"] isEqual:@175]&&[m[@"packets"] count]==1);
 for(NSDictionary *c in m[@"officialCounters"])assert([c[@"t"] doubleValue]<=[m[@"durationSeconds"] doubleValue]); // the late reading at 300 s is not stored as a counter
 // A manual stop keeps a 5 s tail.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"talk");Now=10;[s requestStop:@"manual"];assert(s.remaining==5);Now=14.9;[s tick];assert(s.phase==TIOClenchPhaseCapturing);[s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:15];
 Now=15;[s tick];assert(s.phase==TIOClenchPhaseFinished&&s.durationSeconds==15&&s.packetCount==0&&[Manifest(s.directory)[@"dropReasons"][@"after-window"] isEqual:@1]);
 // Lifecycle, device change and caps stop and finalize at once.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"walk");Now=3;[s lifecycleStop:@"background"];assert(s.phase==TIOClenchPhaseFinished&&s.durationSeconds==3&&[s.lastStopReason isEqual:@"background"]);
 Fake *g=NewFake(NO,NO);Now=0;s=Started(g,NewRoot(),Defaults(),@"walk");g.device=@"device-B";Now=1;[s tick];assert(s.phase==TIOClenchPhaseFinished&&[s.lastStopReason isEqual:@"device-changed"]);
 TIOClenchConfig *c=Config(NewFake(NO,NO),NewRoot(),Defaults());c.maxPackets=2;Now=0;s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"silence" source:@"lifelog"]);
 for(int i=0;i<3;i++)[s receiveBusiness:13 payload:A3(i) device:@"device-A" arrival:1+i];assert(s.phase==TIOClenchPhaseFinished&&s.packetCount==2&&[Manifest(s.directory)[@"dropReasons"][@"cap"] isEqual:@1]&&[s.lastStopReason isEqual:@"storage-cap"]);
 c=Config(NewFake(NO,NO),NewRoot(),Defaults());c.maxEnvelopeBytes=TIOClenchFrame(A3(1)).length+3;s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"silence" source:@"lifelog"]);
 [s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:1];[s receiveBusiness:13 payload:A3(2) device:@"device-A" arrival:2];assert(s.phase==TIOClenchPhaseFinished&&s.packetCount==1);
 // Marks are rejected at and after the cutoff even before a tick finalizes.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"double-tap");Now=124.999;assert([s mark]);Now=125;assert(![s mark]);[s tick];assert([Manifest(s.directory)[@"marks"] count]==1);
}
static void TestDump(void){
 // Prior dump on with events NO comes back exactly as it was.
 Fake *f=NewFake(YES,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");Now=1;[s requestStop:@"manual"];
 assert([f.calls[1] isEqual:(@{@"enabled":@YES,@"realtime":@YES,@"cached":@YES,@"events":@NO})]&&![f.status[@"dumpEvents"] boolValue]&&[f.status[@"dumpEnabled"] boolValue]&&s.dumpRestored);
 Now=6;[s tick];assert([Manifest(s.directory)[@"dumpRestoreExact"] isEqual:@YES]);
 // A configure call that returns NO but sticks is judged by read-back.
 f=NewFake(NO,NO);Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");f.returns=NO;[s requestStop:@"manual"];assert(s.dumpRestored);
 // Restore read-back failure persists; a later retry restores and clears it.
 f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;s=Started(f,root,d,@"tap-temple");f.sticks=NO;__block BOOL promptOK=YES;s.stopPrompt=^(BOOL ok){promptOK=ok;};
 [s requestStop:@"manual"];assert(!s.dumpRestored&&!promptOK);Now=5;[s tick];assert(s.phase==TIOClenchPhaseFinished&&[s.pending[@"dumpRestored"] isEqual:@NO]);
 NSDictionary *m=Manifest(s.directory);assert([m[@"dumpRestored"] isEqual:@NO]&&[m[@"dumpConfig"][@"restoreReadBack"][@"events"] isEqual:@YES]);
 TIOClenchSession *again=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert(again.pending&&[[again startWithLabel:@"chew" source:@"lifelog"] isEqual:@"pending"]);
 assert(![again retryPending]&&again.pending);f.sticks=YES;assert(![again retryPending]&&[again.pending[@"dumpRestored"] isEqual:@YES]); // dump restored, LifeLog still running
 m=Manifest(s.directory);NSDictionary *prior=@{@"enabled":@NO,@"realtime":@YES,@"cached":@YES,@"events":@NO};
 assert([m[@"dumpRestored"] isEqual:@YES]&&[m[@"dumpRestoreExact"] isEqual:@YES]&&[m[@"dumpConfig"][@"restoreReadBack"] isEqual:prior]&&[m[@"dumpConfig"][@"restoreAttempts"] isEqual:@3]); // stop + failed retry + good retry
 f.status[@"alwaysOnRunning"]=@NO;assert([again retryPending]&&!again.pending&&![d dictionaryForKey:@"clenchLab.pending.v1"]);
 m=Manifest(s.directory);assert([m[@"dumpRestored"] isEqual:@YES]&&[m[@"stopPending"] isEqual:@NO]&&[m[@"stopBasis"] isEqual:@"official-status-not-running"]&&![f.status[@"dumpEvents"] boolValue]&&![f.status[@"dumpEnabled"] boolValue]);
 assert([m[@"dumpConfig"][@"restoreAttempts"] isEqual:@3]&&[m[@"dumpRestoreExact"] isEqual:@YES]);
 // Launch recovery restores only the dump: the stop stays pending and nothing else is sent.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];assert([s.pending[@"dumpRestored"] isEqual:@NO]);
 f.sticks=YES;f.statusNil=YES;again=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];NSUInteger calls=f.calls.count;assert(![again restorePendingDump]&&f.calls.count==calls); // official interface not ready: no call
 f.statusNil=NO;assert([again restorePendingDump]&&f.calls.count==calls+1&&[again.pending[@"stopPending"] isEqual:@YES]&&[again.pending[@"dumpRestored"] isEqual:@YES]&&![f.status[@"dumpEvents"] boolValue]);
 m=Manifest(s.directory);assert([m[@"dumpRestored"] isEqual:@YES]&&[m[@"dumpRestoreExact"] isEqual:@YES]&&[m[@"stopPending"] isEqual:@YES]);
 // Enable read-back failures refuse to start, restore the prior config and leave no session folder.
 for(int variant=0;variant<2;variant++){f=NewFake(NO,NO);if(variant)f.ignoreEvents=YES;else f.sticks=NO;root=NewRoot();d=Defaults();s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];
  assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-enable-failed"]&&s.phase==TIOClenchPhaseIdle&&!TIOClenchTapActive());
  assert(!s.pending&&![f.status[@"dumpEnabled"] boolValue]&&f.calls.count==2&&[TIOClenchListSessions(root) count]==0);}
 // An enable failure whose restore also fails stays pending.
 f=NewFake(NO,NO);f.ignoreEvents=YES;d=Defaults();s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),d)];__block Fake *flip=f;
 s.config.dumpConfigure=^BOOL(NSDictionary *x){[flip.calls addObject:x];if([x[@"events"] boolValue])flip.status[@"dumpEnabled"]=@YES;return YES;};
 assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-enable-failed"]&&[s.pending[@"dumpRestored"] isEqual:@NO]);
 // Unavailable or incomplete official status never starts.
 f=NewFake(NO,NO);f.statusNil=YES;s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),Defaults())];assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-unavailable"]&&!f.calls.count);
 f=NewFake(NO,NO);[f.status removeObjectForKey:@"dumpEvents"];s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),Defaults())];assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-unavailable"]&&!f.calls.count);
}
static void TestPending(void){
 // Stop unconfirmed after finalize: a fresh object restores the flag, refuses Start, and a user confirmation clears it.
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;TIOClenchSession *s=Started(f,root,d,@"single-tap");NSURL *dir=s.directory;
 assert(![s confirmPhysicalStop]);Now=1;[s requestStop:@"manual"];Now=6;[s tick];assert(s.stopPending&&s.dumpRestored);
 TIOClenchSession *next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert([next.pending[@"sessionId"] isEqual:s.sessionId]&&[[next startWithLabel:@"chew" source:@"lifelog"] isEqual:@"pending"]);
 [next observeOfficialStatus];assert(next.pending);
 assert([next confirmPhysicalStop]&&!next.pending&&![d dictionaryForKey:@"clenchLab.pending.v1"]);
 NSDictionary *c=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"stop-confirmation.json"]] options:0 error:nil];
 assert([c[@"source"] isEqual:@"user-observed-lifelog-off"]&&IsBool(c[@"protocolOffObserved"])&&Mode([dir URLByAppendingPathComponent:@"stop-confirmation.json"])==0600);
 NSDictionary *m=Manifest(dir);assert([m[@"stopPending"] isEqual:@NO]&&[m[@"stopBasis"] isEqual:@"user-confirmed"]);assert(![next startWithLabel:@"chew" source:@"lifelog"]);[next lifecycleStop:@"test"];
 // Official alwaysOnRunning==NO after the prompt resolves the stop during capture.
 // Two consecutive readings with the session's glasses connected are needed; one is not enough.
 f=NewFake(NO,NO);Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");Now=1;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=2;[s tick];assert(s.stopPending);
 Now=2.25;[s tick];assert(!s.stopPending&&[s.stopBasis isEqual:@"official-status-not-running"]);Now=6;[s tick];assert(!s.pending);
 // A link loss never clears the stop: the phone-side NO after the glasses drop is not evidence LifeLog stopped.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();Now=0;s=Started(f,root,d,@"chew");Now=1;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=1.25;[s tick];assert(s.stopPending);
 f.device=nil;Now=1.5;[s tick];assert(s.phase==TIOClenchPhaseFinished&&[s.lastStopReason isEqual:@"manual"]&&s.stopPending&&[Manifest(s.directory)[@"stopPending"] isEqual:@YES]);
 next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];[next observeOfficialStatus];[next observeOfficialStatus];assert(![next retryPending]&&[next.pending[@"stopPending"] isEqual:@YES]);
 f.device=@"device-B";[next observeOfficialStatus];[next observeOfficialStatus];assert(![next retryPending]&&next.pending); // other glasses
 f.device=@"device-A";[next observeOfficialStatus];assert(next.pending);[next observeOfficialStatus];assert(!next.pending&&[Manifest(s.directory)[@"stopBasis"] isEqual:@"official-status-not-running"]);
 // Protocol off: only an inbound life_log_switch value 0 after the prompt.
 f=NewFake(NO,NO);Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");
 [s receiveBusiness:15 payload:Switch(@"life_log_switch",0) device:@"device-A" arrival:0.5];assert(!s.offObserved);
 Now=1;[s requestStop:@"manual"];[s receiveBusiness:15 payload:Switch(@"life_log_switch_result",0) device:@"device-A" arrival:1.5];assert(!s.offObserved);
 [s receiveBusiness:15 payload:Switch(@"life_log_switch",0) device:@"device-B" arrival:1.6];assert(!s.offObserved);
 [s receiveBusiness:15 payload:Switch(@"life_log_switch",0) device:@"device-A" arrival:2];assert(s.offObserved&&!s.stopPending&&[s.stopBasis isEqual:@"protocol-life-log-switch-0"]);
 Now=6;[s tick];m=Manifest(s.directory);assert([m[@"offObserved"] isEqual:@YES]&&[m[@"stopPending"] isEqual:@NO]&&!s.pending);
 // Without an official interface the user confirmation records a waiver for the unverifiable restore.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];f.statusNil=YES;
 next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert(next.pending&&![next retryPending]&&[next confirmPhysicalStop]&&!next.pending);
 assert([Manifest(s.directory)[@"dumpRestoreWaived"] isEqual:@"official-interface-unavailable-user-confirmed"]);
}
static void TestTap(void){
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(1)}},1);TIOClenchTapChannel(@"rayneonet_event",10);Drain();assert(!TIOClenchTapActive());
 Fake *f=NewFake(NO,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");assert(TIOClenchTapActive());
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(1),@"deviceId":@"device-A"}},1);
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@20,@"payload":Env(1,2,@{},nil),@"deviceId":@"device-A"}},1.1);
 TIOClenchTapEvent(@{@"eventType":@"connectionState"},1.2);TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(2),@"deviceId":@"device-A"}},1.3);
 TIOClenchTapChannel(@"rayneonet_event",120);TIOClenchTapChannel(@"other_channel",7);TIOClenchTapChannel(@42,7);
 assert(s.packetCount==0);Drain();assert(s.packetCount==2);
 Now=2;[s lifecycleStop:@"test"];assert(!TIOClenchTapActive());NSDictionary *g=Manifest(s.directory)[@"diagnostics"];
 assert([g[@"businessCounts"] isEqual:(@{@"13":@2,@"20":@1})]&&[g[@"eventTypeCounts"] isEqual:(@{@"messageReceived":@3,@"connectionState":@1})]);
 assert([g[@"channelCounts"] isEqual:(@{@"rayneonet_event":@{@"messages":@1,@"bytes":@120},@"other_channel":@{@"messages":@1,@"bytes":@7}})]);
 assert([[Manifest(s.directory)[@"packets"][1] objectForKey:@"arrivalSeconds"] isEqual:@1.3]);
}
static NSString *SHA(NSData *d){unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,h);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof h;i++)[s appendFormat:@"%02x",h[i]];return s;}
static uint32_t U32(const uint8_t *p){return p[0]|p[1]<<8|p[2]<<16|(uint32_t)p[3]<<24;}
static uint16_t U16(const uint8_t *p){return (uint16_t)(p[0]|p[1]<<8);}
static void TestAttachAndZip(void){
 NSFileManager *fm=NSFileManager.defaultManager;NSURL *sessions=[OfficialHome URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/day1"];assert([fm createDirectoryAtURL:sessions withIntermediateDirectories:YES attributes:nil error:nil]);
 NSData *a=Ogg(4,1),*b=Ogg(6,2);
 NSURL *oldURL=[sessions URLByAppendingPathComponent:@"realtime_old.ogg"];assert([Ogg(3,9) writeToURL:oldURL atomically:NO]);
 // 40 older official session folders with their own events.jsonl, so enumeration order cannot hide this session's.
 for(int i=0;i<40;i++){NSURL *o=[OfficialHome URLByAppendingPathComponent:[NSString stringWithFormat:@"Documents/always_on_debug/sessions/old%02d",i]];assert([fm createDirectoryAtURL:o withIntermediateDirectories:YES attributes:nil error:nil]);
  Put(o,@"events.jsonl",Lines(@[@{@"eventTsMs":@((Wall0-1000+i)*1000),@"type":@"a3",@"vpuMask":@1}]),Wall0-2000,Wall0-900);}
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();Now=0;TIOClenchSession *s=Started(f,root,Defaults(),@"double-tap");Now=1;assert([s mark]);
 NSFileHandle *h=[NSFileHandle fileHandleForWritingToURL:oldURL error:nil];[h seekToEndOfFile];[h writeData:a];[h closeFile];Times(oldURL,Wall0-3600,Wall0-10); // grew, but last written before the window
 Put(sessions,@"realtime_first.ogg",a,Wall0+0.5,Wall0+3);Put(sessions,@"realtime_new.ogg",b,Wall0+0.5,Wall0+4);
 // Outside the window, written after the session, cached-kind (S2-03: provenance unverified) or not Ogg: never copied, each with its reason.
 Put(sessions,@"cached_new.ogg",Ogg(3,7),Wall0+0.5,Wall0+3);
 Put(sessions,@"realtime_late.ogg",Ogg(2,3),Wall0+1,Wall0+60);Put(sessions,@"realtime_after.ogg",Ogg(2,4),Wall0+300,Wall0+301);
 Put(sessions,@"realtime_long.ogg",Ogg(2,8),Wall0+1,Wall0+700);
 Put(sessions,@"realtime_early.ogg",Ogg(2,5),Wall0-3600,Wall0+2);Put(sessions,@"realtime_raw.pcm",[NSMutableData dataWithLength:64],Wall0+1,Wall0+2);
 NSArray *lines=@[@{@"eventTsMs":@((Wall0+1)*1000),@"type":@"a3",@"vpuMask":@3,@"vadMask":@1,@"frameCount":@2,@"bytes":@480,@"text":@"secret words",@"payload":@{@"asr":@"x"}},
  @{@"eventTsMs":@((Wall0-50)*1000),@"type":@"a3",@"vpuMask":@1},@{@"type":@"a3",@"text":@"no time"},@"not json"];
 Put(sessions,@"events.jsonl",Lines(lines),Wall0+0.5,Wall0+4);
 Now=2;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=6.5;[s tick];Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished&&!s.pending);
 // Session B (same window on the synthetic clock) records and attaches its own file first; A must not claim it.
 Fake *g=NewFake(NO,NO);Now=0;TIOClenchSession *other=Started(g,root,Defaults(),@"chew");Put(sessions,@"realtime_b.ogg",Ogg(5,6),Wall0+2,Wall0+5);
 Now=2;[other requestStop:@"manual"];g.status[@"alwaysOnRunning"]=@NO;Now=6.5;[other tick];Now=7;[other tick];assert(other.phase==TIOClenchPhaseFinished);
 NSDictionary *rb=TIOClenchAttachOfficial(other.directory,OfficialHome);assert([rb[@"files"] isEqual:@1]&&[Manifest(other.directory)[@"officialDump"][0][@"originalName"] isEqual:@"realtime_b.ogg"]);
 NSDictionary *r=TIOClenchAttachOfficial(s.directory,OfficialHome);assert([r[@"files"] isEqual:@2]&&[r[@"events"] isEqual:@1]&&[r[@"alignment"] isEqual:@"unaligned"]&&!r[@"alreadyAttached"]);
 assert(TIOClenchDeleteSession(root,other.directory));
 NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");assert([m[@"officialAttach"] isEqual:@"done"]&&[m[@"officialDump"] count]==2&&[m[@"officialSnapshotTruncated"] isEqual:@NO]&&[m[@"officialListingTruncated"] isEqual:@NO]&&[m[@"officialAttachAttempts"] isEqual:@1]);
 // The capture saw the official stop at 6.5 s (first NO reading after the prompt, glasses connected): last writes count to 6.5+5 s.
 // S2-01: last writes count to startWallMs + the effective deadline (stop 2 s + 5 s tail) + 5 s flush slack; the observed stop is a diagnostic.
 assert([m[@"officialStopObservedMs"] isEqual:@((Wall0+6.5)*1000)]&&[m[@"officialAttachWindow"][@"officialStopSource"] isEqual:@"observed"]&&[m[@"officialAttachWindow"][@"writeLimitMs"] isEqual:@((Wall0+12)*1000)]&&[m[@"officialAttachWindow"][@"effectiveDeadlineSeconds"] isEqual:@7]&&!m[@"officialAttachWindow"][@"lateWriteGraceMs"]);
 for(NSDictionary *e in m[@"officialDump"])assert([e[@"writtenAfterLabWindow"] isEqual:@NO]);
 NSMutableSet *kinds=[NSMutableSet new];for(NSDictionary *e in m[@"officialDump"]){NSData *copy=[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:e[@"file"]]];
  assert([e[@"sha256"] isEqual:SHA(copy)]&&[e[@"bytes"] isEqual:@(copy.length)]&&[e[@"copyFinalized"] isEqual:@YES]&&[e[@"alignment"] isEqual:@"unaligned"]&&Mode([s.directory URLByAppendingPathComponent:e[@"file"]])==0600);
  assert([copy isEqual:[e[@"originalName"] isEqual:@"realtime_first.ogg"]?a:b]&&[e[@"file"] hasSuffix:@".ogg"]&&[e[@"granuleMode"] isEqual:@"toc-correct"]&&[e[@"origin"] isEqual:@"new-in-window"]);[kinds addObject:e[@"sourceKind"]];}
 NSMutableDictionary *reasons=[NSMutableDictionary new];for(NSDictionary *k in m[@"officialDumpSkipped"])reasons[k[@"originalName"]]=k[@"reason"];
 assert([reasons isEqual:(@{@"realtime_old.ogg":@"pre-existing-file-changed",@"realtime_late.ogg":@"written-after-session",@"realtime_long.ogg":@"written-after-session",@"cached_new.ogg":@"cached-provenance-unverified",@"realtime_after.ogg":@"created-after-session",@"realtime_early.ogg":@"created-before-session",@"realtime_raw.pcm":@"not-ogg-opus",@"realtime_b.ogg":@"attached-to-another-session"})]);
 assert([kinds isEqual:([NSSet setWithObject:@"realtime"])]&&Mode([s.directory URLByAppendingPathComponent:@"official-dump"])==0700);
 NSString *events=[NSString stringWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"official-events.jsonl"] encoding:NSUTF8StringEncoding error:nil];NSArray *rows=[events componentsSeparatedByString:@"\n"];
 assert(rows.count==2&&[rows[1] isEqual:@""]&&[events rangeOfString:@"secret"].location==NSNotFound&&[events rangeOfString:@"asr"].location==NSNotFound);
 NSDictionary *kept=[NSJSONSerialization JSONObjectWithData:[rows[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];assert([[NSSet setWithArray:kept.allKeys] isEqual:([NSSet setWithArray:@[@"eventTsMs",@"type",@"vpuMask",@"vadMask",@"frameCount",@"bytes"]])]);
 NSDictionary *ev=m[@"officialEvents"];assert([ev[@"count"] isEqual:@1]&&[ev[@"sourceFiles"] isEqual:@1]&&[ev[@"sourceFilesTruncated"] isEqual:@NO]&&[ev[@"excluded"][@"outsideWindow"] isEqual:@1]&&[ev[@"excluded"][@"withoutTime"] isEqual:@1]&&[ev[@"excluded"][@"unparseable"] isEqual:@1]&&[ev[@"droppedKeyCounts"][@"text"] isEqual:@1]);
 assert([[NSData dataWithContentsOfURL:[sessions URLByAppendingPathComponent:@"realtime_first.ogg"]] isEqual:a]); // originals untouched
 NSURL *exports=[OfficialHome URLByAppendingPathComponent:@"Documents/TurboIOAlwaysOnExports"];for(NSString *n in [fm contentsOfDirectoryAtPath:exports.path error:nil]?:@[])assert(![n length]||![[fm contentsOfDirectoryAtPath:[exports.path stringByAppendingPathComponent:n] error:nil] count]);
 NSNumber *excluded=nil;assert([exports getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil]&&excluded.boolValue); // staging area kept out of backups
 // One attach per session: a later attach copies nothing, even a new in-window file.
 Put(sessions,@"cached_later.ogg",Ogg(2,7),Wall0+1,Wall0+5);
 NSDictionary *again=TIOClenchAttachOfficial(s.directory,OfficialHome);assert([again[@"alreadyAttached"] isEqual:@YES]&&[again[@"files"] isEqual:@2]&&[again[@"events"] isEqual:@1]);
 assert([Manifest(s.directory)[@"officialDump"] count]==2&&[[fm contentsOfDirectoryAtPath:[s.directory URLByAppendingPathComponent:@"official-dump"].path error:nil] count]==2);
 // Stored zip: parse local headers, central directory and end record back.
 NSURL *exportRoot=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"exports/ClenchExports"];NSURL *zip=TIOClenchZipSession(s.directory,exportRoot);assert(zip&&Mode(zip)==0600&&Mode(zip.URLByDeletingLastPathComponent)==0700);
 NSData *z=[NSData dataWithContentsOfURL:zip];const uint8_t *p=z.bytes;NSUInteger at=0;NSMutableArray *names=[NSMutableArray new];NSString *prefix=[NSString stringWithFormat:@"clench-%@/",s.sessionId];
 while(at+30<=z.length&&U32(p+at)==0x04034b50){uint16_t method=U16(p+at+8),nlen=U16(p+at+26),xlen=U16(p+at+28);uint32_t crc=U32(p+at+14),cs=U32(p+at+18),us=U32(p+at+22);
  NSString *name=[[NSString alloc]initWithBytes:p+at+30 length:nlen encoding:NSASCIIStringEncoding];NSUInteger data=at+30+nlen+xlen;assert(method==0&&cs==us&&data+cs<=z.length);
  assert((uint32_t)crc32(crc32(0,Z_NULL,0),p+data,cs)==crc&&[name hasPrefix:prefix]&&[name rangeOfString:@".."].location==NSNotFound&&![name hasPrefix:@"/"]);
  NSData *src=[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:[name substringFromIndex:prefix.length]]];assert([src isEqual:[z subdataWithRange:NSMakeRange(data,cs)]]);[names addObject:[name substringFromIndex:prefix.length]];at=data+cs;}
 NSArray *want=@[@"manifest.json",@"envelopes.rnp",@"official-events.jsonl",[m[@"officialDump"][0][@"file"] hasPrefix:@"official-dump/00"]?m[@"officialDump"][0][@"file"]:m[@"officialDump"][1][@"file"],[m[@"officialDump"][1][@"file"] hasPrefix:@"official-dump/01"]?m[@"officialDump"][1][@"file"]:m[@"officialDump"][0][@"file"]];
 assert([names isEqual:want]&&[[names filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH 'manifest.json'"]] count]==1);
 NSUInteger cd=at,count=0;while(U32(p+at)==0x02014b50){assert(U16(p+at+10)==0&&(U32(p+at+38)>>16)==(S_IFREG|0600)&&U16(p+at+4)>>8==3);at+=46+U16(p+at+28)+U16(p+at+30)+U16(p+at+32);count++;}
 assert(count==names.count&&U32(p+at)==0x06054b50&&U16(p+at+10)==count&&U32(p+at+16)==cd&&U32(p+at+12)==at-cd&&at+22==z.length);
 assert([fm removeItemAtURL:zip.URLByDeletingLastPathComponent error:nil]);
 // Incomplete sessions (no manifest) are listed but never zipped; delete stays inside the Lab root.
 NSURL *incomplete=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString.lowercaseString];assert(!mkdir(incomplete.fileSystemRepresentation,0700));assert(!TIOClenchZipSession(incomplete,exportRoot));
 NSArray *list=TIOClenchListSessions(root);assert(list.count==2);for(NSDictionary *row in list)assert([row[@"complete"] boolValue]==[row[@"id"] isEqual:s.sessionId]);
 assert(!TIOClenchDeleteSession(root,OfficialHome)&&!TIOClenchDeleteSession(NewRoot(),s.directory));assert(TIOClenchDeleteSession(root,incomplete)&&TIOClenchDeleteSession(root,s.directory)&&![fm fileExistsAtPath:s.directory.path]);
 // A symlinked Lab root is refused before anything is created.
 NSURL *real=NewRoot(),*link=NewRoot();assert([fm createDirectoryAtURL:real withIntermediateDirectories:YES attributes:nil error:nil]&&[fm createSymbolicLinkAtURL:link withDestinationURL:real error:nil]);
 TIOClenchSession *bad=[[TIOClenchSession alloc]initWithConfig:Config(NewFake(NO,NO),link,Defaults())];assert([[bad startWithLabel:@"chew" source:@"lifelog"] isEqual:@"storage"]&&![[fm contentsOfDirectoryAtPath:real.path error:nil] count]&&!bad.pending);
}
// Concurrent post-capture updates (two panels, a background attach) are serialized: no key is lost.
static void TestConcurrentMerge(void){
 Fake *f=NewFake(NO,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");Now=1;[s lifecycleStop:@"test"];NSURL *dir=s.directory;
 dispatch_apply(64,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){assert(TIOClenchMergeManifest(dir,@{[NSString stringWithFormat:@"probe%02zu",i]:@(i)}));});
 NSDictionary *m=Manifest(dir);for(size_t i=0;i<64;i++)assert(([m[[NSString stringWithFormat:@"probe%02zu",i]] isEqual:@(i)]));CheckManifest(m,@"0123abcd-dirty");
}
// Many official files (well past TIOAOAudioFiles' 500-row display cap): the Lab's own listing still finds and copies this
// session's file, whatever the enumeration order, and the snapshot is complete.
static void TestManyOfficialFiles(void){
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-many"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/old"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 NSData *old=Ogg(1,1);for(int i=0;i<2000;i++)assert(([old writeToURL:[day URLByAppendingPathComponent:[NSString stringWithFormat:@"realtime_%04d.ogg",i]] atomically:NO]));
 Fake *f=NewFake(NO,NO);TIOClenchConfig *c=Config(f,NewRoot(),Defaults());c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 NSDictionary *snap=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"official-snapshot.json"]] options:0 error:nil];assert([snap[@"files"] count]==2000&&[snap[@"truncated"] isEqual:@NO]);
 Put(day,@"realtime_new.ogg",Ogg(3,1),Wall0+1,Wall0+2);Now=2;[s requestStop:@"manual"];Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished);
 NSDictionary *r=TIOClenchAttachOfficial(s.directory,home);assert([r[@"files"] isEqual:@1]&&[r[@"state"] isEqual:@"done"]);NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert([m[@"officialSnapshotTruncated"] isEqual:@NO]&&[m[@"officialListingTruncated"] isEqual:@NO]&&[m[@"officialDump"] count]==1&&[m[@"officialDump"][0][@"originalName"] isEqual:@"realtime_new.ogg"]);
 for(NSDictionary *k in m[@"officialDumpSkipped"])assert([k[@"reason"] isEqual:@"created-before-session"]&&![k[@"originalName"] isEqual:@"realtime_new.ogg"]);
}
// P-CORR-1/3: the restored dump (prior on) keeps the official writer going after the Lab window until the user stops
// LifeLog. Auto-attach waits for a settled stop with the session's glasses connected and records when it was seen.
// S2-01: a file born inside the window but still written after the effective deadline (stop 2 s + 5 s tail) plus the 5 s
// flush slack holds audio from after the session: it is skipped "written-after-session", however late the stop was seen.
static void TestLateWriter(void){
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-late"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/late"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 Fake *f=NewFake(YES,NO);TIOClenchConfig *c=Config(f,NewRoot(),Defaults());c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 Now=2;[s requestStop:@"manual"];assert([f.status[@"dumpEnabled"] boolValue]&&![f.status[@"dumpEvents"] boolValue]);Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished&&s.stopPending);
 assert(Manifest(s.directory)[@"officialStopObservedMs"]==NSNull.null);NSURL *dir=s.directory;
 Put(day,@"realtime_live.ogg",Ogg(6,2),Wall0+1,Wall0+20);Put(day,@"cached_next.ogg",Ogg(2,3),Wall0+40,Wall0+41); // the user's next LifeLog session
 Put(day,@"realtime_edge.ogg",Ogg(4,5),Wall0+1,Wall0+12);Put(day,@"realtime_tail.ogg",Ogg(4,6),Wall0+1,Wall0+12.5); // last written at / just past the limit
 // Not settled while LifeLog runs, on a link loss, or with other glasses.
 Now=15;assert(![s officialSettledForAttach:dir]);f.status[@"alwaysOnRunning"]=@NO;f.device=nil;Now=16;assert(![s officialSettledForAttach:dir]);
 f.device=@"device-B";Now=17;assert(![s officialSettledForAttach:dir]);Now=18;assert(![s officialSettledForAttach:dir]);Now=19;assert(![s officialSettledForAttach:dir]);
 // Three readings spanning 2 s with the session's glasses: settled, first reading recorded.
 f.device=@"device-A";Now=20;assert(![s officialSettledForAttach:dir]);Now=21;assert(![s officialSettledForAttach:dir]);f.device=nil;Now=21.5;assert(![s officialSettledForAttach:dir]);
 f.device=@"device-A";Now=22;assert(![s officialSettledForAttach:dir]);Now=23;assert(![s officialSettledForAttach:dir]);Now=24;assert([s officialSettledForAttach:dir]);
 NSDictionary *m=Manifest(dir);assert([m[@"officialStopObservedMs"] isEqual:@((Wall0+22)*1000)]&&[m[@"officialStopObservedBy"] isEqual:@"attach-settle"]);
 NSDictionary *r=TIOClenchAttachOfficial(dir,home);m=Manifest(dir);CheckManifest(m,@"0123abcd-dirty");
 assert([r[@"files"] isEqual:@1]&&[r[@"state"] isEqual:@"done"]&&[m[@"officialDump"] count]==1);NSDictionary *e=m[@"officialDump"][0];
 assert([e[@"originalName"] isEqual:@"realtime_edge.ogg"]&&[e[@"writtenAfterLabWindow"] isEqual:@NO]&&[[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:e[@"file"]]] isEqual:Ogg(4,5)]);
 NSMutableDictionary *reasons=[NSMutableDictionary new];for(NSDictionary *k in m[@"officialDumpSkipped"])reasons[k[@"originalName"]]=k;
 assert(reasons.count==3&&[m[@"officialDumpSkipped"] count]==3&&[reasons[@"cached_next.ogg"][@"reason"] isEqual:@"created-after-session"]&&[reasons[@"realtime_live.ogg"][@"reason"] isEqual:@"written-after-session"]&&[reasons[@"realtime_tail.ogg"][@"reason"] isEqual:@"written-after-session"]);
 assert([reasons[@"realtime_live.ogg"][@"sourceModifiedMs"] isEqual:@((Wall0+20)*1000)]&&[m[@"officialAttachWindow"][@"writeLimitMs"] isEqual:@((Wall0+12)*1000)]&&[m[@"officialAttachWindow"][@"officialStopMs"] isEqual:@((Wall0+22)*1000)]);
}
// P2: a user who switched official audio saving off mid-session keeps their choice; the stop and the launch recovery
// never turn it back on. A record written before the enable was verified is always undone.
static void TestUserChangedDump(void){
 Fake *f=NewFake(YES,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");NSUInteger calls=f.calls.count;
 f.status[@"dumpEnabled"]=@NO; // the LifeLog Audio panel's saving switch, inside the same app
 Now=1;[s requestStop:@"manual"];assert(f.calls.count==calls&&![f.status[@"dumpEnabled"] boolValue]&&s.dumpRestored);
 Now=6;[s tick];NSDictionary *m=Manifest(s.directory);assert([m[@"dumpRestoreOutcome"] isEqual:@"user-changed"]&&[m[@"dumpRestoreExact"] isEqual:@NO]&&[m[@"dumpConfig"][@"restoreReadBack"][@"enabled"] isEqual:@NO]&&[m[@"dumpConfig"][@"restoreAttempts"] isEqual:@0]);
 // Crash recovery: the record is still open, but the user changed the config since; it is left alone.
 f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];assert([s.pending[@"dumpRestored"] isEqual:@NO]);
 f.sticks=YES;f.status[@"dumpEvents"]=@NO;calls=f.calls.count;TIOClenchSession *again=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];
 assert([again restorePendingDump]&&f.calls.count==calls&&[again.pending[@"dumpRestored"] isEqual:@YES]&&[Manifest(s.directory)[@"dumpRestoreOutcome"] isEqual:@"user-changed"]);
 // The user put it back exactly as it was before Start: recorded as already prior, exact.
 f=NewFake(NO,NO);Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");calls=f.calls.count;f.status[@"dumpEnabled"]=@NO;f.status[@"dumpEvents"]=@NO;
 Now=1;[s requestStop:@"manual"];Now=6;[s tick];m=Manifest(s.directory);assert(f.calls.count==calls&&[m[@"dumpRestoreOutcome"] isEqual:@"already-prior"]&&[m[@"dumpRestoreExact"] isEqual:@YES]);
 // A crash between the enable call and its read-back: the partly applied config is always undone.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();f.ignoreEvents=YES;s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];
 s.config.dumpConfigure=^BOOL(NSDictionary *x){[f.calls addObject:x];f.status[@"dumpEnabled"]=x[@"enabled"];return YES;}; // enable sticks without events
 [d setObject:@{@"sessionId":NSUUID.UUID.UUIDString.lowercaseString,@"prior":@{@"enabled":@NO,@"realtime":@YES,@"cached":@YES,@"events":@NO},@"labDumpEnabled":@YES,@"dumpRestored":@NO,@"stopPending":@NO,@"stopRequested":@NO,@"enableUnverified":@YES} forKey:@"clenchLab.pending.v1"];
 f.status[@"dumpEnabled"]=@YES;again=[[TIOClenchSession alloc]initWithConfig:s.config];calls=f.calls.count;
 assert([again restorePendingDump]&&f.calls.count==calls+1&&![f.status[@"dumpEnabled"] boolValue]&&!again.pending);
}
// P-CORR-5: a dump-only record (failed enable and failed restore) whose official interface then disappears can still be
// waived by the user's confirmation, so Start is not blocked for good.
static void TestDumpOnlyWaiver(void){
 Fake *f=NewFake(NO,NO);NSUserDefaults *d=Defaults();NSURL *root=NewRoot();f.ignoreEvents=YES;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];__block Fake *flip=f;
 s.config.dumpConfigure=^BOOL(NSDictionary *x){[flip.calls addObject:x];if([x[@"events"] boolValue])flip.status[@"dumpEnabled"]=@YES;return YES;};
 assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-enable-failed"]&&[s.pending[@"stopPending"] isEqual:@NO]&&[s.pending[@"dumpRestored"] isEqual:@NO]);
 f.statusNil=YES;TIOClenchSession *next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert(next.pending&&![next retryPending]&&![next restorePendingDump]);
 assert([next confirmPhysicalStop]&&!next.pending&&![d dictionaryForKey:@"clenchLab.pending.v1"]);
}
// P-CORR-A: auto-lock would resign the app and end the capture. The idle timer is disabled while capturing and the value
// seen at Start comes back on every end path; a refused Start and crash recovery never touch it. S1-3: when it was already
// disabled at Start (another holder), the Lab never writes it at all.
static void TestIdleTimer(void){
 for(NSString *path in @[@"manual-tail",@"cutoff",@"background",@"device-changed",@"device-lost",@"storage-cap"])for(int prior=0;prior<2;prior++){
  Fake *f=NewFake(NO,NO);f.idle=prior;TIOClenchConfig *c=Config(f,NewRoot(),Defaults());if([path isEqual:@"storage-cap"])c.maxPackets=1;
  Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]&&f.idle&&s.holdsIdleTimer);
  [s releaseIdleTimer];assert(f.idle&&s.holdsIdleTimer); // never released while capturing
  if([path isEqual:@"manual-tail"]){Now=10;[s requestStop:@"manual"];assert(f.idle);Now=15;[s tick];}
  else if([path isEqual:@"cutoff"]){Now=120;[s tick];assert(s.stopRequested&&f.idle);Now=125;[s tick];}
  else if([path isEqual:@"background"]){Now=3;[s lifecycleStop:@"app-inactive"];}
  else if([path isEqual:@"device-changed"]){f.device=@"device-B";Now=1;[s tick];}
  else if([path isEqual:@"device-lost"]){f.device=nil;Now=1;[s tick];}
  else{[s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:1];[s receiveBusiness:13 payload:A3(2) device:@"device-A" arrival:2];}
  NSUInteger sets=prior?0:2; // prior enabled: disabled at Start, enabled at the end; prior disabled: never written
  assert(s.phase==TIOClenchPhaseFinished&&!s.holdsIdleTimer&&f.idle==(BOOL)prior&&f.idleSets==sets);
  NSDictionary *it=Manifest(s.directory)[@"idleTimer"];assert([it[@"disabledDuringCapture"] isEqual:@YES]&&[it[@"restored"] isEqual:@YES]&&[it[@"priorDisabled"] boolValue]==(BOOL)prior);
  assert([it[@"setByLab"] boolValue]==!prior&&[it[@"outcome"] isEqual:prior?@"left-to-other-holder":@"restored"]);
  [s releaseIdleTimer];Now=400;[s tick];assert(f.idleSets==sets); // ended once, released once
 }
 // Refused or failed starts never take the idle timer.
 Fake *f=NewFake(NO,NO);f.sticks=NO;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),Defaults())];
 assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"dump-enable-failed"]&&!f.idleSets&&!s.holdsIdleTimer);
 f=NewFake(NO,NO);f.device=nil;s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),Defaults())];assert([[s startWithLabel:@"chew" source:@"lifelog"] isEqual:@"device"]&&!f.idleSets);
 // Crash recovery: a new process starts with the system value; restoring the pending dump record leaves the idle timer alone.
 f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"app-inactive"];assert(!f.idle&&f.idleSets==2&&[s.pending[@"dumpRestored"] isEqual:@NO]);
 f.sticks=YES;f.idle=YES;TIOClenchSession *again=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert([again restorePendingDump]);[again releaseIdleTimer];assert(f.idle&&f.idleSets==2&&!again.holdsIdleTimer);
}
// P-CORR-B: every session folder is ordered by creation before the 200-row cap, so the newest are never dropped, however
// the directory listing orders them and whatever later manifest writes do to modification times.
static void TestListOrder(void){
 NSFileManager *fm=NSFileManager.defaultManager;NSURL *root=NewRoot();assert([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
 for(int i=0;i<230;i++){NSURL *u=[root URLByAppendingPathComponent:NSUUID.UUID.UUIDString.lowercaseString];assert(!mkdir(u.fileSystemRepresentation,0700));assert([Lines(@[@{@"createdAt":@"2027-01-15T08:00:00Z",@"label":@"chew"}]) writeToURL:[u URLByAppendingPathComponent:@"manifest.json"] atomically:NO]);}
 NSArray<NSURL *> *order=[fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil];assert(order.count==230);
 // Birth times rise with the listing order: the newest folders are the last ones the directory returns.
 for(NSUInteger i=0;i<order.count;i++)Times(order[i],Wall0+i,Wall0+i);
 Times(order[0],Wall0,Wall0+100000); // the oldest folder was written much later (a late manifest update)
 NSArray *list=TIOClenchListSessions(root);assert(list.count==200);
 for(NSUInteger k=0;k<200;k++){assert([list[k][@"id"] isEqual:order[229-k].lastPathComponent]&&[list[k][@"complete"] isEqual:@YES]&&[list[k][@"manifest"][@"label"] isEqual:@"chew"]);}
 for(NSDictionary *row in list)assert(![row[@"id"] isEqual:order[0].lastPathComponent]);
}
// P-CORR-C: the manual Attach passes the same gate as the automatic one: LifeLog stopped, the session's own glasses
// connected (a link loss or other glasses never count) and settled over three readings spanning 2 s.
static void TestAttachGate(void){
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-gate"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/gate"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();TIOClenchConfig *c=Config(f,root,d);c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 NSURL *dir=s.directory;assert([[s attachGate:dir] isEqual:@"capturing"]);Put(day,@"realtime_gate.ogg",Ogg(3,1),Wall0+1,Wall0+3);
 Now=2;[s requestStop:@"manual"];Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished);
 Now=8;assert([[s attachGate:dir] isEqual:@"not-stopped"]);                      // LifeLog still running
 f.status[@"alwaysOnRunning"]=@NO;f.device=nil;Now=9;assert([[s attachGate:dir] isEqual:@"not-stopped"]);   // link loss
 f.device=@"device-B";Now=10;assert([[s attachGate:dir] isEqual:@"not-stopped"]);                         // other glasses
 f.device=@"device-A";Now=11;assert([[s attachGate:dir] isEqual:@"settling"]);Now=12;assert([[s attachGate:dir] isEqual:@"settling"]);
 f.device=nil;Now=12.5;assert([[s attachGate:dir] isEqual:@"not-stopped"]);f.device=@"device-A";            // a drop restarts the count
 Now=13;assert([[s attachGate:dir] isEqual:@"settling"]);Now=14;assert([[s attachGate:dir] isEqual:@"settling"]);Now=15;assert(![s attachGate:dir]);
 assert([Manifest(dir)[@"officialStopObservedMs"] isEqual:@((Wall0+13)*1000)]);
 NSDictionary *r=TIOClenchAttachOfficial(dir,home);assert([r[@"files"] isEqual:@1]&&[r[@"state"] isEqual:@"done"]);
 f.device=nil;f.status[@"alwaysOnRunning"]=@YES;assert(![s attachGate:dir]); // done: only reports, copies nothing
 // A session whose dump restore is outstanding is never attached, settled or not.
 Fake *g=NewFake(NO,NO);TIOClenchConfig *gc=Config(g,NewRoot(),Defaults());gc.officialHome=home;Now=0;TIOClenchSession *t=[[TIOClenchSession alloc]initWithConfig:gc];assert(![t startWithLabel:@"chew" source:@"lifelog"]);
 g.sticks=NO;Now=1;[t lifecycleStop:@"app-inactive"];g.status[@"alwaysOnRunning"]=@NO;for(double n=2;n<6;n++){Now=n;assert([[t attachGate:t.directory] isEqual:@"dump-outstanding"]);}
}
// P-CORR-D: duration and stored counters end at the session's effective deadline (an earlier stop plus its tail), not at
// the 125 s receive limit, however late the finishing tick runs.
static void TestEffectiveDeadline(void){
 Fake *f=NewFake(NO,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"talk");Now=10;[s requestStop:@"manual"];Now=12;[s tick];
 assert([[s manifest][@"durationSeconds"] isEqual:@12]);Now=300;[s tick];assert(s.phase==TIOClenchPhaseFinished&&s.durationSeconds==15);
 NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");assert([m[@"durationSeconds"] isEqual:@15]&&[m[@"deadlineOverrunSeconds"] isEqual:@285]&&[m[@"stopRequestedAtSeconds"] isEqual:@10]);
 for(NSDictionary *c in m[@"officialCounters"])assert([c[@"t"] doubleValue]<=15);
 // A lifecycle stop inside the tail ends at its own time.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"talk");Now=10;[s requestStop:@"manual"];Now=12;[s lifecycleStop:@"app-inactive"];assert(s.durationSeconds==12&&[Manifest(s.directory)[@"durationSeconds"] isEqual:@12]);
 // A packet stored inside the tail is covered; the duration still ends at the deadline.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"talk");Now=10;[s requestStop:@"manual"];[s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:14.5];Now=200;[s tick];
 m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");assert([m[@"durationSeconds"] isEqual:@15]&&[m[@"packets"] count]==1);
}
// P-CORR-E: the key name decides the unit before the magnitude, and the best time key wins over the first that parses.
static void TestEventTimeKeys(void){
 NSDate *s=[NSDate dateWithTimeIntervalSince1970:Wall0],*e=[NSDate dateWithTimeIntervalSince1970:Wall0+130];NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];
 assert(!TIOClenchFilterOfficialEvent(@{@"eventTsMs":@(Wall0+5),@"vpuMask":@1},s,e));              // epoch seconds under an ms name: no time
 assert(!TIOClenchFilterOfficialEvent(@{@"timeMs":@(Wall0+5),@"text":@"x"},s,e));
 assert([TIOClenchFilterOfficialEvent(@{@"eventTs":@(Wall0+5),@"vpuMask":@1},s,e) isEqual:(@{@"eventTs":@(Wall0+5),@"vpuMask":@1})]); // unit-less: magnitude
 // eventTs (seconds, outside) comes first in key order, but timestampMs (epoch ms, inside) is the better reading.
 NSDictionary *o=TIOClenchFilterOfficialEvent(@{@"eventTs":@(Wall0+500),@"timestampMs":@((Wall0+5)*1000),@"vpuMask":@1},s,e);
 assert([o isEqual:(@{@"timestampMs":@((Wall0+5)*1000),@"vpuMask":@1})]);
 assert(!TIOClenchFilterOfficialEvent(@{@"ts":@(Wall0+5),@"tsMs":@((Wall0+500)*1000)},s,e));         // the best reading is outside: dropped
 o=TIOClenchFilterOfficialEvent(@{@"timestamp":[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:Wall0+999]],@"time":@((Wall0+5)*1000)},s,e);assert([o isEqual:(@{@"time":@((Wall0+5)*1000)})]);
 o=TIOClenchFilterOfficialEvent(@{@"eventTsMs":@"soon",@"time":@(Wall0+5)},s,e);assert([o isEqual:(@{@"time":@(Wall0+5)})]);
 o=TIOClenchFilterOfficialEvent(@{@"eventTsMs":@((Wall0+6)*1000),@"eventTs":@((Wall0+6)*1000),@"frameCount":@2},s,e);assert([o isEqual:(@{@"eventTsMs":@((Wall0+6)*1000),@"frameCount":@2})]); // one time key kept
}
// P-CORR-F / S1-1: the dump was on and LifeLog running at Start, so the official file was already open (in the start
// snapshot, same inode). Everything before its size at Start is official audio from before the session (up to hours of
// LifeLog), so it is never copied into the session or its share zip, however much it grew during the window; it is skipped
// with its reason and size at Start. A file born inside the window is still attached.
static void TestPreExistingGrown(void){
 NSFileManager *fm=NSFileManager.defaultManager;NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-grown"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/grown"];assert([fm createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 // One official stream (legacy granules) that the writer extends by three pages during the window.
 NSData *stream=OggG(7,1,YES),*head=[stream subdataWithRange:NSMakeRange(0,stream.length-90)],*tail=[stream subdataWithRange:NSMakeRange(stream.length-90,90)];NSURL *open=Put(day,@"realtime_open.ogg",head,Wall0-600,Wall0-1),*cut=Put(day,@"realtime_cut.ogg",Ogg(5,4),Wall0-600,Wall0-2);
 Put(day,@"cached_same.ogg",Ogg(2,3),Wall0-600,Wall0-300);
 NSURL *pcm=Put(day,@"realtime_open.pcm",[NSMutableData dataWithLength:64],Wall0-600,Wall0-1),*lateURL=Put(day,@"realtime_late.ogg",Ogg(2,5),Wall0-600,Wall0-1);
 Fake *f=NewFake(YES,NO);NSURL *root=NewRoot();TIOClenchConfig *c=Config(f,root,Defaults());c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 NSDictionary *snap=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"official-snapshot.json"]] options:0 error:nil];assert([snap[@"files"] count]==5);
 void(^append)(NSURL *,NSData *)=^(NSURL *u,NSData *x){NSFileHandle *h=[NSFileHandle fileHandleForWritingToURL:u error:nil];[h seekToEndOfFile];[h writeData:x];[h closeFile];};
 append(open,tail);Times(open,Wall0-600,Wall0+4);append(pcm,[NSMutableData dataWithLength:32]);Times(pcm,Wall0-600,Wall0+4);append(lateURL,tail);Times(lateURL,Wall0-600,Wall0+5000);
 NSFileHandle *t=[NSFileHandle fileHandleForWritingToURL:cut error:nil];[t truncateFileAtOffset:40];[t closeFile];Times(cut,Wall0-600,Wall0+3);
 NSData *fresh=Ogg(3,6);Put(day,@"realtime_new.ogg",fresh,Wall0+1,Wall0+3); // this session's own file
 Now=2;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=6.5;[s tick];Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished&&!s.pending);
 NSDictionary *r=TIOClenchAttachOfficial(s.directory,home);assert([r[@"files"] isEqual:@1]&&[r[@"state"] isEqual:@"done"]);NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 NSDictionary *e=m[@"officialDump"][0];assert([m[@"officialDump"] count]==1&&[e[@"originalName"] isEqual:@"realtime_new.ogg"]&&[e[@"origin"] isEqual:@"new-in-window"]&&!e[@"containsAudioBeforeSession"]);
 assert([[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:e[@"file"]]] isEqual:fresh]);
 for(NSDictionary *x in m[@"officialDump"])assert(![x[@"origin"] isEqual:@"pre-existing-grown"]);
 NSMutableDictionary *reasons=[NSMutableDictionary new],*rows=[NSMutableDictionary new];for(NSDictionary *k in m[@"officialDumpSkipped"]){reasons[k[@"originalName"]]=k[@"reason"];rows[k[@"originalName"]]=k;}
 assert([reasons isEqual:(@{@"realtime_open.ogg":@"pre-existing-file-grown",@"realtime_late.ogg":@"pre-existing-file-grown",@"realtime_open.pcm":@"pre-existing-file-grown",@"realtime_cut.ogg":@"pre-existing-file-changed"})]); // the unchanged file is not listed
 assert([rows[@"realtime_open.ogg"][@"sourceBytesAtStart"] isEqual:@(head.length)]&&[rows[@"realtime_open.ogg"][@"containsAudioBeforeSession"] isEqual:@YES]);
 // The share zip holds no byte of the pre-existing stream.
 NSURL *zip=TIOClenchZipSession(s.directory,[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"exports/Grown"]);NSData *z=[NSData dataWithContentsOfURL:zip];
 assert(zip&&[z rangeOfData:head options:0 range:NSMakeRange(0,z.length)].location==NSNotFound&&[z rangeOfData:fresh options:0 range:NSMakeRange(0,z.length)].location!=NSNotFound);
 assert([fm removeItemAtURL:zip.URLByDeletingLastPathComponent error:nil]);
}
// P-CORR-G: a session in use (an attach or zip running, or work the UI registered) is never deleted.
static void TestDeleteInUse(void){
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();Now=0;TIOClenchSession *s=Started(f,root,Defaults(),@"chew");Now=1;[s lifecycleStop:@"test"];NSURL *dir=s.directory;
 assert(!TIOClenchSessionInUse(dir));TIOClenchBeginSessionWork(dir);TIOClenchBeginSessionWork(dir);assert(TIOClenchSessionInUse(dir)&&!TIOClenchDeleteSession(root,dir)&&RealDirExists(dir));
 TIOClenchEndSessionWork(dir);assert(TIOClenchSessionInUse(dir)&&!TIOClenchDeleteSession(root,dir));TIOClenchEndSessionWork(dir);assert(!TIOClenchSessionInUse(dir));
 // Attach and zip register the session only while they run.
 assert(TIOClenchAttachOfficial(dir,OfficialHome)&&!TIOClenchSessionInUse(dir));NSURL *zip=TIOClenchZipSession(dir,[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"exports/InUse"]);assert(zip&&!TIOClenchSessionInUse(dir));
 // An attach on a background queue and a delete on this thread never interleave: either the delete is refused while the
 // attach runs, or it runs first and the attach finds no session.
 __block NSDictionary *bg=nil;dispatch_semaphore_t done=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{bg=TIOClenchAttachOfficial(dir,OfficialHome);dispatch_semaphore_signal(done);});
 BOOL deleted=NO;while(!deleted&&dispatch_semaphore_wait(done,DISPATCH_TIME_NOW))deleted=TIOClenchDeleteSession(root,dir);
 if(!deleted){assert(bg);deleted=TIOClenchDeleteSession(root,dir);}else dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
 assert(deleted&&!RealDirExists(dir)&&!TIOClenchSessionInUse(dir));
}
// C1-1: the panel's session list read mid-capture is stale once the capture finishes (phase moved, and the session's row
// holds no finished manifest), and again whenever the pending record changes (a confirmed stop), so the finished row is
// complete, offers Share/Attach, shows the current stop state and is auto-attached.
static void TestListStale(void){
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];
 NSArray *rows=TIOClenchListSessions(root);NSString *key=TIOClenchListStateKey(s);assert(!TIOClenchSessionListStale(rows,key,s));
 assert(![s startWithLabel:@"chew" source:@"lifelog"]);assert(TIOClenchSessionListStale(rows,key,s));
 // The page reappears mid-capture (the user went to the official app and came back to Mark).
 Now=1;assert([s mark]);Now=3;[s requestStop:@"manual"];rows=TIOClenchListSessions(root);key=TIOClenchListStateKey(s);
 assert(!TIOClenchSessionListStale(rows,key,s)&&[rows[0][@"id"] isEqual:s.sessionId]&&![rows[0][@"manifest"][@"captureState"] isEqual:@"finished"]);
 Now=8;[s tick];assert(s.phase==TIOClenchPhaseFinished&&s.stopPending&&TIOClenchSessionListStale(rows,key,s));
 // Even if the key were read after finish, a row listed without its finished manifest is stale.
 assert(TIOClenchSessionListStale(@[@{@"id":s.sessionId,@"url":s.directory,@"complete":@NO}],TIOClenchListStateKey(s),s));
 assert(TIOClenchSessionListStale(rows,TIOClenchListStateKey(s),s));
 rows=TIOClenchListSessions(root);key=TIOClenchListStateKey(s);assert(!TIOClenchSessionListStale(rows,key,s));
 assert([rows[0][@"complete"] isEqual:@YES]&&[rows[0][@"manifest"][@"captureState"] isEqual:@"finished"]&&[rows[0][@"manifest"][@"stopPending"] isEqual:@YES]&&[rows[0][@"manifest"][@"marks"] count]==1);
 // The user confirms the stop: the cached row still says pending, so the list is stale until re-read.
 assert([s confirmPhysicalStop]&&!s.pending&&TIOClenchSessionListStale(rows,key,s));
 rows=TIOClenchListSessions(root);key=TIOClenchListStateKey(s);assert(!TIOClenchSessionListStale(rows,key,s)&&[rows[0][@"manifest"][@"stopPending"] isEqual:@NO]);
 // The finished session deleted from the list: nothing to refresh.
 assert(TIOClenchDeleteSession(root,s.directory));rows=TIOClenchListSessions(root);key=TIOClenchListStateKey(s);assert(!rows.count&&!TIOClenchSessionListStale(rows,key,s));
}
// C1-3: official values Lane T's validator would reject (fractional counts, out-of-range tags) are dropped, integral floats
// are written as integers, and at most 64 dump files are attached (the rest skipped with a reason).
static void TestOfficialTypes(void){
 NSDate *s0=[NSDate dateWithTimeIntervalSince1970:Wall0],*e0=[NSDate dateWithTimeIntervalSince1970:Wall0+130];
 NSDictionary *o=TIOClenchFilterOfficialEvent(@{@"eventTsMs":@((Wall0+1)*1000),@"vadStart":@0.35,@"bytes":@12.5,@"frameCount":@2.0,@"vpuOn":@YES,@"index":@(-3),@"packets":@(UINT64_MAX),
  @"seq":@"12",@"type":@(-1),@"source":@(1ULL<<33),@"kind":@YES,@"taskId":@7,@"event":@"a3_batch"},s0,e0);
 assert([o isEqual:(@{@"eventTsMs":@((Wall0+1)*1000),@"frameCount":@2,@"vpuOn":@YES,@"index":@(-3),@"packets":@(UINT64_MAX),@"taskId":@7,@"event":@"a3_batch"})]);
 assert(IsInt(o[@"frameCount"])&&IsBool(o[@"vpuOn"])&&IsInt(o[@"index"]));
 NSString *j=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];
 assert([j rangeOfString:@"\"frameCount\":2,"].location!=NSNotFound&&[j rangeOfString:@"\"vpuOn\":true"].location!=NSNotFound);
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-cap"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/cap"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 Fake *f=NewFake(NO,NO);TIOClenchConfig *c=Config(f,NewRoot(),Defaults());c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 for(int i=0;i<70;i++)Put(day,[NSString stringWithFormat:@"realtime_%02d.ogg",i],Ogg(1,(uint8_t)i),Wall0+1,Wall0+2);
 Put(day,@"events.jsonl",Lines(@[@{@"eventTsMs":@((Wall0+1)*1000),@"type":@"a3",@"vadStart":@0.35,@"bytes":@12.5,@"frameCount":@2.0}]),Wall0+1,Wall0+2);
 Now=2;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=7;[s tick];assert(s.phase==TIOClenchPhaseFinished);
 NSDictionary *r=TIOClenchAttachOfficial(s.directory,home);assert([r[@"files"] isEqual:@64]&&[r[@"state"] isEqual:@"done"]);NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert([m[@"officialDump"] count]==64&&[m[@"officialDumpSkipped"] count]==6);for(NSDictionary *k in m[@"officialDumpSkipped"])assert([k[@"reason"] isEqual:@"dump-cap-64-files"]&&[k[@"originalName"] compare:@"realtime_64.ogg"]!=NSOrderedAscending);
 NSString *events=[NSString stringWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"official-events.jsonl"] encoding:NSUTF8StringEncoding error:nil];
 NSDictionary *kept=[NSJSONSerialization JSONObjectWithData:[[events componentsSeparatedByString:@"\n"][0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 assert([kept isEqual:(@{@"eventTsMs":@((Wall0+1)*1000),@"type":@"a3",@"frameCount":@2})]&&[events rangeOfString:@"."].location==NSNotFound);
 assert([m[@"officialEvents"][@"droppedKeyCounts"] isEqual:(@{@"vadStart":@1,@"bytes":@1})]);
}
// C1-4: tap envelopes queued on the main queue while capturing but processed after finish (a tick or a lifecycle stop ran
// first) are counted in the written manifest, never silently lost. Arrivals after the end never count.
static void TestLateTap(void){
 Fake *f=NewFake(NO,NO);Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(1),@"deviceId":@"device-A"}},1.5);
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(2),@"deviceId":@"device-B"}},1.6);
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@20,@"payload":Env(1,2,@{},nil),@"deviceId":@"device-A"}},1.7);
 Now=2;[s lifecycleStop:@"app-inactive"];assert(s.packetCount==0&&!TIOClenchTapActive()&&[Manifest(s.directory)[@"droppedPackets"] isEqual:@0]);
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(3),@"deviceId":@"device-A"}},2.5); // inactive: never queued
 Drain();NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert(s.droppedPackets==2&&[m[@"droppedPackets"] isEqual:@2]&&[m[@"dropReasons"] isEqual:(@{@"arrived-before-finish-unprocessed":@1,@"other-device":@1})]&&![m[@"packets"] count]);
 [s receiveBusiness:13 payload:A3(4) device:@"device-A" arrival:2.5];assert([Manifest(s.directory)[@"droppedPackets"] isEqual:@2]); // arrived after the end
 // Queued inside the tail but past the deadline (stop at 10, deadline 15), finished by a late tick at 20: after-window.
 Now=0;s=Started(NewFake(NO,NO),NewRoot(),Defaults(),@"chew");Now=10;[s requestStop:@"manual"];
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(5),@"deviceId":@"device-A"}},16);
 TIOClenchTapEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@13,@"payload":A3(6),@"deviceId":@"device-A"}},14);
 Now=20;[s tick];assert(s.phase==TIOClenchPhaseFinished);Drain();m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");
 assert([m[@"dropReasons"] isEqual:(@{@"after-window":@1,@"arrived-before-finish-unprocessed":@1})]&&[m[@"droppedPackets"] isEqual:@2]);
}
// C1-5: the wake-word context is read once at Start, so wake-up sends are refused while capturing.
static void TestWakeGate(void){
 Fake *f=NewFake(NO,NO);TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:Config(f,NewRoot(),Defaults())];assert(s.wakeCommandAllowed);
 Now=0;assert(![s startWithLabel:@"talk" source:@"lifelog"]&&!s.wakeCommandAllowed);Now=3;[s requestStop:@"manual"];assert(!s.wakeCommandAllowed); // the tail still captures
 Now=8;[s tick];assert(s.phase==TIOClenchPhaseFinished&&s.wakeCommandAllowed);
}
// C1-6: a capture whose process dies (crash, jetsam: no finish, no WillTerminate) keeps its marks, packets and window up to
// the last checkpoint. The next launch cuts envelopes.rnp back to what that checkpoint lists, once; the session is listed
// complete, attaches and zips.
static void TestCheckpoint(void){
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();TIOClenchConfig *c=Config(f,root,d);c.officialHome=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-none"];
 NSURL *dir=nil;NSString *sid=nil;NSUInteger one=TIOClenchFrame(A3(1)).length;NSURL *rnp=nil;
 @autoreleasepool{
  Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"double-tap" source:@"lifelog"]);dir=s.directory;sid=s.sessionId;rnp=[dir URLByAppendingPathComponent:@"envelopes.rnp"];
  NSDictionary *m=Manifest(dir);CheckManifest(m,@"0123abcd-dirty");assert([m[@"captureState"] isEqual:@"interrupted"]&&[m[@"checkpoint"][@"envelopeFileBytes"] isEqual:@0]&&IsNum(m[@"wallClockWindow"][@"endMs"])); // at Start
  assert([TIOClenchListSessions(root)[0][@"complete"] isEqual:@YES]&&TIOClenchSessionInUse(dir)&&!TIOClenchDeleteSession(root,dir)); // the live capture is in use
  Now=1;assert([s mark]);[s receiveBusiness:13 payload:A3(1) device:@"device-A" arrival:1.5];
  Now=4.75;[s tick];assert([Manifest(dir)[@"checkpoint"][@"envelopeFileBytes"] isEqual:@0]);
  Now=5;[s tick];m=Manifest(dir);CheckManifest(m,@"0123abcd-dirty");
  assert([m[@"captureState"] isEqual:@"interrupted"]&&[m[@"checkpoint"][@"envelopeFileBytes"] isEqual:@(one)]&&[m[@"checkpoint"][@"atSeconds"] isEqual:@5]&&[m[@"marks"] count]==1&&[m[@"packets"] count]==1);
  assert([m[@"durationSeconds"] isEqual:@5]&&[m[@"wallClockWindow"][@"endMs"] isEqual:@((Wall0+5)*1000)]&&[m[@"stopPending"] isEqual:@YES]&&m[@"finalizedAtSeconds"]==NSNull.null);
  [s receiveBusiness:13 payload:A3(2) device:@"device-A" arrival:6];assert([[NSData dataWithContentsOfURL:rnp] length]==2*one);
  s=nil; // the process dies here
 }
 assert(!TIOClenchTapActive()&&!TIOClenchSessionInUse(dir));
 TIOClenchSession *next=[[TIOClenchSession alloc]initWithConfig:c];
 assert([[NSData dataWithContentsOfURL:rnp] isEqual:TIOClenchFrame(A3(1))]&&[next.pending[@"sessionId"] isEqual:sid]&&[[next startWithLabel:@"chew" source:@"lifelog"] isEqual:@"pending"]);
 NSDictionary *m=Manifest(dir);CheckManifest(m,@"0123abcd-dirty");assert([m[@"checkpoint"][@"recovered"] isEqual:@YES]&&[m[@"checkpoint"][@"envelopeBytesCut"] isEqual:@(one)]&&[m[@"packets"] count]==1&&[m[@"marks"] count]==1);
 NSString *at=m[@"checkpoint"][@"recoveredAt"];(void)[[TIOClenchSession alloc]initWithConfig:c];assert([Manifest(dir)[@"checkpoint"][@"recoveredAt"] isEqual:at]); // once
 NSArray *rows=TIOClenchListSessions(root);assert(rows.count==1&&[rows[0][@"complete"] isEqual:@YES]);
 assert(TIOClenchAttachOfficial(dir,c.officialHome)&&[Manifest(dir)[@"officialAttach"] isEqual:@"done"]);
 NSURL *zip=TIOClenchZipSession(dir,[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"exports/Checkpoint"]);assert(zip);assert([NSFileManager.defaultManager removeItemAtURL:zip.URLByDeletingLastPathComponent error:nil]);
 // A finished capture replaces the checkpoint with its final manifest.
 assert([next restorePendingDump]&&![f.status[@"dumpEnabled"] boolValue]&&[next confirmPhysicalStop]&&!next.pending);Now=0;assert(![next startWithLabel:@"chew" source:@"lifelog"]);Now=1;[next lifecycleStop:@"test"];
 m=Manifest(next.directory);CheckManifest(m,@"0123abcd-dirty");assert([m[@"captureState"] isEqual:@"finished"]&&!m[@"checkpoint"]&&!TIOClenchSessionInUse(next.directory));
}
// S1-3: MapKit navigation and the camera save and restore the same idle-timer flag. The Lab writes it only when needed and
// never writes back a remembered "disabled". C2-4/S2-02 known limitation (shared by those holders): one that starts while the
// Lab holds the flag saves the Lab's "disabled" and writes it back when it ends; the Lab cannot prevent that.
static void TestIdleTimerSharing(void){
 // Navigation held it at Start and ended mid-capture (writing its saved "enabled"): the Lab takes over, then re-enables it.
 Fake *f=NewFake(NO,NO);f.idle=YES;Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");assert(f.idle&&f.idleSets==0&&s.holdsIdleTimer);
 f.idle=NO;Now=1;[s tick];assert(f.idle&&f.idleSets==1);
 Now=2;[s lifecycleStop:@"app-inactive"];assert(!f.idle&&f.idleSets==2);NSDictionary *it=Manifest(s.directory)[@"idleTimer"];assert([it[@"outcome"] isEqual:@"restored"]&&[it[@"setByLab"] isEqual:@YES]&&[it[@"priorDisabled"] isEqual:@YES]);
 // Navigation still holds it at the end: untouched (before the fix the Lab wrote its saved "disabled" after nav ended).
 f=NewFake(NO,NO);f.idle=YES;Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");Now=1;[s tick];Now=2;[s lifecycleStop:@"app-inactive"];
 assert(f.idle&&f.idleSets==0&&[Manifest(s.directory)[@"idleTimer"][@"outcome"] isEqual:@"left-to-other-holder"]);
 f.idle=NO;[s releaseIdleTimer];assert(!f.idle&&f.idleSets==0); // navigation ends later: stays enabled
 // Someone enabled it again just before the capture ended: the Lab does not write it a second time.
 f=NewFake(NO,NO);Now=0;s=Started(f,NewRoot(),Defaults(),@"chew");assert(f.idle&&f.idleSets==1);f.idle=NO;Now=2;[s lifecycleStop:@"app-inactive"];
 assert(!f.idle&&f.idleSets==1&&[Manifest(s.directory)[@"idleTimer"][@"outcome"] isEqual:@"already-enabled"]);
 // C2-4/S2-02: the camera went live (or navigation started) while the Lab held the flag. Still on screen when the capture
 // ends, it holds the flag: the Lab leaves it alone instead of turning auto-lock back on under it. Off screen: restored.
 for(int on=0;on<2;on++){Fake *g=NewFake(NO,NO);TIOClenchConfig *c=Config(g,NewRoot(),Defaults());c.idleTimerHeldElsewhere=^BOOL{return on==1;};
  Now=0;s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]&&g.idle&&g.idleSets==1);Now=2;[s lifecycleStop:@"app-inactive"];
  assert(g.idle==(on==1)&&g.idleSets==(on?1u:2u)&&!s.holdsIdleTimer&&[Manifest(s.directory)[@"idleTimer"][@"outcome"] isEqual:on?@"left-to-active-holder":@"restored"]);}
 // Only a flag the Lab set is ever left to an on-screen holder; one it found disabled stays "left-to-other-holder".
 Fake *h=NewFake(NO,NO);h.idle=YES;TIOClenchConfig *hc=Config(h,NewRoot(),Defaults());hc.idleTimerHeldElsewhere=^BOOL{return YES;};Now=0;s=[[TIOClenchSession alloc]initWithConfig:hc];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 Now=2;[s lifecycleStop:@"app-inactive"];assert(h.idle&&h.idleSets==0&&[Manifest(s.directory)[@"idleTimer"][@"outcome"] isEqual:@"left-to-other-holder"]);
}
// S1-4: a dump restore waived because the official interface was unavailable unblocks Start only. It stays owed across
// launches, blocks attach, is restored (read back) once the interface returns, and Start resolves it first.
static void TestOwedRestore(void){
 NSDictionary *prior=@{@"enabled":@NO,@"realtime":@YES,@"cached":@YES,@"events":@NO};
 Fake *f=NewFake(NO,NO);NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;TIOClenchSession *s=Started(f,root,d,@"chew");NSURL *dir=s.directory;f.sticks=NO;[s lifecycleStop:@"background"];
 assert([s.pending[@"dumpRestored"] isEqual:@NO]&&[f.status[@"dumpEvents"] boolValue]);
 f.statusNil=YES;TIOClenchSession *next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert([next confirmPhysicalStop]&&!next.pending&&next.restoreOwed);
 assert([d dictionaryForKey:@"clenchLab.restoreOwed.v1"]&&![d dictionaryForKey:@"clenchLab.pending.v1"]&&[Manifest(dir)[@"dumpRestoreWaived"] isEqual:@"official-interface-unavailable-user-confirmed"]);
 assert([[next attachGate:dir] isEqual:@"dump-outstanding"]);
 NSUInteger calls=f.calls.count;assert(![next restorePendingDump]&&f.calls.count==calls&&next.restoreOwed); // still unavailable: kept, nothing called
 TIOClenchSession *later=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert(later.restoreOwed&&!later.pending); // a later launch still owes it
 f.statusNil=NO;f.sticks=YES;assert([later restorePendingDump]&&f.calls.count==calls+1&&[f.calls.lastObject isEqual:prior]&&!later.restoreOwed&&![d dictionaryForKey:@"clenchLab.restoreOwed.v1"]);
 assert(![f.status[@"dumpEnabled"] boolValue]&&![f.status[@"dumpEvents"] boolValue]);
 NSDictionary *m=Manifest(dir);assert([m[@"dumpRestored"] isEqual:@YES]&&[m[@"dumpRestoredAfterWaiver"] isEqual:@YES]&&[m[@"dumpRestoreOutcome"] isEqual:@"restored"]&&[m[@"dumpRestoreExact"] isEqual:@YES]&&[m[@"dumpConfig"][@"restoreReadBack"] isEqual:prior]);
 f.status[@"alwaysOnRunning"]=@NO;assert(![later attachGate:dir]||[[later attachGate:dir] isEqual:@"settling"]);
 // Start resolves an owed restore first: the new session's prior is the user's own setting, not the Lab's config.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];f.statusNil=YES;
 next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert([next confirmPhysicalStop]&&next.restoreOwed);f.statusNil=NO;f.sticks=YES;calls=f.calls.count;
 assert(![next startWithLabel:@"chew" source:@"lifelog"]&&!next.restoreOwed&&f.calls.count==calls+2&&[f.calls[calls] isEqual:prior]);
 assert([Manifest(next.directory)[@"dumpConfig"][@"prior"] isEqual:prior]);Now=1;[next lifecycleStop:@"test"];assert([Manifest(next.directory)[@"dumpConfig"][@"prior"] isEqual:prior]);
 // An owed restore that still does not read back when Start runs: an open record again, Start refused, the retry path works.
 f=NewFake(NO,NO);root=NewRoot();d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];f.statusNil=YES;
 next=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];assert([next confirmPhysicalStop]&&next.restoreOwed);f.statusNil=NO;
 assert([[next startWithLabel:@"chew" source:@"lifelog"] isEqual:@"pending"]&&!next.restoreOwed&&next.pending&&[next.pending[@"dumpRestored"] isEqual:@NO]&&!next.pending[@"dumpRestoreWaived"]&&[next.pending[@"stopPending"] isEqual:@NO]);
 assert(next.phase!=TIOClenchPhaseCapturing&&[TIOClenchListSessions(root) count]==1);f.sticks=YES;assert([next retryPending]&&!next.pending&&![f.status[@"dumpEvents"] boolValue]);
}
// S2-01 / C2-5: a lifecycle stop at 3 s gives an effective deadline of 8 s, so last writes count to startWallMs + 13 s
// (8 s + 5 s flush slack). The old 10-minute late-write grace is gone: a stop seen much later never widens what is copied.
// The copied entries' writtenAfterLabWindow is a JSON boolean (true and false), never 1 or 0.
static void TestConsentWindow(void){
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-consent"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/consent"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 Fake *f=NewFake(YES,NO);TIOClenchConfig *c=Config(f,NewRoot(),Defaults());c.officialHome=home;Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 Now=3;[s lifecycleStop:@"app-inactive"];assert(s.phase==TIOClenchPhaseFinished);NSURL *dir=s.directory;
 Put(day,@"realtime_quick.ogg",Ogg(3,1),Wall0+1,Wall0+6);Put(day,@"realtime_in.ogg",Ogg(3,2),Wall0+1,Wall0+10);Put(day,@"realtime_edge.ogg",Ogg(3,3),Wall0+1,Wall0+13);
 Put(day,@"realtime_after.ogg",Ogg(3,4),Wall0+1,Wall0+13.5);Put(day,@"realtime_grace.ogg",Ogg(3,5),Wall0+2,Wall0+300);
 assert(TIOClenchMergeManifest(dir,@{@"officialStopObservedMs":@((Wall0+400)*1000)})); // seen stopped late: the old grace path copied realtime_grace
 NSDictionary *r=TIOClenchAttachOfficial(dir,home);NSDictionary *m=Manifest(dir);CheckManifest(m,@"0123abcd-dirty");assert([r[@"files"] isEqual:@3]&&[r[@"state"] isEqual:@"done"]);
 NSMutableDictionary *dump=[NSMutableDictionary new],*skip=[NSMutableDictionary new];for(NSDictionary *e in m[@"officialDump"])dump[e[@"originalName"]]=e[@"writtenAfterLabWindow"];for(NSDictionary *k in m[@"officialDumpSkipped"])skip[k[@"originalName"]]=k[@"reason"];
 assert([dump isEqual:(@{@"realtime_quick.ogg":@NO,@"realtime_in.ogg":@YES,@"realtime_edge.ogg":@YES})]&&[skip isEqual:(@{@"realtime_after.ogg":@"written-after-session",@"realtime_grace.ogg":@"written-after-session"})]);
 NSDictionary *w=m[@"officialAttachWindow"];assert([w[@"writeLimitMs"] isEqual:@((Wall0+13)*1000)]&&[w[@"effectiveDeadlineSeconds"] isEqual:@8]&&[w[@"flushSlackMs"] isEqual:@5000]&&[w[@"officialStopSource"] isEqual:@"observed"]&&!w[@"lateWriteGraceMs"]);
 NSString *raw=[NSString stringWithContentsOfURL:[dir URLByAppendingPathComponent:@"manifest.json"] encoding:NSUTF8StringEncoding error:nil];NSRegularExpression *flag=[NSRegularExpression regularExpressionWithPattern:@"\"writtenAfterLabWindow\" *: *([^,\\s]+)" options:0 error:nil];
 NSMutableArray *values=[NSMutableArray new];for(NSTextCheckingResult *x in [flag matchesInString:raw options:0 range:NSMakeRange(0,raw.length)])[values addObject:[raw substringWithRange:[x rangeAtIndex:1]]];
 assert(values.count==3&&[[NSSet setWithArray:values] isEqual:([NSSet setWithArray:@[@"true",@"false"]])]);
}
// S2-03: cached-kind files are never attached, so the Lab keeps the user's prior cached setting instead of forcing it on.
// The guarded restore and the crash recovery still recognise that config as the Lab's own and put the prior back.
static void TestCachedPrior(void){
 NSDictionary *lab=@{@"enabled":@YES,@"realtime":@YES,@"cached":@NO,@"events":@YES},*prior=@{@"enabled":@NO,@"realtime":@YES,@"cached":@NO,@"events":@NO};
 Fake *f=NewFake(NO,NO);f.status[@"dumpCachedAudio"]=@NO;Now=0;TIOClenchSession *s=Started(f,NewRoot(),Defaults(),@"chew");assert(f.calls.count==1&&[f.calls[0] isEqual:lab]&&![f.status[@"dumpCachedAudio"] boolValue]);
 Now=1;[s requestStop:@"manual"];assert(f.calls.count==2&&[f.calls[1] isEqual:prior]&&s.dumpRestored);Now=6;[s tick];
 NSDictionary *m=Manifest(s.directory);assert([m[@"dumpConfig"][@"lab"] isEqual:lab]&&[m[@"dumpConfig"][@"prior"] isEqual:prior]&&[m[@"dumpRestoreOutcome"] isEqual:@"restored"]&&[m[@"dumpRestoreExact"] isEqual:@YES]);
 f=NewFake(NO,NO);f.status[@"dumpCachedAudio"]=@NO;NSURL *root=NewRoot();NSUserDefaults *d=Defaults();Now=0;s=Started(f,root,d,@"chew");f.sticks=NO;[s lifecycleStop:@"background"];assert([s.pending[@"dumpRestored"] isEqual:@NO]);
 f.sticks=YES;NSUInteger calls=f.calls.count;TIOClenchSession *again=[[TIOClenchSession alloc]initWithConfig:Config(f,root,d)];
 assert([again restorePendingDump]&&f.calls.count==calls+1&&[f.calls.lastObject isEqual:prior]&&[Manifest(s.directory)[@"dumpRestoreOutcome"] isEqual:@"restored"]);
}
// C2-1: each officialCounters row reads the official status first, then the monotonic and wall clocks back to back, and
// Start takes t0 and startWallMs from one such read: a slow status call never skews wallMs-1000*t (anchor drift stays 0).
static void TestAnchorPairs(void){
 Fake *f=NewFake(NO,NO);TIOClenchConfig *c=Config(f,NewRoot(),Defaults());c.dumpStatus=^NSDictionary *{Now+=0.013;return [f.status copy];}; // every status call takes 13 ms
 Now=0;TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"chew" source:@"lifelog"]);
 for(int k=1;k<=20;k++){Now=0.25*k+0.03;[s tick];}Now=6;[s lifecycleStop:@"test"];
 NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"0123abcd-dirty");double start=[m[@"startWallMs"] doubleValue];NSArray *cs=m[@"officialCounters"];assert(cs.count>=20);
 for(NSDictionary *x in cs)assert(fabs([x[@"wallMs"] doubleValue]-1000*[x[@"t"] doubleValue]-start)<=1);
 assert([cs[0][@"t"] doubleValue]>0); // the first row's t is read after its status call, not assumed to be 0
}
// A complete synthetic session for Lane T's validator: manifest, empty envelopes.rnp (passive LifeLog), one attached
// official realtime Ogg dump (alignment "unaligned") and its allow-listed official-events.jsonl. The dump carries the
// official legacy granule quirk (mono 60 ms TOC packets, granules +960 per packet), so Lane T reports granuleMode legacy.
// Each event batch lies inside its own one-step realtimePackets increment window: (2,4.5] holds t=3 and (4.5,7] t=6.
static void WriteSample(NSURL *root){
 NSURL *home=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official-sample"],*day=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/sample"];assert([NSFileManager.defaultManager createDirectoryAtURL:day withIntermediateDirectories:YES attributes:nil error:nil]);
 Fake *f=NewFake(NO,NO);TIOClenchConfig *c=Config(f,root,Defaults());c.officialHome=home;c.appCommit=TIOClenchBuildCommit();c.synthetic=YES;Now=0;
 TIOClenchSession *s=[[TIOClenchSession alloc]initWithConfig:c];assert(![s startWithLabel:@"double-tap" source:@"lifelog"]);
 NSArray *steps=@[@[@2,@0],@[@4.5,@1],@[@7,@2]];for(NSArray *st in steps){Now=[st[0] doubleValue];f.status[@"realtimePackets"]=st[1];[s tick];assert([s mark]);}
 NSData *legacy=OggG(20,0,YES);Put(day,@"realtime_sample.ogg",legacy,Wall0+1,Wall0+9);
 Put(day,@"events.jsonl",Lines(@[@{@"eventTsMs":@((Wall0+3)*1000),@"type":@"realtime_batch",@"frameCount":@10,@"vpuMask":@0,@"vadMask":@1,@"text":@"dropped"},@{@"eventTsMs":@((Wall0+6)*1000),@"type":@"realtime_batch",@"frameCount":@10,@"vpuMask":@1,@"vadMask":@1}]),Wall0+1,Wall0+9);
 Now=10;[s requestStop:@"manual"];f.status[@"alwaysOnRunning"]=@NO;Now=14.5;[s tick];Now=15;[s tick];
 assert(s.phase==TIOClenchPhaseFinished&&!s.pending);NSDictionary *r=TIOClenchAttachOfficial(s.directory,home);assert([r[@"files"] isEqual:@1]&&[r[@"events"] isEqual:@2]);
 NSDictionary *m=Manifest(s.directory);CheckManifest(m,@"unknown");assert([m[@"synthetic"] isEqual:@YES]&&![m[@"packets"] count]&&[m[@"audioFormat"][@"provenance"] isEqual:@"synthetic"]&&[m[@"audioFormat"][@"sampleRate"] isEqual:@16000]);
 NSDictionary *dump=[m[@"officialDump"] firstObject];assert([dump[@"file"] isEqual:@"official-dump/00-realtime.ogg"]&&[dump[@"alignment"] isEqual:@"unaligned"]&&[dump[@"copyFinalized"] isEqual:@YES]&&[[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:dump[@"file"]]] isEqual:legacy]);
 assert([dump[@"granuleMode"] isEqual:@"official-legacy-20ms"]&&[dump[@"copyVerbatim"] isEqual:@YES]&&[dump[@"sha256"] isEqual:SHA(legacy)]);
 // Last page granule: 20 packets x 960 + 312 (legacy), not 20 x 2880 (TOC-correct).
 const uint8_t *lb=legacy.bytes;NSUInteger lastPage=legacy.length-30;uint64_t gp=0;for(int i=0;i<8;i++)gp|=(uint64_t)lb[lastPage+6+i]<<(8*i);assert(lb[lastPage]=='O'&&gp==20*960+312&&gp!=20*2880);
 // Counter steps: one increment per event batch, each window holding exactly its batch.
 NSMutableArray *windows=[NSMutableArray new];NSArray *cs=m[@"officialCounters"];for(NSUInteger i=1;i<cs.count;i++)if([cs[i][@"realtimePackets"] integerValue]>[cs[i-1][@"realtimePackets"] integerValue]){assert([cs[i][@"realtimePackets"] integerValue]-[cs[i-1][@"realtimePackets"] integerValue]==1);[windows addObject:@[cs[i-1][@"t"],cs[i][@"t"]]];}
 assert([windows isEqual:(@[@[@2,@4.5],@[@4.5,@7]])]&&[[cs.lastObject objectForKey:@"realtimePackets"] isEqual:@2]);
 assert([[NSString stringWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"official-events.jsonl"] encoding:NSUTF8StringEncoding error:nil] rangeOfString:@"dropped"].location==NSNotFound);
 assert([[NSData dataWithContentsOfURL:[s.directory URLByAppendingPathComponent:@"envelopes.rnp"]] length]==0);printf("sample session: %s\n",s.directory.fileSystemRepresentation);
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);Home=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"clench-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];assert(!mkdir(Home.fileSystemRepresentation,0700));
 OfficialHome=[[NSURL fileURLWithPath:Home] URLByAppendingPathComponent:@"official"];Suites=[NSMutableArray new];
 TestValues();TestEnvelope();TestWake();TestFilter();TestCapture();TestTiming();TestDump();TestPending();TestTap();TestAttachAndZip();TestConcurrentMerge();TestManyOfficialFiles();TestLateWriter();TestUserChangedDump();TestDumpOnlyWaiver();
 TestIdleTimer();TestListOrder();TestAttachGate();TestEffectiveDeadline();TestEventTimeKeys();TestPreExistingGrown();TestDeleteInUse();
 TestListStale();TestOfficialTypes();TestLateTap();TestWakeGate();TestCheckpoint();TestIdleTimerSharing();TestOwedRestore();
 TestConsentWindow();TestCachedPrior();TestAnchorPairs();
 NSURL *sample=[NSURL fileURLWithPath:@(argv[1])];assert(![NSFileManager.defaultManager fileExistsAtPath:sample.path]);WriteSample(sample);
 for(NSString *n in Suites)[[[NSUserDefaults alloc]initWithSuiteName:n] removePersistentDomainForName:n];
 assert([NSFileManager.defaultManager removeItemAtPath:Home error:nil]);
 puts("PASS: clench lab envelope framing/parsing, late official writer + settled auto-attach gate, uncapped official listing, user-changed dump left alone, dump-only waiver, idle timer held only while capturing (every end path), list sorted before cap, one attach gate (manual = automatic), effective-deadline duration, unit-by-key-name event times, pre-existing official files never copied, delete gated on in-use sessions, legacy-granule sample, manifest schema v1 + Amendments 1/1a (counters within duration, wallMs, unaligned dumps), labels/marks, 120/125 s caps with late-tick catch-up, dump enable/restore read-back and retry merge, launch dump recovery, pending stop (target glasses, two readings), protocol off, tap, events allow-list and file selection, windowed official attach (once, no cross-session claims), serialized manifest merges, stored zip, wake packets, stale session list after capture, Lane T official value types and 64-file cap, late tap packets counted, wake sends refused while capturing, crash checkpoint + rnp recovery, shared idle timer left to an on-screen holder, waived dump restore kept owed, official files last written after the effective deadline + 5 s never copied, cached-kind files skipped with the prior cached setting kept, status-then-clock anchor pairs, JSON boolean flags. Synthetic only.");
}return 0;}
