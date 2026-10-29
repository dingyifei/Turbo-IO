Synced lyrics on the glasses: the current line in band B, the next line in M, the track in T, and no previous line.

**Consumer provides:** the current and next lyric lines, plus the track and artist. Artwork is optional.

**Rules**
- **Current line:** `lens-title` in `lens-full`, up to two wrapped lines, which fill band B.
- **Next line:** one line of `lens-body` in `lens-high`. It is the preview of what to sing next.
- **The previous line is dropped.** It has already been heard, so it isn't worth a band.
- **Track in T:** `lens-label`/`lens-mid`, with optional 36×36 artwork in `lens-mid`. Album art at 144px is too large for an ambient role.
- **Controls** use the transient hint, not a permanent line.
