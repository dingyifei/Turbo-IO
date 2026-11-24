The phone-side picture of a glasses page, used in Navigation, Music, the tile editor, mini-apps and Turbo Display.

**Consumer provides:** the page content, or a host-rendered image of it, and a VoiceOver summary of what the wearer sees.

**Rules**
- Always `lens-black` with `lens-*` greens, whatever the phone's appearance. This is the one surface that keeps a fixed dark look (`overrideUserInterfaceStyle = Dark` on the preview view only).
- Keep the 540:180 (or 540:220 menu) aspect and never crop. It sits in a `bg-raised` card with `radius-md` corners.
- Label it honestly with "Approximate · surrogate font" when it isn't a firmware render. Remove ad-hoc "not an accurate preview" banners.
- The whole preview is one accessibility element with a summary label ("Glasses preview: Turn right in 100 metres").
- `TAPPreview`, `TCECanvas` and the `DisplayPhoneUI` navigation image draw a lens surface, so `tests/design_literals.py` lists them as exempt from the tokens-only rule.
