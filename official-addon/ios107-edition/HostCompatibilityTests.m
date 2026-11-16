#import "HostCompatibility.h"
#include <assert.h>
int main(void){@autoreleasepool{
    struct {struct mach_header_64 h;struct uuid_command c;} image={0};
    image.h.magic=MH_MAGIC_64;image.h.filetype=MH_EXECUTE;image.h.ncmds=1;image.h.sizeofcmds=sizeof(image.c);image.c.cmd=LC_UUID;image.c.cmdsize=sizeof(image.c);
    // 1.0.21/1: download-only (C19) without its own marker; the full profile "ios1021" (C20 onward) only with the
    // exact marker "ios1021" on the exact 1.0.21/1 image.
    NSDictionary *n=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.21",@"CFBundleVersion":@"1"};
    assert([TIOHostDownloadOnlyUUID(n) isEqual:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"]);
    for(NSArray *pair in @[@[@"1.0.21",@"259"],@[@"1.0.21",@"2"],@[@"1.0.20",@"1"],@[@"1.0.22",@"1"],@[@"1.0.21",@""]])assert(!TIOHostDownloadOnlyUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]}));
    assert(!TIOHostDownloadOnlyUUID(@{}));assert(!TIOHostProfileFor(NULL,n));assert(!TIOHostProfileFor(NULL,@{}));
    [[[NSUUID alloc]initWithUUIDString:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"] getUUIDBytes:image.c.uuid];
    assert(TIOHostDownloadOnlyImageMatches((const void *)&image,n));
    assert([TIOHostProfileFor((const void *)&image,n) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,n));
    // The image checks: one UUID bit, a bad command size or a dylib header all fail.
    image.c.uuid[0]^=1;assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,n));assert(!TIOHostProfileFor((const void *)&image,n));image.c.uuid[0]^=1;
    image.c.cmdsize=8;assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,n));image.c.cmdsize=sizeof(image.c);
    image.h.filetype=MH_DYLIB;assert(!TIOHostProfileFor((const void *)&image,n));image.h.filetype=MH_EXECUTE;
    NSMutableDictionary *other=[n mutableCopy];other[@"CFBundleIdentifier"]=@"example.other";
    assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,other));assert(!TIOHostProfileFor((const void *)&image,other));
    other=[n mutableCopy];other[@"CFBundleVersion"]=@"2";assert(!TIOHostProfileFor((const void *)&image,other));
    // A missing or unknown marker is the download-only profile (retired profile names included).
    for(id marker in @[@"ios1011",@"ios1021-download",@"ios1011-download",@"IOS1021",@"ios1021 ",@"ios1021-full",@"",@"ios107",@1021,@[@"ios1021"],NSNull.null]){
        NSMutableDictionary *m=[n mutableCopy];m[@"TIOHostProfile"]=marker;
        assert([TIOHostProfileFor((const void *)&image,m) isEqual:@"ios1011-download"]);assert(!TIOHostFullImageMatches((const void *)&image,m));assert(!TIOHostFullExpectedUUID(m));
    }
    NSMutableDictionary *marked=[n mutableCopy];marked[@"TIOHostProfile"]=@"ios1021";
    assert([TIOHostProfileFor((const void *)&image,marked) isEqual:@"ios1021"]);assert(TIOHostFullImageMatches((const void *)&image,marked));
    assert([TIOHostFullExpectedUUID(marked) isEqual:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"]);
    assert([TIOHostFullMarkerProfile(marked) isEqual:@"ios1021"]&&!TIOHostFullMarkerProfile(n));
    // The marker widens nothing else: another bundle, build, version or image stays out.
    NSMutableDictionary *wrong=[marked mutableCopy];wrong[@"CFBundleIdentifier"]=@"example.other";
    assert(!TIOHostProfileFor((const void *)&image,wrong));assert(!TIOHostFullImageMatches((const void *)&image,wrong));
    for(NSArray *kv in @[@[@"CFBundleVersion",@"2"],@[@"CFBundleVersion",@"259"],@[@"CFBundleShortVersionString",@"1.0.11"],@[@"CFBundleShortVersionString",@"1.0.22"]]){
        wrong=[marked mutableCopy];wrong[kv[0]]=kv[1];assert(!TIOHostFullImageMatches((const void *)&image,wrong));assert(!TIOHostProfileFor((const void *)&image,wrong));
    }
    image.c.uuid[15]^=1;assert(!TIOHostProfileFor((const void *)&image,marked));assert(!TIOHostFullImageMatches((const void *)&image,marked));image.c.uuid[15]^=1;
    // Older RayNeo AI releases (their own version, build and Runner UUID, from the retired host table) fail
    // closed: no profile, no full features, no download-only guard, with or without any marker.
    NSArray *older=@[@[@"1.0.2",@"67",@"EEEA85E5-4114-313C-B651-73C90A6B5D3C"],@[@"1.0.4",@"195",@"261C8E78-F955-3D7D-85F7-13B9082972CF"],
        @[@"1.0.5",@"201",@"748FD301-DA60-3095-A244-9BD0558FACA5"],@[@"1.0.6",@"218",@"98A03B57-E816-3BA1-9778-E55FABE8D762"],
        @[@"1.0.7",@"230",@"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B"],@[@"1.0.11",@"259",@"22724C97-2EF9-388D-8E6A-6E051855A555"]];
    for(NSArray *host in older){
        [[[NSUUID alloc]initWithUUIDString:host[2]] getUUIDBytes:image.c.uuid];
        for(id marker in @[NSNull.null,@"ios1021",@"ios1021-download",@"ios1011",@"ios1011-download",@"ios107"]){
            NSMutableDictionary *info=[@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":host[0],@"CFBundleVersion":host[1]} mutableCopy];
            if(marker!=NSNull.null)info[@"TIOHostProfile"]=marker;
            assert(!TIOHostProfileFor((const void *)&image,info));assert(!TIOHostFullImageMatches((const void *)&image,info));
            assert(!TIOHostDownloadOnlyImageMatches((const void *)&image,info));assert(!TIOHostFullExpectedUUID(info));assert(!TIOHostDownloadOnlyUUID(info));
        }
    }
    // A build that is not the RayNeo app (the UI preview, the Mac tests) has no host profile either.
    [[[NSUUID alloc]initWithUUIDString:@"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"] getUUIDBytes:image.c.uuid];
    NSDictionary *preview=@{@"CFBundleIdentifier":@"example.preview",@"CFBundleShortVersionString":@"1.0",@"CFBundleVersion":@"1"};
    assert(!TIOHostProfileFor((const void *)&image,preview));assert(!TIOHostFullImageMatches((const void *)&image,preview));
    puts("PASS host version/build/UUID guards; 1.0.21/1 download-only profile exact; the full profile only on its exact marker and image; older releases and other apps match nothing");
}}
