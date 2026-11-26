# Turbo IO releases

These are unofficial, high-risk builds. Flash only if you are a developer and accept that recovery is not guaranteed. No merged or personally signed IPA is published.

## Current release: C26 + TMG17

This pair is on the owner's devices but is not yet accepted as released. The owner installed C26 on 2026-11-24 and flashed TMG17 from it. The owner's checks of the new PIN screen, of PIN entry with Do Not Disturb on, and of the wrong-tries notice going dark have not been reported yet. Nothing is tagged: the tags `app/c26` and `fw/tmg17` come only after the owner accepts the pair. The last accepted pair is C24 + TMG15, which is also the way back (see [Way back](#way-back)).

TMG16 + C25 were built and packaged on 2026-11-23 but were never installed or tagged. TMG17 contains everything in TMG16.

TMG17 is TMG15 with two rounds of lock changes:

- **TMG16: a new PIN screen.** It follows the design system. The digit being entered is drawn large over a short bar. Entered digits show as dots and empty places as short bars. The time and battery are at the top, and a hint replaces them for 3 s after every turn or press. The other lock screens (wrong PIN, waiting, use the phone, the wrong-tries notice, "Unlocked") show one line in the middle and one at the bottom. It also fixes a misdrawn bar: TMG15 handed the stock drawing code a buffer it read from the wrong address.
- **TMG17: Do Not Disturb.** On TMG15 and TMG16, with Do Not Disturb on, every PIN screen went dark about 3 s after it lit. Now the lock holds the screen on while a PIN screen is lit, and puts its screen back on top of Do Not Disturb's overlay instead of closing. The lock's own timers still end it: PIN entry goes dark 30 s after the last turn or press. Without Do Not Disturb the screens and timings are as in TMG16, except that a long PIN entry no longer blinks off when stock's 15 s screen timeout comes.
- **TMG17: the wrong-tries notice goes dark.** "N wrong tries since last unlock" goes dark 30 s after it was shown or last touched, and stays dark. The next press or turn shows it again, and a press then dismisses it. Before, the lock lit the panel again each time stock turned it off.

The Bluetooth image, the PIN rules, the phone protocol and the lock record are unchanged from TMG15. The phone code of C26 is C24's apart from the pins, the release name and one developer row in Music, now labelled "Copy callback log". The page Turbo › Glasses › Glasses lock is the one C24 added.

C26 carries two packages and the wizard picks one: TMG17, selected at every launch, and stock Strix OS 1.0.6.11. C26 cannot flash TMG15 or TMG16.

| | |
|---|---|
| Phone build | C26: RayNeo AI 1.0.21 (1), full host (`--host 1021-full`; Info.plist `TIOHostProfile` `ios1021`) |
| TMG17 ZIP | `StrixOS-1.0.6.11-TurboIO-TMG17-CANDIDATE-NOT-APPROVED.zip`, 9,563,076 bytes |
| TMG17 ZIP SHA-256 | `dab9cdbde8b5a29eb0f481b062ed3f82af4b56941eac8438d212dee3ffabae01` |
| TMG17 ZIP MD5 | `dc804a1ca2a9bc36fccc9bca6483ff9a` |
| TMG17 AP (`nuttx_ap.bin`) | 8,157,000 bytes, SHA-256 `cca3cb6b6301f9aa08499d872c1ceaf4a774a78651bc275b9e4881141ddbdfaa`, MD5 `b652fe12cc50ab2d8081c8b0b442eb7f` |
| TMG17 BTH (`nuttx_bth.bin`) | 1,251,308 bytes, SHA-256 `8a101a702e3f6a2eb327747f246c40ea62ace22e86cd5a86e1acc88679466ffd`, MD5 `3544eb350d4ba5b5665c34e0afa56435` (the same file as in TMG15) |
| AP module | 189,756 bytes at 0x10929204 |
| BTH module | 452 bytes at 0x0c131620 |
| TMG17 build identity (status `build`) | `3906e459b7835660d61f61713af446b80cd4502552fc555d35337600e58f618c`, 32 bytes at AP offset 0x7b8332 |
| Stock ZIP | `Strix-OS-1.0.6.11-members-canonical.zip`, 9,447,267 bytes |
| Stock ZIP SHA-256 | `5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e` |
| Each package | 17 files: 16 payloads and `OtaFileInfo.json`. The two differ only in `nuttx_ap.bin`, `nuttx_bth.bin` and `OtaFileInfo.json`. The other 14 payloads are stock 1.0.6.11, byte for byte. |
| Audit | 33 AP patch sites, 3 BTH patch sites, 7 startup descriptors, stock cores `Strix OS 1.0.6` build 11 |
| Toolchain | LLVM/LLD 23.1.5 |
| Glasses must report | Strix OS 1.0.5.12 or Strix OS 1.0.6.11 |

The pins are in the `c26` entry of [releases.json](releases.json) and in [firmware-pins-c26.json](firmware-pins-c26.json). The firmware release label is in [firmware/RELEASE](../firmware/RELEASE). What the lock does is in [firmware/README.md](../firmware/README.md) and [docs/lock-design.md](../docs/lock-design.md).

Never flash the first TMG17 ZIP, built before the fix in tmg17(2) (SHA-256 `dbe8cfbb7e8733ffea62f144211bd3a0ac0716f61d6f94c7c31414760d1b7b87`, 9,563,065 bytes). No commit referenced it. Only the ZIP in the table is TMG17.

The packager writes `TIOHostProfile = ios1021` into Info.plist. That key is the only thing that separates the full build from the download-only 1.0.21 build (`ios1021-download`); a 1.0.21 app without it is treated as download-only. There is no arming: one confirmation in the wizard allows one transfer. An arm record left on the phone by C20 is never read.

### What was checked

- The full gate with previews passed on the release commit, `fdf1b8b`.
- A plain build and a `--repin` build give the same ZIP, byte for byte. `build.py --audit` passes on it: both images differ from stock only at the pinned sites and in the appended modules.
- The host lock tests cover the screen-on hold over every way out of a lock screen, the move back on top of the Do Not Disturb overlay, and the notice timeout. Five deliberate source breaks each fail them.
- In the emulator, TMG16 with Do Not Disturb on closed the PIN screen about 3 s after it lit, as the owner saw on TMG15. TMG17 kept the PIN screen up and unlocked with the right PIN. Without Do Not Disturb, TMG17's screens matched TMG16's. The notice went dark after 30 s and came back on the next press. The emulator is not the glasses.
- `tools/phone_pins.py` builds the phone pins from this ZIP for the 1.0.21 full host (release `c26`).

### Device check

The checks in [firmware/README.md](../firmware/README.md#device-check) up to item 10 passed on TMG15 with C24 on 2026-11-23. The items added for TMG16 and TMG17 (the new PIN screen, PIN entry with Do Not Disturb on, the wrong-tries notice going dark) have not been reported for TMG17 yet.

### Way back

- **C24 + TMG15** (tags `app/c24` and `fw/tmg15`). Install C24 over the existing app, then flash TMG15 from it. TMG15 ZIP SHA-256 `206d19f1bfb4b97f37826ed18c288c975e17ca83a066ad7d00a275c1be697d49`; after the flash the build identity reads `429943006439d62a611dc7b1af758c2912e7d5190bc1ed5ba2e0372c748f6d26`.
- **Stock Strix OS 1.0.6.11, from C26.** Pick it in the wizard.

The steps and their costs are in [Going back](OTA.md#going-back) in OTA.md.

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
| C24 | 1.0.21 (1) full | TMG15, or stock 1.0.6.11 | 1.0.6.11 | `206d19f1bfb4b97f37826ed18c288c975e17ca83a066ad7d00a275c1be697d49` | `app/c24`, `fw/tmg15` |
| C21 | 1.0.21 (1) full | TMG12, or stock 1.0.6.11 | 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` | `app/c21`, `fw/tmg12` |
| C20 | 1.0.21 (1) full | TMG12 | 1.0.6.11 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` | `app/c20`, `fw/tmg12` |
| C18 | 1.0.11 (259) full | TMG11 | 1.0.5.12 | `edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1` | `app/c18`, `fw/tmg11` |
| C17 | 1.0.11 (259) full | TMG9 (rollback from TMG10) | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C16 | 1.0.11 (259) full | TMG10 | 1.0.5.12 | `4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c` | `app/c16`, `fw/tmg10` |
| C14, C15 | 1.0.7 (230); 1.0.11 (259) full | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | none |
| C13 | 1.0.7 (230) | TMG9 | 1.0.5.5 | `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd` | `app/c13`, `fw/tmg9` |
| C12 | 1.0.7 (230) | TMG8 | 1.0.5.5 | `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6` | `app/c12`, `fw/tmg8` |

C14 to C25 have left `releases.json`; their entries are in git history. C22 and C23, with firmware TMG13 and TMG14, were device candidates for the lock and are not tagged. C25, with firmware TMG16, was built and packaged on 2026-11-23 but never installed or tagged. C11 is tagged `app/c11` (paired with `fw/tmg7`). Firmware TMG2 to TMG7 are tagged `fw/tmg2` to `fw/tmg7`.

Never flash the superseded TMG9 ZIP built before review round 1 (the `fw/tmg9` tag message names it). For TMG9, use only the ZIP in the table.

## Not included

No personal cookies, keys, signing material, private logs or phone backups. Original source follows the repository license. Third-party rights are unchanged.
