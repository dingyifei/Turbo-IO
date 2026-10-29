The menu's ambient status row and the grid's focus treatment. Status sits quietly in band T, and the focused item's name gets band B.

**Consumer provides:** the time, the battery percentage, an optional connection glyph, and the grid items.

**Rules**
- **Status row in T:** time on the left, battery on the right, both `lens-label`/`lens-mid`. There is no "Turbo IO" wordmark. The wearer knows which product they are wearing.
- **Unfocused icons** draw in `lens-mid` with their labels at `lens-min`. The **focused icon** draws in `lens-full` with the `lens-caret` under it, and its name in `lens-title` at band B, centred.
- **Menu bands (540×220):** reserved y 0–12, T y 12–56, the grid in M y 56–172, B y 172–212 for the focused label, and reserved y 212–220.
- **Page dots** (today 36×4 at y 214, in the reserved strip) move into band T, centred between the time and the battery.
