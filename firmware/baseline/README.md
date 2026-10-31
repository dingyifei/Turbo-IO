# Baseline: immutable inputs older firmware trees used to provide

This folder replaces the old per-release folder copies (`strix-1.0.5.5-tmg2` … `-tmg7`). They stay in git history and behind the annotated `fw/tmgN` tags. Only files that code in this tree actually reads are copied here, byte for byte. Nothing in `baseline/` is edited, ever; a changed pin means a new, reviewed file.

| File | Read by | Provenance (path @ commit, release tag) | SHA-256 |
| --- | --- | --- | --- |
| `animation-frames.l8` | `build.py` (`animation_asset()`, pinned in code) | `firmware-research/strix-1.0.5.5-tmg2/assets/animation-frames.l8` @ `aa2d995`, tag `fw/tmg2` | `f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d` |
| `tmg3-build-inputs.json` | `tests/stock_abi_test.py` (the 25 patch sites and the raw edit must equal the audited TMG3 set) | `firmware-research/strix-1.0.5.5-tmg3/build-inputs.json` @ `b6af97f` (unchanged through `3e83832` and the `fw/tmg3` tag commit `e19b54e`), tag `fw/tmg3` | `1d5a7cf297032b15570714a492aa59ae75d25143e6c219285d315205b5ad34a1` |
| `kept/src/app-runtime-v1/app_service.c` | `tools/check_kept.py` | `firmware-research/strix-1.0.5.5-tmg2/src/app-runtime-v1/app_service.c` @ `aa2d995`, tag `fw/tmg2` | `9b98c9140e2735b8c32572fa136213c854b7d97c4cfdf66e31d16c8b23ad4ba9` |
| `kept/src/camera-v1/camera_native.c` | `tools/check_kept.py` | same path under `strix-1.0.5.5-tmg2/src` @ `aa2d995`, tag `fw/tmg2` | `bfd3f2c2fa193d1f19e58d5ae4d760ca095aa68dc82d87311d0ac126d42bb9c9` |
| `kept/src/focus-v1/focus_menu_native.c` | `tools/check_kept.py` | same, `fw/tmg2` | `b90f5b71c8f8abd516320b021a7a809ab88ce6faaeaf2ad4a0bd6765833b4ab2` |
| `kept/src/focus-v1/focus_service.c` | `tools/check_kept.py` | same, `fw/tmg2` | `249d24ee99e9d38d451b47203f7b30b2520e21612bcee5f4e52eb1646d9b366e` |
| `kept/src/music-runtime-v1/menu10.c` | `tools/check_kept.py` | same, `fw/tmg2` | `b63c8a56bd00392daecbc2f6389075b5a241a357b19aadd105b216ac25aa81ce` |
| `kept/src/music-runtime-v1/music_service.c` | `tools/check_kept.py` | same, `fw/tmg2` | `ffd1d9b9632350b2faf59d48da704829ecc245d74fb60cf753f0940cc11247e6` |
| `kept/src/navigation-runtime-v1/nav_service.c` | `tools/check_kept.py` | same, `fw/tmg2` | `f4965f593035e90c94b25b174848bb5fac051e6dc02adbfc9f0673e3a0924895` |

## Why `kept/` is a copy and not `git show fw/tmg2:…`

`tools/check_kept.py OLD NEW` proves that every `#include` and every called identifier of seven TMG2 files survives in the current tree, except the explicitly removed module symbols. Its input is a directory tree whose `src/` holds the seven TMG2 originals, and `baseline/kept/` is exactly that tree (96 KB). A copy keeps the gate meaning identical (same bytes, same comparison, same exit codes) and works in a shallow clone, in a worktree without tags, and offline. Reading `fw/tmg2` through `git show` would make the test depend on tags being fetched. The tags remain the authority: for every file above, `git rev-parse HEAD:firmware/baseline/<file>` must equal `git rev-parse fw/tmg2:<source path>` (`fw/tmg3:<source path>` for `tmg3-build-inputs.json`), where the source path is the one in the Provenance column (`kept/src/<x>` comes from `firmware-research/strix-1.0.5.5-tmg2/src/<x>`). Verified when this folder was created, and the proposed linecheck repeats the comparison on every run, so an edit to this folder fails H2.
