The glasses type ramp, sized by visual angle and mapped to the stock vector font's pixel sizes.

**Consumer provides:** text and a role: `lens-hero`, `lens-primary`, `lens-title`, `lens-body`, `lens-label` or `lens-min`.

**Rules**
- Use only these six sizes. Mini-apps (TAP1) may use 16, 18, 20 and 24. 14 is retired, and `app.c` should reject it in TMG7.
- Angle = px ÷ `lens-ppd`. Cap height is about 0.7 em. The 16px floor gives about 27′ cap height, inside the 16–24′ minimum that human-factors standards give, with margin for edge blur.
- One `lens-hero` or `lens-primary` per page, always in band B.
- Text boxes are at least font size + 4px tall (the existing `app.c` rule). Long strings break at word boundaries (`tn_text_two_lines`) and then ellipsize. They never shrink below the role's size.
- CJK uses the same sizes. ZH strings are shorter, so they get no extra size.
