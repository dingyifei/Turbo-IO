// FirmwareExport against a temporary container: nested ota folders, a .bin, a ZIP,
// an extracted_* folder, links pointing outside (never followed), depth and entry
// limits, hashes checked against /usr/bin/shasum and /sbin/md5, re-zip written only
// into the addon's own folder, and every source file byte-for-byte unchanged.
// No device, network or signing.
#import "FirmwareExport.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *Home,*Outside;
static NSString *P(NSString *rel){return [Home stringByAppendingPathComponent:rel];}
static void Dir(NSString *path){assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);}
static NSData *Bytes(NSUInteger n,uint8_t seed){NSMutableData *d=[NSMutableData dataWithLength:n];uint8_t *b=d.mutableBytes;uint32_t x=seed*2654435761u+1;for(NSUInteger i=0;i<n;i++){x=x*1103515245u+12345u;b[i]=(uint8_t)(x>>16);}return d;}
static void File(NSString *path,NSData *data){Dir(path.stringByDeletingLastPathComponent);assert([data writeToFile:path atomically:NO]);}
static NSString *Tool(NSString *tool,NSArray *args){
    NSTask *t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:tool];t.arguments=args;NSPipe *pipe=[NSPipe pipe];t.standardOutput=pipe;
    NSError *e=nil;assert([t launchAndReturnError:&e]);NSData *out=[pipe.fileHandleForReading readDataToEndOfFile];[t waitUntilExit];assert(t.terminationStatus==0);
    return [[NSString alloc]initWithData:out encoding:NSUTF8StringEncoding];
}
static NSString *Shasum(NSString *path){return [[Tool(@"/usr/bin/shasum",@[@"-a",@"256",path]) componentsSeparatedByString:@" "].firstObject lowercaseString];}
static NSString *Md5(NSString *path){return [Tool(@"/sbin/md5",@[@"-q",path]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
// Path -> size, mtime and SHA-256 for every file under root, links recorded as their target.
static NSDictionary *Snapshot(NSString *root){
    NSMutableDictionary *s=[NSMutableDictionary new];NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtPath:root];
    for(NSString *rel in e){NSString *path=[root stringByAppendingPathComponent:rel];struct stat st;assert(lstat(path.fileSystemRepresentation,&st)==0);
        if(S_ISLNK(st.st_mode))s[rel]=[@"link:" stringByAppendingString:[NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:path error:nil]];
        else if(S_ISREG(st.st_mode))s[rel]=[NSString stringWithFormat:@"%lld/%ld.%ld/%@",(long long)st.st_size,(long)st.st_mtimespec.tv_sec,(long)st.st_mtimespec.tv_nsec,Shasum(path)];
        else s[rel]=@"dir";}
    return s;
}
static NSDictionary *Entry(NSArray *entries,NSString *rel){for(NSDictionary *e in entries)if([e[@"relative"] isEqual:rel])return e;return nil;}

static void Touch(NSString *path,NSDate *date){assert([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:date} ofItemAtPath:path error:nil]);}
static NSUInteger IndexOf(NSArray *entries,NSString *rel){for(NSUInteger i=0;i<entries.count;i++)if([entries[i][@"relative"] isEqual:rel])return i;return NSNotFound;}

// argv[1], optional: the pinned candidate ZIP (test.py passes --firmware).
int main(int argc,const char **argv){@autoreleasepool{
    TIOSetUILanguageOverride(@"en");
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"fwexport-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    Home=[base stringByAppendingPathComponent:@"container"];Outside=[base stringByAppendingPathComponent:@"outside"];
    NSURL *home=[NSURL fileURLWithPath:Home isDirectory:YES];
    // Fixtures shaped like the two known layouts: 1.0.7 (extracted Strix_OS_* folder)
    // and Android 1.0.10 (fota_<ts>.bin plus extracted_* subfolders).
    File(P(@"Library/Application Support/ota/fota_1762400000.bin"),Bytes(3*1024*1024+17,1));
    File(P(@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip"),Bytes(70000,2));
    File(P(@"Library/Application Support/ota/extracted_1762400000/nuttx_ap.bin"),Bytes(40000,3));
    File(P(@"Library/Application Support/ota/extracted_1762400000/manifest.json"),[@"{\"OtaVersion\":\"Strix OS 1.0.5.6\"}" dataUsingEncoding:NSUTF8StringEncoding]);
    File(P(@"Library/Application Support/ota/extracted_1762400000/res/font.bin"),Bytes(1234,4));
    File(P(@"Library/Application Support/ota/extracted_1762400000/res/empty.bin"),[NSData data]);
    File(P(@"Documents/ota/nested/deeper/pkg.zip"),Bytes(999,5));
    File(P(@"Library/Caches/ota/cache.bin"),Bytes(10,6));
    File(P(@"Documents/fota_loose.bin"),Bytes(77,7));
    File(P(@"Documents/notes.txt"),Bytes(5,8));                       // not firmware-looking: ignored
    File(P(@"Library/Application Support/Upgrade/u.bin"),Bytes(33,9)); // discovered root by name
    File(P(@"Library/Application Support/TurboIOPrivateAddon/archive.txt"),Bytes(3,10));
    // Depth: entries deeper than 4 levels below a root are not listed.
    File(P(@"Documents/ota/a/b/c/d/e/too-deep.bin"),Bytes(9,11));
    // Links pointing outside the container: a linked folder, a linked file and a linked root.
    File([Outside stringByAppendingPathComponent:@"secret/secret.bin"],Bytes(100,12));
    assert(symlink([Outside stringByAppendingPathComponent:@"secret"].fileSystemRepresentation,P(@"Library/Application Support/ota/escape").fileSystemRepresentation)==0);
    assert(symlink([Outside stringByAppendingPathComponent:@"secret/secret.bin"].fileSystemRepresentation,P(@"Library/Application Support/ota/linked.bin").fileSystemRepresentation)==0);
    Dir(P(@"tmp"));assert(symlink([Outside stringByAppendingPathComponent:@"secret"].fileSystemRepresentation,P(@"tmp/ota").fileSystemRepresentation)==0);
    // A 1.0.7 leftover: the Turbo candidate the old feed served, kept by the install over C13,
    // older than everything else. With the real pinned ZIP it must be labelled a candidate.
    NSString *leftZip=P(@"Library/Application Support/ota/Strix_OS_1.0.5.5.zip"),*leftDir=P(@"Library/Application Support/ota/Strix_OS_1.0.5.5");
    if(argc>1)assert([NSFileManager.defaultManager copyItemAtPath:[NSString stringWithUTF8String:argv[1]] toPath:leftZip error:nil]);else File(leftZip,Bytes(500,13));
    File([leftDir stringByAppendingPathComponent:@"manifest.json"],Bytes(20,14));
    NSDate *old=[NSDate dateWithTimeIntervalSince1970:1761900000],*newest=[NSDate dateWithTimeIntervalSinceNow:120];
    Touch(leftZip,old);Touch([leftDir stringByAppendingPathComponent:@"manifest.json"],old);Touch(leftDir,old);
    Touch(P(@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip"),newest);
    NSDictionary *before=Snapshot(Home),*outsideBefore=Snapshot(Outside);

    NSDictionary *scan=TIOFirmwareExportScan(home);NSArray *entries=scan[@"entries"];
    assert([scan[@"roots"] isEqual:(@[@"Library/Application Support/ota",@"Documents/ota",@"Library/Caches/ota",@"Library/Application Support/Upgrade"])]);
    assert([scan[@"skippedLinks"] integerValue]==3);assert(![scan[@"truncated"] boolValue]);assert([scan[@"depthLimited"] boolValue]);
    for(NSDictionary *e in entries){
        NSString *rel=e[@"relative"];
        assert(![rel containsString:@"secret"]&&![rel containsString:@"escape"]&&![rel containsString:@"linked"]&&![rel hasPrefix:@"tmp/"]);
        assert(![rel containsString:@"TurboIOPrivateAddon"]&&![rel containsString:@"notes.txt"]&&![rel containsString:@"too-deep"]);
        assert([e[@"depth"] integerValue]>=1&&[e[@"depth"] unsignedIntegerValue]<=TIOFirmwareExportMaxDepth);
        assert([[e[@"url"] path] hasPrefix:Home]);
    }
    NSDictionary *bin=Entry(entries,@"Library/Application Support/ota/fota_1762400000.bin");
    assert(bin&&[bin[@"kind"] isEqual:@"file"]&&[bin[@"bytes"] unsignedLongLongValue]==3*1024*1024+17&&[bin[@"depth"] integerValue]==1&&[bin[@"modified"] isKindOfClass:NSDate.class]);
    NSDictionary *extracted=Entry(entries,@"Library/Application Support/ota/extracted_1762400000");
    assert(extracted&&[extracted[@"kind"] isEqual:@"folder"]&&[extracted[@"extracted"] boolValue]&&[extracted[@"files"] integerValue]==4&&[extracted[@"bytes"] unsignedLongLongValue]==40000+1234+[NSData dataWithContentsOfFile:P(@"Library/Application Support/ota/extracted_1762400000/manifest.json")].length);
    assert(Entry(entries,@"Library/Application Support/ota/extracted_1762400000/res/font.bin"));
    assert(Entry(entries,@"Documents/ota/nested/deeper/pkg.zip"));
    assert(Entry(entries,@"Documents/ota/a/b/c/d")&&!Entry(entries,@"Documents/ota/a/b/c/d/e"));
    assert(Entry(entries,@"Documents/fota_loose.bin"));
    assert(Entry(entries,@"Library/Application Support/Upgrade/u.bin"));
    assert(Entry(entries,@"Library/Caches/ota/cache.bin"));

    // Newest first by top-level item; a folder keeps its contents right behind it.
    assert([entries[0][@"relative"] isEqual:@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip"]);
    NSUInteger leftDirAt=IndexOf(entries,@"Library/Application Support/ota/Strix_OS_1.0.5.5"),leftZipAt=IndexOf(entries,@"Library/Application Support/ota/Strix_OS_1.0.5.5.zip");
    assert(leftDirAt!=NSNotFound&&leftZipAt!=NSNotFound);
    assert(IndexOf(entries,@"Library/Application Support/ota/Strix_OS_1.0.5.5/manifest.json")==leftDirAt+1);
    assert(MIN(leftDirAt,leftZipAt)==entries.count-3&&MAX(leftDirAt,leftZipAt)>=entries.count-2);
    NSUInteger ex=IndexOf(entries,@"Library/Application Support/ota/extracted_1762400000");
    for(NSString *child in @[@"nuttx_ap.bin",@"manifest.json",@"res",@"res/font.bin",@"res/empty.bin"])assert(IndexOf(entries,[@"Library/Application Support/ota/extracted_1762400000" stringByAppendingPathComponent:child])>ex&&IndexOf(entries,[@"Library/Application Support/ota/extracted_1762400000" stringByAppendingPathComponent:child])<=ex+5);
    // Versions come from Strix_OS names only.
    assert([entries[leftDirAt][@"version"] isEqual:@"1.0.5.5"]&&[entries[leftZipAt][@"version"] isEqual:@"1.0.5.5"]&&[entries[0][@"version"] isEqual:@"1.0.5.6"]);
    assert(!Entry(entries,@"Library/Application Support/ota/fota_1762400000.bin")[@"version"]&&!entries[ex][@"version"]);
    assert([TIOFirmwareExportVersion(@"StrixOS-1.0.5.5-TurboIO-TMG9-CANDIDATE-NOT-APPROVED.zip") isEqual:@"1.0.5.5"]&&[TIOFirmwareExportVersion(@"Strix OS 1.0.6") isEqual:@"1.0.6"]&&!TIOFirmwareExportVersion(@"fota_1.bin"));
    // Turbo candidates: the compiled-in pin and every recorded ZIP hash, case-insensitive; anything else is not one.
    assert([TIOFirmwareExportTurboCandidate(TIO_FW_ZIP_SHA256) isEqual:TIO_FW_NAME]&&[TIOFirmwareExportTurboCandidate(TIO_FW_ZIP_SHA256.uppercaseString) isEqual:TIO_FW_NAME]);
    assert([TIOFirmwareExportTurboCandidate(@"def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd") isEqual:@"TMG9"]&&[TIOFirmwareExportTurboCandidate(@"6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473") isEqual:@"TMG2"]);
    assert(!TIOFirmwareExportTurboCandidate(Shasum(P(@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip")))&&!TIOFirmwareExportTurboCandidate(nil)&&!TIOFirmwareExportTurboCandidate(@""));
    {NSError *e=nil;NSDictionary *h=TIOFirmwareExportHash([NSURL fileURLWithPath:leftZip],&e);assert(h&&!e);
     if(argc>1)assert([TIOFirmwareExportTurboCandidate(h[@"sha256"]) hasPrefix:@"TMG"]);else assert(!TIOFirmwareExportTurboCandidate(h[@"sha256"]));}

    // Hashes agree with independent tools, for a multi-chunk file, a small file and an empty file.
    for(NSString *rel in @[@"Library/Application Support/ota/fota_1762400000.bin",@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip",@"Library/Application Support/ota/extracted_1762400000/res/empty.bin"]){
        NSError *e=nil;NSDictionary *h=TIOFirmwareExportHash([NSURL fileURLWithPath:P(rel)],&e);assert(h&&!e);
        assert([h[@"sha256"] isEqual:Shasum(P(rel))]);assert([h[@"md5"] isEqual:Md5(P(rel))]);
        assert([h[@"bytes"] unsignedLongLongValue]==[Entry(entries,rel)[@"bytes"] unsignedLongLongValue]);
    }
    {NSError *e=nil;assert(!TIOFirmwareExportHash([NSURL fileURLWithPath:P(@"Library/Application Support/ota/linked.bin")],&e)&&e);}
    {NSError *e=nil;assert(!TIOFirmwareExportHash([NSURL fileURLWithPath:P(@"Library/Application Support/ota")],&e)&&e);}
    {NSError *e=nil;assert(!TIOFirmwareExportHash([NSURL fileURLWithPath:P(@"missing.bin")],&e)&&e);}

    // Re-zip: refused outside the container, through a link, for the addon's own folder and over the depth limit.
    NSError *e=nil;
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:[Outside stringByAppendingPathComponent:@"secret"]],home,&e)&&e);e=nil;
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:P(@"Library/Application Support/ota/escape")],home,&e)&&e);e=nil;
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:P(@"tmp/ota")],home,&e)&&e);e=nil;
    assert(!TIOFirmwareExportRezip(home,home,&e)&&e);e=nil;
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:P(@"Documents/ota")],home,&e)&&e);e=nil;
    assert(![NSFileManager.defaultManager fileExistsAtPath:TIOFirmwareExportOwnDirectory(home).path]);
    NSDictionary *own=Snapshot(P(@"Library/Application Support/TurboIOPrivateAddon"));
    NSDictionary *zip=TIOFirmwareExportRezip([extracted[@"url"] URLByStandardizingPath],home,&e);assert(zip&&!e);
    assert([zip[@"label"] isEqual:@"rezipped"]&&[zip[@"files"] integerValue]==4);
    NSString *zipPath=[zip[@"url"] path];
    assert([zipPath.lastPathComponent hasPrefix:@"extracted_1762400000-rezipped-"]&&[zipPath hasSuffix:@".zip"]);
    assert([zipPath.stringByDeletingLastPathComponent.stringByResolvingSymlinksInPath isEqual:TIOFirmwareExportOwnDirectory(home).path.stringByResolvingSymlinksInPath]);
    assert([zip[@"sha256"] isEqual:Shasum(zipPath)]&&[zip[@"md5"] isEqual:Md5(zipPath)]);
    // The archive holds exactly the four files, byte-identical, with no link content.
    NSString *listing=Tool(@"/usr/bin/unzip",@[@"-Z1",zipPath]);
    NSArray *names=[[listing componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length>0"]];
    assert([[names sortedArrayUsingSelector:@selector(compare:)] isEqual:(@[@"extracted_1762400000/manifest.json",@"extracted_1762400000/nuttx_ap.bin",@"extracted_1762400000/res/empty.bin",@"extracted_1762400000/res/font.bin"])]);
    Tool(@"/usr/bin/unzip",@[@"-tq",zipPath]);
    NSString *unpacked=[base stringByAppendingPathComponent:@"unpacked"];Tool(@"/usr/bin/unzip",@[@"-q",zipPath,@"-d",unpacked]);
    for(NSString *n in names)assert([[NSData dataWithContentsOfFile:[unpacked stringByAppendingPathComponent:n]] isEqual:[NSData dataWithContentsOfFile:[P(@"Library/Application Support/ota") stringByAppendingPathComponent:n]]]);
    // Own copies list, a later scan skips the addon's folder, and delete refuses anything else.
    NSArray *copies=TIOFirmwareExportOwnCopies(home);assert(copies.count==1&&[[copies[0][@"url"] path].lastPathComponent isEqual:zipPath.lastPathComponent]);
    for(NSDictionary *x in TIOFirmwareExportScan(home)[@"entries"])assert(![x[@"relative"] containsString:@"rezipped"]);
    assert(!TIOFirmwareExportDeleteOwnCopy([NSURL fileURLWithPath:P(@"Library/Application Support/ota/Strix_OS_1.0.5.6.zip")],home));
    assert(!TIOFirmwareExportDeleteOwnCopy([NSURL fileURLWithPath:P(@"Documents/ota/nested/deeper/pkg.zip")],home));
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:TIOFirmwareExportOwnDirectory(home).path],home,&e)&&e);e=nil;
    // Nothing outside the addon's own FirmwareExport folder changed; RayNeo's files are untouched.
    NSMutableDictionary *after=[Snapshot(Home) mutableCopy];
    for(NSString *rel in after.allKeys)if([rel hasPrefix:@"Library/Application Support/TurboIOPrivateAddon/FirmwareExport"])[after removeObjectForKey:rel];
    NSMutableDictionary *expected=[before mutableCopy];[expected removeObjectForKey:@"Library/Application Support/TurboIOPrivateAddon/FirmwareExport"];
    assert([after isEqual:expected]);assert([Snapshot(Outside) isEqual:outsideBefore]);
    assert([Snapshot(P(@"Library/Application Support/TurboIOPrivateAddon"))[@"archive.txt"] isEqual:own[@"archive.txt"]]);
    assert(TIOFirmwareExportDeleteOwnCopy(zip[@"url"],home));assert(!TIOFirmwareExportOwnCopies(home).count);

    // Entry limit: a flood of files stops at the limit and says so.
    for(NSUInteger i=0;i<600;i++)File(P([NSString stringWithFormat:@"Library/Caches/ota/flood/%03lu.bin",(unsigned long)i]),Bytes(1,(uint8_t)i));
    NSDictionary *flood=TIOFirmwareExportScan(home);
    assert([flood[@"truncated"] boolValue]&&[flood[@"entries"] count]==TIOFirmwareExportMaxEntries);
    assert(!TIOFirmwareExportRezip([NSURL fileURLWithPath:P(@"Library/Caches/ota/flood")],home,&e)&&e);e=nil;
    // Missing container: empty result, no crash.
    NSDictionary *none=TIOFirmwareExportScan([NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"missing"]]);
    assert(![none[@"entries"] count]&&![none[@"roots"] count]);

    [NSFileManager.defaultManager removeItemAtPath:base error:nil];
    NSLog(@"PASS: firmware export: %lu entries, 3 links not followed, depth and entry limits, SHA-256/MD5 match shasum and md5, re-zip only in the addon folder, sources unchanged",(unsigned long)entries.count);
}return 0;}
