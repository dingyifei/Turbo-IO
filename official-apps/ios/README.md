# Stock decrypted iOS app inputs

This folder indexes the stock decrypted RayNeo IPAs. They contain **no Turbo IO addon** and they are not official source code. The IPAs are large, so they are stored in GitHub Releases; the binaries are kept out of Git history.

| Version | Status and use | Download |
| --- | --- | --- |
| **1.0.7 (230)** | Stock, decrypted, **all code signatures removed**. The exact-match input for APP107 / TMG2. The 1.0.7 host code is no longer in the current tree; see Git history, tags `app/c11` to `app/c13`. | [Notes and checksums](1.0.7/README.md) · [Release](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.7-230) |
| **1.0.6 (218)** | Stock, decrypted, **all code signatures removed**. Suitable as the input for TMIG1 / Strix 1.0.5.5 (archived in commit `27ad86e`: `official-addon/tmig1-edition/README.md`). | [Notes and checksums](1.0.6/README.md) · [Release](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.6-218) |
| 1.0.5 (201) | Older stock decrypted input. It keeps the App Store signing information it had at the time, not the maintainer's personal developer signature. It was not rebuilt the way the newer versions were. | [Notes and checksums](1.0.5/README.md) · [Older Release](https://github.com/Turbo1123/Turbo-IO/releases/tag/rayneo-ios-1.0.5-201) |

Copyright remains with RayNeo and the other rights holders. The license for this repository's original source code does not apply to the stock IPAs. Nothing here implies official endorsement. No personal accounts, service configuration, signing certificates or private keys are provided.

"Stock" means no custom features have been added. Because the files were decrypted, stripped of signatures and re-archived, they are not byte-for-byte identical to the encrypted App Store packages. **No package signed for you and ready to install is provided.** If you want Turbo IO, follow the guide for the matching version to merge, configure and sign it yourself. A normal encrypted App Store IPA cannot be merged directly.
