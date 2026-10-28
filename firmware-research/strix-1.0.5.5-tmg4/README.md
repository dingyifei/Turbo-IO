# TMG3: 13-item bilingual menu and bounded navigation prediction

**CANDIDATE-NOT-APPROVED. Built and audited offline; never flashed or accepted on a device.** The normal phone features remain compatible with TMG2. The phone's fixed TMG3 candidate is opt-in through the existing human confirmation; packaging never authorizes or starts a flash.

TMG3 removes the WeRead, Ride/DiDi, Dots and Context English modules. Camera, My Apps/Gallery, Pomodoro, Music, navigation, display, dashboard, diagnostics and the seven stock launch targets remain. The carousel and focus grid contain 13 items. The grid supports the unchanged two/three-row menu configuration.

| Index | Item |
| --- | --- |
| 0 | Recorder |
| 1 | Live Captions |
| 2 | Live Assist |
| 3 | To-do |
| 4 | Teleprompter |
| 5 | Lifelog |
| 6 | Do Not Disturb |
| 7 | Turbo Display (grid: Display Test) |
| 8 | Navigation |
| 9 | Music |
| 10 | Pomodoro |
| 11 | My Apps |
| 12 | Camera |

## Language

The byte-identical phone/firmware `lang_flag.c/h` implement a 32-byte TLG1/TLA1 frame in a 74-byte carrier: `08 01 10 7f 1a 44`, then `TLG:`/`TLA:` and 64 lowercase hex digits, business 15. Language 0 is English and 1 is Chinese. State lives only in the launcher RAM controller: every boot starts in English until the phone sends a flag. Replies use source 0 (default) or 1 (phone), never persisted source 2. Invalid lengths, CRCs, reserved fields and languages are rejected before state changes.

Language lookup scans an existing controller without allocating. A change defers grid invalidation and the custom carousel refresh to the UI executor. Other retained views use the flag when they render. The stock carousel labels 0–6 retain the stock firmware language; the replacement grid's 13 labels use the table. `menu_config.c/h`, TML/TMA/TMC wire bytes and saved row banks remain byte-identical to TMG2.

## POSE2 dead reckoning

Capability bit 1 advertises op 11, a 14-byte POSE2 body: the unchanged 12-byte pose plus little-endian speed in quarter-metres/second (0–200). Prediction uses bounded 32-bit integer arithmetic, stops advancing at 8 seconds, and clamps coordinates to ±8192 quarter metres. Moving POSE2 expires at 10 seconds; speed zero and legacy POSE retain the 5-second stale rule and the existing 180 ms blend.

The phone mirrors only acknowledged, fully committed wire bodies and sends corrections for prediction/heading/speed changes, a new scene, or the 4-second moving / 2.5-second stationary cadence. TMG2 peers (capabilities 1 or 5) allocate no prediction mirror and receive only the unchanged legacy POSE path. No op 11 is sent without bit 1.

## Rebuild and audit

The accepted toolchain differs from the historical TMG2 compiler: Homebrew clang 23.1.4 and Homebrew LLD 23.1.4. TMG3 is reproducible against itself; two clean pinned builds and a separate verification build match the candidate byte-for-byte. No package manager is needed.

```sh
R=$(git rev-parse --show-toplevel)
FW3=$R/firmware-research/strix-1.0.5.5-tmg3
IN=$HOME/projects/personal/turboio-inputs
TC=$IN/toolchain/llvm-bin
STOCK=$R/firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip
D=$(mktemp -d)
python3 -I "$FW3/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$D/build"
python3 -I "$FW3/build.py" --stock "$STOCK" --audit "$D/build/StrixOS-1.0.5.5-TurboIO-TMG3-CANDIDATE-NOT-APPROVED.zip"
python3 -I "$FW3/tools/phone_pins.py" --zip "$D/build/StrixOS-1.0.5.5-TurboIO-TMG3-CANDIDATE-NOT-APPROVED.zip" --check "$R/official-addon/ios107-edition"
```

Normal builds enforce source/extra, toolchain, module, branch, AP and archive pins. `--compile-only` checks intermediate source compilation; `--repin` is a deliberate developer operation that emits a proposed pin file. The generated animation assembly is linked last. The only shared binary input is read-only `../strix-1.0.5.5-tmg2/assets/animation-frames.l8`; its required SHA-256 is `f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d`, and a mismatch fails closed. No duplicate bitmap is tracked here.

| Identity | Bytes | SHA-256 | MD5 |
| --- | ---: | --- | --- |
| ZIP | 8803177 | `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274` | `20547ed2ee0d4ceaee41a64ac46d19c6` |
| AP | 7344072 | `b54a28a628112c2b548393328528c2f7a19e727741f1fd6ede35cfbee4290c52` | `28d26bb9965e2648ab514e02d4708957` |

The module is 135424 bytes, 64,512 bytes smaller than TMG2. The audit checks exactly 25 stock-byte patch sites, all symbolic targets and entry trampoline prologues, seven startup descriptors, header/tail preservation, 14 unchanged stock payloads, the AP under 9,600,000 bytes and total decompressed ZIP size under 24 MB. No AEABI shims were added.

## Human decision and rollback

The morning flash is a separate human decision. The C6 phone package offers this exact TMG3 candidate as `TurboWeReadCandidate.zip`; opening the wizard or installing the phone package grants no flash authorization. The existing host, freshness, hash, ordered manifest/slice checks and single destructive confirmation remain mandatory. Follow the phone wizard; do not infer device acceptance from an offline test.

Keep the immutable TMG2 ZIP and a pre-WP6 signed phone package for rollback. That phone package carries the TMG2 pins; the TMG3-pinned package rejects a TMG2 candidate. Recovery/flashing is human-only and not guaranteed. Menu row-bank format is unchanged, so a rollback has no new language byte to invalidate its banks. TMG2 ignores TLG1; language state always resets on boot. No device, boot, OTA or radio-driver path was exercised during this work.
