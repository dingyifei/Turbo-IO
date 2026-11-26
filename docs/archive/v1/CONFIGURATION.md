# Configure and start from source

> Archive: the V1 client code (apps, core-probe, codex-bridge, display-observer, rayneo-session, rayneo-archive, third-party) was removed from the source tree in cleanup(2) and remains in git history. This file is kept as a record only; its commands and paths no longer work.

## 1. Choose the right entry point

- To see only the UI, local files, to-dos, the library and the logic: use the local build. It needs no glasses, no cloud keys and no vendor framework.
- To connect real glasses: use the device build. It uses the existing communication dependencies, your own Apple signing and your own device. It is not currently an SDK rewritten from scratch.
- No IPA, pre-signed app or developer key is provided. Each user configures and builds it themselves.

First install and set up Xcode, XcodeGen and Node.js, and prepare a working iOS simulator in Xcode. The app's minimum deployment target is iOS 16. The toolchain must satisfy each Package.swift; the standalone transport package needs Swift 6.2+. Node must support fetch, ESM and node:test; no fully verified minimum version has been defined yet.

This verification used Xcode 27.0, XcodeGen 2.45.4 and Node.js 26.3.0. System developer tools are not distributed with the source; the vendor framework, Opus, VAD and ZIPFoundation are all included. The Codex or other agent runtime, and the iproxy needed for USB observation, are external tools installed as needed. They are not app build dependencies.

## 2. Start the local build

Run from the source root:

```sh
node scripts/start.mjs --local
```

The script checks the tools, generates the project from `apps/RayNeoCompanion/project-source.yml` and opens Xcode. Select `RayNeoCompanion` and a simulator, then click Run. The public release ships ZIPFoundation 0.9.20 as a local source dependency, so there is nothing extra to download. The script does not install to the phone, does not pair, does not read system Reminders and does not call a model.

Command-line build:

```sh
xcodegen generate --spec apps/RayNeoCompanion/project-source.yml
xcodebuild -project apps/RayNeoCompanion/RayNeoCompanion.xcodeproj \
  -scheme RayNeoCompanion -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath apps/RayNeoCompanion/build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

Keep ad-hoc signing for real Keychain runs. `CODE_SIGNING_ALLOWED=NO` is only for compile checks and does not mean the Keychain works. Do not present a simulator-state demo as a successful connection.

## 3. Device build dependencies and signing

The device build configuration is `project-device.yml` (named `project.yml` in the original research workspace) and reuses `core-probe/Sources`. This source release includes the existing build dependencies below; per-file hashes are in `DEPENDENCIES.json` at the root:

| Path | Purpose |
| --- | --- |
| `core-probe/Frameworks/RayneoNet.framework` | Vendor communication core |
| CocoaAsyncSocket / OpenSSL / RayneoLog / SwiftProtobuf / CocoaLumberjack / SSZipArchive frameworks in the same folder | Matching runtime dependencies |
| `core-probe/RecoveredInterface/RayneoNet.swift` | Recovered declaration source; the start script uses the local toolchain to generate a declaration-only swiftmodule and does not compile or link a placeholder implementation |
| `core-probe/Vendor/opus-ios/libopus.a` and opus-1.5.2/include | Opus decoding dependency |
| `core-probe/Vendor/py-webrtcvad-2.0.10/cbits` | Local VAD C sources and headers |
| Each third-party COPYING / LICENSE | Original attribution and license; not covered by this project's non-commercial license |

Do not download same-named libraries from unknown sources, and do not assume another version has the same ABI. If a dependency is missing, the start script lists exactly what is missing and exits; it does not fake success with empty files.

```sh
node scripts/start.mjs --device
```

In Xcode, select `RayNeoCompanionDevice`, your own Signing Team and a specific iPhone, then run. The Bundle ID defaults to `io.turboio.companion`. If your own project needs a different ID, update every related configuration and understand how this isolates data, Keychain and pairing. When upgrading an existing install, do not change the ID or uninstall casually.

The public version uses a neutral Bundle ID and service namespace, isolated from the maintainer's original test install; it does not read the original test app's Keychain. When you sign it yourself, choose an identifier you can use. Do not copy the pairing database between two different clients.

On first use, or when switching from the official app, **first unbind the glasses inside the official RayNeo app, then in the phone's "设置 → 蓝牙" (Settings → Bluetooth) choose "忽略此设备" (Forget This Device) for those glasses**. Closing the official app is not the same as unbinding. Then hold the glasses button for about 5 seconds, confirm the blue light is flashing, select the target in Turbo IO, confirm the system pairing prompt, and wait for the app to show "已认证" (Authenticated). Do not let the official app and Turbo IO connect to, or compete for, the same glasses at the same time.

Once the glasses are bound to Turbo IO, everyday use should reconnect first; there is no need to unbind, forget or reset each time. The user has accepted the build on a non-jailbroken device. An Android version is still to be developed; these configuration steps cover iOS only.

## 4. Cloud conversation: use only your own services

On the device, open "会话 → 模型设置 / 配置 ASR 和模型密钥" (Conversation → Model settings / Configure ASR and model keys):

1. Enter your own Alibaba Cloud ASR Host, as a hostname only: no `https://`, port, path, user name or query parameters. Only aliyuncs.com subdomains are currently allowed, and the service must support the DashScope WebSocket streaming task protocol.
2. The server must provide `qwen-audio-3.0-asr-flash-streaming`. Audio is 16 kHz, mono, PCM16, with cloud-side VAD. Switching model or protocol is not compatible just by changing the key.
3. Enter the ASR API Key and the DeepSeek API Key. The keys go only into your own app's Keychain; they are not written into source or environment scripts.
4. The current DeepSeek executor uses the fixed official HTTPS chat/completions endpoint, `deepseek-v4-flash`, thinking off, stream=true, max_tokens=1024. Other model draft pages do not replace this executor.
5. Choose save only, or explicitly enable default standby or continuous interjection. After connecting, say a short sentence and check the ASR and the answer; a successful settings save does not count as interface acceptance.

The source carries no developer default ASR tenant. Without a Host or Key there is no automatic cloud audio capture. Changing the Host uses a separate service Keychain identifier and does not reuse the old host's key. When an existing test install upgrades to this configuration version, it must first enter its own Host; entering the original Host again finds the existing Keychain content under the original service. The old Key is not deleted.

Manual ASR for ordinary recordings shares this user configuration and captures the Host and its Key at start, so changing the configuration during decoding cannot send the old Key to a new address. A recording is not transcribed automatically just because the file was received.

## 5. Weather, notifications, recordings

- Weather: in Tools, enter your own QWeather Host / Key and city. Query first and confirm the candidate lens icons, then enable automatic sending of verified icons. Home-screen weather and the weather card are separate features.
- System notifications: allow notification sharing in the system Bluetooth accessory settings; set the sources in the app's notification center. Custom notifications use the app's own channel and can send a random code manually; there is no need to generate a phone system notification.
- Recordings: first turn on recording receive for the glasses, then record and save on the glasses. The receive switch currently needs rechecking after it is turned back on. Transcribe and share manually from the recording archive; the full system share flow still has items to verify.
- To-dos: local editing and sending work, but completion on the glasses not syncing back to the app is a known issue. Do not resend an old not-done state that overwrites the glasses.
- NAS/Obsidian: for now, export audio, Markdown or ZIP. There is no promise of automatic upload or remote indexing once configured.

## 6. Codex bridge (optional)

The computer needs a working Codex login and a compatible app-server. This project starts a separate child process and does not control the current desktop chat. `RAYNEO_CODEX_BINARY` can set the binary path. The bridge currently uses the verified `--stdio` argument; check the CLI and schema after a version upgrade.

Create a random token file in a private path (32–256 bits, Base64URL, permissions 0600). Do not reuse a cloud service key, and do not put the token on the command line. Run:

```sh
node codex-bridge/bridge.mjs \
  --workspace /absolute/your/allowed/project \
  --token-file /absolute/private/token-file \
  --state-file /absolute/private/ledger.json
```

The default is `127.0.0.1:8787` with a read-only workspace. For iPhone access, use your own trusted HTTPS proxy or supply `--tls-cert` / `--tls-key`; a non-loopback listener requires TLS. The phone stores the HTTPS root address (no `/v1` suffix) and a separate token, checks the connection, then allows voice tools and proactive reminders as needed. For the first integration test, use a random-code task that reads and writes no files.

| Endpoint | Purpose |
| --- | --- |
| GET /v1/state | State, tasks and events |
| POST /v1/message | requestId, text, optional taskId; returning accepted does not mean done |
| POST /v1/stop | requestId, taskId; requests a stop |
| POST /v1/decision | requestId, taskId, approvalId and decision/answers; the user confirms on the phone |

Every request uses Bearer authorization; POST bodies are JSON. The model has only three tools, message/status/stop, and cannot approve anything automatically. Write access is added only when the host user explicitly chooses `--allow-workspace-write`. If a request's result is uncertain, do not resend it with a new requestId.

Proactive reminders are app polling while running plus glasses notifications, not APNs. Delivery is not guaranteed after a force quit, while suspended or during long offline periods. Do not expose the app-server directly or put the bridge token in a web page.

## 7. USB display observation (optional)

Set up iproxy on the Mac and connect a trusted phone over USB:

```sh
node display-observer/server.mjs --udid YOUR_TEST_DEVICE_UDID
```

On the phone, open "工具 → 显示观察" (Tools → Display observation) to enable the interface for this session. Open `http://127.0.0.1:8790/` in a browser and enter this session's temporary token. Text is excluded by default; observing newly appearing text needs separate consent. Access expires after 30 minutes and must be re-enabled. Mac 8790, forwarded 18766 and phone 18765 are all loopback addresses; do not expose them externally.

This is a redraw of page and state, not a pixel screenshot of the lens. Switching styles does not control the glasses. Stopping clears memory and does not fake live state.

## 8. Checks

```sh
node scripts/check-source.mjs
node --test codex-bridge/bridge.test.mjs display-observer/*.test.mjs
xcrun swift test --package-path rayneo-protocol
```

A source scan is not a full security or license audit. Local builds and data produced by running are not for release. App unit and UI tests use your own existing simulator and a new xcresult path. The user has confirmed the build on a non-jailbroken device; background behavior, acoustic performance and lens operations under different firmware still need acceptance feature by feature.
