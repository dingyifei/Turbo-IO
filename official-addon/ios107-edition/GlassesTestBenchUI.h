#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/* Developer, "Glasses test bench" (research catalog key testBench). Sends demo data through the existing wire messages so a TMG9 build can
 * be checked on the glasses without a real song, account or route: lyric layouts and the dashboard card, a fake now-playing song and the
 * Pomodoro timer. The fixture builders are in GlassesBench.h; the senders are small entry points beside each owner (MusicPlayer.h,
 * DashboardCard.h, FocusBridge.h). Nothing is sent while a firmware stage is running, and there is no fake navigation route. */
UIViewController *TIOGlassesTestBenchController(void);
#if TIO_UI_PREVIEW
/* section: @"lyrics", @"song", @"card" or @"timer" scrolls the screen to that section; nil shows the top. */
UIViewController *TIOGlassesTestBenchPreviewController(NSString *_Nullable section);
#endif
NS_ASSUME_NONNULL_END
