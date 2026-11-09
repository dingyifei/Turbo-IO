#import "ResearchCatalog.h"
#import "TIOLanguage.h"
#import "FirmwarePins.h"

typedef struct {
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *icon;
    TIOHubSection section;
    __unsafe_unretained NSString *parent;
    __unsafe_unretained NSString *code;
} TIOHubRowDefinition;

// Keep this order aligned with the hub: Glasses, Assistant, Media, Developer.
// The only dynamic code is the OTA build name, resolved below.
static const TIOHubRowDefinition Rows[] = {
    {@"experimentalOTA", @"arrow.down.circle", TIOHubSectionGlasses, @"", @""},
    {@"firmwareExport", @"square.and.arrow.up.on.square", TIOHubSectionGlasses, @"", @""},
#if TIO_MAPKIT_ENABLED
    {@"navigation", @"location.north.line", TIOHubSectionGlasses, @"", @"TNV1"},
#endif
    {@"camera", @"camera", TIOHubSectionGlasses, @"", @"TCM1"},
    {@"focus", @"timer", TIOHubSectionGlasses, @"", @""},
    {@"menuLayout", @"square.grid.3x3", TIOHubSectionGlasses, @"", @""},
    {@"brightness", @"sun.max", TIOHubSectionGlasses, @"", @""},
    {@"watchRemote", @"applewatch", TIOHubSectionGlasses, @"", @"TGR1"},
    {@"developerApps", @"square.stack.3d.up", TIOHubSectionGlasses, @"", @"TAP1"},
    {@"dashboardEditor", @"rectangle.3.group", TIOHubSectionGlasses, @"", @"TCE1"},
    {@"language", @"textformat", TIOHubSectionGlasses, @"", @""},

    {@"mode", @"sparkles", TIOHubSectionAssistant, @"", @""},
    {@"api", @"cube", TIOHubSectionAssistant, @"", @""},
    {@"tts", @"speaker.wave.2", TIOHubSectionAssistant, @"", @""},
    {@"ttsSpeed", @"speedometer", TIOHubSectionAssistant, @"", @""},
    {@"search", @"globe", TIOHubSectionAssistant, @"", @""},
    {@"knowledge", @"books.vertical", TIOHubSectionAssistant, @"", @""},
    {@"assistantMore", @"slider.horizontal.3", TIOHubSectionAssistant, @"", @""},
    {@"agent", @"cpu", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"thinking", @"bolt", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"exit", @"waveform", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"aboutMe", @"person.text.rectangle", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"tools", @"wrench.and.screwdriver", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"prompt", @"text.bubble", TIOHubSectionAssistant, @"assistantMore", @""},
    {@"history", @"clock.arrow.circlepath", TIOHubSectionAssistant, @"assistantMore", @""},

    {@"music", @"music.note", TIOHubSectionMedia, @"", @"TMU1"},
    {@"localTranslation", @"character.bubble", TIOHubSectionMedia, @"", @""},
    {@"recordings", @"waveform.circle", TIOHubSectionMedia, @"", @""},
    {@"summary", @"text.badge.star", TIOHubSectionMedia, @"", @""},
    {@"lifelog", @"doc.text", TIOHubSectionMedia, @"", @""},
    {@"lifelogText", @"doc.text", TIOHubSectionMedia, @"lifelog", @""},
    {@"lifelogAudio", @"waveform.circle", TIOHubSectionMedia, @"lifelog", @""},
    {@"capture", @"square.and.arrow.down", TIOHubSectionMedia, @"lifelog", @""},
    {@"archive", @"square.and.arrow.up", TIOHubSectionMedia, @"lifelog", @""},

#if TIO_APPLE_AI
    {@"appleAI", @"sparkles", TIOHubSectionDeveloper, @"", @""},
#endif
    {@"status", @"checkmark.shield", TIOHubSectionDeveloper, @"", @""},
    {@"diagnosticsRuntime", @"gauge.with.dots.needle.67percent", TIOHubSectionDeveloper, @"", @"TDG1"},
    {@"glassesLog", @"doc.text.magnifyingglass", TIOHubSectionDeveloper, @"", @""},
#if TIO_WIRE_LOG
    {@"wireLog", @"record.circle", TIOHubSectionDeveloper, @"", @""},
#endif
    {@"languageStatus", @"character.bubble", TIOHubSectionDeveloper, @"", @""},
#if TIO_IMAGE_RX_LAB && TIO_DISPLAY_PHONE
    {@"displayPhone", @"rectangle.connected.to.line.below", TIOHubSectionDeveloper, @"", @"PHONE 06"},
#endif
#if TIO_IMAGE_RX_LAB
    {@"imageRXLab", @"photo", TIOHubSectionDeveloper, @"", @"N8W FIX 01"},
    {@"clenchLab", @"waveform.and.magnifyingglass", TIOHubSectionDeveloper, @"", @"CLENCH A1"},
#endif
    {@"dashboardCard", @"chart.bar.xaxis", TIOHubSectionDeveloper, @"", @"TDC1"},
    {@"testBench", @"testtube.2", TIOHubSectionDeveloper, @"", @"TMU1 TFP1 TDC1"},
    {@"a2ui", @"rectangle.on.rectangle", TIOHubSectionDeveloper, @"", @"A2UI 7392/8642"},
    {@"apiTest", @"bubble.left.and.bubble.right", TIOHubSectionDeveloper, @"", @""},
    {@"searchTest", @"magnifyingglass", TIOHubSectionDeveloper, @"", @""},
    {@"todoTest", @"checklist", TIOHubSectionDeveloper, @"", @""},
    {@"ttsTest", @"play.circle", TIOHubSectionDeveloper, @"", @""},
    {@"subtitleHUD", @"text.bubble", TIOHubSectionDeveloper, @"", @"v1.1"},
};

static NSString *FirmwareCode(void) {
    id value = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTABuild"];
    if (![value isKindOfClass:NSString.class]) return TIO_FW_NAME;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^TMG[0-9]+$" options:0 error:NULL];
    NSString *code = value;
    return [pattern firstMatchInString:code options:0 range:NSMakeRange(0, code.length)] ? code : TIO_FW_NAME;
}

// The firmware export row exists only on the 1.0.11 hosts. On the download-only
// host it and the language row are the whole hub, plus the wire log row when the
// build has it (TIO_WIRE_LOG=1): the recorder is passive and only reads the channel.
// The full 1.0.11 host ("ios1011") gets every row, with the export row moved under
// Developer. Everything else is the full 1.0.7 hub without the export row.
static BOOL RowOnHost(NSString *key, BOOL downloadOnly, BOOL full1011) {
    BOOL exportRow = [key isEqualToString:@"firmwareExport"];
    if (full1011) return YES;
    if (!downloadOnly) return !exportRow;
    if (exportRow || [key isEqualToString:@"language"]) return YES;
#if TIO_WIRE_LOG
    if ([key isEqualToString:@"wireLog"]) return YES;
#endif
    return NO;
}

NSArray<NSDictionary *> *TIOHubCatalog(void) {return TIOHubCatalogForProfile(nil);}

NSArray<NSDictionary *> *TIOHubCatalogForProfile(NSString *profile) {
    BOOL downloadOnly = [profile isEqualToString:@"ios1011-download"];
    BOOL full1011 = [profile isEqualToString:@"ios1011"];
    NSMutableArray<NSDictionary *> *catalog = [NSMutableArray arrayWithCapacity:sizeof(Rows)/sizeof(Rows[0])];
    for (NSUInteger index = 0; index < sizeof(Rows)/sizeof(Rows[0]); index++) {
        const TIOHubRowDefinition *row = &Rows[index];
        if (!RowOnHost(row->key, downloadOnly, full1011)) continue;
        TIOHubSection section = full1011 && [row->key isEqualToString:@"firmwareExport"] ? TIOHubSectionDeveloper : row->section;
        NSString *code = [row->key isEqualToString:@"experimentalOTA"] ? FirmwareCode() : row->code;
        [catalog addObject:@{@"key":row->key,
#if TIO_APPLE_AI
                             @"title":TIOText([row->key isEqual:@"localTranslation"]?@"apple.captions.title":[@"hub.row." stringByAppendingString:row->key]),
#else
                             @"title":TIOText([@"hub.row." stringByAppendingString:row->key]),
#endif
                             @"icon":row->icon,
                             @"section":@(section),
                             @"parent":row->parent,
                             @"code":code}];
    }
    return catalog;
}

NSString *TIOHubSectionTitle(TIOHubSection section) {
    switch (section) {
        case TIOHubSectionGlasses: return TIOText(@"hub.section.glasses");
        case TIOHubSectionAssistant: return TIOText(@"hub.section.assistant");
        case TIOHubSectionMedia: return TIOText(@"hub.section.media");
        case TIOHubSectionDeveloper: return TIOText(@"hub.section.developer");
    }
    return @"";
}

NSArray<NSDictionary *> *TIOHubSections(NSString *parent) {return TIOHubSectionsForProfile(parent, nil);}

NSArray<NSDictionary *> *TIOHubSectionsForProfile(NSString *parent, NSString *profile) {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray new];
    NSString *target = parent ?: @"";
    NSArray<NSDictionary *> *catalog = TIOHubCatalogForProfile(profile);
    for (TIOHubSection section = TIOHubSectionGlasses; section <= TIOHubSectionDeveloper; section++) {
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray new];
        for (NSDictionary *row in catalog) {
            if ([row[@"section"] integerValue] == section && [row[@"parent"] isEqualToString:target]) [rows addObject:row];
        }
        if (rows.count) [sections addObject:@{@"section":@(section), @"title":TIOHubSectionTitle(section), @"rows":rows}];
    }
    return sections;
}
