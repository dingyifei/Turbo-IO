# Turbo IO releases

These are unofficial, high-risk builds. Flash only if you are a developer and accept that recovery is not guaranteed. No merged or personally signed IPA is published.

## Current release: C21 + TMG12

C21 was installed on 2026-11-16 and is tagged `app/c21`; it has not flashed anything yet. The glasses run TMG12, flashed from C20 on 2026-11-15 (tags `app/c20` and `fw/tmg12`); the glasses report Strix OS 1.0.6.11 with the update confirmed, and the owner's first check passed. No full device checklist has been run yet.

C21 carries two packages and the wizard picks one: TMG12, selected at every launch, and stock Strix OS 1.0.6.11, the way back.

| | |
|---|---|
| Phone build | C21: RayNeo AI 1.0.21 (1), full host (`--host 1021-full`; Info.plist `TIOHostProfile` `ios1021`) |
| TMG12 ZIP | `StrixOS-1.0.6.11-TurboIO-TMG12-CANDIDATE-NOT-APPROVED.zip`, 9,549,211 bytes |
| TMG12 ZIP SHA-256 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| TMG12 AP (`nuttx_ap.bin`) | 8,132,360 bytes, SHA-256 `6b6afd77ce845aca83c52ce23c5a1eae006a7d36ca1cc89536dff3ec795aba50` |
| TMG12 build identity (status `build`) | `0f43c519fc964dc4bd578cf9d7193e502b5c5daa17f3061fba26ccec0280fc55` |
| Stock ZIP | `Strix-OS-1.0.6.11-members-canonical.zip`, 9,447,267 bytes |
| Stock ZIP SHA-256 | `5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e` |
| Each package | 17 files: 16 payloads and `OtaFileInfo.json`. The two differ only in `nuttx_ap.bin` and `OtaFileInfo.json`. |
| Glasses must report | Strix OS 1.0.5.12 or Strix OS 1.0.6.11 |

The pins are in the `c21` entry of [releases.json](releases.json) and in [firmware-pins-c21.json](firmware-pins-c21.json). The firmware release label is in [firmware/RELEASE](../firmware/RELEASE). The firmware build record is in the TMG12 section of [firmware/README.md](../firmware/README.md).

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
| C20 | 1.0.21 (1) full | TMG12 | 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` | `app/c20`, `fw/tmg12` |
| C18 | 1.0.11 (259) full | TMG11 | 1.0.5.12 | `edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1` | `app/c18`, `fw/tmg11` |
| C17 | 1.0.11 (259) full | TMG9 (rollback from TMG10) | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C16 | 1.0.11 (259) full | TMG10 | 1.0.5.12 | `4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c` | `app/c16`, `fw/tmg10` |
| C14, C15 | 1.0.7 (230); 1.0.11 (259) full | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C13 | 1.0.7 (230) | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | `app/c13`, `fw/tmg9` |
| C12 | 1.0.7 (230) | TMG8 | 1.0.5.5 | `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6` | `app/c12`, `fw/tmg8` |

C14 to C20 have left `releases.json`; their entries are in git history. C11 is tagged `app/c11` (paired with `fw/tmg7`). Firmware TMG2 to TMG7 are tagged `fw/tmg2` to `fw/tmg7`.

Never flash the superseded TMG9 ZIP built before review round 1 (the `fw/tmg9` tag message names it). For TMG9, use only the ZIP in the table.

## Not included

No personal cookies, keys, signing material, private logs or phone backups. Original source follows the repository license. Third-party rights are unchanged.
