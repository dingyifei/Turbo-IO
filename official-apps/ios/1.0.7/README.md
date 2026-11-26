# RayNeo AI iOS 1.0.7 (230) · Stock decrypted / unsigned IPA

2026-10-19 · **[Download the IPA, SHA256SUMS and audit report](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.7-230)** · [Version index](../README.md)

This is **a decrypted copy of stock 1.0.7 (230). It contains no Turbo IO code and the stock feature code is unchanged.** Every code signature, provisioning profile and store authorization metadata file was removed and the archive was repacked. It is not the original encrypted App Store package, and it is not a signed, ready-to-install product.

**Copyright stays with RayNeo and the other rights holders.** This is not official source code. The repository's original source license does not cover the stock binary, does not change its original license and does not imply endorsement by RayNeo. You must have the right to use this input.

## Exact artifact

| Item | Value |
| --- | --- |
| File | `RayNeo_AI_1.0.7_230_decrypted_unsigned_original.ipa` |
| Version / Build | **1.0.7 / 230** |
| Bundle ID | `com.rayneo.venus.pub` |
| Architecture / encryption | arm64; none of the 95 Mach-O files has encryption turned on |
| Size | **353,804,631 bytes** |
| IPA SHA-256 | `50df3954845e3bc2e34f9ba6def8c3837e9d1a6c232f36f3a975dd08152a3ff7` |
| Unsigned Runner SHA-256 | `765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3` |
| Unsigned App.framework/App SHA-256 | `041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d` |

## Signature removal and privacy checks

- **Signatures removed from 95/95 Mach-O files.** A separate read-back of the archive confirmed that `LC_CODE_SIGNATURE`, `LC_DYLIB_CODE_SIGN_DRS` and code images with encryption turned on all number 0.
- 102 signature and store metadata files were cleaned, including the signature directories, SC_Info, receipts and provisioning profiles. Nothing was re-signed.
- Compared with the existing stock decrypted input: the UUIDs, load dependencies, normalized load commands, all in-file sections and pre-signature data match. Length changes in the signature-related header and link-edit areas are allowed; the other 2610 resource entries are unchanged.
- A scan for the identifiers in the local personal signing profile found 0 matches. The compared identifiers, cookies, keys, app data, personal signatures and certificate private keys are not published.
- The ZIP CRCs and each of the 2705 archive members passed read-back. The original input is unchanged.
- It contains no Turbo IO, research probes, jailbreak injection load commands, personal models or Watch extension. These checks are not a complete audit of all stock business logic or vendor built-in configuration.

The [audit report](audit.json) and [SHA256SUMS](SHA256SUMS) are also attached to the release; the large IPA is stored in the release and is not added to the git history.

```sh
shasum -a 256 -c SHA256SUMS
unzip RayNeo_AI_1.0.7_230_decrypted_unsigned_original.ipa -d /absolute/new-input
```

## Merging Turbo IO

Use the latest [APP107 / iOS 1.0.7 integration folder](../../../ios-addon/README.md). The packager accepts exactly the **paired hashes** of Runner + App.framework for either the original signature-preserved version or this release's de-signed version. It does not accept a mix, other versions or unknown re-signed inputs, and it does not relax the firmware checks or the single-flash gate.

You must still complete the merge signing with your own lawful certificate, provisioning profile and device authorization; unzipping or removing signatures is not signing. Official login, push and other entitlements need separate verification. A 1.0.6 input cannot stand in for this version.

1.0.7 / TMG2 has been tested on an iPhone 17 Pro Max. **This de-signed derived input has only had the release audit and a local package-and-sign check; it has not been installed separately for a full-feature real-device regression.** Do not take the former as meaning this IPA is pre-signed or works out of the box.

`sanitize.py` processes only an existing stock unencrypted input with a pinned hash, or a decrypted main binary already obtained. It does not decrypt on a device, extract over the network, install, sign or flash. The output must be a new directory; the original input is not modified. Unknown versions, code and research injections are refused.
