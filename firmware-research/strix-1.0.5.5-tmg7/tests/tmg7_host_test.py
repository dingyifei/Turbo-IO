#!/usr/bin/env python3
"""TMG7 host gate: design tokens, transient hint, focus caret and page layout.

Builds tests/tmg7_ui_test.c with ASan/UBSan at the default 24.8 px/deg and at other
ppd values (the layout must hold for 22..27), then builds and runs the layout gate
(tests/tmg7_layout_preview.m), which renders every page EN and ZH to PNG and checks each
widget against its band, the reserved rows, the 16 px text floor and the no-filled-panel rule.
No device I/O."""
import argparse, subprocess, sys
from pathlib import Path

FW = Path(__file__).resolve().parents[1]
BOARD = FW.parents[1] / 'docs/design-system/screens/LensApp.dc.html'
PPD_X10 = (220, 230, 240, 248, 260, 270)

def run(cmd, log):
    r = subprocess.run(list(map(str, cmd)), capture_output=True, text=True, timeout=240)
    log.write_text(r.stdout + r.stderr)
    if r.returncode:
        sys.exit('FAIL ' + ' '.join(map(str, cmd[:3])) + '\n' + r.stdout + r.stderr)
    return r.stdout

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True, help='scratch and preview directory')
    ap.add_argument('--board', type=Path, default=BOARD)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    cc = ['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-I', FW / 'src']
    for ppd in PPD_X10:
        exe = a.out / ('tmg7-ui-%d' % ppd)
        run(cc + ['-DTIO_PPD_X10=%d' % ppd, FW / 'tests/tmg7_ui_test.c', '-o', exe], a.out / ('tmg7-ui-%d-build.log' % ppd))
        if 'PASS' not in run([exe], a.out / ('tmg7-ui-%d.log' % ppd)):
            sys.exit('tmg7-ui did not report PASS at ppd %d' % ppd)
    src = FW / 'src'
    nav = src / 'navigation-runtime-v1'
    # Navigation core and the LensNav view facade (mock widgets, ASan/UBSan); tio_lang is stubbed by the tests.
    for name, files in (('nav', ['nav_test.c', 'nav_runtime.c', 'nav_visual.c']),
                        ('nav-view', ['nav_view_test.c', 'nav_view.c', 'nav_runtime.c', 'nav_visual.c'])):
        exe = a.out / ('tmg7-' + name)
        run(cc + [nav / f for f in files] + [src / 'common-v1/tio_text.c', '-o', exe], a.out / ('tmg7-%s-build.log' % name))
        if 'PASS' not in run([exe], a.out / ('tmg7-%s.log' % name)):
            sys.exit('tmg7-%s did not report PASS' % name)
    exe = a.out / 'tmg7-layout'
    run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-O1', '-g', '-fsanitize=address,undefined', '-framework', 'AppKit',
         FW / 'tests/tmg7_layout_preview.m', src / 'navigation-runtime-v1/nav_view.c', src / 'navigation-runtime-v1/nav_visual.c',
         src / 'navigation-runtime-v1/nav_runtime.c', src / 'music-runtime-v1/music.c', src / 'common-v1/tio_text.c', '-o', exe],
        a.out / 'tmg7-layout-build.log')
    if 'PASS tmg7 layout gate' not in run([exe, a.out / 'preview', a.board], a.out / 'tmg7-layout.log'):
        sys.exit('tmg7 layout gate did not report PASS')
    print('PASS tmg7 host (tokens at ppd 22..27, hint, caret, navigation core and view, layout EN/ZH)')

main()
