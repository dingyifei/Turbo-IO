#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#include <string.h>

// The one supported host: RayNeo AI 1.0.21/1. The same image serves two profiles, told
// apart only by the packager's Info.plist marker TIOHostProfile (both IPAs share the Runner UUID):
//   "ios1021"           the full build: features on, every TMG transfer frame through the flash gate;
//   anything else, missing included: "ios1011-download", the refusing download-only guard.
// On the download-only profile the addon installs only the rayneonet channel hook,
// which carries the OTA transfer guard. Exact version, build and UUID; no ranges.
// Any other app version, older RayNeo AI releases included, matches nothing here: no
// profile, no features, no flashing (the packager refuses to build for it as well).
static inline NSString *TIOHostDownloadOnlyUUID(NSDictionary *info) {
    NSString *version=info[@"CFBundleShortVersionString"];
    NSString *build=[info[@"CFBundleVersion"] description];
    if([version isEqual:@"1.0.21"]&&[build isEqual:@"1"])return @"74DA0780-DCF0-384F-9E84-1AC12F56CDF5";
    return nil;
}
static inline BOOL TIOHostIs1021(NSDictionary *info) {
    return [info[@"CFBundleShortVersionString"] isEqual:@"1.0.21"]&&[[info[@"CFBundleVersion"] description] isEqual:@"1"];
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
// The packager's marker for the full 1.0.21 profile (C20). Only this exact string selects it.
#define TIO_HOST_PROFILE_1021_FULL @"ios1021"
static inline BOOL TIOHost1021FullMarker(NSDictionary *info) {
    return [info[@"TIOHostProfile"] isKindOfClass:NSString.class]&&[info[@"TIOHostProfile"] isEqualToString:TIO_HOST_PROFILE_1021_FULL];
}
// "ios1021" for the full-profile marker on 1.0.21/1, else nil. (The image UUID is checked by the callers.)
static inline NSString *TIOHostFullMarkerProfile(NSDictionary *info) {
    return TIOHost1021FullMarker(info)&&TIOHostIs1021(info)?TIO_HOST_PROFILE_1021_FULL:nil;
}
// The 1.0.21 UUID, only with the full-profile marker. Features gate on this (or
// TIOHostFullImageMatches), so the download-only build keeps them off.
static inline NSString *TIOHostFullExpectedUUID(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]&&TIOHostFullMarkerProfile(info)?TIOHostDownloadOnlyUUID(info):nil;
}
static inline BOOL TIOHostFullImageMatches(const struct mach_header *h,NSDictionary *info) {
    return TIOHostImageUUIDIs(h,TIOHostFullExpectedUUID(info));
}
static inline BOOL TIOHostDownloadOnlyImageMatches(const struct mach_header *h,NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]&&TIOHostImageUUIDIs(h,TIOHostDownloadOnlyUUID(info));
}
// The download-only runtime profile: the 1.0.21/1 image without its full-profile marker. The string
// keeps its C15-era spelling: the packager writes it as the Info.plist marker and other modules compare it.
#define TIO_HOST_PROFILE_DOWNLOAD_ONLY @"ios1011-download"
// For the 1.0.21/1 image: "ios1021" with its full-profile marker, "ios1011-download" otherwise
// (missing or unknown marker); nil for anything else (an unknown app or version, older RayNeo AI
// releases included, or a build that is not the RayNeo app, such as a preview).
static inline NSString *TIOHostProfileFor(const struct mach_header *h,NSDictionary *info) {
    if(![info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"])return nil;
    if(TIOHostDownloadOnlyImageMatches(h,info))return TIOHostFullMarkerProfile(info)?:TIO_HOST_PROFILE_DOWNLOAD_ONLY;
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
