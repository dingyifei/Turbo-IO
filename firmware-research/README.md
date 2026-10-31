# 固件研究与固定版本索引

所有自定义包均为**非官方、高风险实验用品**。小白不要刷，日常使用请使用官方 App 与原厂固件。掉电、中断、错包或缺陷可能导致设备损坏；不保证回滚、恢复或救砖。

| 底座 | 自定义研究 | 官方原版 |
| --- | --- | --- |
| **Strix OS 1.0.5.5 / TMG2 – TMG8**（TurboIO 自定义固件） | 不再按版本复制文件夹：唯一源码树是 [`../firmware/`](../firmware/README.md)，版本标签在 `../firmware/RELEASE`（现为 TMG8）。每个候选对应 git 标注标签 `fw/tmg2` … `fw/tmg8`，`git checkout fw/tmgN` 即得当时源码；TMG3 为 13 项 EN/ZH 菜单与 POSE2 预测，TMG2 为可选两/三排菜单、矢量导航运行时与 NAVS3 手机端（原样刷入反馈与公开可复现构建；锁屏导航问题未闭环）。均为 CANDIDATE-NOT-APPROVED；各候选的 ZIP 哈希与设备验收状态写在对应 `fw/tmgN` 标签说明里 | 沿用下方 1.0.5.5 原始 ZIP |
| **Strix OS 1.0.5.5** | [TMIG1 新底座迁移、情境英语、App 1.0.6（218）](strix-1.0.5.5/README.md)，2026-10-14 iPhone 17 Pro Max 用户实刷兼容；Dots 开发中未完成 | [官方原始 ZIP / SHA-256](strix-1.0.5.5/stock/README.md)，字节不变、未重封装 |
| Strix OS 1.0.4.12 | [历史研究索引](strix-1.0.4.12/README.md)，各功能/候选有独立源码、手机门禁和验收边界 | [原厂负载归档](strix-1.0.4.12/stock/README.md)，负载未改、ZIP 重封装 |

版本号只是条件之一，还要核对 ZIP 哈希、官方宿主构建号、扩展标记及固定门禁。旧 iOS / Android 候选不能换文件名或哈希强刷新版；新 AP 不能简单平移旧补丁地址。

完整 OTA 不等于只写 AP。TMIG1 的自定义变化只在**相对新原厂包**的 application 中，其他负载随官方底座升级，并非固定在旧版本。原厂归档用于分析与受控恢复研究，不是通用一键救砖包。
