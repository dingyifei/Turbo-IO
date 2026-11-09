#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TIOHubSection) {
    TIOHubSectionGlasses = 0,
    TIOHubSectionAssistant = 1,
    TIOHubSectionMedia = 2,
    TIOHubSectionDeveloper = 3,
};

// A row has key, localized title, SF Symbol icon, section, parent, and build code.
// Rows for the full 1.0.7 host (and the UI preview).
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubCatalog(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubSections(NSString *parent);
// Rows for a host profile (TIOHostProfile()). The download-only profile
// "ios1011-download" gets only the stock firmware export and the language row:
// no TMG flash wizard and no feature panels. The full 1.0.11 profile "ios1011"
// gets TIOHubCatalog() plus the firmware export row under Developer. Any other
// value gets TIOHubCatalog().
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubCatalogForProfile(NSString *profile);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubSectionsForProfile(NSString *parent, NSString *profile);
FOUNDATION_EXPORT NSString *TIOHubSectionTitle(TIOHubSection section);
