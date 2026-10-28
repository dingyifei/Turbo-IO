# iOS 1.0.7（230）固件向导与 WP6 TMG3 候选

## WP6: unflashed TMG3 candidate

**The morning flash is a human decision.** WP6 offers TMG3, not a device-accepted upgrade: `StrixOS-1.0.5.5-TurboIO-TMG3-CANDIDATE-NOT-APPROVED.zip`, 8803177 bytes, SHA-256 `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274`. Its AP is 7344072 bytes, SHA-256 `b54a28a628112c2b548393328528c2f7a19e727741f1fd6ede35cfbee4290c52`, MD5 `28d26bb9965e2648ab514e02d4708957`. The package still uses resource name `TurboWeReadCandidate.zip` and the frozen APP107 routing marker. Packaging/installing the phone app never starts or authorizes a flash. The 2026-10-19 TMG2 acceptance record below is historical; `tmg3FlashAcceptedOnDevice` is false.

The existing three-step wizard and single destructive confirmation below are unchanged. TMG2 glasses keep normal phone functionality, receive legacy POSE only and ignore TLG1. Check the new phone package with TMG2 still installed before making a separate TMG3 decision.

**Rollback requires an earlier phone build.** This build accepts only the TMG3 ZIP, so it cannot authorize a TMG2 reflash. Before a human chooses TMG3, keep the TMG2-pinned C5 phone IPA at `~/projects/personal/turboio-inputs/signed-20261027-1443-wp7c-c5/TurboIO-local-only.ipa`, or C4 at `~/projects/personal/turboio-inputs/signed-20261027-1231-wp5-c4/TurboIO-local-only.ipa`, with the immutable TMG2 ZIP. A human must install that earlier phone build before attempting the matching TMG2 rollback; no rollback was performed here.

2026-10-19 · [构建与签名](README.md) · [TMG2 固件下载](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)

## 适用范围与风险

本版开放的是 **APP107-OTA / 雷鸟 1.0.7（230）→ 固定 TMG2（基于 Strix OS 1.0.5.5）**。iPhone 17 Pro Max 已实刷成功，不代表任意宿主、机型或候选都能使用。已装 TMG2 且功能正常，不必重复刷。

高风险研究固件，非开发者请勿尝试。不保证回滚、恢复或救砖。只有 AP 内容经过自定义修改，**不代表完整官方 OTA 仅写 AP**。不要改版本号或校验来绕过保护，不混用 Android / 1.0.6 的包与授权。

公开版只提供源码与构建工具；自行取得合法未加密原厂输入、匹配签名和设备授权，按 README 打包。新打包器默认加入专用升级通道，**不自动开始下载或刷写**；旧 APP107 禁用 OTA 包必须重新构建，改 README 不会更新已装 App。

## Firmware wizard (English)

Open **Turbo › Glasses › Glasses firmware**. The wizard shows the firmware name from the app's `TIOExperimentalOTABuild` key. With that key set to `TMG3`, it names TMG3. WP6 now pins the exact TMG3 bytes and sets the Info value to TMG3; the bundled filename remains `TurboWeReadCandidate.zip`. The earlier WP5 C4 package was TMG2-pinned. Opening the wizard does not start an installation.

1. **Check.** Back up the phone App data. Keep the glasses above 50% charge, on their home screen and connected; finish recording, navigation, music and other active tasks. The Package row checks the candidate, Source checks the local download service, Protection checks the host gate, Auto Update checks RayNeo's setting, and Version checks the recent read from the glasses. On a fresh install, open **RayNeo › Glasses › Software version** and turn Auto Update **on, then off once** so RayNeo saves the setting. The wizard's **Fix** can turn it off only when an existing, recognizable setting is present; if the setting is missing or unknown, use RayNeo. Do not continue while a required check fails.
2. **Download.** Open the wizard's 15-minute download window. In **RayNeo › Glasses › Software version**, download the update and stop at **Ready to install**; do not tap Start install yet. Return to Turbo and wait for the downloaded directory check to pass. RayNeo may reuse a matching verified cache, so a download request count of zero alone does not show failure. If the window expires or the directory does not match, stop and repeat the checks.
3. **Install.** Have RayNeo read the glasses version again and return to Turbo **within 120 seconds**. Check that the version read is fresh and the downloaded directory still matches. Read and accept the wizard's **single confirmation** to allow one transfer. Authorization alone does not start a flash: return to **Ready to install** in RayNeo and manually tap **Start install** there. Wait for RayNeo to finish and the glasses to restart and reconnect. Then fully close and relaunch RayNeo; check its result and the wizard status before using the glasses normally. If the result is unclear, stop rather than repeat the transfer.

## 固件向导（中文）

打开 **Turbo › 眼镜 › 眼镜固件**。向导从 App 的 `TIOExperimentalOTABuild` 键读取固件名称；该键为 `TMG3` 时显示 TMG3。WP6 已固定本次 TMG3 的字节校验值，Info 值为 TMG3；资源名仍为 `TurboWeReadCandidate.zip`。历史 WP5 C4 包固定的是 TMG2。打开向导不会开始安装。

1. **检查。** 先备份手机 App 数据。眼镜电量保持 50% 以上、停在首页并保持连接，结束录音、导航、音乐等正在进行的任务。「固件包」检查候选包，「来源」检查本机下载服务，「保护」检查宿主门禁，「自动更新」检查雷鸟设置，「版本」检查最近一次眼镜版本回读。首次安装时，在 **RayNeo › 眼镜 › 软件版本**中把「自动更新」**先打开、再关闭一次**，让 RayNeo 保存该设置。仅当已有可识别的设置键时，向导的「修复」才能将其关闭；设置缺失或状态未知时请在 RayNeo 中操作。必需检查未通过时不要继续。
2. **下载。** 在向导中开启 **15 分钟**下载窗口。到 **RayNeo › 眼镜 › 软件版本**下载更新，停在「**软件就绪**」，先不要点「开始安装」。返回 Turbo，等待解压目录校验通过。RayNeo 可能复用已校验且一致的缓存，因此下载请求数为 0 本身不代表失败。窗口过期或目录不匹配时，停止并重新检查。
3. **安装。** 让 RayNeo 再次读取眼镜版本，并在 **120 秒内**返回 Turbo。确认版本回读仍有效、下载目录仍匹配。阅读向导的**单次确认**，允许一次传输。授权本身不会开始刷写：回到 RayNeo 的「软件就绪」页，**手动点「开始安装」**。等待 RayNeo 完成、眼镜重启并重新连接。随后彻底关闭并重新打开 RayNeo，核对官方结果和向导状态，再恢复日常使用。结果不明时停止，不要重复传输。

本版不是原厂恢复工具：原厂 ZIP 或其他候选会被拒绝。恢复请读[原厂固件说明](../../firmware-research/strix-1.0.5.5/README.md)，使用独立匹配且经过验证的工具链。

## 本次实测证据与边界

- 用户完成实刷；官方记录传输 100%、安装 succeeded / version_matched，重连后 Strix OS 1.0.5.5 / idle / confirmed。
- 236 个通过校验的分片共 11940662 字节，覆盖本次官方请求的 6 个负载，含完整 AP 7408584 字节；不声称 15 个负载均重新传输。
- 刷后新手机进程回读：授权 0、已开始 0、下载窗口关闭。
- 本轮使用逐字节校验一致的官方缓存，未另做网络重新下载实测。公开脱敏源独立编译、回归和本地签名检查，与私用实测 IPA 不逐字节相同。
- 私人日志、Cookie、Key、签名材料和 IPA 不公开；其他机型、账号与所有后台场景未逐一验证。

## Why official updates stay redirected (decision 2026-10)

- package.mjs patches two inspected App.framework route records through patch-route.mjs, and ExperimentalOTAFeed.m answers on 127.0.0.1. For packageType=app, and for firmware unless a pinned TMG archive is armed, it returns no update. This prevents the official app from offering stock Strix OS, which would overwrite TMG2/TMG3 and remove the Turbo glasses features.
- A build without the route marker fails TIOOTA107HostMatches in OTAHost.h. The flash gate then refuses every business-9 frame, and the flash wizard cannot install Turbo firmware updates.
- Official app updates do not apply to this re-signed build. The App Store does not update it, and validateHost in package.mjs pins 1.0.7/230 exactly; a new RayNeo version therefore needs a new addon port.

To return to stock: delete the Turbo build, reinstall RayNeo AI from the App Store, and accept the official firmware update there. No separate un-redirected build is shipped.
