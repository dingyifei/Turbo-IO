# RayNeo AI iOS 1.0.6 (218) · Stock decrypted / unsigned IPA

2026-10-15 · **[Download the IPA, SHA256SUMS and audit report](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.6-218)** · [Version index](../README.md)

This is **a decrypted copy of the stock 1.0.6 (218) app. It contains no Turbo IO code and none of the app's features were changed.** For release privacy and so that you can sign it yourself, every code signature, provisioning profile and store authorization metadata file was removed and the archive was repacked. It is therefore not the same as the original encrypted App Store package, and it cannot be claimed to be byte-for-byte unchanged as a whole.

**Copyright stays with RayNeo and the other rights holders.** This is not the official app's source code. The repository's original non-commercial source license does not cover the stock binary; archiving it does not change its copyright or its original license, and does not imply endorsement by RayNeo.

## Exact artifact

| Item | Value |
| --- | --- |
| File | `RayNeo_AI_1.0.6_218_decrypted_unsigned_original.ipa` |
| Version / Build | **1.0.6 / 218** |
| Bundle ID | `com.rayneo.venus.pub` |
| Architecture / encryption | arm64; none of the 95 Mach-O files has encryption turned on |
| Size | **353,545,727 bytes** |
| IPA SHA-256 | `f20d23c2e90c9f6effb73463491725d2a359af14b1afa1bc06cf68f61bf2a852` |
| Unsigned Runner SHA-256 | `d59823568be232b1742f7414a6ebae4718f053e1a251577808041b032306bd44` |
| Unsigned App.framework/App SHA-256 | `57d064491c46a21420fd73c969ebfb390707556861526e62db58633514caf884` |

Unzipping is not signing, and removing signatures is not signing it for you. A non-jailbroken device still needs your own lawful certificate, provisioning profile and device authorization; do not treat this file as an install package pre-signed for you. Official login, push and other entitlements of a self-signed app have to be verified separately.

## What was cleaned and checked

- **Code signatures removed from 95/95 Mach-O files**, with no re-signing. The final `LC_CODE_SIGNATURE` count is 0; no signing certificate or entitlements signature blob is included.
- Signature directories, `SC_Info`, store receipts, provisioning and similar metadata were cleaned; 102 files were removed in this round. No personal signature, Apple developer account or device list, cookie, key or app data backup is published.
- Against the saved stock decrypted code, the UUIDs, load dependencies, normalized load commands, all in-file section contents and pre-signature data were checked: **the executable code and dependencies are unchanged**. Length changes in the signature-related header and link-edit areas are explicitly allowed; the 2610 resource entries are unchanged.
- The package was scanned for the identifiers in the local personal signing profile, with no match. The report gives only the result, not the identifiers compared against.
- The IPA has 2705 members; the ZIP CRCs and each archive member were read back and match. The original input is unchanged.
- It contains no Turbo IO, research probes, jailbreak injection load commands, personal models, Watch extension or account data directories. These checks are not an audit of all of the official app's business logic, third-party services or embedded vendor configuration.

The [audit report](audit.json) / [SHA256SUMS](SHA256SUMS) are also attached to the release.

```sh
shasum -a 256 -c SHA256SUMS
unzip RayNeo_AI_1.0.6_218_decrypted_unsigned_original.ipa -d /absolute/new-input
```

## Merging Turbo IO

This version pairs with **the TMIG1 addon (archived in commit `27ad86e`: `official-addon/tmig1-edition/README.md`)** and **Strix OS 1.0.5.5 (research tree deleted; see `git show 5b6c63d:firmware-research/strix-1.0.5.5/README.md`)**. Use the latest repository packager. It accepts exactly two pinned App.framework hashes, the original signature-preserved one and this release's unsigned one, and **does not relax the firmware hash, manifest or flash gates**.

This unsigned copy has passed the cleaning audit and the packaging input / load command tests. The de-signed derived package has not yet been re-signed, installed and given a whole-package real-device regression. The earlier 1.0.6 / TMIG1 test on an iPhone 17 Pro Max and the audit of this release input are separate evidence; do not merge them into "this IPA installs directly or is fully accepted".

`sanitize.py` processes only an existing lawful unencrypted input or a previously obtained decrypted main binary. It does not decrypt or extract from a device, go online, sign, install or flash. It refuses an unknown App.framework, code with encryption turned on, and research injections. The output must be a new directory; the original input is not modified. You still need the right to use the input you provide.
