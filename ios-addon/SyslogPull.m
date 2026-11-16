#import "SyslogPull.h"
static const NSUInteger kMaxFile=16u<<20,kMaxLines=200,kMaxLineLen=300;

NSDictionary *TIOSyslogRequest(void){const uint8_t b[4]={0xA1,0x00,0x00,0x12};return @{@"businessId":@16,@"payload":[NSData dataWithBytes:b length:4]};}

// Glasses -> phone on business 16, as seen on the device (C18 wire log, 2026-11-12):
//   0x13 | file size, 4 bytes big-endian | name, 50 bytes NUL-padded   (55 bytes; "file announced")
//   0x14 | name, 50 bytes NUL-padded                                  (51 bytes; "file sent")
// There is no A1 prefix on these replies; only the phone's request (A1 00 00 12) has it.
static NSString *Name50(const uint8_t *b){
    NSUInteger n=0;while(n<50&&b[n])n++;if(!n)return nil;
    for(NSUInteger i=0;i<n;i++)if(b[i]<0x21||b[i]>0x7e)return nil;
    for(NSUInteger i=n;i<50;i++)if(b[i])return nil;
    return [[NSString alloc]initWithBytes:b length:n encoding:NSASCIIStringEncoding];
}
NSDictionary *TIOSyslogParseNotice(NSData *p){
    if(![p isKindOfClass:NSData.class])return nil;const uint8_t *b=p.bytes;
    if(p.length==55&&b[0]==0x13){
        NSString *name=Name50(b+5);if(!name)return nil;
        uint32_t size=((uint32_t)b[1]<<24)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<8)|b[4];
        return @{@"sub":@0x13,@"size":@(size),@"name":name};
    }
    if(p.length==51&&b[0]==0x14){NSString *name=Name50(b+1);if(!name)return nil;return @{@"sub":@0x14,@"name":name,@"raw":[p copy]};}
    return nil;
}

// ---- protobuf (varint / length-delimited only) ----
static BOOL Varint(const uint8_t *b,NSUInteger n,NSUInteger *i,uint64_t *v){uint64_t r=0;for(int s=0;s<70&&*i<n;s+=7){uint8_t c=b[(*i)++];if(s<64)r|=(uint64_t)(c&0x7f)<<s;if(!(c&0x80)){*v=r;return YES;}}return NO;}
static BOOL Walk(const uint8_t *b,NSUInteger n,void(^cb)(uint32_t,int,uint64_t,const uint8_t *,NSUInteger)){
    NSUInteger i=0;while(i<n){uint64_t key;if(!Varint(b,n,&i,&key))return NO;uint32_t f=(uint32_t)(key>>3);int w=(int)(key&7);
        if(w==0){uint64_t v;if(!Varint(b,n,&i,&v))return NO;cb(f,0,v,NULL,0);}
        else if(w==2){uint64_t l;if(!Varint(b,n,&i,&l)||l>n-i)return NO;cb(f,2,0,b+i,(NSUInteger)l);i+=(NSUInteger)l;}
        else return NO;}
    return YES;
}

@implementation TIOSyslogAssembler{NSMutableData *_d;uint64_t _size;NSString *_name,*_md5,*_uuid;}
- (instancetype)init{if((self=[super init])){_d=[NSMutableData new];}return self;}
- (NSData *)data{return [_d copy];}
- (uint64_t)expectedSize{return _size;}
- (NSString *)fileName{return _name;}
- (NSString *)advertisedMD5{return _md5;}
- (BOOL)complete{return _size>0&&_d.length>=_size;}
- (void)expectSize:(uint64_t)size name:(NSString *)name{_size=size;_name=[name copy];}
- (BOOL)appendChunk:(NSData *)bytes{if(![bytes isKindOfClass:NSData.class])return NO;if(_d.length+bytes.length>kMaxFile)return NO;[_d appendData:bytes];return YES;}
- (BOOL)feedTransferMessage:(NSData *)payload{
    if(![payload isKindOfClass:NSData.class]||!payload.length)return NO;
    __block BOOL used=NO;const uint8_t *b=payload.bytes;
    BOOL ok=Walk(b,payload.length,^(uint32_t f,int w,uint64_t v,const uint8_t *p,NSUInteger l){
        if(w!=2)return;
        if(f==1){ // FileInfoSync
            __block NSString *uuid=nil,*name=nil,*md5=nil;__block uint64_t size=0;
            Walk(p,l,^(uint32_t g,int x,uint64_t y,const uint8_t *q,NSUInteger m){
                NSString *s=x==2?[[NSString alloc]initWithBytes:q length:m encoding:NSUTF8StringEncoding]:nil;
                if(g==1&&s)uuid=s;else if(g==2&&s)name=s;else if(g==3&&x==0)size=y;else if(g==4&&s)md5=s;});
            if(uuid){self->_uuid=uuid;self->_md5=md5;if(size)self->_size=size;if(name)self->_name=name;self->_d=[NSMutableData new];used=YES;}
        }else if(f==4){ // FileChunk
            __block NSString *uuid=nil;__block uint64_t start=0;__block NSData *data=nil;
            Walk(p,l,^(uint32_t g,int x,uint64_t y,const uint8_t *q,NSUInteger m){
                if(g==1&&x==2)uuid=[[NSString alloc]initWithBytes:q length:m encoding:NSUTF8StringEncoding];
                else if(g==3&&x==0)start=y;else if(g==5&&x==2)data=[NSData dataWithBytes:q length:m];});
            if(!data||(self->_uuid&&uuid&&![self->_uuid isEqual:uuid]))return;
            if(start>self->_d.length||start+data.length>kMaxFile)return; // a gap cannot be placed passively
            [self->_d replaceBytesInRange:NSMakeRange((NSUInteger)start,self->_d.length-(NSUInteger)start) withBytes:data.bytes length:data.length];
            used=YES;
        }});
    return ok&&used;
}
@end

// ---- lz4 ----
BOOL TIOLZ4DecodeBlock(const uint8_t *s,NSUInteger n,NSMutableData *out,NSUInteger maxOut){
    NSUInteger i=0;
    while(i<n){
        uint8_t tok=s[i++];NSUInteger lit=tok>>4;
        if(lit==15){uint8_t c;do{if(i>=n)return NO;c=s[i++];lit+=c;if(lit>maxOut)return NO;}while(c==255);}
        if(lit>n-i||out.length+lit>maxOut)return NO;
        [out appendBytes:s+i length:lit];i+=lit;
        if(i==n)return YES; // last sequence is literals only
        if(n-i<2)return NO;
        NSUInteger off=s[i]|((NSUInteger)s[i+1]<<8);i+=2;
        NSUInteger ml=tok&15;if(ml==15){uint8_t c;do{if(i>=n)return NO;c=s[i++];ml+=c;if(ml>maxOut)return NO;}while(c==255);}
        ml+=4;
        if(off==0||off>out.length||out.length+ml>maxOut)return NO;
        NSUInteger from=out.length-off;
        for(NSUInteger k=0;k<ml;k++){uint8_t c=((const uint8_t *)out.bytes)[from+k];[out appendBytes:&c length:1];}
    }
    return YES;
}
NSData *TIOLZ4DecodeFrame(NSData *f,NSUInteger maxOut){
    if(![f isKindOfClass:NSData.class]||f.length<7)return nil;const uint8_t *b=f.bytes;NSUInteger n=f.length;
    if(!(b[0]==0x04&&b[1]==0x22&&b[2]==0x4D&&b[3]==0x18))return nil;
    uint8_t flg=b[4];if((flg>>6)!=1)return nil;
    BOOL blockSum=(flg>>4)&1,hasSize=(flg>>3)&1,dict=flg&1;
    NSUInteger i=6;if(hasSize)i+=8;if(dict)i+=4;i+=1; // FLG,BD, optional size/dict id, header checksum
    if(i>n)return nil;
    NSMutableData *out=[NSMutableData new];
    for(;;){
        if(n-i<4)return nil;uint32_t w=b[i]|((uint32_t)b[i+1]<<8)|((uint32_t)b[i+2]<<16)|((uint32_t)b[i+3]<<24);i+=4;
        if(w==0)break; // end mark
        BOOL raw=w>>31;NSUInteger len=w&0x7fffffff;if(len>n-i)return nil;
        if(raw){if(out.length+len>maxOut)return nil;[out appendBytes:b+i length:len];}
        else if(!TIOLZ4DecodeBlock(b+i,len,out,maxOut))return nil;
        i+=len;if(blockSum){if(n-i<4)return nil;i+=4;}
    }
    return out;
}

NSArray<NSString *> *TIOSyslogProbeLines(NSData *text){
    if(![text isKindOfClass:NSData.class]||!text.length)return @[];
    NSString *s=[[NSString alloc]initWithData:text encoding:NSUTF8StringEncoding]?:[[NSString alloc]initWithData:text encoding:NSISOLatin1StringEncoding];
    if(!s)return @[];
    static NSArray *needles;static dispatch_once_t once;dispatch_once(&once,^{needles=@[@"sensor type:",@"LSM6DSO32",@"LSM6DSV16X",@"ST IMU",@"icm45608",@"mmc5603",@"W1160",@"W1161",@"[KNOB]",@"OTS",@"initHallStatus",@"hall init"];});
    NSMutableArray *hits=[NSMutableArray new];
    [s enumerateLinesUsingBlock:^(NSString *line,BOOL *stop){
        for(NSString *k in needles)if([line rangeOfString:k].location!=NSNotFound){
            NSString *t=[line stringByReplacingOccurrencesOfString:@"\0" withString:@""];
            if(t.length>kMaxLineLen)t=[t substringToIndex:kMaxLineLen];
            [hits addObject:t];break;}
        if(hits.count>=kMaxLines)*stop=YES;}];
    return hits;
}
