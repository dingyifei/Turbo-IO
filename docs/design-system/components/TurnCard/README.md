The navigation page's primary block: a turn arrow, the distance and the maneuver in band B, with the road being passed in T, trip detail in M and the map in the right column.

**Consumer provides:** maneuver icon (`TN_RIGHT` …), distance, short maneuver text, the target road, the road being passed, and remaining distance, time and ETA.

**Rules**
- **Band B, left to right:** the arrow (64×64, 8px stroke, in the left inset), distance in `lens-primary`, the maneuver in `lens-title`, and the target road in `lens-min` under them.
- **Band M:** "1.2 km · 10 min · 10:10" in `lens-body`/`lens-high`. ETA replaces the separate "Now 10:00 - ETA 10:10" clock footer.
- **Band T:** the Passing line (`lens-label`/`lens-mid`). It keeps the TMG6 fitting logic (18 → 16 → ellipsis), but 14 is dropped.
- **Map:** 148×144, right column x 372–520, bottom-anchored (y 28–172). The route is `lens-full`, roads `lens-mid` and `lens-track`.
- **Fixed slots.** Updates at 1 Hz change text only, never positions.
