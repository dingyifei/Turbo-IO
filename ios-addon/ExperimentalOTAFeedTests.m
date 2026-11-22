#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAFlash.h"
#import "FirmwarePins.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

static NSDictionary *Fetch(uint16_t port,NSString *method,NSString *target,NSString *extra){
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    struct timeval t={5,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&t,sizeof(t));assert(connect(fd,(struct sockaddr *)&a,sizeof(a))==0);
    NSData *req=[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: 127.0.0.1:%u\r\n%@\r\n",method,target,port,extra?:@""] dataUsingEncoding:NSUTF8StringEncoding];assert(send(fd,req.bytes,req.length,0)==(ssize_t)req.length);
    NSMutableData *all=[NSMutableData new];uint8_t buf[65536];ssize_t n;while((n=recv(fd,buf,sizeof(buf),0))>0){[all appendBytes:buf length:(NSUInteger)n];assert(all.length<10000000);}assert(n==0);close(fd);
    NSData *sep=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];NSRange r=[all rangeOfData:sep options:0 range:NSMakeRange(0,all.length)];assert(r.location!=NSNotFound);
    NSString *header=[[NSString alloc]initWithData:[all subdataWithRange:NSMakeRange(0,r.location)] encoding:NSUTF8StringEncoding];NSData *body=[all subdataWithRange:NSMakeRange(NSMaxRange(r),all.length-NSMaxRange(r))];
    NSInteger status=[[[header componentsSeparatedByString:@" "] objectAtIndex:1] integerValue];return @{@"code":@(status),@"body":body,@"header":header};
}
static NSDictionary *Query(uint16_t port,NSString *path){NSDictionary *r=Fetch(port,@"GET",path,@"");assert([r[@"code"] intValue]==200);return [NSJSONSerialization JSONObjectWithData:r[@"body"] options:0 error:nil];}
// The release's feed policy, written out here by hand (not from FirmwarePins.h) so a wrong generated value fails.
// C23, the only release (TMG14 on 1.0.6.11): flashes glasses that report 1.0.5.12 (TMG11) or 1.0.6.11 (stock, TMG12, or
// TMG14 flashed again); its releases.json entry must match.
static NSArray *Accepted(void){return @[@"01.00.05.0012",@"01.00.06.0011"];}
static NSString *const WantName=@"0100060011";static const int WantCode=100060011;static NSString *const WantFile=@"Strix_OS_1.0.6.11.zip";
int main(int argc,const char **argv){@autoreleasepool{
    assert([TIO_FW_ACCEPTED_QUERY_CODES isEqual:Accepted()]);
    // A feed request never changes the selection (only TIOOTASelectPackage does): checked after the queries and downloads below.
    assert(TIOOTASelectedPackageIndex()==0);const NSUInteger startGeneration=TIOOTASelectionGeneration();
    assert(argc==3);NSURL *stockFile=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];NSURL *file=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];NSError *error=nil;
    TIOExperimentalOTAFeed *feed=[TIOExperimentalOTAFeed new];assert([feed startOnPort:0 error:&error]);uint16_t port=feed.port;assert(port);
    TIOExperimentalOTAFeed *duplicate=[TIOExperimentalOTAFeed new];assert(![duplicate startOnPort:port error:&error]);assert(!duplicate.port);
    NSString *path=[@"/g/xxxxxxxA78p2M?packageType=firmware&packageName=strix%20OS&glassesType=S3&deviceType=iOS&versionCode=" stringByAppendingString:Accepted()[0]];assert(Query(port,path)[@"data"]==NSNull.null);assert(Query(port,@"/g/xxxxxxxxxxCCXhB?sn=TEST_ONLY")[ @"data"]==NSNull.null);
    assert([Fetch(port,@"POST",path,@"")[@"code"] intValue]==405);
    assert([Fetch(port,@"GET",path,@"Host: evil.example\r\n")[@"code"] intValue]==400);
    assert([Fetch(port,@"GET",path,@"Transfer-Encoding: chunked\r\n")[@"code"] intValue]==400);
    assert([Fetch(port,@"GET",@"/../private",@"")[@"code"] intValue]==404);
    assert([Fetch(port,@"GET",path,@"Content-Length: 1\r\n")[@"code"] intValue]==400);
    assert(![feed armArchive:file lifetime:0 error:&error]);
    assert(TIOOTASelectedPackageIndex()==0&&TIOOTASelectionGeneration()==startGeneration);
#if TIO_OTA_FEED_ARMING_ENABLED
    assert(![feed armArchive:file lifetime:901 error:&error]);
    assert([feed armArchive:file lifetime:60 error:&error]);NSDictionary *metadata=Query(port,path)[@"data"];
    for(NSString *wrong in @[@"/g/xxxxxxxA78p2M",@"/g/xxxxxxxA78p2M?packageType=app",[path stringByAppendingString:@"&packageType=firmware"],[path stringByReplacingOccurrencesOfString:@"S3" withString:@"OTHER"],[path stringByReplacingOccurrencesOfString:Accepted()[0] withString:@"01.00.03.0015"]])assert(Query(port,wrong)[@"data"]==NSNull.null);
    // Every accepted current version gets the offer; every other known version gets nothing.
    for(NSString *code in @[@"01.00.03.0015",@"01.00.04.0012",@"01.00.05.0005",@"01.00.05.0012",@"01.00.05.0006",@"1.0.5.12",@"01.00.06.0011"]){
        NSString *query=[path stringByReplacingOccurrencesOfString:Accepted()[0] withString:code];
        if([Accepted() containsObject:code])assert([Query(port,query)[@"data"][@"versionCode"] intValue]==WantCode);else assert(Query(port,query)[@"data"]==NSNull.null);
    }
    assert([metadata[@"apkSize"] unsignedIntegerValue]==TIO_FW_ZIP_BYTES);assert([metadata[@"versionName"] isEqual:WantName]);assert([metadata[@"versionCode"] intValue]==WantCode);assert([[NSURL URLWithString:metadata[@"downloadUrl"]].lastPathComponent isEqual:WantFile]);
    NSData *zip=[NSData dataWithContentsOfURL:file];uint8_t digest[16];CC_MD5(zip.bytes,(CC_LONG)zip.length,digest);NSMutableString *md5=[NSMutableString new];for(unsigned i=0;i<16;i++)[md5 appendFormat:@"%02x",digest[i]];
    assert([metadata[@"apkMd5"] isEqual:md5]);assert(![metadata[@"apkMd5"] isEqual:@"bfc21e823f991962c852de22f02d62c1"]);
    NSString *download=[NSURL URLWithString:metadata[@"downloadUrl"]].path;NSDictionary *full=Fetch(port,@"GET",download,@"");assert([full[@"code"] intValue]==200);assert(TIOCheckExperimentalOTA(full[@"body"],TIOOTASelectedPackage(),nil));
    NSDictionary *head=Fetch(port,@"HEAD",download,@"");assert([head[@"body"] length]==0);assert(([head[@"header"] containsString:[NSString stringWithFormat:@"Content-Length: %u",TIO_FW_ZIP_BYTES]]));
    NSDictionary *part=Fetch(port,@"GET",download,@"Range: bytes=5-19\r\n");assert([part[@"code"] intValue]==206);assert([part[@"body"] isEqual:[full[@"body"] subdataWithRange:NSMakeRange(5,15)]]);
    part=Fetch(port,@"GET",download,[NSString stringWithFormat:@"Range: bytes=%u-\r\n",TIO_FW_ZIP_BYTES-14u]);assert([part[@"code"] intValue]==206);assert([part[@"body"] length]==14);
    for(NSString *range in @[@"bytes=-1",@"bytes=2-1",[NSString stringWithFormat:@"bytes=%u-",TIO_FW_ZIP_BYTES],@"bytes=1-2,4-5",@"bytes=99999999999999-"]){assert([Fetch(port,@"GET",download,[NSString stringWithFormat:@"Range: %@\r\n",range])[@"code"] intValue]==416);}
    // Firmware queries (accepted and refused codes), downloads, HEAD and ranges left the selection and its generation alone.
    assert(TIOOTASelectedPackageIndex()==0&&TIOOTASelectionGeneration()==startGeneration);
    [feed disarm];assert(Query(port,path)[@"data"]==NSNull.null);assert([Fetch(port,@"GET",download,@"")[@"code"] intValue]==404);
    assert([feed armArchive:file lifetime:0.01 error:&error]);usleep(20000);assert(![feed.status[@"armed"] boolValue]);assert(Query(port,path)[@"data"]==NSNull.null);
    assert([feed armArchive:file lifetime:60 error:&error]);NSString *next=[NSURL URLWithString:Query(port,path)[@"data"][@"downloadUrl"]].path;assert(![next isEqual:download]);assert([Fetch(port,@"GET",download,@"")[@"code"] intValue]==404);
    assert([Query(port,path)[@"data"][@"taskName"] isEqual:@"Turbo Menu TMG14 PRIVATE EXPERIMENT"]&&[feed.status[@"package"] isEqual:@"TMG14"]);
    // The update text names the members that differ from the bundled stock package.
    assert([Query(port,path)[@"data"][@"updateDesc"] isEqual:@"PRIVATE EXPERIMENT: AP and BTH modified, other 14 payloads unchanged. Runtime unverified."]);
    // A change of selection closes the open window at once, even when the first package is picked again.
    assert(TIOOTASelectedPackageIndex()==0);NSUInteger generation=TIOOTASelectionGeneration();
    assert(TIOOTASelectPackage(1,&error)&&TIOOTASelectedPackageIndex()==1&&TIOOTASelectionGeneration()==generation+1);
    assert(![feed.status[@"armed"] boolValue]);assert(Query(port,path)[@"data"]==NSNull.null);assert([Fetch(port,@"GET",next,@"")[@"code"] intValue]==404);
    // With the stock package selected, the TMG ZIP is refused and the stock ZIP is served under its own name, size and MD5.
    assert(![feed armArchive:file lifetime:60 error:&error]);assert(![feed.status[@"armed"] boolValue]);
    assert([feed armArchive:stockFile lifetime:60 error:&error]);NSDictionary *stockMeta=Query(port,path)[@"data"];
    NSData *stockZip=[NSData dataWithContentsOfURL:stockFile];CC_MD5(stockZip.bytes,(CC_LONG)stockZip.length,digest);NSMutableString *stockMD5=[NSMutableString new];for(unsigned i=0;i<16;i++)[stockMD5 appendFormat:@"%02x",digest[i]];
    assert([stockMeta[@"taskName"] isEqual:@"Stock 1.0.6.11"]&&[stockMeta[@"apkSize"] unsignedIntegerValue]==stockZip.length&&stockZip.length==[TIOOTAPackageAt(1)[@"zipBytes"] unsignedIntegerValue]);
    assert([stockMeta[@"apkMd5"] isEqual:stockMD5]&&![stockMD5 isEqual:md5]&&[stockMeta[@"versionCode"] intValue]==WantCode&&[[NSURL URLWithString:stockMeta[@"downloadUrl"]].lastPathComponent isEqual:WantFile]);
    NSDictionary *stockBody=Fetch(port,@"GET",[NSURL URLWithString:stockMeta[@"downloadUrl"]].path,@"");assert([stockBody[@"code"] intValue]==200&&[stockBody[@"body"] isEqual:stockZip]);
    // The stock query and download did not switch back to TMG14 or move the generation either.
    assert(TIOOTASelectedPackageIndex()==1&&TIOOTASelectionGeneration()==generation+1);
    // An arm made for an older generation is refused; picking TMG14 again closes the stock window.
    assert(![feed armArchive:stockFile package:TIOOTAPackageAt(1) generation:generation lifetime:60 error:&error]);
    assert(TIOOTASelectPackage(0,&error));assert(![feed.status[@"armed"] boolValue]);assert(Query(port,path)[@"data"]==NSNull.null);
    assert(!TIOOTASelectPackage(2,&error)&&TIOOTASelectedPackageIndex()==0);
#else
    assert(![feed armArchive:file lifetime:60 error:&error]);assert(Query(port,path)[@"data"]==NSNull.null);
#endif
    [feed stop];assert(!feed.port);assert(![feed.status[@"armed"] boolValue]);assert(![feed.status[@"running"] boolValue]);
    NSLog(@"PASS: loopback-only feed, the selected package only (window closed by a change of selection, stock served as Stock 1.0.6.11 with its own size and MD5), default no update, production gate / test-only transfer, strict HTTP, pinned bytes, expiry, revocation; no glasses IO");
}return 0;}
