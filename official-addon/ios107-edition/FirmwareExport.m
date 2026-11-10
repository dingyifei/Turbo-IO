#import "FirmwareExport.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>

const NSUInteger TIOFirmwareExportMaxDepth=4;
const NSUInteger TIOFirmwareExportMaxEntries=500;
static const size_t Chunk=1<<20;
static NSString *const ErrorDomain=@"TIOFirmwareExport";

NSArray<NSString *> *TIOFirmwareExportRootPaths(void){
    return @[@"Library/Application Support/ota",@"Documents/ota",@"Library/Caches/ota",@"tmp/ota"];
}
// The folders the roots live in. A direct child whose name looks like an OTA or
// firmware folder is searched too, because the 1.0.11 download location is not
// established; loose fota_* / *strix* files directly in a base are listed.
static NSArray<NSString *> *Bases(void){return @[@"Library/Application Support",@"Documents",@"Library/Caches",@"tmp"];}
NSURL *TIOFirmwareExportOwnDirectory(NSURL *home){
    return [home URLByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/FirmwareExport" isDirectory:YES];
}
static NSError *Failure(NSString *key){return [NSError errorWithDomain:ErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:TIOText(key)}];}
static NSString *Real(NSString *path){
    char buffer[PATH_MAX];if(!path.length||!realpath(path.fileSystemRepresentation,buffer))return nil;
    return [NSFileManager.defaultManager stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
}
static BOOL Inside(NSString *real,NSString *base){return real&&base&&([real isEqual:base]||[real hasPrefix:[base stringByAppendingString:@"/"]]);}
static BOOL Lstat(NSString *path,struct stat *st){return lstat(path.fileSystemRepresentation,st)==0;}
static NSArray<NSString *> *Children(NSString *dir){
    return [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]?:@[];
}
static NSDate *Modified(const struct stat *st){return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st->st_mtimespec.tv_sec+st->st_mtimespec.tv_nsec/1e9];}
static BOOL LooksLikeFirmwareFolder(NSString *name){
    NSString *n=name.lowercaseString;
    if([n isEqual:@"turboioprivateaddon"])return NO;
    return [n isEqual:@"ota"]||[n hasPrefix:@"ota_"]||[n hasPrefix:@"ota-"]||[n hasPrefix:@"fota"]||[n containsString:@"firmware"]||[n containsString:@"upgrade"];
}
static BOOL LooksLikeFirmwareFile(NSString *name){NSString *n=name.lowercaseString;return [n hasPrefix:@"fota"]||[n containsString:@"strix"];}

NSString *TIOFirmwareExportVersion(NSString *name){
    static NSRegularExpression *pattern;static dispatch_once_t once;
    dispatch_once(&once,^{pattern=[NSRegularExpression regularExpressionWithPattern:@"strix[ _-]?os[ _-]?v?([0-9]+(?:\\.[0-9]+)+)" options:NSRegularExpressionCaseInsensitive error:NULL];});
    if(![name isKindOfClass:NSString.class])return nil;
    NSTextCheckingResult *m=[pattern firstMatchInString:name options:0 range:NSMakeRange(0,name.length)];
    return m?[name substringWithRange:[m rangeAtIndex:1]]:nil;
}
NSString *TIOFirmwareExportTurboCandidate(NSString *sha256){
    static NSDictionary<NSString *,NSString *> *known;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableDictionary *d=[@{
            @"6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473":@"TMG2",
            @"45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274":@"TMG3",
            @"47f3f639400173acf57916c5e24c35b307ab2146a2030a2a2b6980b31ce4ab03":@"TMG4",
            @"aa387b37ece2092d50721bcc3409984f7bd0d650aad4b7b249aceba515161126":@"TMG4",
            @"9f1e327c42c859d37e035bcfe83554c137e9fed05dfbaa8c5ed938bb65d19ebb":@"TMG5",
            @"6705bf4d164178943018d55ac882cf796bbc255f186d0be509ecb2f798ede0ef":@"TMG5",
            @"06927af943f06463b5bff1c10df0bcbd326c110280ef4f9ec22ac7b2b44a48d4":@"TMG6",
            @"a134c0f9d8550cdd5b53559e4857e27ca92ec8b168543d2c357cbc1e3fbe4d6e":@"TMG6",
            @"0d77be022276a573591915a7baa0048117c049eb048ce326be4f0beaa1b3ece7":@"TMG7",
            @"ecb5fd7dcb7340c76b00ee609fe84f2a66fc66eaa565b1cda1900a086f0d6e0d":@"TMG7",
            @"6b06d0dd3124ac1f86c91e0879908f9bfe129a2051cf0b619d5b0b664bc3c0aa":@"TMG7",
            @"76cac17dfbddbee5683c5a4e4f40b81d98f4d2706f21a460277093cf416f24e5":@"TMG8",
            @"effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6":@"TMG8",
            @"2ae00724ff47aabe1c19e192316a8cf497f9838698129a3c40b493deebf6231e":@"TMG9",
            @"2b90c0d081365acaf18a5e79ee629d3e2495dc43fa1a4b27b54c795168c4126f":@"TMG9",
            @"a4ca066249c277c06bebf327970b4c1c31935a3f84aeab371bf11c99b9d5a36b":@"TMG9",
            @"a6e5d4e7f1e9c3dbcc5efab292a6010b50301d9472e5af0e36b4e7a4089c8c91":@"TMG9",
            @"def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd":@"TMG9",
            @"97657db0d8835b9c43f692cd095e5ca44743d35c7e9ad8473bf29dafdb8ccdd2":@"TMG10",
            @"4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c":@"TMG10",
        } mutableCopy];
        d[TIO_FW_ZIP_SHA256.lowercaseString]=TIO_FW_NAME;known=d;
    });
    return [sha256 isKindOfClass:NSString.class]?known[sha256.lowercaseString]:nil;
}

typedef struct{NSUInteger count,links;BOOL truncated,depthLimited;} WalkState;
static NSDictionary *WithVersion(NSDictionary *entry){
    NSString *version=TIOFirmwareExportVersion(entry[@"name"]);if(!version)return entry;
    NSMutableDictionary *m=[entry mutableCopy];m[@"version"]=version;return m;
}
// Top-level items newest first; a folder keeps its contents right after it.
static NSArray *NewestFirst(NSArray<NSDictionary *> *entries){
    NSMutableArray<NSMutableArray *> *groups=[NSMutableArray new];
    for(NSDictionary *e in entries){if([e[@"depth"] integerValue]<=1||!groups.count)[groups addObject:[NSMutableArray new]];[groups.lastObject addObject:e];}
    NSMutableArray *keyed=[NSMutableArray new];
    for(NSUInteger i=0;i<groups.count;i++){NSDate *newest=NSDate.distantPast;for(NSDictionary *e in groups[i])if([e[@"modified"] compare:newest]==NSOrderedDescending)newest=e[@"modified"];[keyed addObject:@{@"newest":newest,@"index":@(i)}];}
    [keyed sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult r=[b[@"newest"] compare:a[@"newest"]];return r!=NSOrderedSame?r:[a[@"index"] compare:b[@"index"]];}];
    NSMutableArray *out=[NSMutableArray arrayWithCapacity:entries.count];for(NSDictionary *k in keyed)[out addObjectsFromArray:groups[[k[@"index"] unsignedIntegerValue]]];
    return out;
}
// Depth-first, sorted, links never followed. Adds folder entries before their
// contents and fills each folder's file count and byte total afterwards.
static void Walk(NSString *dir,NSString *relative,NSString *root,NSUInteger depth,NSString *own,NSMutableArray *entries,WalkState *state,uint64_t *bytes,NSUInteger *files){
    for(NSString *name in Children(dir)){
        if(state->count>=TIOFirmwareExportMaxEntries){state->truncated=YES;return;}
        NSString *path=[dir stringByAppendingPathComponent:name],*rel=[relative stringByAppendingPathComponent:name];struct stat st;
        if(!Lstat(path,&st))continue;
        if(S_ISLNK(st.st_mode)){state->links++;continue;}
        if(S_ISREG(st.st_mode)){
            state->count++;*bytes+=(uint64_t)st.st_size;(*files)++;
            [entries addObject:WithVersion(@{@"url":[NSURL fileURLWithPath:path isDirectory:NO],@"relative":rel,@"name":name,@"root":root,@"kind":@"file",@"depth":@(depth),@"bytes":@((uint64_t)st.st_size),@"modified":Modified(&st)})];
        }else if(S_ISDIR(st.st_mode)){
            if(own&&Inside(Real(path),own))continue;
            state->count++;NSUInteger index=entries.count;uint64_t subBytes=0;NSUInteger subFiles=0;
            [entries addObject:@{}];
            if(depth<TIOFirmwareExportMaxDepth)Walk(path,rel,root,depth+1,own,entries,state,&subBytes,&subFiles);
            else if(Children(path).count)state->depthLimited=YES;
            entries[index]=WithVersion(@{@"url":[NSURL fileURLWithPath:path isDirectory:YES],@"relative":rel,@"name":name,@"root":root,@"kind":@"folder",@"depth":@(depth),@"bytes":@(subBytes),@"files":@(subFiles),@"modified":Modified(&st),@"extracted":@([name.lowercaseString hasPrefix:@"extracted"])});
            *bytes+=subBytes;*files+=subFiles;
        }
    }
}

NSDictionary *TIOFirmwareExportScan(NSURL *home){
    NSMutableArray *entries=[NSMutableArray new],*roots=[NSMutableArray new];WalkState state={0};
    NSString *homeReal=Real(home.path);
    if(!homeReal)return @{@"entries":@[],@"roots":@[],@"skippedLinks":@0,@"truncated":@NO,@"depthLimited":@NO};
    NSString *own=Real(TIOFirmwareExportOwnDirectory(home).path);
    NSMutableArray<NSString *> *candidates=[TIOFirmwareExportRootPaths() mutableCopy];
    NSMutableArray<NSString *> *loose=[NSMutableArray new];
    for(NSString *base in Bases()){
        NSString *basePath=[home.path stringByAppendingPathComponent:base];struct stat st;
        if(!Lstat(basePath,&st)||!S_ISDIR(st.st_mode)||!Inside(Real(basePath),homeReal))continue;
        for(NSString *name in Children(basePath)){
            NSString *path=[basePath stringByAppendingPathComponent:name],*rel=[base stringByAppendingPathComponent:name];
            if(!Lstat(path,&st))continue;
            if(S_ISDIR(st.st_mode)&&LooksLikeFirmwareFolder(name)&&![candidates containsObject:rel])[candidates addObject:rel];
            else if(S_ISREG(st.st_mode)&&LooksLikeFirmwareFile(name))[loose addObject:rel];
        }
    }
    NSMutableSet *seen=[NSMutableSet new];
    for(NSString *root in candidates){
        NSString *path=[home.path stringByAppendingPathComponent:root];struct stat st;
        if(!Lstat(path,&st))continue;
        if(S_ISLNK(st.st_mode)){state.links++;continue;}
        if(!S_ISDIR(st.st_mode))continue;
        NSString *real=Real(path);
        if(!Inside(real,homeReal)||[seen containsObject:real]||(own&&Inside(real,own)))continue;
        [seen addObject:real];[roots addObject:root];
        uint64_t bytes=0;NSUInteger files=0;
        Walk(path,root,root,1,own,entries,&state,&bytes,&files);
        if(state.truncated)break;
    }
    for(NSString *rel in loose){
        if(state.count>=TIOFirmwareExportMaxEntries){state.truncated=YES;break;}
        NSString *path=[home.path stringByAppendingPathComponent:rel];struct stat st;
        if(!Lstat(path,&st)||!S_ISREG(st.st_mode))continue;
        state.count++;
        [entries addObject:WithVersion(@{@"url":[NSURL fileURLWithPath:path isDirectory:NO],@"relative":rel,@"name":rel.lastPathComponent,@"root":rel.stringByDeletingLastPathComponent,@"kind":@"file",@"depth":@1,@"bytes":@((uint64_t)st.st_size),@"modified":Modified(&st)})];
    }
    return @{@"entries":NewestFirst(entries),@"roots":roots,@"skippedLinks":@(state.links),@"truncated":@(state.truncated),@"depthLimited":@(state.depthLimited)};
}

static NSString *Hex(const unsigned char *bytes,size_t length){
    NSMutableString *s=[NSMutableString stringWithCapacity:length*2];for(size_t i=0;i<length;i++)[s appendFormat:@"%02x",bytes[i]];return s;
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
// MD5 is only for comparing with the server's apkMd5; SHA-256 is the record.
typedef struct{CC_SHA256_CTX sha;CC_MD5_CTX md5;uLong crc;uint64_t bytes;} Digest;
static void DigestInit(Digest *d){CC_SHA256_Init(&d->sha);CC_MD5_Init(&d->md5);d->crc=crc32(0L,Z_NULL,0);d->bytes=0;}
static void DigestUpdate(Digest *d,const void *p,size_t n){CC_SHA256_Update(&d->sha,p,(CC_LONG)n);CC_MD5_Update(&d->md5,p,(CC_LONG)n);d->crc=crc32(d->crc,p,(uInt)n);d->bytes+=n;}
static NSDictionary *DigestFinal(Digest *d){
    unsigned char sha[CC_SHA256_DIGEST_LENGTH],md5[CC_MD5_DIGEST_LENGTH];CC_SHA256_Final(sha,&d->sha);CC_MD5_Final(md5,&d->md5);
    return @{@"sha256":Hex(sha,sizeof sha),@"md5":Hex(md5,sizeof md5),@"bytes":@(d->bytes),@"crc":@((uint32_t)d->crc)};
}
#pragma clang diagnostic pop
static int OpenRegular(NSString *path,struct stat *st){
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return -1;
    if(fstat(fd,st)!=0||!S_ISREG(st->st_mode)){close(fd);return -1;}return fd;
}
// Reads the whole file; optional sink receives every chunk. Fails if the size changes.
static NSDictionary *DigestFile(NSString *path,BOOL(^sink)(const void *,size_t)){
    struct stat st;int fd=OpenRegular(path,&st);if(fd<0)return nil;
    void *buffer=malloc(Chunk);if(!buffer){close(fd);return nil;}
    Digest d;DigestInit(&d);BOOL ok=YES;ssize_t n;
    while((n=read(fd,buffer,Chunk))!=0){
        if(n<0){ok=NO;break;}
        DigestUpdate(&d,buffer,(size_t)n);if(sink&&!sink(buffer,(size_t)n)){ok=NO;break;}
    }
    free(buffer);struct stat after;ok=ok&&fstat(fd,&after)==0&&after.st_size==st.st_size&&d.bytes==(uint64_t)st.st_size;close(fd);
    return ok?DigestFinal(&d):nil;
}
NSDictionary *TIOFirmwareExportHash(NSURL *file,NSError **error){
    NSDictionary *d=file.isFileURL?DigestFile(file.path,nil):nil;
    if(!d){if(error)*error=Failure(@"fwexport.error.read");return nil;}
    return @{@"sha256":d[@"sha256"],@"md5":d[@"md5"],@"bytes":d[@"bytes"]};
}

#pragma mark Re-zip: a stored ZIP written only to the addon folder
static void Put16(NSMutableData *d,uint16_t v){uint8_t b[2]={v&255,v>>8};[d appendBytes:b length:2];}
static void Put32(NSMutableData *d,uint32_t v){uint8_t b[4]={v&255,(v>>8)&255,(v>>16)&255,v>>24};[d appendBytes:b length:4];}
static void DosTime(NSDate *date,uint16_t *dosTime,uint16_t *dosDate){
    time_t t=(time_t)date.timeIntervalSince1970;struct tm tm;localtime_r(&t,&tm);
    if(tm.tm_year<80){*dosTime=0;*dosDate=(1<<5)|1;return;}
    *dosTime=(uint16_t)((tm.tm_hour<<11)|(tm.tm_min<<5)|(tm.tm_sec/2));*dosDate=(uint16_t)(((tm.tm_year-80)<<9)|((tm.tm_mon+1)<<5)|tm.tm_mday);
}
static void Header(NSMutableData *d,BOOL central,NSData *name,uint32_t crc,uint32_t size,uint16_t time,uint16_t date,uint32_t offset){
    Put32(d,central?0x02014b50:0x04034b50);if(central)Put16(d,20);Put16(d,20);Put16(d,0x0800);Put16(d,0);Put16(d,time);Put16(d,date);
    Put32(d,crc);Put32(d,size);Put32(d,size);Put16(d,(uint16_t)name.length);Put16(d,0);
    if(central){Put16(d,0);Put16(d,0);Put16(d,0);Put32(d,0);Put32(d,offset);}
    [d appendData:name];
}
static BOOL WriteAll(int fd,const void *p,size_t n){const uint8_t *b=p;while(n){ssize_t w=write(fd,b,n);if(w<=0)return NO;b+=w;n-=(size_t)w;}return YES;}

NSDictionary *TIOFirmwareExportRezip(NSURL *folder,NSURL *home,NSError **error){
    NSString *homeReal=Real(home.path),*path=folder.path;struct stat st;
    NSURL *ownURL=TIOFirmwareExportOwnDirectory(home);
    if(!folder.isFileURL||!homeReal||!Lstat(path,&st)||!S_ISDIR(st.st_mode)||!Inside(Real(path),homeReal)||[Real(path) isEqual:homeReal]){if(error)*error=Failure(@"fwexport.error.source");return nil;}
    NSString *ownReal=Real(ownURL.path);
    if(ownReal&&Inside(Real(path),ownReal)){if(error)*error=Failure(@"fwexport.error.source");return nil;}
    NSMutableArray *entries=[NSMutableArray new];WalkState state={0};uint64_t total=0;NSUInteger fileCount=0;
    Walk(path,@"",path,1,ownReal,entries,&state,&total,&fileCount);
    if(state.truncated||state.depthLimited){if(error)*error=Failure(@"fwexport.error.limit");return nil;}
    NSMutableArray *files=[NSMutableArray new];for(NSDictionary *e in entries)if([e[@"kind"] isEqual:@"file"])[files addObject:e];
    if(!files.count){if(error)*error=Failure(@"fwexport.error.source");return nil;}
    if(total+(uint64_t)files.count*1024>UINT32_MAX-65536){if(error)*error=Failure(@"fwexport.error.size");return nil;}
    if(![NSFileManager.defaultManager createDirectoryAtURL:ownURL withIntermediateDirectories:YES attributes:nil error:nil]){if(error)*error=Failure(@"fwexport.error.write");return nil;}
    ownReal=Real(ownURL.path);
    if(!Inside(ownReal,homeReal)){if(error)*error=Failure(@"fwexport.error.write");return nil;}
    for(NSString *name in Children(ownReal))if([name hasSuffix:@".partial"])unlink([ownReal stringByAppendingPathComponent:name].fileSystemRepresentation);
    NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.dateFormat=@"yyyyMMdd-HHmmss";
    NSString *base=[NSString stringWithFormat:@"%@-rezipped-%@",path.lastPathComponent,[f stringFromDate:NSDate.date]];
    NSString *finalPath=[ownReal stringByAppendingPathComponent:[base stringByAppendingString:@".zip"]];
    for(NSUInteger i=2;[NSFileManager.defaultManager fileExistsAtPath:finalPath];i++)finalPath=[ownReal stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%lu.zip",base,(unsigned long)i]];
    NSString *partial=[finalPath stringByAppendingString:@".partial"];
    int out=open(partial.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(out<0){if(error)*error=Failure(@"fwexport.error.write");return nil;}
    NSMutableData *central=[NSMutableData new];uint64_t offset=0;BOOL ok=YES;NSString *top=path.lastPathComponent;NSError *failure=nil;
    for(NSDictionary *e in files){
        NSString *source=[e[@"url"] path];
        // First pass: CRC and size for the local header. Second pass copies and must agree.
        NSDictionary *first=DigestFile(source,nil);
        if(!first){failure=Failure(@"fwexport.error.read");ok=NO;break;}
        NSData *name=[[top stringByAppendingPathComponent:e[@"relative"]] dataUsingEncoding:NSUTF8StringEncoding];
        uint16_t t,d;DosTime(e[@"modified"],&t,&d);NSMutableData *local=[NSMutableData new];
        Header(local,NO,name,[first[@"crc"] unsignedIntValue],(uint32_t)[first[@"bytes"] unsignedLongLongValue],t,d,0);
        if(!WriteAll(out,local.bytes,local.length)){failure=Failure(@"fwexport.error.write");ok=NO;break;}
        NSDictionary *second=DigestFile(source,^BOOL(const void *p,size_t n){return WriteAll(out,p,n);});
        if(!second||![second isEqual:first]){failure=Failure(@"fwexport.error.changed");ok=NO;break;}
        Header(central,YES,name,[first[@"crc"] unsignedIntValue],(uint32_t)[first[@"bytes"] unsignedLongLongValue],t,d,(uint32_t)offset);
        offset+=local.length+[first[@"bytes"] unsignedLongLongValue];
        if(offset>UINT32_MAX-65536){failure=Failure(@"fwexport.error.size");ok=NO;break;}
    }
    if(ok){
        NSMutableData *end=[NSMutableData new];Put32(end,0x06054b50);Put16(end,0);Put16(end,0);Put16(end,(uint16_t)files.count);Put16(end,(uint16_t)files.count);
        Put32(end,(uint32_t)central.length);Put32(end,(uint32_t)offset);Put16(end,0);
        ok=WriteAll(out,central.bytes,central.length)&&WriteAll(out,end.bytes,end.length)&&fsync(out)==0;
        if(!ok)failure=Failure(@"fwexport.error.write");
    }
    close(out);
    if(ok&&rename(partial.fileSystemRepresentation,finalPath.fileSystemRepresentation)!=0){ok=NO;failure=Failure(@"fwexport.error.write");}
    if(!ok){unlink(partial.fileSystemRepresentation);if(error)*error=failure;return nil;}
    NSURL *zip=[NSURL fileURLWithPath:finalPath isDirectory:NO];NSDictionary *hash=TIOFirmwareExportHash(zip,error);
    if(!hash){unlink(finalPath.fileSystemRepresentation);return nil;}
    return @{@"url":zip,@"bytes":hash[@"bytes"],@"files":@(files.count),@"sha256":hash[@"sha256"],@"md5":hash[@"md5"],@"label":@"rezipped"};
}

NSArray<NSDictionary *> *TIOFirmwareExportOwnCopies(NSURL *home){
    NSString *own=TIOFirmwareExportOwnDirectory(home).path;struct stat st;NSMutableArray *rows=[NSMutableArray new];
    if(!Lstat(own,&st)||!S_ISDIR(st.st_mode))return rows;
    for(NSString *name in Children(own)){
        NSString *path=[own stringByAppendingPathComponent:name];
        if(![name hasSuffix:@".zip"]||!Lstat(path,&st)||!S_ISREG(st.st_mode))continue;
        [rows addObject:@{@"url":[NSURL fileURLWithPath:path isDirectory:NO],@"name":name,@"bytes":@((uint64_t)st.st_size),@"modified":Modified(&st)}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"modified"] compare:a[@"modified"]];}];
    return rows;
}
BOOL TIOFirmwareExportDeleteOwnCopy(NSURL *file,NSURL *home){
    NSString *own=Real(TIOFirmwareExportOwnDirectory(home).path),*path=file.path;struct stat st;
    if(!own||!file.isFileURL||![path hasSuffix:@".zip"]||!Lstat(path,&st)||!S_ISREG(st.st_mode))return NO;
    if(![Real(path.stringByDeletingLastPathComponent) isEqual:own])return NO;
    return unlink(path.fileSystemRepresentation)==0;
}
