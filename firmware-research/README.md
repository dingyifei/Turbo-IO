# 固件研究

这里是原厂固件与研究资料。两个 `stock/` 目录里的原厂 ZIP 是固件构建与门禁的输入（`firmware/build.py`、`firmware/baseline/rebase-*.json`、`firmware/tests/stock_base_test.py`、`scripts/turbo-gate.sh` 的标签复现），其余内容不参与当前构建。当前的 TurboIO 眼镜固件只有一个源码树：[`firmware/`](../firmware/README.md)，每个版本是一个 git 标签（`fw/tmg2` … `fw/tmg12`），`git show fw/tmgN` 可查看该版本的 ZIP SHA-256 与配对手机构建。

所有自定义包均为**非官方、高风险实验用品**。小白不要刷，日常使用请使用官方 App 与原厂固件。掉电、中断、错包或缺陷可能导致设备损坏；不保证回滚、恢复或救砖。

| 目录 | 内容 | 官方原版 |
| --- | --- | --- |
| [strix-1.0.5.12](strix-1.0.5.12/stock/README.md) | 原厂 Strix OS 1.0.5.12（2026-11-06 由原版 App 1.0.11 下载）：TMG10 的构建底座，仅作分析与构建输入，不要刷原厂包 | [官方原始 ZIP / SHA-256](strix-1.0.5.12/stock/README.md)，字节不变、未重封装 |
| strix-1.0.5.5 | 原厂 Strix OS 1.0.5.5：TMG9 及更早版本的构建底座。TMIG1 研究树已在 C21 删除，保留在 git 历史中（`git show 5b6c63d:firmware-research/strix-1.0.5.5/README.md`） | [官方原始 ZIP / SHA-256](strix-1.0.5.5/stock/README.md)，字节不变、未重封装 |

Strix OS 1.0.4.12 研究树与 TVP2（`strix-1.0.5.5-tvp2`）已在 cleanup(5) 删除，保留在 git 历史中。原厂 1.0.6.11 ZIP（TMG12 的底座）不在仓库里，放在 `$TURBO_INPUTS` 下，由 `firmware/build.py --show stock-zip` 指出路径。

版本号只是条件之一，还要核对 ZIP 哈希、官方宿主构建号、扩展标记及固定门禁。旧 iOS / Android 候选不能换文件名或哈希强刷新版；新 AP 不能简单平移旧补丁地址。

完整 OTA 不等于只写 AP。TMIG1 的自定义变化只在**相对新原厂包**的 application 中，其他负载随官方底座升级，并非固定在旧版本。原厂归档用于分析与受控恢复研究，不是通用一键救砖包。
