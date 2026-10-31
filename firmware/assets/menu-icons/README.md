# TMG8 menu icons

The 13 icon sources and the masters the device art is generated from.

| Path | Role |
| --- | --- |
| `svg/NN-name.svg` | Source of truth. 48x48 viewBox, white stroke, from the Round 2 design (`icons-proposed/svg`). |
| `png/NN-name.png` | 48x48 RGB masters, rasterised from the SVG on black. Committed so the build never needs a renderer. |
| `../../tools/encode_icons.py` | PNG masters to `src/focus-v1/focus_menu_icons.h` (4 bpp). |
| `../../tests/tmg8_icons_test.py` | Proves the committed header equals the regeneration from the masters. |

`NN` is the menu index and the order of `names[]` in `focus_menu.c`: 00 recorder, 01 live-captions, 02 live-assist,
03 todo, 04 teleprompter, 05 lifelog, 06 do-not-disturb, 07 display-test, 08 navigation, 09 music, 10 pomodoro,
11 my-apps, 12 camera.

## Regenerate

SVG to PNG (documented, not part of the test; run from this directory):

    for f in svg/*.svg; do rsvg-convert -w 48 -h 48 -b black "$f" -o "png/$(basename "$f" .svg).png"; done

PNG to header (from the firmware tree root):

    python3 -I tools/encode_icons.py            # writes src/focus-v1/focus_menu_icons.h
    python3 -I tools/encode_icons.py --check    # exit 1 unless the header is byte-identical to the regeneration
    python3 -I tests/tmg8_icons_test.py

Masters in this commit were made with:

    rsvg-convert version 2.63.4
    cairo 1.18.6, pango 1.58.2, harfbuzz 15.0.0, fontconfig 2.18.3

A different renderer version may anti-alias a pixel differently. If the masters are ever re-rasterised, commit the new
PNGs and the regenerated header together.

## Format

Header: `fm_icon4[13][1152]`, 14976 B (`_Static_assert(sizeof fm_icon4==14976)` in `focus_menu.c`).
Per icon: 48 rows of 24 B. Pixel `pos = row*48 + col`; an even pixel is the high nibble, an odd pixel the low nibble.
Nibble = green level / 17 (integer division); the lens is green-only. The grid draws the icon at 28 px (3 rows) or
32 px (2 rows) with the existing nearest-neighbour `icon()` scaler and its unchanged gains (unfocused 0x77, focused 0xFF); the carousel
draws it at any size from 32 to 80 px with its own bilinear scaler (`car_icon` in `focus_menu.c`) and gains 0xFF/0x77/0x38.
80 px is the measured maximum that stays under the `lens-peak-max` 0.45.
