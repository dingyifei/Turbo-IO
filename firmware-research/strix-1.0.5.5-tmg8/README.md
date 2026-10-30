# TMG8 candidate (Round 2 fork)

**CANDIDATE-NOT-APPROVED. Offline build only; no glasses or device I/O, and no physical acceptance.**

TMG8 starts as a source-identical fork of frozen TMG7 (`../strix-1.0.5.5-tmg7`) with only the candidate archive name, this header and the phone-pin tool label renamed. Runtime build identity name (TD_BUILD_TMG6), patch sites (25) and the sole raw edit stay unchanged; the only wire change is the TMG8 caps bit described below. Before the Round 2 commits land it builds the same AP as TMG7. The phone pins stay on TMG7 until the ZIP8 re-pin. The TMG7 sections below are historical until updated; the test files keep their tmg7 names until the test-retarget step.

## TMG8 caps bit and the carousel layout value

The only wire change in TMG8 is one capability bit and one layout value that depends on it.

- **Caps bit.** `TD_CAP_MENU_CAROUSEL` is bit 9 (`0x200`) of the status `caps` word (`diagnostics.h`). `TD_CAPS_TMG8 = TD_CAPS_TMG6 | TD_CAP_MENU_CAROUSEL`. TMG8 glasses report `TD_CAPS_TMG8` in every status sample; the build field stays `TD_BUILD_TMG6` ("TMG6"), so TMG7 and TMG8 are told apart by this bit (and by the build-identity sha256), not by a new build name. TMG6 and TMG7 glasses report `TD_CAPS_TMG6` and never set it. `td_encode`/`td_decode` accept `TD_CAPS_TMG6` and `TD_CAPS_TMG8` for the TMG6 build; any other bit is still rejected.
- **Layout value.** The menu layout record (`TMC2`, `menu_config.c`) now accepts 1 (carousel) besides the grid row counts 2 and 3. A stored 1 draws as the 2-row grid (`tml_grid_rows`) until the carousel layout lands; 2 and 3 are unchanged, and the default stays 3.
- **Negotiation.** Value 1 is honoured only from a peer that has seen the caps bit and says so: wire byte 7 of the `TML:` command (reserved and zero up to TMG7) is `TML_PEER_TMG8` (1) on a carousel SET and zero on every other command. `tml_decode` drops a SET of 1 with byte 7 zero, any grid SET or query with byte 7 set, and any other byte 7; `tml_accept` repeats the check and answers `TML_BLOCKED` without a write. So grid SETs and queries are byte-for-byte what TMG7 accepts, and a carousel SET is something TMG7 glasses decode-reject (they drop it with no reply and no write).
- **Phone.** The phone (`MenuLayout.m`) encodes layout 1 in one place, and only when the last status sample of the current peer carries the caps bit (`TIOMenuLayoutLink.glassesReportTMG8Caps`, `TDGlassesReportTMG8Caps()`); a TMG7 or TMG6 peer is never sent it and the write is refused with a note. A reply that confirms 1 is accepted (only TMG8 glasses can send it).
- **Compatibility.** C12 stays fully compatible with TMG7 and TMG6 glasses. An older phone (C11 and earlier) rejects a TMG8 status sample because of the new bit; C12 is the only phone paired with ZIP8. Rollback is C11 plus ZIP7: ZIP7 does not accept a stored 1 and falls back to the default 3 rows.
- **Not drawn yet.** This step stores and negotiates the value only; the carousel layout itself is a later commit.

Host tests: `tests/tmg8_caps_test.c` (the `tmg8-caps` group in the phone `test.py`) covers the constants, the status codec, the command codec against a copy of the frozen TMG7 decoder, the storage state machine and reboot reload; the phone `MenuLayoutTests.m` and `tests/TDRuntimeTests.m` prove that the phone never encodes 1 for a TMG7 peer and report the caps accessor.

## Knob (Round 2)

`TIO_WHEEL_DETENT_RAW 300` (`tio_ui.h`, token `lens-wheel-detent`) is the one detent. `wr_input_wheel` (pages), `tm_input_wheel` (music) and `TK_DETENT_RAW` (`knob_calibration.h`, shared with the phone, static-asserted equal in `menu_wheel.h`) use it, so one item or step takes 300 raw counts, about 6.7 per ~2000-count turn. The main menu hands the stock carousel `2 x delta` (`m8_hook_wheel`, `tio_menu_wheel_scaled`) because the stock carousel needs 600 raw units per item. At either end the stock carousel clamps, so `tio_menu_wheel_wrap` counts the raw deltas that push against the end and jumps last to first (or first to last) after a full detent; this works in every layout because it only reads the focused rank and the visible count. Its state lives in the heap menu controller (`fm_wheel_wrap`), not in the fixed owner tail or .bss. Lockouts after a step: 200 ms on pages (was 300) and 500 ms in music (was 900); the press guards are unchanged.

The status sample's `detent` is now 300 for a peer that reports the TMG8 caps bit and stays 600 (`TK_DETENT_LEGACY`) for TMG4..TMG7 samples, which the codec still accepts. Positive delta is taken as forward, as on every page, and the wrap jump (scroll position, `native_snap`, labels and frame) is host-modelled only; both need the device check. Tests: `tests/tmg8_wheel_test.c` (`tmg8-wheel`) and `src/music-runtime-v1/music_input_test.c` (`tmg8-music-input`).

## Menu icon art (Round 2)

The 13 menu icons are the Round 2 set. Sources and masters live in `assets/menu-icons/` (`svg/NN-name.svg` is the source of truth; `png/NN-name.png` are 48x48 masters rasterised with `rsvg-convert -w 48 -h 48 -b black`, version recorded in `assets/menu-icons/README.md`). `tools/encode_icons.py` turns the masters into `src/focus-v1/focus_menu_icons.h` (4 bpp, even pixel high nibble, 24 B stride, nibble = level/17; 13 x 1152 B, `sizeof fm_icon4 == 14976` unchanged). `tests/tmg8_icons_test.py` (the `tmg8-icons` group in the phone `test.py`) proves the committed header is byte-identical to the regeneration from the masters. Gains are unchanged: unfocused 0x77, focused 0xFF. The art is the only change in this step; the carousel sizes (80 / 48 / 36 px) come with the carousel layout.

# TMG7 candidate (design-system fork)

**CANDIDATE-NOT-APPROVED. Offline build only; no glasses or device I/O, and no physical acceptance.**

TMG7 forks frozen TMG6 (`../strix-1.0.5.5-tmg6`) and re-lays every glasses page to the design system in `docs/design-system/` (the spec wins over the code; glasses boards are drawn at 2x, so every px value is halved). Wire protocol, capabilities, firmware name (TD_BUILD_TMG6, TD_CAPS_TMG6), the 25 patch sites and the sole raw carousel edit are unchanged. Changes are source-level only:

- Shared tokens in `src/common-v1` (lens intensity ramp, bands, 40..500 core, caret, 16 px text floor) with a transient hint helper that fades and hides.
- Navigation (LensNav): the distance and instruction have fixed slots (x 84 and 196) that never move or resize (a distance of 10 km and more drops its tenths and rounds to the nearest kilometre, capped at 999 km), the map is the board's x 372..520 window (canvas at x 348, car within 3 px of the window centre, columns outside it blanked, the scale bar and its label inside it, 29 px clear of the band-B text), the turn glyph has a 7 px stroke, and the fixed clock footer is gone (removed at TMG6).
- Music (LensMusic): current and next lyric labels are core width, lyric lines wrap to two rows with an ellipsis, a one-line current lyric sits on the bottom row of band B, and the control hint is transient.
- Main menu (LensMenu): status row, page dots, 24x3 caret, one focused name in the bottom band, two- and three-row grids. Tile and index math is unchanged.
- Camera control hint is transient and is lit again when the camera session goes live. Focus hint: every wheel step lights it (also while the timer runs) and it is gone at 3000 ms (50 ms service tick while it fades).
- Mini-app runtime: buttons are caret focus items (wheel focus clamps at the ends, no wrap; the caret snaps, the TAP runner has no tick to slide it), 14 px text draws at 16, and the My Apps shelf follows the bands (title and empty slots re-tinted to lens-mid after the page opens, two 222 px columns with a 16 px gutter). The 20 gallery apps are re-laid to the bands with no Exit or Back item: a long press goes back (from a detail page to the overview, and from the overview out of the app), so a detail page is never a dead end. TMG6 glasses, which are frozen, exit the app from either page. The TAP1 wire format is unchanged and older packages still decode.

Modules removed at TMG4 stay removed: ride (didi-v1), English (context-english-v1), dots (dots-v1) and reader (weread-v1). None is restored here.

## Host gates

The tokens in `tio_ui.h` rescale with `TIO_PPD_X10`, but the page layouts are fitted to 24.8 px/deg only (measured: the menu bands break below 24.6, music's core-width assert holds only at 24.8, the turn glyph leaves band B from 25.4). Each page therefore refuses to build at any other value (`TIO_PAGES_CHECK`), and the host test proves it. If the measured ppd differs, the pages must be re-laid, not just that one number changed.

`python3 tests/tmg7_host_test.py --out DIR` runs the tokens test at 22..27 px/deg, the mini-app runtime test, the navigation core and view tests, the menu grid test and the layout gate. The layout gate renders every page in English and Chinese to PNG and checks each widget against its band, the reserved rows, the 16 px floor and the no-filled-panel rule. The phone `test.py` in `official-addon/ios107-edition` now targets this tree: it audits the supplied ZIP with this tree's `build.py`, runs the tmg7 host group, and checks the shared sources against the phone copies. Its `pins` group stays red for a ZIP7 until the phone is re-pinned to ZIP7. Each source edit needs a repin (`build.py --repin`) and a copy of the repin output into `build-inputs.json`.

After the flash the glasses still report the TMG6 firmware name and capabilities (TD_BUILD_TMG6, TD_CAPS_TMG6; the wire protocol is unchanged, so a `firmware: TMG6` status reads the same before and after). The proof that TMG7 is running is the status `build` field, the build-identity sha256 in `identity.sha256` of the build output, which changes from TMG6's `83b82fab9fe9356de62570deff5878b9cfc292b3037998088664e87bd90d8644` to `b86af6e1edf99fef2e1c1aa8bab8153295cb7f973ad0abe262e2f6c1b00d3bdf` for the current ZIP7. The glasses never report the ZIP hash.

Phone pins name TMG7 and the exact ZIP7 hash (`tools/phone_pins.py`, name `TMG7`); the phone stays compatible with TMG6 glasses because the wire protocol and capabilities are unchanged. Navigation `Passing`, the knob observation and the older candidate records below are historical.

# TMG6 candidate (historical)

TMG6 keeps the 25 existing patch sites and unchanged sole raw carousel edit. New navigation opcode 12 is a 224-byte body: map generation, UTF-8 byte count, reserved zeros, 192-byte zero-padded text, and 24 bytes of word-end offsets. The phone sends it only after nav capability bit 3 is acknowledged; TMG5 peers advertising caps 7 retain their understood messages and presentation. The geographic map receives remaining route geometry independently of the turn schematic. FW6 uses a five-pixel route with a seven-pixel contrast halo and a larger centered heading-up marker.

The fixed Passing line chooses the next crossing street from route/road data, then the current road, with unabridged route text as fallback when map data has no name. It tries stock-font sizes 18, 16 and 14 before word-boundary ellipsis. The map scale uses the same stock font family rather than enlarged bitmap digits. Three lyric slots each accept at most two explicitly wrapped lines and are clipped to nonoverlapping bounds. Native widgets and static text buffers remain allocated/owned through the existing lifecycle.

## Knob calibration observation

The user reports approximately **2000 raw counts per full rotation** on TMG5. This is a human-guided one-turn observation, not an independently measured hardware CPR specification. No calibration, scaling, detent constant, or wheel behavior changes are made; the existing 600-unit heuristic remains unchanged.

Host previews use production geometry/raster/layout with explicitly documented macOS surrogate fonts; exact stock glyph appearance and physical acceptance remain human checks. C10 must be used with TMG5 before any optional human flash. Rollback is C9 plus ZIP5, or C8 plus ZIP4. The historical candidate records below remain historical.

# TMG5 candidate

## TMG5 candidate — current development branch

TMG5 supersedes the historical candidate sections below. The exact candidate ZIP SHA256 is `6705bf4d164178943018d55ac882cf796bbc255f186d0be509ecb2f798ede0ef`; AP size is 7,355,400 bytes and AP MD5 is `8ece02af435fb8643c444ca5d412a2fe`. Two clean builds match byte for byte, with 25 existing patch sites and 14 unchanged stock payloads. This is build/host evidence; physical acceptance remains unrun.

The phone remains compatible with TMG4 glasses. Tile actions now work during reordering and display acknowledgement/failure feedback; Reset also saves. Read-only status accepts safe supported app states, while knob calibration explains the main-menu prerequisite and releases a refused lease. Initial navigation geometry precedes turn updates; TMG5 advertises bounded correction/heading smoothing, a six-pixel route, and static square music artwork with wheel/tap control hints. Background roads are filtered on the phone. The existing music commands still invoke the phone's Spotify controls. Speech defaults to 1.2× with five persisted choices for both English and Chinese, and explicitly confirmed idle captions no longer block microphone selection because of a missing template or stopped session.

**Human-only TMG4 → TMG5 checklist:**

1. Install the C9 phone package only after its signing/build review. Turn RayNeo Auto Update on and then off once.
2. Download the bundled exact TMG5 candidate in RayNeo and stop at **Ready to install**.
3. Obtain a version read within two minutes, then use the existing single confirmation. This worker never flashes or talks to glasses.
4. After reboot, restart the phone app. Check all 13 tiles and Camera, reorder/hide/save/reset feedback and persistence, language, read-only status, main-menu knob guidance, and one-turn measurement.
5. Check simulated and real-GPS initial map timing, backward/forward corrections, turns and route contrast; check music artwork and wheel/tap controls, both speech languages at each speed, and caption source changes after stopping. Verify active navigation, display and OTA still block conflicting caption changes.
6. Roll back with **C8 plus ZIP4**, or **C5 plus ZIP2**, using the matching old phone package and manual flash flow. C9 accepts only ZIP5; rollback and hardware recovery are not verified here.

The firmware's source/input identity is separate from the ZIP hash. Runtime capabilities are accepted only for the matching TMG4/TMG5 family. OTA host guards, hash/freshness policy and single-confirmation behavior are unchanged. The sole preservation-check exception is the user-approved removal of `tm_rotate`, applied and committed by the coordinator in FW5 only; earlier firmware trees remain frozen.

# TMG4: persistent tiles and language, runtime status and knob measurement

**CANDIDATE-NOT-APPROVED. Offline build only; no glasses/device I/O or physical acceptance.** TMG4 includes the unflashed TMG3 delta. The phone offers only the exact TMG4 candidate through the existing wizard and single human confirmation. Normal legacy app replies and outbound legacy POSE are removed; the flash path still works with TMG2 installed.

## Tiles and persistence

Canonical stock IDs0–6 stay fixed and visible: Recorder, Live Captions, Live Assist, To-do, Teleprompter, Lifelog and Do Not Disturb. IDs7–12 are Display Test, Navigation, Music, Pomodoro, My Apps and Camera. Their six-item suffix permits all720 permutations. Only IDs7–11 can be hidden; Camera12 is always visible and can move within that suffix. Both carousel and grid use the same compact8–13-item map. Two/three-row layout remains independent.

The two `turbo_tiles_v1_{0,1}.cfg` banks contain32 bytes: `TTC1`, version1, count13, little-endian hide mask, generation,13 canonical IDs,3 reserved zero bytes, CRC32. The32-byte `TTL1`/`TTA1` command/reply uses a74-byte `TTL:`/`TTA:` carrier, business15, a single-use120-second token, client binding and expected generation. Order is encoded as a Lehmer rank0–719; saves require complete write/flush/fsync/close/readback before success.

Separate `turbo_lang_v1_{0,1}.cfg` banks contain20 bytes: `TLC1`, version1, language0EN/1ZH, reserved zeros, generation, reserved zeros and CRC32. Both new bank families use serial generations, wrapMAX to1, select valid older banks after corruption, and refuse ambiguous equal/conflicting or half-range generations. Missing/short/corrupt files fall back to built-in order/English; hard I/O errors prevent writes. Even an explicit first English save creates a verified record. `TLA1` source2 means persisted; the phone requires source2 before reporting sync.

State is owned by the existing heap Control and bounded timer lookup. New NAND reads occur only at the existing first menu show, never from controller creation or boot. Pre-show mutation is unavailable. Active tile changes wait for the plain awake launcher and renderer idle, preserve the selected canonical ID or select Camera, and use the existing snap/count ABI. No raw patch was added; `0x4d9bec` remains7→13 and the verified runtime count field narrows it.

## Runtime status and one-turn measurement

`TDG1` v2 uses256 bytes and the existing571-byte protobuf/JSON transport. It reports TMG4, the source/build-input SHA, caps`0x3f`, optional NAND total/available and existing RAM metrics, language/source, tile generation/pending map, and the unchanged600 raw units per detent heuristic. Unknown metrics remain unmeasured. `STATUS` is request-only; it does not create the launcher or a periodic collection timer. Only an explicit status or periodic-start request probes NAND statistics.

Build identity is SHA-256 over canonical source hashes, source order, toolchain versions, normalized build flags, stock/asset inputs and patch descriptors. It is neither a Git commit nor the ZIP hash. This candidate's identity is `71d7fb8798f77f029a694722e3ef612b63d180f1f58a5ab7eda986d190998cb1`. Generated pins and output paths are excluded to avoid a circular or machine-specific identity.

Knob calibration is a volatile, bounded30-second window: rotate exactly one turn in one direction, then Finish. It counts raw physical wheel deltas, stores net and absolute movement, and cancels before synthetic remote dispatch or when launcher/gates are lost. Replayed START cannot renew a window. Canceled/expired/overflowed/zero or substantially reversed motion yields no estimate. Nothing is saved or recalibrated;600 stays unchanged. The phone requires matching peer/window/sequence/kind and both ACK and file-terminal ownership before another command. No uncertain retry is sent.

## Navigation and T4 removal

POSE2 keeps the existing14-byte body, bounded prediction and timing. The phone sends no op8 fallback. Missing capability bit1 or failed prediction-mirror allocation stops navigation with an explicit message. The shared12-byte base validator remains because POSE2 and SCENE2 use it. The removed WeRead/Ride/English/Dots reply classifier is gone; WP8 transport-equivalence fixtures remain. FW2/FW3 trees and candidates are immutable; FW2 supplies only the pinned animation and structural-preservation baseline.

## Rebuild and audit

Use the already-provisioned LLVM23.1.4 toolchain. No package manager is required.

```sh
R=$(git rev-parse --show-toplevel)
FW4=$R/firmware-research/strix-1.0.5.5-tmg4
IN=$HOME/projects/personal/turboio-inputs
TC=$IN/toolchain/llvm-bin
STOCK=$R/firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip
D=$(mktemp -d)
python3 -I "$FW4/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$D/build"
python3 -I "$FW4/build.py" --stock "$STOCK" --audit "$D/build/StrixOS-1.0.5.5-TurboIO-TMG4-CANDIDATE-NOT-APPROVED.zip"
python3 -I "$FW4/tools/phone_pins.py" --zip "$D/build/StrixOS-1.0.5.5-TurboIO-TMG4-CANDIDATE-NOT-APPROVED.zip" --check "$R/official-addon/ios107-edition"
```

The shared immutable animation is read from `../strix-1.0.5.5-tmg2/assets/animation-frames.l8`, SHA-256`f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d`; no duplicate binary asset is tracked. Normal builds enforce all pins. `--repin` is a deliberate developer operation, not a runtime update mechanism.

| Payload | Bytes | SHA-256 | MD5 |
| --- | ---: | --- | --- |
| ZIP | 8809015 | `aa387b37ece2092d50721bcc3409984f7bd0d650aad4b7b249aceba515161126` | `f72c9a3a79ab02d968dc1415ee117509` |
| AP | 7353800 | `0d6a3ec1d4aac08351afa6b60031c96f4e3904887a61a62def3da561f6c0c02b` | `ea89c1d953fff0b0ffe932c2ed2b5c46` |

The audit enforces25 patch sites,14 unchanged stock payloads,7 startup descriptors, stock header/tail and AP below9.6MB. Host ASan/UBSan tests cover every new codec/file, malformed inputs, A/B faults and generation wrap, exhaustive720×32 maps, renderer rows/pages, timer wrap, and native adapter fault/ownership cases. These checks do not establish physical boot or flash acceptance.

## Human flash and rollback

Keep C5 and the immutable TMG2 ZIP. With TMG2 installed, follow the phone [TMG4 wizard instructions](../../official-addon/ios107-edition/OTA.md): Auto Update on then off once, download in RayNeo and stop at Ready to install, version read within120seconds, one human confirmation, manual Start install, then restart the phone app after glasses reboot. Check all13 default tiles; save/reboot reorder and visibility; save/reboot language; status metrics; one-turn calibration; POSE2 in a dead zone; all retained tiles and Spotify.

Rollback requires installing the TMG2-pinned C5 phone build and then flashing the TMG2 ZIP by hand. This TMG4 phone package rejects TMG2/TMG3 candidates. No loader code, dynamic imports, OTA/boot changes, new raw patch or device operation is included. Loader findings remain research for a possible TMG5.
