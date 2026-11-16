#import <Foundation/Foundation.h>
BOOL TNVStart(NSDictionary *);
void TNVOffer(NSDictionary *),TNVPump(void),TNVStop(void),TNVSetAlways(BOOL);
BOOL TNVConsume(NSDictionary *),TNVPauseForOTA(void),TNVAlways(void);
// The shared BLE file link: one native file in flight across navigation and music (see MusicPlayer.h).
BOOL TNVFileInFlight(void);
NSDictionary *TNVStatus(void);
void TNVReplayPaused(BOOL paused);
void TNVLifecycle(NSString *event);
