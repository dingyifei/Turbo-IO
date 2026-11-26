> Historical: describes a feature removed from the current ios107 build (2026-10)

# iOS navigation background behaviour fix

Fixed on 2026-09-22. Phone side only; the glasses firmware is not changed or flashed.

**Risk warning: this is experimental, non-commercial developer code for learning and research, not a finished navigation product. Do not operate or test it while driving, cycling or crossing a road. The lens can disconnect, lag, stay on an old instruction or turn off; always go by the actual road and a mature navigation product. Background location uses more battery, and the system can suspend or terminate the app; a permanent connection is not guaranteed. This background fix does not need a firmware flash, so do not go into the experimental OTA just to use it.**

## What was fixed

The old navigation page called stop-navigation as soon as it received `UIApplicationWillResignActiveNotification`, which then stopped the AMap engine and exited the lens display. Going to the home screen, locking the screen, or even a system alert could trigger this, so it cannot be read directly as a Bluetooth disconnect.

The session is now judged only when the app really enters the background. Real navigation that is running is kept; a route that has not started yet does not turn on location by itself. Alerts no longer trigger STOP. Leaving the navigation page, closing the research page, a user stop, arrival and a navigation error still run the normal teardown. The official Bluetooth connection logic is not changed. Revoking location permission stops the session.

## How to use it

1. Configure your own AMap iOS key, then build, merge and sign with your own signature as described in the [navigation guide](NAVIGATION.md). Do not commit private configuration or signed packages to the repo.
2. With the phone in the foreground, choose a live route, plan it and tap start. Allow location "使用 App 期间" ("While Using the App"); this implementation does not request the "始终" ("Always") permission by itself.
3. The host `Info.plist` must have the `location` entry in `UIBackgroundModes`. Keep the existing Bluetooth and accessory modes; do not overwrite the whole array. Without that entry the code does not force background location: the page states that only foreground use is supported, and going to the background stops safely. The packager does not add background capabilities silently.
4. When you tap start on live navigation, the AMap engine that this code owns is set to `allowsBackgroundLocationUpdates=YES` and `pausesLocationUpdatesAutomatically=NO`. Both are restored on stop. Engines owned by other features are not changed.
5. You can go to the home screen or lock the screen. **Do not force-quit the app from the app switcher.** System termination, lost connection and location permission changes can still interrupt navigation; it is not promised to stay online permanently.

### Simulated navigation is different

Simulation does not need real location and does not start it to stay alive. On entering the background it requests a short system background task, **25 seconds at most**, and the system may end it sooner. When the time runs out it stops and shows an explanation. Returning to the foreground releases the allowance, and a late timeout from an old session does not end a new one. There is no silent audio playback, fake location or repeated renewal of the background task.

This fix does not lift the existing limits on each display channel. The public subtitle path is still the simulated research channel; the 4-minute/80-frame limit and the stale-data guard stay, and the subtitle channel's own foreground guard is not removed. **AMap continuing to run in the background on the phone does not mean the old subtitle channel keeps displaying in the background.** The private TNV1 native navigation branch uses the same lifecycle fix, but this commit does not package its firmware, OTA entry, personal configuration or private IPA. Do not mistake this patch for a complete TNV1 release.

## Verification limits

- Host tests of 32 policy combinations and the real lifecycle code cover: keeping real navigation in the background, denied permission, the simulation allowance, repeated backgrounding, foreground return, stale callbacks, a refused allowance, user stop and permission revocation.
- The build can be called buildable only after the host build and the AMap SDK build pass. The host tests use OS stand-ins and **cannot replace proof of background running on a real iPhone**.
- On 2026-09-22 the matching private build `NAVIGATION-PHONE-02-BG` was installed and its load marker checked; the user reported "No problem, I tested it." This is recorded as initial on-device feedback for that iPhone Air research build. It uses the same lifecycle fix, and **it does not mean every display channel of the public build, or every phone model, has passed**.
- The user did not give the test duration or whether it was simulated or live mode, so it cannot be used to claim long-running background use is fully verified. Live navigation with the screen locked for at least 2 minutes, foreground/background round trips, no extra location after stop, low battery, and recovery from a Bluetooth disconnect should still each be recorded. Do not use it for real driving decisions.

References: [AMap background navigation settings](https://developer.amap.com/api/ios-navi-sdk/guide/location-info/location-setting-callback), [Apple background location requirements](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates).
