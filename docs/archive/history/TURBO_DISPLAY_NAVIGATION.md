> Historical: describes a feature removed from the current ios107 build (2026-10)

# Turbo Display and the native navigation app

Updated 2026-09-22. This page separates two implementations built on Strix OS 1.0.4.12: **Turbo Display is a development test tool, and native navigation is a standalone app page**. Neither is a default SDK capability of the stock firmware.

## 1. One test tool, one navigation app

### Turbo Display: image transfer and display test tool (Test)

The eighth item in the glasses menu is **Turbo Display**. It is for development, debugging and acceptance checks only, not for everyday display. The phone picks and processes an image, sends it over the existing Bluetooth connection, and the glasses show the custom pixel content. The display canvas is **512×128, 8-bit grayscale**, and the glasses show it as green monochrome. A normal color image has to be scaled and converted to grayscale first; this is not a color display.

A user has confirmed, looking through the lens, that both full-image display and partial updates work. A partial update sends only the changed region. It is meant for checking test images, text layout and display prototypes, but the first full image and large changes still cost transfer time. Block-by-block updates can show intermediate frames, so there is no tear-free guarantee. This is not video casting and not image transfer at arbitrary resolutions.

### Native navigation: a standalone app page on the glasses

A ninth item, "导航" (Navigation), was added; the original seven items and Turbo Display stay. Navigation has its own icon, menu title, page and session state. It does not fake navigation on the image test page, captions or the teleprompter.

On the phone, AMap (Gaode) handles search, route planning and navigation callbacks, and sends the turn, distance, road text and route points. An LVGL page inside the glasses application draws the arrow, text and a route sketch, so **the phone no longer has to render a full image for each navigation update**.

- Layout: 540×180, with arrow, distance, road name, remaining-trip info and a route sketch of up to 32 points.
- Each complete navigation message is at most 328 bytes. Only one transfer is in flight at a time; the phone waits for the file's final state and the matching glasses acknowledgement, keeps only the latest pending state, and updates at most once per second (1 Hz).
- The phone's START can open navigation from the home screen, so the user does not have to enter the glasses menu first. If navigation is opened by hand with no session, the glasses show "请从手机开始导航" (Start navigation from the phone).
- By default the display turns off after 60 seconds without a valid content update, the physical button wakes it, and always-on is optional. Stop, back, and takeover by another task each end the session cleanly. A heartbeat is not new navigation data and must not keep stale guidance on screen indefinitely.
- The phone app no longer exits immediately when sent to the background; see [Background location and simulation test limits](NAVIGATION_BACKGROUND.md).

"App level" here means a native navigation app page built into the firmware, with its own entry point and lifecycle. Underneath, it is an LVGL subpage in the Launcher. It is not a dynamically installed APK/HAP, and it is not a general third-party app store. The feature is still experimental.

## 2. How to use it (matching new firmware and phone build)

1. Keep the RayNeo app connected to the glasses as usual, and end any other recording, teleprompter or voice task. You do not need to unpair and re-pair for navigation.
2. In TurboIO navigation, enter your own AMap iOS key, choose a mode and the start and end points, plan the route, then tap start simulated or live navigation.
3. Once the phone has a turn and a distance, tap "开启眼镜原生导航" (Start native navigation on glasses). The glasses can be opened this way even while they sit on the home screen. Do not pick the old caption or teleprompter display buttons.
4. Check the arrow, distance, road name and route sketch. The phone's route data keeps driving the native screen; it is not a stream of navigation screenshots.
5. Use "停止并退出眼镜导航" (Stop and exit glasses navigation), or the glasses' physical back button, to end the display. Live navigation can keep running in the background if location permission allows. Simulation only gets the system's short background allowance, so unlimited simulation with the screen locked is not promised.

Use the [TNV1 experimental release](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tnv1) and its matching source build notes, and read the upgrade and acceptance steps first. **The old R3 release does not include this feature and must not be mixed with it.** No merged or signed IPA is provided; users configure their own service key and signing.

## 3. Implemented, verified and released

| Item | Progress on the research device | Current public status |
| --- | --- | --- |
| Turbo Photo R3 | Embedded PNG; enter, exit and re-enter confirmed on the lens | Source, tools and a clearly warned pre-release are public |
| Turbo Display / TDP1 (test tool) | Full image and partial updates confirmed on the lens | Pinned firmware provided in the TNV1 pre-release; matching iOS source, build and checksums are public |
| Native navigation / TNV1 | New firmware boots, the standalone navigation page opens, and the user reports phone navigation works normally | Pinned firmware provided in the TNV1 pre-release; matching iOS source, build and checksums are public |
| Phone background fix | A private iPhone Air build from the same source tested fine per user report | main has the optional iOS build matching TNV1, the background fix and tests |

User reports do not cover every navigation mode, long periods with the screen locked, low battery, reconnect after a disconnect, or every power policy. One success on the research device does not mean every public client or every device has passed acceptance.

## 4. Risks and development constraints

**For developers, for non-commercial study and research only. This is not a finished product for regular users and not a certified safe navigation product.** Test while stationary in a safe place. Do not operate it while driving, cycling or crossing a street, and do not rely on the experimental lens to decide which way to go.

- The route sketch is not an AMap base map, street labels or a real view of the intersection, and accurate map matching is not guaranteed.
- Bluetooth transfer, phone background limits, stale data and abnormal exits can all cause delay, wrong guidance or a blank screen. Background location uses more battery, and recovery after a force quit or system termination is not guaranteed.
- The firmware changes only the contents of `nuttx_ap.bin`; the other 13 payloads stay unchanged. **That does not mean OTA flashes only the AP, and it certainly does not mean the glasses cannot brick.** A bad AP, power loss, an interrupted install or a version mismatch can leave the glasses unable to boot or unable to take OTA. Neither the stock rollback nor the original package is a guaranteed recovery.
- Do not casually enlarge image sizes, widget counts or transfer queues. Memory, rate limiting, release on exit and error acknowledgements have to be verified together.
- Releases still contain only reviewed source and dependencies plus explicitly listed research attachments. Private keys, accounts, logs, signing material and merged phone packages are not published.

[Back to main README](../../../README.md) · Early R3 process and risks · [iOS standard navigation guide](NAVIGATION.md)
