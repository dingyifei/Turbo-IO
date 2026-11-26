# V1: standalone SDK and sample client

> Archived: the V1 client code (apps, core-probe, codex-bridge, display-observer, rayneo-session, rayneo-archive, third-party) was removed from the source tree in cleanup(2) and is kept in git history. This page is a record only; its commands and paths no longer work.

Moved out of the [project home page](../../../README.md). The content is kept as it was (now in English); only the links were fixed, and phrases such as "above" that pointed at home-page content were turned into links.
This page covers the **iOS V1 standalone SDK**. Its notification, Codex and recording acceptance results do not carry over to other platforms.


V1 is the unofficial SDK's sample iOS client and research tool, for connecting to the glasses on its own, voice, recordings, notifications and agent integration. You build, sign and configure the services yourself; it is not a consumer app you can install directly. Its features are accepted separately from the other platforms, and it follows the [non-commercial license and privacy limits on the home page](../../../README.md#隐私与许可).

An unofficial RayNeo iO smart glasses SDK for developers, with a sample iOS client—not a ready-to-install consumer app. Build, sign and configure your own services to explore voice AI, recordings, custom notifications, Codex integration and a read-only web display observer.

**Before connecting the V1 standalone client, unbind the glasses in the official RayNeo app, then choose "忽略此设备" (Forget This Device) for them in the phone's Bluetooth settings, then put the glasses back into pairing mode and connect Turbo IO.** See [Read before connecting](#read-before-connecting-unbind-then-forget-the-bluetooth-device) below. A user has accepted this on a real non-jailbroken iPhone.

> This project is only for technical users who know iOS development, signing, API configuration and basic debugging, and it is for interoperability research. If you want something that works out of the box, or you are not familiar with these steps, use the official app. Some features are still being verified; research and real-device results are welcome. It does not promise to replace every feature of the official app.

## Screenshots

These are real screenshots of the project running. The phone shows an isolated simulator page with no account and no keys; the web view uses clearly labelled demo style data. They are not pixel captures of the glasses, and they do not mean the glasses were connected when they were taken.


## Web display preview and observer

The source includes a browser-side display observer for studying the RayNeo iO page state and two-way events:

- **Live follow**: reads the real page and state reports through a temporary observer endpoint on the phone and USB forwarding, and tells glasses reports apart from content the app has submitted.
- **Style preview**: home, conversation, single-page app menu and notification templates; the menu preview steps through the seven app icons one page at a time.
- **Clear limits**: this redraws protocol state. It is not a lens recording or screenshot, and it does not change the glasses UI; switching preview styles sends no control command to the glasses.
- **Privacy**: local and read-only. Message text is left out by default, text observation needs separate consent, and the temporary endpoint expires. A stale snapshot from before a disconnect is never shown as live.

The images below show the conversation and menu styles. "观察接口失联" (observer endpoint lost) means no phone was connected when they were taken; it does not affect viewing the demo layout. For startup and USB setup see the [configuration doc](CONFIGURATION.md).

The style preview alone needs no phone, iproxy or service keys:

```sh
node display-observer/server.mjs --no-proxy
```

Open `http://127.0.0.1:8790/` and choose "首页样式 / 对话样式 / 菜单样式 / 通知样式" (home style / conversation style / menu style / notification style). Only live follow needs the phone's temporary observer endpoint and USB forwarding.





## What it can do

**The capabilities below belong to the V1 iOS research build.**

- Use your own services for glasses speech recognition, streamed AI answers and barge-in within a session; save a text timeline of chats.
- Receive glasses recordings, save them on the phone, start cloud transcription by hand, and export audio and text.
- Send to-dos, teleprompter text and weather; import TXT / EPUB as local manuscripts.
- Send custom notifications, and push results of computer tasks to the glasses.
- Use the glasses as the voice input and result display for an agent. The one that actually works today is **Codex**; other agents need an adapter. See the table below for status.
- Observe the page and state the protocol reports through USB + web, to help study two-way interaction. This is not a glasses screenshot.

## Agent integration: built and possible

| Agent | Current status | Approach |
| --- | --- | --- |
| Codex | Built, with real-device records of starting tasks from the glasses, querying results and completion notifications | Phone tool call → this project's HTTP bridge → Codex app-server → task events → glasses |
| Claude Code | No adapter, not tested | A computer-side adapter could be studied through the Claude Agent SDK or a CLI subprocess |
| Hermes Agent | No adapter, not tested | Its programmatic entry point / message gateway could be studied and mapped to the phone's common task and event interface |
| OpenClaw | No adapter, not tested | A Gateway protocol adapter could be studied, covering auth, tasks, events and permissions |
| WorkBuddy | Could in theory be studied, not tested | First confirm a usable API / extension or automation entry point; there is no guarantee one exists today |

These directions are based on each project's public entry points and **do not mean this repo has built in or verified these adapters**. References: [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview), [Hermes Agent](https://github.com/NousResearch/hermes-agent), [OpenClaw Gateway](https://docs.openclaw.ai/gateway/protocol). You set up and confirm each service's account, permissions, costs and terms yourself; swapping in another agent's name will not make it run.

## What it cannot do

### Why can't it be customised freely like Android glasses?

The RayNeo iO studied here uses the **BES2800** platform, which follows a low-power, lightweight embedded firmware route, not a full Android application system. Think of it as a wearable input and display terminal: the glasses handle wake, audio and the built-in UI, and the phone, cloud or computer handles the heavier recognition, model and agent work. It is not a tiny phone that can install any APK, replace the launcher or run any Android UI.

On the **stock firmware route**, you mainly fill the glasses' built-in templates with content and send control commands over the protocol. The **custom AP route** has added Turbo Display and native navigation, which shows that drawing and app pages on the glasses can be extended; the two routes have different prerequisites and risks. **The limits come from the current firmware and the available communication interfaces; they do not simply mean the BES2800 has no graphics capability.** Bestechnic positions the BES2800 series as an ultra-low-power wearable computing platform, and optional specs of other models in the series do not mean these glasses have all of them. For chip background see [Bestechnic's official introduction](https://www.bestechnic.com/en/content/2.html).

### Current limits

- **The everyday SDK/app cannot replace the firmware's built-in UI at will over the normal protocol, and it is not a flashing or custom-launcher tool.** Besides custom notifications, research has verified limited A2UI dashboard text/layout cards; HarmonyOS is currently verified only up to short text cards. The separate [custom AP app route](../history/TURBO_DISPLAY_NAVIGATION.md) has built image transfer and native navigation, but that is not an HTML/Canvas runtime or general third-party app installation.
- On stock firmware, conversation, to-dos, teleprompter, weather and similar features mainly send content through existing templates. This does not rule out the new drawn pages in the custom firmware, but it also does not mean every stock template can be changed at will. The web preview styles do not become lens firmware UI either.
- **The standalone client cannot compete with the official app for a connection to the same glasses.** The V2 official extension reuses the host app's connection; do not unbind again and again to add navigation.
- No guarantee of complete offline recording, lossless back-fill of any length, background connections that never drop, reliable push after a force quit, or compatibility with every firmware.
- No migration of official history data, no pixel-level lens screenshots, no voice auto-approval of high-risk computer actions; automatic filing into NAS / Obsidian is not finished.

Unfinished or still-buggy features will keep being marked, and a success receipt is never treated as lens acceptance. Scrubbed logs, repro steps and PRs are welcome; do not upload your own keys, recordings, chats, device identifiers or other people's private data.

## Quick start

### Guided install with a Codex / Claude Code skill

If you have Node.js and the matching coding assistant installed, one command installs the `turbo-io` skill (user level, for both Codex and Claude Code):

```sh
DISABLE_TELEMETRY=1 npx --yes skills@1.5.24 add Turbo1123/Turbo-IO --skill turbo-io -g -a codex claude-code --copy
```

Confirm the targets in the installer, open a new assistant session and ask it: **"Use the turbo-io skill to install and start Turbo IO for non-commercial study, and run the web preview that needs no glasses first."** In Claude Code type `/turbo-io`; in Codex pick the skill in the skill picker or mention it explicitly.

The skill checks the environment, fetches the source and starts the preview, then guides you through the iOS build, service configuration and Codex bridge as needed. **The one-line install gives you the skill, not a signed iPhone app**: a real device still needs your own Xcode signing, pairing and service keys. Claude Code being able to use the skill does not mean a Claude Code backend adapter for the glasses exists. Full instructions and manual install.

### Read before connecting: unbind, then forget the Bluetooth device

**This applies only to the first pairing when switching the V1 standalone client over from the official app; the official app extension does not need an unbind. Before using V1, finish these steps before you try to connect:**

1. In the official RayNeo app, run "解绑" (Unbind) on these glasses and confirm it finished. Just closing the official app is not an unbind.
2. Open the phone's "设置 → 蓝牙" (Settings → Bluetooth), find the RayNeo glasses, open the device details and choose "忽略此设备" (Forget This Device) to clear the old pairing record.
3. Put the glasses back into pairing mode (hold the button for about 5 seconds and check that the blue light flashes), then pair and connect inside Turbo IO.

Do not let the official app and Turbo IO connect to, or compete for, the same glasses at the same time. Once the glasses are bound to Turbo IO, everyday reconnects do not need the unbind, forget or reset again. Users who only use the simulator preview do not need to touch the glasses.

### Build and run

Have macOS, Xcode, XcodeGen, Node.js and a working simulator ready, and run this from the source root:

```sh
node scripts/start.mjs --local
```

Choose `RayNeoCompanion` + a simulator and click Run in Xcode. This path needs no vendor libraries, glasses or cloud keys, and you can use the local pages, files, to-dos and library. ZIPFoundation 0.9.20 is bundled as a local source dependency; you install Xcode and the runtime yourself.

To connect real glasses use:

```sh
node scripts/start.mjs --device
```

The existing vendor framework, Opus static library/headers and WebRTC VAD build sources that the device build needs ship with the project; the version list is in `DEPENDENCIES.json`. The script prechecks the dependencies and regenerates the restored interface declaration module; it lists any missing file explicitly. In Xcode choose `RayNeoCompanionDevice`, set your own Team, connect your own iPhone and build and run. For detailed steps and API configuration see [Configuration and startup](CONFIGURATION.md).

## Using it after setup

1. When switching from the official app, first finish the unbind, Bluetooth forget and re-pairing above. Glasses already bound to Turbo IO only need a reconnect/auth on the device page; do not keep resetting.
2. On the voice service page, enter your own ASR Host / Key and DeepSeek Key, then turn on standby.
3. After wake, the recognised text and the model's answer stream onto the display, and a valid new sentence within the session can barge in.
4. Recordings are saved on the phone first, and are uploaded to your own ASR only when you tap transcribe. Chat text is under "会话 → 对话时间轴" (Session → Conversation timeline).
5. Configure Codex, weather and USB observation separately as needed; do not use one service's key as a general token.

The source has no default developer tenant or credentials. The services you provide must support the protocols/models currently implemented; changing to another API name is not promised to work. The iPhone target is currently iOS16+, and the standalone public transport package needs a Swift6.2+ toolchain.

<a id="能力与边界"></a>

## Capabilities and limits

| Capability | Status |
| --- | --- |
| Standalone app binding/auth/connection recovery | Real-device records on the vendor-library reuse route; a user has accepted it on a real non-jailbroken device |
| Cloud ASR/VAD, DeepSeek streaming, continuous barge-in | Passed on a real device; the new configuration entry needs acceptance on your own services. The V2 official extension also has TTS: the private cloud version is tested on a real device, and the on-device default mode awaits a listening check |
| Normal recording→WAV, manual ASR→Markdown | Short recordings passed on a real device; wireless lossless, long recordings and fully offline recording start are not guaranteed |
| Chat timeline, local to-dos, TXT/EPUB | Built; official history is not imported, and system Reminders are copied one way |
| Reverse sync of glasses to-dos | Currently has a bug where completion status does not come back to the app |
| Teleprompter, weather, notifications | Connected, partly accepted on the lens; not every icon/knob/layout is covered yet |
| Codex send task/query result/proactive reminder | Real-device records; no APNs, voice auto-approval not enabled |
| All-day memory | Time-limited experiment: raw packets/computer decoding/ASR comparison; not a full all-day product chain |
| Display observer | Real page state→USB→web; not a lens screenshot |
| NAS/Obsidian automatic filing | Not finished; a local export base exists |


## How it was made

First the official app's structure and real interactions were analysed, separating connection auth from business messages. The communication core was reused to get a standalone client working quickly, and then the logic that could be pinned down was split into Swift packages: protocol, session, transport, display, archive and so on. The glasses do input/display, the phone does connection/audio/state, the cloud does recognition and models, and the computer runs Codex.

The glasses-side app route changes only the AP: Turbo Display receives pixels, TNV1 receives navigation data and draws it on the glasses, and ANIM60 keeps frames inside the AP and draws them on a local timer. Each extends the display in a different way. The other 13 firmware payloads are not modified, but a full official OTA may still write the unchanged payloads.

Full explanation and pitfalls: [Implementation notes](ARCHITECTURE.md) · [Turbo Display and native navigation](../history/TURBO_DISPLAY_NAVIGATION.md). They explain how the evidence was built, why a successful send cannot be taken as a successful lens display, and why there is no rush to rewrite the whole communication layer for now.

## Tests

```sh
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
xcrun swift test --package-path rayneo-session
```

More steps are in the [configuration doc](CONFIGURATION.md). Local passes, normal signing, real lens and non-jailbroken acceptance are recorded separately; no fixture containing a developer's recordings or accounts is used.

Build and test records for the source already delivered are in [Delivery validation](VALIDATION.md); this README cleanup did not re-run the per-platform builds or real-device tests.
