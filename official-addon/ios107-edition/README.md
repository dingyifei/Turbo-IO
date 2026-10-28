# iOS 1.0.7（230）· APP107 兼容适配

## TMG4 candidate — current development branch

This branch offers only **TMG4 CANDIDATE-NOT-APPROVED**, bundled as `TurboWeReadCandidate.zip`. It includes the unflashed TMG3+TMG4 delta; deviceIO=false and physical acceptance is unrun. [Firmware source, formats and rebuild](../../firmware-research/strix-1.0.5.5-tmg4/README.md).

| Payload | Bytes | SHA-256 | MD5 |
| --- | ---: | --- | --- |
| ZIP | 8808959 | `47f3f639400173acf57916c5e24c35b307ab2146a2030a2a2b6980b31ce4ab03` | `fe614ff2f325850e08484536a7d0cba2` |
| AP | 7353672 | `aec2e79083dac92c55f6387b2ee5f7cf67201ba99011ecca9b70f0aaa3406efd` | `a3b5de9cfdee8341ccc4233ce4e0fc52` |

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

This branch bundles the unflashed **TMG3 CANDIDATE-NOT-APPROVED** as `TurboWeReadCandidate.zip`. ZIP SHA-256: `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274` (8803177 bytes). AP: 7344072 bytes, MD5 `28d26bb9965e2648ab514e02d4708957`. [TMG3 source, tile map and rebuild](../../firmware-research/strix-1.0.5.5-tmg3/README.md). TMG2 glasses remain supported and do not need to be flashed for the phone update. The wizard offers TMG3 only after the existing checks and single human confirmation; no package automatically flashes. The 2026-10-19 TMG2 device results below are historical and do not establish TMG3 device acceptance.

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
