# Firmware research

This folder holds stock firmware and research material. The stock ZIPs in the two `stock/` folders are inputs to the firmware build and the gate (`firmware/build.py`, `firmware/baseline/rebase-*.json`, `firmware/tests/stock_base_test.py`, and the tag reproduction in `scripts/turbo-gate.sh`). Nothing else here is part of the current build. The current TurboIO glasses firmware has a single source tree, [`firmware/`](../firmware/README.md). Each released version is a git tag (`fw/tmg2` … `fw/tmg12`, plus `fw/tmg15` and `fw/tmg17`; TMG13, TMG14 and TMG16 were candidates only and have no tag). `git show fw/tmgN` shows that release's ZIP SHA-256 and its paired phone build.

Every custom package is an **unofficial, high-risk experiment**. If you are new to this, do not flash it; for daily use, use the official app and the stock firmware. Power loss, an interrupted transfer, the wrong package or a bug can damage the device. Rollback, recovery and unbricking are not guaranteed.

| Folder | Contents | Official original |
| --- | --- | --- |
| [strix-1.0.5.12](strix-1.0.5.12/stock/README.md) | Stock Strix OS 1.0.5.12 (downloaded on 2026-11-06 by the stock app 1.0.11): the build base for TMG10 and TMG11. It is for analysis and as a build input only; do not flash the stock package | [Official original ZIP / SHA-256](strix-1.0.5.12/stock/README.md), bytes unchanged, not repackaged |
| strix-1.0.5.5 | Stock Strix OS 1.0.5.5: the build base for TMG9 and earlier. The TMIG1 research tree was deleted in C21 and is kept in git history (`git show 5b6c63d:firmware-research/strix-1.0.5.5/README.md`) | [Official original ZIP / SHA-256](strix-1.0.5.5/stock/README.md), bytes unchanged, not repackaged |

The Strix OS 1.0.4.12 research tree and TVP2 (`strix-1.0.5.5-tvp2`) were deleted in cleanup(5) and are kept in git history. The stock 1.0.6.11 ZIP (the base from TMG12 on, including the current release TMG17) is not in the repo. It lives under `$TURBO_INPUTS`, and `firmware/build.py --show stock-zip` prints its path.

The version number is only one of the conditions. You also have to check the ZIP hash, the official host build number, the extension marker and the fixed gate checks. An old iOS or Android candidate cannot be force-flashed onto a newer version by changing its file name or hash, and old patch addresses cannot simply be carried over to a new AP.

A full OTA is not the same as writing only the AP. TMIG1's custom changes are only in the application, **relative to the newer stock package**; the other payloads upgrade with the official base and are not pinned to an old version. The stock archives are for analysis and controlled recovery research, not a general one-tap unbricking package.
