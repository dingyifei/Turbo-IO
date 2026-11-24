How the glasses show which item the wheel has selected: brightness plus a short caret, with no outlined or filled buttons.

**Consumer provides:** 2 to 5 action labels, one to two words each. On a page that is only a menu, they go on one row of band B in `lens-title`. On a page with a primary readout (a mini-app showing "4 min"), the readout keeps band B and the actions sit in band M in `lens-body`.

**Rules**
- The focused item is drawn in `lens-full` with the `lens-caret` (24×3, `radius-xs`) 4px under its baseline. Unfocused items are `lens-mid`.
- Wheel steps move focus one item, clamped at the ends (no wrap, `tio_caret.h`). The menu is the exception: it wraps. The caret slides in `lens-move-ms`, or snaps when Reduce Motion is mirrored from the phone.
- A short press runs the focused item and a long press goes back. Never list "Exit" or "Back".
- TAP1 mini-app kind 2 "buttons" render this way, with no format change (`app_view.c`). The 1px outline in `app_lvgl.c` is used only for kind 5 frames, never for focus.
- Menu grid: the caret sits under the focused icon, and the focused label shows once, in band B. This replaces the 52px rounded focus ring.
