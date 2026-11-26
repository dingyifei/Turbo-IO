> Historical: describes a feature removed from the current ios107 build (2026-10)

# WeChat Reading (微信读书): reading on the glasses, approach and reference projects

2026-09-24. **This page shares the architecture, the research status and links to third-party projects. The original AP and phone modules and the exact flashed firmware have since been released separately. They contain no web-text adapter code, account sessions, cookies, keys, book caches or private IPA.** Source, firmware and build notes. The public phone module is not yet in the default build or behind the TWR1 OTA gate, so it does not work out of the box.

## What the screens look like



A layout mock-up supplied by a user, showing the menu, the sync prompt, the four-book shelf and the reading page. **It is not evidence from a device check and not a screenshot of the current public build.** The books, text, page numbers and speed in it are examples only, and no matching book resources come with it. The actual speed unit and the research status are described below.

## Which projects can I look at?

| Project | What it is useful for | Caveats |
| --- | --- | --- |
| [Tencent/WeChatReading](https://github.com/Tencent/WeChatReading) | The official WeChat Reading Skill: bookshelf, book info, table of contents, notes and highlights, reading stats | Skill 1.0.4, checked this round, has no API for full chapter text. The table of contents, blurb and highlights are not the book text. |
| [finlater/weread.koplugin](https://github.com/finlater/weread.koplugin) | How to read WeChat Reading in KOReader: login session, fetching the table of contents and text, caching, reading state | It is a KOReader plugin for the devices KOReader supports, such as Kindle and Kobo. It is not a plugin you can install on RayNeo iO, and not an iOS SDK. |

To understand why a book shows on the shelf but opens with no text, start with the second project's [README](https://github.com/finlater/weread.koplugin#readme) and [source folder](https://github.com/finlater/weread.koplugin/tree/main/weread). Our approach separates **fetching content the account has rights to** from **display and interaction on the glasses**. The glasses do not run all of KOReader or a web browser.

Upstream features, login steps and APIs can change; their current docs are authoritative. This project does not guarantee that third-party plugins work, does not log in for you, does not supply cookies, and does not deal with membership, purchase limits or bypassing risk controls.

## The phone handles content, the glasses handle display

```text
Official Skill ─── shelf/stats ──┐
EPUB/TXT you may use ────────────┼→ Phone: organise, paginate, shrink images, bounded cache
Your own web reading session ────┘              │
                                                │ Bluetooth: this shelf page / text window / controls
                                                ▼
                                       Glasses AP native reading page
                                                │
                                                └→ page turn / pick book / scroll / back requests
```

Web text access and the Skill API are two separate routes. Installing the Skill or entering a shelf key does not grant web text access. When the web session expires, the account lacks reading rights, or the format is unsupported, the reader must stop and say so. It must never pass off the blurb as the book text.

### Shelf: four books per page

- The phone fetches the shelf and handles only the four books on the current page. It downloads each cover and scales it to a **64×88 grayscale image**, 5632 bytes of pixel data per cover, before sending it to the glasses.
- The next group loads only when you turn to the next page. The glasses never store the original images for the whole shelf and never parse arbitrary network images.
- The current page and the receive staging page use a fixed double buffer. The switch happens only after the whole page passes its check and the renderer is idle, so memory LVGL is still using is never freed.
- The phone sends only the title, author, a per-session book ID and the processed cover. Account credentials never enter the glasses firmware or the Bluetooth display data.

### Reading: send a text window, not a stream of full-screen images

- The phone organises the text by paragraph and builds a bounded text window. The glasses draw the text natively and scroll locally.
- The research build sends at most **64 lines** at a time; the whole book never goes to the glasses. When the window runs short in either direction, the glasses ask the phone for more. For long books the phone should cap its chapter cache and free it on cancel, book change or exit.
- Manual knob scrolling and auto-scroll are both supported. The research build's auto speed is **30–480 characters per minute**, not pixels per second. Any manual input pauses auto-scroll so the two controls do not fight.
- Each transfer carries a session number, sequence number, length check, acknowledgement and timeout. Late data from an old session must not overwrite a new book. An SDK "send succeeded" does not mean the lens has finished drawing.
- Reading content, highlights and preferences are not uploaded to a model by default. Local reading stats and the official WeChat Reading stats are kept apart.

## Current research status and known issues

The private research build is based on **RayNeo AI iOS 1.0.5 (201) + Strix OS 1.0.4.12**. It adds an eleventh AP item, "微信读书" (WeChat Reading), and keeps the earlier display test, navigation and music entries. Only the AP content changed; the other 13 OTA payloads are untouched. That does not mean the official update process writes only the AP, and it does not guarantee the glasses will not brick.

- A user reported shelf sync working on a device. Downloading and shrinking the four covers on the phone has been verified.
- Native text fetching and window building with a normal web login session have been verified on a Mac. A user confirmed the latest AP finished updating and returned to the home screen. **None of this lets us mark all book text, continuous reading across chapters or long-term stability as passed on the lens.**
- **Known issue: long-pressing the knob to return to the shelf can misbehave. It has not been located or fixed.** If it happens, first try "退出眼镜阅读" (Exit glasses reading) on the phone. Do not reflash repeatedly in place of diagnosing. Do not treat this build as a mature everyday reader.
- Telling a knob tap from a scroll, paging back, disconnects and recovery all need wider testing. Changes to the reading controls do not mean the music menu knob problem is fixed too.

**A later release on the same day added the TWR1 original source modules and the exact flashed firmware, but did not merge the private web adapter into the public phone build.** The [TWR1 Release](https://github.com/Turbo1123/Turbo-IO/releases/tag/firmware-strix-1.0.4.12-twr1) and the existing TMU1/TNV1 are different candidates. Do not swap version strings or skip the update gate to mix-flash them. Do not flash it until you have your own matching phone integration. Ordinary SDK or app development does not need a firmware flash.

## License and privacy

- The original menu, shelf, reading layout, scrolling, transfer, local phone import and tests published here use the repository's PolyForm Noncommercial license. Stock firmware and third-party content keep their own copyright and licenses. Do not describe the whole firmware as our original source.
- The [LICENSE](https://github.com/finlater/weread.koplugin/blob/main/LICENSE) of `finlater/weread.koplugin` is AGPL-3.0. It keeps its own copyright and terms and is not covered by Turbo IO's noncommercial license. This page only links to it and describes the architecture; it does not copy its text-protocol implementation.
- If you adopt, port or distribute upstream code, check its LICENSE, NOTICE, README and how it is integrated yourself. Translating it, splitting it into folders or crediting the source does not settle every license question. If upstream statements disagree, ask the author.
- A cookie is a login credential. Use only your own account and keep the cookie in the device's secure storage. Never put it in source, firmware, an install package, a screenshot, a runtime log, a Git commit or an Issue. When it expires, log in again; never take a session from a package someone else shared.
- This page does not provide the maintainers' cookies, API keys, Apple developer account, signing certificates, personal bookshelf, text samples or private modified IPA. The main project license has not changed.

Developers should first test "phone window → glasses layout → knob events back → memory freed" with TXT/EPUB files they have rights to, or with short original texts. Research content sources and licenses separately, so login, transfer and rendering problems do not get mixed up.
