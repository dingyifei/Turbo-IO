# Strix OS 1.0.5.12 · 官方原始固件归档

2026-11-06。**这是官方原厂版本，不含 Turbo IO 自定义改动。不是修改版，也不是 ZIP 重封装。仅作分析与构建输入，绝不要刷写原厂包。**

**[下载原始 ZIP](Strix-OS-1.0.5.12-original.zip) · [SHA256SUMS](SHA256SUMS) · [TMG10 构建说明](../../../firmware/README.md)**

- 来源：2026-11-06 由**原版 RayNeo AI 1.0.11（259）**（Turbo IO 仅下载构建，App.framework 与原厂一致，因此访问的是雷鸟真实服务器）从雷鸟服务器下载；操作者停在“准备安装”，没有安装或刷写。文件从手机 App 数据目录只读复制，原样归档。
- 服务端文件名：`thirdapk_efd5bb5a679f5fda659401add30434ca.zip`（下载地址的最后一段）。本仓库改名为 `Strix-OS-1.0.5.12-original.zip`，字节不变。
- 大小：**8,769,953 字节**。
- 服务端/原包 MD5：`efd5bb5a679f5fda659401add30434ca`，与服务端文件名一致。
- SHA-256：`b7bfd3cc73528e3e9995ad227dc877c8334d43dc8051436e2d2ccff2ca0b4133`。
- ZIP 共 16 项：15 个原厂负载及 `OtaFileInfo.json`；ZIP CRC 与每个负载 Size/MD5 均核对。
- `nuttx_ap.bin`：7,313,036 字节，SHA-256 `af701a6525fbf703854b3d63e757734546c20bdb5d50e246867dc6a0565713ae`。AP、APC1、BTH 三个核心都报告 `SW_VER="Strix OS 1.0.5"`、`BUILD_VER="12"`、`REV_INFO=55bc20b0-dirty`。
- 与 1.0.5.5 相比：`nuttx_ap.bin`、`nuttx_apc1.bin`、`nuttx_bth.bin`、`pil_algo_vad_demo.dll` 和 `OtaFileInfo.json` 变化，其余 11 个文件不变。AP 与 APC1 之间的 A2DP RPC 也变了，所以 1.0.5.12 的 AP 不能与 1.0.5.5 的 APC1/BTH 混用（`firmware/build.py --audit` 会检查三个核心是同一底座）。

```sh
cd firmware-research/strix-1.0.5.12/stock
shasum -a 256 -c SHA256SUMS
```

## 用途

TMG10 以此为底座构建（`firmware/build-inputs.json` 的 `stockBase`、`stockZIP`、`stockAP`、`stockMembers`）。地址从 1.0.5.5 迁移到 1.0.5.12 的对照表是 `firmware/baseline/rebase-1.0.5.5-to-1.0.5.12.json`，由 `firmware/tools/rebase_derive.py` 生成、`firmware/tools/rebase_apply.py` 应用。

这是 OTA 文件，不是整机闪存备份、启动器备份或救砖工具。不要把它当作 TMG 包或回滚包刷写；手机端刷写门禁也不会接受它。**非开发者不要刷；掉电、中断、误操作均可能损坏设备。**

版权仍归雷鸟官方及原权利人，归档不把原厂固件重新许可为本仓库原创开源代码。不包含个人账号、Cookie、Key、设备记录或 Apple 签名材料。
