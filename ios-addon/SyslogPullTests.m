// Sensor-log pull: request bytes, 0x13/0x14 notices, file-share reassembly, lz4 decode and probe-line grep.
// The lz4 vector was made with the lz4 CLI from kText (frame with content checksum, 4 MiB blocks).
#import "SyslogPull.h"
#include <assert.h>
static NSString *const kText=@"[000001] boot ok\n[000002] [RAYNEO_RPMSG] sensor type: ST IMU(1)\n[000003] boot ok\n[000004] [KNOB]: Detected OTS ID 0x4A\n[000005] boot ok\n[000006] initHallStatus: is_hall_fold=0\n";
static const uint8_t kLZ4[]={0x04,0x22,0x4d,0x18,0x64,0x40,0xa7,0x8e,0x00,0x00,0x00,0x20,0x5b,0x30,0x01,0x00,0xb2,0x31,0x5d,0x20,0x62,0x6f,0x6f,0x74,0x20,0x6f,0x6b,0x0a,0x11,0x00,0xf3,0x19,0x32,0x5d,0x20,0x5b,0x52,0x41,0x59,0x4e,0x45,0x4f,0x5f,0x52,0x50,0x4d,0x53,0x47,0x5d,0x20,0x73,0x65,0x6e,0x73,0x6f,0x72,0x20,0x74,0x79,0x70,0x65,0x3a,0x20,0x53,0x54,0x20,0x49,0x4d,0x55,0x28,0x31,0x29,0x2f,0x00,0x1c,0x33,0x40,0x00,0xf3,0x10,0x34,0x5d,0x20,0x5b,0x4b,0x4e,0x4f,0x42,0x5d,0x3a,0x20,0x44,0x65,0x74,0x65,0x63,0x74,0x65,0x64,0x20,0x4f,0x54,0x53,0x20,0x49,0x44,0x20,0x30,0x78,0x34,0x41,0x37,0x00,0x1c,0x35,0x37,0x00,0xf0,0x13,0x36,0x5d,0x20,0x69,0x6e,0x69,0x74,0x48,0x61,0x6c,0x6c,0x53,0x74,0x61,0x74,0x75,0x73,0x3a,0x20,0x69,0x73,0x5f,0x68,0x61,0x6c,0x6c,0x5f,0x66,0x6f,0x6c,0x64,0x3d,0x30,0x0a,0x00,0x00,0x00,0x00,0x48,0x00,0xf1,0x4c};
static void Var(NSMutableData *d,uint64_t v){while(v>0x7f){uint8_t b=(v&0x7f)|0x80;[d appendBytes:&b length:1];v>>=7;}uint8_t b=v;[d appendBytes:&b length:1];}
static void Field(NSMutableData *d,uint32_t f,NSData *body){Var(d,(f<<3)|2);Var(d,body.length);[d appendData:body];}
static NSData *Str(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
static NSData *Sync(NSString *uuid,NSString *name,uint64_t size){NSMutableData *b=[NSMutableData new],*o=[NSMutableData new];Field(b,1,Str(uuid));Field(b,2,Str(name));Var(b,3<<3);Var(b,size);Field(b,4,Str(@"2234567890abcdef"));Var(b,5<<3);Var(b,17);Field(o,1,b);return o;}
static NSData *Chunk(NSString *uuid,uint64_t start,NSData *bytes){NSMutableData *b=[NSMutableData new],*o=[NSMutableData new];Field(b,1,Str(uuid));Var(b,3<<3);Var(b,start);Field(b,5,bytes);Field(o,4,b);return o;}
static NSData *Notice13(uint32_t size,NSString *name){const uint8_t h[1]={0x13};NSMutableData *d=[NSMutableData dataWithBytes:h length:1];uint8_t s[4]={size>>24,size>>16,size>>8,size};[d appendBytes:s length:4];NSMutableData *n=[NSMutableData dataWithData:Str(name)];n.length=50;[d appendData:n];return d;}
static NSData *Hex(NSString *h){NSMutableData *d=[NSMutableData new];for(NSUInteger i=0;i+1<h.length;i+=2){unsigned v;[[NSScanner scannerWithString:[h substringWithRange:NSMakeRange(i,2)]] scanHexInt:&v];uint8_t c=(uint8_t)v;[d appendBytes:&c length:1];}return d;}
int main(void){@autoreleasepool{
    // builder
    NSDictionary *r=TIOSyslogRequest();assert([r[@"businessId"] isEqual:@16]);
    const uint8_t want[4]={0xA1,0,0,0x12};assert([r[@"payload"] isEqual:[NSData dataWithBytes:want length:4]]);
    // 0x13 / 0x14 as the glasses sent them on the device (C18 wire log, 2026-11-12): no A1 prefix.
    NSDictionary *n=TIOSyslogParseNotice(Hex(@"130002c053726e7379736c6f675f32303236313131332d30322d34382d30312e6c7a340000000000000000000000000000000000000000"));
    assert([n[@"sub"] isEqual:@0x13]&&[n[@"size"] isEqual:@180307]&&[n[@"name"] isEqual:@"rnsyslog_20261113-02-48-01.lz4"]);
    NSData *dn=Hex(@"14726e7379736c6f675f32303236313131332d30322d34382d30312e6c7a340000000000000000000000000000000000000000");
    n=TIOSyslogParseNotice(dn);assert([n[@"sub"] isEqual:@0x14]&&[n[@"name"] isEqual:@"rnsyslog_20261113-02-48-01.lz4"]&&[n[@"raw"] isEqual:dn]);
    NSString *name=@"rnsyslog_20261112-14-03-07.lz4";n=TIOSyslogParseNotice(Notice13(3670016,name));
    assert([n[@"sub"] isEqual:@0x13]&&[n[@"size"] isEqual:@3670016]&&[n[@"name"] isEqual:name]);
    assert([TIOSyslogParseNotice(Notice13(1,@"defult_log"))[@"name"] isEqual:@"defult_log"]);
    assert(!TIOSyslogParseNotice([Notice13(1,@"x") subdataWithRange:NSMakeRange(0,54)])); // truncated
    NSMutableData *longer=[Notice13(1,@"x") mutableCopy];[longer appendBytes:"\0" length:1];assert(!TIOSyslogParseNotice(longer)); // wrong length
    NSMutableData *bad=[Notice13(1,@"x") mutableCopy];((uint8_t *)bad.mutableBytes)[0]=0x15;assert(!TIOSyslogParseNotice(bad));
    NSMutableData *junk=[Notice13(1,@"x") mutableCopy];((uint8_t *)junk.mutableBytes)[40]='y';assert(!TIOSyslogParseNotice(junk)); // bytes after the NUL
    assert(!TIOSyslogParseNotice(Notice13(1,@""))); // empty name
    NSMutableData *ctl=[Notice13(1,@"ab") mutableCopy];((uint8_t *)ctl.mutableBytes)[6]=0x01;assert(!TIOSyslogParseNotice(ctl)); // control byte in the name
    const uint8_t old[4]={0xA1,0,0,0x13};assert(!TIOSyslogParseNotice([NSData dataWithBytes:old length:4]));
    assert(!TIOSyslogParseNotice(nil));
    assert(!TIOSyslogParseNotice(r[@"payload"])); // our own request is not a notice
    // reassembly from raw 0x11 frames, out of order and duplicated
    NSData *blob=[NSData dataWithBytes:kLZ4 length:sizeof kLZ4];
    TIOSyslogAssembler *a=[TIOSyslogAssembler new];[a expectSize:blob.length name:name];assert(!a.complete);
    assert([a feedTransferMessage:Sync(@"u1",name,blob.length)]);assert([a.advertisedMD5 isEqual:@"2234567890abcdef"]&&a.expectedSize==blob.length);
    NSData *c1=[blob subdataWithRange:NSMakeRange(0,100)],*c2=[blob subdataWithRange:NSMakeRange(100,blob.length-100)];
    assert(![a feedTransferMessage:Chunk(@"u1",100,c2)]||a.data.length==0); // gap: not placed
    assert(a.data.length==0);
    assert([a feedTransferMessage:Chunk(@"u1",0,c1)]);assert([a feedTransferMessage:Chunk(@"u1",0,c1)]); // duplicate is idempotent
    assert(a.data.length==100&&!a.complete);
    assert([a feedTransferMessage:Chunk(@"u1",100,c2)]);assert(a.complete&&[a.data isEqual:blob]);
    assert(![a feedTransferMessage:Chunk(@"other",0,c1)]||[a.data isEqual:blob]); // foreign task never overwrites
    const uint8_t ackb[2]={0x12,0x00},trunc[2]={0x22,0x7f};
    assert(![a feedTransferMessage:[NSData dataWithBytes:ackb length:2]]); // an ack is not data
    assert(![a feedTransferMessage:[NSData dataWithBytes:trunc length:2]]); // truncated
    // passive append of decoded progress chunks
    TIOSyslogAssembler *p=[TIOSyslogAssembler new];[p expectSize:blob.length name:name];
    assert([p appendChunk:c1]&&[p appendChunk:c2]&&p.complete&&[p.data isEqual:blob]);
    // lz4
    NSData *text=TIOLZ4DecodeFrame(blob,1<<20);assert([text isEqual:Str(kText)]);
    assert(!TIOLZ4DecodeFrame(blob,50)); // output cap
    assert(!TIOLZ4DecodeFrame([blob subdataWithRange:NSMakeRange(0,80)],1<<20)); // truncated
    assert(!TIOLZ4DecodeFrame(Str(@"not an lz4 frame"),1<<20));
    NSMutableData *flip=[blob mutableCopy];((uint8_t *)flip.mutableBytes)[4]=0x24;assert(!TIOLZ4DecodeFrame(flip,1<<20)); // bad version
    // literal-only block and an overlapping match (offset 1, run of 'a')
    const uint8_t lit[]={0x30,'a','b','c'};NSMutableData *o=[NSMutableData new];assert(TIOLZ4DecodeBlock(lit,4,o,100)&&[o isEqual:Str(@"abc")]);
    const uint8_t run[]={0x14,'a',0x01,0x00,0x10,'z'}; // 1 literal, match 8 at offset 1, then 1 literal
    o=[NSMutableData new];assert(TIOLZ4DecodeBlock(run,6,o,100)&&[o isEqual:Str(@"aaaaaaaaaz")]);
    const uint8_t zero[]={0x14,'a',0x00,0x00};o=[NSMutableData new];assert(!TIOLZ4DecodeBlock(zero,4,o,100)); // offset 0
    const uint8_t far[]={0x14,'a',0x05,0x00};o=[NSMutableData new];assert(!TIOLZ4DecodeBlock(far,4,o,100)); // before start
    // probe lines
    NSArray *lines=TIOSyslogProbeLines(text);
    assert(lines.count==3);assert([lines[0] containsString:@"sensor type: ST IMU(1)"]&&[lines[1] containsString:@"[KNOB]"]&&[lines[2] containsString:@"initHallStatus"]);
    NSString *all=@"icm45608 x\nLSM6DSO32 y\nLSM6DSV16X z\nmmc5603 a\nW1160 b\nW1161 c\nhall init d\nplain\n";
    assert(TIOSyslogProbeLines(Str(all)).count==7);
    assert(TIOSyslogProbeLines(Str(@"nothing here\n")).count==0&&TIOSyslogProbeLines(nil).count==0);
    NSMutableString *many=[NSMutableString new];for(int i=0;i<500;i++)[many appendString:@"OTS line\n"];assert(TIOSyslogProbeLines(Str(many)).count==200);
    puts("syslog-pull: PASS");return 0;}}
