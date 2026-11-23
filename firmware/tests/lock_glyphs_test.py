#!/usr/bin/env python3
"""TMG16 PIN digit glyphs: the committed src/lock-v1/lock_glyphs.h is exactly what tools/lock_glyphs.py makes.

Host only; standard library only; no device I/O. Also checks the table's shape and that each digit's pixels round-trip.
Run: python3 -I tests/lock_glyphs_test.py
"""
import os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import lock_glyphs as G

HEADER = os.path.join(ROOT, "src", "lock-v1", "lock_glyphs.h")
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


committed = open(HEADER, "rb").read()
regen = G.render_header()
check(regen.encode("utf-8") == committed, "lock_glyphs.h differs from the regeneration (run: python3 -I tools/lock_glyphs.py)")
packed = G.parse_header(committed.decode("utf-8"))
check(len(packed) == 10 and all(len(p) == 850 for p in packed), "header is not 10 x 850 B")
for d in range(10):
    n = G.unpack(packed[d])
    check(n == G.coverage(d), "digit %d does not round-trip" % d)
    check(max(n) == 15 and sum(1 for v in n if v == 15) > 150, "digit %d has too little full-level ink" % d)
    border = [n[y * G.W + x] for y in range(G.H) for x in range(G.W) if x in (0, G.W - 1) or y in (0, G.H - 1)]
    check(max(border) < 15, "digit %d reaches the box edge" % d)
check(len(set(packed)) == 10, "two digits share a bitmap")
view = open(os.path.join(ROOT, "src", "lock-v1", "lock_view.h")).read()
check("TLV_GLYPH_W=34,TLV_GLYPH_H=50,TLV_GLYPH_STROKE=5" in view, "lock_view.h glyph box changed: regenerate the tables for it")
if failures:
    print("FAIL lock glyphs:\n  " + "\n  ".join(failures))
    sys.exit(1)
print("PASS lock glyphs: lock_glyphs.h equals the regeneration, 10 x 850 B at 4 bpp, every digit round-trips and stays inside its 34x50 box")
