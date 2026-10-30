#!/usr/bin/env python3
"""TMG8 host gate (file keeps its TMG7 name): design tokens, transient hint, focus caret and page layout.

Builds tests/tmg7_ui_test.c (tokens, hint, caret) with ASan/UBSan at the default 24.8 px/deg and at other
ppd values 22..27; the page layouts are fitted to 24.8 only and must refuse any other value. Then builds and runs the layout gate
(tests/tmg7_layout_preview.m), which renders every page EN and ZH to PNG and checks each
widget against its band, the reserved rows, the 16 px text floor and the no-filled-panel rule.
TMG8 adds the carousel, the live tile state, the navigation title, the lyric fit and the dashboard card to the layout gate, and a menu matrix (every layout x route x phone link x language). The same run measures every render's 1 degree peak and lit share (the brightness gate, tests/lens_brightness.h), fails above
0.45 (band-B primary 0.65, unfocused icons 0.20) and writes brightness.json (--brightness PATH, default OUT/brightness.json); then
tests/tmg8_brightness_test.py cross-checks the metric and a sample of the renders against an independent implementation.
No device I/O."""
import argparse, base64, io, json, os, subprocess, sys, zipfile
from pathlib import Path

FW = Path(__file__).resolve().parents[1]
BOARD = FW.parents[1] / 'docs/design-system/screens/LensApp.dc.html'
DS = FW.parents[1] / 'dashboard-service'
LEGACY_TAP_B64 = DS / 'tests/fixtures/gallery_commute_legacy.tap.b64'   # committed as base64 text: the source audit rejects binaries
PPD_X10 = (220, 230, 240, 248, 260, 270)   # tokens only; the pages build at 248 alone

def run(cmd, log, env=None):
    r = subprocess.run(list(map(str, cmd)), capture_output=True, text=True, timeout=240, env=env)
    log.write_text(r.stdout + r.stderr)
    if r.returncode:
        sys.exit('FAIL ' + ' '.join(map(str, cmd[:3])) + '\n' + r.stdout + r.stderr)
    return r.stdout

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True, help='scratch and preview directory')
    ap.add_argument('--board', type=Path, default=BOARD)
    ap.add_argument('--brightness', type=Path, help='where to write brightness.json (default: OUT/brightness.json)')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    cc = ['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-I', FW / 'src']
    for ppd in PPD_X10:
        exe = a.out / ('tmg7-ui-%d' % ppd)
        run(cc + ['-DTIO_PPD_X10=%d' % ppd, FW / 'tests/tmg7_ui_test.c', '-o', exe], a.out / ('tmg7-ui-%d-build.log' % ppd))
        if 'PASS' not in run([exe], a.out / ('tmg7-ui-%d.log' % ppd)):
            sys.exit('tmg7-ui did not report PASS at ppd %d' % ppd)
    src = FW / 'src'
    # Pages are fitted to 24.8 px/deg only (tio_ui.h): each page file must build at 24.8 and refuse every other value.
    for page in ('navigation-runtime-v1/nav_view.c', 'focus-v1/focus_menu.c', 'focus-v1/focus_view.c', 'app-runtime-v1/app_view.c'):
        for ppd in (240, 247, 249, 270):
            r = subprocess.run(list(map(str, ['xcrun', 'clang', '-std=c11', '-fsyntax-only', '-DTIO_PPD_X10=%d' % ppd, '-I', FW / 'src', src / page])),
                               capture_output=True, text=True)
            if r.returncode == 0 or 'page layouts are fitted to 24.8' not in r.stderr:
                sys.exit('%s must refuse TIO_PPD_X10=%d with the TIO_PAGES_CHECK error\n%s' % (page, ppd, r.stderr))
    # Mini-app runtime: TAP1 wire from the committed legacy gallery fixture and the current gallery/examples (encoded by the
    # dashboard-service SDK, which needs only the standard library plus jsonschema).
    exe = a.out / 'tmg7-app'
    run(cc + [FW / 'tests/tmg7_app_test.c', src / 'app-runtime-v1/app.c', src / 'app-runtime-v1/app_view.c', src / 'app-runtime-v1/app_runner.c', src / 'app-runtime-v1/app_store.c', '-o', exe], a.out / 'tmg7-app-build.log')
    wires = a.out / 'app-wire'
    wires.mkdir(exist_ok=True)
    legacy_tap = wires / 'gallery_commute_legacy.tap.bin'
    legacy_tap.write_bytes(base64.b64decode(LEGACY_TAP_B64.read_text()))
    sys.path.insert(0, str(DS))
    from turbo_dashboard.app_wire import encode
    from turbo_dashboard.app_examples import examples
    gallery = json.loads(zipfile.ZipFile(FW.parents[1] / 'app-gallery/Gallery_commute.zip').read('app.json'))
    sdk = examples()
    docs = {'gallery-commute': gallery, 'sdk-weather': sdk['TurboAppSDKWeather'], 'sdk-music': sdk['TurboAppSDKMusic'], 'sdk-brief': sdk['TurboAppSDKExample']}
    # TMG8: every committed gallery package goes through the runtime and the brightness gate too (the commute package is also checked strictly above).
    for z in sorted((FW.parents[1] / 'app-gallery').glob('Gallery_*.zip')):
        if z.stem != 'Gallery_commute':
            docs['gal-' + z.stem[len('Gallery_'):]] = json.loads(zipfile.ZipFile(z).read('app.json'))
    paths = []
    for name, doc in docs.items():
        (wires / (name + '.tap')).write_bytes(encode(doc))
        paths.append(wires / (name + '.tap'))
    if 'PASS tmg7 app runtime' not in run([exe, legacy_tap] + paths, a.out / 'tmg7-app.log'):
        sys.exit('tmg7-app did not report PASS')
    nav = src / 'navigation-runtime-v1'
    # Navigation core and the LensNav view facade (mock widgets, ASan/UBSan); tio_lang is stubbed by the tests.
    for name, files in (('nav', ['nav_test.c', 'nav_runtime.c', 'nav_visual.c']),
                        ('nav-view', ['nav_view_test.c', 'nav_view.c', 'nav_runtime.c', 'nav_visual.c'])):
        exe = a.out / ('tmg7-' + name)
        run(cc + [nav / f for f in files] + [src / 'common-v1/tio_text.c', '-o', exe], a.out / ('tmg7-%s-build.log' % name))
        if 'PASS' not in run([exe], a.out / ('tmg7-%s.log' % name)):
            sys.exit('tmg7-%s did not report PASS' % name)
    # LensMenu renderer: bands, caret, single focused name, index math and allocation failures (mock widgets, ASan/UBSan).
    exe = a.out / 'tmg7-grid'
    run(cc + [FW / 'tests/focus_grid_test.c', src / 'focus-v1/focus_menu.c', src / 'common-v1/tio_text.c', src / 'menu-grid-v2/tile_config.c', '-o', exe], a.out / 'tmg7-grid-build.log')
    if 'PASS focus_grid' not in run([exe], a.out / 'tmg7-grid.log'):
        sys.exit('tmg7-grid did not report PASS')
    # TMG8 dashboard card (src/dashboard-v1): the TDC1 parser, the Round 2 layout against the board's numbers, allocation failure and fuzz
    # (mock widgets, ASan/UBSan). Its render goes through the layout gate below and the brightness gate.
    exe = a.out / 'tmg8-card'
    run(cc + [src / 'dashboard-v1/test_card.c', src / 'dashboard-v1/card.c', '-o', exe], a.out / 'tmg8-card-build.log')
    if 'dashboard parser/layout/allocation-failure/fuzz: PASS' not in run([exe], a.out / 'tmg8-card.log'):
        sys.exit('tmg8-card did not report PASS')
    exe = a.out / 'tmg7-layout'
    run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-O1', '-g', '-fsanitize=address,undefined', '-framework', 'AppKit',
         FW / 'tests/tmg7_layout_preview.m', src / 'navigation-runtime-v1/nav_view.c', src / 'navigation-runtime-v1/nav_visual.c',
         src / 'navigation-runtime-v1/nav_runtime.c', src / 'music-runtime-v1/music.c', src / 'focus-v1/focus_view.c', src / 'focus-v1/focus.c', src / 'focus-v1/focus_menu.c', src / 'menu-grid-v2/tile_config.c', src / 'common-v1/tio_text.c', src / 'app-runtime-v1/app.c', src / 'app-runtime-v1/app_view.c', src / 'app-runtime-v1/app_shelf.c', src / 'dashboard-v1/card.c', '-o', exe],
        a.out / 'tmg7-layout-build.log')
    bright = (a.brightness or a.out / 'brightness.json').resolve()
    planes = a.out / 'brightness-planes'
    planes.mkdir(exist_ok=True)
    for old in planes.glob('*.pgm'):
        old.unlink()
    env = dict(os.environ, TIO_BRIGHTNESS_JSON=str(bright), TIO_BRIGHTNESS_PLANES=str(planes))
    layout = run([exe, a.out / 'preview', a.board] + ['%s=%s' % (p.stem, p) for p in paths], a.out / 'tmg7-layout.log', env)
    if 'PASS tmg7 layout gate' not in layout or 'PASS tmg8 brightness gate' not in layout or 'PASS board LensDashCard' not in layout:
        sys.exit('tmg7 layout gate did not report PASS')
    # TMG8 menu matrix: 3 layouts x route on/off x phone linked/unlinked x EN/ZH, every one rendered to PNG by the layout gate.
    if layout.count('PASS tmg8 menu matrix') != 2:
        sys.exit('tmg8 menu matrix did not report PASS for EN and ZH')
    want = ['menu-matrix-%s-%s-%s-%s.png' % (l, r, k, z) for l in ('carousel', 'rows2', 'rows3') for r in ('route', 'noroute') for k in ('linked', 'unlinked') for z in ('en', 'zh')]
    missing = [w for w in want if not (a.out / 'preview' / w).is_file()]
    if missing:
        sys.exit('menu matrix renders missing: ' + ', '.join(missing))
    if 'PASS tmg8 brightness checks' not in run(['python3', '-I', FW / 'tests/tmg8_brightness_test.py', '--out', a.out / 'brightness', '--planes', planes, '--json', bright], a.out / 'tmg8-brightness.log'):
        sys.exit('tmg8 brightness checks did not report PASS')
    print('PASS tmg7 host (tokens at ppd 22..27, hint, caret, navigation core and view, menu grid, mini-app runtime, layout EN/ZH, TMG8 menu matrix, TMG8 brightness gate)')

main()
