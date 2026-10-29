A thin progress track paired with a hero value, used for the Pomodoro timer, the reader position and OTA progress on the glasses.

**Consumer provides:** progress from 0 to 1, a hero value (a countdown or a percentage), and an optional count ("2 / 4").

**Rules**
- **The track:** 4px tall, x 40–500 in band T, `lens-track` with a `lens-full` fill and `radius-xs` caps.
- **The hero value:** `lens-hero` with tabular digits in band B. There is only one per page.
- **No percentage text.** Don't print a percentage next to a track; the hero value carries the number.
