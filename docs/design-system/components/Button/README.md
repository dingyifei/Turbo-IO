Full-width capsule buttons for a screen's main action and its alternatives.

**Consumer provides:** a verb-first title and a role (`primary`, `secondary` or `destructive`). Optionally, a busy state that swaps the title for a spinner plus "Sending…".

**Build with:** `UIButtonConfiguration.filledButtonConfiguration` (primary) or `tintedButtonConfiguration` (secondary). Set `cornerStyle = UIButtonConfigurationCornerStyleCapsule` and a minimum height of `button-height` (50pt). The title font is `headline` via `titleTextAttributesTransformer`. Colors are `accent-fill`/`on-accent`, or `accent-soft`/`accent`. Destructive is a plain button in `status-danger`. `TIOStyleAction(button, primary, destructive)` keeps its signature and calls this.

**Rules**
- At most one primary button per screen, at the bottom of the content or pinned above the home indicator.
- Two secondary buttons may share a row. At `accessibilityLarge` and above they stack.
- A destructive action is never filled red unless it can't be undone. If it can't, confirm it with `ConfirmSheet`.
- A disabled button explains itself in its title ("Waiting for glasses…") or in the footer above it.
