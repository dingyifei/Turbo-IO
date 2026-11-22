# TurboIO firmware

The source for the patched Strix OS firmware of the RayNeo iO glasses. The build compiles a module, links it into stock `nuttx_ap.bin` at the patch sites pinned in `build-inputs.json` (`editCount`) and packs the result with the other stock payloads, unchanged, into an OTA ZIP.

There is one tree. The release label is the single line in [`RELEASE`](RELEASE). `build.py` names the ZIP from it and `tools/phone_pins.py` names the phone pins from it. Each released firmware is an annotated git tag `fw/tmgN`. Run `git show fw/tmgN` to see its ZIP hash and paired phone build. Release history lives in those tags, in git history and in [docs/CHANGELOG.md](../docs/CHANGELOG.md).

Agents never flash. The owner flashes, with the steps in [OTA.md](../ios-addon/OTA.md).

## Current release: TMG12

TMG12 is on the owner's glasses: flashed from C20 on 2026-11-15, with the update confirmed after the first boot, and the owner's first check passed. It is tagged `fw/tmg12`. No full TMG12 device checklist has been run yet. The ZIP keeps its pinned file name, `CANDIDATE-NOT-APPROVED` included. The phone build that flashes it is C20 (release `c20` in [releases.json](../ios-addon/releases.json)).

TMG12 is TMG11 ported to stock Strix OS 1.0.6.11 (`stockBase` in [`build-inputs.json`](build-inputs.json)).

| Item | Value |
| --- | --- |
| ZIP | `StrixOS-1.0.6.11-TurboIO-TMG12-CANDIDATE-NOT-APPROVED.zip`, 9,549,211 bytes |
| ZIP SHA-256 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| ZIP MD5 | `063b380629e1a01fcde04ce45a5dac15` |
| Pinned copy | `$TURBO_INPUTS/tmg12/` |
| AP (`nuttx_ap.bin`) | 8,132,360 bytes, SHA-256 `6b6afd77ce845aca83c52ce23c5a1eae006a7d36ca1cc89536dff3ec795aba50`, MD5 `96eebf1467b53759e816f05057df506e` |
| Module | 165,116 bytes at 0x10929204 |
| Build identity (status `build` field) | `0f43c519fc964dc4bd578cf9d7193e502b5c5daa17f3061fba26ccec0280fc55` |
| Package | 17 entries: 16 payloads and `OtaFileInfo.json`. Only `nuttx_ap.bin` differs from stock; the other 15 payloads are stock 1.0.6.11, byte for byte. |
| Audit | 25 patch sites, 7 startup descriptors, stock cores `Strix OS 1.0.6` build 11 |
| Toolchain | LLVM/LLD 23.1.5 |

### Do not repin while TMG12 is current

The build identity is 32 bytes in the AP, at AP offset 0x7b45fe. It hashes `build.py` and every source. `build.py` was edited after the last repin, but nothing it compiles or links changed. So `build-inputs.json` carries `identityCarryOver` for `build.py`: it binds the hash of the older `build.py` (`carried`) to the current file (`live`). `tests/identity_test.py` allows this only next to the TMG12 ZIP pin.

A `--repin` drops the carry-over. The AP then differs in those 32 bytes (identity `45c4c4ba3d07b380314f59d8ffad7fdd30923f3bddec329aaaf6c15c1c2b8e13`), and the ZIP no longer matches the pinned release. Repin only when you make a new release.

### What TMG12 changes

- The carousel has 8 stock and 6 module tiles: 14 items, module ids 8 to 13.
- The module's navigation tile is labelled Turbo Nav. Stock's own Navigation app is added to the remote's input gate.
- The Sensors page (Display Test, then one knob press) shows a "UI heap" line: the LVGL memory in use and its peak. It updates once a second.
- A new "Light" line shows the bucket of the light value stock last cached ("0-1 lx" to "5000+ lx", or "n/a"). It is read through stock's own getter (`tio_light_latest` in `link.ld`). The module never starts or stops the sensor. Build with `TIO_SENSORS_LIGHT=0` to remove the line.
- Tile settings are stored in new version-2 files (`turbo_tiles_v2_{0,1}.cfg`). The TMG11 order and hidden set are not carried over; TMG12 starts with the default order.
- Tile commands from an old phone build (version 1) are refused with no reply.

Stock 1.0.6.11 changed these, and the port follows:

- The menu object is 0x10c bytes (it was 0xfc), so the allocation with the module's tail is 0x130.
- Stock has 8 tiles, with Navigation at index 4. Every stock tile from index 4 up moved by one.
- The launcher's manager pointer is at +0x15c (it was +0x3c).
- The package holds 16 payloads, one more than 1.0.5.12.

Every stock offset the tree uses is named in [`src/stock_layout.h`](src/stock_layout.h) and proven from the stock image by `tests/stock_layout_test.py`.

### What was checked

- The firmware-only gate passed with a plain build of the tree.
- The ZIP is byte-identical to candidate 4's (`tmg12(42)`). Three plain builds, one from the worktree and two from clean copies, gave the same bytes.
- A static check found no changed byte on the boot-confirm path, and nothing in the module posts to the OTA queue.
- The emulator ran the candidates with no crash, assert, hang, reset or new guest-error class. The Display page passed 100 open and close cycles.
- `tools/phone_pins.py` builds the phone pins from this ZIP for the 1.0.21 full host (for C20 then; now the TMG12 package of `c21`).

Not checked: anything on glasses, the phone link, the OTA install of a 1.0.6.11 package and its post-boot confirm, real sensors and real timing.

### Known limits

- If the menu's arming check fails (trace event 141), the menu stays unarmed. The carousel does not animate, but the build still advertises and is confirmed, so the fix is a reflash. Event 142 means the menu's canary word was overwritten; the menu then reads as unarmed.
- With event 141 result 4, stock logs a warning at each step and show while the selection is past index 7, and a press there launches nothing.
- The Light line keeps showing the last bucket after the sensor stops.
- The phone status shows the LVGL heap total as not available.
- The first "UI heap" interval after the Sensors page opens can be shorter than a second.
- The Turbo Display page has no top-app check. Behind an app that opens without hiding the menu, the page stays until its deadline (60, 120 or 300 s).
- The system heap is smaller than on 1.0.5.12: 24,241,248 bytes against 27,004,960. The module's worst case live at once is about 350 KB.

### Device check

There is no full TMG12 checklist yet. Until there is one, check at least the following, and compare with the TMG11 owner check below:

1. RayNeo › Glasses › Software version shows Strix OS 1.0.6.11, and Turbo › Developer › Glasses runtime, row "Firmware and build", shows the build identity above.
2. The carousel has 14 items, the navigation tile reads Turbo Nav, and every tile behaves as on TMG11.
3. The tile order is the default one.
4. Display Test opens, and one knob press shows "Sensors (read only)".
5. The IMU line reads ST or TDK.
6. Folding the glasses changes the fold line.
7. Turning and pressing the knob change its counts.
8. The "UI heap" line shows memory, and the "Light" line shows a lux bucket.
9. Leaving the page restores normal menu stepping.

For comparison, the TMG11 owner check on 2026-11-12 found: IMU ST; fold reads "open" when unfolded (the Hall sensor is on the right hinge); the knob counts negative counter-clockwise, about 1,200 counts per turn. The C18 sensor log named the ST IMU (LSM6DSO32 driver, WHO_AM_I 0x6b), the MMC5603NJ magnetometer (ID 0x10), the W1161 light sensor (ID 0xe6) and the Mixo OTS knob (ID 0xB1).

To go back, see [Going back](../ios-addon/OTA.md#going-back) in OTA.md.

## Build

You need:

- `TURBO_INPUTS` exported in every shell. It is the folder with the toolchain, the release ZIPs and `package.env`. `scripts/turbo-gate.sh` exports it for its own stages; a direct run of `test.py` or of a test in `firmware/tests/` does not.
- The pinned toolchain: LLVM/LLD 23.1.5 in `$TURBO_INPUTS/toolchain/llvm-bin`. It has no `llvm-objdump`, so no tool here may need one. No package manager is needed.
- The stock ZIP of the tree's base. Get its path from `build.py --show stock-zip`; never type it by hand. For 1.0.6.11 it is a canonical ZIP of the stock members under `$TURBO_INPUTS`, made by `tools/stock_zip.py`.

Build and audit:

```sh
export TURBO_INPUTS=<the inputs folder>
R=$(git rev-parse --show-toplevel)
FW=$R/firmware
TC=$TURBO_INPUTS/toolchain/llvm-bin
STOCK=$(python3 -I "$FW/build.py" --show stock-zip)
ZIP=$(python3 -I "$FW/build.py" --show archive-name)
D=$(mktemp -d)
python3 -I "$FW/tools/rebase_apply.py" --check --stock "$STOCK"
python3 -I "$FW/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$D/build"
python3 -I "$FW/build.py" --stock "$STOCK" --audit "$D/build/$ZIP"
cmp "$D/build/$ZIP" "$TURBO_INPUTS/tmg12/$ZIP"
```

- `rebase_apply.py --check` confirms the tree is wholly on its stock base.
- A plain build asserts every pin in `build-inputs.json` and stops at the first mismatch. It writes the ZIP and `audit.json` to `--out`.
- `--audit` checks a ZIP: the patch sites, the unchanged stock payloads, the startup descriptors, the stock cores and an AP below 9,600,000 bytes.
- `tests/rebase_independent_test.py` re-derives every rebased address. It takes about 40 s.

Other `--show` values: `base` (the stock base) and `emu-only` (`false` for this tree).

## Update the pins

Do this only for a new release. It ends the TMG12 identity carry-over (see above).

1. Change the source. If the label changes, edit `RELEASE`.
2. Run the build with `--repin` in place of a plain build:
   ```sh
   python3 -I "$FW/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$D/repin" --repin
   ```
   It writes `$D/repin/build-inputs.pinned.json`.
3. Review the diff, then copy that file over `firmware/build-inputs.json`.
4. Run a plain build again. It must pass with the new pins.
5. Copy the ZIP to `$TURBO_INPUTS/<folder>/`. Add or update its entry in `ios-addon/releases.json`: `firmware`, `stockBase`, `zip.input` (relative to `$TURBO_INPUTS`), `zip.bytes`, `zip.sha256`, `acceptCurrent` and `hosts`. Paste the size and hash from command output.
6. Regenerate and check the phone pins (`FirmwarePins.h` and `firmware-pins*.json`):
   ```sh
   python3 -I "$FW/tools/phone_pins.py" --write "$R/ios-addon" --inputs "$TURBO_INPUTS"
   python3 -I "$FW/tools/phone_pins.py" --check "$R/ios-addon" --inputs "$TURBO_INPUTS"
   ```
   `--check` prints `PHONEPINS_OK` and the release names. `--tree-release` prints the release whose ZIP is the tree's build (today `c21`).

`phone_pins.py` refuses emulator-only builds in every mode. It also refuses the superseded TMG12 candidates 1 to 3 by their SHA-256 (`SUPERSEDED_ZIPS`).

## Gate

Run `bash scripts/turbo-gate.sh --firmware-only` for the firmware checks alone. It needs no phone build, no `package.env` and no `releases.json` entry, and writes its report to `ios-addon/build/gate-firmware/`. It cannot be combined with `--preview`, `--only-build` or `--skip-tests`. Its stages, in order:

1. `fw-rebase`: `rebase_apply.py --check`.
2. `fw-layout`: the stock-layout proof, `tools/check_layout.py` (no raw stock offset in built code) and its self-test, the host drivers, the independent rebase check, `stock_abi_test`, `stock_base_test`, `tools/check_kept.py`, `tools/check_cjk.py`, the stock name and grid label tests, and the tile model.
3. `fw-build`: a plain build of the tree, then `tests/sensors_light_off_link_test.py`. With `--tree-zip ZIP` it compiles only and uses the given ZIP.
4. `fw-audit`: `build.py --audit` of the tree ZIP.
5. `fw-tests`: `test.py --firmware-only`.
6. `fw-reproduce`: rebuilds the newest `fw/tmgN` tag merged into HEAD (today `fw/tmg12`) with that tag's own `build.py` and pins.
7. `source-audit`.

A pass ends with `GATE PASS (firmware-only, plain build)`. Run it without `--tree-zip`.

The full gate (`bash scripts/turbo-gate.sh`, see [AGENTS.md](../AGENTS.md)) runs `fw-layout` but none of the other firmware-only stages. It builds the phone addon, checks the pins and runs the phone `test.py`. It looks the tree's ZIP up in `releases.json`, so a release that carries this ZIP must be listed there.

## Reproduce an earlier release

The tree's `build.py` cannot rebuild an earlier release, because the build identity hashes `build.py` and every source. Rebuild from the tag, with its own `build.py`, pins and stock ZIP:

```sh
TAG=fw/tmg11
BASE=$(git -C "$R" show "$TAG":firmware/build-inputs.json | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["stockBase"])')
mkdir "$D/old" && git -C "$R" archive "$TAG" firmware "firmware-research/strix-$BASE/stock" | tar -x -C "$D/old"
python3 -I "$D/old/firmware/build.py" --stock "$D/old/firmware-research/strix-$BASE/stock/Strix-OS-$BASE-original.zip" --llvm-bin "$TC" --out "$D/old/out"
```

The recipe works as written for `fw/tmg10` and `fw/tmg11`, with LLVM/LLD 23.1.5 (`$TURBO_INPUTS/toolchain/llvm-bin`). For `fw/tmg9`, whose pins have no `stockBase`, set `BASE=1.0.5.5` by hand and use LLVM/LLD 23.1.4 (`$TURBO_INPUTS/toolchain/llvm-23.1.4/bin`). TMG8 and older were built from `firmware-research/strix-1.0.5.5-tmgN` at their tags, not from `firmware/`; the tag message names the folder. TMG2 does not reproduce with either toolchain; its tag note says why.

## Earlier releases

| Tag | Stock base | Phone build | ZIP SHA-256 |
| --- | --- | --- | --- |
| `fw/tmg11` | 1.0.5.12 | C18 | `edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1` |
| `fw/tmg10` | 1.0.5.12 | C16 | `4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c` |
| `fw/tmg9` | 1.0.5.5 | C13 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` |
| `fw/tmg8` | 1.0.5.5 | C12 | `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6` |
| `fw/tmg7` | 1.0.5.5 | C11 | `6b06d0dd3124ac1f86c91e0879908f9bfe129a2051cf0b619d5b0b664bc3c0aa` |
| `fw/tmg6` | 1.0.5.5 | C10 | `a134c0f9d8550cdd5b53559e4857e27ca92ec8b168543d2c357cbc1e3fbe4d6e` |
| `fw/tmg5` | 1.0.5.5 | C9 | `6705bf4d164178943018d55ac882cf796bbc255f186d0be509ecb2f798ede0ef` |
| `fw/tmg4` | 1.0.5.5 | C8 | `aa387b37ece2092d50721bcc3409984f7bd0d650aad4b7b249aceba515161126` |
| `fw/tmg3` | 1.0.5.5 | C6 | `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274` |
| `fw/tmg2` | 1.0.5.5 | C1 to C5 | `6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473` |

Flash only a ZIP whose SHA-256 matches its tag. Never use a superseded ZIP; the tag notes name them.

## Files

| Path | Contents |
| --- | --- |
| `RELEASE` | The release label |
| `build.py` | Build, audit, repin and `--show` |
| `build-inputs.json` | Every pin: stock base and hashes, the 25 edits, module, AP, ZIP and toolchain |
| `src/` | Module source; `src/stock_layout.h` names every stock offset |
| `link.ld`, `trampolines.S` | The link script with the stock symbol addresses, and the patch-site trampolines |
| `ImageWireFormat.h` | The image wire format shared with the phone |
| `include/`, `assets/` | Build includes and the menu icon art |
| `baseline/` | Immutable inputs carried over from older releases, and the rebase tables ([README](baseline/README.md)) |
| `tools/` | `rebase_apply.py`, `rebase_derive.py`, `phone_pins.py`, `stock_zip.py`, `check_layout.py`, `check_kept.py`, `check_cjk.py`, `encode_icons.py`, `test_branch.py` |
| `tests/` | Host tests and stock proofs |
