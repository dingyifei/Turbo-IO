A compact status indicator for glasses connection, firmware and session states.

**Consumer provides:** a state (`ok`, `warn`, `danger` or `neutral`) and a word or two in the user's language.

**Rules**
- Always use symbol plus word. The color tokens `status-ok`, `status-warn` and `status-danger` differ in lightness as well as hue, but the word carries the meaning.
- Place it under the navigation title or in a row's trailing slot, never floating over content.
- VoiceOver reads only the word. The symbol is hidden.
