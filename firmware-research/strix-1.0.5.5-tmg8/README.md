# TMG8 candidate (Round 2 fork)

**CANDIDATE-NOT-APPROVED. Offline build only; no glasses or device I/O, and no physical acceptance.**

TMG8 starts as a source-identical fork of frozen TMG7 (`../strix-1.0.5.5-tmg7`) with only the candidate archive name, this header and the phone-pin tool label renamed. Runtime build identity name (TD_BUILD_TMG6), patch sites (25) and the sole raw edit stay unchanged; the only wire change is the TMG8 caps bit described below. Before the Round 2 commits land it builds the same AP as TMG7. The phone pins stay on TMG7 until the ZIP8 re-pin. The TMG7 sections below are historical until updated; the test files keep their tmg7 names until the test-retarget step.

## TMG8 caps bit and the carousel layout value

The only wire change in TMG8 is one capability bit and one layout value that depends on it.

- **Caps bit.** `TD_CAP_MENU_CAROUSEL` is bit 9 (`0x200`) of the status `caps` word (`diagnostics.h`). `TD_CAPS_TMG8 = TD_CAPS_TMG6 | TD_CAP_MENU_CAROUSEL`. TMG8 glasses report `TD_CAPS_TMG8` in every status sample; the build field stays `TD_BUILD_TMG6` ("TMG6"), so TMG7 and TMG8 are told apart by this bit (and by the build-identity sha256), not by a new build name. TMG6 and TMG7 glasses report `TD_CAPS_TMG6` and never set it. `td_encode`/`td_decode` accept `TD_CAPS_TMG6` and `TD_CAPS_TMG8` for the TMG6 build; any other bit is still rejected.
- **Layout value.** The menu layout record (`TMC2`, `menu_config.c`) now accepts 1 (carousel) besides the grid row counts 2 and 3. A stored 1 draws the carousel (below); 2 and 3 are unchanged, and the default stays 3.
- **Negotiation.** Value 1 is honoured only from a peer that has seen the caps bit and says so: wire byte 7 of the `TML:` command (reserved and zero up to TMG7) is `TML_PEER_TMG8` (1) on a carousel SET and zero on every other command. `tml_decode` drops a SET of 1 with byte 7 zero, any grid SET or query with byte 7 set, and any other byte 7; `tml_accept` repeats the check and answers `TML_BLOCKED` without a write. So grid SETs and queries are byte-for-byte what TMG7 accepts, and a carousel SET is something TMG7 glasses decode-reject (they drop it with no reply and no write).
- **Phone.** The phone (`MenuLayout.m`) encodes layout 1 in one place, and only when the last status sample of the current peer carries the caps bit (`TIOMenuLayoutLink.glassesReportTMG8Caps`, `TDGlassesReportTMG8Caps()`); a TMG7 or TMG6 peer is never sent it and the write is refused with a note. A reply that confirms 1 is accepted (only TMG8 glasses can send it).
- **Compatibility.** C12 stays fully compatible with TMG7 and TMG6 glasses. An older phone (C11 and earlier) rejects a TMG8 status sample because of the new bit; C12 is the only phone paired with ZIP8. Rollback is C11 plus ZIP7: ZIP7 does not accept a stored 1 and falls back to the default 3 rows.

Host tests: `tests/tmg8_caps_test.c` (the `tmg8-caps` group in the phone `test.py`) covers the constants, the status codec, the command codec against a copy of the frozen TMG7 decoder, the storage state machine and reboot reload; the phone `MenuLayoutTests.m` and `tests/TDRuntimeTests.m` prove that the phone never encodes 1 for a TMG7 peer and report the caps accessor.

## Carousel layout (Round 2)

`fm_view_rows(v, FM_CAROUSEL)` (layout value 1, `focus_menu.c`, `LensMenuCarousel.dc.html`) draws one row of icons instead of the grid, through the same `FMView` widgets and `hide_legacy` of the stock rows. `fm_menu_rows()` and `fm_relayout()` now pass the stored value (1, 2 or 3) straight through; the value 1 is only ever stored after a SET that carried the TMG8 peer byte, so no extra gate is needed in the view. `tml_grid_rows` is gone.

- **Geometry** (px on the 540x220 menu canvas, the board's `BIG` / `SMALL` tables). No route: the focused icon 80 px at `lens-full`, centre x 270, cy 68; neighbours 48 px at `lens-mid` (0x77), dx 124; outer 36 px at `lens-track` (0x38), dx 214; caret 24x3 at y 114; status line (16 px, `lens-high`, band M, x 40..500, centred) at y 146; focused name 24 px in band B; clock and battery in band T. With a route: 64 / 40 / 32 px at cy 92, dx 118 / 206, caret y 127, status y 140. The page dots and the grid names are not drawn. 80 px is the largest size (`FM_CAR_MAX`; the scaler clamps there) that keeps every glyph under `lens-peak-max`.
- **One continuous model.** The focus is a fractional position `p` (8.8 fixed point). An item at signed distance `r` from it takes size, dx and brightness interpolated at `|r|` (knots 0..3 items; at 3 it is gone), so a wheel step, the wrap from the last item to the first and an interrupted step are the same slide: 160 ms cubic ease-out (`TIO_MOVE_MS`), a newer target restarts from where the position is, never queues, and goes the short way round (ties forward). A jump of several items slides through them in the same 160 ms. Items that would leave the 16 px side insets are not drawn (they are at most 11 % of `lens-track` by then).
- **Scaler.** The 48x48 4 bpp art is scaled to any size up to 80 with a bilinear filter (`car_icon`, fixed point, no per-frame heap); 48 px is the art itself and the grid's nearest-neighbour `icon()` is unchanged. Brightness is the art's level times the gain for `|r|` (0xFF, 0x77, 0x38), so a neighbour never exceeds 0x77 and an outer icon 0x38.
- **Retained pixels.** The six visible items take canvas slots in order of `|r|` (centre 80x80, then at most 64, 48, 42, 36, 36 px square), 17280 B per bank, two banks, in a union with the grid's cell storage. The menu controller allocation grows from about 20 KiB to about 35 KiB (cap `FMControl` 40 KiB, was 32 KiB); allocation failure still leaves the native menu.
- **Hooks for the next steps.** `fm_view_route(v, on, now)` is the route flag (navigation title in band T); `fm_view_line(v, text)` sets the status line (UTF-8, cut at a character boundary, empty hides it, no rewrite when unchanged); `fm_view_reduce_motion(v, on)` makes steps, wraps and the route slide snap. `fm_view_line` is wired by the live tile state (below); the navigation-title step wires `fm_view_route` from `nav_service`.
- **Tests.** `tests/focus_grid_test.c` (geometry per tile set with and without a route, the neighbours are the art at 48 px, slide midpoint and direction, wrap both ways, canvas bounds over every fraction and jump size, interrupted step, Reduce Motion, the status line), `tests/native_ui_test.c` (a stored layout 1 reaches the view) and the layout gate in `tests/tmg7_layout_preview.m` (bands with the carousel icon spanning T and M, reserved rows, 16 px text, no filled panels, no icon on the clock, battery, line or caret; sizes, offsets, caret and line against the board's constants; EN and ZH, route on and off). Previews: `menu-carousel*-{en,zh}.png`.

## Live tile state (Round 2)

`focus-v1/tile_state.h` (header only, pure) turns one read-only snapshot of the existing service state (`tile_live.h`, `TSLive`) into the carousel's status line and the grid's state dots. Nothing is sent, written or woken, and no wire or patch site changes. Each service exports one small read accessor that fills only its own fields: `tf_live` (Pomodoro, the singleton timer, so it works whichever page is up), `tm_slot_live` (Music), `tn_slot_live` (Navigation), `tc_slot_live` (Camera); the phone link is `nav_bonded && nav_connection(0x80)`, the same test the services use. `focus_menu_native.c` takes the snapshot on the 1 Hz refresh and whenever the focus moves (`live_sync`, before the redraw so the line and the focus change in one frame), never per frame.

| Tile | Condition | Line (EN / ZH) | Grid dot |
|---|---|---|---|
| Pomodoro | timer running or paused (local: no phone needed) | `18:42 left` / `剩余 18:42` | yes |
| Music | phone linked, playing flag set, phone spoke within 30 s (the `tm_expired` window) | `Playing · <title>` / `正在播放 · <title>` | yes |
| Navigation | phone linked, route session connected and not stale, metres left | `1.2 km to go` / `剩余 1.2 公里` (`950 m` and under: `640 m to go` / `剩余 640 米`) | yes |
| Camera | phone camera session open | `Live view` / `实时取景` (the page's own text; the board has no camera string) | yes |
| Music, Navigation | phone link down | `Phone not connected` / `手机未连接` | no |
| everything else | stock apps, My Apps, Display Test | name only | no |

- **Strings.** Five new `tio_text` keys (`TT_STATE_*`, EN ASCII and ZH); `{}` marks the figure. The middle dot is added in code because `tio_text` English stays ASCII. Seconds round up (`mm:ss`, two-digit minutes, `120:00` at most); kilometres have one decimal, whole kilometres from 100 km.
- **Fit.** The line is one 16 px line in the 460 px core: text that does not fit is cut at a character (a title may be one long word) and ends in an ellipsis; invalid UTF-8 is never shown. The width estimate is the lyric one (`tm_advance`), which errs wide, and the label also clips.
- **Carousel.** `fm_view_line` shows the focused tile's line under the caret (`lens-high`, y 146 or 140); empty hides it. The grid records the text but does not redraw for it.
- **Grid dot.** `fm_view_active(v, mask)` (bit per tile id) draws a 5 px disc at `lens-mid` 1 px right of and 4 px above the icon box, i.e. (cx+17, cy-20) for the 32 px icon, never above band M (`LensMenuGrid2.dc.html`). Nine extra 8x5 canvases share one 40 B buffer; they are hidden in the carousel. The mask is only rewritten, and the grid only redrawn, when it changes.
- **Not visible on every path.** The Camera session ends with its page, and Music stops updating once its page closes (the line lingers for 30 s from the last contact), so those lines appear on the menu only while something keeps them alive; Pomodoro, the phone-link line and, from tmg8(7), the Navigation line always work. A phone-fed state that outlives the page for Camera or Music would need a wire change and is out of scope.
- **Tests.** `tests/tmg8_tile_state_test.c` (group `tmg8-tile-state`: the board's three scenarios EN and ZH, boundaries, truncation, stock apps), `tests/focus_grid_test.c` (dot geometry against the board, no overlap, one shared art, redraw only on change), `tests/native_ui_test.c` (the production `live_sync` and `fm_sync` over stubbed services: carousel line per focused tile, grid dots, phone off, language switch) and the preview gate (`menu-carousel*`, `menu-live*`; the boards' `STATUS` tables are parsed and compared with the production strings and dots). Previews: `menu-live*-{en,zh}.png`, `menu-carousel-{pomodoro,offline*,stock}*-{en,zh}.png`.


## Navigation title (Round 2, option A)

`focus-v1/nav_title.h` (header only, pure) draws the next turn in band T of the menu, in both layouts (`OptionANavTitle.dc.html`; option B, the shared title bar, is not built). While a route is live, connected, not stale and the phone is linked, an 18 px arrow and `<distance> · <road>` in lens-high sit centred between the clock and the battery, e.g. `↱ 200 m · Market St`. No wire or patch change: `tn_slot_live` copies `icon`, `distance_m` and `road` from the scene `nav_service` already holds, read only.

- **Slot.** x 108..432 (the clock box is x 40..104 and the battery box x 436..500, both now 64 px wide), on the clock's row, y 23..45. The group (arrow, 6 px gap, left-aligned text) is centred on x 270. The page dots of the grid share band T and are hidden while the title shows. The carousel moves its row down and shrinks to 64/40/32 px through `fm_view_route`, wired from `live_sync`; the grid does not move.
- **Text.** `<d> m` to 10 m under 950 m, else `<d.d> km` (whole km from 100 km); the same units as the navigation page in both languages. An empty road shows the distance alone. The road is cut so its estimated width (the lyric estimator, which errs wide) fits 300 px: at the last word boundary (a space, or after any CJK character) and ending in an ellipsis; one word longer than the slot is cut at a character.
- **Arrow.** The navigation page's glyph polylines (`navigation-runtime-v1/nav_glyph.h`, shared with `nav_visual.c`) at 45/256 scale, a 2 px anti-aliased stroke in lens-high on an 18 px canvas. The roundabout mark is dense at this size.
- **Timing.** Written at most once per second (`NT_MIN_MS`): `fm_view_title` holds a changed arrow or text until a second after the last write, and `fm_sync` retries on its 1 Hz refresh. Hiding (route end, stale, link lost) is immediate. Text is banked like the status line, the arrow canvas is double buffered, and nothing is rewritten when unchanged.
- **Route lifetime.** The route session now outlives the Navigation page (tmg8(7), "Background route state" below), so the title shows on the menu for as long as the phone's route is live and not stale.

## Background route state (Round 2, ds2.md 3b)

Leaving the Navigation page no longer ends the route. While a phone route is active, closing the page (long press, the launcher hiding, or the page lost to another owner) keeps the glasses' route **data** session, so the band T title and the Navigation tile line show on the menu for the whole route. No wire change: the phone sends the same messages at the same rate, and the glasses answer the same replies.

- **What is kept.** `TNRuntime` (`navigation-runtime-v1/nav_runtime.c`, byte-shared with the phone) gets `hidden`: scene (manoeuvre, distance, road, remaining distance and time), `sid`, sequence and digest, and the stale clocks (`last_update`, `last_link`). The map's data (`TNRState`, about 8.4 KB) is copied to the heap at the moment the page closes (`tn_view_map_save`) and keeps being fed by map messages; a reopened page takes it back (`tn_view_map_restore`), so the next pose still finds its scene.
- **Closing.** `tn_detach`: the power hold is released (`TN_POWER_RELEASE`, as before), the page is left once, then `hidden` is set before the widgets go so their delete event does not end the session. If the route is not live and fresh, or the heap copy cannot be made, the page closes as before (`tn_local_exit`: the session ends). A second close (the launcher hiding after a long press) changes nothing.
- **While hidden.** UPDATE, HEARTBEAT, QUERY, MODE and the map messages are accepted with the usual sequence rules, replies stay `OK` and `active`, `awake` is clear. There is no render, no `nav_screen_on`, no power hold or sleep request, no LVGL object and no new timer (the service's existing timer keeps its period); the page's widgets are freed by the existing idle reaper. The menu reads the plain state at its own redraw (`nav_live.h`, `tn_live_fill`, shared by `nav_service` and the host tests).
- **Ends on.** STOP from the phone (route end or arrival), 60 s without an UPDATE (the existing stale limit), 30 s without any packet, a phone disconnect (`tn_disconnect`), or a new START with a newer sid (a START with an older or equal sid is answered `STALE`; one that cannot start leaves the kept route alone). The menu read applies the same limits itself, so a title is never drawn for a route already gone. The launcher menu app being destroyed ends it too (the service lives in that app). `deleted` (a page widget removed by someone else) still ends a visible session.
- **Reopening.** The Navigation tile with a kept route runs `tn_attach`: the page is built from the kept scene and the map from the kept data, with no new handshake (same `sid` and sequence; the phone's next UPDATE is accepted and rendered), the hold is taken again and the usual 60 s of manual hold starts, as for a button press. If the previous page is still being removed the press does nothing and the next one works.
- **Phone.** `TNVSession` has no page-closed signal. Its UPDATE cadence (one per changed scene, at most one a second; a refresh every 10 s; a HEARTBEAT when nothing is offered) goes on as long as the glasses answer `OK` and `active`. TMG7 glasses answer the first UPDATE after a page close with `NO_SESSION`, which ends the phone's session (unchanged). `NativeNavigationTests.m` covers both. No phone change was needed.
- **Tests.** `navigation-runtime-v1/nav_test.c` (state machine against a mock UI: leave keeps the state and releases the hold, hidden updates do no render or wake, stale, silence, disconnect, STOP, replace, reopen, 2000 leave/reopen turns with every page left and every hold released), `nav_view_test.c` (map save and restore), `tests/tmg8_nav_background_test.c` (group `tmg8-nav-background`: the menu's title and tile line from a page-less route through `tn_live_fill`, `nt_title` and `ts_state`, EN and ZH).
- **Device checks (for the user's checklist).** (1) Battery drain over a 20-minute route with the Navigation page closed against the same route with it open (page closed should be clearly lower, never higher than open). (2) The band T title tracks the turns during a real route with the page closed: arrow, distance and road change with each manoeuvre, at most once a second. (3) Long-press out of Navigation mid-route, open another app and come back to the menu: the title and `n km to go` are still there; open Navigation again: the page shows the current turn and the map without a new START. (4) End the route on the phone, walk out of range, or stop sending for a minute: the title and the tile line disappear. (5) The panel does not wake on its own while the page is closed. (6) Whether the launcher menu app is destroyed while another app is open (the route then ends with it).
- **Not host-testable.** `nav_service.c` itself (it reads fixed launcher addresses). Its edits are `close_page`, `resume`, `reap`, `map_apply` and the `deleted` guard; the logic they call is covered above.

## Knob (Round 2)

`TIO_WHEEL_DETENT_RAW 300` (`tio_ui.h`, token `lens-wheel-detent`) is the one detent. `wr_input_wheel` (pages), `tm_input_wheel` (music) and `TK_DETENT_RAW` (`knob_calibration.h`, shared with the phone, static-asserted equal in `menu_wheel.h`) use it, so one item or step takes 300 raw counts, about 6.7 per ~2000-count turn. The main menu hands the stock carousel `2 x delta` (`m8_hook_wheel`, `tio_menu_wheel_scaled`) because the stock carousel needs 600 raw units per item. At either end the stock carousel clamps, so `tio_menu_wheel_wrap` counts the raw deltas that push against the end and jumps last to first (or first to last) after a full detent; this works in every layout because it only reads the focused rank and the visible count. Its state lives in the heap menu controller (`fm_wheel_wrap`), not in the fixed owner tail or .bss. Lockouts after a step: 200 ms on pages (was 300) and 500 ms in music (was 900); the press guards are unchanged.

The status sample's `detent` is now 300 for a peer that reports the TMG8 caps bit and stays 600 (`TK_DETENT_LEGACY`) for TMG4..TMG7 samples, which the codec still accepts. Positive delta is taken as forward, as on every page, and the wrap jump (scroll position, `native_snap`, labels and frame) is host-modelled only; both need the device check. Tests: `tests/tmg8_wheel_test.c` (`tmg8-wheel`) and `src/music-runtime-v1/music_input_test.c` (`tmg8-music-input`).

## Brightness gate and the mini-app art cap (Round 2)

Glare comes from local hot spots, not total light, so every host render is measured (`tests/lens_brightness.h`, the metric of the Lens Brightness Audit and `ds2/tools/lens_metrics.py`): the **1 degree peak** is the mean of `L^2.2` (`L` = green/255) over the brightest 25x25 device-pixel window inside the image, and the lit share is the share of pixels above zero.

- **Limits** (`tokens.json` v2): no render above `lens-peak-max` 0.45. The band-B primary readout (the navigation turn arrow, the focus hero timer) may reach `lens-peak-max-primary` 0.65. Unfocused menu icons stay at or below `lens-peak-max-unfocused` 0.20.
- **Exceptions by region, not by file.** A widget counts as primary only if the fixture flags it AND its ink lies wholly in band B (y 112..172 on a page): a flagged widget outside band B is held to 0.45. A widget counts as an unfocused icon only if it is a menu canvas in the glyph zone (y 12..172 of the 540x220 menu) that is not the focused cell or the carousel centre. Each class is measured on its own plane, and the whole render must stay at or below 0.65 with a primary, 0.45 without.
- **Where it runs.** `tests/tmg7_layout_preview.m` calls `Measure` for every render the layout gate or the mini-app runner checks (menu layouts, every page EN and ZH, the app and shelf samples). A new render is included automatically as long as it goes through `Gate` or `RunWire`; a raster that is not a widget list (the dashboard card, 256x194) calls `MeasureRaster`. `tests/tmg7_host_test.py` runs it over the SDK samples and all 20 committed gallery packages and writes `brightness.json` (`--brightness PATH`, default `OUT/brightness.json`): one row per render with `screen`, `version` (`tmg8`), `page`, `lang`, `lit_pct`, `light` (mean linear light per pixel), `peak_1deg`, `peak_x`, `peak_y` (top-left of the brightest window), `center_y` (light-weighted vertical centre), plus `peak_rest`, `peak_primary`, `peak_unfocused`, `limit` and `pass`. `tests/tmg8_brightness_test.py` then compares the C metric with a brute-force reference and, when it sits next to the checkout, with `ds2/tools/lens_metrics.py`, and recomputes one render per page from its dumped plane.
- **Mini-app art cap.** `app-runtime-v1/app_view.c` draws TAP1 images (kind 4) and the progress fill (kind 3) at green `0x77` (`TAP_ART_LEVEL`) unless the item lies wholly in band B (`TAP_ART_BAND_B`), where it keeps full. The phone's `TAPPreview` applies the same rule (`TAPInBandB` in `AppUI.m`; the brightness test checks that the two agree). Before the cap the SDK music sample's album art measured 1.00 and the weather sample's sun 0.73 (the TMG7 audit rounded them 0.97 and 0.69); both now read below 0.30. Text, the caret and the track (`0x38`) are not capped, and the gallery wire is unchanged, so no gallery package changed.
- **Measuring on the host.** The preview repaints each render at 1x with AppKit and the macOS surrogate fonts (font smoothing off); canvases are blitted at their exact levels. Text peaks therefore move a little with the surrogate font; the navigation arrow is the closest to its limit (0.645 of 0.65).

## Dashboard card (Round 2)

`src/dashboard-v1/card.c` draws the TDC1 card (256x194, the wake-screen card slot) per `LensDashCard` and `spec/card/proposed.svg`. The wire is unchanged: the same `TDC1;weekly;claude5h;claudeWeek;ramFree;ramTotal;diskFree;diskTotal;icon;icon;icon` string, the same parser. `icons[3]` is still parsed and range-checked and is ignored by the renderer. `card.c` and `card.h` stay byte-identical with the phone copies.

- **Top, 16 px.** `MacBook Pro · M5 Max` in lens-mid (box y 10), then `RAM <free> of <total> GB free` and `SSD <free> of <total> TB free` in lens-high (y 32 and y 52), one line each. RAM is tenths of GB and SSD is GB shown as TB, with the same one-decimal truncation as before.
- **Bottom, three columns at x 6, 89 and 172.** The label (`Codex 7d`, `Claude 5h`, `Claude 7d`, 16 px, lens-mid, y 108), the number (`<n>%`, 32 px, lens-full, y 128) and a 70x3 bar at y 172 (track `0x003800`, fill lens-high, fill width = 70 x n / 100 rounded: the board's 69, 63 and 60). Box tops follow the board's SVG, where a text box top is the baseline minus 0.92 of the size.
- **Removed.** The three 32 px icons (and `icons.inc` with their pixel data), the two divider lines, the hard-coded plan names and the old `Weekly ... left` row. The card never says `left` or `used`: the Claude values are neutral labels until the open question (percent left or used) is answered.
- **6 px safe area.** Every box lies inside it. One exception in geometry: `100%` at 32 px is about 81 px wide, more than the 78 px the last column has before the safe edge, so in the last column only that number starts 4 px left (x 168). The other columns and all labels are fixed. Three `100%` side by side are tight (card-100-en preview).
- **Test and gate.** `src/dashboard-v1/test_card.c` (run by `tests/tmg7_host_test.py` with ASan/UBSan) checks every string, size, intensity and position, the bar rounding, `icons[]` being ignored, allocation failure at every step and parser fuzz. `tests/tmg7_layout_preview.m` renders the production `dc_render` with host widgets, compares the result with the board's proposed SVG (9 strings, 6 rects) and measures it through `MeasureRaster` (`card-en`, `card-alt-en`, `card-100-en`, `card-zero-en`, `card-full-en` rows in `brightness.json`; the board's card peaks at 0.33 of 0.45).

## Lyrics: the current line is never truncated (Round 2, ds2.md 7b)

`src/music-runtime-v1/music_layout.h` (TMG8 only; `music.c` stays byte-shared with the phone and the advance estimator is unchanged) now fits the current lyric with `tm_fit_current`, bottom-aligned on band B's bottom edge (y 172), in this order:

1. up to 2 lines at 24 px, inside band B, with the next lyric shown (as in TMG7);
2. up to 4 lines at 24 px, growing up into band M (top y 60), with the next lyric's row hidden;
3. up to 4 lines at 20 px;
4. up to 5 lines at 16 px, the legibility floor.

Only text that does not fit step 4 ends in an ellipsis (about 140 CJK characters, 28 per 16 px row). The next lyric keeps its one-line ellipsis (`tm_one_line`) and reappears as soon as the current lyric fits band B again, that is exactly when it needs at most two lines.

- **Service.** The stock label API has no font setter, so `music_service.c` keeps one label per font (24, 20, 16 px) for the current lyric and shows only the fitted one; the next-lyric label is hidden with an empty text when it is not shown. The label box is `tm_cur_rect_for(fit)`: lines x (font + 4) ending at y 172, so the top is y 60 at 4 x 28, y 76 at 4 x 24 and y 72 at 5 x 20.
- **Buffers.** The source buffer for the current lyric is 576 bytes (it was 244, which cut a 100 character Chinese line at 81 characters without an ellipsis). 575 bytes can never hide a lyric that would have fitted step 4: the widest fit is 140 four-byte glyphs, 560 bytes. The wrapped output buffer is 576 bytes.
- **Unreadable bytes.** A CR, tab, zero width space or stray byte used to stop the wrap at that byte and drop the rest of the line; `tm_clean` now turns tabs and line feeds into a space and drops the others before the fit. A row never starts or ends with a space and trailing spaces no longer add a phantom row.
- **Tests.** `tests/tmg8_lyrics_test.c` (group `tmg8-lyrics`, ASan/UBSan) checks the contract on Latin, Chinese and four-byte text at every length: the step is the first that holds the text, no ellipsis below step 4, nothing lost or added by the wrap, rows within 460 px, the next row hidden exactly past two lines, the box inside bands M and B (top never above y 60), the CJK boundaries 38 / 76 / 92 / 140, the 560 byte case and a 4000-case fuzz. `tests/tmg7_layout_preview.m` renders `lyrics-2line` ... `lyrics-over` (and `lyrics-long`, `lyrics-nextlong`), EN and ZH, through the production fit and the layout and brightness gates (peaks 0.18 to 0.30 of 0.45).

## Menu icon art (Round 2)

The 13 menu icons are the Round 2 set. Sources and masters live in `assets/menu-icons/` (`svg/NN-name.svg` is the source of truth; `png/NN-name.png` are 48x48 masters rasterised with `rsvg-convert -w 48 -h 48 -b black`, version recorded in `assets/menu-icons/README.md`). `tools/encode_icons.py` turns the masters into `src/focus-v1/focus_menu_icons.h` (4 bpp, even pixel high nibble, 24 B stride, nibble = level/17; 13 x 1152 B, `sizeof fm_icon4 == 14976` unchanged). `tests/tmg8_icons_test.py` (the `tmg8-icons` group in the phone `test.py`) proves the committed header is byte-identical to the regeneration from the masters. Gains are unchanged: unfocused 0x77, focused 0xFF. The art is the only change in this step; the carousel sizes (80 / 48 / 36 px) come with the carousel layout.

# TMG7 candidate (design-system fork)

**CANDIDATE-NOT-APPROVED. Offline build only; no glasses or device I/O, and no physical acceptance.**

TMG7 forks frozen TMG6 (`../strix-1.0.5.5-tmg6`) and re-lays every glasses page to the design system in `docs/design-system/` (the spec wins over the code; glasses boards are drawn at 2x, so every px value is halved). Wire protocol, capabilities, firmware name (TD_BUILD_TMG6, TD_CAPS_TMG6), the 25 patch sites and the sole raw carousel edit are unchanged. Changes are source-level only:

- Shared tokens in `src/common-v1` (lens intensity ramp, bands, 40..500 core, caret, 16 px text floor) with a transient hint helper that fades and hides.
- Navigation (LensNav): the distance and instruction have fixed slots (x 84 and 196) that never move or resize (a distance of 10 km and more drops its tenths and rounds to the nearest kilometre, capped at 999 km), the map is the board's x 372..520 window (canvas at x 348, car within 3 px of the window centre, columns outside it blanked, the scale bar and its label inside it, 29 px clear of the band-B text), the turn glyph has a 7 px stroke, and the fixed clock footer is gone (removed at TMG6).
- Music (LensMusic): current and next lyric labels are core width; the current lyric is never truncated (see Lyrics below), a one-line current lyric sits on the bottom row of band B, the next lyric is one line with an ellipsis, and the control hint is transient.
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
