# 雷鸟 AI iOS 1.0.6（218）· 原厂砸壳 / 未签名 IPA

2026-10-15 · **[下载 IPA、SHA256SUMS 与审计报告](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.6-218)** · [版本索引](../README.md)

提供的是**原厂 1.0.6（218）应用的砸壳副本，未加入 Turbo IO，也没有修改应用功能**。为发布隐私与自行签名需要，移除了全部代码签名、描述文件及商店授权元数据，并重新归档。因此不等同于 App Store 原始加密包，也不能声称整包逐字节未变。

**版权仍归雷鸟官方及相关权利人。** 这不是官方应用源码，仓库的原创非商业源码许可不覆盖原厂二进制；归档不改变其版权或原有许可，不表示官方背书。

## 精确产物

| 项目 | 值 |
| --- | --- |
| 文件 | `RayNeo_AI_1.0.6_218_decrypted_unsigned_original.ipa` |
| 版本 / Build | **1.0.6 / 218** |
| Bundle ID | `com.rayneo.venus.pub` |
| 架构 / 加密状态 | arm64；全部 95 个 Mach-O 均无启用的加密标记 |
| 大小 | **353,545,727 字节** |
| IPA SHA-256 | `f20d23c2e90c9f6effb73463491725d2a359af14b1afa1bc06cf68f61bf2a852` |
| 未签名 Runner SHA-256 | `d59823568be232b1742f7414a6ebae4718f053e1a251577808041b032306bd44` |
| 未签名 App.framework/App SHA-256 | `57d064491c46a21420fd73c969ebfb390707556861526e62db58633514caf884` |

解压不是签名，去签名也不是替你签名。非越狱设备仍需自己的合法证书、描述文件和设备授权，不能将此文件当作为自己预签名的安装包。自签 App 的官方登录/推送等权限还需独立验证。

## 清理与核验范围

- **95/95 个 Mach-O 的代码签名移除**，不重新签名；最终 `LC_CODE_SIGNATURE` 数量为 0，不携带签名证书与 entitlements 签名块。
- 清理签名目录、`SC_Info`、商店收据和 provisioning 等元数据，本轮共移除 102 个文件；不发布个人签名、Apple 开发者账号/设备列表、Cookie、Key 或应用数据备份。
- 对照已保存的原厂解密代码，检查 UUID、加载依赖、归一化加载命令、全部文件内 section 内容及签名前数据，**可执行代码和依赖未改变**；签名相关头部/链接区长度变化明确允许，资源 2610 项保持原样。
- 对照本机个人签名 profile 的标识进行包内扫描，未发现匹配；报告只给结果，不包含被比对的标识。
- IPA 共 2705 个成员，ZIP CRC 与归档成员逐个回读一致；原始输入保持不变。
- 不含 Turbo IO、研究探针、越狱注入加载项、个人模型、Watch 扩展或账号数据目录。检查不等于审计官方应用全部业务、第三方服务或嵌入的厂商配置。

[审计报告](audit.json) / [SHA256SUMS](SHA256SUMS) 同时附在 Release。

```sh
shasum -a 256 -c SHA256SUMS
unzip RayNeo_AI_1.0.6_218_decrypted_unsigned_original.ipa -d /absolute/new-input
```

## 合并 Turbo IO

新版对应 **TMIG1 插件（已归档 / archived in git tag `archive/editions-2026-10`: `official-addon/tmig1-edition/README.md`）** 和 **[Strix OS 1.0.5.5](../../../firmware-research/strix-1.0.5.5/README.md)**。使用最新版仓库打包器，其精确接受原始签名保留版及本 Release 未签名版这两个固定 App.framework 哈希，**没有放宽固件哈希、清单或刷写门禁**。

本未签名副本已通过清理审计与打包输入/加载项测试，尚未把这份去签名派生包重新签名安装做整包真机回归。此前 iPhone 17 Pro Max 的 1.0.6 / TMIG1 实测与此发行输入的审计是不同证据，不能混为“此 IPA 可直接安装或已全量验收”。

`sanitize.py` 只处理已有合法未加密输入或先前已取得的解密主程序，不执行砸壳/设备提取、联网、签名、安装或刷写；拒绝未知 App.framework、启用加密的代码与研究注入项。输出必须为新的目录，原始输入不修改。使用者仍需有权使用所提供输入。
