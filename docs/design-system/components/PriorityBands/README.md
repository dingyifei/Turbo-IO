The layout grid every glasses page uses: a reserved top strip, then bands T, M and B. Priority rises toward the bottom.

**Consumer provides:** one primary item for band B, optional supporting items for M, and ambient items for T. Every item is assigned to exactly one band.

**Why bottom-up:** the waveguide's display window sits high in the wearer's view. The lower an item sits, the closer it is to the eye's resting line of sight, so the most important item goes lowest. The phone puts the key information at the top and the actions at the bottom for the thumb. Glasses have no thumb, so that reason doesn't apply.

**Rules**
- Band B holds one thing in `lens-full`: a glyph (left inset allowed) plus at most two text lines. Primary text stays inside `lens-core-x`.
- Band M holds at most two lines of `lens-body` in `lens-high`.
- Band T holds one line of `lens-label` in `lens-mid`, or the transient hint in `lens-high`.
- Nothing goes in y 0–12 or y 172–180.
- A spatial element (the navigation map) may span bands in the right column, anchored to the bottom of B.
- The menu (540×220) uses the same order: status in T (y 12–56), the icon grid in M (y 56–172), and the focused item's label in B (y 172–212), with y 212–220 reserved.
- The carousel menu layout (TMG8) keeps that order: clock and battery in T, the focused 80px icon (rising from T into M, between the clock and battery) with its live status line (`lens-high`) under it in M, and the focused name in B. Neighbours are 48px `lens-mid` and 36px `lens-track`. 80px is the largest icon size that keeps every glyph under `lens-peak-max`.
- In firmware these come from `tio_ui.h` (`TIO_BAND_T`, `TIO_BAND_M`, `TIO_BAND_B`), all derived from `TIO_PPD`.
