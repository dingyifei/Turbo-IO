#import "DownloadOnlySafety.h"

static BOOL Signature(Method m,NSUInteger n){
    if(!m||method_getNumberOfArguments(m)!=n)return NO;
    char *r=method_copyReturnType(m);BOOL ok=r&&r[0]=='v';free(r);
    for(NSUInteger i=2;i<n;i++){char *t=method_copyArgumentType(m,(unsigned)i);ok=ok&&t&&t[0]=='@';free(t);}
    return ok;
}
NSString *TIOChannelHookTargetFailure(Class bridge,Class engine){
    if(!bridge)return @"bridge class missing";
    if(!Signature(class_getInstanceMethod(bridge,NSSelectorFromString(@"handleMethodCall:result:")),4))return @"bridge handleMethodCall:result: missing or signature mismatch";
    if(!engine)return @"FlutterEngine class missing";
    if(!Signature(class_getInstanceMethod(engine,NSSelectorFromString(@"sendOnChannel:message:binaryReply:")),5))return @"FlutterEngine sendOnChannel:message:binaryReply: missing or signature mismatch";
    return nil;
}
BOOL TIODownloadOnlyGuardActiveFor(NSString *profile,BOOL hookInstalled,BOOL transportHookReady){
    return [profile isEqual:@"ios1011-download"]&&hookInstalled&&transportHookReady;
}
static NSString *Unprivate(NSString *p){return [p hasPrefix:@"/private/"]?[p substringFromIndex:8]:p;}
BOOL TIOChannelResultImageIsStock(NSString *imagePath,NSString *addonImagePath,NSString *bundlePath){
    if(![imagePath isKindOfClass:NSString.class]||!imagePath.length||![bundlePath isKindOfClass:NSString.class]||!bundlePath.length)return NO;
    NSString *image=Unprivate(imagePath.stringByStandardizingPath),*bundle=Unprivate(bundlePath.stringByStandardizingPath);
    if([addonImagePath isKindOfClass:NSString.class]&&[image isEqual:Unprivate(addonImagePath.stringByStandardizingPath)])return NO;
    if([image.lastPathComponent hasPrefix:@"Turbo"])return NO;
    return [image hasPrefix:[bundle stringByAppendingString:@"/"]];
}
NSString *TIODownloadOnlyGuardLevelFor(NSString *profile,BOOL hookInstalled,BOOL transportHookReady,BOOL stockTrafficSeen){
    if(!TIODownloadOnlyGuardActiveFor(profile,hookInstalled,transportHookReady))return @"danger";
    return stockTrafficSeen?@"ok":@"warn";
}
TIOAutoUpdateReading TIOAutoUpdateReadingFor(NSDictionary *preferences){
    if(![preferences isKindOfClass:NSDictionary.class])return TIOAutoUpdateReadingMissing;
    NSUInteger found=0;
    for(id key in preferences){
        if(![key isKindOfClass:NSString.class]||![key hasSuffix:@"_ota_firmware_auto_update"])continue;found++;
        id v=preferences[key];
        BOOL off=[v isKindOfClass:NSString.class]?[v isEqual:@"false"]:
            ([v isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID()&&![v boolValue]);
        if(!off)return TIOAutoUpdateReadingOn;
    }
    return found?TIOAutoUpdateReadingOff:TIOAutoUpdateReadingMissing;
}
NSString *TIOAutoUpdateReadingName(TIOAutoUpdateReading state){
    return state==TIOAutoUpdateReadingOff?@"off":state==TIOAutoUpdateReadingMissing?@"missing":@"on";
}
NSDictionary *TIOFirmwareExportSafetyModel(NSString *profile,BOOL hookInstalled,BOOL transportHookReady,BOOL stockTrafficSeen,NSDictionary *preferences){
    BOOL guard=TIODownloadOnlyGuardActiveFor(profile,hookInstalled,transportHookReady);
    NSString *guardLevel=TIODownloadOnlyGuardLevelFor(profile,hookInstalled,transportHookReady,stockTrafficSeen);
    NSString *guardKey=[guardLevel isEqual:@"ok"]?@"fwexport.guard.on":[guardLevel isEqual:@"warn"]?@"fwexport.guard.waiting":@"fwexport.guard.off";
    TIOAutoUpdateReading autoUpdate=TIOAutoUpdateReadingFor(preferences);
    NSString *autoLevel=autoUpdate==TIOAutoUpdateReadingOff?@"ok":autoUpdate==TIOAutoUpdateReadingMissing?@"warn":@"danger";
    NSString *level=[guardLevel isEqual:@"danger"]||autoUpdate==TIOAutoUpdateReadingOn?@"danger":
        [guardLevel isEqual:@"warn"]||autoUpdate==TIOAutoUpdateReadingMissing?@"warn":@"ok";
    NSMutableDictionary *m=[@{
        @"guardActive":@(guard),@"stockTrafficSeen":@(stockTrafficSeen),@"guardLevel":guardLevel,
        @"guardKey":guardKey,@"guardDetail":[guardKey stringByAppendingString:@".detail"],
        @"autoUpdate":TIOAutoUpdateReadingName(autoUpdate),@"autoLevel":autoLevel,
        @"autoKey":[@"fwexport.auto." stringByAppendingString:TIOAutoUpdateReadingName(autoUpdate)],
        @"autoDetail":[[@"fwexport.auto." stringByAppendingString:TIOAutoUpdateReadingName(autoUpdate)] stringByAppendingString:@".detail"],
        @"safe":@([guardLevel isEqual:@"ok"]&&autoUpdate==TIOAutoUpdateReadingOff),@"level":level,
    } mutableCopy];
    // The guard banner outranks the Auto Update one: without the guard nothing stops a transfer.
    // Auto Update ON is next (danger); a guard with no stock traffic seen yet outranks a missing reading.
    if(!guard)m[@"bannerKey"]=@"fwexport.banner.unguarded";
    else if(autoUpdate==TIOAutoUpdateReadingOn)m[@"bannerKey"]=@"fwexport.banner.autoOn";
    else if(!stockTrafficSeen)m[@"bannerKey"]=@"fwexport.banner.noTraffic";
    else if(autoUpdate==TIOAutoUpdateReadingMissing)m[@"bannerKey"]=@"fwexport.banner.autoMissing";
    return m;
}
