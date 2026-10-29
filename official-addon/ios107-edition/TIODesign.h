#import <UIKit/UIKit.h>
#include "TIODesign.inc"
NS_ASSUME_NONNULL_BEGIN

/* Turbo IO design system for the phone (docs/design-system). Every color, type
 * style, spacing, radius and size below comes from TIODesign.inc, which the
 * unit test compares with tokens.json. Screens use these tokens, never literal
 * colors, system font sizes or numeric padding. */

#pragma mark Colors

#define TIO_DESIGN_COLOR_ENUM(Id,name,light,dark) TIODesignColor##Id,
typedef NS_ENUM(NSInteger, TIODesignColorToken) {
 TIO_DESIGN_COLORS(TIO_DESIGN_COLOR_ENUM)
 TIODesignColorTokenCount
};
#undef TIO_DESIGN_COLOR_ENUM

/* Phone colors follow the system appearance. The lens-* colors are fixed. */
FOUNDATION_EXPORT UIColor *TIODesignColor(TIODesignColorToken token);
FOUNDATION_EXPORT NSString *TIODesignColorName(TIODesignColorToken token);
FOUNDATION_EXPORT UIColor *_Nullable TIODesignColorNamed(NSString *name);
/* Exact 0xRRGGBB for a token in light or dark (the lens ramp is identical). */
FOUNDATION_EXPORT uint32_t TIODesignColorRGB(TIODesignColorToken token, BOOL dark);

#pragma mark Type

#define TIO_DESIGN_TYPE_ENUM(Id,name,size,line,weight,tracking) TIODesignTextStyle##Id,
typedef NS_ENUM(NSInteger, TIODesignTextStyle) {
 TIO_DESIGN_TYPES(TIO_DESIGN_TYPE_ENUM)
 TIODesignTextStyleCount
};
#undef TIO_DESIGN_TYPE_ENUM

/* Text styles scale through UIFontMetrics; set adjustsFontForContentSizeCategory. */
FOUNDATION_EXPORT UIFont *TIODesignFont(TIODesignTextStyle style);
FOUNDATION_EXPORT UIFont *TIODesignFontForTraits(TIODesignTextStyle style, UITraitCollection *_Nullable traits);
/* A text style with a different weight, for example a semibold footnote. */
FOUNDATION_EXPORT UIFont *TIODesignFontWeight(TIODesignTextStyle style, UIFontWeight weight);
/* Monospaced digits for sizes, hashes and timers (caption by default). */
FOUNDATION_EXPORT UIFont *TIODesignMonospacedDigitFont(TIODesignTextStyle style);
/* Compiled token values: point size at Large, line height, weight, tracking. */
FOUNDATION_EXPORT NSString *TIODesignTextStyleName(TIODesignTextStyle style);
FOUNDATION_EXPORT CGFloat TIODesignTextStyleSize(TIODesignTextStyle style);
FOUNDATION_EXPORT CGFloat TIODesignTextStyleLineHeight(TIODesignTextStyle style);
FOUNDATION_EXPORT UIFontWeight TIODesignTextStyleWeight(TIODesignTextStyle style);
FOUNDATION_EXPORT NSInteger TIODesignTextStyleCSSWeight(TIODesignTextStyle style);
FOUNDATION_EXPORT CGFloat TIODesignTextStyleTracking(TIODesignTextStyle style);
/* Only for forwarding shims over pre-design-system call sites. */
FOUNDATION_EXPORT UIFont *TIODesignLegacyFont(CGFloat size, UIFontWeight weight);

#pragma mark Numbers

#define TIO_DESIGN_CONST_1(Id,name,value) static const CGFloat TIO##Id = (value);
#define TIO_DESIGN_CONST_2(name,A,a,B,b) static const CGFloat TIO##A = (a); static const CGFloat TIO##B = (b);
TIO_DESIGN_NUMBERS_1(TIO_DESIGN_CONST_1)
TIO_DESIGN_NUMBERS_2(TIO_DESIGN_CONST_2)
#undef TIO_DESIGN_CONST_1
#undef TIO_DESIGN_CONST_2
/* Look a numeric token up by its tokens.json name. second is NO for singles. */
FOUNDATION_EXPORT BOOL TIODesignNumber(NSString *name, CGFloat *_Nullable first, CGFloat *_Nullable second);
FOUNDATION_EXPORT NSArray<NSString *> *TIODesignNumberNames(void);

#pragma mark Motion

/* Reduce Motion is respected: the animation is applied at once and the
 * completion still runs. Prefer cross-fades over slides when it is on. */
FOUNDATION_EXPORT BOOL TIODesignReduceMotion(void);
FOUNDATION_EXPORT void TIODesignAnimate(NSTimeInterval duration, void (^animations)(void), void (^_Nullable completion)(BOOL finished));

#pragma mark Buttons

typedef NS_ENUM(NSInteger, TIODesignButtonRole) {
 TIODesignButtonPrimary,        /* accent-fill, on-accent text */
 TIODesignButtonSecondary,      /* accent-soft, accent text */
 TIODesignButtonDestructive,    /* plain, status-danger text */
 TIODesignButtonDestructiveFilled /* status-danger fill, only for what cannot be undone */
};
/* Full-width capsule: headline title, at least button-height and hit-min tall. */
FOUNDATION_EXPORT void TIODesignStyleButton(UIButton *button, TIODesignButtonRole role);

#pragma mark Lists

FOUNDATION_EXPORT void TIODesignStyleRow(UITableViewCell *cell);
/* Section header and footer text: footnote in label-secondary. */
FOUNDATION_EXPORT void TIODesignStyleHeaderLabel(UILabel *label);
/* Inset-grouped table styling without any global UIKit change. */
FOUNDATION_EXPORT void TIODesignStyleTable(UITableViewController *controller);
/* Maps stock system surfaces in a view subtree onto bg, bg-raised and accent. */
FOUNDATION_EXPORT void TIODesignStyleSurface(UIView *view);
/* 30pt hub icon tile, one image per section (0 Glasses, 1 Assistant, 2 Media,
 * 3 Developer) with light and dark variants. Decorative: hide it from VoiceOver. */
FOUNDATION_EXPORT UIImage *TIODesignHubIcon(NSString *symbol, NSInteger section);

#pragma mark Status and empty state

typedef NS_ENUM(NSInteger, TIODesignStatus) {
 TIODesignStatusOk, TIODesignStatusWarn, TIODesignStatusDanger, TIODesignStatusNeutral
};
/* Symbol plus word, never color alone. VoiceOver reads only the word. */
FOUNDATION_EXPORT UIView *TIODesignStatusPill(TIODesignStatus status, NSString *word);
/* Centered message: title3 name, subheadline fix and at most one accent action. */
FOUNDATION_EXPORT UIView *TIODesignEmptyState(NSString *symbol, NSString *title, NSString *detail,
                                              NSString *_Nullable actionTitle, void (^_Nullable action)(void));

#pragma mark Lens preview

/* The phone-side picture of a glasses page is always lens-black with lens-*
 * greens, whatever the phone's appearance, and is one accessibility element. */
FOUNDATION_EXPORT void TIODesignStyleLensPreview(UIView *surface, NSString *summary);
/* bg-raised card (radius-md) holding the preview surface at 540:180, or 540:220
 * for a menu. content is placed inside the surface, edge to edge. */
FOUNDATION_EXPORT UIView *TIODesignLensPreviewCard(UIView *_Nullable content, NSString *summary, BOOL menu);

NS_ASSUME_NONNULL_END
