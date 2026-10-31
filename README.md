# Turbo IO · 雷鸟 iO / RayNeo iO 非官方 SDK

![Turbo IO · Android 与 iOS 双端源码已公开：仪表盘、原生应用与开发者 SDK](docs/screenshots/android-ios-release-hero-20260927.png)

**Android / iOS 双端源码已公开。** 面向开发者的雷鸟 iO 智能眼镜 SDK、手机 App 扩展与眼镜端固件研究项目：自有 AI、Spotify 音乐与歌词、Apple 地图导航、番茄时钟，以及可自定义的仪表盘和小应用 SDK。**不是给小白刷机即用的成品。原生鸿蒙 HarmonyOS 已停止更新，保留历史源码供参考。**

*头图为 AI 生成的宣传示意，不是实机截图，不代表官方背书。本文“公开/开源”指列出的原创扩展源码可获取；具体权利以非商业许可证和各第三方许可为准，并非无限制商用授权。*

原创代码仅供学习、研究与非商业使用，沿用 [PolyForm Noncommercial 1.0.0](LICENSE)，未经授权不得商用或收费分发。除源码及明确列出的依赖，Release 提供原厂砸壳 IPA 作为 iOS 扩展输入，以及 **Android 1.0.5 非官方完整插件 APK / 高风险实验固件**。原厂部分版权仍归各自权利人，不因分发修改包而重新许可。**不提供个人密钥、Cookie、账号、签名私钥，亦不提供合并后的 IPA / HAP**；第三方服务由用户自行配置。

**文档更新：2026-10-30** · 2026-10-23 之前的逐条更新与历史验收记录已移到[更新记录](docs/CHANGELOG.md)。

[当前状态](#当前状态) · [使用前必读](#使用前必读) · [选择路线](#先选开发路线) · [AI 帮你接入](#让-claude-code--codex-帮你接入) · [Roadmap](#roadmap) · [源码布局](#源码布局) · [文档索引](docs/README.md) · [许可与隐私](#隐私与许可)

<a id="ios107-update"></a>

## 当前状态

| 部分 | 现在是什么 | 怎么获取 |
| --- | --- | --- |
| **iOS 手机扩展** | 雷鸟 AI 1.0.7（230）+ [ios107-edition](official-addon/ios107-edition/README.md)，持续更新：中英双语界面、Spotify 音乐与歌词、Apple 地图（MapKit）导航、本机 Apple AI 回答（实验，默认关闭）、新版手机与镜片界面 | 源码；自行合并、签名、安装，**不提供合并 IPA**。原厂输入见 [IPA 下载](#ios-原厂砸壳-ipa-下载) |
| **眼镜固件** | [`firmware/`](firmware/README.md) 单一源码树，最新候选为 **TMG8**（Strix OS 1.0.5.5）。每个版本是一个 git 标签：`fw/tmg2` … `fw/tmg8` | TMG3 起只提供源码与可复现构建，**没有公开固件 Release**；全部是候选（CANDIDATE-NOT-APPROVED） |
| **Android** | 官方 1.0.5（201）宿主 + GUARD-07 完整插件 APK + TAP1-TEST-01 实验固件（2026-09-27），之后未更新 | [APK / 固件下载](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01) · [安装与刷机](android-addon/docs/INSTALL_AND_FLASH.md) |
| **鸿蒙 HarmonyOS** | 已停止更新 | [历史源码与限制](harmony-sdk/README.md) |

**TMG8 已在维护者自己的设备上刷入试用，发现三处问题**：菜单只能单向循环、导航标题的箭头偏移、导航进行中音乐无法播放。计划在 TMG9 修复，同时加入可在手机上调整的旋钮步长。公开预发布的 iOS 1.0.7 OTA 仍对应原样 TMG2（[预发布](https://github.com/Turbo1123/Turbo-IO/releases/tag/ios107-app107-ota-20261019)）。

| 固件标签 | 主要变化 |
| --- | --- |
| `fw/tmg2` | 两／三排菜单、矢量导航（NAVS3）；有公开预发布 |
| `fw/tmg3` | 固件界面中英双语、导航航位推算（POSE2） |
| `fw/tmg4` | 菜单磁贴的顺序与显示可保存、运行状态读取、旋钮一圈校准 |
| `fw/tmg5` | 导航平滑、方形音乐封面、字幕与语速改进 |
| `fw/tmg6` | 导航保留后续路线、歌词与地图显示修正 |
| `fw/tmg7` | 新设计系统：分区布局、焦点提示、迷你应用重新排版 |
| `fw/tmg8` | 轮播菜单、磁贴状态行、导航标题、新的仪表盘卡片 |

**手机构建与固件必须成对使用**，刷写、校验和回退只按 [OTA 教程](official-addon/ios107-edition/OTA.md)。`git show fw/tmg8` 可以看到该版本的 ZIP SHA-256、构建提交和配对的手机构建；从 TMG3 起，在标签上重新构建会逐字节得到同一个 ZIP。

其他仍有效的发布：[TVP2 / TAR2 · 540×220 原生清晰投屏](docs/TVP2_TAR2.md)（2026-10-23，仅 iOS，需要 TVP2）· [Strix OS 1.0.4.12 原厂负载归档](firmware-research/strix-1.0.4.12/stock/README.md)（不是救砖工具）。

## 使用前必读

- **小白不要刷，日常使用请保留官方固件。** 眼镜端原生应用、自定义图形仪表盘与小应用运行时，都需要对应的实验固件；仅安装手机插件不会把这些能力加进原厂固件。已有模型接入、部分字幕等手机侧功能不因此要求刷机。已有匹配运行时后，导入兼容卡片/应用包不必每次重刷。
- **刷机风险由使用者自行评估和承担。** 本项目按现状提供，无稳定性、回滚、救砖或售后保证；掉电、中断、错包和缺陷可能导致数据丢失或设备损坏。在适用法律允许的范围内，作者不承担由此造成的损失或责任。一次实测成功不代表你的设备安全，更不构成“不会刷死”的承诺。
- **候选固件不是稳定版。** TMG3–TMG8 候选最多只在维护者自己的设备上试过，其中 TMG3、TMG7 从未单独刷写（各版本状态见 `git show fw/tmgN`）；不要混用不同候选的固件、手机构建或授权，也不要为了追版本逐个刷。
- **鸿蒙 HarmonyOS 不再更新。** 保留既有研究源码和历史验收，不再移植新功能、适配新固件或承诺修复现有问题。
- **第三方服务的账号与权限请自行解决**（Spotify、模型、搜索等）。不提供账号、Cookie、Key、会员权益、代登录或风控绕过。
- **觉得好用，再自愿打赏。** 不要在打赏前私信要求作者先增加某项功能，也不要把打赏当作功能定制或交付条件。建议可在 Issues 讨论，但不承诺采纳、排期或一对一支持；打赏后同样不产生这些义务。[微信二维码在文末](#support)。

**开发者入口：[仪表盘与小应用 SDK 教程](docs/DEVELOPER_ECOSYSTEM.md) · [20 个 MCP 应用模板 / ZIP](app-gallery/README.md) · [自托管 API](dashboard-service/README.md) · [Agent 开发 Skill](skills/turboio-developer/SKILL.md)**。MCP 在**用户自己的 Server** 上运行，眼镜不运行 MCP、浏览器或任意 JS：后端取数 → SDK 生成卡片或有界原生应用 → 手机确认 → 眼镜显示。

## 先选开发路线

**先按目标选，不必从 V1 源码开始。** 普通日常用户请使用官方 App 和原厂固件，不要把实验包当作官方更新。

| 你的目标 | 现在提供什么 | 从这里开始 |
| --- | --- | --- |
| **在 iPhone 使用插件** | 1.0.7（230）ios107 扩展源码，自行合并、签名、安装，**不提供合并 IPA**。眼镜端功能需要与手机构建配对的固件 | [ios107 构建](official-addon/ios107-edition/README.md) · [刷机与回退](official-addon/ios107-edition/OTA.md) · [固件源码](firmware/README.md) |
| **在 Android 使用插件** | 官方 1.0.5（201）宿主已合并 Turbo IO 的完整实验 APK；不用自己合并，服务配置自行填写 | [下载 APK / 配套固件](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01) → [安装与刷机教程](android-addon/docs/INSTALL_AND_FLASH.md) |
| **开发自己的仪表盘 / 小应用** | 自托管 API、Python / MCP、20 个模板、Agent Skill；先在电脑生成卡片或 ZIP 并预览，再接入匹配手机和运行时 | [开发 SDK 教程](docs/DEVELOPER_ECOSYSTEM.md) · [模板](app-gallery/README.md) · [Skill](skills/turboio-developer/SKILL.md) |
| **只看效果 / 离线学习** | Web UI、模板、SVG 预览与本机测试；不要求设备、服务 Key 或刷机，不等于真机验收 | [Web 预览](docs/v1-sdk.md#web-显示预览与观察台) · [模板离线入门](docs/DEVELOPER_ECOSYSTEM.md#1-十分钟离线入门) |
| **研究独立连接（iOS V1）** | 独立 SDK 与示例客户端，研究配对、协议和自有 ASR；不是当前插件的完整替代品 | [V1 说明与快速开始](docs/v1-sdk.md) |
| **研究鸿蒙 HarmonyOS** | **已停止更新**，仅保留 HarmonyOS 6.1 历史源码与验收 | [历史安装与限制](harmony-sdk/README.md) |

**要不要刷固件？** 模型接入、TTS、部分字幕等手机侧扩展可沿用原厂显示能力；眼镜原生应用、图形仪表盘与小应用需要对应实验运行时。**安装 APK ≠ 安装眼镜固件；iOS / Android 的 OTA 门禁和候选也不能混用。**

**连接与安装：** iOS / Android 扩展沿用宿主配对，不需要为插件反复解绑；Android 重签名 APK 不能直接覆盖签名不同的旧 App，先导出数据再按教程处理。只有切换到 V1 / 鸿蒙独立客户端时，才按对应流程解绑旧宿主、在原手机系统蓝牙忽略设备，不能让多个客户端争抢连接。Android 刷完还必须完成只读回查与解除结果保护。

## iOS 原厂砸壳 IPA 下载

**[1.0.7（230）原厂砸壳 · 未签名](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.7-230)**（当前 ios107 扩展使用）· [1.0.6（218）](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.6-218) · [1.0.5（201）历史输入](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.5-201) · [版本索引与校验](official-apps/ios/README.md)

提供的是**原厂应用的砸壳（解密）版本，未合并 Turbo IO 扩展，不是修改功能后的版本**。1.0.7 已移除全部 95 个 Mach-O 的代码签名、签名目录及商店授权元数据，不包含个人 Apple 签名信息；文件名、大小与 SHA-256 见 [1.0.7 说明](official-apps/ios/1.0.7/README.md)。下载不会直接获得 Turbo IO 功能，请按 [ios107 教程](official-addon/ios107-edition/README.md)自行合并、配置并用自己的签名安装。项目不提供代砸壳或代签名服务。

### 通知与权限，先看这里

- **自定义测试通知**：App 主动发送一段文字到眼镜，不等于读取微信等其他 App 的通知；需要眼镜连接并开启应用内通知总开关。
- **iOS 系统通知**：需允许系统蓝牙设备的“共享系统通知”，且来源 App 自身获准通知；具体以系统设置和对应客户端为准。
- **鸿蒙系统通知转发尚未实现**：需要 `ohos.permission.SUBSCRIBE_NOTIFICATION`、符合要求的签名/证书授权、通知订阅扩展及用户授权。普通应用通知开关、蓝牙权限、在清单声明一行权限，都不等于已获得读取其他 App 通知的能力。**不要为此盲目修改签名等级或 Root。** [鸿蒙权限与已知限制](harmony-sdk/README.md#通知与权限)

## 让 Claude Code / Codex 帮你接入

**Android：[雷鸟 AI Android 官方下载入口](https://rayneo.cn/commonPage/venus/appDownload/index_m.html)** · **[完整 AI 接入说明](docs/AI_SETUP.md)**

**iOS：可使用上方 Release 提供的原厂 1.0.7（230）未签名输入（当前 ios107 扩展使用），或自行准备有权使用的兼容未加密副本；旧版输入不能混用。提供的 IPA 没有 Turbo IO 扩展，需自行合并和签名；普通 App Store 加密 IPA 不能直接合并。**

Android 用户把**官方下载入口 + 本仓库 + 下面的提示词**一起交给电脑上的 Claude Code 或 Codex；iOS 官方扩展用户可同时提供上方原厂砸壳 IPA Release 链接，或自行准备合法兼容的未加密应用副本。原生鸿蒙 HarmonyOS 用户只需本仓库与提示词，不需要官方包。再让助手按所选路线检查环境、编译并引导配置；只有官方扩展需要合并宿主。不需要先弄懂所有脚本；但你仍需提供自己的签名、服务配置并完成手机授权和镜片验收。仅聊天、不能访问本机文件和终端的环境不能替你完成真机安装。

<details>
<summary>展开可复制给 Codex / Claude Code 的接入提示词</summary>

复制下面整段，选择括号里的目标：

```text
请帮我在这台电脑上接入 Turbo IO，仅用于个人非商业学习研究。
源码：https://github.com/Turbo1123/Turbo-IO
Android 官方 App 下载入口：https://rayneo.cn/commonPage/venus/appDownload/index_m.html
iOS 官方扩展原厂砸壳 IPA 版本索引：https://github.com/Turbo1123/Turbo-IO/tree/main/official-apps/ios
该 IPA 未合并 Turbo IO，需校验 SHA-256、版本和 UUID，再自行合并、配置并签名；也可使用我自行准备的合法兼容副本。
目标：[原生鸿蒙 HarmonyOS 客户端 / Android 官方扩展 / iOS 官方扩展 / iOS 独立 SDK / 仅 Web 预览]

先读取 README、docs/AI_SETUP.md 和目标平台文档，检查电脑环境、现有项目改动及设备状态。
没有源码时克隆到新的目录；使用仓库现成构建、测试和合并脚本，不要只给我操作教程。
官方下载页用于 Android 宿主，不保证当前下载版本兼容，需核对版本和 SHA-256；iOS 对自行准备的副本核对版本、UUID 及未加密 thin arm64 要求。原生鸿蒙不需要官方 APK/IPA，按 harmony-sdk/README.md 用自己的 DevEco 签名编译。
下载或输入不兼容时停止合并并说明缺什么，不修改校验、不绕过加密，也不索取第三方破解包。
先完成能独立验证的构建或预览，再引导我使用自己的签名；安装、卸载、重启或改变绑定前确认目标和数据备份。
Key由我在本机安全填写，不索取聊天明文、不复用维护者配置，不把私钥、安装包、录音和日志提交到GitHub。
官方扩展沿用官方连接；切换到V1或鸿蒙独立客户端才按文档解绑和忽略蓝牙。
完成后分别报告源码/编译/安装/登录/眼镜/模型的实际结果；未验收明确标注，不把构建成功当作全部可用。
```

</details>

- **原生鸿蒙 HarmonyOS**：独立客户端已在 Mate X5（HarmonyOS 6.1）验证连接、自有语音和步行模拟导航镜片显示，**无需 Root，也不需要官方 APK / IPA**。使用 DevEco Studio、自有开发者账号和签名自行编译安装，服务 Key 自行配置；不提供 HAP 或签名包。系统通知转发尚未实现，其他限制见[鸿蒙安装、权限与验收说明](harmony-sdk/README.md)。
- **Android**：非 Root 设备已由用户实机验证可用；官方下载页用于取得 Android 宿主，输入仍需通过仓库校验，使用自己的签名与服务配置。见 [Android 安装教程](android-addon/README.md)。
- **iOS**：从上方原厂砸壳 IPA 或自行准备的合法兼容副本提取未加密 `Runner.app`；仍需校验、合并与个人签名，官方下载/商店安装不等于取得可合并输入。只用 V1/Web 不需要官方包。见 [iOS 扩展教程](official-addon/README.md)。

已有 `turbo-io` 技能也可使用，见[技能安装与更新](docs/AGENT_SKILL.md)；选择鸿蒙时，应同时提供 [HarmonyOS 安装教程](harmony-sdk/README.md)，不要套用 iOS/Android 宿主合并流程。

## Roadmap

以下是正在做或准备研究的方向，不是交付时间承诺；顺序会随实测结果调整。

- [ ] **TMG9**：修复 TMG8 实机发现的三处问题（菜单单向循环、导航标题箭头偏移、导航时音乐被拦截），加入手机可调的旋钮步长，以及手机端的眼镜界面测试台。
- [ ] **唤醒屏重绘**：接管原厂唤醒屏的布局与亮度（研究中）。
- [ ] **环境光自适应界面**：按环境亮度自动选择显示亮度与图标/字重风格，兼顾不刺眼和看得清（研究中）。
- [ ] **咬合轻叩唤醒**：用轻叩牙齿代替唤醒词，目前在采集数据、判断可行性。
- [ ] **开发者文档**：固件版本记录、协议说明与适配示例。
- **鸿蒙停止更新（2026-09-27）**：保留既有源码，不再安排维护。

项目仍建议开发者按自己的需求编译、改造和研究使用，不以面向普通用户的开箱即用产品为当前目标。不熟悉开发与调试的用户，建议继续使用官方 App。

## 源码布局

| 路径 | 内容 |
| --- | --- |
| `official-addon/ios107-edition` | 当前 iOS 扩展：构建、打包、测试与 OTA 刷写流程；旧版本在提交 `27ad86e` 中保留 |
| `official-addon/tar2-airplay` · `tar2-display` | TVP2 投屏的接收与显示模块；**AirPlay 接收模块单独采用 GPLv3**，见[许可说明](docs/LICENSING.md) |
| `official-apps` | 原厂 App 输入的版本索引与校验（不含 Turbo IO） |
| `firmware` | 当前眼镜固件源码（单一源码树，版本为 `fw/tmgN` 标签）；`firmware/baseline` 保存早期版本的少量构建输入 |
| `firmware-research` | 原厂固件与研究笔记（1.0.4.12、1.0.5.5、TVP2），不参与当前构建 |
| `android-addon` | Android 官方 App 扩展、纯 Java 测试及本地合并工具 |
| `harmony-sdk` | 原生鸿蒙 HarmonyOS SDK 与客户端（已停止更新） |
| `dashboard-service` · `app-gallery` · `skills` | 仪表盘与小应用 SDK、20 个模板、Agent Skill |
| `apps` · `core-probe` · `rayneo-*` · `codex-bridge` · `display-observer` | V1 独立客户端与 Swift 模块，见 [V1 说明](docs/v1-sdk.md) |
| `watch-remote` | Apple Watch 遥控实验 |
| `third-party` | 第三方依赖，许可见 [第三方说明](THIRD_PARTY_NOTICES.md) |
| `tools` · `scripts` | 离线分析工具；构建检查、打包与发布扫描脚本 |
| `docs` | 文档，入口是 [文档索引](docs/README.md) |

参与开发或使用编码助手前，先读 [AGENTS.md](AGENTS.md)：其中写明刷机与安装的安全规则、推送规则和检查命令。

## 隐私与许可

自己的Key保存在自己的iOS钥匙串；云对话会上传音频/识别文字，录音转写由用户手动触发。音频/Markdown留在自己的App容器，不覆盖原件，不自动上传NAS。Hash/CRC不是加密，也不构成全程端到端加密承诺。

当前有权授权的原创内容采用 [PolyForm Noncommercial 1.0.0](LICENSE)，用于非商业学习研究；未经授权不得商用或收费分发。历史 MIT 权利不追溯撤销，详见[许可说明](docs/LICENSING.md)。第三方组件及厂商通信库不因随工程使用而变更许可，具体归属见 [第三方说明](THIRD_PARTY_NOTICES.md)。本工程与设备厂商无官方隶属关系。

发布不包含个人录音、聊天、凭据、绑定数据库、原始日志、私有临时隧道配置或个人签名私钥。Android Release 的完整修改 APK 使用独立研究发行签名；单独列出的原厂砸壳 IPA 不含 Turbo IO 扩展，原厂部分也不适用本仓库原创源码许可证。详见[源码发布说明](docs/SOURCE_RELEASE.md)；旧文档中“不提供安装包”的一概表述，以本页明确列出的发行例外为准。仍不提供合并 IPA / HAP，其他隐私边界不变。

<a id="support"></a>

## 请我喝杯咖啡 ☕

如果 Turbo IO 对你的研究和开发有所帮助，觉得好用，欢迎自愿打赏。感谢支持！请不要在打赏前私信要求作者先加功能，也不要用“做完某功能就打赏”作为交换条件；功能建议欢迎在 Issues 讨论，不承诺采纳或排期。

打赏完全自愿，不代表购买软件、功能定制、技术支持、售后或商业授权，不产生交付义务，也不改变本项目的非商业许可。

<p align="center">
  <img src="https://github.com/Turbo1123/turbometa-rayban-ai/raw/main/screenshots/%E8%AF%B7%E6%88%91%E5%96%9D%E5%92%96%E5%95%A1.png" alt="请我喝杯咖啡 · 自愿捐赠支持 Turbo IO" width="360" />
</p>
