# Turbo IO design system: implementation spec

This folder is the approved spec for phone and glasses UI work on `feat/design-system`. If the code and this spec disagree, the spec wins.

## Live artifacts
- Design System: https://claude.ai/artifact/99kxGzdKLKrS28m5CpQicc
- Screens: https://claude.ai/artifact/RtT8N4DackV69GwPwbSAT1

## Files
- `tokens.json`: phone colors (light and dark), type, spacing, radius and size; the lens intensity ramp, type roles and geometry.
- `README.md`: the principles and rules.
- `components/<Name>/README.md`: per-component rules. `preview.html` holds the visual reference.
- `screens/*.dc.html`: one board per screen, with current and proposed. Phone boards show the proposal in light and dark. Glasses boards draw the lens at 2× scale, so halve every px value to get device pixels.
- `screens/canvas.json`: the sticky notes per board, listing what changes and why.

`support.js` and the screenshot images are not included. The boards depend on them only for rendering; every layout value is in the markup.
