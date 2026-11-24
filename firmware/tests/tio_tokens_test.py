#!/usr/bin/env python3
"""The glasses' design constants must equal docs/design-system/tokens.json (the firmware's side of ios-addon/TIODesignTests.m).

Compiles a small host program that includes src/common-v1/tio_ui.h and tests/lens_brightness.h and prints every constant
(the derived ones evaluated by the compiler, not re-computed here), reads the carousel icon sides from src/focus-v1/focus_menu.c,
and compares them with the lens colors, the glasses type ramp, radius-xs, the lens group and the lensFirmware group of tokens.json.
Both directions: every #define in tio_ui.h is compared with a token or listed in NOT_TOKENS with a reason, and every glasses token
except the two design-time ones (lens-black has no constant, lens-guide is never shipped) is compared with the code.
Disagreements are reported, never fixed here. --tokens and --fw take scratch copies, so a changed value can be shown to fail.
No device I/O."""
import argparse, json, re, subprocess, sys
from pathlib import Path

FW = Path(__file__).resolve().parents[1]
TOKENS = FW.parent / 'docs/design-system/tokens.json'

# (token, field) -> C expression. field is 0 or 1 for a value's first or second number, or a range key.
CODE = {
    ('lens-ppd', 0): 'TIO_PPD_X10/10.0', ('lens-page-w', 0): 'TIO_PAGE_W', ('lens-page-h', 0): 'TIO_PAGE_H', ('lens-menu-h', 0): 'TIO_MENU_H',
    ('lens-reserve-top', 0): 'TIO_RESERVE_TOP', ('lens-reserve-bottom', 0): 'TIO_RESERVE_BOTTOM',
    ('lens-band-t', 0): 'TIO_PAGE_T0', ('lens-band-t', 1): 'TIO_PAGE_T1', ('lens-band-m', 0): 'TIO_PAGE_T1', ('lens-band-m', 1): 'TIO_PAGE_M1',
    ('lens-band-b', 0): 'TIO_PAGE_M1', ('lens-band-b', 1): 'TIO_PAGE_B1',
    ('lens-inset-x', 0): 'TIO_INSET_X', ('lens-core-x', 0): 'TIO_CORE_X0', ('lens-core-x', 1): 'TIO_CORE_X1',
    ('lens-caret', 0): 'TIO_CARET_W', ('lens-caret', 1): 'TIO_CARET_H', ('lens-hint-ms', 0): 'TIO_HINT_MS', ('lens-move-ms', 0): 'TIO_MOVE_MS',
    ('lens-peak-max', 0): 'LB_PEAK_MAX', ('lens-peak-max-primary', 0): 'LB_PEAK_MAX_PRIMARY', ('lens-peak-max-unfocused', 0): 'LB_PEAK_MAX_UNFOCUSED',
    ('lens-wheel-detent', 0): 'TIO_WHEEL_DETENT_DEFAULT', ('lens-wheel-detent', 'min'): 'TIO_WHEEL_DETENT_MIN',
    ('lens-wheel-detent', 'max'): 'TIO_WHEEL_DETENT_MAX', ('lens-wheel-detent', 'step'): 'TIO_WHEEL_DETENT_STEP',
    ('lens-wheel-detent', 'default'): 'TIO_WHEEL_DETENT_DEFAULT',
    ('radius-xs', 0): 'TIO_RADIUS_XS',
    ('lens-full', 0): 'TIO_LENS_FULL', ('lens-high', 0): 'TIO_LENS_HIGH', ('lens-mid', 0): 'TIO_LENS_MID', ('lens-track', 0): 'TIO_LENS_TRACK',
    ('lens-menu-band-t', 0): 'TIO_MENU_T0', ('lens-menu-band-t', 1): 'TIO_MENU_T1', ('lens-menu-band-m', 0): 'TIO_MENU_T1',
    ('lens-menu-band-m', 1): 'TIO_MENU_M1', ('lens-menu-band-b', 0): 'TIO_MENU_M1', ('lens-menu-band-b', 1): 'TIO_MENU_B1',
    ('lens-text-pad', 0): 'TIO_TEXT_PAD', ('lens-caret-gap', 0): 'TIO_CARET_GAP', ('lens-track-h', 0): 'TIO_TRACK_H',
    ('lens-glyph-min', 0): 'TIO_GLYPH_MIN', ('lens-focus-max', 0): 'TIO_FOCUS_MAX', ('lens-hint-fade-ms', 0): 'TIO_HINT_FADE_MS',
    ('lens-page-move-ms', 0): 'TIO_PAGE_MOVE_MS', ('lens-map-blend-ms', 0): 'TIO_MAP_BLEND_MS',
    ('lens-wheel-lock-page-ms', 0): 'TIO_WHEEL_LOCK_PAGE_MS', ('lens-wheel-lock-music-ms', 0): 'TIO_WHEEL_LOCK_MUSIC_MS',
}
TYPE = {'lens-hero': 'TIO_FONT_HERO', 'lens-primary': 'TIO_FONT_PRIMARY', 'lens-title': 'TIO_FONT_TITLE',
        'lens-body': 'TIO_FONT_BODY', 'lens-label': 'TIO_FONT_LABEL', 'lens-min': 'TIO_FONT_MIN'}
CAROUSEL = {'lens-carousel-icon': 0, 'lens-carousel-icon-route': 1}   # row of car_size in focus_menu.c
DESIGN_ONLY = {'lens-black', 'lens-guide'}
# Defines in tio_ui.h that are not a token value of their own, and what covers them instead.
NOT_TOKENS = {
    'TIO_UI_HEADER': 'include guard',
    'TIO_PAGES_PPD_X10': 'checked below: equals TIO_PPD_X10 (lens-ppd)',
    'TIO_PAGES_CHECK': 'static assert, not a value',
    'TIO_PX': 'angle-to-pixel helper', 'TIO_EDGE': 'angle-to-pixel helper, clamped', 'TIO_SNAP_FONT': 'font snapping helper',
    'TIO_LINE': 'checked below: every lens type role lineHeight is TIO_LINE(fontSize)',
    'TIO_CORE_W': 'checked below: TIO_CORE_X1 - TIO_CORE_X0',
}
EXTRA = {'TIO_PAGES_PPD_X10': 'TIO_PAGES_PPD_X10', 'TIO_PPD_X10': 'TIO_PPD_X10', 'TIO_CORE_W': 'TIO_CORE_W',
         'TIO_CORE_W_DERIVED': 'TIO_CORE_X1-TIO_CORE_X0', 'LB_WINDOW': 'LB_WINDOW'}


def numbers(value):
    return [float(p[:-2] if p.endswith('px') else p) for p in str(value).split()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True, help='scratch directory')
    ap.add_argument('--tokens', type=Path, default=TOKENS)
    ap.add_argument('--fw', type=Path, default=FW, help='firmware directory (src/ and tests/)')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    spec = json.loads(a.tokens.read_text())
    header = (a.fw / 'src/common-v1/tio_ui.h').read_text()
    fails = []

    # Every value the code holds, evaluated by the compiler.
    exprs = {}
    for key, expr in CODE.items(): exprs['%s|%s' % key] = expr
    for name, expr in TYPE.items():
        exprs[name + '|size'] = expr
        exprs[name + '|line'] = 'TIO_LINE(%s)' % expr
    for name, expr in EXTRA.items(): exprs['extra|' + name] = expr
    lines = ['#include "common-v1/tio_ui.h"', '#include "lens_brightness.h"', '#include <stdio.h>', 'int main(void){']
    lines += ['printf("%%s %%.9g\\n","%s",(double)(%s));' % (k, v) for k, v in exprs.items()]
    lines += ['return 0;}']
    src = a.out / 'tio_tokens_dump.c'
    exe = a.out / 'tio_tokens_dump'
    src.write_text('\n'.join(lines) + '\n')
    subprocess.run(['xcrun', 'clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(a.fw / 'src'), '-I', str(a.fw / 'tests'),
                    str(src), '-o', str(exe), '-lm'], check=True)
    got = {}
    for row in subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout.splitlines():
        k, v = row.rsplit(' ', 1)
        got[k] = float(v)

    # The carousel sides, from the one table that draws them.
    m = re.search(r'car_size\[2\]\[4\]\s*=\s*\{\{([\d,\s]+)\},\{([\d,\s]+)\}\}', (a.fw / 'src/focus-v1/focus_menu.c').read_text())
    if not m: sys.exit('FAIL car_size table not found in focus_menu.c')
    car = [[int(x) for x in g.split(',')] for g in m.groups()]

    def check(what, code, want):
        if abs(code - want) > 1e-9: fails.append('%s: code %g, tokens.json %g' % (what, code, want))

    # Tokens -> code.
    groups = {'lens': spec['lens']['tokens'], 'lensFirmware': spec['lensFirmware']['tokens'],
              'radius': [t for t in spec['radius']['tokens'] if t['name'] == 'radius-xs'],
              'color': [t for t in spec['color']['tokens'] if t['name'].startswith('lens-')]}
    compared = set()
    for group, tokens in groups.items():
        for t in tokens:
            name = t['name']
            if name in DESIGN_ONLY: continue
            if name in CAROUSEL:
                want = numbers(t['value']); row = car[CAROUSEL[name]]
                if len(want) != 3: fails.append('%s: want 3 sides (focused, neighbour, farther)' % name); continue
                for i, w in enumerate(want): check('%s[%d] (car_size[%d][%d])' % (name, i, CAROUSEL[name], i), row[i], w)
                if row[3] != row[2]: fails.append('%s: car_size[%d] farthest slot %d != %d' % (name, CAROUSEL[name], row[3], row[2]))
                compared.add(name); continue
            if group == 'color':
                want = [int(t['value'][1:], 16)]
            else:
                want = numbers(t['value'])
            fields = sorted(f for (n, f) in CODE if n == name and isinstance(f, int))
            if not fields: fails.append('%s (%s): no firmware constant is compared with it' % (name, group)); continue
            if len(fields) != len(want): fails.append('%s: tokens.json has %d numbers, the code %d' % (name, len(want), len(fields))); continue
            for f in fields: check('%s[%d] (%s)' % (name, f, CODE[(name, f)]), got['%s|%s' % (name, f)], want[f])
            if 'range' in t:
                for f in ('min', 'max', 'step', 'default'):
                    if (name, f) not in CODE: fails.append('%s range %s: no constant' % (name, f)); continue
                    check('%s range %s (%s)' % (name, f, CODE[(name, f)]), got['%s|%s' % (name, f)], numbers(t['range'][f])[0])
            compared.add(name)
    glasses = spec['type']['groups'][1]['styles']
    for s in glasses:
        name = s['name']
        if name not in TYPE: fails.append('type %s: no firmware constant' % name); continue
        check('%s fontSize (%s)' % (name, TYPE[name]), got[name + '|size'], numbers(s['fontSize'])[0])
        check('%s lineHeight (TIO_LINE)' % name, got[name + '|line'], numbers(s['lineHeight'])[0])
        compared.add(name)
    for name in set(TYPE) - {s['name'] for s in glasses}: fails.append('type %s: in the code table, not in tokens.json' % name)
    for name in {n for (n, _) in CODE} | set(CAROUSEL):
        if name not in compared: fails.append('%s: compared in code but missing from tokens.json' % name)

    # Derived checks.
    check('TIO_PAGES_PPD_X10 vs TIO_PPD_X10', got['extra|TIO_PAGES_PPD_X10'], got['extra|TIO_PPD_X10'])
    check('TIO_CORE_W', got['extra|TIO_CORE_W'], got['extra|TIO_CORE_W_DERIVED'])
    check('LB_WINDOW is 1 degree at lens-ppd', got['extra|LB_WINDOW'], round(got['lens-ppd|0']))

    # Code -> tokens: every define in tio_ui.h is compared or explained.
    used = set(re.findall(r'\b(TIO_[A-Z0-9_]+)\b', ' '.join(list(CODE.values()) + list(TYPE.values()))))
    for name in re.findall(r'^#define\s+(TIO_[A-Z0-9_]+)', header, re.M):
        if name not in used and name not in NOT_TOKENS: fails.append('%s in tio_ui.h: no token compared with it (add one or list it in NOT_TOKENS)' % name)

    if fails:
        print('\n'.join('FAIL ' + f for f in fails))
        sys.exit('tio_tokens: %d disagreement(s) between the firmware and tokens.json' % len(fails))
    print('PASS tio_tokens: %d tokens and %d type roles match tio_ui.h, lens_brightness.h and focus_menu.c' % (len(compared) - len(glasses), len(glasses)))


if __name__ == '__main__':
    main()
