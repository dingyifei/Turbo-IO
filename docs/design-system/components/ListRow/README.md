The inset-grouped list row used by every Turbo screen: an optional icon tile, a title, an optional subtitle or trailing value, and one accessory.

**Consumer provides:** title (`body`), optional subtitle (`subheadline`, `label-secondary`) that states the current value, optional SF Symbol and section (picks the tile color), and an accessory: disclosure chevron, switch, or trailing value.

**Build with:** `UIListContentConfiguration.subtitleCellConfiguration` / `valueCellConfiguration` on `bg-raised`, layout margins `space-3` × `space-4`, and `accessoryType` for the chevron. Don't add a second label hierarchy inside the cell. `TIOStyleResearchCell` becomes a thin wrapper over `TIODesignStyleRow`.

**Rules**
- Use a subtitle for a value the user should notice ("Ready to check", "25 min"). Use a trailing value for a picker's current choice ("RayNeo assistant").
- Toggle rows have no chevron, and the whole row is one VoiceOver element: "Show on glasses, switch button, on".
- The icon tile is decorative (`accessibilityElementsHidden`).
- Text wraps to any number of lines. At AX sizes the trailing value moves under the title (`prefersSideBySideTextAndSecondaryText = NO`).
- Developer-only rows live in the Developer section, never mixed into feature sections.
