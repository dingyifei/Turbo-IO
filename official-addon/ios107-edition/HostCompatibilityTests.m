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
    // The full 1.0.11 profile: the same image, selected only by the exact packager marker.
    // A missing or unknown marker is the download-only profile; the old download-only IPA keeps its own marker.
    [[[NSUUID alloc]initWithUUIDString:@"22724C97-2EF9-388D-8E6A-6E051855A555"] getUUIDBytes:image.c.uuid];
    NSMutableDictionary *fullMarked=[d mutableCopy];fullMarked[@"TIOHostProfile"]=@"ios1011";
    assert([TIOHostProfileFor((const void *)&image,fullMarked) isEqual:@"ios1011"]);
    assert(TIOHostFullImageMatches((const void *)&image,fullMarked));assert([TIOHostFullExpectedUUID(fullMarked) isEqual:@"22724C97-2EF9-388D-8E6A-6E051855A555"]);
    assert(!TIOHostImageMatches((const void *)&image,fullMarked));assert(!TIOHostExpectedUUID(fullMarked));
    for(id marker in @[@"ios1011-download",@"ios1011-full",@"IOS1011",@"ios1011 ",@"",@"ios107",@1,@[@"ios1011"],NSNull.null]){
        NSMutableDictionary *m=[d mutableCopy];m[@"TIOHostProfile"]=marker;
        assert([TIOHostProfileFor((const void *)&image,m) isEqual:@"ios1011-download"]);
        assert(!TIOHostFullImageMatches((const void *)&image,m));assert(!TIOHostFullExpectedUUID(m));
    }
    assert([TIOHostProfileFor((const void *)&image,d) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,d));
    // The marker never widens anything else: another bundle, build or image stays out.
    NSMutableDictionary *wrong=[fullMarked mutableCopy];wrong[@"CFBundleIdentifier"]=@"example.other";
    assert(!TIOHostProfileFor((const void *)&image,wrong));assert(!TIOHostFullImageMatches((const void *)&image,wrong));
    wrong=[fullMarked mutableCopy];wrong[@"CFBundleVersion"]=@"260";assert(!TIOHostProfileFor((const void *)&image,wrong));assert(!TIOHostFullImageMatches((const void *)&image,wrong));
    image.c.uuid[15]^=1;assert(!TIOHostProfileFor((const void *)&image,fullMarked));assert(!TIOHostFullImageMatches((const void *)&image,fullMarked));image.c.uuid[15]^=1;
    NSMutableDictionary *full107=[full mutableCopy];full107[@"TIOHostProfile"]=@"ios1011";
    [[[NSUUID alloc]initWithUUIDString:TIOHostExpectedUUID(full)] getUUIDBytes:image.c.uuid];
    assert([TIOHostProfileFor((const void *)&image,full107) isEqual:@"ios107"]);assert(TIOHostFullImageMatches((const void *)&image,full107));
    assert(!TIOHostFullImageMatches((const void *)&image,fullMarked));
    // Every inspected full host still matches through the full-image check, with or without a marker.
    for(NSArray *pair in pairs){NSDictionary *info=@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]};assert([TIOHostFullExpectedUUID(info) isEqual:TIOHostExpectedUUID(info)]);}
    // 1.0.21/1: download-only (C19) without its own marker; the full C20 profile "ios1021" only with the
    // exact marker "ios1021" on the exact 1.0.21/1 image. The 1.0.11 marker never selects it, nor does the
    // 1.0.21 marker select anything on 1.0.11.
    {
        NSDictionary *n=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.21",@"CFBundleVersion":@"1"};
        assert([TIOHostDownloadOnlyUUID(n) isEqual:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"]);assert(!TIOHostExpectedUUID(n));
        for(NSArray *pair in @[@[@"1.0.21",@"259"],@[@"1.0.21",@"2"],@[@"1.0.20",@"1"],@[@"1.0.22",@"1"],@[@"1.0.21",@""]])assert(!TIOHostDownloadOnlyUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]}));
        [[[NSUUID alloc]initWithUUIDString:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"] getUUIDBytes:image.c.uuid];
        assert([TIOHostProfileFor((const void *)&image,n) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,n));
        for(id marker in @[@"ios1011",@"ios1021-download",@"ios1011-download",@"IOS1021",@"ios1021 ",@"ios1021-full",@"",@"ios107",@1021,@[@"ios1021"],NSNull.null]){
            NSMutableDictionary *m=[n mutableCopy];m[@"TIOHostProfile"]=marker;
            assert([TIOHostProfileFor((const void *)&image,m) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,m));assert(!TIOHostFullExpectedUUID(m));
        }
        NSMutableDictionary *marked=[n mutableCopy];marked[@"TIOHostProfile"]=@"ios1021";
        assert([TIOHostProfileFor((const void *)&image,marked) isEqual:@"ios1021"]);assert(TIOHostFullImageMatches((const void *)&image,marked));
        assert([TIOHostFullExpectedUUID(marked) isEqual:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"]);assert(!TIOHostImageMatches((const void *)&image,marked));
        assert([TIOHostFullMarkerProfile(marked) isEqual:@"ios1021"]&&!TIOHostFullMarkerProfile(n));
        // The 1.0.21 marker widens nothing else: another bundle, build, version or image stays out.
        NSMutableDictionary *wrong=[marked mutableCopy];wrong[@"CFBundleIdentifier"]=@"example.other";
        assert(!TIOHostProfileFor((const void *)&image,wrong));assert(!TIOHostFullImageMatches((const void *)&image,wrong));
        for(NSArray *kv in @[@[@"CFBundleVersion",@"2"],@[@"CFBundleVersion",@"259"],@[@"CFBundleShortVersionString",@"1.0.11"]]){
            wrong=[marked mutableCopy];wrong[kv[0]]=kv[1];assert(!TIOHostFullImageMatches((const void *)&image,wrong));assert(![TIOHostProfileFor((const void *)&image,wrong) isEqual:@"ios1021"]);
        }
        image.c.uuid[15]^=1;assert(!TIOHostProfileFor((const void *)&image,marked));assert(!TIOHostFullImageMatches((const void *)&image,marked));image.c.uuid[15]^=1;
        // The 1.0.11 image with the 1.0.21 marker: the download-only profile, never a full one.
        NSMutableDictionary *crossed=[d mutableCopy];crossed[@"TIOHostProfile"]=@"ios1021";
        assert(!TIOHostFullImageMatches((const void *)&image,crossed));
        [[[NSUUID alloc]initWithUUIDString:@"22724C97-2EF9-388D-8E6A-6E051855A555"] getUUIDBytes:image.c.uuid];
        assert([TIOHostProfileFor((const void *)&image,crossed) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,crossed));assert(!TIOHostFullExpectedUUID(crossed));
        // Each image only matches as itself: the 1.0.11 image never passes as 1.0.21 and vice versa.
        assert(!TIOHostProfileFor((const void *)&image,n));assert(!TIOHostFullImageMatches((const void *)&image,marked));
    }
    puts("PASS host version/build/UUID guards; 1.0.11/259 and 1.0.21/1 download-only profiles exact; each full profile only on its own exact marker and image");
}}
