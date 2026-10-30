#import <UIKit/UIKit.h>
UIViewController *TIOMenuLayoutController(void);

UIViewController *TIOTileEditorController(void);
#if TIO_UI_PREVIEW
/* fixture: @"tmg8" (glasses report the TMG8 caps bit, carousel stored) or @"tmg7" (older glasses, three rows). */
UIViewController *TIOMenuLayoutPreviewController(NSString *fixture);
UIViewController *TIOTileEditorPreviewController(void);
#endif
