#import <UIKit/UIKit.h>
#import "MenuLayout.h"
UIViewController *TIOMenuLayoutController(void);
/* The one layout link of the app (replies are routed to it by TIOMenuLayoutConsume). The knob step setting writes D through it. */
TIOMenuLayoutLink *TIOMenuLayoutSharedLink(void);

UIViewController *TIOTileEditorController(void);
#if TIO_UI_PREVIEW
/* fixture: @"tmg8" (glasses report the TMG8 caps bit, carousel stored) or @"tmg7" (older glasses, three rows). */
UIViewController *TIOMenuLayoutPreviewController(NSString *fixture);
UIViewController *TIOTileEditorPreviewController(void);
#endif
