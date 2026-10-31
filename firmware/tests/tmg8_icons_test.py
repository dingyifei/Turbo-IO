#!/usr/bin/env python3
"""TMG8 menu icon art: the committed header is exactly what tools/encode_icons.py makes from the PNG masters.

Host only; standard library only; no device I/O. The SVG -> PNG step (rsvg-convert) is documented in
assets/menu-icons/README.md and is deliberately not run here, so the result does not depend on a renderer version.
Run: python3 -I tests/tmg8_icons_test.py
"""
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import encode_icons as E

HEADER = os.path.join(ROOT, "src", "focus-v1", "focus_menu_icons.h")
ART = os.path.join(ROOT, "assets", "menu-icons")
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


committed = open(HEADER, "rb").read().decode("ascii")

# 1. Regeneration from the masters is byte-identical to the committed header.
regen = E.regenerate(os.path.join(ART, "png"))
check(regen == committed, "focus_menu_icons.h differs from the regeneration of assets/menu-icons/png "
      "(run: python3 -I tools/encode_icons.py)")
check(regen.encode("ascii") == open(HEADER, "rb").read(), "header bytes differ from the regeneration")

# 2. Budget: 13 x 1152 B, the same _Static_assert focus_menu.c carries.
packed = E.parse_header(committed)
check(len(packed) == 13 and all(len(p) == 1152 for p in packed), "header is not 13 x 1152 B")
check(sum(map(len, packed)) == 14976, "artwork budget is not 14976 B")
src = open(os.path.join(ROOT, "src", "focus-v1", "focus_menu.c")).read()
check("_Static_assert(sizeof fm_icon4==14976" in src, "focus_menu.c artwork budget assert changed")

# 3. Format: even pixel is the high nibble, odd the low nibble; level = nibble*17 round-trips the masters.
for i, name in enumerate(E.NAMES):
    lv = E.read_png_levels(os.path.join(ART, "png", "%02d-%s.png" % (i, name)))
    dec = [((packed[i][p // 2] >> (0 if p % 2 else 4)) & 15) * 17 for p in range(2304)]
    check(all(d == l // 17 * 17 for d, l in zip(dec, lv)), "icon %d: nibble layout does not match its master" % i)
    check(max(dec) == 255, "icon %d never reaches full level" % i)
    check(sum(1 for d in dec if d) >= 100, "icon %d is almost empty" % i)
    check(all(dec[p] == 0 for p in (0, 47, 2256, 2303)), "icon %d lights a corner pixel" % i)

# 4. Masters and sources pair up one to one, in menu order, and the README records the renderer version.
svgs = sorted(os.listdir(os.path.join(ART, "svg")))
pngs = sorted(os.listdir(os.path.join(ART, "png")))
want = ["%02d-%s" % (i, n) for i, n in enumerate(E.NAMES)]
check([s[:-4] for s in svgs] == want and all(s.endswith(".svg") for s in svgs), "svg set is not the 13 menu icons")
check([p[:-4] for p in pngs] == want and all(p.endswith(".png") for p in pngs), "png set is not the 13 menu icons")
for s in svgs:
    check('viewBox="0 0 48 48"' in open(os.path.join(ART, "svg", s)).read(), s + ": viewBox is not 0 0 48 48")
readme = open(os.path.join(ART, "README.md")).read()
check(re.search(r"rsvg-convert version \d+\.\d+\.\d+", readme) is not None, "README does not record the rsvg-convert version")
check("rsvg-convert -w 48 -h 48 -b black" in readme, "README does not record the rasterise command")

# 5. A damaged master is caught: flipping one pixel changes the regenerated header.
bad = list(E.read_png_levels(os.path.join(ART, "png", "00-recorder.png")))
bad[24 * 48 + 24] = 255 - bad[24 * 48 + 24]
check(E.encode(bad) != packed[0], "encoder ignores a changed pixel")

if failures:
    print("\n".join("FAIL: " + f for f in failures))
    sys.exit(1)
print("PASS: tmg8 icons (13 x 1152 B, regeneration from the PNG masters is byte-identical)")
