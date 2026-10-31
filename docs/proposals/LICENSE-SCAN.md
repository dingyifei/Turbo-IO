# License scan and recommendations

Scan date: 2026-10-29. Source: `main` at 659fd67, read-only. This document recommends; it changes no license and moves no file. It is an engineering inventory, not legal advice. Items marked "to-be-verified upstream" come from the author's general knowledge of the upstream projects, not from files in this repository, and must be checked against the pinned upstream versions before anyone relies on them.

## 1. Summary

| Area | Path | Declared / found license | License file present | Status |
| --- | --- | --- | --- | --- |
| Original material | repo root | PolyForm Noncommercial 1.0.0 | `LICENSE`, `NOTICE`, `docs/LICENSING.md`, `THIRD_PARTY_NOTICES.md` | Documented |
| Skill copy | `skills/turbo-io/` | PolyForm Noncommercial 1.0.0 (header of its `LICENSE`) | `LICENSE`, `NOTICE` | Consistent with root |
| AirPlay receiver | `official-addon/tar2-airplay/` | GPL-3.0-or-later | `LICENSE` (GPLv3 text) | Documented exception; see section 2 |
| ZIPFoundation | `third-party/ZIPFoundation/` | MIT | `LICENSE` | OK |
| py-webrtcvad | `core-probe/Vendor/py-webrtcvad-2.0.10/` | MIT | `LICENSE` | OK |
| Opus source | `core-probe/Vendor/opus-1.5.2/` | BSD-3-Clause style | `COPYING` | OK |
| Opus prebuilt | `core-probe/Vendor/opus-ios/libopus.a` | Opus (BSD) | none | Gap |
| Binary frameworks | `core-probe/Frameworks/*.framework` | mixed, see section 5 | none (7 of 7) | Gap |
| Local translation models | `official-addon/ios107-edition/local-translation/licenses/` | Apache-2.0, MIT and others | six files | OK as far as present |
| Firmware research | `firmware-research/` | mixed: original code plus vendor material | none at that level; prose in `THIRD_PARTY_NOTICES.md` | Needs per-item review |
| Package manifests | `dashboard-service/pyproject.toml`, `rayneo-*/Package.swift` | no license field | n/a | Gap |

Verified in this scan: the only `LICENSE`, `COPYING` or `NOTICE` files tracked outside `official-addon/ios107-edition/local-translation/licenses/` are `LICENSE` and `NOTICE` at the root, `skills/turbo-io/LICENSE` and `NOTICE`, `third-party/ZIPFoundation/LICENSE`, `official-addon/tar2-airplay/LICENSE`, `core-probe/Vendor/opus-1.5.2/COPYING` and `core-probe/Vendor/py-webrtcvad-2.0.10/LICENSE`. `DEPENDENCIES.json` is a hash manifest of 95 third-party files with the stated purpose "not covered by the project license"; it records no license names.

## 2. Root license and the GPL-3.0 subtree

### What exists

- `LICENSE` is the PolyForm Noncommercial 1.0.0 text. `NOTICE` carries "Required Notice: Copyright (c) 2026 Turbo IO contributors" and says earlier MIT grants are not revoked.
- `docs/LICENSING.md` (Chinese) states: the project is source-visible and noncommercial, not OSI open source; a 2026-09-08 relicense applies prospectively; the earlier public versions (commit `f78573e0f6298677ab50adba342e161c32e9de45`) were MIT and stay MIT; third parties keep their own licenses.
- `docs/LICENSING.md` and `THIRD_PARTY_NOTICES.md` both record a dated (2026-10-23) maintainer exception: `official-addon/tar2-airplay/` is GPL-3.0-or-later and the root noncommercial terms do not stack on it. `official-addon/tar2-airplay/README.md` repeats this.

### The conflict

PolyForm Noncommercial forbids commercial use. GPL-3.0 forbids adding further restrictions on recipients and requires the corresponding source of any conveyed combined work to be GPL-licensed. The two cannot cover the same code. The repository handles this by directory carve-out, which is a legitimate approach only when the carve-out is clean. Points that are not yet clean:

1. **Copyright holder authority.** The exception text says "the maintainer explicitly authorizes" it. Relicensing the project's own files under GPL is valid only for code the maintainer (and any contributors) own. `NOTICE` names "Turbo IO contributors", not one person. If any outside contribution exists in the subtree or in the copied files, each contributor's consent is needed. Recommendation: confirm by `git shortlog` on the subtree that all authors are covered, and keep that evidence.
2. **Copies of root-licensed code inside the GPL tree.** `official-addon/tar2-airplay/airplay-hd-v1/` (`FrameEncoder.*`, `HDLink.*`, `player.h`) and `video-player-v1/` are described as copies of the code in `official-addon/tar2-display/` (which has same-named `FrameEncoder.*`, `HDLink.*`, `player.c`, `player.h`). Because the owner is the same, dual presence is legal: the GPL copy is GPL, the `tar2-display` original stays PolyForm. But any later edit made in only one place makes the two drift, and a contributor who edits the wrong copy applies the wrong license. Not verified in this scan: whether the copies are byte-identical.
3. **Per-file markers.** Only one file under `official-addon/tar2-airplay/` carries an SPDX header (`TAR2Module.m`: `GPL-3.0-or-later`). Other files (for example `airplay-v1/Receiver.m`, whose first line says "UxPlay core is GPLv3; not a public release") do not. The directory `LICENSE` covers them, but copies of single files lose that context.
4. **Upstream components.** `upstream.lock.json` pins UxPlay at 517cbb1 (GPL-3.0-or-later), libplist at 2117b8f (LGPL-2.1-or-later) and OpenSSL 3.5.4 (Apache-2.0). `build_core.py` fetches them at build time; none is vendored in the tree. Their licenses are therefore not relicensed, as the docs say. The GPL receiver code links UxPlay, so the GPL choice is not optional for the receiver core: UxPlay's own GPL forces it. This is the real reason the subtree cannot be PolyForm.
5. **Combination with proprietary host and vendor frameworks.** `docs/LICENSING.md` already warns that source release does not authorise redistributing a binary that combines the GPL module with a closed vendor host or SDK. That is the real hazard: GPL-3.0 section 5 and the system-library exception do not clearly cover a proprietary RayNeo host app plus RayneoNet/RayneoLog being linked or loaded with GPL code. Verified in this scan: no tracked build script outside the subtree references `tar2-airplay` (matches are in docs and README files only), so the GPL code is not currently built into another tracked product in this repository. The risk arises at distribution time of a merged IPA, which the docs say is not done.
6. **Apache-2.0 with GPL-3.0.** OpenSSL 3.5.4 under Apache-2.0 is compatible with GPL-3.0 (not GPL-2.0). Fine, since the receiver is GPL-3.0-or-later. LGPL libplist, statically linked into `libTurboAirPlay.a` per `build_core.py`, is allowed inside a GPL-3.0 whole.
7. **Mixed-license repository.** A GPL directory inside a noncommercial repository means a recipient who obtains the whole tree can use the GPL directory commercially but not its neighbours. This is intended, but it must stay obvious in the README.

### Options

- **A. Keep the carve-out, tighten it (recommended, lowest effort).** Add SPDX headers to every first-party file in the subtree; add a short `NOTICE`-style file there naming the copyright holder and the pinned upstream licenses; add a CI check that `tar2-airplay/` files carry GPL SPDX tags and nothing outside it does; decide and document whether the `tar2-display` copies must stay in sync (a one-line script check).
- **B. Move the GPL code to its own repository** (or a git submodule) with its own LICENSE and a thin integration contract. Cleanest legally, since a repository then has one license. Cost: the split, build path changes, loss of the single-tree workflow. Not requested here; no files should be moved on this recommendation alone.
- **C. Relicense the whole project to GPL-3.0-or-later.** Removes the conflict but gives up the noncommercial restriction, which contradicts `docs/LICENSING.md`'s purpose. Only if the maintainer's goals change.
- **D. Drop UxPlay and rewrite the receiver clean-room under PolyForm.** Large effort and legally subtle (the AirPlay protocol is reverse-engineered); not recommended.
- **E. Seek a commercial or permissive grant from UxPlay authors.** UxPlay's copyright is spread over many contributors, including code from other GPL projects (playfair is of uncertain provenance upstream; to-be-verified upstream). Not realistic.

Whichever option is chosen, do not distribute a merged or signed IPA that contains the GPL module together with the vendor host until a lawyer has reviewed the combination.

## 3. MIT and BSD components

| Component | Path | Evidence | Notes |
| --- | --- | --- | --- |
| ZIPFoundation 0.9.20 | `third-party/ZIPFoundation/` | `LICENSE` is MIT, "Copyright (c) 2017-2025 Thomas Zoechling" | Keep the file. `THIRD_PARTY_NOTICES.md` records that the manifest was edited to drop test targets; modified Package.swift is allowed under MIT but should say so in a header. |
| py-webrtcvad 2.0.10 | `core-probe/Vendor/py-webrtcvad-2.0.10/` | `LICENSE` is MIT, "Copyright (c) 2016 John Wiseman" | The package bundles Google WebRTC VAD C sources, whose own license (BSD-3-Clause, to-be-verified upstream) is not shown by this file. Check for the WebRTC license text inside the vendored tree and add it to the notices if missing. |
| Opus 1.5.2 source | `core-probe/Vendor/opus-1.5.2/` | `COPYING` begins "Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, ..." (BSD-3-Clause style with patent-related notes) | Complete tree retained as the notices state. |
| Local translation model licenses | `official-addon/ios107-edition/local-translation/licenses/` | `fastcluster-LICENSE.md`, `FluidAudio-Apache-2.0.txt`, `JapaneseG2P-LICENSE.md`, `llama-MIT.txt`, `NemoTextProcessing-LICENSE.md`, `vbx-LICENSE.md` | Not part of the task list but good practice. Not verified here: whether model weights themselves (if any are fetched) have separate terms. |

## 4. Prebuilt `core-probe/Vendor/opus-ios/libopus.a`

Verified: a single-architecture arm64 static archive, tracked in git, with no license file beside it (the directory holds only the `.a`). Symbols such as `opus_packet_parse` confirm it is Opus. `THIRD_PARTY_NOTICES.md` says device builds use Opus 1.5.2, but nothing in the tree records how this archive was built, from which source, or with which flags.

Recommendations:

- Add a short README or provenance note beside it: source version (presumably 1.5.2), build flags, and a SHA-256, and point to `core-probe/Vendor/opus-1.5.2/COPYING`. Opus is BSD-3-Clause style, so binary redistribution needs the copyright notice reproduced with the binary.
- Prefer building it from the vendored source in the build, or add a reproducible build script, so the binary is derivable and not an opaque blob.
- Add its hash to `DEPENDENCIES.json` if absent (not verified in this scan).

## 5. Binary frameworks in `core-probe/Frameworks`

All seven are tracked in git, none has a license file inside it or beside it, and `DEPENDENCIES.json` lists hashes only. Versions below were read from each `Info.plist`; the upstream licenses are from general knowledge and are to-be-verified upstream against that exact version.

| Framework | Version found | Bundle id | Likely upstream license (to-be-verified upstream) | Obligation if redistributed |
| --- | --- | --- | --- | --- |
| CocoaAsyncSocket | 7.6.5 | org.cocoapods.CocoaAsyncSocket | Public domain / BSD-style (project says public domain) | Low; keep attribution as a courtesy |
| CocoaLumberjack | 3.8.5 | org.cocoapods.CocoaLumberjack | BSD-3-Clause | Reproduce copyright and license text with binaries |
| OpenSSL | 3.3.2000 (`com.github.krzyzanowskim.OpenSSL`, the krzyzanowskim iOS packaging) | n/a | Apache-2.0 for OpenSSL 3.x; the packaging repository is believed to be MIT-style or Apache (unclear; to-be-verified upstream) | Apache-2.0 requires the license text and NOTICE, and a statement of changes |
| SwiftProtobuf | 1.36.1 | org.cocoapods.SwiftProtobuf | Apache-2.0 with Runtime Library Exception | Provide license text; the exception relieves attribution for generated code |
| SSZipArchive | 2.4.3 | org.cocoapods.SSZipArchive | MIT (it bundles minizip under zlib-style terms) | Reproduce MIT notice; minizip notice too |
| RayneoLog | 1.0.8 | org.cocoapods.RayneoLog | Proprietary, RayNeo; no grant found | None granted |
| RayneoNet | 1.2.35 | org.cocoapods.RayneoNet | Proprietary, RayNeo; no grant found | None granted |

Notes:

- The five open-source frameworks appear to be built from CocoaPods (bundle ids `org.cocoapods.*`) and to have been taken from a vendor app or a pod build. Provenance is not recorded. If they were lifted from the RayNeo app bundle, the redistribution right comes from the open-source license of each, not from the vendor, but the vendor's build may include local modifications.
- `THIRD_PARTY_NOTICES.md` says these "retain their original licenses" and that RayneoNet and RayneoLog are "not authored or relicensed by Turbo IO". That is correct as far as it goes but leaves the files unaccompanied by license text, which BSD, MIT and Apache terms all require when binaries are redistributed.
- **RayneoLog and RayneoNet are the main exposure.** They are vendor binaries committed to a public-style repository with no license. No grant is visible. The notices say they are "build dependencies" supplied by the vendor app. Committing them is the redistribution; the "build dependency" wording does not change that. Even with an interoperability purpose, copying and publishing vendor binaries can infringe, and the PolyForm text says nothing about them. This is a vendor-rights question the maintainer should decide consciously.
- Every framework carries a `_CodeSignature/CodeResources`, so signing details from the original provider are also published; check whether this is intended.

Recommendations: (a) for the five open-source frameworks, add a `core-probe/Frameworks/THIRD_PARTY_LICENSES.md` or per-framework license files with upstream text for the exact version; (b) for the two RayNeo frameworks, either stop tracking them and have the build fetch them from the user's own installed app (consistent with the approach already stated for IPAs), or get written permission; the `DEPENDENCIES.json` hash manifest could still be kept so the build verifies a user-supplied copy.

## 6. `firmware-research/`

Verified facts: about 2,457 tracked files, 35 MB; mostly `.c` (1055), `.h` (981), `.py` (128), `.m` (103), assembly and PNG. Tracked vendor material includes `firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip` (8,740,749 bytes, an unmodified RayNeo OTA download archived by hash) (the 1.0.4.12 `stock/` directory exists but listed empty in the working tree; its README refers to a payload archive, not verified as tracked). `firmware-research/README.md` calls everything unofficial and high-risk. `THIRD_PARTY_NOTICES.md` says original firmware code, libraries and resources remain copyrighted by RayNeo, Bestechnic and others and are "not relicensed", while the research code follows the repository license.

Issues:

1. **No per-directory license marker.** A reader of `firmware-research/` cannot tell which files are original (PolyForm), which derive from vendor firmware, and which are vendor bytes. The notices exist only in the root document.
2. **Stock OTA archives are redistributed vendor binaries.** The README argues for integrity checking and recovery research, and the archive is described as byte-unchanged with hash and source URL. That is a documentation-friendly design, but it is still redistribution of copyrighted firmware without a license grant. Treat as a risk accepted by the maintainer, ideally replaced by a hash plus fetch instructions.
3. **Vendor-derived source.** Files such as `firmware_profile.h` (per tag), `trampolines.S`, `link.ld` and the `include/` headers can embed addresses, structure layouts or function signatures recovered from vendor firmware. Facts about interfaces are generally less protected than code, but verbatim disassembly output or copied vendor headers would be. Not verified in this scan: whether any file contains verbatim vendor code; it needs a targeted review (for example a search for Bestechnic or BES identifiers and for large dumped tables).
4. **Embedded third-party strings, images and fonts.** PNG and binary assets (for example the animation `.bin` under `native-navigation/`) have no recorded origin in a license file. `THIRD_PARTY_NOTICES.md` notes an embedded portrait explicitly authorised by its owner; other assets are not covered by a statement.
5. **Candidate OTA outputs** (modified archives) are derivative works of vendor firmware; the notices state this correctly.

Recommendations: add `firmware-research/LICENSING.md` that classifies the content as (a) original research code, (b) vendor stock archives, (c) derived or patched vendor payloads, (d) assets, and states per class the license and the source of rights. Consider replacing in-repo stock ZIPs by hash plus provenance.

## 7. Package manifests without a license field

- `dashboard-service/pyproject.toml` (package `turboio-dashboard`, version 0.1.0): no `license` key. If built into a wheel or sdist, the metadata says nothing. Recommendation: add `license = { file = "../LICENSE" }` or an SPDX expression, using `LicenseRef-PolyForm-Noncommercial-1.0.0` since PolyForm has an SPDX id `PolyForm-Noncommercial-1.0.0`; confirm the identifier against the SPDX list (to-be-verified upstream). Also add a `LICENSE` file inside the package directory so sdists carry it.
- Seven Swift packages: `rayneo-archive`, `rayneo-audio-container`, `rayneo-display`, `rayneo-protocol`, `rayneo-session`, `rayneo-session-runtime`, `rayneo-transport-ios`. Verified: zero occurrences of "license" in each `Package.swift`. SwiftPM has no license field, so the fix is a `LICENSE` file or a header comment in each package directory (or a README line). Note the naming: these are original code named after the vendor; the name does not make them vendor-licensed, but a reader may assume so. A short README sentence "original, PolyForm Noncommercial" would remove ambiguity. Also check that the `rayneo-` prefix is acceptable use of the vendor name (the notices already state non-endorsement).
- The Python and Swift sources have no per-file SPDX headers (only one SPDX header was found in the scanned subtree). Adding them is optional but helpful, and is the only way to keep file-level clarity when files get copied between the GPL and PolyForm trees.

## 8. Other observations

- `THIRD_PARTY_NOTICES.md` is accurate but is a prose log ordered by date, and does not list the version and license of each shipped component in a table. A generated table (name, version, license, path, source) would be easier to audit.
- `DEPENDENCIES.json` says its files are "not covered by the project license", which is a good statement, but it does not add the license identifier. Adding a `license` and `source` field per entry would let CI assert that no entry is missing a license.
- A removed NetEase client adapted from Beans Music (MIT) is preserved in commit `27ad86e`; ensure the MIT notice is present there (not verified).
- The OSM test extracts under `official-addon/ios107-edition/tests/maps` are ODbL 1.0; notices say attribution is kept per fixture (not re-verified here).
- AMap and HarmonyOS SDKs are downloaded at build and carry their own terms, as stated.
- `NOTICE` says "Turbo IO contributors" with no individual name. Consider whether the copyright line should name a legal person to make relicensing and enforcement simpler.

## 9. Prioritised action list for the user

1. **Decide the RayneoNet and RayneoLog position (highest).** These proprietary binaries are tracked with no grant. Either stop tracking them and fetch or point to the user's own app copy at build time, or obtain written permission. Do this before any public release or wider sharing.
2. **Decide the stock firmware ZIPs.** `firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip` is a vendor binary (check the 1.0.4.12 stock payloads too). Consider hash plus fetch instructions instead of embedding them.
3. **Do not distribute a combined binary of the GPL AirPlay module with the vendor host** until the combination is reviewed; keep the "not a binary distribution" statement true.
4. **Confirm copyright authority for the GPL carve-out** (all contributors to `official-addon/tar2-airplay/` and the copied display/transport files). Record the evidence.
5. **Tighten the GPL subtree**: SPDX headers on every file, a short notice file with the pinned upstream licenses, and a CI check for the boundary; decide whether to split it into its own repository (option B) later.
6. **Add upstream license texts for the five open-source frameworks** (CocoaAsyncSocket, CocoaLumberjack, OpenSSL, SwiftProtobuf, SSZipArchive) for the exact versions found, after verifying each upstream license; record where they were obtained.
7. **Record provenance for `core-probe/Vendor/opus-ios/libopus.a`** (source version, flags, hash) and ship `COPYING` with it, or build it from the vendored source.
8. **Check the WebRTC VAD C sources** inside `py-webrtcvad-2.0.10` for the Google BSD notice and add it to the notices if absent.
9. **Add `firmware-research/LICENSING.md`** classifying original, vendor, derived and asset content; run a targeted search for verbatim vendor code.
10. **Add license metadata** to `dashboard-service/pyproject.toml` and a license note or file in each of the seven `rayneo-*` Swift packages.
11. **Improve the inventory**: a table in `THIRD_PARTY_NOTICES.md` and `license` or `source` fields in `DEPENDENCIES.json`, with a CI check.
12. **Seek legal review** for the whole combination (PolyForm root, GPL subtree, vendor-interoperability material) before any commercial or broad public step.
