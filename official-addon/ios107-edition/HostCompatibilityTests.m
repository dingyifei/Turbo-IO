#import "HostCompatibility.h"
#include <assert.h>
int main(void){@autoreleasepool{
    struct {struct mach_header_64 h;struct uuid_command c;} image={0};
    image.h.magic=MH_MAGIC_64;image.h.filetype=MH_EXECUTE;image.h.ncmds=1;image.h.sizeofcmds=sizeof(image.c);image.c.cmd=LC_UUID;image.c.cmdsize=sizeof(image.c);
    NSArray *pairs=@[@[@"1.0.2",@"67"],@[@"1.0.4",@"195"],@[@"1.0.5",@"201"],@[@"1.0.6",@"218"],@[@"1.0.7",@"230"]];
    for(NSArray *pair in pairs){
        NSDictionary *info=@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]};
        [[[NSUUID alloc]initWithUUIDString:TIOHostExpectedUUID(info)] getUUIDBytes:image.c.uuid];
        assert(TIOHostImageMatches((const void *)&image,info));
        for(NSArray *other in pairs)if(![other isEqual:pair]){
            NSDictionary *otherInfo=@{@"CFBundleShortVersionString":other[0],@"CFBundleVersion":other[1]};
            assert(!TIOHostImageMatches((const void *)&image,otherInfo));
            assert(!TIOHostExpectedUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":other[1]}));
        }
        image.c.uuid[0]^=1;assert(!TIOHostImageMatches((const void *)&image,info));image.c.uuid[0]^=1;
        image.c.cmdsize=8;assert(!TIOHostImageMatches((const void *)&image,info));image.c.cmdsize=sizeof(image.c);
        image.h.filetype=MH_DYLIB;assert(!TIOHostImageMatches((const void *)&image,info));image.h.filetype=MH_EXECUTE;
    }
    assert(!TIOHostExpectedUUID(@{@"CFBundleShortVersionString":@"1.0.4",@"CFBundleVersion":@"67"}));
    assert(!TIOHostExpectedUUID(@{}));assert(!TIOHostImageMatches(NULL,@{}));
    // 1.0.11/259 is a download-only host: exact UUID, never a full-feature host.
    NSDictionary *d=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.11",@"CFBundleVersion":@"259"};
    NSDictionary *full=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230"};
    assert([TIOHostDownloadOnlyUUID(d) isEqual:@"22724C97-2EF9-388D-8E6A-6E051855A555"]);
    assert(!TIOHostExpectedUUID(d));assert(!TIOHostDownloadOnlyUUID(full));
    for(NSArray *pair in pairs)assert(!TIOHostDownloadOnlyUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]}));
    for(NSArray *pair in @[@[@"1.0.11",@"258"],@[@"1.0.11",@"260"],@[@"1.0.10",@"259"],@[@"1.0.12",@"259"],@[@"1.0.11",@""]])assert(!TIOHostDownloadOnlyUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]}));
    [[[NSUUID alloc]initWithUUIDString:@"22724C97-2EF9-388D-8E6A-6E051855A555"] getUUIDBytes:image.c.uuid];
    assert(TIOHostDownloadOnlyImageMatches((const void *)&image,d));
    assert(!TIOHostImageMatches((const void *)&image,d));assert(!TIOHostImageMatches((const void *)&image,full));
    assert([TIOHostProfileFor((const void *)&image,d) isEqual:@"ios1011-download"]);
    assert(!TIOHostProfileFor((const void *)&image,full));
    NSMutableDictionary *other=[d mutableCopy];other[@"CFBundleIdentifier"]=@"example.other";
    assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,other));assert(!TIOHostProfileFor((const void *)&image,other));
    other=[d mutableCopy];other[@"CFBundleVersion"]=@"260";assert(!TIOHostProfileFor((const void *)&image,other));
    image.c.uuid[15]^=1;assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,d));assert(!TIOHostProfileFor((const void *)&image,d));image.c.uuid[15]^=1;
    image.h.filetype=MH_DYLIB;assert(!TIOHostProfileFor((const void *)&image,d));image.h.filetype=MH_EXECUTE;
    [[[NSUUID alloc]initWithUUIDString:TIOHostExpectedUUID(full)] getUUIDBytes:image.c.uuid];
    assert([TIOHostProfileFor((const void *)&image,full) isEqual:@"ios107"]);
    assert(!TIOHostProfileFor((const void *)&image,d));assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,d));
    NSDictionary *older=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.6",@"CFBundleVersion":@"218"};
    [[[NSUUID alloc]initWithUUIDString:TIOHostExpectedUUID(older)] getUUIDBytes:image.c.uuid];
    assert(TIOHostImageMatches((const void *)&image,older));assert(!TIOHostProfileFor((const void *)&image,older));
    assert(!TIOHostProfileFor(NULL,d));assert(!TIOHostProfileFor(NULL,@{}));
    puts("PASS host version/build/UUID guards; 1.0.11/259 download-only profile exact");
}}
