#import "AlwaysOnAudio.h"
#import "TIOLanguage.h"
#import "AlwaysOnOgg.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <limits.h>
#import <stdlib.h>
static BOOL Dir(NSURL *u){struct stat s;return !lstat(u.fileSystemRepresentation,&s)&&S_ISDIR(s.st_mode);}
static BOOL Regular(NSURL *u){struct stat s;return !lstat(u.fileSystemRepresentation,&s)&&S_ISREG(s.st_mode)&&s.st_size>0&&s.st_size<=1024LL*1024*1024;}
static BOOL Inside(NSURL *u,NSURL *root){return [[u URLByResolvingSymlinksInPath].path hasPrefix:[[root URLByResolvingSymlinksInPath].path stringByAppendingString:@"/"]];}
NSArray<NSDictionary *> *TIOAOAudioFiles(NSURL *home){
    NSURL *docs=[home URLByAppendingPathComponent:@"Documents"],*base=[docs URLByAppendingPathComponent:@"always_on_debug"],*root=[base URLByAppendingPathComponent:@"sessions"];
    NSMutableArray *rows=[NSMutableArray new];if(!Dir(docs)||!Dir(base)||!Dir(root)||!Inside(root,docs))return rows;
    NSDirectoryEnumerator *files=[NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLContentModificationDateKey,NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *u,NSError *e){(void)u;(void)e;return NO;}];NSUInteger seen=0;
    for(NSURL *f in files){if(++seen>4000)break;NSDictionary *v=[f resourceValuesForKeys:@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLContentModificationDateKey,NSURLFileSizeKey] error:nil];
        if([v[NSURLIsSymbolicLinkKey] boolValue]||!Inside(f,root)){[files skipDescendants];continue;}
        // Depth by enumerator level: listing URLs carry the real path (/private/var/...), so counting path components
        // against the home-relative root was off by one there. Files up to two folders below sessions/ are listed.
        if([v[NSURLIsDirectoryKey] boolValue]){if(files.level>2)[files skipDescendants];continue;}
        if(![@[@"opus",@"ogg",@"pcm"] containsObject:f.pathExtension.lowercaseString]||!Regular(f))continue;
        NSString *name=f.lastPathComponent;NSString *kind=[name.lowercaseString containsString:@"cached"]?TIOText(@"缓存音频"):([name.lowercaseString containsString:@"realtime"]?TIOText(@"实时音频"):TIOText(@"智记调试音频（来源待核对）"));
        [rows addObject:@{@"url":f,@"name":name,@"kind":kind,@"date":v[NSURLContentModificationDateKey]?:NSDate.distantPast,@"bytes":v[NSURLFileSizeKey]?:@0}];
    }
    // Newest first, then the 500-row display cap: the cap never hides the newest files behind enumeration order.
    [rows sortUsingComparator:^NSComparisonResult(id a,id b){return [b[@"date"] compare:a[@"date"]];}];if(rows.count>500)[rows removeObjectsInRange:NSMakeRange(500,rows.count-500)];return rows;
}
// The same scope as TIOAOAudioFiles (sessions/ up to two folders deep, no hidden or symlinked components, opus/ogg/pcm
// regular files) checked on the path itself, so membership does not depend on the listing's row or entry caps.
static BOOL Listed(NSURL *home,NSURL *source){
    NSURL *docs=[home URLByAppendingPathComponent:@"Documents"],*base=[docs URLByAppendingPathComponent:@"always_on_debug"],*root=[base URLByAppendingPathComponent:@"sessions"];
    if(!Dir(docs)||!Dir(base)||!Dir(root)||!Inside(root,docs)||!source.isFileURL||!Inside(source,root)||!Regular(source))return NO;
    if(![@[@"opus",@"ogg",@"pcm"] containsObject:source.pathExtension.lowercaseString])return NO;
    // Listing URLs carry the real path (/private/var/...), callers may pass the home-relative one (/var/...).
    char real[PATH_MAX];NSMutableArray *roots=[NSMutableArray arrayWithObject:root.path];if(realpath(root.fileSystemRepresentation,real))[roots addObject:@(real)];
    NSString *path=source.path,*rel=nil;
    for(NSString *r in roots){NSString *prefix=[r stringByAppendingString:@"/"];if([path hasPrefix:prefix]){rel=[path substringFromIndex:prefix.length];path=r;break;}}
    NSArray *parts=[rel componentsSeparatedByString:@"/"];if(!rel.length||parts.count>3)return NO;
    for(NSUInteger i=0;i<parts.count;i++){NSString *part=parts[i];if(!part.length||[part hasPrefix:@"."]||[part isEqual:@".."])return NO;path=[path stringByAppendingPathComponent:part];if(i+1<parts.count&&!Dir([NSURL fileURLWithPath:path]))return NO;}
    return YES;
}
static NSError *AudioError(void){return [NSError errorWithDomain:@"TurboIOAlwaysOnAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:TIOText(@"无法生成稳定的智记音频副本。请先停止本次全天智记，再刷新重试；原文件未改。")}];}
// Stable byte-for-byte copy into Documents/TurboIOAlwaysOnExports/<uuid>/ (the source must not change while it is read).
static NSURL *StableCopy(NSURL *home,NSURL *source,NSError **error){
    if(!source.isFileURL||!Regular(source)){if(error)*error=AudioError();return nil;}
    if(!Listed(home,source)){if(error)*error=AudioError();return nil;}
    int in=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);struct stat before,after,pathAfter;if(in<0||fstat(in,&before)||!S_ISREG(before.st_mode)||before.st_size<=0||before.st_size>1024LL*1024*1024){if(in>=0)close(in);if(error)*error=AudioError();return nil;}
    NSURL *base=[home URLByAppendingPathComponent:@"Documents/TurboIOAlwaysOnExports"],*folder=[base URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if([NSFileManager.defaultManager fileExistsAtPath:base.path]&&!Dir(base)){close(in);if(error)*error=AudioError();return nil;}
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]){close(in);return nil;}
    // Keep the actual format extension. Raw PCM is never renamed into fake WAV.
    NSURL *outURL=[folder URLByAppendingPathComponent:[/*i18n:keep*/@"全天智记音频." stringByAppendingString:source.pathExtension.lowercaseString]];
    int out=open(outURL.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);BOOL ok=out>=0;off_t copied=0;char buffer[65536];
    while(ok){ssize_t n=read(in,buffer,sizeof(buffer));if(!n)break;if(n<0){ok=NO;break;}copied+=n;if(copied>before.st_size){ok=NO;break;}for(ssize_t at=0;at<n;){ssize_t k=write(out,buffer+at,n-at);if(k<=0){ok=NO;break;}at+=k;}}
    ok=ok&&!fstat(in,&after)&&!lstat(source.fileSystemRepresentation,&pathAfter)&&before.st_size==copied&&before.st_size==after.st_size&&before.st_ino==pathAfter.st_ino&&before.st_dev==pathAfter.st_dev&&before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
    if(out>=0){if(fsync(out))ok=NO;close(out);}close(in);
    if(!ok){[NSFileManager.defaultManager removeItemAtURL:outURL error:nil];if(error)*error=AudioError();return nil;}return outURL;
}
static BOOL IsOgg(NSURL *u){return [@[@"opus",@"ogg"] containsObject:u.pathExtension.lowercaseString];}
NSURL *TIOAOAudioCopy(NSURL *home,NSURL *source,NSError **error){
    NSURL *outURL=StableCopy(home,source,error);if(!outURL)return nil;
    if(IsOgg(outURL)&&!TIOFinalizeAlwaysOnOgg(outURL)){[NSFileManager.defaultManager removeItemAtURL:outURL error:nil];if(error)*error=AudioError();return nil;}return outURL;
}
NSURL *TIOAOAudioCopyVerbatim(NSURL *home,NSURL *source,NSString **granules,NSError **error){
    if(granules)*granules=nil;if(!IsOgg(source)){if(error)*error=AudioError();return nil;}
    NSURL *outURL=StableCopy(home,source,error);if(!outURL)return nil;
    // The same structural check as TIOAOAudioCopy, run on a twin so the kept copy stays byte-for-byte: a twin that the
    // finalizer had to rewrite carried the official legacy granule clock.
    NSURL *twin=[outURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"check.ogg"];
    BOOL ok=[NSFileManager.defaultManager copyItemAtURL:outURL toURL:twin error:nil]&&TIOFinalizeAlwaysOnOgg(twin);NSData *a=ok?[NSData dataWithContentsOfURL:outURL options:NSDataReadingMappedIfSafe error:nil]:nil,*b=ok?[NSData dataWithContentsOfURL:twin options:NSDataReadingMappedIfSafe error:nil]:nil;
    ok=ok&&a&&b&&a.length==b.length;if(ok&&granules)*granules=[a isEqualToData:b]?@"toc-correct":@"official-legacy-20ms";
    unlink(twin.fileSystemRepresentation);
    if(!ok){[NSFileManager.defaultManager removeItemAtURL:outURL error:nil];if(error)*error=AudioError();return nil;}return outURL;
}
