#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
/* Geometry and icon outlines for the phone-side picture of the glasses menu (docs/design-system boards PhoneMenuLayout,
 * LensMenuCarousel and LensMenuGrid2). Pure Foundation and Core Graphics, so a host test can check every number.
 * Lens pixels are glasses pixels: the picture is 540 x 220 and the caller scales it. */

/* The three menu layouts, numbered like the glasses' layout record (menu_config.h): 1 carousel, 2 and 3 grid rows. */
typedef NS_ENUM(NSUInteger, TIOMenuLensLayout) {TIOMenuLensCarousel=1,TIOMenuLensRows2=2,TIOMenuLensRows3=3};
/* Lens intensity of an icon: lens-full, lens-mid or lens-track. */
typedef NS_ENUM(uint8_t, TIOMenuLensInk) {TIOMenuLensInkFull=0,TIOMenuLensInkMid=1,TIOMenuLensInkTrack=2};
typedef struct {uint8_t tile;CGFloat cx,cy,size;TIOMenuLensInk ink;} TIOMenuLensSlot;
enum {TIOMenuLensIconCount=13,TIOMenuLensSlotMax=13};
/* The 13 menu icons by tile id (the same order as the glasses' icon table), drawn on a 48 x 48 grid with a 2.6 stroke,
 * round caps and joins, no fill. The outline of tile `tile`, or NULL when it is out of range. The path is shared and immortal. */
CGPathRef TIOMenuLensIconPath(NSUInteger tile);
/* The slug of an icon, as in docs/design-system icons-proposed ("recorder", "do-not-disturb", ...). */
NSString *TIOMenuLensIconName(NSUInteger tile);
FOUNDATION_EXPORT const CGFloat TIOMenuLensIconGrid,TIOMenuLensIconStroke;
/* Slots to draw for the focused entry `focus` (an index into `visible`, the tile ids in menu order). The focused slot is
 * last, so it paints on top. Returns the slot count. */
NSUInteger TIOMenuLensSlots(TIOMenuLensLayout layout,const uint8_t *visible,NSUInteger count,NSUInteger focus,TIOMenuLensSlot out[TIOMenuLensSlotMax]);
/* Text baselines in lens pixels (PhoneMenuLayout.dc.html): the focused name (24 px), the carousel status line (16 px)
 * and the clock (16 px). */
CGFloat TIOMenuLensNameBaseline(TIOMenuLensLayout layout);
CGFloat TIOMenuLensStatusBaseline(void);
CGFloat TIOMenuLensClockBaseline(void);
/* The outline for an SVG path string in the commands the icons use (M L H V C S Q T A Z, absolute and relative);
 * NULL when the string is malformed. Returned retained; the caller releases it. */
CGPathRef TIOMenuLensCreatePath(NSString *svg) CF_RETURNS_RETAINED;
