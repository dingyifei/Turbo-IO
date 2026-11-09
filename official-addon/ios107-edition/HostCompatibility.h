#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#include <string.h>

// Inspected host builds only. Interface signatures are independently checked
// before installing hooks; inclusion is not a claim of feature acceptance.
static inline NSString *TIOHostExpectedUUID(NSDictionary *info) {
    NSString *version=info[@"CFBundleShortVersionString"];
    NSString *build=[info[@"CFBundleVersion"] description];
    if([version isEqual:@"1.0.2"]&&[build isEqual:@"67"])return @"EEEA85E5-4114-313C-B651-73C90A6B5D3C";
    if([version isEqual:@"1.0.4"]&&[build isEqual:@"195"])return @"261C8E78-F955-3D7D-85F7-13B9082972CF";
    if([version isEqual:@"1.0.5"]&&[build isEqual:@"201"])return @"748FD301-DA60-3095-A244-9BD0558FACA5";
    if([version isEqual:@"1.0.6"]&&[build isEqual:@"218"])return @"98A03B57-E816-3BA1-9778-E55FABE8D762";
    if([version isEqual:@"1.0.7"]&&[build isEqual:@"230"])return @"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B";
    return nil;
}
// The 1.0.11/259 image is deliberately NOT in the table above, so every feature
// gated on TIOHostImageMatches or TIOHostExpectedUUID stays off there. The same
// image serves two profiles, told apart only by the packager's Info.plist marker
// TIOHostProfile (both IPAs share the Runner UUID):
//   "ios1011"  the full 1.0.11 build (C15): features on, TMG flashing disarmed until armed;
//   anything else, missing included: "ios1011-download", the refusing download-only guard.
// On the download-only profile the addon installs only the rayneonet channel hook,
// which carries the OTA transfer guard. Exact version, build and UUID; no ranges.
// (The name predates the full profile; it identifies the 1.0.11 image for both.)
static inline NSString *TIOHostDownloadOnlyUUID(NSDictionary *info) {
    NSString *version=info[@"CFBundleShortVersionString"];
    NSString *build=[info[@"CFBundleVersion"] description];
    if([version isEqual:@"1.0.11"]&&[build isEqual:@"259"])return @"22724C97-2EF9-388D-8E6A-6E051855A555";
    return nil;
}
static inline BOOL TIOHostImageUUIDIs(const struct mach_header *h,NSString *expected) {
    if(!expected||!h||h->magic!=MH_MAGIC_64||h->filetype!=MH_EXECUTE||h->ncmds>1024||h->sizeofcmds>1024*1024)return NO;
    const uint8_t *p=(const uint8_t *)h+sizeof(struct mach_header_64),*end=p+h->sizeofcmds;
    for(uint32_t i=0;i<h->ncmds;i++){
        if((size_t)(end-p)<sizeof(struct load_command))return NO;
        const struct load_command *c=(const void *)p;
        if(c->cmdsize<sizeof(*c)||c->cmdsize%8||c->cmdsize>(size_t)(end-p))return NO;
        if(c->cmd==LC_UUID){if(c->cmdsize!=sizeof(struct uuid_command))return NO;return [[[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString] isEqual:expected];}
        p+=c->cmdsize;
    }
    return NO;
}
static inline BOOL TIOHostImageMatches(const struct mach_header *h,NSDictionary *info) {
    return TIOHostImageUUIDIs(h,TIOHostExpectedUUID(info));
}
// The packager's marker for the full 1.0.11 profile. Only this exact string selects it.
#define TIO_HOST_PROFILE_1011_FULL @"ios1011"
static inline BOOL TIOHost1011FullMarker(NSDictionary *info) {
    return [info[@"TIOHostProfile"] isKindOfClass:NSString.class]&&[info[@"TIOHostProfile"] isEqualToString:TIO_HOST_PROFILE_1011_FULL];
}
// TIOHostExpectedUUID plus the 1.0.11 UUID, the latter only with the full-profile marker.
// Features gate on this (or TIOHostFullImageMatches), so the download-only build keeps them off.
static inline NSString *TIOHostFullExpectedUUID(NSDictionary *info) {
    NSString *uuid=TIOHostExpectedUUID(info);if(uuid)return uuid;
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]&&TIOHost1011FullMarker(info)?TIOHostDownloadOnlyUUID(info):nil;
}
static inline BOOL TIOHostFullImageMatches(const struct mach_header *h,NSDictionary *info) {
    return TIOHostImageUUIDIs(h,TIOHostFullExpectedUUID(info));
}
static inline BOOL TIOHostDownloadOnlyImageMatches(const struct mach_header *h,NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]&&TIOHostImageUUIDIs(h,TIOHostDownloadOnlyUUID(info));
}
// "ios107" for the full 1.0.7/230 host; for the 1.0.11/259 image "ios1011" with the
// full-profile marker and "ios1011-download" otherwise (missing or unknown marker);
// nil for anything else (older inspected hosts included).
static inline NSString *TIOHostProfileFor(const struct mach_header *h,NSDictionary *info) {
    if(![info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"])return nil;
    if(TIOHostDownloadOnlyImageMatches(h,info))return TIOHost1011FullMarker(info)?TIO_HOST_PROFILE_1011_FULL:@"ios1011-download";
    if([info[@"CFBundleShortVersionString"] isEqual:@"1.0.7"]&&[[info[@"CFBundleVersion"] description] isEqual:@"230"]&&TIOHostImageMatches(h,info))return @"ios107";
    return nil;
}
// Header of the running process's main executable (the image whose path is the
// main bundle's executable), looked up once; NULL when not found.
static inline const struct mach_header *TIOHostMainImage(void) {
    static const struct mach_header *image;static dispatch_once_t once;
    dispatch_once(&once,^{
        const char *executable=NSBundle.mainBundle.executablePath.fileSystemRepresentation;
        for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&executable&&strcmp(name,executable)==0){image=_dyld_get_image_header(i);break;}}
    });
    return image;
}
// Profile of the running host's main executable image; nil when unknown. Defined in Addon.m.
FOUNDATION_EXPORT NSString *TIOHostProfile(void);
// YES only on the download-only host when the rayneonet transport hook that
// applies the (flag-independent) OTA refusal is installed and recorded ready.
// Defined in Addon.m on top of TIODownloadOnlyGuardActiveFor (DownloadOnlySafety.h).
// The UI must show a loud warning when the profile is download-only and this is NO.
FOUNDATION_EXPORT BOOL TIOHostDownloadOnlyGuardActive(void);
