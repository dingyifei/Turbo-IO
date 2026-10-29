# TMG6 candidate

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
