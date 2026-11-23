# Turbo IO releases

These are unofficial, high-risk builds. Flash only if you are a developer and accept that recovery is not guaranteed. No merged or personally signed IPA is published.

## Current release: C24 + TMG15

C24 was installed on 2026-11-23 and flashed TMG15 the same day (tags `app/c24` and `fw/tmg15`). The glasses report Strix OS 1.0.6.11, and the owner's device check passed; the list is in [firmware/README.md](../firmware/README.md#device-check).

TMG15 adds a PIN lock for the glasses: they lock after being folded or left idle, and unlock by PIN on the knob or from the phone. C24 adds the page that controls it, Turbo › Glasses › Glasses lock.

C24 carries two packages and the wizard picks one: TMG15, selected at every launch, and stock Strix OS 1.0.6.11, the way back.

| | |
|---|---|
| Phone build | C24: RayNeo AI 1.0.21 (1), full host (`--host 1021-full`; Info.plist `TIOHostProfile` `ios1021`) |
| TMG15 ZIP | `StrixOS-1.0.6.11-TurboIO-TMG15-CANDIDATE-NOT-APPROVED.zip`, 9,559,509 bytes |
| TMG15 ZIP SHA-256 | `206d19f1bfb4b97f37826ed18c288c975e17ca83a066ad7d00a275c1be697d49` |
| TMG15 AP (`nuttx_ap.bin`) | 8,147,400 bytes, SHA-256 `ce6815c8a9ec12e555bef80d89f7fcd21dab156bb972125951d4a848f6b6f725` |
| TMG15 BTH (`nuttx_bth.bin`) | 1,251,308 bytes, SHA-256 `8a101a702e3f6a2eb327747f246c40ea62ace22e86cd5a86e1acc88679466ffd` |
| TMG15 build identity (status `build`) | `429943006439d62a611dc7b1af758c2912e7d5190bc1ed5ba2e0372c748f6d26` |
| Stock ZIP | `Strix-OS-1.0.6.11-members-canonical.zip`, 9,447,267 bytes |
| Stock ZIP SHA-256 | `5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e` |
| Each package | 17 files: 16 payloads and `OtaFileInfo.json`. The two differ only in `nuttx_ap.bin`, `nuttx_bth.bin` and `OtaFileInfo.json`. |
| Glasses must report | Strix OS 1.0.5.12 or Strix OS 1.0.6.11 |

The pins are in the `c24` entry of [releases.json](releases.json) and in [firmware-pins-c24.json](firmware-pins-c24.json). The firmware release label is in [firmware/RELEASE](../firmware/RELEASE). The firmware build record is in the TMG15 section of [firmware/README.md](../firmware/README.md).

The packager writes `TIOHostProfile = ios1021` into Info.plist. That key is the only thing that separates the full build from the download-only 1.0.21 build (`ios1021-download`); a 1.0.21 app without it is treated as download-only. There is no arming: one confirmation in the wizard allows one transfer. An arm record left on the phone by C20 is never read.

### Build

1. Set `TURBO_APP1021` in `$TURBO_INPUTS/package.env`.
2. Run the gate: `bash scripts/turbo-gate.sh`.
3. Package: `bash scripts/turbo-package.sh --host 1021-full --wire-log <label>`. It writes `TurboIO-local-only.ipa` to a new directory and installs nothing. It refuses either ZIP unless its size and SHA-256 match `releases.json`.

### Flash

Follow [OTA.md](OTA.md): "Flash", then "After the flash". If the phone refuses, read "If the gate refuses".

## Earlier releases

Each release has annotated tags: `app/cN` for the phone build, `fw/tmgN` for the firmware. The tag message gives the build commit, the IPA or ZIP hash and the device status. Flash steps for older releases are in the git history of [OTA.md](OTA.md). Notes up to late October are in [docs/CHANGELOG.md](../docs/CHANGELOG.md), which is frozen.

| Phone | Host | Firmware | Stock base | ZIP SHA-256 | Tags |
|---|---|---|---|---|---|
| C21 | 1.0.21 (1) full | TMG12, or stock 1.0.6.11 | 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` | `app/c21`, `fw/tmg12` |
| C20 | 1.0.21 (1) full | TMG12 | 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` | `app/c20`, `fw/tmg12` |
| C18 | 1.0.11 (259) full | TMG11 | 1.0.5.12 | `edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1` | `app/c18`, `fw/tmg11` |
| C17 | 1.0.11 (259) full | TMG9 (rollback from TMG10) | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C16 | 1.0.11 (259) full | TMG10 | 1.0.5.12 | `4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c` | `app/c16`, `fw/tmg10` |
| C14, C15 | 1.0.7 (230); 1.0.11 (259) full | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C13 | 1.0.7 (230) | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | `app/c13`, `fw/tmg9` |
| C12 | 1.0.7 (230) | TMG8 | 1.0.5.5 | `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6` | `app/c12`, `fw/tmg8` |

C14 to C21 have left `releases.json`; their entries are in git history. C22 and C23, with firmware TMG13 and TMG14, were device candidates for the lock and are not tagged. C11 is tagged `app/c11` (paired with `fw/tmg7`). Firmware TMG2 to TMG7 are tagged `fw/tmg2` to `fw/tmg7`.

Never flash the superseded TMG9 ZIP built before review round 1 (the `fw/tmg9` tag message names it). For TMG9, use only the ZIP in the table.

## Not included

No personal cookies, keys, signing material, private logs or phone backups. Original source follows the repository license. Third-party rights are unchanged.
