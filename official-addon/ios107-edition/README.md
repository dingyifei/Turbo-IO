# iOS 1.0.7（230）· APP107 兼容适配

## TMG8 candidate — current development branch

TMG8 supersedes the historical candidate sections below. ZIP SHA256: `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6`; ZIP bytes: 8,819,108; ZIP MD5: `2c1a67c2d0108ecdfab139210ad67e7d`; AP size: 7,368,072 bytes (under 9.6 MB); AP SHA256: `5441188525e3fda393028694d093be713de360563ea2bb9696ec5c4c8c4a1fc1`; AP MD5: `2160d6a794be52c37797a06f173e50fe`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence only; the candidate is not approved, not flashed, and no glasses were contacted.

TMG8 adds one capability bit and one layout value to the wire (and the status `detent` field, which already existed, reads 300 instead of 600 when that bit is set; C12 accepts both): the glasses report `TD_CAP_MENU_CAROUSEL` (bit 9, `0x200`) in the status caps (`TD_CAPS_TMG8`; the build field stays `TD_BUILD_TMG6`), and the menu layout record accepts 1 (carousel) besides the grid row counts 2 and 3. The phone writes 1 only after the connected glasses' last status sample carries the bit (a SET with wire byte 7 = 1, the only non-zero use of that byte); TMG7 and TMG6 glasses never receive it, so C12 stays fully compatible with them and with TMG5 as before. After the flash the glasses still report the TMG6 build name; the proof that TMG8 is running is the caps bit 9 and the build-identity sha256 in the status `build` field, which changes from TMG7's `b86af6e1edf99fef2e1c1aa8bab8153295cb7f973ad0abe262e2f6c1b00d3bdf` to `7fe49d041471776203ba8af03424597b53413b4b2621c8edfd69eb9b51a3ad0b`. The glasses never report the ZIP hash. The same ZIP is pinned by `firmware-pins.json` and `FirmwarePins.h` (`firmware/tools/phone_pins.py`, name `TMG8` read from `firmware/RELEASE`). Rollback is C11 plus ZIP7 (ZIP7 rejects a stored carousel value and loads the last saved grid layout, 3 rows if none was ever saved; until ZIP7 is flashed back, C11's status and knob screens do not read TMG8 glasses, and the C11 OTA wizard, which does not use that sample, still flashes). Details: `firmware/README.md`.

**Human-only TMG7 → TMG8 checklist:**

1. Install the separately signed C12 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG8 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation. No automatic worker installation or flashing is authorized.
3. After the glasses reboot, restart the phone app and check the new menu and pages: the carousel (80 / 48 / 36 px icons and its slide), the knob (one item per 300 counts, wrap at both ends), the live tile status line and grid dots, the navigation title in the menu while a route is live and the Navigation page is closed, the dashboard card, and long lyrics. The device checks listed in the TMG8 README remain open.
4. Roll back manually to C11 plus ZIP7 using the same guarded OTA process. Host previews do not establish hardware acceptance.

## TMG7 candidate (superseded by TMG8)


TMG7 supersedes the historical candidate sections below. ZIP SHA256: `6b06d0dd3124ac1f86c91e0879908f9bfe129a2051cf0b619d5b0b664bc3c0aa`; ZIP bytes: 8,814,600; AP size: 7,360,584 bytes; AP SHA256: `5213d2f3a29858ff2e04c770b3ae4501615c448158e354173b39cd2345501a67`; AP MD5: `55458db47aaa5e69e5ef95f72e0b611e`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence only; the candidate is not approved, not flashed, and no glasses were contacted. After the flash the glasses still report the TMG6 firmware name and capabilities (TD_BUILD_TMG6, TD_CAPS_TMG6; the wire protocol is unchanged by design), so the status screen reads `firmware: TMG6` before and after. The proof that TMG7 is running is the status `build` field, the build-identity sha256, which changes from TMG6's `83b82fab9fe9356de62570deff5878b9cfc292b3037998088664e87bd90d8644` to `b86af6e1edf99fef2e1c1aa8bab8153295cb7f973ad0abe262e2f6c1b00d3bdf` (shown on the "Firmware and build" row).

TMG7 re-lays navigation, music, focus timer, the main menu, the camera hint and the mini-app runtime to the design system. The wire protocol, capability masks and firmware name (TD_BUILD_TMG6, TD_CAPS_TMG6) are unchanged, so C11 stays fully compatible with TMG6 glasses (and TMG5 as before) and pins only the exact TMG7 ZIP for the wizard. Only the build-identity sha256 in the status `build` field changes with the flash (see above); the glasses never report the ZIP hash.

**Human-only TMG6 → TMG7 checklist:**

1. Install the separately signed C11 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG7 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation. No automatic worker installation or flashing is authorized.
3. After the glasses reboot, restart the phone app and check each re-laid page: map clipped at the lens edge, music lyrics on one or two lines, focus timer, the menu caret and focused name, the transient camera hint, and mini-app caret focus. The 16 px lens-mid text legibility and the caret visibility are device checks.
4. Roll back manually to C10 plus ZIP6, or C9 plus ZIP5, using the same guarded OTA process. Host previews do not establish hardware acceptance.

## TMG6 candidate (superseded by TMG7)

TMG6 supersedes the historical candidate sections below. ZIP SHA256: `a134c0f9d8550cdd5b53559e4857e27ca92ec8b168543d2c357cbc1e3fbe4d6e`; AP size: 7,357,832 bytes; AP MD5: `55d933ad07b474535ed0389b09d0ddf3`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence; device acceptance remains NOT RUN.

C10 remains compatible with TMG5 glasses: the new Passing message requires navigation capability mask `0x08`. TMG6 shows the full forward route within the visible map, a five-pixel route with a seven-pixel black halo, a larger fixed heading-up car marker, a fixed full-road-name line, smooth stock-family scale text, and three non-overlapping lyric slots capped at two lines each. Phone word segmentation supplies safe ellipsis boundaries. Host EN/ZH previews use macOS surrogate fonts; actual stock font appearance remains a human device check. Knob observation: approximately 2000 raw counts per full rotation; wheel behavior is unchanged.

**Human-only TMG5 → TMG6 checklist:**

1. Install the separately signed C10 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG6 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation.
3. Confirm exactly once in the existing wizard, keep both devices powered and connected, and wait for the glasses to reboot. No automatic worker installation or flashing is authorized.
4. Restart the phone app after flashing. Check TMG6 identity, full-route pixels before each of two turns, EN/ZH Passing fallback and long-name ellipsis, scale/distance readability, marker centering, and long EN/ZH lyrics. Recheck tiles, captions, speech speed, and existing music controls.
5. Roll back manually to C9 plus ZIP5, or C8 plus ZIP4, using the same guarded OTA process. Signed packages and host previews do not establish hardware acceptance.

OTA routing, hash/freshness checks, the single-confirmation policy, boot/NAND paths, and wheel scaling remain unchanged. The FW6 retained-call checker is byte-identical to FW5, including only the existing `tm_rotate` exception.

## TMG5 candidate — current development branch

TMG5 supersedes the historical candidate sections below. The exact candidate ZIP SHA256 is `6705bf4d164178943018d55ac882cf796bbc255f186d0be509ecb2f798ede0ef`; AP size is 7,355,400 bytes and AP MD5 is `8ece02af435fb8643c444ca5d412a2fe`. Two clean builds match byte for byte, with 25 existing patch sites and 14 unchanged stock payloads. This is build/host evidence; physical acceptance remains unrun.

The phone remains compatible with TMG4 glasses. Tile actions now work during reordering and display acknowledgement/failure feedback; Reset also saves. Read-only status accepts safe supported app states, while knob calibration explains the main-menu prerequisite and releases a refused lease. Initial navigation geometry precedes turn updates; TMG5 advertises bounded correction/heading smoothing, a six-pixel route, and static square music artwork with wheel/tap control hints. Background roads are filtered on the phone. The existing music commands still invoke the phone's Spotify controls. Speech defaults to 1.2× with five persisted choices for both English and Chinese, and explicitly confirmed idle captions no longer block microphone selection because of a missing template or stopped session.

**Human-only TMG4 → TMG5 checklist:**

1. Install the C9 phone package only after its signing/build review. Turn RayNeo Auto Update on and then off once.
2. Download the bundled exact TMG5 candidate in RayNeo and stop at **Ready to install**.
3. Obtain a version read within two minutes, then use the existing single confirmation. This worker never flashes or talks to glasses.
4. After reboot, restart the phone app. Check all 13 tiles and Camera, reorder/hide/save/reset feedback and persistence, language, read-only status, main-menu knob guidance, and one-turn measurement.
5. Check simulated and real-GPS initial map timing, backward/forward corrections, turns and route contrast; check music artwork and wheel/tap controls, both speech languages at each speed, and caption source changes after stopping. Verify active navigation, display and OTA still block conflicting caption changes.
6. Roll back with **C8 plus ZIP4**, or **C5 plus ZIP2**, using the matching old phone package and manual flash flow. C9 accepts only ZIP5; rollback and hardware recovery are not verified here.

The firmware's source/input identity is separate from the ZIP hash. Runtime capabilities are accepted only for the matching TMG4/TMG5 family. OTA host guards, hash/freshness policy and single-confirmation behavior are unchanged. The sole preservation-check exception is the user-approved removal of `tm_rotate`, applied and committed by the coordinator in FW5 only; earlier firmware releases are frozen as the `fw/tmgN` tags.

## TMG4 candidate — current development branch

This branch offers only **TMG4 CANDIDATE-NOT-APPROVED**, bundled as `TurboWeReadCandidate.zip`. It includes the unflashed TMG3+TMG4 delta; deviceIO=false and physical acceptance is unrun. Firmware source, formats and rebuild: [`firmware/README.md`](../../firmware/README.md) (this exact release is the git tag `fw/tmg4`).

| Payload | Bytes | SHA-256 | MD5 |
| --- | ---: | --- | --- |
| ZIP | 8809015 | `aa387b37ece2092d50721bcc3409984f7bd0d650aad4b7b249aceba515161126` | `f72c9a3a79ab02d968dc1415ee117509` |
| AP | 7353800 | `0d6a3ec1d4aac08351afa6b60031c96f4e3904887a61a62def3da561f6c0c02b` | `ea89c1d953fff0b0ffe932c2ed2b5c46` |

TMG4 adds persistent custom tile order/visibility (stock0–6 fixed, Camera always visible,8–13 active entries), reboot-persistent language with source2 confirmation, read-only runtime status and a30-second one-turn knob estimate. The600-unit detent heuristic is unchanged. Legacy removed-app replies and the outbound legacy POSE fallback are dropped; this phone build does not fully drive TMG2. The existing flash wizard still accepts a fresh validated TMG2-era version reply and uses exactly the TMG4 ZIP; the host/freshness/hash/slice policy and single confirmation remain unchanged.

**Human-only TMG2→TMG4 checklist:**

1. Keep the TMG2-pinned C5 phone IPA and immutable TMG2 ZIP for rollback. Install C8 by hand only after its separate review.
2. Back up phone app data, charge glasses above50%, open their launcher, and finish active recording/navigation/music/file work. In RayNeo Software version, turn Auto Update **on then off once** so its setting exists.
3. In Turbo › Glasses › Glasses firmware, pass the package/source/protection/settings checks and open the15-minute download window. Download in RayNeo and stop at **Ready to install**. Return to Turbo and require an exact directory match.
4. Read the glasses version in RayNeo and return within **120seconds**. Accept the wizard's **one confirmation**, then manually tap Start install in RayNeo. Authorization itself starts no flash.
5. After glasses reboot/reconnect, fully close and restart the phone app. Verify13 default tiles; save and reboot reordered/hidden tiles and language; inspect status; measure one full knob turn; test POSE2 in a dead zone, all retained tiles and Spotify.
6. For rollback, install the earlier **C5** phone package, then manually flash the matching **TMG2 ZIP**. C8 accepts only TMG4; it cannot authorize a TMG2 rollback. Recovery has not been tested by this worker.

```sh
python3 test.py --firmware /absolute/path/to/exact-TMG4-CANDIDATE-NOT-APPROVED.zip --app107 /absolute/original/Runner.app --patched-app /absolute/patched/Runner.app
```

The default packager identity is `TMG4` (an explicit `--experimental-ota TMG4` is optional); older candidate names and changed hashes are rejected. All instructions and acceptance results below describe earlier WP6/WP5/publication snapshots. They do not establish TMG4 device acceptance and do not override this section.


Layout (2026-10): this directory is self-contained — build.sh, package.mjs, test.py, local-translation/ and tests/ live here. Older editions are in git tag `archive/editions-2026-10`. Ignored parser copies and signing inputs remain external; see the build instructions.

## Historical WP6 candidate status

This branch bundles the unflashed **TMG3 CANDIDATE-NOT-APPROVED** as `TurboWeReadCandidate.zip`. ZIP SHA-256: `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274` (8803177 bytes). AP: 7344072 bytes, MD5 `28d26bb9965e2648ab514e02d4708957`. TMG3 source, tile map and rebuild: the git tag `fw/tmg3` (the current tree is [`firmware/README.md`](../../firmware/README.md)). TMG2 glasses remain supported and do not need to be flashed for the phone update. The wizard offers TMG3 only after the existing checks and single human confirmation; no package automatically flashes. The 2026-10-19 TMG2 device results below are historical and do not establish TMG3 device acceptance.

**Rollback requires an earlier phone build.** This build accepts only the TMG3 ZIP, so it cannot authorize a TMG2 reflash. Before a human chooses TMG3, keep the TMG2-pinned C5 phone IPA at `~/projects/personal/turboio-inputs/signed-20261027-1443-wp7c-c5/TurboIO-local-only.ipa`, or C4 at `~/projects/personal/turboio-inputs/signed-20261027-1231-wp5-c4/TurboIO-local-only.ipa`, with the immutable TMG2 ZIP. A human must install that earlier phone build before attempting the matching TMG2 rollback; no rollback was performed here.

2026-10-19 · [首页更新](../../README.md#ios107-update) · [OTA 预发布](https://github.com/Turbo1123/Turbo-IO/releases/tag/ios107-app107-ota-20261019) · 上一版 NAVS3（已归档 / archived in git tag `archive/editions-2026-10`: `official-addon/navs3-edition/README.md`）

**用户已在 iPhone 17 Pro Max 覆盖安装 1.0.7（230）私用适配包，测试后反馈“没啥问题”。** 回读确认 APP107-PHONE-01、宿主 1.0.7/230、hooks/版本门槛通过。不是所有功能、账号、机型与后台场景的全量验收；公开脱敏版单独编译与离线检查，不冒充与私用包逐字节相同。

## 变化与版本选择

- 基于 NAVS3 保留起终点导航、矢量路网与路名、菜单排数配置及现有扩展模块。
- 精确新增 `1.0.7 / 230 / 410DEFDB-F937-39EA-ACF2-F616ABFF9D0B`，不放宽未知宿主。
- 8 个关键 native 类的 110 个既有方法签名无变化；Flutter 检查覆盖 445 个方法，关键桥接一致。静态一致不代表业务逻辑完全不变。
- **历史 2026-10-19 发布版沿用 TMG2**。当前 WP6 分支提供未实刷的 TMG3 候选；已有 TMG2 不必因手机升级重刷，刷写须另由人工决定。
- **1.0.7 OTA 已实刷开放。** 2026-10-19，iPhone 17 Pro Max 使用 APP107-OTA-PHONE-01 经官方升级流程安装原样 TMG2 成功，重连版本匹配；刷后重启手机 App，授权归零。公开版移植同一升级逻辑，单独编译回归，不将公开包称为原样实测 IPA。
- 新版两个 Dart 查询数据记录单独验证，仅修改字符串内容，长度、缓存哈希、对象头与代码指令不变；运行时精确检查宿主版本/UUID/标记和路由。完整包、15 文件清单、待传分片仍严格校验；未授权不能刷写。

| 版本 | 手机适配 | 固件 / OTA |
| --- | --- | --- |
| APP107 / 1.0.7（230） | 最新兼容适配，继承 NAVS3 | **原样 TMG2 OTA 已实刷开放**；默认锁定，按专用教程单次授权 |
| NAVS3 / 1.0.6（218） | 前版矢量导航修正 | 精确 TMG2 候选与门禁，按其独立教程使用 |
| Android 1.0.5 | 本轮未更新 | 不与 iOS 门禁混用 |

## 公开边界

仅公开原创源码、构建/打包工具与离线测试，**不含合并/个人签名 IPA、Cookie、Key、私人服务地址、签名材料、备份、用户通知/智记/路线**。

从已脱敏 NAVS3 基线导出，合入已审核的 1.0.7 兼容及 OTA 适配，不从私人 IPA 抽取配置或素材。沿用 [PolyForm Noncommercial 1.0.0](../../LICENSE)，第三方许可不变。原厂 App 须自行合法取得。

## 构建与检查（macOS / Xcode）

The legacy six-flag command (`TIO_MAPKIT_ENABLED`, `TIO_IMAGE_RX_LAB`, `TIO_DISPLAY_PHONE`, `TIO_DISPLAY_FLASH`, `TIO_OTA_FLASH_ENABLED`, `TIO_CLASSIC_BINDINGS`) builds the same feature set as `TIO_DEV=1`.
Music remains unchanged pending WP4.

在本目录执行：

```bash
TIO_MAPKIT_ENABLED=1 TIO_OTA_FLASH_ENABLED=1 TIO_DISPLAY_FLASH=1 TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub
TIO_DEV=1 TIO_MAPKIT_ENABLED=1 TIO_OTA_FLASH_ENABLED=1 TIO_DISPLAY_FLASH=1 TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub

node --test package.test.mjs
python3 test.py --firmware /absolute/path/to/exact-TMG3-CANDIDATE-NOT-APPROVED.zip
```

`FLASH` 是保护模块编译开关，**不是授权**；WP6 打包默认携带 TMG3 候选，初始仍锁定。不要移除校验或改 Info.plist 冒充其他版本。

WP6 使用本机构建的 TMG3 候选，SHA-256 为 `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274`；未实刷、未获得设备验收，不会自动授予刷写权限。历史 [TMG2 原样预发布](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)保留为独立回退输入。

## 自行合并与签名

需合法的 **1.0.7（230）未加密原厂 Runner.app**。可参见[原厂去签名 IPA 归档](../../official-apps/ios/1.0.7/README.md)，它没有 Turbo IO，也不是签名安装包。本工具不提取或解密；1.0.6 输入不能代替。只接受下列两种精确配对，其他去签名/重签派生文件不接受，不能通过删校验绕过。

| 输入 | SHA-256 |
| --- | --- |
| 解密 Runner | `c416d939c90745b170027171844e3275faf5e502306746176375dee5837aadcf` |
| 原厂 App.framework/App | `fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e` |
| 发布去签名版 Runner | `765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3` |
| 发布去签名版 App.framework/App | `041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d` |

```bash
node package.mjs \
  --app /absolute/original/Runner.app \
  --addon /absolute/ios107-edition/build/image-rx-lab/TurboIOPrivateAddon.dylib \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 --device YOUR_DEVICE_UDID \
  --out /absolute/new-private-output --bundle com.rayneo.venus.pub \
  --product iPhone18,2 \
  --firmware /absolute/path/to/exact-TMG3-CANDIDATE-NOT-APPROVED.zip
```

无需额外传 `--experimental-ota`，WP6 打包默认携带固定 TMG3 候选（显式传值也只接受 `TMG3`）。工具只修改两个已核验的 App.framework 查询数据记录，不改代码指令；签名后再次检查记录，不下载/安装/刷写，不新增官方推送或 Apple 登录权限。可选翻译模块与模型见[单独说明](local-translation/README.md)；Watch 按 [Watch 说明](../../watch-remote/README.md)自行构建，不含作者签名包。源码含模块不代表打包器自动补齐所有第三方 SDK、模型、Watch、服务配置或应用广场资源。

先备份，再使用同一有效签名覆盖安装；签名冲突时不要盲目卸载。启动确认版本、插件入口、眼镜连接并逐项测试，编译成功不等于你的设备验收通过。

## Turbo hub（WP5）

Turbo 入口按「眼镜、助手、媒体、开发者」分区显示现有功能；「开发者」默认收起，展开后可进入研究工具。唯一的界面语言控制位于「眼镜 › 语言」，可选「自动」（跟随 iOS/App）、「English」或「中文」，切换后界面会立即更新。固件向导位于「眼镜 › 眼镜固件」，操作步骤见[升级教程](OTA.md)。

## WP6：TMG3 候选，仅由人工决定是否刷入

按[1.0.7 升级教程](OTA.md)执行：内置校验 → 15 分钟只下载 → 官方软件就绪 → 目录校验 → 单次授权 → 官方安装 → 成功回首页后重启手机 App，确认授权归零。高风险实验，非开发者请勿刷。

## 已知限制

- 手机锁屏后导航停止/卡住仍待闭环，不用于驾驶或安全依赖。
- 路网首次加载、断网或请求预算耗尽仍可能只显示路线。
- WP6 固定 TMG3 候选，不接受原厂 ZIP 或其他候选；[原厂恢复](../../firmware-research/strix-1.0.5.5/README.md)需要独立匹配的恢复工具链，不能复用本版授权，也不保证救砖。
- 原厂登录/推送、Apple 登录、长期后台和所有功能均需独立验收。

## No-network answers / 无网络回答（WP7c）

With `TIO_APPLE_AI=1`, Apple on-device mode (3), or endpoint mode (2) with Apple fallback enabled, can answer after the host's final speech result when no official reply arrives. Keep the RayNeo app open in the foreground. The host supplies its bundled bilingual ASR; the addon does not capture glasses audio. Locked-phone recognition and synthetic-card rendering still need device validation.

启用 `TIO_APPLE_AI=1` 后，Apple 本机模式（3），或开启 Apple 回退的接口模式（2），可在官方回复未到达时使用宿主的最终语音识别结果回答。需要在前台打开 RayNeo 应用；扩展不自行采集眼镜音频。锁屏识别与合成回复卡片仍需设备验收。

- After each launch, complete an official Q&A to verify the chat domain, then choose the answer mode again: launch still resets to Official (0).
- A known unavailable network uses a 0.7 s grace period. An unknown or available network uses the panel's 3–15 s wait (default 6 s). Mode 3 uses Apple directly; mode 2 tries the configured endpoint first and reuses the existing Apple fallback marker on a transport/configuration failure.
- Official commands or an early official reply cancel the pending takeover. Held NLP, errors and completions replay in arrival order on refusal or cancellation; successful takeover drops them. The existing request, streamed display, TTS, history and tool restrictions remain the shared path.
- Developer › Apple Intelligence contains status, wait time and a Copy action for the no-network timeline. The 64-event ring contains rounded uptime, fixed event codes and a four-digit session hash, never questions, answers or error messages.
- Both experimental switches default OFF. Background listening takes effect at the next launch and does not promise locked-phone support. The optional stop-workflow switch waits until the answer has ended and uses the existing idle-exit gate.
- The held queue is capped at 8 and the owned callback FIFO at 64. Overflow disables new synthetic turns until relaunch, replays callbacks in order and releases interception. Overflow spill to the main queue is bounded by input rather than a hard memory cap; an existing local answer may continue while official errors become visible.

每次启动后，请先完成一次官方问答以确认聊天域，再重新选择回答模式。状态、等待时间和可复制的元数据时间线位于「开发者 › Apple Intelligence」。两个实验开关默认关闭；后台监听不保证锁屏可用。队列溢出时会停止新的合成接管并保序回放，需重新启动应用恢复；时间线不保存问题、答案或错误消息。

Portable regression group (supply the audited firmware archive):

```bash
python3 test.py --firmware "$FWZIP" --only no-network-turn
```

The tests inject a clock and scheduler and cover cancellation, duplicates, pre-accept replies, ordered hold/replay, synchronous reentry, stale generations, overflow, wrapper failures and default-OFF options. Build and simulator gates do not establish device acceptance. No entitlements, Info.plist keys or firmware changes are introduced by WP7c.
