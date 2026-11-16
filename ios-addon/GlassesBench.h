#import <Foundation/Foundation.h>
#include "card.h"
#include "GlassesBenchLyrics.h"
NS_ASSUME_NONNULL_BEGIN

/* Fixture builders for the Glasses test bench (Developer, key testBench). Foundation only, so the host tests run them.
 * Everything they build is demo data: nothing is read from an account, a Mac or a route. */

#pragma mark Lyrics

/* The fixtures of GlassesBenchLyrics.h, in list order. A fixture is @{id, lang (en or zh), current, next, step, lines, ellipsis, nextEllipsis}. */
FOUNDATION_EXPORT NSArray<NSDictionary *> *TGBLyricFixtures(void);
/* The text cut to at most maxBytes of UTF-8 at a character boundary, as MusicBridge clips a lyric line (control characters become spaces). */
FOUNDATION_EXPORT NSString *TGBClipText(NSString *_Nullable text, NSUInteger maxBytes);
/* The rows the music bridge takes: @[@{ms, text}] with the current line at 0 and the next line at TGB_LYRIC_NEXT_MS, each at most TGB_LYRIC_CAP bytes. */
FOUNDATION_EXPORT NSArray<NSDictionary *> *TGBLyricRows(NSDictionary *fixture);
/* Three short lines for the fake now-playing song (60 s apart), in the phone's language. */
FOUNDATION_EXPORT NSArray<NSDictionary *> *TGBDemoSongRows(void);

#pragma mark Dashboard card

/* The ten TDC1 values, in wire order. */
typedef NS_ENUM(NSUInteger, TGBCardField) {
 TGBCardFieldWeekly, TGBCardFieldClaude5h, TGBCardFieldClaudeWeek, TGBCardFieldRamFree, TGBCardFieldRamTotal,
 TGBCardFieldDiskFree, TGBCardFieldDiskTotal, TGBCardFieldIcon1, TGBCardFieldIcon2, TGBCardFieldIcon3, TGBCardFieldCount
};
#define TGB_CARD_BYTES_MAX 120u   /* dc_parse: the whole "TDC1;..." text */
FOUNDATION_EXPORT NSArray<NSString *> *TGBCardPresetIDs(void);   /* typical, three100, empty */
FOUNDATION_EXPORT BOOL TGBCardPreset(NSString *preset, DCValues *out);
/* "TDC1;a;b;...;j" for the values, or nil when dc_parse refuses it (so a card of at most TGB_CARD_BYTES_MAX bytes, every value in range). */
FOUNDATION_EXPORT NSString *_Nullable TGBCardText(const DCValues *values);
FOUNDATION_EXPORT unsigned TGBCardGet(const DCValues *values, TGBCardField field);
/* Moves a value one step up (direction > 0) or down and keeps the rules: percent 0...100, RAM and SSD free never above their total, a total never below its free. NO at the end of the range. */
FOUNDATION_EXPORT BOOL TGBCardStep(DCValues *values, TGBCardField field, int direction);
FOUNDATION_EXPORT NSString *TGBCardFieldID(TGBCardField field);
FOUNDATION_EXPORT NSString *TGBCardFieldTitleKey(TGBCardField field);
/* The value as the editor shows it: "99%", "37.5 GB", "1.4 TB", "2". */
FOUNDATION_EXPORT NSString *TGBCardFieldText(const DCValues *values, TGBCardField field);

#pragma mark Pomodoro and position

#define TGB_TIMER_SECONDS 60u     /* the demo timer; TFP1 accepts 10...7200 s */
#define TGB_POSITION_STEP_MS 15000u
FOUNDATION_EXPORT NSString *TGBClockText(uint32_t milliseconds);   /* m:ss */

NS_ASSUME_NONNULL_END
