The centred message shown when a screen has nothing to show yet, or can't work until something else happens.

**Consumer provides:** an SF Symbol, a `title3` title that names the situation, a `subheadline` sentence that says how to fix it, and an optional single action.

**Rules**
- Name the cause and the fix, without apologizing. "Glasses not connected" plus what to do, never "Something went wrong".
- At most one action, styled as an `accent` text button.
- Replaces the current `TIOEmptyState(symbol, title, detail)`. The fonts move from 18/14pt to `title3`/`subheadline`, and the padding to `space-6`.
