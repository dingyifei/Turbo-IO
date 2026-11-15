# Third-party components

## TVP2 / TAR2 AirPlay receiver (2026-10-23)

`official-addon/tar2-airplay/` (a GPL-3.0-or-later subtree pinning UxPlay, libplist and OpenSSL) and `official-addon/tar2-display/` were removed from the tree in cleanup(3). Their notices and licenses stay with them in git history and are unchanged there.

## APP107 / iOS 1.0.7 compatibility (2026-10-19)

`official-addon/ios107-edition` reuses reviewed NAVS3 components with their existing attribution and licenses. Its OSM test extracts remain © OpenStreetMap contributors under ODbL 1.0. No original 1.0.7 app binary, merged IPA, private web reading adapter, personal configuration or signing material is included in this source release. Vendor app and SDK rights are unchanged.

## NAVS3 / TMG2 navigation research (2026-10-19)

The small-area map extracts under `official-addon/ios107-edition/tests/maps` are © OpenStreetMap contributors, licensed under ODbL 1.0; provenance and attribution are retained in each fixture and its README. They are not personal navigation logs and are not relicensed under PolyForm. AMap SDK/services retain their separate terms and require the user's own configuration. TMG2 original vendor firmware components retain the same copyright boundaries as the prior Strix releases; only the listed original extension sources are licensed by this project. No signed/merged iOS app, developer credentials, account session or private reading adapter is included.

V2 (`official-addon/`) adds original extension sources and local preparation/signing tools only. No new official application executable, decrypted image, IPA, vendor framework or signing material is shipped in that directory. The official app is a user-supplied interoperability target, not a component licensed by this repository. The V1 client and its vendored dependencies (vendor frameworks, Opus, WebRTC VAD, ZIPFoundation) were removed from the tree in cleanup(2); their notices are in git history with them.

The root PolyForm Noncommercial 1.0.0 license covers original Turbo IO material the project has authority to license, not third-party components, vendor binaries, extracted interfaces or their trademarks. Previously granted MIT permissions remain unaffected; see docs/LICENSING.md. Do not replace any upstream license with the root license.

- RayNeo and other product names identify interoperability targets; this project is not an official manufacturer release.

Before publication, check the actual dependency inventory and retain each supplied component's original notices. The presence of a component in a local development environment is not recorded here as a license grant. IPA/App distribution, signing certificates, private service credentials and user data are outside this source release.

## Experimental Strix OS 1.0.4.12 firmware artifacts

The `firmware-strix-1.0.4.12-turbophoto-r3` prerelease contains an experimental modified OTA archive, its AP image, and a locally repacked original-content baseline. Original firmware code, libraries, and resources remain copyrighted by RayNeo, Bestechnic, and their respective rights holders. These binaries are not original firmware source code and are not relicensed under the repository's PolyForm license. No official endorsement or guaranteed recovery is implied. Original research code follows the repository license. The embedded Turbo portrait was explicitly authorized for publication by its owner.

These are high-risk research specimens, not production firmware. Their source folder, `firmware-research/strix-1.0.4.12/` (including `docs/SAFETY.md`, which must be read before handling them), was removed from the tree in cleanup(5) and is in git history. The baseline is not a full flash backup or a validated unbrick image.

The `firmware-strix-1.0.4.12-tnv1` prerelease additionally provides the exact tested TNV1 navigation OTA archive and AP image, retaining the TDP1 display test tool. Only AP content differs from the 1.0.4.12 original payload baseline; the other 13 payloads are unchanged. These original-code/resource copyright and non-endorsement boundaries also apply. Its README (`firmware-research/strix-1.0.4.12/native-navigation/README.md`) is in git history; rollback is not guaranteed. No personal merged/signed iOS package is included.

## TMU1 音乐 API 参考

The NetEase client adapted from Beans Music (MIT) was removed in 2026-10; the historical source and its license are preserved in commit `27ad86e` (for example, `git show 27ad86e:official-addon/music/Beans-MIT-LICENSE.txt`).

The `firmware-strix-1.0.4.12-tmu1` prerelease distributes the exact hardware-tested music OTA archive, retaining navigation, display and animation experiments. The firmware copyright and risk boundaries above apply equally; only AP payload content and its manifest Size/MD5 change. No account data or personal signing material is included, and original vendor firmware is not licensed as original project source.
