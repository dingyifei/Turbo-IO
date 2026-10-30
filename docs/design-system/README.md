Turbo IO has two surfaces that work as a pair. The **phone** is where people set things up, read and decide, and it follows Apple's Human Interface Guidelines. The **glasses** are where people glance while doing something else, and they follow the rules of a waveguide, not a screen. A rule that is right on one surface is often wrong on the other. Use this book to tell which is which.

## The two surfaces

| | Phone (iOS addon, UIKit) | Glasses (RayNeo iO, LVGL firmware) |
|---|---|---|
| Job | Configure, read, decide | Glance, then look away |
| Canvas | Safe-area layout, Dynamic Type | 540×180 app page, 540×220 menu, about 21.8° × 7.3° |
| Color | System appearance: `bg`, `label`, lime `accent` | Green mono on black: `lens-full` → `lens-track`; black is transparent |
| Units | Points; text styles | Visual angle; `lens-ppd` converts to pixels |
| Most important item | Top of the screen, near the title | Bottom band **B**, near the natural line of sight |
| Input | Touch, VoiceOver, keyboard | Wheel (1-D), short press, long press, voice |
| Actions | Buttons | No buttons: focus caret plus press |

## Content fundamentals

- **Plain, short, verb-first.** Say what will happen: "Start navigation", "Check for update", "Show on glasses". Avoid system words such as "payload", "lease" or "opcode" in UI. They belong in Developer rows.
- **Sentence case** everywhere ("Glasses firmware", not "Glasses Firmware"). No ALL CAPS, no exclamation marks, no emoji.
- **Address the user as "you" only when needed.** Most rows are nouns ("Screen timeout"), and their subtitles state the current value ("Always", "25 min", "Ready to check").
- **Every string goes through `TIOText()`** with an EN and a ZH-Hans value in `i18n/strings.jsonl`. Design for ZH being about 40% shorter and EN about 30% longer than the mockup. Rows wrap; they never truncate meaningful text.
- **Glasses copy is a glance.** Use at most 4 words in band B ("Turn right", "100 m"), numbers before nouns, and units abbreviated ("km", "min"). Never put instructions in band B. Instructions are hints, and hints are transient (see Glasses foundations).
- Real examples to keep: "Apple Maps turn-by-turn", "Ready to check", "Looks up lyrics on lrclib.net using only the song title, artist, and duration."
- Example to fix: "Copy Spotify callback diagnostics (Developer)" truncates in a row. Move it into the Developer section as "Copy callback log".

## Phone foundations (iOS)

**Appearance.** Follow the system light and dark setting. Do not set `overrideUserInterfaceStyle`. The only exception is a lens preview, which always renders `lens-black` because it depicts the glasses. Dark keeps Turbo's plum surfaces, and light uses the iOS grouped greys.

**Color.**
- Screens sit on `bg`. Grouped cells, sheets and cards sit on `bg-raised`.
- Text is `label`, and subtitles and section text are `label-secondary`.
- `label-tertiary` is only for disabled and placeholder text.
- Tint the whole hierarchy with `accent`: switches, selected segments, links, the text cursor.
- The one filled primary button per screen is `accent-fill` with `on-accent` text.
- Secondary buttons are `accent-soft` with `accent` text.
- Destructive actions use `status-danger`.
- Never use pure system blue or indigo for actions; `accent` replaces them.

**Status.** Status always pairs a symbol with a word: `status-ok` checkmark.circle.fill "Connected", `status-warn` exclamationmark.triangle.fill "Update ready", `status-danger` xmark.octagon.fill "Transfer failed". Never rely on color alone.

**Type.**
- Use only the text styles `large-title`, `title2`, `title3`, `headline`, `body`, `subheadline`, `footnote` and `caption`, through `UIFont preferredFontForTextStyle:`. Set `adjustsFontForContentSizeCategory = YES`.
- Never use `systemFontOfSize:`; there are 29 of these today.
- Use monospaced digits (`caption` + `UIFontDescriptorFeatureSettings`) for sizes, hashes and timers.
- Layouts must work at AX5. Rows grow, and horizontal button pairs stack vertically above `accessibilityLarge`.

**Layout.**
- Most screens are `UITableViewStyleInsetGrouped` with system section radius `radius-lg`. Keep that structure.
- Inside custom cells, use `space-4` horizontal and `space-3` vertical padding, and `space-2` between stacked labels.
- Separate unrelated blocks by `space-8`.
- Every tappable thing is at least `hit-min` (44pt). Full-width buttons are `button-height` (50pt) capsules (`radius-pill`).

**Navigation.**
- The hub is a navigation stack with a large title. Sub-pages push with standard titles.
- Use sheets for confirm and pickers, and full-screen covers only for the OTA wizard.
- Close is the system xmark in the top-trailing bar slot, and Info is the info.circle button beside it.

**Motion.** Use system transitions only. When `UIAccessibilityIsReduceMotionEnabled()` is on, replace slides with cross-fades and stop any looping animation.

**Accessibility.**
- Every control has an `accessibilityLabel` in the user's language. Toggle rows read as one element ("Show on glasses, switch, off").
- Decorative icon tiles are hidden from VoiceOver.
- Lens previews carry a summary label ("Glasses preview: Turn right in 100 metres").

## Glasses foundations (waveguide)

The glasses are not a small phone. The field of view is about 23.5°, so the centre of it has to stay clear for the real world. There is no eye tracking. Edges lose brightness and color. Input is one-dimensional. Design for a two-second glance.

**1. Size everything by angle.** One degree is `lens-ppd` pixels (24.8, an unverified estimate). Write sizes as angles and convert, so that a measured ppd changes one number. Human-factors practice (for example MIL-STD-1472) puts minimum legible character height around 16–24 arcminutes. Our floor is `lens-min` (16px, about 39′ em and about 27′ cap height). Use only the ramp `lens-hero` 48, `lens-primary` 32, `lens-title` 24, `lens-body` 20, `lens-label` 18, `lens-min` 16. 14px is retired.

**2. Priority runs bottom-up.** The display sits high in the field of view, so the lower an item sits, the closer it is to where the eye naturally rests.
- **Band B** (`lens-band-b`, y 112–172) holds the single thing the page is for: the turn and distance, the current lyric, the timer, the answer.
- **Band M** (`lens-band-m`, y 56–112) holds supporting detail: the remaining distance, the next lyric, the question that was asked.
- **Band T** (`lens-band-t`, y 12–56) holds ambient information: time and battery, the road being passed, the page title, and the transient hint.
- **The top `lens-reserve-top`** (12px) and the bottom `lens-reserve-bottom` (8px) stay empty, which leaves room for the display-height and depth shift. The app's display-height setting only moves this window inside a fixed optical field.
- **Within a band, primary text stays inside `lens-core-x`** (x 40–500), where both eyes overlap. Glyphs such as the turn arrow and album art may use the side insets.
- **A spatial element may span bands.** The map (192×144) sits in the right column and is anchored to the bottom of band B.

**3. Black is the container.** The waveguide adds light, so `lens-black` is see-through.
- Never draw filled boxes, cards, backgrounds or button shapes. Group items by position and intensity.
- Intensity steps down with priority: band B uses `lens-full`, band M uses `lens-high`, band T uses `lens-mid` (18px or larger only).
- `lens-track` is for tracks and dividers, never text.

**4. No buttons. One-dimensional focus.**
- The wheel moves focus, a short press acts, and a long press goes back or exits, on every page.
- Focus is shown by brightness (`lens-full` versus `lens-mid`) plus the caret (`lens-caret`, a 24×3 bar under the focused item), never by an outline box.
- An "Exit" action is never listed, because long press already does it.
- A page has at most 5 focusable items. If there are more, it pages.

**5. Hints are transient.**
- Control hints ("Wheel: previous / next · Tap: pause") appear in band T at `lens-high` for `lens-hint-ms` (3 s) after a page opens or after the last input, then disappear.
- They never occupy band B. Today's fixed footer at `{16,150,508,24}` spends the most valuable row on text that is read once. That is the pattern this system removes.

**6. Motion.** Focus and caret moves use `lens-move-ms` (160ms ease-out, or 120ms on a page change). The map blends in 180ms. There is no ambient or looping animation, and nothing moves while the wearer isn't giving input, except live data.

**7. Update rate.** Navigation data arrives at no more than 1 Hz, so layout must not reflow on each update. Fix the slots and change only the text inside them.

**8. Brightness is measured, not judged.** Glare comes from local hot spots, such as a dense filled glyph, not from total light. The rule:
- No 1° square may average more than `lens-peak-max` (0.45) in linear light (the mean of level^2.2 over a 25×25 px window).
- The one band-B primary readout (the turn arrow, the hero timer) may reach `lens-peak-max-primary` (0.65).
- Unfocused art stays at or below `lens-peak-max-unfocused` (0.20).
- Mini-app art outside band B is capped at `lens-mid`.
- Every host render passes the brightness gate, using the same metric as the Lens Brightness Audit dashboard.

**9. Knob.** Every list moves one item per `lens-wheel-detent` (300 raw counts, about 6.7 items per turn) and wraps from the last item to the first. Input lockouts are 200 ms on pages and 500 ms in music.

## Iconography

- **Phone:** SF Symbols only, in `label` or `accent`.
  - Hub rows use a 30pt `icon-tile` (`radius-sm`) with a 15pt semibold glyph.
  - Tile colors by section: Glasses `accent-fill`/`on-accent`, Assistant `tile-assistant`, Media `tile-media`, Developer `tile-developer`, each with a white glyph.
  - No custom image icons.
- **Glasses:**
  - Menu icons are 13 outline glyphs on a 48×48 grid with a 2.6-unit round stroke and no fills. The SVG sources are the single source of truth, encoded to 4 bpp in `focus_menu_icons.h`. They are drawn at 80px (carousel centre), 48 and 36px (carousel neighbours), 32px (2-row grid) or 28px (3-row grid). The focused peak is at most 0.44 at 80px, under `lens-peak-max`; larger sizes thicken the strokes past it.
  - App and card icons are 1-bit (`mono1-msb`).
  - Turn arrows are drawn as 64×64 strokes 8px wide.
  - All of them are single-ink `lens-full`, or `lens-mid` when unfocused.
  - No emoji, and no pictograms smaller than 24px (about 1°).

## Don't

- **Phone:** don't force dark. Don't use `systemFontOfSize:`, raw `colorWithRed:`, or numeric constraint constants outside `TIODesign`. Don't leave a control without a label. Don't truncate meaningful text.
- **Glasses:** don't put the title at the top and the hints at the bottom (phone habit). Don't draw boxes or filled buttons, use text below 16px, light the whole field, use the top 12px, or show a hint for more than 3 seconds.
