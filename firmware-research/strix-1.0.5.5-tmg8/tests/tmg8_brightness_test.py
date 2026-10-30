#!/usr/bin/env python3
"""TMG8 brightness gate checks that do not need a render: the C metric against an independent reference and against the
design system's lens_metrics.py (when that tool is present next to this checkout), and the phone mirror of the art cap.

  usage: tmg8_brightness_test.py --out DIR [--planes DIR --json brightness.json]

Without --planes it runs the metric checks only. With --planes/--json (the host run's output) it also recomputes the 1 degree
numbers of a deterministic sample of renders with the independent reference and requires them to equal the rows the gate wrote,
and requires every row to pass the limits. No device I/O."""
import argparse, json, math, random, re, subprocess, sys
from pathlib import Path

FW = Path(__file__).resolve().parents[1]
REPO = FW.parents[1]
GAMMA, WIN = 2.2, 25
LIMITS = dict(peak=0.45, primary=0.65, unfocused=0.20)

def reference(w, h, green):
    """Brute force, no summed-area table: the brightest 25x25 window by direct summation, first maximum in raster order."""
    lin = [(g / 255.0) ** GAMMA for g in green]
    n = min(WIN, w, h)
    best, bx, by = -1.0, 0, 0
    for y in range(h - n + 1):
        for x in range(w - n + 1):
            s = sum(sum(lin[(y + j) * w + x:(y + j) * w + x + n]) for j in range(n))
            if s > best + 1e-9:
                best, bx, by = s, x, y
    tot = sum(lin)
    vc = -1 if tot == 0 else sum((i // w + 0.5) * v for i, v in enumerate(lin)) / tot
    return dict(lit_pct=100.0 * sum(1 for g in green if g) / (w * h), light=tot / (w * h), peak=best / (n * n), peak_x=bx, peak_y=by, center_y=vc)

def pgm(path, w, h, green):
    path.write_bytes(b'P5\n%d %d\n255\n' % (w, h) + bytes(green))

def fast_reference(w, h, green):
    """Summed-area table in plain Python (the same algorithm as lens_metrics.py) for the 540x180/220 renders."""
    lin = [(g / 255.0) ** GAMMA for g in green]
    S = [[0.0] * (w + 1) for _ in range(h + 1)]
    for y in range(h):
        run = 0.0
        for x in range(w):
            run += lin[y * w + x]
            S[y + 1][x + 1] = S[y][x + 1] + run
    n = min(WIN, w, h)
    best, bx, by = -1.0, 0, 0
    for y in range(h - n + 1):
        for x in range(w - n + 1):
            s = S[y + n][x + n] - S[y][x + n] - S[y + n][x] + S[y][x]
            if s > best + 1e-9:
                best, bx, by = s, x, y
    tot = sum(lin)
    return dict(peak=best / (n * n), peak_x=bx, peak_y=by, center_y=-1 if tot == 0 else sum((i // w + 0.5) * v for i, v in enumerate(lin)) / tot,
                light=tot / (w * h), lit_pct=100.0 * sum(1 for g in green if g) / (w * h))

def read_pgm(path):
    d = path.read_bytes()
    m = re.match(rb'P5\n(\d+) (\d+)\n255\n', d)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, list(d[m.end():])

def lens_tool():
    """The design system's own tool, if it sits next to this checkout (overnight/ds2/tools); the test also stands alone."""
    for base in (REPO.parent.parent / 'ds2' / 'tools', REPO.parent / 'ds2' / 'tools'):
        if (base / 'lens_metrics.py').exists():
            sys.path.insert(0, str(base))
            import lens_metrics
            return lens_metrics
    return None

def close(a, b, tol=1e-9):
    return abs(a - b) <= tol * max(1.0, abs(a), abs(b))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--planes', type=Path)
    ap.add_argument('--json', type=Path)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    exe = a.out / 'tmg8-brightness'
    r = subprocess.run(['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-I', str(FW / 'tests'), str(FW / 'tests/tmg8_brightness_test.c'), '-o', str(exe), '-lm'], capture_output=True, text=True)
    if r.returncode:
        sys.exit('FAIL build tmg8_brightness_test\n' + r.stderr)
    out = subprocess.run([str(exe)], capture_output=True, text=True)
    if out.returncode or 'PASS' not in out.stdout:
        sys.exit('FAIL tmg8_brightness_test\n' + out.stdout + out.stderr)
    tool = lens_tool()
    rnd = random.Random(8)
    cases = []   # (w, h, green): random noise, a bright corner, sparse text-like lines, an all-black image, tiny images
    for w, h in ((30, 28), (40, 26), (27, 25), (25, 25), (17, 12)):
        cases.append((w, h, [rnd.choice((0, 0, 0, 56, 119, 176, 255)) for _ in range(w * h)]))
    cases.append((44, 30, [255 if x >= 30 and y >= 20 else 0 for y in range(30) for x in range(44)]))
    cases.append((50, 40, [0] * 2000))
    cases.append((60, 32, [119 if y % 5 == 0 else 0 for y in range(32) for x in range(60)]))
    paths = []
    for i, (w, h, g) in enumerate(cases):
        p = a.out / ('case%d.pgm' % i)
        pgm(p, w, h, g)
        paths.append(p)
    lines = subprocess.run([str(exe)] + [str(p) for p in paths], capture_output=True, text=True).stdout.split('\n')
    for (w, h, g), line in zip(cases, lines):
        lit, light, peak, px, py, cy = line.split()
        ref = reference(w, h, g)
        got = dict(lit_pct=float(lit), light=float(light), peak=float(peak), peak_x=int(px), peak_y=int(py), center_y=float(cy))
        for k in ref:
            if not close(ref[k], got[k], 1e-9):
                sys.exit('FAIL metric %dx%d %s: C %r reference %r' % (w, h, k, got[k], ref[k]))
        if tool:
            m = tool.metrics(w, h, g, 1, WIN)
            theirs = dict(lit_pct=100 * m['lit_share'], light=m['total_light_per_px'], peak=m['peak_25'], peak_x=m['peak_25_pos'][0], peak_y=m['peak_25_pos'][1], center_y=-1 if m['v_centre'] is None else m['v_centre'])
            for k in ref:
                if not close(theirs[k], got[k], 1e-6 if k == 'light' else 1e-9):
                    sys.exit('FAIL metric %dx%d %s: C %r lens_metrics.py %r' % (w, h, k, got[k], theirs[k]))
    print('PASS metric: C equals the brute-force reference on %d images%s' % (len(cases), ' and lens_metrics.py' if tool else ' (lens_metrics.py not found next to this checkout: reference only)'))
    # The phone's lens preview applies the same art cap on the same band edges as app_view.h.
    ui = (REPO / 'official-addon/ios107-edition/AppUI.m').read_text()
    m = re.search(r'static BOOL TAPInBandB\(CGRect r\)\{return r\.origin\.y>=(\d+)&&CGRectGetMaxY\(r\)<=(\d+);\}', ui)
    hdr = (FW / 'src/app-runtime-v1/app_view.h').read_text()
    probe = a.out / 'probe.c'
    probe.write_text('#include "app-runtime-v1/app_view.h"\n#include <stdio.h>\nint main(void){printf("%u %u %u %u",(unsigned)TIO_PAGE_M1,(unsigned)TIO_PAGE_B1,(unsigned)TAP_ART_LEVEL,(unsigned)(TIO_LENS_MID>>8&255u));return 0;}\n')
    subprocess.run(['xcrun', 'clang', '-std=c11', '-I', str(FW / 'src'), str(probe), '-o', str(a.out / 'probe')], check=True)
    m1, b1, level, mid = map(int, subprocess.run([str(a.out / 'probe')], capture_output=True, text=True).stdout.split())
    if not m or (int(m.group(1)), int(m.group(2))) != (m1, b1) or level != mid or level != 119:
        sys.exit('FAIL phone mirror: AppUI.m TAPInBandB does not match app_view.h (band B %d..%d, level 0x%x)' % (m1, b1, level))
    if 'TAPInBandB(r)?full:mid' not in ui or 'UIColor *fill=TAPInBandB(r)?full:mid' not in ui or 'TAP_ART_BAND_B' not in hdr:
        sys.exit('FAIL phone mirror: image and progress fill must follow the band-B rule')
    print('PASS phone mirror: TAPPreview caps images and progress fill at 0x%02x outside band B (y %d..%d), as app_view.c does' % (level, m1, b1))
    if a.planes and a.json:
        rows = json.loads(a.json.read_text())
        bad = [x['screen'] for x in rows if not x['pass']]
        if bad or not rows:
            sys.exit('FAIL brightness rows over the limits: %s' % bad)
        for x in rows:
            if not (0 <= x['lit_pct'] <= 100 and 0 <= x['peak_1deg'] <= 1.0 and x['peak_x'] >= 0 and x['peak_y'] >= 0 and x['page'] and x['lang'] in ('en', 'zh') and x['version'] == 'tmg8'):
                sys.exit('FAIL brightness row malformed: %r' % x)
            if x['peak_1deg'] > x['limit'] + 1e-9 or x['peak_rest'] > LIMITS['peak'] + 1e-9 or (x['peak_primary'] is not None and x['peak_primary'] > LIMITS['primary'] + 1e-9) or (x['peak_unfocused'] is not None and x['peak_unfocused'] > LIMITS['unfocused'] + 1e-9):
                sys.exit('FAIL brightness row over the limits: %s' % x['screen'])
        pages = {}
        for x in rows:
            pages.setdefault(x['page'], []).append(x)
        sample = sorted({max(v, key=lambda x: x['peak_1deg'])['screen'] for v in pages.values()})
        for x in rows:
            if x['screen'] in sample:
                w, h, g = read_pgm(a.planes / (x['screen'] + '.pgm'))
                ref = fast_reference(w, h, g)
                for k, name in (('peak', 'peak_1deg'), ('peak_x', 'peak_x'), ('peak_y', 'peak_y'), ('center_y', 'center_y'), ('light', 'light'), ('lit_pct', 'lit_pct')):
                    if not close(ref[k], x[name], 2e-3 if k in ('light', 'lit_pct', 'center_y') else 1e-3):
                        sys.exit('FAIL render %s: gate %s %r, reference %r' % (x['screen'], name, x[name], ref[k]))
                if tool:
                    m = tool.metrics(w, h, g, 1, WIN)
                    if abs(m['peak_25'] - x['peak_1deg']) > 1e-3 or list(m['peak_25_pos']) != [x['peak_x'], x['peak_y']]:
                        sys.exit('FAIL render %s: lens_metrics.py peak %r at %r, gate %r at (%d,%d)' % (x['screen'], m['peak_25'], m['peak_25_pos'], x['peak_1deg'], x['peak_x'], x['peak_y']))
        print('PASS rows: %d renders within the limits; %d renders (%s) recomputed from their planes%s' % (len(rows), len(sample), ', '.join(sample), ' with lens_metrics.py' if tool else ''))
    print('PASS tmg8 brightness checks')

main()
