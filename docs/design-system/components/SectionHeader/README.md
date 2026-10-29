The section header, footer and optional fold control that sit above and below an inset-grouped section.

**Consumer provides:** a header title (sentence case, no colon), an optional footer sentence that explains a privacy or network consequence, and, for long developer sections, a fold (`TIOFoldHeader`).

**Rules**
- Headers use `footnote` in `label-secondary`. Don't uppercase them: iOS 16+ grouped headers are sentence case.
- Footers say what happens and what data leaves the phone ("Looks up lyrics on lrclib.net using only…"). They don't repeat the row title.
- The fold control is an `accent` text button with at least a `hit-min` target. VoiceOver reads it as "Lyrics, heading" plus "Hide, button, expanded".
