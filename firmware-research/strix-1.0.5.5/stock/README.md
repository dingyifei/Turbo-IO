# Strix OS 1.0.5.5 · Official original firmware archive

2026-10-14. **This is the official stock version, with no Turbo IO changes. It is not a modified build and not a repacked ZIP.**

**[Download the original ZIP](Strix-OS-1.0.5.5-original.zip) · [SHA256SUMS](SHA256SUMS) · [TMIG1 custom package and risks](../../README.md)**

- Source: a real firmware update response to RayNeo AI iOS **1.0.6 (218)**; only the official download file was archived, exactly as downloaded.
- Official download address: [original firmware file](https://file-tdp-ffalcon-o.api.leiniao.com/res/e655a4a0/thirdapk_824eb1d21bb2be146ec2b9043cca438e.zip). The server link may change; check the archive against the hash pinned in this repository.
- Size: **8,740,749 bytes**.
- Server / original package MD5: `824eb1d21bb2be146ec2b9043cca438e`.
- SHA-256: `2927917f976ef3c9b183253e2342a7a0c85a3e454e973876100f3158da5ec367`.
- The ZIP has 16 entries: 15 stock payloads and `OtaFileInfo.json`. The ZIP CRCs and each payload's Size/MD5 were all checked. It includes the new `bt_controller.bin`.

```sh
cd firmware-research/strix-1.0.5.5/stock
shasum -a 256 -c SHA256SUMS
```

## If you want to go back to stock

First use **the compatible firmware update and vendor support process that the official RayNeo app normally offers**, and confirm that it really is an applicable stock candidate. Do not put the old 1.0.4.12 AP into a newer full package, and do not force-flash based on a name or a rename alone.

**The public TMIG1 installer from this release is pinned to the custom package and refuses to treat this stock ZIP as TMIG1.** Whether RayNeo offers a same-version reinstall depends on its update process; this project does not currently promise a one-step same-version recovery tool that can import this archive. Do not remove the hash, device, manifest or flash protections to recover. Developers who need a stock recovery should separately verify a matching normal install path; until that is confirmed, use this file only for offline analysis and comparison.

This is an OTA file. It is not a full flash backup, a bootloader backup or an unbricking tool. If the device no longer boots, has lost Bluetooth/OTA, or its flash state is unknown, having the stock ZIP does not guarantee recovery. **Non-developers must not flash it. A power loss, an interruption or a mistake can all damage the device.**

Copyright stays with RayNeo and the original rights holders; archiving does not relicense the stock firmware as this repository's original open-source code. It contains no personal accounts, cookies, keys, device records or Apple signing material.
