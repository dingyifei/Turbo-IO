# Changelog

> **Frozen (2026-11-15, cleanup(6)):** this file is no longer updated. cleanup(1)–(6) deleted the Android, HarmonyOS, V1, Apple Watch, TVP2/TAR2 and Strix OS 1.0.4.12 research trees it mentions, and most of the screenshots. Links and images that pointed to those deleted files were turned into plain text or removed. The original files stay in git history (for example `git show 5b6c63d:<path>`). In 2026-11 the text was translated from Chinese to English; the facts are unchanged.

Update notes and historical acceptance records from 2026-09-22 to 2026-10-23, moved out of the [project home page](../README.md). The text was kept as it was; only the links were fixed, and phrases such as "above" that pointed at home-page content were turned into links. Later firmware versions are in [`firmware/`](../firmware/README.md) and the `fw/tmgN` tags.

<a id="updates"></a>

## Recent updates and glasses apps

Newest first. Each entry states its public scope and acceptance limits.

| Date | Update | Public scope |
| --- | --- | --- |
| 2026-10-23 | [TVP2 / TAR2 native sharp mirroring](#tvp2-tar2-update) | 540×220 pixel for pixel, full frame / zoomed region / grayscale; a user tested on iPhone 17 Pro Max and reported it works; published the as-flashed firmware, a reproducible build, the HD transfer code and a standalone GPLv3 receiver SDK; no personal merged IPA, account or video |
| 2026-10-19 | [Stock iOS 1.0.7 (230) decrypted · unsigned input](../official-apps/ios/1.0.7/README.md) | Turbo IO not merged; 95 code signatures and store license metadata removed; SHA-256 and audit included; works with the latest APP107 packager; merge and sign it yourself |
| 2026-10-19 | [iOS 1.0.7 (230) APP107 adaptation and OTA enabled](#ios107-update) | Features reported working on iPhone 17 Pro Max; TMG2 flashed successfully through the official 1.0.7 update flow; published redacted source, the dedicated query adapter and the packaging tool; full checks and one-time authorization kept; inherits NAVS3; firmware reused unchanged |
| 2026-10-19 | [NAVS3 vector navigation and TMG2 selectable-row menu](#navs3-update) | Simulated/real navigation straight from start and destination, road and road-name stability fixes, two/three-row menu; iOS source, offline tests, as-flashed TMG2 firmware and reproducible build; the lock-screen problem is still open |
| 2026-10-19 | [Remote camera: glasses viewfinder, knob shutter and zoom](#remote-camera) | iOS phone and glasses native source published; included in TMG2 firmware; countdown, compressed viewfinder and post-shot review; originals saved to the phone's photo library; the phone must stay in the foreground and unlocked |
| 2026-10-15 | [Stock iOS 1.0.6 (218) decrypted · unsigned input](../official-apps/ios/1.0.6/README.md) | Turbo IO not merged; 95 code signatures and store license metadata removed; stock feature code kept; merge and sign it yourself; copyright stays with the vendor |
| 2026-10-14 | [New version adaptation: App 1.0.6 / Strix 1.0.5.5 / TMIG1](#tmig1-update) | Tested compatible on iPhone 17 Pro Max; as-flashed firmware, reproducible AP build, phone adapter source, Situational English, new stock ZIP; Dots in development, not finished |
| 2026-09-30 | [TLC1: all-day Lifelog coexists with extension apps](#lifelog-coexist) | Coexistence checks for six extension apps, reproducible build and tests, as-flashed firmware and iOS OTA reference; AP-only change; after flashing you must end the phone's update protection |
| 2026-09-29 | [Apple Watch remote experiment source and TGR1 firmware](#apple-watch-remote) | Watch crown/screen/gestures, iOS bridge, TGR1 AP input adapter and the experimental OTA as is; known page-turn problem not resolved; no signed package |
| 2026-09-27 | [Android 1.0.5 full addon and official-flow OTA](#android-release-update) | Full APK without the web-text adapter, extension source, as-flashed TAP1-TEST-01 firmware, checksums and step-by-step guide; high-risk experimental release |
| 2026-09-26 | [Developer ecosystem: app gallery, dashboard and App SDK](#developer-ecosystem) | Self-hosted API / Python / MCP, 20 offline template ZIPs, Agent Skill, protocol reference source; the matching full firmware is not in this release |
| 2026-09-25 | [Major update: new UI, four-item menu, native Pomodoro timer](#focus-update) | FOCUS-04 original source, matching iOS addon and the exact as-flashed experimental firmware; no private config or web-text adapter |
| 2026-09-24 | [Local translation and offline English captions](#local-translation) | Apple / Hy-MT2 / Parakeet source, model downloads and optional iOS build; no weights or keys |
| 2026-09-24 | [WeChat Reading: four-book shelf and reading page](#weread-research) | TWR1 original module, build tools and as-flashed experimental firmware; no web-text adapter |
| 2026-09-23 | [NetEase Cloud Music: tenth menu item](#music-app) | TMU1 source, matching phone code and tested experimental firmware |
| 2026-09-22 | [Turbo Display and native navigation](#native-apps) | TDP1/TNV1 source, matching phone code and matching firmware |
| 2026-09-22 | [ANIM60 local animation](#animation-test) | Animation experiment source and a standalone firmware candidate; not a general animated-image upload |

> **Custom firmware is experimental. If you are not a developer, do not flash it.** AP changes can still leave the glasses unable to boot or lose OTA. Do not mix firmware, phone gates or authorizations from different candidates. Rolling back to stock is not a guaranteed unbrick. Success on a device does not make it a stable production release.

<a id="tvp2-tar2-update"></a>

### 2026-10-23 · Sharp mirroring: from "it sends a picture" to native 540×220

**No more scaling a 270×110 image up 2×.** TVP2 encodes at 540×220 and displays it pixel for pixel, 4× the pixel count. The phone supports full frame, zoomed region, a draggable selection and 2/4/8/16 gray levels. A frame switches only after all four tiles have arrived and passed per-tile and whole-image CRC checks, which avoids half images and queued stale frames. The extra detail also means the real frame rate is limited by bandwidth; 30 fps is not guaranteed.

**Another iPhone/iPad/Mac → iPhone receiver on the same Wi-Fi → glasses. No extra Mac or server needed.** The phone requests a 1280×720 source and decodes and scales it locally; the glasses receive only bounded grayscale data. It runs in the foreground, muted, started by hand and PIN-paired, and saves no frames. The receiving phone is still a required relay. Locked-screen background use, protected video and arbitrary senders were not accepted this round and are not supported.

A user tested **iPhone 17 Pro Max / RayNeo app 1.0.7 (230) / TAR2 + TVP2** and reported "no problems". Only summary statistics were read back from the device: 1280×720 source, 540×220 output, 16 grays, 3470 frames decoded with zero errors, 186 frames fully acknowledged by the glasses, clean shutdown. The raw logs are not published. The standalone public SDK was compiled and linked separately; the acceptance of the private integrated build is not presented as proof that the public host-bound build is in place.

**Double-buffer memory does not grow: 239424 bytes. The AP is 7,435,336 bytes, only 1024 bytes larger.** Old TVP1 video compatibility is kept, and the other 14 new stock payloads are unchanged. The AP and ZIP rebuilt from public source match the tested candidate byte for byte. The new HD mode needs TVP2 flashed; installing only the phone addon is not enough. Full OTA and recovery risks remain; non-developers should keep stock firmware.

**[As-flashed firmware/AP/SHA256/source bundle](https://github.com/Turbo1123/Turbo-IO/releases/tag/tvp2-tar2-20261023) · [Full guide and version differences](archive/TVP2_TAR2.md) · Firmware source and rebuild · Original HD module · GPLv3 AirPlay receiver SDK**

No personal signed or merged IPA, video material, pairing keys, cookies or accounts are published. `tar2-airplay` is a GPLv3 partial license exception confirmed by the maintainer; all other directories keep the non-commercial license. No Android AirPlay receiver was released this time. Full compatibility with Mentra OS store apps is still being adapted and is not part of this mirroring test result.

<a id="ios107-update"></a>

### 2026-10-19 · iOS 1.0.7 adapted; TMG2 flash tested

**A user installed APP107 on 1.0.7 (230) on an iPhone 17 Pro Max and reported "no real problems".** After install, the new addon's load marker, the version/UUID gate and the key callbacks were read back. The public build was prepared from the redacted NAVS3 baseline, compiled separately and run through offline regression. A user report is not full acceptance of every feature, phone model and background scenario.

This round keeps the vector mini map, the two/three-row menu setting and the existing extension modules, and **updates only the phone, not the glasses firmware**. The installed TMG2 stays; there is no need to reflash for the phone update. Signature and Flutter bridge checks passed for 110 existing methods across 8 key native classes. Old-version addresses were not applied directly to the new version.

**OTA is enabled: on 2026-10-19 the as-is TMG2 was flashed successfully on iPhone 17 Pro Max / 1.0.7 (230).** The official log confirms 100% transfer, a successful install and a matching version on reconnect. After flashing, the phone app was restarted and the authorization was back to 0. The public code adds a 1.0.7-specific query route and host check and does not reuse 1.0.6 offsets. Packaging includes the update channel but never authorizes or flashes on its own; follow the [new guide](../ios-addon/OTA.md) and finish the wrap-up after flashing. This round reused the official cache, whose checksum matched; it does not claim a fresh network download or acceptance on every phone model. The phone lock-screen navigation problem remains; Dots is still unfinished.

Source, build and tests are public. Personal signed IPAs, cookies, keys, private service addresses, device backups and the WeChat Reading web-text adapter are not. The [stock 1.0.7 decrypted/unsigned input](../official-apps/ios/1.0.7/README.md) is archived separately and not merged with Turbo IO; you must use and sign it lawfully yourself. The older stock 1.0.6 input cannot be used for 1.0.7 packaging.

**[1.0.7 source / build and version comparison](../ios-addon/README.md) · [APP107 OTA pre-release](https://github.com/Turbo1123/Turbo-IO/releases/tag/ios107-app107-ota-20261019) · [Current TMG2 firmware (git tag `fw/tmg2`, download from the Release)](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019) · [Current glasses firmware source `firmware/`](../firmware/README.md)**

<a id="remote-camera"></a>

### 2026-10-19 · Remote camera: set the phone down, frame and shoot from the glasses

The phone takes the photo; the glasses are the viewfinder and the controller: **short-press the knob to shoot, scroll to zoom, long-press to cancel or exit**. The phone offers no countdown or a 3 / 5 / 10 second countdown, and lets you set viewfinder sharpness and landscape or portrait orientation. The glasses show a compressed preview and, after the shot, a review; the original is saved to the phone's photo library. The preview is processed on the device and not uploaded to the cloud.

In TurboIO on the phone, open 「遥控拍照」 (Remote Camera), grant camera and save-to-photos permission, tap 「开启相机与眼镜取景」 (Start camera and glasses viewfinder), then operate from the glasses. **The phone must keep this page in the foreground and stay unlocked.** The glasses viewfinder is at most 256×144, and the HD level transfers more slowly. It is a low-frame-rate preview to help framing, not HD live video.

The phone-side capture, compression, transfer and test code, and the glasses native page and control protocol are all public. **The released TMG2 firmware includes this feature; if you already have TMG2 you do not need to flash TCM1.** This entry adds a standalone feature description and does not build or replace firmware. The matching phone implementation listed is iOS; that does not mean Android has been adapted too.

**[iOS 1.0.7 phone source](../ios-addon/camera-v1) · iOS 1.0.6 phone source (archived; see `official-addon/navs3-edition/camera-v1` at commit `27ad86e`) · [Glasses native source](../firmware/src/camera-v1) · [TMG2 firmware download](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019) · [1.0.7 flash guide](../ios-addon/OTA.md)**

<a id="navs3-update"></a>

### 2026-10-19 · Vector mini map: from picking start and destination to native drawing on the glasses



*Design illustration made with imagegen, not a device screenshot. The map and place names are illustrative and do not represent actual routes or display accuracy. Experimental pre-release; the lock-screen navigation problem is still open. Image generation notes.*

**Pick a start and a destination, then start simulated or real navigation directly.** The phone uses Amap for planning and location, fetches licensed OSM roads nearby and converts the coordinates. The glasses draw roads, route, vehicle marker, road names and scale bar from a bounded vector scene, instead of receiving a continuous stream of full-screen screenshots. The time bar now stays in place and no longer alternates with 「导航常亮」 (navigation keep-on).

NAVS3 fixes the old road network being cleared too early: it keeps at most two areas, requests ahead and hands over atomically. Road names are placed at visible anchors along real roads that suit the current heading. On first load, when offline, or past the map-source request budget, only the route may be shown; nearby roads are never faked. **Navigation stopping or freezing after the phone locks is a known problem. Do not use it for driving or anything safety-relevant.**

The matching **TMG2** defaults to a menu of three rows and three columns; the phone can switch it to two rows of three and save that. Remote camera, music, reading, Pomodoro, Situational English, dashboard, mini apps, Watch input and the rest are kept. The customization changes only the AP (7,408,584 bytes); the other 14 stock payloads are unchanged. A full OTA is not the same as writing only the AP.

- TMG2 users have reported successful flashes. The release stays as it was, and the public source rebuilds a byte-identical AP / ZIP.
- The private NAVS3 phone build was installed on an iPhone 17 Pro Max and its loading checked. The public redacted derived source was compiled separately and passed offline regression. **There is no claim of sustained on-device navigation or full-feature acceptance.**
- Only for RayNeo AI iOS 1.0.6 (218) + Strix OS 1.0.5.5; this is not a new Android APK. An existing TMG2 does not need reflashing for NAVS3.
- No cookies, keys, signing material, private IPA, real routes/notifications/Lifelog records or web reading adapter. Dots is still unfinished.

**Source and build (archived; see `official-addon/navs3-edition/README.md` at commit `27ad86e`) · [Firmware and flash steps (git tag `fw/tmg2`)](https://github.com/Turbo1123/Turbo-IO/blob/fw/tmg2/firmware-research/strix-1.0.5.5-tmg2/README.md) · [Download / SHA-256](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)**

<a id="tmig1-update"></a>

### 2026-10-14 · New version adaptation pre-release: the low level moved again, the features carry on



*Landscape promo design made with imagegen, not a device screenshot. The version numbers are this round's fixed targets; future versions are not automatically compatible.*

**A user tested on iPhone 17 Pro Max: RayNeo AI iOS 1.0.6 (218) + Strix OS 1.0.5.5 / TMIG1 was flashed, entered and verified compatible.** The uploaded firmware is the one actually flashed, with no binary changes passed off as tested. The public phone source, with private config and the WeChat Reading web-text adapter removed, recompiles cleanly; the public derived full package was not reinstalled for a full regression.

**This is a low-level migration, not a version-number bump.** The bytes ahead of the old patches match **0/36** at the same locations in the new version. 134 native bindings were relocated; the new sizes and member offsets of the C++ menu and head-control objects were checked, along with callbacks and input lifecycle; then the 1.0.6 official query, download, unzip and 15-payload OTA checks were adapted. The public build rebuilds the AP and full ZIP identical to the tested ones. The adaptation was not easy. Later official updates must be audited again; old addresses cannot be copied over.

- Carries over the four-item menu, dashboard and mini-app SDK, navigation, music, native reading, Pomodoro, Watch input, diagnostics, Lifelog coexistence and other modules. There is no promise that each feature has passed long-term full acceptance.
- **Situational English joins this public research scope**: it builds a bounded question bank from Lifelog clips already on the device; the phone authorizes, checks and sends; the glasses run light study and review. You configure models and service credentials yourself; automatic features are off by default.
- **Dots keeps an in-development entry and is not finished**; it is not a conversation product shipped in this round. Private Bridge, session, subscription, tunnel and auth configuration is not published.
- The customization changes only the new AP; the other **14 payloads are byte-identical to the new stock**, and a full OTA still installs them. The AP is **7,373,064 bytes**, under the conservative 9.6 MB budget. Size is no guarantee of RAM headroom or safety.
- **Archived the original official 1.0.5.5 ZIP**: not repackaged, no custom changes, with its source and checksums. It is not an unbrick guarantee, and the fixed TMIG1 gate cannot flash it as a custom package.

**[Download TMIG1 / checksums](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.5.5-tmig1) · Low-level migration, reproduction and flash guide (deleted; see `git show 5b6c63d:firmware-research/strix-1.0.5.5/README.md`) · 1.0.6 addon build (archived; see `official-addon/tmig1-edition/README.md` at commit `27ad86e`) · [Stock 1.0.5.5](../firmware-research/strix-1.0.5.5/stock/README.md)**

**Unofficial experimental pre-release; beginners should not flash it.** Power loss, an interruption, the wrong package or a code defect can leave the glasses unable to boot or damage the device. Stability, rollback and unbricking are not guaranteed. Old Android APK and iOS candidates cannot be mixed in; no new Android 1.0.6 APK was released. It contains no personal keys, cookies, Apple developer account, signing material or merged IPA.

<a id="lifelog-coexist"></a>

### 2026-09-30 · TLC1: extension apps open even with all-day Lifelog on

Fixes navigation, music, reading, Pomodoro, DiDi and mini apps sometimes failing to open from the glasses menu once the official 「全天智记」 (all-day Lifelog) is on. **Lifelog stays on and stock recording is not rewritten; only the coexistence checks of six extensions change. The AP grows by 192 bytes relative to TGR1.** The stock foreground-occupancy and assistant-activity checks are kept. The TBL1 brightness experiment patch is not included.

**Source, reproduction and flash notes · [Download TLC1 firmware / SHA-256 / audit](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tlc1)**

A user confirmed that other apps open with Lifelog on and, after the update-protection wrap-up instructions, that music displays correctly in this round. Continuous capture, audio coexistence, repeated head raises and long-term stability still need testing. **Once you have confirmed that the glasses update finished and the glasses returned to the home screen on their own, you must fully quit and reopen the RayNeo app on the phone to end the in-process update protection; otherwise music and other content may not sync. Do not force-quit while the update is unfinished or its state is unclear.**

Experimental firmware: non-developers should not flash it, and rollback is no unbrick guarantee. Only AP content changes, but it is still a full OTA; the other 13 payloads are unchanged. Targeted source and an iOS OTA reference are provided; there is no private IPA, no credentials and no new TLC1 Android APK. The old GUARD-07 APK cannot flash this package directly. This does not fix the known TGR1 Watch global page-turn problem.

<a id="apple-watch-remote"></a>

### 2026-09-29 · Apple Watch remote: crown, gestures and screen controls



*Landscape concept image made with imagegen, not a device screenshot. The illustrated UI does not mean global input has passed acceptance.*

Uses the Watch as an input device for the glasses, relayed through the RayNeo addon on the paired iPhone: crown for previous/next item, screen for confirm/back, two gesture mappings, and phone authorization for 10 minutes or always on. Source, build and integration · TGR1 protocol and acceptance limits

**[Download TGR1 experimental OTA / SHA-256 / audit report](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tgr1) · Compatibility, checks and risks**

**Experimental source and firmware, not a stable remote-control release.** A user has reported that TGR1 flashed fine, but "page turning doesn't work" is still unresolved. This upload is the archived package as is, with no rebuild and no new device acceptance. Global input needs the matching TGR1; stock firmware and the released TAP1/FOCUS-04 do not support it automatically, and the fixed candidate gate in the old public APK cannot import this package directly either. No private IPA, signing material or personal config is published. "Always on" does not guarantee that the Watch or phone stays reachable in the background. Non-developers should not flash it; rollback is no unbrick guarantee.

<a id="android-release-update"></a>

### 2026-09-27 · Android 1.0.5 full addon and experimental OTA



**[Download full APK / TAP1-TEST-01 / checksum files](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01) · Full install and flash guide · Public scope and source build**

*The landscape update graphic was made with imagegen. It is not a device screenshot and does not replace the full guide. The public APK has no WeChat Reading web-text adapter or private config; the public derived package has not been flashed on a device again. After the glasses restart on their own, you must follow the guide to read the state back (read-only) and release the result protection. Do not release it while the update is unfinished or its state is unclear.*

<a id="developer-ecosystem"></a>

### 2026-09-26 · BIG STEP: from built-in features to a developer ecosystem



*AI-generated illustration of the developer ecosystem, not a lens photo. The data and UI in the image are examples, and the music template plays no audio. What is opened up is developer interfaces and bounded component capabilities, not unlimited system access. The matching TAP1 experimental firmware was released separately on 09-27; see the download entry at the top.*

**The point of this release is moving from "we build features for you" to "you can build features for the glasses too".** Within the components the matching runtime supports, new info cards or mini apps can be made from data and a ZIP, without changing the AP for every page. New system capabilities, low-level protocols or components outside the runtime still need firmware work; not just any web page or JS can be put on the glasses.

| What this opens up | What users can do with it |
| --- | --- |
| Dashboard components, JSON constraints and backend API | Lay out your own data, such as quotas, weather, calendar and device status, as info cards, reusing icons, progress bars and charts |
| Mini-app descriptions, package validation and native runtime reference source | Generate a ZIP with constrained pages and interactions; on a matching runtime, import it, query the four slots and launch the mini app |
| Self-hosted HTTP / Python / MCP | You keep the data sources and credentials, with no dependency on the author's private server |
| 20 offline templates, copyable prompts and Agent Skill | Start from existing examples and have an Agent generate, check and package within size, component and memory limits, instead of guessing the protocol from scratch |

**Changes:** the app gallery is reorganized into three entries. Opening 「我的应用」 (My Apps) queries the four slots automatically (subject to connection, busy and update-protection limits). 20 downloadable ZIPs with source notes were added, and the dashboard and mini-app backend developer guides, 12 MCP tools and the Agent Skill were completed. The phone research build also added a dashboard draft preview list; the public dashboard scope of this PR is the model and backend interface reference and does not include that full editor UI.

The app gallery has three tabs: **我的应用 / 应用广场 / 开发指南** (My Apps / App Gallery / Developer Guide). The four basic examples stay, and **20 editable offline templates** are added, covering weather, rain, commute, remaining train tickets, flights, calendar, to-dos, knowledge notes, reading notes, code and service status, and more. Each has an icon, content, integration requirements, a ZIP and a copyable Agent prompt. The glasses install at most four mini apps and run one at a time; gallery entries are not all installed automatically.

```sh
npx skills add Turbo1123/Turbo-IO --skill turboio-developer -g
```

Give the Agent your requirement and the selected template's prompt, and have it connect to **your own Server / MCP**, keep the minimum display fields, and generate and validate a small package. Keys always stay on the server. Development and packaging details for the phone, dashboard and app packages are all in the [developer guide](DEVELOPER_ECOSYSTEM.md), to keep commands out of the main README.

- **Dashboard SDK**: 256×194 cards with text / icons / images / progress bars / bar charts / line charts; backend drafts, revisions, publishing, phone approval and receipts.
- **App SDK**: 540×180, at most four pages; JS is used only for the build on the development computer; the ZIP's unpacked budget is 20 KiB. The glasses use bounded native components and do not run code from the ZIP.
- **Standalone backend**: HTTP API, Python SDK, 12 MCP tools, no dependency on the author's private services.

**Limits:** mini apps in this release use versioned snapshots and manual import on the phone. Automatic background refresh, button callbacks to the server and queue recovery are not wired up yet. The 20 templates are not 20 finished connected apps. The public API and packaging tools run on their own; the phone module is integration source, not a signed install package. The basic install of the private matching runtime has user test feedback, but this release publishes no new flashable firmware and does not treat simulator tests as lens acceptance.

**Opening up development does not remove the safety limits:** at most four installed apps, one foreground instance, at most four pages per package and at most 12 components per page; total unpacked budget 20 KiB, ZIP limit 24 KiB. Phone confirmation and protocol checks stay. The glasses do not run MCP or arbitrary scripts. API keys, cookies, signing certificates and private install packages are not published with the source. Run the template and backend tests on a computer first, then handle the matching phone and firmware integration. See [public scope and compatibility prerequisites](DEVELOPER_ECOSYSTEM.md).

[20 templates and their sources](../app-gallery/README.md) · [API and install steps](DEVELOPER_ECOSYSTEM.md) · Phone integration limits (deleted; see `git show b389cc6:official-addon/research/app-runtime-v1/README.md`)

<details>
<summary>View the app gallery UI</summary>


Screenshot from an isolated simulator. It is not a lens photo, and it does not mean an upstream MCP is connected.
</details>

<a id="focus-update"></a>

### 2026-09-25 · Mid-Autumn major update: new UI and FOCUS-04

1. **Menu rework**: four glasses menu items on one screen, a clear selection frame, time and battery in the top-left corner. Detail pages no longer show a leftover menu scroll indicator.
2. **Fixes for remaining firmware problems**: light touches on the music knob skipping tracks by mistake, text margins, WeChat Reading long-press back/exit, and Pomodoro page overlap.
3. **New native Pomodoro timer app**: the twelfth glasses menu item, with two-way control from the phone; short press to pause or resume, long press to stop. It keeps timing with the screen off and gives an idle reminder when time is up, so the screen does not stay lit and distracting.
4. **Turbo IO addon UI refresh**: home-screen glasses animation, music/WeChat Reading/navigation/Pomodoro cards, reorganized inner pages and settings. Only our own addon changed; the official app was not redone.

**FOCUS-04 firmware and build checks** · **Matching phone build and use (archived; see `official-addon/focus-edition/README.md` at commit `27ad86e`)** · **[Download experimental firmware](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tfp1-focus04)**

Based on Strix OS 1.0.4.12. Only AP content changes; the other 13 firmware payloads are unchanged. The AP is **9,558,216 bytes**, under the 9,600,000-byte limit. On 2026-09-25 a user flashed this build and confirmed it works. It is still experimental; that does not mean it is stable in every scenario, cannot brick, or can be guaranteed to unbrick. The matching host is RayNeo AI **iOS 1.0.5 (201)**; do not mix it with old packages or gates.



Full long update poster. UI illustration, not a lens photo. In the public build, WeChat Reading text must be imported lawfully by yourself.

<details>
<summary>View the home screen, Pomodoro timer and music images separately</summary>





The home screen is a simulated-environment UI; Pomodoro and music are design renders. They are not evidence of pixel accuracy or full acceptance on the device.
</details>

<a id="local-translation"></a>

### 2026-09-24 · Local translation and offline English captions

Publishes **Apple on-device translation, Hy-MT2 text translation and Parakeet offline English ASR**, with support for Bluetooth microphones the phone/system can use, fast pre-translation, and syncing the original and translated text to the glasses. It runs on the iPhone and **needs no service key and no glasses firmware flash**. It is a standalone captions entry, not a full replacement for all official translation features. It is an optional build for iOS 26+; on first use you prepare the models and system language packs yourself. No signed IPA or weight packages are provided.

[Download, build, signing and usage guide](../ios-addon/local-translation/README.md) · [Models and third-party licenses](../ios-addon/local-translation/THIRD_PARTY.md) · [Validation and limits](../ios-addon/local-translation/VALIDATION.md). English recognition is not multilingual ASR. The glasses' own front/surround directional pickup is not wired up yet. Capture runs in the foreground with a 20-minute protection, and there is no automatic cloud fallback. The public source has been compiled and tested offline; the full public package and the lenses still need acceptance by the user.

<a id="weread-research"></a>

### 2026-09-24 · WeChat Reading research: four-book shelf and native reading page

**New eleventh research menu item 「微信读书」 (WeChat Reading): a four-cover bookshelf, a native text window and manual/auto scrolling.** Published the original AP / phone modules, build and protocol notes, and the [TWR1 as-flashed experimental firmware](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-twr1). The AP rebuilt from source matches the flashed version; only the AP changes, and the other 13 payloads are unchanged. **The old TWR1 long-press back problem was fixed in FOCUS-04 on 09-25; the old Release is unchanged. Non-developers should not flash it; rollback and unbricking are not guaranteed.**

The phone module publishes the bookshelf/statistics, cover processing, TXT/EPUB import and reading transfer, **without the web-text adapter, cookies, keys or private IPA, and it is not yet wired into the main repo's default build or the TWR1 OTA packaging entry**. Do not flash until you have your own matching phone integration. This is not a claim that "download the source and you can read all WeChat Reading text directly". The bookshelf/statistics follow [Tencent/WeChatReading](https://github.com/Tencent/WeChatReading); for web reading you can study the AGPL project [finlater/weread.koplugin](https://github.com/finlater/weread.koplugin) yourself. [Architecture approach and license scope](archive/history/WEREAD_RESEARCH.md)



The integration limits above apply to the historical TWR1. The optional FOCUS-04 integration build added on 09-25 (archived; see `official-addon/focus-edition/README.md` at commit `27ad86e`) provides a matching build and a TFP1 packaging entry. The web-text adapter is still not public; the local TXT/EPUB import scope is unchanged.

*UI illustration (provided by a user): shows the menu, sync prompt, four-book shelf and reading layout. It is not device acceptance evidence. The books, text, page numbers and speed are examples only; see the research notes for the actual interaction.*

<a id="music-app"></a>

### 2026-09-23 · NetEase Cloud Music: the tenth glasses menu item

**Passed testing on the research device on 2026-09-23**: the matching iOS player has sound, cover art and lyrics. The glasses show a spinning album cover and **five lines of lyrics, with the current line always highlighted in the middle**; pause/resume, track skip and seeking stay in sync. The code supports both playback started from the phone and reverse requests from the glasses. Automatic relaunch after the system kills the app is not guaranteed.

- **New tenth menu item for music**; the original seven items, the eighth (Turbo Display/ANIM60) and the ninth (native navigation) stay.
- The phone fetches playable songs, covers and lyrics and plays the audio; the glasses AP draws natively, with no continuous full-screen screenshots. Optional display: always on / 30 s / 60 s.
- **Known problem in the old TMU1: a light touch on the knob may skip a track by mistake. FOCUS-04 on 09-25 added input filtering and debounce; the old Release is unchanged.** QR-code login may report 「环境异常」 (environment abnormal). This round was accepted with songs that play without login; risk controls, membership and copyright limits are not bypassed.
- Targets **RayNeo AI iOS 1.0.5 (201) + Strix OS 1.0.4.12**. Android / HarmonyOS do not have this music player yet.

**Full guide: build, signing, test flash, playback and protocol** · **[Download TMU1 tested firmware pre-release](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tmu1)**. Source, the exact tested firmware and the checking tools are published; no merged IPA, personal signing, keys, accounts or cookies.

> **Experimental; for non-commercial developer study and research only. Non-developers, do not flash it!** Only AP content changes; the other 13 items keep the stock bytes, and the manifest updates the AP Size/MD5. That does not mean the OTA writes only the AP, nor that it cannot brick. Power loss, an interruption or the wrong firmware can leave the glasses unable to boot or lose OTA; rolling back to stock is no unbrick guarantee. Passing tests does not make it a stable production release. Ordinary SDK/App development does not need a firmware flash.

<a id="native-apps"></a>

### 2026-09-22 · Turbo Display and the native navigation app

**This is more than "sending navigation test text to the glasses": the glasses get a standalone navigation app page.** **Turbo Display stays as a developer image-transfer and display test tool, not a display app for daily use.** The new navigation is an app page with its own menu entry, layout and run state. The two have different roles.

| Feature | Turbo Display · display test (Test) | Native navigation · TNV1 |
| --- | --- | --- |
| What it is for | Verify image transfer, pixel rendering, partial updates and the display protocol | The phone plans the route; the glasses draw the navigation UI natively |
| Glasses entry | Eighth item **Turbo Display** | New ninth item **导航** (Navigation); the original seven items and Turbo Display stay |
| How it updates | The phone processes the image and sends a full image or partial pixel updates | The phone sends turns, distance, road name and route points; the glasses draw with LVGL |
| What it shows | The current 512×128 grayscale canvas; the lens shows a green monochrome image | 540×180 layout: direction arrow, distance, road name, remaining info, route sketch |
| Good for | Development debugging, test images and protocol acceptance; not a daily app or video mirroring | Continuously changing navigation guidance, without sending a whole navigation image each time |

#### Navigation app: own entry and native drawing

- **Own entry and lifecycle**: the glasses menu has 「导航」 (Navigation). Once the phone starts navigation it can open the page directly, without going through the official captions or teleprompter first each time.
- **Native drawing on the glasses**: built-in turn icons, text and route sketch. The phone sends only navigation data, at most **328 B** per full snapshot, which reduces the bandwidth load of the old image-transfer approach. This is no guarantee of zero latency.
- **Amap provides the route, the glasses show the guidance**: the phone has planning/navigation entries for walking, cycling and driving. The route sketch is not a full Amap base map or a real-world junction view.
- **Display and exit handling**: implements stop/physical-back wrap-up, screen off after about 60 seconds without a valid update, wake on key press and optional always-on. Each branch still needs wider acceptance; there is no promise that the screen never turns off.
- **Background navigation no longer exits immediately**: the matching iPhone Air build got a normal report from a user. Real navigation uses background location as authorized; simulated background was only tested briefly. See [background behavior and limits](archive/history/NAVIGATION_BACKGROUND.md).

"App-level" here means **a native app page integrated into the firmware application, with its own menu and interaction**, no longer borrowing the old test UI. It does not mean that Android-style APK installs, loading arbitrary third-party apps or replacing the whole system UI are open.

**Device progress (2026-09-22)**: Turbo Display full-image and partial updates have lens feedback. TNV1 was flashed and the standalone navigation page opened; navigation started from the phone and the background fix got initial normal feedback from a user. A new app is not a stable production release; long runs, all modes, low battery and fault recovery still need dedicated testing.

**The matching TNV1 build is public:** [Download high-risk firmware pre-release](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-tnv1) · Full source, build and phone merge · Update, navigation and image-transfer test notes. This package keeps the **Turbo Display test tool** and adds the **standalone native navigation app**, with matching iOS 1.0.5 (201) source and the background fix. Only AP content changes; the other 13 items are unchanged. Use your own config and signing; no merged IPA is provided. The old R3 Release has neither feature and cannot be mixed in. **Non-developers should not flash it. Success on a device does not mean it cannot brick or that unbricking is guaranteed.**

<a id="animation-test"></a>

### 2026-09-22 · ANIM60: local animation on the glasses (experiment)

ANIM60 is **a separate experimental AP** based on the same Strix OS 1.0.4.12. It reuses the eighth item, Turbo Display, has 12 built-in frames and draws them on a timer on the glasses, so the phone does not send each frame. On 2026-09-22 it was flashed on the research device; a user confirmed the animation plays, and after 30 seconds the counter showed 1799 submits. That is a **submit count** of about 60 per second, not a measurement of 60 FPS on the physical panel, and it does not prove long-term thermal stability or no dropped frames in every case. It is not a GIF uploader or an animation app for ordinary users.

View asset previews, test limits, AP checksums and offline rebuild · [ANIM60 high-risk experimental firmware pre-release](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-anim60). ANIM60 and TNV1 are different firmware candidates; do not mix their update authorizations or phone gates. The public source does not currently provide an ANIM60-specific phone OTA entry. **Ordinary SDK/App development does not need a firmware flash.**

> **For non-commercial developer study and research only. Risky; not a daily navigation product.** Do not operate or test it while driving, cycling or crossing the road; disconnects, delay, stale guidance or screen-off can happen. Custom firmware can also leave the glasses unable to boot or lose OTA; rolling back to stock is no unbrick guarantee. Ordinary SDK/App development does not need a firmware flash.

<details>
<summary>Early R3 firmware validation: why change only the application?</summary>

> **Experimental, not daily firmware. Non-developers should not try it; do not flash it casually.** This round tests whether a modified AP can run through the official OTA and whether glasses pages can be developed that show a PNG. It is not firmware for its own sake, and not a recommendation to replace the official system.

On 2026-09-21, Turbo Photo R3, based on **Strix OS 1.0.4.12**, was confirmed on a real device by a user: after the update it showed a custom image, and the image page could be exited and entered again. Only the AP payload changed; the other 13 items are unchanged. This does not mean a full OTA writes only the AP. **Rollback and unbricking are not guaranteed**: power loss, an unexpected interruption, a version mismatch or wrong code/resources can all leave the glasses unable to boot or lose OTA. Do not advertise it as "almost unbrickable".

**Why change only the application (`nuttx_ap.bin`)?** The target code for menus, pages and PNG display is in the AP. Limiting changes to it first and keeping the other stock components reduces variables and extra risk, and tests the glasses' app/UI extension ability rather than rewriting the system. The AP is not an isolated sandbox; mistakes can still stop the whole device from booting. "AP only" is no guarantee against bricking. Design trade-offs

**Research process, source, known problems and offline tests** · **[Experimental firmware pre-release and checksums](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-turbophoto-r3)**. Ordinary SDK/App development does not need this firmware. R3 tests only the embedded image page and does not include the later TDP1 image transfer or TNV1 navigation. It is not a general glasses app install system, and long-term stability and fault recovery were not tested.

</details>


## 2026-10-14 feature comparison across platforms (historical)

### Which phone version to choose (2026-10-14)

**New fixed pair: official iOS 1.0.6 (218) + TMIG1 / Strix OS 1.0.5.5**; see the new adaptation guide (archived; see `official-addon/tmig1-edition/README.md` at commit `27ad86e`). Its iPhone 17 Pro Max test does not extend automatically to old Android APKs, old iOS gates or other phone models. The historical versions below keep their own compatibility limits.

The table compares **what is currently public and how it is integrated**, without mixing up "has source", "is packaged" and "fully passed on a device". V1/V2 are architecture routes and 1.0.5 is the official host version; GUARD-07, FOCUS-04 and TAP1 are different extension/firmware labels, not one series of version numbers.

| Difference | Android 1.0.5 · GUARD-07 | iOS official extension · V2 | iOS standalone SDK · V1 | HarmonyOS |
| --- | --- | --- | --- | --- |
| Delivery | **Full experimental APK + source** | **Source**; merge and sign it yourself; no merged IPA | SDK + example client source | Historical source, no HAP; **no longer updated** |
| Connection / ASR | Reuses the official host's connection and ASR | Reuses the official host's connection and ASR | Own connection, own ASR | Own connection, own ASR; historical acceptance |
| Own model / search / TTS | Config and implementation integrated; bring your own credentials | Models, TinyFish, on-device/cloud TTS; enable per the build notes | Own model/voice route; not the same as V2's full module set | Keeps its existing own voice; does not follow new modules |
| Music / reading / native navigation / Pomodoro | Matching phone modules integrated; needs the matching experimental firmware | Matching public modules exist; FOCUS-04 provides an optional integration build; do not mix in historical candidates | Not a fully integrated feature of this route | No port of the current native apps |
| WeChat Reading text | **Local TXT** and original samples; no web-text/cookie entry | FOCUS-04 supports local **TXT / EPUB**; no web-text adapter | Not the same WeChat Reading client | The current reading app is not ported |
| Local translation / offline ASR | **Not ported**; cloud captions configured separately | **Optional iOS 26+** Apple / Hy-MT2 / Parakeet module; bring your own models and language packs | This standalone module not wired | Not wired |
| Dashboard / four-slot app gallery | The current APK integrates the entry and 20 offline templates; needs TCE1/TAP1 | Protocol and phone reference module are public; **integrate them yourself**; the old FOCUS-04 does not include them | Not provided by default | Not followed |
| Flashing | Current Release fixed to TAP1-TEST-01, through the official OTA; **after flashing, check by hand and release the protection** | Fixed firmware/gate matching the chosen iOS integration build; build and sign it yourself | No current Android OTA workflow | No current flash flow |
| Acceptance limits | The private predecessor flashed fine on Fold3 / Android 15; the public trimmed APK passed build and audit but was not flashed again | Each module has its own research acceptance; the public rebuild, signing and the chosen pair still need verification | Only V1's recorded results apply | Mate X5 / HarmonyOS 6.1 historical results; new firmware not guaranteed |

**Shared limits:** bring your own model, map and other config. Handle WeChat Reading and NetEase Cloud Music login and service permissions yourself. No private credentials, no logging in on your behalf and no risk-control bypass. Cloud services, system permissions, long background runs and other phone models may behave differently; success on one platform does not prove another has been verified.

### How the glasses firmware differs

| Firmware / runtime | Main capabilities and use | Requirements |
| --- | --- | --- |
| **Stock Strix OS** | Official menu and features. Phone extensions can use the existing text/captions channels, but there is no native new menu of ours, no TCE1 graphics editor runtime and no TAP1 four-slot apps | First choice for ordinary users. Keep the official app and firmware; the stock limited cards are not the new dashboard SDK |
| **FOCUS-04 / TFP1** (historical experimental) | Four-item menu on one screen, native Pomodoro; includes fixes to music/reading interaction and more. **Does not include the later TCE1/TAP1 runtime** | The FOCUS-04 iOS integration build (archived; see `official-addon/focus-edition/README.md` at commit `27ad86e`) with that Release's fixed firmware; not an upgrade candidate for Android GUARD-07 |
| **TAP1-TEST-01** (current Android experimental release) | The earlier TAP1 bounded four-slot mini-app runtime and dashboard capabilities. Compared with spacefix-c it only changes the menu marker so it shows "TEST"; it is not a new feature rewrite | GUARD-07 APK + the exact ZIP from the same Release; the TCE1/TAP1 phone bridge must match. It cannot be flashed with the FOCUS-04 iOS gate directly |
| **R3 / TDP1 / TNV1 / ANIM60 / TMU1 / TWR1** (historical research packages) | Research into images, image transfer, navigation, animation, music and reading respectively; each matches its source and acceptance at the time | Firmware research index. These are not "patches" to install in order; flashing each one to keep up is not recommended |

**Newer firmware does not mean you can upgrade freely.** FOCUS-04 and TAP1-TEST-01 are both based on Strix OS 1.0.4.12, so the system version number may not change. You must check the Release name, SHA-256, host and gate, not just "1.0.4.12". All custom firmware is high-risk and experimental; rollback and unbricking are not guaranteed.

### Historical per-item acceptance records

Below is the **2026-09-24 historical comparison**, kept for traceability. Do not use it to judge whether the current Android build has been ported. The current scope is the table above in this section and each module's docs. HarmonyOS is no longer updated.

**Tested** = device/lens feedback for that route; **Partial** = only part of the flow passed, or known problems remain; **To verify** = code exists but the device loop is not closed; **Not wired** = not integrated in this route; **Official** = uses the host's capability, which does not mean the extension rewrote or re-accepted it. Feedback on historical private predecessors does not guarantee that your own build, other firmware or other phone models all work.

<details>
<summary>Expand the 09-24 historical feature and acceptance comparison across four platforms</summary>

| Feature | iOS standalone SDK · V1 | iOS official extension · V2 | Android official extension | Native HarmonyOS |
| --- | --- | --- | --- | --- |
| App form / connection | **Tested**: standalone pairing, reuses the vendor communication library | **Official**: keeps login, pairing and connection | **Official**: keeps login, pairing and connection | **Tested**: native standalone pairing, auth, initialization |
| No jailbreak / no root | Verified on a non-jailbroken iPhone | Verified on a non-jailbroken iPhone; needs a compatible unencrypted input | Verified on a non-rooted device; needs a compatible APK | No root needed; verified on Mate X5; no official package needed |
| Speech recognition ASR | Own Alibaba streaming ASR / cloud VAD | Uses the official ASR | Uses the official ASR | Own Alibaba streaming ASR / cloud VAD |
| Local translation / offline English captions | **Module not wired** | **Optional iOS 26+**: Apple / Hy-MT2 translation, Parakeet English recognition; public build and tests passed, the full chain on a device is to be rechecked | **Not wired** | **Not wired** |
| Own model → answer on the lens | **Tested**: streaming display | **Tested**: streaming display | **Tested**: streaming display | **Tested**: currently not SSE; fetched, then shown in segments |
| Spoken answer TTS | **Extension not wired** | **Private cloud build tested**: official and own answers each read aloud in full once; **on-device default mode awaits a listening check on the lens** | **Not wired** | **Not wired** |
| Music cover / five-line lyrics · TMU1 | **Not wired** | **Tested**: optional music build + TMU1 firmware; knob accidental track skip is a known problem | **Not wired** | **Not wired** |
| Barge-in / auto-close after the answer | **Tested** | **Partial**: research tests; depends on official session events | **Tested**: passed on the research device | **Partial**: exit verified; WB14 barge-in change to be rechecked |
| TinyFish web search | No dedicated tool | **Tested**: needs your own key | **Tested**: needs your own key | **To verify**: tool code wired, off by default |
| Codex / knowledge base | **Tested**: send tasks, check results, completion notifications | **To verify**: read-only service/Tools exist; the public build's full chain not fully verified | **To verify**: query/status adapter code exists | **Not wired** |
| Recording and text export | **Partial**: short recording receive and manual ASR passed; long recordings/full sharing not fully verified | **Partial**: local audio sharing, transcript cleanup; the complete official history is not guaranteed | **Partial**: local recording selection/sharing verified; full Lifelog not rebuilt | **Partial**: recording started from the glasses works; recording started from the phone and full export to verify |
| All-day Lifelog | **Partial**: time-limited protocol experiment, not a full all-day product chain | **Partial**: export of clips after saving is turned on; historical audio is not backfilled | **Not fully ported** | **Full chain not finished** |
| To-do push / two-way sync | **Partial**: add/send works; completion sync back from the glasses still has problems | **Partial**: creation by natural voice verified; the full two-way web chain not fully verified | **Official** to-dos; extension two-way sync not fully ported | **Partial**: push to the lens verified; reverse completion to verify |
| Teleprompter / AI news | **Partial**: script transfer, TXT/EPUB manuscripts; news generation not wired | **Partial**: long news script scrolling verified; restart preparation/speed not fully verified | **Official** teleprompter; AI news not fully ported | **Known problem**: unknown error in the glasses menu; list handshake incomplete |
| Weather → glasses home screen | **Partial**: own weather wired, partial lens acceptance | **Official**; not counted as a standalone weather port | **Official**; not counted as a standalone weather port | **Partial**: simulated weather verified on the lens; the live service needs config and a recheck |
| Map search / routing | **This repo's navigation module not wired** | **Partial**: map search and entries for three modes; not each mode fully verified | **Tested**: map/search; all three modes return planned routes | **Partial**: POI/walking routing verified; white screen on the phone base map |
| Navigation → continuous guidance on the glasses | **Not wired** | **Partial**: simulated guidance verified on the lens, 4-minute protection | **Partial**: real route text verified; the new simulated mode to verify, 4-minute protection | **Partial**: walking simulation verified on the lens; cycling/driving to verify |
| Real outdoor / long background navigation | **Not wired** | **Not fully accepted**; not a finished capability | **Not fully accepted**; foreground research guidance | **Not fully accepted**; navigation stops when leaving the page or in the background |
| Proactive custom text notifications | **Tested**: manual and Codex completion notifications; not APNs | Extension proactive push not finished; APNs not wired | Extension proactive notifications not fully ported | **To verify**: manual command and master switch wired |
| Forwarding other apps' system notifications | iOS system shared notifications; needs user authorization | Uses official/system permissions; official push after re-signing not guaranteed | Uses the official notification capability and permissions | **Not implemented**: needs a restricted subscription permission, an extension and user authorization |
| Web display observation | **Tested**: USB state observation + style preview; not pixel mirroring | V1's observation ability is not applied directly | V1 observation interface not migrated | V1 observation interface not migrated |

</details>

**Default stock firmware and custom firmware are two routes:** the limited card/notification templates on stock firmware do not mean the system UI can be replaced freely. The custom AP route has grown to Turbo Display and a standalone navigation app, but it needs matching firmware and a matching phone implementation and cannot be applied directly to all four platforms. Claude Code, Hermes, WorkBuddy and OpenClaw also cannot be considered connected just because they appear as dropdown options.

Detailed evidence and usage limits: [iOS V1](archive/v1/v1-sdk.md#能力与边界) · iOS V2 · Android current release · HarmonyOS historical acceptance. Android provides a full experimental APK with its own research signature. iOS still needs you to merge, build and sign, and no merged IPA is provided; HarmonyOS provides no HAP. You prepare the service config for each platform yourself.

## Versions and history

Recent features are listed by date in the [updates section](#updates). Below are each platform's historical adaptation records; they were not re-accepted for this page.

<details>
<summary>Expand iOS / Android / HarmonyOS version records</summary>

- **iOS 1.0.5 (201) + Strix OS 1.0.4.12**: adds exact version / Build / UUID adaptation for the new host and keeps 1.0.4 and 1.0.2. The private research build on a non-jailbroken iPhone Air was installed and the extension load confirmed. After the user finished the official firmware update they reported "everything normal", and no feature problems caused by the update have been reported so far. That report is not a full regression conclusion for all features, long background runs or other platforms. Compatibility, update steps and acceptance limits

- **Native HarmonyOS source first published · WORKBENCH 14**: standalone BLE connection/initialization and own voice model verified on Mate X5; simulated weather, to-dos and custom card push passed. Amap native POI search, walking routing, simulated navigation callbacks and glasses display passed this round. 243 local tests passed. **The phone map base map is currently a white screen, and cycling/driving on a device and real outdoor navigation are not accepted yet.** Recording and teleprompter still have unfixed problems; system notification forwarding is not implemented. Install and use · Per-item acceptance status

- **Android source newly published**: compatible with official Android 1.0.4 (195); **a user verified on a real non-rooted device that it works**. Model/search/recording export and route text have user confirmation on the research device. Simulated navigation supports pause and 1/2/4/8× speed, and automated tests passed; the new simulated lens view awaits acceptance. Still source only: compile and sign it yourself; it is not a prebuilt package.
- **iOS 1.0.4 + Strix OS 1.0.4.8**: keeps iOS 1.0.2 support. The personally signed research build on a non-jailbroken iPhone passed regression for voice, own model and navigation. Adds an adaptive frosted-glass TurboIO bottom bar. Compatibility and preview
- **Navigation**: three travel modes, map search and text guidance on the glasses; not map mirroring. iOS fixed phone navigation stopping as soon as it left the foreground; real routes enable background location as authorized, and simulation was only tested briefly in the background. The private iPhone Air build from the same source got initial normal feedback; long background runs and each display channel of the public build still await dedicated acceptance. The old captions 4-minute/80-frame limit and foreground protection remain. **Experimental feature with risks of disconnects, delay, stale guidance and screen-off. It does not replace real navigation; do not test it while driving.** [iOS background fix and limits](archive/history/NAVIGATION_BACKGROUND.md) · [iOS navigation](archive/history/NAVIGATION.md) · Android navigation

</details>

Model keys, search keys, cloud TTS keys, personal prompts and private knowledge bases are configured by the user; on-device TTS needs no service key. The only binary exceptions are the [stock decrypted IPAs listed on the home page](../README.md#ios-原厂砸壳-ipa-下载) and the separately warned R3, TNV1, ANIM60, TMU1 and TWR1 experimental firmware / stock-content baseline Releases. No merged phone packages or personal signing material are provided. Copyright in the stock code and resources inside the firmware is unchanged; the experimental attachments are not official update recommendations; unknown binary versions must not skip compatibility checks. iOS version/UUID details are in the [V2 doc](../official-addon/README.md#1-兼容性门槛); Android input checks are in the Android doc.
