> Historical: describes a feature removed from the current ios107 build (2026-10)

# RayNeo iO Glasses Navigation: Developer Guide

**Tested environment at the time: official iOS RayNeo AI app 1.0.5 (Build 201) + Strix OS 1.0.4.12, on a non-jailbroken iPhone Air.** The app version and the glasses firmware version are separate things. 1.0.4 and 1.0.2 are older adaptations, not the app used here.

2026-09-22: the phone navigation background lifecycle is fixed. Live routes use background location once the user grants it; simulation allows only a short background test of up to 25 seconds. A private iPhone Air build from the same source has received early positive feedback. **Long-running background use and each display channel of the public build still need dedicated acceptance testing, and the old subtitle channel keeps its own foreground guard. This is experimental and risky; do not use it to make driving decisions.** See [background navigation setup and acceptance limits](NAVIGATION_BACKGROUND.md).

This is an optional module of the V2 official-app addon, not a feature of the V1 standalone client. The project is for non-commercial developer research only and uses the PolyForm Noncommercial license in the repository root. It does not provide merged or pre-signed IPAs, signing certificates, personal accounts or API keys. The repository's [stock 1.0.5 (201) decrypted IPA](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.5-201) can be used as the merge input; it does not contain the Turbo IO addon.

**Choose one route first. Do not mix the two display methods:**

- **Standard build / stock firmware**: AMap phone navigation + the stock subtitle template. The default commands in sections 2 to 5 and the "开启眼镜字幕显示" (Turn on glasses subtitle display) button belong to this route, which still has simulation and foreground guards.
- **TNV1 experimental firmware / standalone navigation app**: the newest app-level glasses navigation. The phone sends semantic data and the glasses draw the arrows and route sketch locally in LVGL; it can be started from the home page. It needs the matching dedicated **1.0.5 (201)** build and the high-risk research firmware. Follow the TNV1 build and the upgrade/navigation usage flow; the button is "开启眼镜原生导航" (Turn on glasses native navigation). **Do not compile with the standard build commands and expect TNV1 to appear.** Turbo Display is an image-transfer test tool, not a navigation app.

The map features both routes share come first, then the standard subtitle build.

## 1. What it can and cannot do

| Item | Current implementation / verification limits |
| --- | --- |
| Phone map and places | AMap keyword search (city optional), last 12 selections, tap/long-press to pick a point, pick the map center, zoom in/out buttons, locate on request |
| Routes | Walking, cycling and driving each use their own AMap engine; overview, step details, simulation/live switch; plan first, then start; changing the start, destination or travel mode invalidates the old route |
| Standard-build lens text | AMap simulation callbacks → turn/distance/road/remaining info → the glasses' built-in subtitle UI; not a map image or screen mirror |
| Standard subtitle staying on | The private predecessor's subtitles stayed up for about 2 minutes in feedback; hands-free navigation display through the official subtitles was confirmed; no guarantee it stays on indefinitely |
| Standard subtitle guards | The first frame waits for a new session ACK; 3.2 s throttle, keeping only the newest content; 4-minute/80-frame cap; stops after 15 s without data; stops when the app leaves the foreground |
| Interaction fixes in this round | Explicit search, cancel, a city change discarding the old query, tap to pick, real zoom and the fixed simulation start passed local/simulator checks; online POI results and on-device feel still need acceptance |
| Real trips | Live phone navigation now uses background location (needs permission and the host's location mode; the matching TNV1 private build has user feedback; long runs untested). **Glasses subtitles are open for simulation only, not for real trip guidance, and are not a safe navigation device** |

Do not test while driving, and do not let experimental lens text replace watching the road or a mature navigation product. The map and search need a network connection. The project provides no offline maps, no navigation TTS takeover and no route track storage. Continuous GPS with the screen locked is configured but still needs on-device acceptance; do not treat it as a guarantee of stable use.

## 2. Compatibility and AMap dependencies

- **Current official app: iOS RayNeo AI Glasses 1.0.5 / Build 201.** The standard addon keeps older adaptations for 1.0.4 (195) and 1.0.2 (67); **the TNV1 experimental OTA supports only 1.0.5 (201)**. For the exact binary constraints, see the [V2 build notes](../../../official-addon/README.md). Do not skip the check for unknown versions.
- **Current firmware: Strix OS 1.0.4.12.** Users reported normal behaviour after the stock upgrade; the TNV1 fixed-AP modified build has separate navigation and background test feedback. See the 1.0.5 adaptation notes and the TNV1 acceptance limits. Early protocol research was based on 1.0.3.15, and 1.0.4.8 was a past upgrade check. A new SID is generated each time and the glasses ACK is awaited; this cannot be extrapolated to every mode or firmware.
- Navi **11.2.100** (includes maps), Foundation **1.9.1** (non-IDFA package), Search **9.8.1**. They are built into the addon as static libraries; do not inject the same SDKs into the host a second time as dynamic libraries.
- Official sources: [Navigation SDK download](https://developer.amap.com/api/ios-navi-sdk/download), [Map/Search SDK download](https://lbs.amap.com/api/ios-sdk/download). Read and follow their license, privacy and service terms before use. This repository no longer distributes these SDK binaries.

From the repository root:

```sh
# After reading the official terms, explicitly agree to download the pinned dependencies. No key is needed.
node official-addon/setup-amap.mjs --accept-sdk-terms

# Build the arm64 addon with real AMap maps
TIO_AMAP_ENABLED=1 bash official-addon/build.sh embedded
```

The output is `official-addon/build/navigation/TurboIOPrivateAddon.dylib`. The SDKs are stored in `official-addon/build/amap-sdk`, which Git ignores; never commit the build directory.

The fetch script checks the SHA256 of both official archives and unpacks only the named sub-packages. If a download link changes and the hash no longer matches, it stops instead of silently switching SDKs. If you already downloaded the same archives, put them in an absolute directory and add `--archives-dir /absolute/downloads`; the file names must be `AMap_iOS_Navi_ALL.zip` and `search-9.8.1.zip`. Offline import checks the hashes too, and an existing SDK directory is not overwritten.

The default `bash official-addon/build.sh embedded` does not link AMap. It suits the base addon or a zero-key preview; the page says plainly that the SDK is missing and does not fake maps or search results.

## 3. Merge and sign on your own computer

First prepare an original `Runner.app` that you are entitled to use and that meets the [V2 technical requirements](../../../official-addon/README.md), plus your own signing material. The tools do not download apps, decrypt them, or bypass login or payment limits. Do not use a previous private build that carries personal configuration as public input.

```sh
node official-addon/package.mjs \
  --app /absolute/authorized/Payload/Runner.app \
  --addon /absolute/Turbo-IO/official-addon/build/navigation/TurboIOPrivateAddon.dylib \
  --amap-sdk-root /absolute/Turbo-IO/official-addon/build/amap-sdk \
  --profile /absolute/private/development.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 \
  --device YOUR_DEVICE_ID \
  --out /absolute/private/new-navigation-output

xcrun devicectl device install app --device YOUR_DEVICE_ID \
  /absolute/private/new-navigation-output/Payload/Runner.app
```

`--amap-sdk-root` copies `AMap.bundle`, `AMapNavi.bundle` and `AMapSearch.bundle` into the output app. It stops if one is missing, is a symbolic link, or a resource with the same name already exists, to avoid mixing versions; it adds a foreground location usage description when needed. The Navi/Foundation/Search code is statically linked into the addon, and no framework is copied into the release repository. **A navigation build must not leave out this parameter, or resources may be missing.**

The input app is not modified, and the output directory must not already exist. Signing and the IPA happen only on your machine; the project neither uploads nor provides these products. A successful install, the app launching, the account and Bluetooth working, and the lens showing the right content are separate acceptance steps.

## 4. Enter your own AMap key

1. In the AMap console, create an **iOS platform key** bound to the real app Bundle ID; the target here is `com.rayneo.venus.pub`. A Web service key or TinyFish key cannot replace the iOS key.
2. Enable the map, search and navigation services your account needs; AMap manages service permissions and quotas.
3. In the app, go to "TurboIO → 资料 → 步行 / 骑行 / 驾车导航" (TurboIO → Profile → Walking / Cycling / Driving navigation), open "更多" (More) at the top right, choose "高德 Key 设置" (AMap key settings) and paste your key.
4. The key is stored only in the local keychain, and the old value is never shown again. The public build has no maintainer key and no logic that imports a key from a private build. To change the key, restart the app first and change it before the map initializes.
5. Tap "开启地图" (Turn on map), read the privacy notice, then decide whether to agree. If you decline, the map SDK is not initialized. Location is requested only when you tap "我的位置" (My location) or use live navigation; simulation does not need your real location.

## 5. Use simulation for the first run

1. On the RayNeo app home page, confirm the glasses are connected, and end any recording, teleprompter, subtitles, Lifelog and conversation. V2 works inside the same host, so V1 does not need to be opened; do not unpair repeatedly to use navigation.
2. Open navigation, choose "步行 / 骑行 / 驾车" (Walking / Cycling / Driving) first, and keep "模拟验收" (Simulation check). Tap "去哪里？" (Where to?), enter a place and an optional city, then tap "搜索地点" (Search place) or the keyboard's search key. Typing alone does not upload a query per character; you can tap cancel while a search runs.
3. Pick a search result, or **tap** the map to choose the destination. You can also drag the map and tap "将地图中心设为终点" (Set map center as destination).
4. The simulation start and the destination are independent. The initial Beijing start has a clear label. To test elsewhere, switch to "选模拟起点" (Pick simulation start) and tap the map, or tap "我的位置" (My location) to use the phone's current position. Searching or dragging the map does not change the start.
5. The **＋ / －** buttons on the right zoom; the crosshair in the middle is not a button. The map can be dragged, and a tap or long press picks a point for the current role.
6. Tap "规划路线" (Plan route), check the route, distance and time for the chosen travel mode, then tap "开始模拟" (Start simulation). The "更多" (More) menu at the top right has a public Beijing demo route, so you can run the check without a private location.
7. When live guidance appears on the phone, tap "开启眼镜字幕显示" (Turn on glasses subtitle display) and confirm the lens home page has no other task. Text starts only after a new session ACK.
8. On normally supported versions you do not need to go through the official "实时字幕→预览→退出" (Live subtitles → Preview → Exit) every time. Only the layout and configuration are restored; an expired SID is not reused and Bluetooth is not assumed to be connected.
9. "停止眼镜显示" (Stop glasses display) keeps the phone simulation running; "结束导航" (End navigation) stops this task. If the exit acknowledgement is unclear, the state stays uncertain. If the lens does not close, exit with the physical button; do not stack sessions one after another.

Changing the start, destination or travel mode of a planned route that has not started clears the old route, and you must plan again. During real navigation, stop first before changing the destination. The 4-minute subtitle guard is not a fault; do not work around it with an automatic restart loop.

### How the three modes differ and their acceptance limits

- Walking: `AMapNaviWalkManager`, with the start and destination as coordinate arrays.
- Cycling: `AMapNaviRideManager`, with the start and destination as single coordinates; it does not reuse walking route planning.
- Driving: `AMapNaviDriveManager`, currently with the single-route default strategy (0); no multi-route choice and no avoid-tolls or truck parameters.
- Each of the three modes has two route-planning entries: "fixed simulation start" and "phone's current position". If the SDK refuses or service permissions are missing, it fails clearly and does not quietly fall back to walking.
- AMap engines must be mutually exclusive singletons. When switching, only the old engine this addon owns is released; other navigation in the host is not forcibly stopped. If the release has not finished, a prompt asks you to plan again later.
- You cannot switch modes during route planning or navigation; end it first. Only a planned route that has not started can be switched directly and re-planned.
- Public transit and a dedicated e-bike mode are not implemented. Cycling must not be treated as adapted to e-bike or motorcycle regulations.
- **The modes added in this round passed parameter mocks for six interfaces, UIKit mode-switch checks and an on-device-architecture build; cycling and driving have not been tested with online routes or on the glasses.** Source that compiles does not replace real acceptance; anonymized test results are welcome.

## 6. Common problems

| Symptom | Check |
| --- | --- |
| Typing gives no results | Tap "搜索地点" (Search place) or the keyboard's search key; watch for loading, no results or an error code. Filling in a city makes it a city-restricted query |
| Search fails but the map loads | Search service permission, network and key binding may differ from the map's; check the error code; a visible map does not mean every authorization succeeded |
| Offline preview / SDK not linked message | Rebuild with `TIO_AMAP_ENABLED=1` and pass the resource parameter; entering a key cannot supply missing binary dependencies |
| Start and destination less than 30 m apart | Choose the start or destination again. Dragging the map alone does not change the fixed start |
| Glasses display button unavailable | Start a real AMap simulation first and wait for a fresh navigation callback; stop other display tasks. It is not live navigation mode and not an offline fixture |
| Display still asks for format/connection | Confirm the current connection on the home page; by default only supported versions match. An unknown format is relearned in the subtitle check under "更多" (More); do not reuse an old session |
| Stops after about 4 minutes / stops when leaving the foreground | Current experimental guard. Long outdoor/background runs are not finished; staying on is not promised |
| Re-signed install will not open | Check unlock, Developer Mode, certificate/provisioning profile and system prompts; do not try to recover by wiping the only original app |

You can look at the local `Documents/TurboIOResearch/navigation/search.json` for the stage, error code and result count; it does not contain search terms, coordinates or the key. Do not commit a full app sandbox, account logs or private recordings.

## 7. Architecture and extension points

```text
AMap SDK: search / Walk, Ride, Drive route planning and navigation callbacks
                 ↓
NavigationModes: picks the right engine and parameters; the navigation page normalizes the three callback sets
                 ↓
NavigationCore: one text state for turn, distance, road and so on
                 ↓
NavigationSubtitleHUD: newest frame, rate limit, data-gap/timeout guards
                 ↓
SubtitleHUD + ProtocolContext: current device, new SID, ACK gate
                 ↓
Official communication channel → RayNeo iO built-in subtitle page
```

`NavigationWorkspace.inc`/`NavigationPlacePicker.m` handle phone interaction, `NavigationTransport.m` keeps the notification and dedicated dashboard-card fallback channels, and `NavigationTeleHUD.m` keeps the manual teleprompter fallback. Notifications and cards turn the screen off, and the teleprompter shows loading when the script changes, so none of them should be treated as a seamless always-on main path.

This is research into business content and a restricted component protocol, not HTML, Canvas, pixel screenshots or replacing the system home screen. Next priorities are real-world safety acceptance of the three travel modes, lifecycle, long background runs and error recovery, not removing the guard timers first.

## 8. Testing without a key


The image above is a UIKit simulator screenshot of the public source, using a public test term to show the cancelled state. It is not a glasses screenshot or a real search result.

```sh
bash official-addon/test.sh
node --test official-addon/macho-embed.test.mjs official-addon/package.test.mjs official-addon/amap-resources.test.mjs
bash official-addon/preview/build.sh
xcrun simctl install booted official-addon/build/research-preview/ResearchPreview.app
xcrun simctl launch --terminate-running-process booted io.turboio.research.preview --navigation --navigation-modes-check --navigation-workspace-check
xcrun simctl launch --terminate-running-process booted io.turboio.research.preview --navigation --navigation-interaction-check
```

The simulator has no network and does not link AMap; do not treat simulator pages as lens screenshots, and the test results do not show that the real map service works. The public source leaves personal profile data empty by default and has you configure model and search keys yourself; it has no built-in maintainer services.
