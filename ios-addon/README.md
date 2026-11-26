# iOS addon

The Turbo IO addon runs inside the RayNeo AI app on the iPhone. This folder holds its source, the build script, the packager and the tests. The flash steps are in [OTA.md](OTA.md).

You build, sign and install the app yourself. No signed IPA is published. Agents never install the app or flash the glasses.

## Current build: C26

| | |
|---|---|
| Phone build | C26, with firmware TMG17 |
| Host app | RayNeo AI 1.0.21 (1), full host (`--host 1021-full`; Info.plist `TIOHostProfile` `ios1021`) |
| Packages | TMG17 (the glasses PIN lock on stock Strix OS 1.0.6.11), selected at every launch; stock Strix OS 1.0.6.11 |
| Release entry | `c26` in [releases.json](releases.json); pins in [firmware-pins-c26.json](firmware-pins-c26.json) |
| TMG17 ZIP SHA-256 | `dab9cdbde8b5a29eb0f481b062ed3f82af4b56941eac8438d212dee3ffabae01` |

The owner installed C26 on 2026-11-24 and flashed TMG17 from it; the pair is not yet accepted as released or tagged. The release record, with every hash and the device status, is in [RELEASE.md](RELEASE.md). The wizard picks the package. One confirmation, Authorize, allows one transfer; there is no arming step.

The page Turbo › Glasses › Glasses lock came with C24. It sets the PIN and the two lock times, locks and unlocks the glasses, and holds the switch "Stay unlocked while worn". The page talks to the lock in the firmware (TMG15 and later); on glasses without it, the page says so and sends nothing more. What the lock does is described in [firmware/README.md](../firmware/README.md) and [docs/lock-design.md](../docs/lock-design.md).

The addon knows only RayNeo AI 1.0.21 (1). An older RayNeo app (1.0.2 to 1.0.11) gets no profile, no features and no flashing, and the packager refuses to build for it. The download-only build (`--host 1021`, profile `ios1021-download`) carries no firmware and cannot flash.

The packager accepts only this stock 1.0.21 (1) input:

| Input | SHA-256 |
| --- | --- |
| `Runner` | `9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2` |
| `App.framework/App` | `0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273` |

Get the stock app legally yourself. Do not edit a hash check to make another input pass.

## Earlier builds

Each tagged build is an annotated `app/cN` tag. The tag message gives the build commit, the IPA hash and the paired firmware.

| Tag | Host app | Firmware | Bundled ZIP SHA-256 |
| --- | --- | --- | --- |
| `app/c24` | RayNeo AI 1.0.21 (1), full host | TMG15 (`fw/tmg15`) and stock 1.0.6.11 | `206d19f1bfb4b97f37826ed18c288c975e17ca83a066ad7d00a275c1be697d49` |
| `app/c21` | RayNeo AI 1.0.21 (1), full host | TMG12 (`fw/tmg12`) and stock 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| `app/c20` | RayNeo AI 1.0.21 (1), full host | TMG12 (`fw/tmg12`) | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| `app/c18` | RayNeo AI 1.0.11 (259), full host | TMG11 (`fw/tmg11`) | `edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1` |
| `app/c16` | RayNeo AI 1.0.11 (259), full host | TMG10 (`fw/tmg10`) | `4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c` |
| `app/c13` | RayNeo AI 1.0.7 (230) | TMG9 (`fw/tmg9`) | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` |
| `app/c12` | RayNeo AI 1.0.7 (230) | TMG8 (`fw/tmg8`) | `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6` |
| `app/c11` | RayNeo AI 1.0.7 (230) | TMG7 (`fw/tmg7`) | `6b06d0dd3124ac1f86c91e0879908f9bfe129a2051cf0b619d5b0b664bc3c0aa` |

The code for the 1.0.7 and 1.0.11 hosts and the untagged releases (C14, C15, C17) left with C21; it stays in git history. C22 and C23 were device candidates for the lock and are not tagged. C25 (TMG16) was built and packaged on 2026-11-23 but never installed or tagged. Older notes are in git history and in [docs/CHANGELOG.md](../docs/CHANGELOG.md). To go back from TMG17, follow [Going back](OTA.md#going-back) in OTA.md.

## Inputs

The stock app, the signing setup and the release ZIPs stay outside the repo. The scripts read them from `$TURBO_INPUTS/package.env`.

| Variable | Used for |
| --- | --- |
| `TURBO_PROFILE`, `TURBO_SIGN_ID`, `TURBO_DEVICE` | Signing a package |
| `TURBO_APP1021` | Stock 1.0.21 `Runner.app`: every package, `test.py`'s real-app checks and the gate's `host1021` stage |

No other variable is read. `TURBO_APP107`, `TURBO_PATCHED_APP`, `TURBO_APP1011`, `TURBO_PRODUCT` and `TURBO_FIRMWARE` are ignored.

The packager finds both ZIPs under `$TURBO_INPUTS` at the paths `releases.json` names (`tmg17/…` and `tmg12-emu/stock/…`), and refuses each unless its size and SHA-256 match. The firmware stages use the LLVM tools in `$TURBO_INPUTS/toolchain/llvm-bin`.

You need macOS with Xcode (the iPhoneOS SDK), Node and Python 3.

## Build

Run the quick check from the repo root:

```bash
bash scripts/turbo-gate.sh --only-build
```

It builds the addon, checks its symbols and the phone pins, and runs the firmware layout checks. The report goes to `build/gate/report.json` in this folder.

To build only the addon, run this in this folder:

```bash
TIO_MAPKIT_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 \
  TIO_OTA_FLASH_ENABLED=1 TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub
```

The dylib lands in `build/mapkit/TurboIOPrivateAddon.dylib`. This is the gate's flag set. While `releases.json` has one release, a build that names none is that release, C26.

| Flag | Effect |
| --- | --- |
| `TIO_MAPKIT_ENABLED` | Apple Maps navigation. Turns on `TIO_DISPLAY_PHONE`; needs the `embedded` mode. |
| `TIO_DISPLAY_PHONE` | The phone-side display and navigation runtime |
| `TIO_DISPLAY_FLASH` | Marks the addon as a flash build, which the packager requires. Needs `TIO_DISPLAY_PHONE=1` and `TIO_OTA_FLASH_ENABLED=1`. |
| `TIO_OTA_FLASH_ENABLED` | Compiles the firmware wizard and its gate. It does not authorize a flash. |
| `TIO_IMAGE_RX_LAB`, `TIO_IMAGE_RX_WIDE` | Developer and research tools |
| `TIO_CLASSIC_BINDINGS` | Links without chained fixups |
| `TIO_RELEASE=cN` | Selects release `cN` in `FirmwarePins.h`. Needs `TIO_OTA_FLASH_ENABLED=1`. |
| `TIO_APPLE_AI` | Apple on-device answers (see below) |
| `TIO_WIRE_LOG` | The wire log recorder (see below) |
| `TIO_DEV` | Turns on `TIO_IMAGE_RX_LAB` |

## Package C26

Run from the repo root:

```bash
bash scripts/turbo-package.sh --host 1021-full --wire-log <label>
```

The script:

1. Builds the addon fresh with the gate's flags. It checks that the dylib names release `c26` and carries the full-host gate symbols and the marker `FULL-HOST-GATE-01`.
2. Checks both ZIPs against `releases.json`.
3. Patches and signs the stock 1.0.21 app with the addon and both ZIPs (bundle resources `TurboWeReadCandidate.zip` for TMG17 and `TurboStockFirmware.zip` for stock).
4. Writes `TurboIO-local-only.ipa` and `report.json` to a new folder, `$TURBO_INPUTS/signed-<YYYYMMDD-HHMM>-<label>`. The report must read `SIGNED_NOT_DEVICE_ACCEPTED`.

Logs go to `$TURBO_INPUTS/package-logs/`. The script never installs anything.

`--host` is required: `1021-full` for the flashing build, `1021` for the download-only build. Any other host exits with code 2. `--release cN` is needed only when `releases.json` lists more than one release.

Options:

- `--build-only`: build and check the addon, then stop before signing.
- `--wire-log`: add the wire log recorder.
- `--apple-ai <new-directory>`: build with Apple on-device answers and bundle `TurboAppleAI.dylib`.

Install the IPA over the existing RayNeo app (`com.rayneo.venus.pub`). Never delete that app: deleting it wipes the pairing and the flash gate's state. Then flash with [OTA.md](OTA.md).

## Test

Run the full gate from the repo root:

```bash
bash scripts/turbo-gate.sh
```

It runs, in order: the private-input check, the build and symbol checks, the pins check, the firmware layout checks, one full `test.py` run for C26, the node package tests, the `host1021` stage (two `--build-only` package runs, one per host) and the source audit. `--preview` adds the preview screenshots and takes about 15 minutes. `--skip-tests` skips everything from `test.py` to the host stages.

To run `test.py` on C26 yourself, from this folder:

```bash
python3 test.py --firmware <TMG17 ZIP> --stock-package <stock 1.0.6.11 ZIP> \
  --tree-firmware <ZIP built from firmware/> --app1021 <stock 1.0.21 Runner.app> --only <groups>
```

- `--firmware` must be the release's TMG ZIP. `--release` defaults to the only release.
- `--stock-package` is the stock ZIP; `python3 -I ../firmware/tools/phone_pins.py --inputs "$TURBO_INPUTS" --resolve c26 --package STOCK-1.0.6.11` prints its path.
- `--tree-firmware` is the ZIP built from the current `firmware/` tree, for the tree audit. It defaults to `--firmware`.
- `--only` takes a comma-separated list of groups. Leave it out to run every group. [tests/manifest.json](tests/manifest.json) lists every test file and its group.
- Logs and test binaries go to `build/tests`, or to `--out`.

The release groups are `pins`, `archive`, `directory`, `flash`, `flash-sequence-1021`, `flash-packages`, `feed`, `feed-restart`, `wizard`, `tmg4-wizard`, `ios1021-full-guard`, `ios1021-full-edge`, `phone-ota-gate` and `firmware-export`. `flash-sequence-1021` replays the request order recorded during the TMG12 flash of 2026-11-15, with TMG17's sizes. The lock page and its commands are in the `glasses-lock` group. The guard sweeps are compared with digests pinned in `test.py`.

Run the packager tests with `node --test package.test.mjs`.

Host tests and previews do not show that a build works on the glasses. Only a check on the device does.

### Reproducible build check

Run from the repo root:

```bash
bash scripts/repro-check.sh --apple-ai --wire-log   # the flags of a packaged build
bash scripts/repro-check.sh                         # defaults: --host 1021-full; also --host 1021, --release cN, --rev <commit>
```

The script builds one commit twice: once from a `git archive` export (no git) and once from a temporary `git worktree` at a path of another length. Both go through `turbo-package.sh --build-only`. It then compares the unsigned `TurboIOPrivateAddon.dylib`, and with `--apple-ai` also `TurboAppleAI.dylib`, byte for byte, and fails on any difference. It builds only committed content, copies the private bootstrap sources from `$TURBO_INPUTS/private-backup/ios107` after their SHA-256 check, signs nothing and touches no device. It is not a gate stage: run it once before a release.

- The claim covers the unsigned dylibs with the pinned inputs. A signed IPA carries a signature and timestamps and is never byte-identical.
- Both builds need the same Xcode and iPhoneOS SDK. Another Xcode changes the SDK version in the load commands, so the dylib differs (this happened to C13). Each package run writes the versions to `toolchain.txt` in its log folder.
- The build commit that Clench Lab records comes from git in a checkout and from `BUILD_COMMIT` (filled by `export-subst`) in a `git archive` export. Both give the same 12 characters.

## Wire log (`TIO_WIRE_LOG=1`)

The wire log records the traffic between the RayNeo app's Dart layer and its native layer, one JSON object per line. Without `TIO_WIRE_LOG=1` the addon has no recorder symbols or strings; the gate and the packager check this.

- It records calls into the RayneoNet bridge with their results, native-to-Dart messages on the `rayneonet` and `rayneo_venus_sdk_plugin` channels, and Dart-to-native calls on the other `rayneo` and `venus` channels.
- It changes no arguments, results, ordering or threading, and it bypasses no gate.
- Glasses protocol frames are kept in full. Other byte fields keep only their length, SHA-256 and first 32 bytes. Credential-like values and device, account and user IDs are replaced before writing. Notification, caption and speech text is kept, so treat the files as private.
- Open Turbo › Developer › Wire log to start it. "Start recording at launch" is off by default.
- Files go to `Documents/turbo-wirelog/wirelog-<UTC time>.jsonl`, 20 MB per file and 200 MB in all; the oldest are dropped first. Use **Export logs** to share them.

Tests: the `wire-log` group.

## No-network answers (`TIO_APPLE_AI=1`)

With this flag, the Apple on-device mode (3), or the endpoint mode (2) with Apple fallback, answers after the host's final speech result when no official reply arrives. Keep the RayNeo app in the foreground. After each launch, finish one official Q&A, then choose the answer mode again; launch resets it to Official (0). Status, the wait time and a copyable event timeline are in Turbo › Developer › Apple Intelligence. The timeline never stores questions, answers or error text.

Tests: the `no-network-turn` group.

## Local translation

The optional translation module and its models are described in [local-translation/README.md](local-translation/README.md).

## License

The source is under the [PolyForm Noncommercial License 1.0.0](../LICENSE). Third-party licenses are unchanged.
