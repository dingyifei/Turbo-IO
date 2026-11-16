#import "ExperimentalOTA.h"
#import "FirmwarePins.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *candidate=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSURL *original=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]] isDirectory:YES];NSError *error=nil;
    NSDictionary *tmg=TIOOTAPackageAt(0),*stock=TIOOTAPackageAt(1);assert(tmg&&stock);NSDictionary *pins=tmg[@"memberPins"];
    NSDictionary *good=TIOCheckOfficialOTADirectory(candidate,tmg,&error);assert(good&&!error);assert([good[@"checkedMembers"] unsignedIntegerValue]==pins.count);assert(![good[@"transferSessionBound"] boolValue]);assert(![good[@"flashAuthorized"] boolValue]);assert([good[@"candidate"] isEqual:[@"Turbo Menu " stringByAppendingString:tmg[@"name"]]]);
    // argv[2] is the base's stock members: they fail as the TMG package and pass as the stock package; the TMG folder
    // fails as the stock package. The message names the package that was checked.
    assert([fm fileExistsAtPath:original.path]);assert(!TIOCheckOfficialOTADirectory(original,tmg,&error));assert([error.localizedDescription containsString:tmg[@"name"]]);
    error=nil;NSDictionary *stockGood=TIOCheckOfficialOTADirectory(original,stock,&error);assert(stockGood&&!error);
    assert([stockGood[@"checkedMembers"] unsignedIntegerValue]==[stock[@"memberPins"] count]&&[stockGood[@"candidate"] isEqual:TIOOTAPackageDisplayName(stock)]&&[stockGood[@"package"] isEqual:stock[@"name"]]);
    assert(!TIOCheckOfficialOTADirectory(candidate,stock,&error));assert([error.localizedDescription containsString:TIOOTAPackageDisplayName(stock)]);
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tio-ota-directory-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    for(int scenario=0;scenario<7;scenario++){
        NSURL *folder=[root URLByAppendingPathComponent:[NSString stringWithFormat:@"case-%d",scenario] isDirectory:YES];assert([fm copyItemAtURL:candidate toURL:folder error:nil]);
        NSURL *target=[folder URLByAppendingPathComponent:@"smf.json"];
        if(scenario==0){NSMutableData *data=[[NSData dataWithContentsOfURL:target] mutableCopy];((uint8_t *)data.mutableBytes)[10]^=1;assert([data writeToURL:target atomically:NO]);}
        if(scenario==1)assert([fm removeItemAtURL:target error:nil]);
        if(scenario==2){assert([fm removeItemAtURL:target error:nil]);assert([fm createSymbolicLinkAtURL:target withDestinationURL:[candidate URLByAppendingPathComponent:@"smf.json"] error:nil]);}
        if(scenario==3){assert([fm removeItemAtURL:target error:nil]);assert(mkfifo(target.path.fileSystemRepresentation,0600)==0);}
        if(scenario==4)assert([[NSData data] writeToURL:[folder URLByAppendingPathComponent:@"unexpected"] atomically:NO]);
        if(scenario==5){assert([fm removeItemAtURL:target error:nil]);assert([fm createDirectoryAtURL:target withIntermediateDirectories:NO attributes:nil error:nil]);}
        if(scenario==6){assert(link(target.path.fileSystemRepresentation,[root URLByAppendingPathComponent:@"hardlink"].path.fileSystemRepresentation)==0);}
        // An extra file beside the members, or a member with a second hard link, holds the pinned bytes: the folder
        // passes, because only the pinned members are read (once, into memory) and sent.
        if(scenario==4||scenario==6){error=nil;assert(TIOCheckOfficialOTADirectory(folder,tmg,&error)&&!error);continue;}
        assert(!TIOCheckOfficialOTADirectory(folder,tmg,&error));
    }
    NSURL *linkURL=[root URLByAppendingPathComponent:@"linked-directory"];assert([fm createSymbolicLinkAtURL:linkURL withDestinationURL:candidate error:nil]);assert(!TIOCheckOfficialOTADirectory(linkURL,tmg,&error));
    // Only this test-owned UUID directory is removed; original/candidate untouched.
    assert([fm removeItemAtURL:root error:nil]);
    NSLog(@"PASS: exact %lu-member candidate snapshot; stock folder only as the stock package; original cache, mutation, missing file, symlink, FIFO and directory rejected, extra file and hardlink accepted; no writes to official cache, no transfer authorization",(unsigned long)pins.count);
}return 0;}
