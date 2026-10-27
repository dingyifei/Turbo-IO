#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TIOHubSection) {
    TIOHubSectionGlasses = 0,
    TIOHubSectionAssistant = 1,
    TIOHubSectionMedia = 2,
    TIOHubSectionDeveloper = 3,
};

// A row has key, localized title, SF Symbol icon, section, parent, and build code.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubCatalog(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIOHubSections(NSString *parent);
FOUNDATION_EXPORT NSString *TIOHubSectionTitle(TIOHubSection section);
