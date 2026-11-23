#import "ExperimentalOTA.h"
#import "FirmwarePins.h"
#import "TIOLanguage.h"
#include <assert.h>
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);NSURL *source=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];NSError *error=nil;
    // The release's packages: the TMG build first (the default), then the stock package of its base.
    assert(TIOOTAPackageCount()==2);NSDictionary *tmg=TIOOTAPackageAt(0),*stock=TIOOTAPackageAt(1);assert(tmg&&stock&&!TIOOTAPackageAt(2));
    assert([tmg[@"kind"] isEqual:@"TMG"]&&[stock[@"kind"] isEqual:@"STOCK"]&&[stock[@"name"] isEqual:[@"STOCK-" stringByAppendingString:TIO_FW_BASE]]);
    NSString *stockName=[NSString stringWithFormat:TIOText(@"ota.package.stockName"),TIO_FW_BASE];
    assert([TIOOTAPackageDisplayName(stock) isEqual:stockName]&&[TIOOTAPackageDisplayName(tmg) isEqual:tmg[@"name"]]);
    assert([tmg[@"resource"] isEqual:@"TurboWeReadCandidate.zip"]&&[stock[@"resource"] isEqual:@"TurboStockFirmware.zip"]);
    assert(!TIOCheckExperimentalOTA([NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]],nil,&error));
    // argv[2] is the stock ZIP of the base: refused as the TMG package, accepted as the stock package only.
    NSData *stockData=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];assert(stockData);
    assert(!TIOCheckExperimentalOTA(stockData,tmg,nil));
    error=nil;NSDictionary *stockOK=TIOCheckExperimentalOTA(stockData,stock,&error);assert(stockOK&&!error);
    assert([stockOK[@"candidate"] isEqual:stockName]&&[stockOK[@"changedPayloads"] isEqual:@[]]&&[stockOK[@"package"] isEqual:stock[@"name"]]);
    NSData *data=[NSData dataWithContentsOfURL:source];assert(data);
    assert(!TIOCheckExperimentalOTA(data,stock,&error));
    error=nil;NSDictionary *ok=TIOCheckExperimentalOTA(data,tmg,&error);assert(ok&&!error);
    // The summary is the pins' difference from the stock package (C25: TMG16 changes the AP and the Bluetooth core).
    {NSMutableArray *diff=[NSMutableArray array];NSDictionary *tp=tmg[@"memberPins"],*sp=stock[@"memberPins"];
     for(NSString *n in [tp.allKeys sortedArrayUsingSelector:@selector(compare:)])if(![n isEqual:@"OtaFileInfo.json"]&&![tp[n] isEqual:sp[n]])[diff addObject:n];
     assert([diff containsObject:@"nuttx_ap.bin"]&&[ok[@"changedPayloads"] isEqual:diff]&&[TIOOTAChangedPayloads(tmg) isEqual:diff]&&[TIOOTAChangedPayloads(stock) isEqual:@[]]);
     assert([ok[@"unchangedPayloadCount"] unsignedIntegerValue]==tp.count-1-diff.count&&[stockOK[@"unchangedPayloadCount"] unsignedIntegerValue]==sp.count-1);
     if([tmg[@"name"] isEqual:@"TMG16"])assert([diff isEqual:(@[@"nuttx_ap.bin",@"nuttx_bth.bin"])]&&[ok[@"unchangedPayloadCount"] unsignedIntegerValue]==14);}assert([ok[@"integrityPassed"] boolValue]);assert(![ok[@"sent"] boolValue]);assert(![ok[@"officialDispatchConnected"] boolValue]);NSString *identity=[@"Turbo Menu " stringByAppendingString:tmg[@"name"]];assert([ok[@"candidate"] isEqual:identity]);
    assert(!TIOCheckExperimentalOTA([NSData data],tmg,&error));assert([error.localizedDescription containsString:tmg[@"name"]]);
    assert(!TIOCheckExperimentalOTA([NSData data],stock,&error));assert([error.localizedDescription containsString:TIOOTAPackageDisplayName(stock)]);
    NSMutableData *bad=[data mutableCopy];((uint8_t *)bad.mutableBytes)[100]^=1;assert(!TIOCheckExperimentalOTA(bad,tmg,&error));
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tio-ota-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSFileManager *fm=NSFileManager.defaultManager;assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    NSURL *badFile=[root URLByAppendingPathComponent:@"invalid.zip"],*store=[root URLByAppendingPathComponent:@"store" isDirectory:YES];
    assert([bad writeToURL:badFile atomically:NO]);assert(!TIOImportExperimentalOTA(badFile,store,tmg,&error));assert(![fm fileExistsAtPath:store.path]);
    error=nil;assert(TIOImportExperimentalOTA(source,store,tmg,&error));assert(!error);
    NSURL *saved=[store URLByAppendingPathComponent:TIOOTAPackageArchiveName(tmg)];assert([TIOOTAPackageArchiveName(tmg) isEqual:[tmg[@"zipSHA256"] stringByAppendingString:@".zip"]]);assert([[NSData dataWithContentsOfURL:saved] isEqual:data]);
    assert(TIOReadExperimentalOTA(saved,tmg,&error));assert(!TIOReadExperimentalOTA(saved,stock,nil));
    NSDate *mtime=[fm attributesOfItemAtPath:saved.path error:nil][NSFileModificationDate];
    assert(TIOImportExperimentalOTA(source,store,tmg,&error));assert([[fm attributesOfItemAtPath:saved.path error:nil][NSFileModificationDate] isEqual:mtime]);
    // The stock package goes into its own file beside the TMG one; the TMG ZIP is never accepted as the stock package.
    NSURL *stockSource=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    assert(!TIOImportExperimentalOTA(source,store,stock,nil));error=nil;assert(TIOImportExperimentalOTA(stockSource,store,stock,&error)&&!error);
    NSURL *stockSaved=[store URLByAppendingPathComponent:TIOOTAPackageArchiveName(stock)];assert([[NSData dataWithContentsOfURL:stockSaved] isEqual:stockData]&&[[NSData dataWithContentsOfURL:saved] isEqual:data]);
    assert([bad writeToURL:saved atomically:NO]);assert(!TIOImportExperimentalOTA(source,store,tmg,&error));assert([[NSData dataWithContentsOfURL:saved] isEqual:bad]);
    // Deletes only this test's UUID-named temporary directory.
    assert([fm removeItemAtURL:root error:nil]);
    NSLog(@"PASS: two packages (TMG default, stock second), each ZIP only under its own package, pinned candidate, invalid rejection, isolated copy, idempotence, corrupt existing copy preserved; no device IO");
}return 0;}
