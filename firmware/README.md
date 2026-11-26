# TurboIO firmware

The source for the patched Strix OS firmware of the RayNeo iO glasses. The build compiles a module, links it into stock `nuttx_ap.bin` at the patch sites pinned in `build-inputs.json` (`editCount`) and packs the result with the other stock payloads, unchanged, into an OTA ZIP.

There is one tree. The release label is the single line in [`RELEASE`](RELEASE). `build.py` names the ZIP from it and `tools/phone_pins.py` names the phone pins from it. Each released firmware is an annotated git tag `fw/tmgN`. Run `git show fw/tmgN` to see its ZIP hash and paired phone build. Release history lives in those tags, in git history and in [docs/CHANGELOG.md](../docs/CHANGELOG.md).

Agents never flash. The owner flashes, with the steps in [OTA.md](../ios-addon/OTA.md).

## Current release: TMG17

TMG17 is on the owner's glasses, flashed from C26 on 2026-11-24, but the owner has not yet accepted it as released and it is not tagged. The owner's checks of what is new since TMG15 have not been reported yet. The release record, with every hash, what was checked and the device status, is in [RELEASE.md](../ios-addon/RELEASE.md). The last tagged release is TMG15 (`fw/tmg15`), and C24 + TMG15 is the way back.

| | |
| --- | --- |
| Phone build | C26 (release `c26` in [releases.json](../ios-addon/releases.json)) |
| ZIP SHA-256 | `dab9cdbde8b5a29eb0f481b062ed3f82af4b56941eac8438d212dee3ffabae01` |
| Pinned copy | `$TURBO_INPUTS/tmg17/` |

The ZIP keeps its pinned file name, `StrixOS-1.0.6.11-TurboIO-TMG17-CANDIDATE-NOT-APPROVED.zip`, `CANDIDATE-NOT-APPROVED` included. The stock base is Strix OS 1.0.6.11 (`stockBase` in [`build-inputs.json`](build-inputs.json)). Two payloads differ from stock: the launcher image `nuttx_ap.bin` and the Bluetooth core's image `nuttx_bth.bin`. The design is in [docs/lock-design.md](../docs/lock-design.md).

TMG17 is TMG15, the PIN lock, with a new PIN screen (TMG16) and a fix for Do Not Disturb (TMG17). TMG13 (the lock alone) and TMG14 (the lock with head motion) were device candidates on the way to TMG15, and TMG16 was built but never flashed. None of the three is tagged.

The build identity is 32 bytes in the AP. It hashes `build.py` and every source. A plain build and a `--repin` build of the release tree give the same ZIP; there is no identity carry-over any more.

### What the lock does

Everything in TMG12 is still there. TMG15 added the lock:

- **When it locks.** After the glasses have stayed folded for the fold delay, or have sat unfolded and unused for the idle time. Both default to 5 minutes and are set on the phone, from 1 to 240 minutes. With the lock on, every boot starts locked.
- **While locked.** The display stays dark until the knob is pressed. A press shows the PIN screen, with the time and battery at the top. Notifications are not shown, then or later. The phone link keeps running.
- **PIN entry.** Four digits, one at a time: turn the knob to change the digit, press to move on, and the fourth press submits. A long press steps back, then leaves. Entered digits show as dots.
- **Wrong PINs.** Three free tries, then a wait of 30 s, 1 min, 5 min, and 15 min for every later try. The count survives a restart. Nothing is ever wiped. After the next unlock the glasses show "N wrong tries since last unlock", and so does the phone.
- **Nothing can be started.** While locked, the keys, the double press, the wake word and the microphone are refused. The rebond hold and the factory-reset confirm pass through to stock.
- **From the phone.** The phone that is paired and runs the addon can unlock, lock now, set or change the PIN, change the two times, and turn the lock off. There is no shared secret. After a phone unlock the glasses show "Unlocked" for 4 s once the panel is lit.
- **Head motion.** With "Stay unlocked while worn" on, head motion counts as use, so worn glasses do not idle-lock. The signal comes from a hook in the Bluetooth core's head-up detector. The hook is off after every boot; the phone switches it on after it connects.
- **Factory reset.** The stock factory reset also deletes the lock record.

### What TMG16 and TMG17 change

- **The PIN screen (TMG16).** It follows the design system ([LensLock](../docs/design-system/screens/LensLock.dc.html)). Four places across the bottom band. The digit being entered is drawn as a 34×50 px numeral over a short bar; entered digits show as dots and empty places as short bars. The time and battery are at the top; the hint replaces them for 3 s after the screen opens and after every turn or press. The other lock screens (wrong PIN, waiting, use the phone, the wrong-tries notice, "Unlocked") show one line in the middle band and one in the bottom band. Every buffer the screen hands to the stock drawing code is 64-byte aligned; TMG15's bar under the focused digit was not, and was drawn from the wrong address.
- **Do Not Disturb (TMG17).** On TMG15 and TMG16, with Do Not Disturb on, every PIN screen went dark about 3 s after it lit: Do Not Disturb's overlay moved to the top, and the lock closed any screen it found covered. Now, while a time-limited lock screen is lit (PIN entry, wrong PIN, waiting, use the phone, "Unlocked"), the lock holds the stock wake lock `turbo_lock_v1`, so stock's screen-off requests are refused. It lets go on every way out. When the one thing on top of the lock screen is Do Not Disturb's own overlay, the lock moves its screen back on top; anything else on top still closes it to dark.
- **The wrong-tries notice (TMG17).** It goes dark 30 s after it was shown or last touched, and stays dark. The next press or turn shows it again, and a press then dismisses it. Before, it had no timeout, and the lock relit the panel each time stock turned it off.

Without Do Not Disturb the timings are as in TMG15, except that a long PIN entry no longer blinks off when stock's 15 s screen timeout comes. The PIN rules, the phone protocol, the lock record and the Bluetooth image are unchanged.

### Lock record and patch sites

The lock record is two files, `/mnt/nand_data/turbo_lock_v1_0.cfg` and `turbo_lock_v1_1.cfg`. A firmware update keeps them. A damaged record starts locked.

The Bluetooth image gets a 452-byte module and three patch sites: the message switch (0x0c0aa958), the motion hook in the head-up detector (0x0c0bfe30), and the end of the boot-time memory clear (0x0c02a1fc), which makes the hook start switched off.

Every stock offset the tree uses is named in [`src/stock_layout.h`](src/stock_layout.h) and proven from the stock image by `tests/stock_layout_test.py`.

### What was checked

What was checked for TMG17 is in [RELEASE.md](../ios-addon/RELEASE.md#what-was-checked). For the lock itself, the emulator ran it from boot on TMG15: fold and idle locking, PIN entry, wrong-PIN waits, phone commands over the emulated link, and every branch of the Bluetooth hook.

Not checked on the glasses: the factory reset clearing the lock, a damaged lock record, and a restart with no phone in reach.

### Known limits

The lock is for honest people. It stops someone nearby from picking the glasses up and using them as you. It does not resist deliberate effort.

- Any phone that pairs with the glasses and runs the addon can unlock them.
- A feature started from the paired phone still starts on locked glasses. The glasses microphone does not open and nothing shows through the lock screen.
- With "Stay unlocked while worn" on, unfolded glasses that keep moving (in a bag, in a moving car) do not idle-lock.
- The clock is trusted only after the phone has set it since the last power-off. Until then every unfold and every screen-on locks again, and after three wrong tries the glasses ask for the phone instead of starting a wait.
- A phone that has never seen the glasses unlocked asks them once whether they have the lock. That path is covered by a host test only.

These TMG12 limits still apply:

- If the menu's arming check fails (trace event 141), the menu stays unarmed. The carousel does not animate, but the build still advertises and is confirmed, so the fix is a reflash. Event 142 means the menu's canary word was overwritten; the menu then reads as unarmed.
- With event 141 result 4, stock logs a warning at each step and show while the selection is past index 7, and a press there launches nothing.
- The Light line keeps showing the last bucket after the sensor stops.
- The phone status shows the LVGL heap total as not available.
- The first "UI heap" interval after the Sensors page opens can be shorter than a second.
- The Turbo Display page has no top-app check. Behind an app that opens without hiding the menu, the page stays until its deadline (60, 120 or 300 s).

### Device check

The owner ran items 1 to 10 on 2026-11-22 and 2026-11-23, on TMG14 with C23 and then on TMG15 with C24. All passed. Items 11 to 13 are new in TMG16 and TMG17; the owner flashed TMG17 on 2026-11-24 and has not reported them yet.

1. The update completes, also with the glasses locked. They boot, and the phone reconnects without pairing again.
2. Notifications, head-up wake and the Turbo features work as on TMG12.
3. Turbo › Glasses › Glasses lock: set a PIN. "Lock now" locks the glasses, and "Unlock glasses" unlocks them and shows "Unlocked" on the glasses.
4. Locked glasses stay dark until the knob is pressed. The PIN screen shows large digits, each centred over its line, and the right PIN unlocks.
5. Repeated wrong PINs start the wait. After the next unlock the glasses and the phone show the number of wrong tries.
6. While locked, a double press and "hey RayNeo" start nothing. No notification was seen on locked glasses.
7. A very long knob press restarts locked glasses, and they come back locked.
8. Folded for longer than the fold delay, then unfolded: locked.
9. "Stay unlocked while worn" on, idle time 1 min: worn glasses stay unlocked. Left unfolded on a desk they lock, and they stay locked when picked up.
10. After a restart, head motion counts again once the phone has reconnected, with no action on the phone.
11. The PIN screen shows the digit being entered as a large numeral over a short bar, entered digits as dots and empty places as short bars. After the hint fades, the time and battery show at the top.
12. With Do Not Disturb on, the PIN screen stays up while you enter the PIN, and the right PIN unlocks.
13. After an unlock that follows wrong tries, the notice left untouched goes dark after about 30 s and stays dark. The next press shows it again, and a second press dismisses it.

Not part of that run: the build identity row (Turbo › Developer › Glasses runtime, "Firmware and build", must show the identity in [RELEASE.md](../ios-addon/RELEASE.md)), and battery over a full day.

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
cmp "$D/build/$ZIP" "$TURBO_INPUTS/tmg17/$ZIP"
```

- `rebase_apply.py --check` confirms the tree is wholly on its stock base.
- A plain build asserts every pin in `build-inputs.json` and stops at the first mismatch. It writes the ZIP and `audit.json` to `--out`.
- `--audit` checks a ZIP: the patch sites in both images, the unchanged stock payloads, the startup descriptors, the stock cores, an AP below 9,600,000 bytes and a Bluetooth image no larger than its partition (0x180000 bytes).
- `tests/rebase_independent_test.py` re-derives every rebased address. It takes about 40 s.

Other `--show` values: `base` (the stock base) and `emu-only` (`false` for this tree).

## Update the pins

Do this only for a new release. A repin changes the build identity, so the ZIP no longer matches the pinned release.

1. Change the source. If the label changes, edit `RELEASE`.
2. Run the build with `--repin` in place of a plain build:
   ```sh
   python3 -I "$FW/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$D/repin" --repin
   ```
   It writes `$D/repin/build-inputs.pinned.json`.
3. Review the diff, then copy that file over `firmware/build-inputs.json`.
4. Run a plain build again. It must pass with the new pins.
5. Copy the ZIP to `$TURBO_INPUTS/<folder>/`. Add or update its entry in `ios-addon/releases.json`: `builds`, `hosts`, `stockBase` and `packages[]`. Each package has a `label`, a `zip` (`input` relative to `$TURBO_INPUTS`, `bytes`, `sha256`) and `acceptCurrent`; the first package is the TMG build and the second is the `STOCK-<base>` package. Paste the size and hash from command output.
6. Regenerate and check the phone pins (`FirmwarePins.h` and `firmware-pins*.json`):
   ```sh
   python3 -I "$FW/tools/phone_pins.py" --write "$R/ios-addon" --inputs "$TURBO_INPUTS"
   python3 -I "$FW/tools/phone_pins.py" --check "$R/ios-addon" --inputs "$TURBO_INPUTS"
   ```
   `--check` prints `PHONEPINS_OK` and the release names. `--tree-release` prints the release whose ZIP is the tree's build (today `c26`).

`phone_pins.py` refuses emulator-only builds in every mode. It also refuses the superseded TMG12 candidates 1 to 3 by their SHA-256 (`SUPERSEDED_ZIPS`).

## Gate

Run `bash scripts/turbo-gate.sh --firmware-only` for the firmware checks alone. It needs no phone build, no `package.env` and no `releases.json` entry, and writes its report to `ios-addon/build/gate-firmware/`. It cannot be combined with `--preview`, `--only-build` or `--skip-tests`. Its stages, in order:

1. `fw-rebase`: `rebase_apply.py --check`.
2. `fw-layout`: the stock-layout proof, `tools/check_layout.py` (no raw stock offset in built code) and its self-test, the host drivers, the independent rebase check, `stock_abi_test`, `stock_base_test`, `tools/check_kept.py`, `tools/check_cjk.py`, the stock name and grid label tests, and the tile model.
3. `fw-build`: a plain build of the tree, then `tests/sensors_light_off_link_test.py`. With `--tree-zip ZIP` it compiles only and uses the given ZIP.
4. `fw-audit`: `build.py --audit` of the tree ZIP.
5. `fw-tests`: `test.py --firmware-only`.
6. `fw-reproduce`: rebuilds the newest `fw/tmgN` tag merged into HEAD with that tag's own `build.py` and pins.
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
| `fw/tmg15` | 1.0.6.11 | C24 | `206d19f1bfb4b97f37826ed18c288c975e17ca83a066ad7d00a275c1be697d49` |
| `fw/tmg12` | 1.0.6.11 | C20, C21 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
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
| `build-inputs.json` | Every pin: stock base and hashes, the patch sites, both modules, AP, BTH, ZIP and toolchain |
| `src/` | Module source; `src/stock_layout.h` names every stock offset |
| `bth-v1/` | The head-motion module for the Bluetooth core's image |
| `link.ld`, `trampolines.S` | The link script with the stock symbol addresses, and the patch-site trampolines |
| `ImageWireFormat.h` | The image wire format shared with the phone |
| `include/`, `assets/` | Build includes and the menu icon art |
| `baseline/` | Immutable inputs carried over from older releases, and the rebase tables ([README](baseline/README.md)) |
| `tools/` | `rebase_apply.py`, `rebase_derive.py`, `phone_pins.py`, `lock_glyphs.py`, `stock_zip.py`, `check_layout.py`, `check_kept.py`, `check_cjk.py`, `encode_icons.py`, `test_branch.py` |
| `tests/` | Host tests and stock proofs |
