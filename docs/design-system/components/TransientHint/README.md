A one-line control hint in band T that appears when a page opens or after input, then hides.

**Consumer provides:** a hint string using the controls' names ("Wheel", "Press", "Hold"), at most 7 words in EN.

**Rules**
- `lens-label` in `lens-high`, in band T, for `lens-hint-ms` (3000ms) after page entry or the last wheel or press input. It fades out over 300ms.
- It never sits in band B, and it is never permanent. This replaces the fixed footers in `focus_view.c` `{16,150,508,24}`, `english_native.c`, `dots_view.c`, `ride_view.c` and the music control line at y 154.
- If band T already holds ambient text (the passing road, the title), the hint replaces it while shown and the ambient text returns afterwards.
- After the wearer has seen a page's hint 3 times, show it only on entry (TMG7 option; phone-side counter).
