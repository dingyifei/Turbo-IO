# Licensing and noncommercial use

Turbo IO is for personal learning, interoperability research, experiments and noncommercial hobby projects. It offers no license for commercial use. The current original content is licensed under the [PolyForm Noncommercial License 1.0.0](../LICENSE), kept as the official license text. That text and the applicable law decide which uses are permitted, and govern the exceptions, notices, handling of violations and the disclaimer. This page is not an additional term that changes the license.

## Limits on commercial use

Without some other valid license, content covered by this license may not be used for commercial purposes, such as commercial sale, paid distribution, a paid hosted service or integration into a commercial product. Noncommercial does not simply mean "no direct charge"; whether a given use is allowed is decided by the license. Paying an ASR or model provider for your own API calls does not by itself turn a personal noncommercial experiment into a commercial business.

**Unlicensed commercial use, paid distribution or any other use beyond the license may infringe the rights involved; the rights holders reserve the right to take legal action as the law allows.** Whether something infringes, and what liability follows, depends on the specific conduct, any valid license and the applicable law; it does not mean that every act of charging money is automatically a crime. For a formal commercial arrangement, get a valid license from the rights holders concerned and seek your own legal advice. This project does not promise to offer a commercial license.

This is a **source-available, noncommercially licensed** research project. It is not an MIT project open to any commercial use, and it does not call a license that restricts commercial use an open source license in the OSI sense.

## 2026-09-08 license change and earlier versions

From the commit that introduced this page and the new LICENSE, the maintainer offers the current original content they have the right to license under PolyForm Noncommercial 1.0.0. Earlier public versions (including commit `f78573e0f6298677ab50adba342e161c32e9de45`) were licensed under MIT.

**This change does not retroactively revoke rights already granted by the earlier MIT versions.** For existing code already received under MIT, the original license still applies, including the right to commercial use on its terms; the new noncommercial restriction cannot override those rights. Original content added later, and never licensed under MIT, is offered under the new license. So this change cannot guarantee that the earlier code can no longer be used commercially in a lawful way, and the Git history is not deleted or rewritten to hide the original license.

If you contribute, confirm that you have the right to submit your contribution and agree to offer it under the project license in force at the time. Third-party content must keep its source and original license; do not present it as original work. Changing the project license cannot grant a license on behalf of third-party rights holders.

## Third-party dependencies

### Local exception for the TAR2 AirPlay receiver module (2026-10-23)

`official-addon/tar2-airplay/` (the receiver module that the maintainer explicitly licensed separately under **GPL-3.0-or-later** on 2026-10-23) and `official-addon/tar2-display/` were removed from the source tree in cleanup(3). In earlier versions, the license notes for these two directories stay as they were: the GPL directory is not bound by the root noncommercial terms, and `tar2-display/` and the original copies in the firmware are still offered under the root license.

The UxPlay, libplist and OpenSSL dependencies keep their GPL, LGPL and Apache licenses respectively, and their sources. Publishing standalone source does not grant a license to redistribute a binary that combines it with any closed-source host or vendor SDK; review the combination yourself and meet every license. No personal merged IPA or pre-signed receiver app was published.

The root LICENSE applies only to the original parts this project has the right to license. It does not cover vendor frameworks, recovery interfaces, third-party source, trademarks or services. These keep their own licenses and rights restrictions; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Their MIT, BSD and other license files must be kept and cannot be replaced across the board with the noncommercial license. Shipping a binary dependency alongside does not grant any extra right to commercial use or redistribution.

References: [PolyForm official license](https://polyformproject.org/licenses/noncommercial/1.0.0), [MIT license text](https://opensource.org/license/mit), [OSI Open Source Definition](https://opensource.org/osd).
