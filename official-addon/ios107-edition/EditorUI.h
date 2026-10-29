#import <UIKit/UIKit.h>
UIViewController *TCEEditorController(void);
#if TIO_UI_PREVIEW
/* Preview-only pages ("draft", "ai", "crop") for the screenshot gate. */
UIViewController *TCEPreviewController(NSString *kind);
#endif
