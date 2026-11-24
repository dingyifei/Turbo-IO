A one-line control hint in band T that appears when a page opens or after input, then hides.

**Consumer provides:** a hint string using the controls' names ("Wheel", "Press", "Hold"), at most 7 words in EN.

**Rules**
- `lens-label` in `lens-high`, in band T, for `lens-hint-ms` (3000ms) after page entry or the last wheel or press input. It fades out over 300ms.
- It never sits in band B, and it is never permanent. In firmware it is `tio_hint.h`, used by the focus timer, music, camera and lock pages.
- If band T already holds ambient text (the passing road, the title), the hint replaces it while shown and the ambient text returns afterwards.
- After the wearer has seen a page's hint 3 times, show it only on entry (TMG7 option; phone-side counter).
