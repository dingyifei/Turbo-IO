#import <AppKit/AppKit.h>
#import "ResearchCatalog.h"
#import "TIOLanguage.h"
#include <assert.h>

static NSDictionary *RowForKey(NSArray<NSDictionary *> *catalog, NSString *key) {
    for (NSDictionary *row in catalog) if ([row[@"key"] isEqualToString:key]) return row;
    return nil;
}

static void CheckSectionOrder(NSArray<NSDictionary *> *sections, NSString *parent) {
    NSInteger previous = -1;
    for (NSDictionary *group in sections) {
        NSInteger section = [group[@"section"] integerValue];
        assert(section >= TIOHubSectionGlasses && section <= TIOHubSectionDeveloper);
        assert(section > previous);
        assert([group[@"title"] isEqualToString:TIOHubSectionTitle(section)]);
        assert([group[@"rows"] count] > 0);
        for (NSDictionary *row in group[@"rows"]) {
            assert([row[@"section"] integerValue] == section);
            assert([row[@"parent"] isEqualToString:parent]);
        }
        previous = section;
    }
}

static void CheckTitles(NSArray<NSDictionary *> *catalog, NSUInteger maxLength) {
    NSRegularExpression *code = [NSRegularExpression regularExpressionWithPattern:@"[A-Z]{2,}[0-9]" options:0 error:NULL];
    for (NSDictionary *row in catalog) {
        NSString *title = row[@"title"];
        assert(title.length > 0 && title.length <= maxLength);
        assert([title rangeOfString:@"·"].location == NSNotFound);
        assert([code numberOfMatchesInString:title options:0 range:NSMakeRange(0,title.length)] == 0);
        NSString *stringKey = [@"hub.row." stringByAppendingString:row[@"key"]];
        assert([title isEqualToString:TIOText(stringKey)]);
        assert(![title isEqualToString:stringKey]);
    }
}

int main(void) {
    @autoreleasepool {
        TIOSetUILanguageOverride(@"en");
        NSArray<NSDictionary *> *catalog = TIOHubCatalog();
        NSMutableSet<NSString *> *keys = [NSMutableSet new];
        NSMutableDictionary<NSString *, NSDictionary *> *rootRows = [NSMutableDictionary new];
        for (NSDictionary *row in catalog) {
            NSString *key = row[@"key"];
            NSString *parent = row[@"parent"];
            assert(key.length && [row[@"icon"] length] && parent && row[@"code"]);
            assert(![keys containsObject:key]);
            [keys addObject:key];
            if (!parent.length) rootRows[key] = row;
            assert([NSImage imageWithSystemSymbolName:row[@"icon"] accessibilityDescription:nil] != nil);
        }

        NSArray<NSDictionary *> *root = TIOHubSections(@"");
        CheckSectionOrder(root, @"");
        assert([root.lastObject[@"section"] integerValue] == TIOHubSectionDeveloper);
        NSMutableDictionary<NSString *, NSNumber *> *visits = [NSMutableDictionary new];
        NSMutableSet<NSString *> *parents = [NSMutableSet setWithObject:@""];
        for (NSDictionary *row in catalog) if ([row[@"parent"] length]) {
            NSDictionary *ancestor = rootRows[row[@"parent"]];
            assert(ancestor);
            assert([ancestor[@"section"] isEqual:row[@"section"]]);
            [parents addObject:row[@"parent"]];
        }
        for (NSString *parent in parents) {
            NSArray<NSDictionary *> *sections = TIOHubSections(parent);
            CheckSectionOrder(sections, parent);
            for (NSDictionary *group in sections) for (NSDictionary *row in group[@"rows"]) {
                NSString *key = row[@"key"];
                visits[key] = @([visits[key] integerValue] + 1);
            }
        }
        for (NSString *key in keys) assert([visits[key] integerValue] == 1);
        assert(visits.count == keys.count);

        NSDictionary *ota = RowForKey(catalog, @"experimentalOTA");
        NSDictionary *language = RowForKey(catalog, @"language");
        NSDictionary *languageStatus = RowForKey(catalog, @"languageStatus");
        assert([ota[@"section"] integerValue] == TIOHubSectionGlasses);
        assert([language[@"section"] integerValue] == TIOHubSectionGlasses && [language[@"parent"] isEqualToString:@""]);
        assert([languageStatus[@"section"] integerValue] == TIOHubSectionDeveloper && [languageStatus[@"parent"] isEqualToString:@""]);
        NSRegularExpression *firmware = [NSRegularExpression regularExpressionWithPattern:@"^TMG[0-9]+$" options:0 error:NULL];
        NSString *otaCode = ota[@"code"];
        assert([firmware numberOfMatchesInString:otaCode options:0 range:NSMakeRange(0,otaCode.length)] == 1);
        assert(TIOHubSections(@"assistantMore").count);
        assert(TIOHubSections(@"lifelog").count);
        assert(TIOHubSections(@"unknown").count == 0);

        for (NSString *key in @[@"language",@"languageStatus",@"aboutMe",@"ttsTest",@"music",@"experimentalOTA",@"lifelogText",@"lifelogAudio",@"capture",@"archive"]) assert([keys containsObject:key]);
        for (NSString *key in @[@"uiLanguage",@"searchKey",@"ttsEngine",@"ttsKey",@"weread",@"didi",@"netease",@"contextEnglish",@"dots",@"enhancedLifelog",@"notificationArchive",@"news",@"newsTeleprompter"]) assert(![keys containsObject:key]);

#if TIO_APPLE_AI
        assert([keys containsObject:@"appleAI"]);
        NSDictionary *apple=RowForKey(catalog,@"appleAI");assert([apple[@"section"] integerValue]==TIOHubSectionDeveloper&&![apple[@"parent"] length]&&[apple[@"icon"] isEqual:@"sparkles"]);
#else
        assert(![keys containsObject:@"appleAI"]);
#endif
        CheckTitles(catalog, 28);
        NSString *englishLanguageTitle = language[@"title"];
        TIOSetUILanguageOverride(@"zh");
        NSArray<NSDictionary *> *chineseCatalog = TIOHubCatalog();
        CheckTitles(chineseCatalog, 14);
        assert(![RowForKey(chineseCatalog, @"language")[@"title"] isEqualToString:englishLanguageTitle]);
        assert([TIOHubSections(@"").firstObject[@"title"] isEqualToString:TIOText(@"hub.section.glasses")]);
        TIOSetUILanguageOverride(@"auto");
        NSLog(@"PASS: hub catalog keys, routes, order, icons, titles and language switching");
    }
    return 0;
}
