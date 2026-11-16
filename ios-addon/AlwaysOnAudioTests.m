#import "AlwaysOnAudio.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *home=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];NSURL *folder=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/synthetic"];
    assert([fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]);NSData *data=[@"synthetic raw PCM fixture" dataUsingEncoding:NSUTF8StringEncoding];NSURL *file=[folder URLByAppendingPathComponent:@"realtime_test.pcm"];assert([data writeToURL:file atomically:YES]);
    NSURL *events=[folder URLByAppendingPathComponent:@"events.jsonl"],*link=[folder URLByAppendingPathComponent:@"link.opus"];assert([data writeToURL:events atomically:YES]);assert([fm createSymbolicLinkAtURL:link withDestinationURL:file error:nil]);
    NSArray *rows=TIOAOAudioFiles(home);assert(rows.count==1);assert([rows[0][@"kind"] isEqual:@"实时音频"]);
    NSURL *copy=TIOAOAudioCopy(home,file,nil);assert(copy&&![copy isEqual:file]&&[[NSData dataWithContentsOfURL:copy] isEqual:data]);assert([[NSData dataWithContentsOfURL:file] isEqual:data]);assert(!TIOAOAudioCopy(home,events,nil));assert(!TIOAOAudioCopy(home,link,nil));
    NSURL *mock=[home URLByAppendingPathComponent:@"Documents/always_on_debug/mock_inputs"];assert([fm createDirectoryAtURL:mock withIntermediateDirectories:YES attributes:nil error:nil]);NSURL *mockFile=[mock URLByAppendingPathComponent:@"mock.opus"];assert([data writeToURL:mockFile atomically:YES]);assert(!TIOAOAudioCopy(home,mockFile,nil));assert(TIOAOAudioFiles(home).count==1);
    // Membership is checked on the path itself: listing URLs (real /private paths) copy; deeper, hidden or symlinked folders never do.
    assert(TIOAOAudioCopy(home,rows[0][@"url"],nil));NSURL *root=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions"];
    NSURL *deep=[root URLByAppendingPathComponent:@"a/b/c"],*hidden=[root URLByAppendingPathComponent:@".hidden"],*real=[home URLByAppendingPathComponent:@"elsewhere"],*linked=[root URLByAppendingPathComponent:@"linked"];
    for(NSURL *d in @[deep,hidden,real])assert([fm createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil]);assert([fm createSymbolicLinkAtURL:linked withDestinationURL:real error:nil]);
    NSURL *ok=[root URLByAppendingPathComponent:@"a/b/realtime_ok.pcm"];assert([data writeToURL:ok atomically:YES]);assert(TIOAOAudioCopy(home,ok,nil));
    for(NSURL *bad in @[[deep URLByAppendingPathComponent:@"x.pcm"],[hidden URLByAppendingPathComponent:@"x.pcm"],[real URLByAppendingPathComponent:@"x.pcm"]]){assert([data writeToURL:bad atomically:YES]);}
    assert(!TIOAOAudioCopy(home,[deep URLByAppendingPathComponent:@"x.pcm"],nil)&&!TIOAOAudioCopy(home,[hidden URLByAppendingPathComponent:@"x.pcm"],nil)&&!TIOAOAudioCopy(home,[linked URLByAppendingPathComponent:@"x.pcm"],nil));
    assert(TIOAOAudioFiles(home).count==2);
    // Past the 500-row display cap the newest files are kept (sorted before the cap), and files outside the rows still copy.
    NSURL *many=[root URLByAppendingPathComponent:@"many"];assert([fm createDirectoryAtURL:many withIntermediateDirectories:YES attributes:nil error:nil]);
    for(int i=0;i<600;i++){NSURL *u=[many URLByAppendingPathComponent:[NSString stringWithFormat:@"realtime_%03d.pcm",i]];assert([data writeToURL:u atomically:NO]);assert([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:1700000000+i]} ofItemAtPath:u.path error:nil]);}
    NSURL *newest=[many URLByAppendingPathComponent:@"realtime_new.pcm"];assert([data writeToURL:newest atomically:NO]);assert([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:1900000000]} ofItemAtPath:newest.path error:nil]);
    rows=TIOAOAudioFiles(home);assert(rows.count==500&&[rows[0][@"name"] isEqual:@"realtime_new.pcm"]);
    for(NSUInteger i=1;i<rows.count;i++)assert([rows[i-1][@"date"] compare:rows[i][@"date"]]!=NSOrderedAscending);
    assert(TIOAOAudioCopy(home,[many URLByAppendingPathComponent:@"realtime_000.pcm"],nil)); // oldest, not among the 500 rows
    assert([fm removeItemAtURL:home error:nil]);puts("PASS: scoped AlwaysOn sessions, mock/event exclusion, symlink/hidden/depth rejection by path, newest-first 500-row cap, independent copies and original preservation. Synthetic only.");
}return 0;}
