"""Portable macOS offline tests. No phone, network, signing or flashing."""
from pathlib import Path
import argparse, fnmatch, json, os, re, shutil, subprocess, tempfile, zipfile
P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--firmware',type=Path,help='the release ZIP under test (required unless --firmware-only)')
parser.add_argument('--app1021',type=Path,help='stock 1.0.21/1 Runner.app (download-only and full host checks)')
parser.add_argument('--only',help='comma-separated test groups')
parser.add_argument('--release',help='phone release configuration from releases.json (cN; default: the only release, when there is exactly one); --firmware must be its ZIP')
parser.add_argument('--out',type=Path,help='log and binary directory (default build/tests)')
parser.add_argument('--tree-firmware',type=Path,help='the ZIP built from the current firmware tree, for the tree audit (default: --firmware)')
parser.add_argument('--tree-stock',type=Path,help="the stock ZIP of the tree's base, for the tree audit and tmg4-stock-abi (default: build.py --show stock-zip)")
parser.add_argument('--stock-package',type=Path,help="the release's second package, the stock ZIP of its base (phone_pins.py --resolve cN --package STOCK-<base>; default: build.py --show stock-zip for the release's base)")
parser.add_argument('--firmware-only',action='store_true',help='the tree audit and the firmware groups only (tmg4-host, tmg9-wheel-hook, tmg9-detent); needs --tree-firmware, refuses --firmware and --release')
args=parser.parse_args()
FIRMWARE_GROUPS={'tmg4-host','tmg9-wheel-hook','tmg9-detent'}
if args.firmware_only:
    if args.firmware is not None:raise SystemExit('--firmware-only refuses --firmware')
    if args.release is not None:raise SystemExit('--firmware-only refuses --release')
    if args.tree_firmware is None:raise SystemExit('--firmware-only needs --tree-firmware')
elif args.firmware is None:raise SystemExit('pass --firmware')
only=set(args.only.split(',')) if args.only else None
if args.firmware_only and only and only-FIRMWARE_GROUPS:raise SystemExit('--firmware-only runs only '+', '.join(sorted(FIRMWARE_GROUPS))+'; not: '+', '.join(sorted(only-FIRMWARE_GROUPS)))
manifest=json.loads((P/'tests/manifest.json').read_text())['tests']
test_files={str(f.relative_to(P)) for f in P.rglob('*') if f.is_file()
    and 'build' not in f.relative_to(P).parts
    and any(fnmatch.fnmatchcase(f.name,g) for g in ('Tests.m','*Tests.m','*Test.m','*_test.c'))}
if test_files!=set(manifest):
    raise SystemExit('manifest mismatch: missing='+str(sorted(test_files-set(manifest)))+
        ' stale='+str(sorted(set(manifest)-test_files)))
for file,entry in manifest.items():
    if entry.get('status')=='run' and entry.get('group'):
        continue
    if entry.get('status')=='excluded' and entry.get('reason'):
        continue
    raise SystemExit('invalid manifest entry: '+file)

ROOT=P.parent
FW=ROOT/'firmware'   # the single firmware tree; released candidates are the fw/tmgN tags, not folders
def show_stock_zip(base=None):
    # The one resolver of stock ZIP paths: build.py --show stock-zip (the tree's base, or --base).
    r=subprocess.run(['python3','-I',str(FW/'build.py'),'--show','stock-zip']+(['--base',base] if base else []),capture_output=True,text=True)
    if r.returncode:raise SystemExit('cannot resolve the stock ZIP: '+(r.stderr.strip() or r.stdout.strip()))
    return Path(r.stdout.strip())
# The tree audit follows the tree's stock base (build-inputs.json stockBase) and audits the tree's own ZIP.
tree_stock=args.tree_stock or show_stock_zip()
if not tree_stock.is_file():raise SystemExit('stock ZIP not found: pass --tree-stock (looked for '+str(tree_stock)+')')
subprocess.run(['python3',FW/'build.py','--stock',tree_stock,'--audit',args.tree_firmware or args.firmware],check=True)
if args.firmware_only:release=release_stock=None;release_versions=[];release_define=[]
else:
    # The phone groups test one release configuration: its ZIP (--firmware), its stock base and its version policy.
    # With no --release, the only release in releases.json; with several, --release is required.
    releases=json.loads((P/'releases.json').read_text())['releases']
    if args.release is None:
        if len(releases)!=1:raise SystemExit('pass --release: releases.json lists '+', '.join(releases))
        args.release=next(iter(releases))
    if args.release not in releases:raise SystemExit('unknown release '+args.release)
    release=releases[args.release]
    release_stock=show_stock_zip(release['stockBase'])
    if not release_stock.is_file():raise SystemExit('stock ZIP not found: '+str(release_stock)+' (stock '+release['stockBase']+' of release '+args.release+')')
    # The first package is the default (the TMG build) and is what --firmware is; the second is the stock package.
    release_packages=release['packages'];release_default=release_packages[0]
    release_versions=['Strix OS '+v for v in release_default['acceptCurrent']]
    release_define=['-DTIO_RELEASE_%s=1'%args.release.upper()]
    stock_label=next((p['label'] for p in release_packages[1:] if p['label'].startswith('STOCK-')),None)
    stock_package=args.stock_package or release_stock
    if not stock_package.is_file():raise SystemExit('stock package ZIP not found: '+str(stock_package))
    print('release: '+args.release+' ('+release_default['label']+' on stock '+release['stockBase']+'; accepts '+', '.join(release_versions)+'; packages '+', '.join(p['label'] for p in release_packages)+')')
out=(args.out or P/'build/tests').resolve();out.mkdir(parents=True,exist_ok=True)
def run(name,cmd,env=None):
    r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=180,env=env)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError(name+' failed: '+r.stdout+r.stderr)
flags=['xcrun','clang','-O1','-g','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types','-fsanitize=address,undefined','-framework','Foundation','-I',P]
flags+=release_define
flags+=['-DTIO_TEST_UI_LANGUAGE_ZH=1','-framework','NaturalLanguage',P/'TIOLanguage.m',P/'TIOTextLanguage.m',P/'Localization.m']
groups=[]
skipped=[]
seen=set()
def skip(name,reason):
    seen.add(name)
    skipped.append([name,reason])
def test(name,files,argv=(),extra=(),san=True,runs=None):
    seen.add(name)
    if only is not None and name not in only:
        skip(name,'not selected by --only');return
    compile_flags=flags if san else [f for f in flags if f!='-fsanitize=address,undefined']
    run(name+'-build',compile_flags+list(extra)+[P/f for f in files]+['-o',out/name])
    for i,arguments in enumerate(runs if runs is not None else [argv]):
        run(name+('-'+str(i+1) if runs is not None else ''),[out/name,*arguments])
    groups.append(name);print(name+': PASS')
def catalyst_test(name,files,argv=(),extra=()):
    seen.add(name)
    if only is not None and name not in only:
        skip(name,'not selected by --only');return
    catalyst=['xcrun','clang','-target','arm64-apple-ios16.0-macabi','-fobjc-arc','-fmodules',
        '-framework','Foundation','-framework','UIKit','-I',P]
    run(name+'-build',catalyst+list(extra)+[P/f for f in files]+['-o',out/name])
    home=out/'catalyst-home';(home/'Documents').mkdir(parents=True,exist_ok=True)
    run(name,[out/name,*argv],env={**os.environ,'CFFIXED_USER_HOME':str(home)})
    groups.append(name);print(name+': PASS')
# Firmware tests live outside the edition manifest's discovery tree.
def ctest(name,files,inc,flags=()):
    run(name+'-build',['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra',
        '-fsanitize=address,undefined',*flags,'-I',inc,*files,'-o',out/name])
    run(name,[out/name])
    if 'PASS' not in (out/(name+'.log')).read_text():
        raise RuntimeError(name+' did not report PASS')
seen.add('tmg4-host')
if only is None or 'tmg4-host' in only:
    run('tmg8-host',['python3','-I',FW/'tests/tmg7_host_test.py','--out',out/'tmg8-host','--brightness',out/'tmg8-host/brightness.json'])   # tokens, app runtime, nav, menu grid and carousel, card, layout EN/ZH, brightness gate (the script keeps its tmg7 name)
    ctest('tmg6-passing',[FW/'tests/tmg6_passing_test.c',FW/'src/navigation-runtime-v1/nav_runtime.c'],FW/'src')
    ctest('tmg4-diagnostics',[FW/'src/diagnostics-v1/diagnostics_test.c',FW/'src/diagnostics-v1/diagnostics.c'],FW/'src/diagnostics-v1')
    ctest('tmg8-caps',[FW/'tests/tmg8_caps_test.c',FW/'src/menu-grid-v2/menu_config.c',FW/'src/diagnostics-v1/diagnostics.c'],FW/'src')
    ctest('tmg9-stepping',[FW/'tests/tmg9_stepping_test.c'],FW/'src')
    ctest('tmg8-music-input',[FW/'src/music-runtime-v1/music_input_test.c'],FW/'src/music-runtime-v1')
    run('tmg8-icons',['python3','-I',FW/'tests/tmg8_icons_test.py'])
    run('tmg8-brightness',['python3','-I',FW/'tests/tmg8_brightness_test.py','--out',out/'tmg8-brightness'])
    ctest('tmg8-lyrics',[FW/'tests/tmg8_lyrics_test.c'],FW/'src')
    ctest('tmg8-tile-state',[FW/'tests/tmg8_tile_state_test.c',FW/'src/common-v1/tio_text.c'],FW/'src')
    ctest('tmg8-nav-title',[FW/'tests/tmg8_nav_title_test.c',FW/'src/common-v1/tio_text.c'],FW/'src')
    ctest('tmg8-nav-background',[FW/'tests/tmg8_nav_background_test.c',FW/'src/navigation-runtime-v1/nav_runtime.c',FW/'src/common-v1/tio_text.c'],FW/'src')
    ctest('tmg4-command',[FW/'src/diagnostics-v1/command_test.c',FW/'src/diagnostics-v1/command.c',FW/'src/diagnostics-v1/diagnostics.c'],FW/'src/diagnostics-v1')
    ctest('tmg4-status',[FW/'tests/runtime_status_test.c',FW/'src/diagnostics-v1/diagnostics.c',FW/'src/diagnostics-v1/command.c'],FW/'src')
    ctest('tmg4-timer-wrap',[FW/'tests/timer_wrap_test.c',FW/'src/menu-grid-v2/tile_config.c',FW/'src/menu-grid-v2/menu_config.c'],FW/'src')
    ctest('tmg4-knob',[FW/'tests/knob_test.c',FW/'src/diagnostics-v1/knob_calibration.c'],FW/'src')
    run('tmg4-identity',['python3','-I',FW/'tests/identity_test.py'])
    run('tmg-release-label',['python3','-I',FW/'tests/release_label_test.py'])   # the label comes from firmware/RELEASE, not the folder name
    ctest('tmg4-tile-config',[FW/'tests/tile_config_test.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src')
    ctest('tmg4-menu-tiles',[FW/'tests/menu_tiles_test.c'],FW/'src')
    ctest('tmg4-menu-lang',[FW/'tests/menu_lang_test.c',FW/'src/global-remote-v1/lang_flag.c',FW/'src/global-remote-v1/lang_store.c'],FW/'src')
    ctest('tmg4-lang-store',[FW/'tests/lang_store_test.c',FW/'src/global-remote-v1/lang_store.c'],FW/'src')
    ctest('tmg13-lock-core',[FW/'tests/lock_core_test.c',FW/'src/lock-v1/lock_core.c'],FW/'src')   # PIN lock state and start-up tables, delays, clock faults
    ctest('tmg13-lock-store',[FW/'tests/lock_store_test.c',FW/'src/lock-v1/lock_store.c',FW/'src/lock-v1/lock_core.c'],FW/'src')
    ctest('tmg13-lock-view',[FW/'tests/lock_view_test.c',FW/'src/lock-v1/lock_view.c',FW/'src/lock-v1/lock_core.c',FW/'src/common-v1/tio_text.c'],FW/'src')
    ctest('tmg13-lock-codec',[FW/'tests/lock_codec_test.c',FW/'src/lock-v1/lock_codec.c',FW/'src/lock-v1/lock_service.c',FW/'src/lock-v1/lock_store.c',FW/'src/lock-v1/lock_core.c'],FW/'src')
    ctest('tmg13-lock-native',[FW/'tests/lock_native_test.c',FW/'src/lock-v1/lock_view.c',FW/'src/lock-v1/lock_core.c',FW/'src/lock-v1/lock_service.c',FW/'src/lock-v1/lock_store.c',FW/'src/lock-v1/lock_codec.c',FW/'src/common-v1/tio_text.c'],FW/'src',['-DTD_STOCK_10412=0','-DTD_STOCK_1055=0','-DTD_STOCK_10512=0','-DTD_STOCK_10611=1','-include',FW/'src/firmware_profile.h'])   # key/wheel hooks, gates, boot, anchor, TLK: routing against stubbed stock
    ctest('tmg14-bth-motion',[FW/'tests/bth_motion_test.c'],FW/'bth-v1',['-I',FW/'src/lock-v1'])   # BTH head-motion body: windows, bars, 30 s rate, NaN prime at motion on, failed send
    ctest('tmg4-text',[FW/'tests/tio_text_test.c',FW/'src/common-v1/tio_text.c'],FW/'src')
    ctest('tmg4-grid',[FW/'tests/focus_grid_test.c',FW/'src/focus-v1/focus_menu.c',FW/'src/common-v1/tio_text.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src')
    ctest('tmg12-tile-model',[FW/'tests/tile_model_test.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src')
    ctest('tmg12-tile-model-10611',[FW/'tests/tile_model_test.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src',['-DTD_STOCK_10611=1'])
    ctest('tmg12-tile-config-10611',[FW/'tests/tile_config_test.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src',['-DTD_STOCK_10611=1'])
    ctest('tmg12-menu-tiles-10611',[FW/'tests/menu_tiles_test.c'],FW/'src',['-DTD_STOCK_10611=1'])
    ctest('tmg12-grid-10611',[FW/'tests/focus_grid_test.c',FW/'src/focus-v1/focus_menu.c',FW/'src/common-v1/tio_text.c',FW/'src/menu-grid-v2/tile_config.c'],FW/'src',['-DTD_STOCK_10611=1'])
    ctest('tmg12-timer-wrap-10611',[FW/'tests/timer_wrap_test.c',FW/'src/menu-grid-v2/tile_config.c',FW/'src/menu-grid-v2/menu_config.c'],FW/'src',['-DTD_STOCK_10611=1'])
    run('tmg12-menu-tail',['python3','-I',FW/'tests/menu_tail_host_test.py','--out',out/'menu-tail-host'])
    run('tmg12-nav-service',['python3','-I',FW/'tests/nav_service_host_test.py','--out',out/'tmg12-nav-service-host'])
    run('tmg12-unarmed-services',['python3','-I',FW/'tests/unarmed_services_host_test.py','--out',out/'unarmed-services-host'])
    ctest('tmg5-music',[FW/'src/music-runtime-v1/music_test.c',FW/'src/music-runtime-v1/music.c'],FW/'src/music-runtime-v1')
    ctest('tmg5-noncardinal',[FW/'tests/noncardinal_smoothing_test.c'],FW/'src')
    ctest('tmg5-smoothing',[FW/'tests/smoothing_test.c',FW/'src/navigation-runtime-v1/nav_runtime.c'],FW/'src')
    ctest('tmg4-prediction',[FW/'tests/pose_prediction_test.c',FW/'src/navigation-runtime-v1/nav_runtime.c'],FW/'src')
    run('tmg4-native-ui',['python3','-I',FW/'tests/native_ui_host_test.py','--out',out/'tmg4-native-ui-host'])
    run('tmg4-native-status',['python3','-I',FW/'tests/native_status_host_test.py','--out',out/'tmg4-native-status-host'])
    run('tmg12-native-light',['python3','-I',FW/'tests/native_light_host_test.py','--stock',tree_stock,'--out',out/'tmg12-native-light'])   # bucket edges read from the stock image
    run('tmg12-native-display',['python3','-I',FW/'tests/native_display_host_test.py','--out',out/'tmg12-native-display'])
    run('tmg4-native',['python3','-I',FW/'tests/native_host_test.py','--out',out/'tmg4-native-host'])
    run('tmg4-stock-abi',['python3','-I',FW/'tests/stock_abi_test.py','--stock',tree_stock])
    run('tmg12-stock-layout',['python3','-I',FW/'tests/stock_layout_test.py','--stock',tree_stock])
    run('tmg12-layout-lint',['python3','-I',FW/'tools/check_layout.py',FW])
    ctest('tmg12-native-file',[FW/'src/image-upload-test/native_file_bridge_test.c',FW/'src/image-upload-test/native_file_bridge.c',FW/'src/image-upload-test/image_test.c'],FW/'src/image-upload-test')
    run('tmg4-kept',['python3','-I',FW/'tools/check_kept.py',FW/'baseline/kept',FW])
    run('tmg4-cjk',['python3','-I',FW/'tools/check_cjk.py',FW])
    run('tmg10-stock-base',['python3','-I',FW/'tests/stock_base_test.py'])   # labels from stockBase, mixed cores refused, tree on one base
    run('tmg10-rebase-independent',['python3','-I',FW/'tests/rebase_independent_test.py'])   # every rebased address re-derived without the table (exports fw/tmg9)
    run('tmg10-render-idle',['python3','-I',FW/'tests/render_idle_host_test.py','--out',out/'tmg10-render-idle'])
    groups.append('tmg4-host');print('tmg4-host: PASS')
else:skip('tmg4-host','not selected by --only')
# TMG9 bug 1: the REAL m8_hook_wheel (sliced from menu10.c) against a stock model transcribed from the disassembly; the TMG8 body must fail it.
seen.add('tmg9-wheel-hook')
if only is None or 'tmg9-wheel-hook' in only:
    run('tmg9-wheel-hook',['python3','-I',FW/'tests/tmg9_wheel_host_test.py','--out',out/'tmg9-wheel-hook'])
    groups.append('tmg9-wheel-hook');print('tmg9-wheel-hook: PASS')
else:skip('tmg9-wheel-hook','not selected by --only')
# TMG9 detent D: caps bit 10, the D-carrying TMG2 SET (peer byte 2), D/50 in the menu record, the status pairing; rollback proven against copies of the TMG7/TMG8 decoders.
seen.add('tmg9-detent')
if only is None or 'tmg9-detent' in only:
    ctest('tmg9-detent',[FW/'tests/tmg9_detent_test.c',FW/'src/menu-grid-v2/menu_config.c',FW/'src/diagnostics-v1/diagnostics.c'],FW/'src')
    groups.append('tmg9-detent');print('tmg9-detent: PASS')
else:skip('tmg9-detent','not selected by --only')
if args.firmware_only:
    # Every other manifest group is skipped by name; the run ends before the release ZIP is opened.
    for group in sorted({v['group'] for v in manifest.values() if v['status']=='run'}-FIRMWARE_GROUPS):skip(group,'firmware-only')
    (out/'report.json').write_text(json.dumps({'passed':True,'firmwareOnly':True,'groups':groups,'deviceIO':False,'hardwareValidated':False,'skipped':skipped,'excluded':sum(v['status']=='excluded' for v in manifest.values())},indent=2)+'\n')
    raise SystemExit(0)
seen.add('shared-sources')
if only is None or 'shared-sources' in only:
    pairs=['menu-grid-v2/menu_config.c','menu-grid-v2/menu_config.h',
        'navigation-runtime-v1/nav_map.c','navigation-runtime-v1/nav_map.h','navigation-runtime-v1/nav_text.h',
        'navigation-runtime-v1/nav_runtime.c','navigation-runtime-v1/nav_runtime.h',
        'music-runtime-v1/music.c','music-runtime-v1/music.h',
        'focus-v1/focus.c','focus-v1/focus.h','app-runtime-v1/app.c',
        'global-remote-v1/remote.c','dashboard-v1/card.c','diagnostics-v1/command.c',
        'display-runtime-v1/display_runtime.c','global-remote-v1/lang_flag.c','global-remote-v1/lang_flag.h']
    for name in pairs:
        phone=P/Path(name).name
        if not phone.exists():
            print('shared-sources: skip removed phone copy '+phone.name);continue
        if phone.read_bytes()!=(FW/'src'/name).read_bytes():
            raise RuntimeError('shared source mismatch: '+name)
    for name in ['menu-grid-v2/tile_config.c','menu-grid-v2/tile_config.h','global-remote-v1/lang_store.c','global-remote-v1/lang_store.h','diagnostics-v1/diagnostics.c','diagnostics-v1/diagnostics.h','diagnostics-v1/command.h','diagnostics-v1/knob_calibration.c','diagnostics-v1/knob_calibration.h','lock-v1/lock_codec.c','lock-v1/lock_codec.h']:
        phone=P/Path(name).name
        if not phone.is_file() or phone.read_bytes()!=(FW/'src'/name).read_bytes():
            raise RuntimeError('TMG4 shared source missing/mismatch: '+name)
    groups.append('shared-sources');print('shared-sources: PASS')
else:skip('shared-sources','not selected by --only')

seen.add('pins')
if only is None or 'pins' in only:
    # This release's ZIP against its firmware-pins JSON and its stock base; the gate runs the full generator --check.
    run('pins',['python3','-I',FW/'tools/phone_pins.py','--verify',args.release,'--zip',args.firmware,'--dir',P])
    # The stock package against its own entry in the firmware-pins JSON (every member equal to the base's stock ZIP).
    if stock_label:run('pins-stock-package',['python3','-I',FW/'tools/phone_pins.py','--verify',args.release,'--package',stock_label,'--zip',stock_package,'--dir',P])
    # The generator itself, with this release's ZIP and the tree's ZIP (once when they are the same file); release ZIPs
    # not given here are read from $TURBO_INPUTS.
    zips=[args.firmware]+([args.tree_firmware] if args.tree_firmware and args.tree_firmware.resolve()!=args.firmware.resolve() else [])
    run('pins-generator',['python3','-I',FW/'tests/phone_pins_test.py',*zips])
    groups.append('pins');print('pins: PASS')
else:skip('pins','not selected by --only')

test('host',['HostCompatibilityTests.m'])
test('guard',['ExperimentalOTAGuardTests.m','ExperimentalOTAGuard.m'])
test('language',['tests/TIOLanguageTests.m'])
test('voice-exit',['tests/VoiceExitTests.m','Core.m'],extra=['-fmodules','-Wno-unused-parameter'])
test('stability',['RoadMap.m','nav_runtime.c','tests/StabilityTests.m'])
test('coordinates',['RoadMap.m','nav_runtime.c','tests/CoordinateTests.m'])
test('replay',['RoadMap.m','NativeNavigation.m','nav_runtime.c','tests/RoadMapTests.m'],[P/'tests/maps',out,'v2'])
test('tmg6-navigation',['NativeNavigation.m','nav_runtime.c','tests/TMG6NavigationTests.m'],extra=['-Dcalloc=TNVTestCalloc'])
test('tmg6-route',['NavigationGuidance.m','RoadMap.m','nav_runtime.c','tests/TMG6RouteTests.m'])
test('guidance',['NavigationGuidance.m','tests/NavigationGuidanceTests.m'])
test('labels',['RoadMap.m','NavigationGuidance.m','RoadTiles.m','nav_runtime.c','tests/RoadMapLabelTests.m'],[],['-DTIO_MAPKIT_ENABLED=1'])
test('tiles',['RoadTiles.m','tests/RoadTilesTests.m'])
test('rate',['NativeNavigation.m','nav_runtime.c','tests/PoseRateTests.m'],extra=['-Dcalloc=TNVTestCalloc'])
test('tmg5-navigation',['NativeNavigation.m','nav_runtime.c','NavigationGuidance.m','tests/TMG5NavigationTests.m'],extra=['-Dcalloc=TNVTestCalloc'])
test('tmg5-roads',['RoadMap.m','nav_runtime.c','tests/TMG5RoadFilterTests.m'])
test('session',['NativeNavigationTests.m','NativeNavigation.m','TNVTransport.m','nav_runtime.c','tests/diagnostic_stub.m'])
test('glasses-file',['tests/GlassesFileTransportTests.m','TIOGlassesFileTransport.m','tests/diagnostic_stub.m','tests/fixtures/wp8/LegacyFocusTransport.m','tests/fixtures/wp8/LegacyMusicTransport.m','tests/fixtures/wp8/LegacyTDTransport.m','focus.c','music.c','command.c','diagnostics.c'])
test('menu-layout',['MenuLayoutTests.m','MenuLayout.m','menu_config.c','tile_config.c'])
test('glasses-lock',['tests/GlassesLockTests.m','GlassesLock.m','lock_codec.c'])   # TLK:/TKA: through the shared codec, token exchange, caps bit 11, caps stale or refused while locked (seen glasses), MOTION_ON refused, page model
test('menu-lens',['tests/MenuLensTests.m','MenuLens.m'],extra=['-framework','CoreGraphics'])
test('tile-layout',['tests/TileLayoutTests.m','MenuLayout.m','menu_config.c','tile_config.c'])
if only is None or 'tile-layout' in only:
    run('tile-roundtrip',['python3','-I',P/'tests/tile_roundtrip.py',out/'tile-roundtrip'])
test('apple-ai-core',['AppleAICoreTests.m','AppleAICore.m'])
test('no-network-turn',['tests/NoNetworkTurnTests.m','NoNetworkTurn.m','NoNetworkTurnHost.m','Core.m'],extra=['-framework','Network','-DTIO_NO_NETWORK_TESTING=1'])
test('catalog',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1'])
test('research-catalog-apple',['ResearchCatalogTests.m','ResearchCatalog.m','AppleAICore.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1','-DTIO_APPLE_AI=1'])
test('music-compatibility',['tests/MusicCompatibilityTests.m','MusicBridge.m','TIOGlassesFileTransport.m','music.c','tests/diagnostic_stub.m'])
test('music-clock',['tests/MusicClockTests.m'])
test('music-navigation',['tests/MusicNavigationTests.m','GlassesBench.m','card.c','MusicPlayer.m','MusicBridge.m','NativeNavigationUI.m','NativeNavigation.m','TNVTransport.m','TIOGlassesFileTransport.m','nav_runtime.c','music.c','SpotifyHTTP.m','SpotifyAuth.m','SpotifyAPI.m','SpotifyLyrics.m','SpotifyCover.m','tests/diagnostic_stub.m'],extra=['-I',P/'tests/shims','-DNSHomeDirectory=TIOTestHome','-framework','Security','-framework','CoreGraphics','-framework','ImageIO'])
test('glasses-bench',['tests/GlassesBenchTests.m','GlassesBench.m','card.c'])
seen.add('bench-layout')
if only is None or 'bench-layout' in only:
    ctest('bench-layout',[P/'tests/GlassesBenchLayout_test.c'],FW/'src')   # the bench lyric fixtures under the firmware's own wrapping
    groups.append('bench-layout');print('bench-layout: PASS')
else:skip('bench-layout','not selected by --only')
test('spotify-lyrics',['SpotifyHTTP.m','SpotifyLyrics.m','tests/SpotifyLyricsTests.m'],[P/'tests/fixtures/spotify'])
test('spotify-auth',['SpotifyHTTP.m','SpotifyAuth.m','tests/SpotifyAuthTests.m'],[P/'tests/fixtures/spotify'],['-framework','Security'])
test('spotify-api',['SpotifyHTTP.m','SpotifyAuth.m','SpotifyAPI.m','tests/SpotifyAPITests.m'],[P/'tests/fixtures/spotify'],['-framework','Security'])
test('spotify-cover',['SpotifyCover.m','tests/SpotifyCoverTests.m'],[],['-framework','CoreGraphics','-framework','ImageIO'])
test('language-flag',['tests/LanguageFlagTests.m','LanguageFlag.m','lang_flag.c'])
test('runtime-status',['tests/TDRuntimeTests.m','TDPhoneRun.m','TDPhoneStore.m','TDPhoneReply.m','command.c','diagnostics.c','knob_calibration.c'])
# The old tmg5-native-status run re-ran the frozen TMG5 copy of native_status_host_test.py; with one firmware tree it would repeat tmg4-native-status exactly, so it is dropped.
test('voice-tts',['VoiceTTSTests.m','VoiceTTSText.m'])
with tempfile.TemporaryDirectory(prefix='turbo-navs3-test-') as tmp:
    root=Path(tmp)
    for name,archive in [('stock',release_stock),('candidate',args.firmware),('stock-package',stock_package)]:
        target=root/name;target.mkdir()
        with zipfile.ZipFile(archive) as z:
            for member in z.namelist():
                assert Path(member).name==member
                (target/member).write_bytes(z.read(member))
    test('archive',['ExperimentalOTATests.m','ExperimentalOTA.m'],[args.firmware,stock_package],['-lz'])
    test('directory',['ExperimentalOTADirectoryTests.m','ExperimentalOTA.m'],[root/'candidate',root/'stock'],['-lz'])
    gate=['ExperimentalOTA.m','ExperimentalOTAFlash.m','ExperimentalOTAGuard.m']
    test('flash',['ExperimentalOTAFlashTests.m',*gate,'ExperimentalOTAFeed.m'],[root/'candidate',root/'stock'],['-lz'])
    test('feed',['ExperimentalOTAFeedTests.m',*gate,'ExperimentalOTAFeed.m'],[args.firmware,stock_package],['-lz','-DTIO_OTA_FEED_ARMING_ENABLED=1'])
    test('feed-restart',['tests/OTAFeedRestartTests.m',*gate,'ExperimentalOTAFeed.m'],[],['-lz'])
    test('wizard',['OTAWizardModelTests.m','OTAWizardModel.m',*gate,'ExperimentalOTAFeed.m'],[],['-lz'])
    def adapted_policy(name,file,substitutions):
        # Execute the unchanged phone policy on macOS. Only platform imports
        # and OS-owned providers are substituted; policy/body bytes are kept.
        source=(P/file).read_text()
        for old,new in substitutions.items():
            assert old in source, 'wizard platform seam changed: '+old
            source=source.replace(old,new)
        adapted=out/name
        adapted.write_text('#import "tests/TMG4WizardHost.h"\n'+source)
        return adapted
    flash_seams={
        '#include <TargetConditionals.h>':'#include <TargetConditionals.h>\n#undef TARGET_OS_IPHONE\n#define TARGET_OS_IPHONE 1',
        '#import "DisplayPhoneUI.h"':'BOOL TDPPhonePauseForOTA(void);',
        'NSHomeDirectory()':'TMG4Home()',
        'NSProcessInfo.processInfo.systemUptime':'TMG4Now()',
        'NSBundle.mainBundle.infoDictionary':'TMG4HostInfo()',
        'NSUserDefaults.standardUserDefaults.dictionaryRepresentation':'TMG4Prefs()'}
    seen.add('tmg4-wizard')
    if only is None or 'tmg4-wizard' in only:
        # The full 1.0.21 host (tests/FullHostFixture.h): the main image seam as in the guard groups.
        adapted=adapted_policy('tmg4-wizard-policy.m','ExperimentalOTAFlash.m',{**flash_seams,'TIOHostMainImage()':'TMG4MainImage()'})
        run('tmg4-wizard-build',flags+[P/'tests/TMG4WizardTests.m',P/'OTAWizardModel.m',P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-o',out/'tmg4-wizard'])
        for version in release_versions:
            run('tmg4-wizard-'+version[len('Strix OS '):],[out/'tmg4-wizard',root/'candidate',root,version])
        groups.append('tmg4-wizard');print('tmg4-wizard: PASS')
    else:skip('tmg4-wizard','not selected by --only')
    # The 1.0.21 flash sequence recorded on 2026-11-15 (tests/flash-sequence-1021.json), replayed through the
    # same unchanged guard and gate on the full 1.0.21 host with the slices cut from this release's ZIP:
    # every frame allowed, stage 2, 314 slices and 15,756,690 bytes; then each mutation in its own process
    # (stages 2 and 3 last until the app restarts), each refused.
    seen.add('flash-sequence-1021')
    if only is None or 'flash-sequence-1021' in only:
        adapted=adapted_policy('flash-sequence-1021-policy.m','ExperimentalOTAFlash.m',{**flash_seams,'TIOHostMainImage()':'TMG4MainImage()'})
        run('flash-sequence-1021-build',flags+[P/'tests/FlashSequenceTests.m',P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-o',out/'flash-sequence-1021'])
        for mode in ('replay','no-auth','mode','version','manifest','early-slice','flip','unpinned','past-end','device','expired','second-start'):
            run('flash-sequence-1021-'+mode,[out/'flash-sequence-1021',root/'candidate',root,P/'tests/flash-sequence-1021.json',mode])
            log=(out/('flash-sequence-1021-'+mode+'.log')).read_text()
            want='PASS flash sequence replay: ' if mode=='replay' else 'PASS flash sequence mutation '+mode+': refused'
            if want not in log or (mode=='replay' and 'stage 2 reached, 314 slices, 15756690 bytes' not in log):raise RuntimeError('flash-sequence-1021-'+mode+' did not report PASS')
        # The hook protection on its own refuses authorization: before the transport hook is ready, and in a
        # build without TIO_OTA_FLASH_ENABLED (same sources, that one define left out).
        run('flash-sequence-1021-noflash-build',flags+[P/'tests/FlashSequenceTests.m',P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-o',out/'flash-sequence-1021-noflash'])
        for binary,state in (('flash-sequence-1021','on'),('flash-sequence-1021-noflash','off')):
            run(binary+'-unprotected',[out/binary,root/'candidate',root,P/'tests/flash-sequence-1021.json','unprotected'])
            if 'PASS flash sequence unprotected: authorization refused without the hook protection (flash build '+state+')' not in (out/(binary+'-unprotected.log')).read_text():raise RuntimeError(binary+'-unprotected did not report PASS')
        groups.append('flash-sequence-1021');print('flash-sequence-1021: PASS (replay, 11 mutations, and the hook protection in a flash and a non-flash build)')
    else:skip('flash-sequence-1021','not selected by --only')
    # The two packages of the release (tests/FlashPackagesTests.m) through the same unchanged guard and gate with both
    # real ZIPs: the stock replay of the recorded sequence, cross refusals, sizes, selection changes, a fresh process,
    # and (with a test-only package table in a copy of ExperimentalOTA.m) the per-package version acceptance.
    seen.add('flash-packages')
    if only is None or 'flash-packages' in only:
        if not stock_label:raise RuntimeError('flash-packages: release '+args.release+' has no stock package')
        # The stock slice totals, computed here from the stock ZIP in the recorded file order (not written out by hand).
        fixture=json.loads((P/'tests/flash-sequence-1021.json').read_text());slice_bytes=fixture['sliceBytes']
        with zipfile.ZipFile(stock_package) as z:sizes={i.filename:i.file_size for i in z.infolist()}
        names=[s['name'] for s in fixture['steps'] if s.get('type')==7]
        stock_slices=sum((sizes[n]+slice_bytes-1)//slice_bytes for n in names);stock_bytes=sum(sizes[n] for n in names)
        print('flash-packages: stock slices in the recorded order: %d slices, %d bytes'%(stock_slices,stock_bytes))
        adapted=adapted_policy('flash-packages-policy.m','ExperimentalOTAFlash.m',{**flash_seams,'TIOHostMainImage()':'TMG4MainImage()'})
        run('flash-packages-build',flags+[P/'tests/FlashPackagesTests.m',P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-o',out/'flash-packages'])
        table=out/'flash-packages-ota.m'
        source=(P/'ExperimentalOTA.m').read_text()
        for old,new in {'static NSArray<NSDictionary *> *Packages(void){':'NSArray *TMG4TestPackages(NSArray *);\nstatic NSArray<NSDictionary *> *Packages(void){','packages=TIO_FW_PACKAGES;':'packages=TMG4TestPackages(TIO_FW_PACKAGES);'}.items():
            assert source.count(old)==1,'package table seam changed: '+old
            source=source.replace(old,new)
        table.write_text(source)
        run('flash-packages-version-build',flags+[P/'tests/FlashPackagesTests.m',table,P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-DTIO_TEST_PACKAGE_TABLE=1','-o',out/'flash-packages-version'])
        base=[root/'candidate',root/'stock-package',root,P/'tests/flash-sequence-1021.json']
        for mode in ('fresh','stock-replay','tmg-stock-manifest','tmg-stock-slice','stock-tmg-manifest','stock-tmg-slice','size','select-stage1','select-stage2','select-stage3','index','version'):
            binary='flash-packages-version' if mode=='version' else 'flash-packages'
            run('flash-packages-'+mode,[out/binary,*base,mode]+([str(stock_slices),str(stock_bytes)] if mode=='stock-replay' else []))
            log=(out/('flash-packages-'+mode+'.log')).read_text()
            if 'PASS flash packages '+mode not in log:raise RuntimeError('flash-packages-'+mode+' did not report PASS')
            if mode=='stock-replay' and ' %d slices, %d bytes'%(stock_slices,stock_bytes) not in log:raise RuntimeError('flash-packages-stock-replay: slice totals differ')
        groups.append('flash-packages');print('flash-packages: PASS (stock replay %d slices %d bytes, cross refusals, sizes, selection changes, capture-time index check, fresh process, version per package)'%(stock_slices,stock_bytes))
    else:skip('flash-packages','not selected by --only')
    # The guard groups: the same unchanged flash policy and feed with fake host info. G1: the refusal
    # must not depend on build flags. Each test is built in every flag set below; every build must print
    # the same sweep, and that sweep must equal the group's pinned digest.
    # name: (defines, extra sources, flash build expected on the download-only host)
    phone_sources=[P/'DisplayPhoneTransport.m',P/'DisplayDiagnostics.m',P/'display_client.c',P/'display_carrier.c',P/'display_runtime.c']
    guard_configs={
        'full':(['-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_DIAGNOSTICS=1','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1'],phone_sources,True),
        'flash':(['-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1'],[],True),
        'noflags':([],[],False),
        # Wire log on (tests/WireLogGuardHarness.h runs every guard call through the recorder): same digest required.
        'wire-full':(['-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_DIAGNOSTICS=1','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-DTIO_WIRE_LOG=1'],phone_sources+[P/'WireLog.m'],True),
        'wire-noflags':(['-DTIO_WIRE_LOG=1'],[P/'WireLog.m'],False),
    }
    # The pinned sweep digests. They hash only the allow/refuse verdicts (no host names), and were the
    # 1.0.11 groups' digests when C19 and C20 were checked against them; a change here is a change in
    # what the phone lets through and needs the owner's review. C21 re-pinned full-edge only: its arm
    # record cases are gone, its profile cases check the gate instead of the arm, and the duplicate-key
    # size queries now follow NSJSONSerialization (first value kept); full-guard is unchanged.
    GUARD_SWEEPS={
        'download-only':'3f0768f86139352f3eb36673f9eb043a745b8aec721b45a1236fd21ccf119956',
        'full-guard':'dcfa63fb841521a143e97f22585e91037e3469b6a74ce12f883ac1e6528bf29b',
        'full-edge':'1e2873f03455be22d574a839e9c7fe33a858a2fdeef57d85b11d1a24fd830335',
        'stock-teleprompter':'3015ec9140ef4b2dfc2c0cfd31b789edede310ea38917c9247c6bcca58e968e7',
    }
    # flash_on_for: per flag set, whether the flash path is compiled in on the tested host (default: the download-only host's).
    # host_named: the log must name the 1.0.21 host (the teleprompter test prints no host name).
    def guard_group(name,argv,want,test_file='tests/DownloadOnlyGuardTests.m',extra_seams=None,flash_on_for=None,host_named=True):
        seams={**flash_seams,'TIOHostMainImage()':'TMG4MainImage()',**(extra_seams or {})}
        flash=adapted_policy(name+'-policy.m','ExperimentalOTAFlash.m',seams)
        feed=adapted_policy(name+'-feed.m','ExperimentalOTAFeed.m',{'TIOOTAHostProfile(bundle.infoDictionary)':'TIOOTAHostProfile(TMG4HostInfo())',
            'TIOHostFullImageMatches(TIOHostMainImage(),bundle.infoDictionary)':'TIOHostFullImageMatches(TMG4MainImage(),TMG4HostInfo())'})
        sweeps={}
        for config,(defines,sources,flash_on) in guard_configs.items():
            for flag in ('TIO_OTA_FLASH_ENABLED','TIO_DISPLAY_FLASH','TIO_DISPLAY_PHONE'):
                present=any(d.startswith('-D'+flag+'=') for d in defines)
                if config=='full' and not present or config=='noflags' and present:raise RuntimeError('guard flag set '+config+': '+flag)
            binary=name+'-'+config
            run(binary+'-build',flags+[P/test_file,P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',P/'DownloadOnlySafety.m',flash,feed,*sources,'-lz',*defines,'-o',out/binary])
            run(binary,[out/binary,*argv])
            log=(out/(binary+'.log')).read_text()
            if 'PASS' not in log:raise RuntimeError(binary+' did not report PASS')
            sweeps[config]=re.search(r'sweep=([0-9a-f]{64})',log).group(1)
            if ('flash build on' in log)!=(flash_on if flash_on_for is None else flash_on_for[config]):raise RuntimeError(binary+': unexpected flash build state')
            if ('wirelog harness: ' in log)!=('-DTIO_WIRE_LOG=1' in defines):raise RuntimeError(binary+': wire log harness state does not match the build')
            if host_named and ' 1.0.21 ' not in log:raise RuntimeError(binary+': the log does not name the 1.0.21 host')
        if len(set(sweeps.values()))!=1:raise RuntimeError(name+': refusal differs between flag sets '+repr(sweeps))
        sweep=next(iter(sweeps.values()))
        if sweep!=want:raise RuntimeError(name+': sweep '+sweep[:16]+' differs from the pinned '+want[:16])
        print(name+': same refusal in flag sets '+', '.join(sweeps)+', equal to the pin (sweep '+sweep[:16]+')')
        return sweep
    # Download-only 1.0.21/1 host (C19 onward): the business-9 refusal, flag-independent.
    seen.add('ios1021-download-guard')
    if only is None or 'ios1021-download-guard' in only:
        guard_group('ios1021-download-guard',[],GUARD_SWEEPS['download-only'])
        groups.append('ios1021-download-guard');print('ios1021-download-guard: PASS')
    else:skip('ios1021-download-guard','not selected by --only')
    # D5: the stock teleprompter sendFile allow-list, same unchanged policy and the same flag sets.
    seen.add('stock-teleprompter')
    if only is None or 'stock-teleprompter' in only:
        # R3: the test sets the OTA gate stage through this seam.
        stage_seam={'static NSUInteger GateStage(void){return ':'NSUInteger TMG4StageOverride(void);\nstatic NSUInteger GateStage(void){if(TMG4StageOverride()!=NSUIntegerMax)return TMG4StageOverride();return '}
        guard_group('stock-teleprompter',[],GUARD_SWEEPS['stock-teleprompter'],'tests/StockTeleprompterSendTests.m',stage_seam,host_named=False)
        groups.append('stock-teleprompter');print('stock-teleprompter: PASS')
    else:skip('stock-teleprompter','not selected by --only')
    # Full 1.0.21 host (ios1021, C20 onward): every business-9 frame goes through the one flash gate in every
    # flag set, and at stage 0 its sweep is one pinned digest. With --app1021 the guard test checks the real
    # Runner too. The edge test covers profile marker near misses, raw-JSON size queries, frame, payload and
    # businessId shapes, and a record left by the retired arm step; known gaps print as XFAIL and abort as
    # XPASS once fixed. The authorized gate is run by tmg4-wizard and flash-sequence-1021.
    for name,test_file,real,want in (('ios1021-full-guard','tests/FullHostGuardTests.m',True,'full-guard'),('ios1021-full-edge','tests/FullHostEdgeTests.m',False,'full-edge')):
        seen.add(name)
        if only is None or name in only:
            full_flash={config:'-DTIO_OTA_FLASH_ENABLED=1' in defines for config,(defines,_s,_f) in guard_configs.items()}
            guard_group(name,[args.app1021/'Runner',args.app1021/'Info.plist'] if real and args.app1021 else [],GUARD_SWEEPS[want],test_file,None,full_flash)
            groups.append(name);print(name+': PASS')
        else:skip(name,'not selected by --only')
    # The stock 1.0.21/1 app: the same pins as package.mjs (ios1021-download and ios1021 share them), the
    # Runner UUID, the route records at the 1.0.21 offsets, and the download-only guard on the real Runner.
    seen.add('ios1021-host')
    if (only is None or 'ios1021-host' in only) and args.app1021:
        import hashlib, plistlib
        app=args.app1021
        info=plistlib.loads((app/'Info.plist').read_bytes())
        assert (info.get('CFBundleIdentifier'),info.get('CFBundleShortVersionString'),str(info.get('CFBundleVersion')),info.get('CFBundleExecutable'))==('com.rayneo.venus.pub','1.0.21','1','Runner'),'1.0.21 Info.plist identity'
        assert not [k for k in info if k.startswith('TIO')] and 'UISupportedDevices' not in info,'stock 1.0.21 Info.plist expected'
        pins={'Runner':'9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2',
            'Frameworks/App.framework/App':'0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273',
            'Frameworks/RayneoNet.framework/RayneoNet':'d8befe5f3144d21e4725bc27791c55954a210ee11e5738c197dbb1c18350bfa3',
            'Frameworks/Flutter.framework/Flutter':'4c16499adee04bf904f7795f98e983b9fb593fb93b607ca7941761c2949f0e9a'}
        package=(P/'package.mjs').read_text()
        for rel,want in pins.items():
            got=hashlib.sha256((app/rel).read_bytes()).hexdigest()
            if got!=want:raise RuntimeError('1.0.21 pin mismatch: '+rel)
            assert want in package,'package.mjs 1.0.21 pin missing: '+rel
        uuid=subprocess.run(['xcrun','dwarfdump','--uuid',app/'Runner'],capture_output=True,text=True,check=True).stdout.split()
        assert uuid[1]=='74DA0780-DCF0-384F-9E84-1AC12F56CDF5' and uuid[2]=='(arm64)','1.0.21 Runner UUID'
        image=(app/'Frameworks/App.framework/App').read_bytes()
        for route,offset in [(b'/xrlauncherapi/v1/signApi/gray/upgrade',46796656),(b'/xrlauncherhwapi/v1/signApi/gray/upgrade',37435136)]:
            if image.count(route)!=1 or image.find(route)!=offset:raise RuntimeError('1.0.21 route record moved: '+route.decode())
        header=(P/'HostCompatibility.h').read_text();compat=(P/'host-compatibility.mjs').read_text()
        assert '"1.0.21"]&&[build isEqual:@"1"])return @"74DA0780-DCF0-384F-9E84-1AC12F56CDF5"' in header
        assert "version:'1.0.21',build:'1',uuid:'74da0780dcf0384f9e841ac12f56cdf5'" in compat
        guard_group('ios1021-host',[app/'Runner',app/'Info.plist'],GUARD_SWEEPS['download-only'])
        groups.append('ios1021-host');print('ios1021-host: PASS')
    else:skip('ios1021-host','needs --app1021' if not args.app1021 else 'not selected by --only')

for name,files in [('camera-link',['CameraLink.m','CameraProfiles.c']),('camera-image',['CameraImage.m']),('camera-capture',['CameraCapture.m'])]:
    main={'camera-link':'CameraLinkTests.m','camera-image':'CameraImageTests.m','camera-capture':'CameraCaptureTests.m'}[name]
    test(name,['camera-v1/'+main,'camera-v1/camera.c',*['camera-v1/'+f for f in files]],[],['-framework','CoreGraphics','-framework','AVFoundation'])
# WP0 step 6: previously orphaned tests.
test('ota-guard',['ExperimentalOTAGuardTests.m', 'ExperimentalOTAGuard.m'],argv=[],extra=['-fmodules'])
test('phone-ota-gate',['PhoneOTAGateTests.m', 'ExperimentalOTA.m', 'ExperimentalOTAFlash.m', 'ExperimentalOTAGuard.m', 'ExperimentalOTAFeed.m', 'DisplayPhoneTransport.m', 'DisplayDiagnostics.m', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-lz', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_DISPLAY_FLASH=1', '-DTIO_OTA_FLASH_ENABLED=1', '-DTIO_OTA_FEED_ARMING_ENABLED=1'])
test('image-upload-transport',['ImageUploadTransportTests.m', 'ImageUploadTransport.m', 'ImageUpload.m', 'ExperimentalOTA.m', 'ExperimentalOTAFlash.m', 'ExperimentalOTAGuard.m', 'ExperimentalOTAFeed.m'],argv=[],extra=['-fmodules', '-lz', '-DTIO_IMAGE_RX_LAB=1', '-DTIO_IMAGE_RX_WIDE=1'])
# Full 1.0.21 host: patch-route.mjs (profile ios1021) on the stock App must give the pinned output, an
# input one byte different must be refused before anything is written, and OTAHost.h must accept the
# output only for ios1021, at the 1.0.21 offsets.
seen.add('ota-host-1021')
if (only is None or 'ota-host-1021' in only) and args.app1021:
    import hashlib
    route_out=out/'ota-host-1021-route'
    shutil.rmtree(route_out,ignore_errors=True)
    stock_app=args.app1021/'Frameworks/App.framework/App'
    run('ota-host-1021-patch',['node',P/'patch-route.mjs',stock_app,route_out,'ios1021'])
    if hashlib.sha256((route_out/'App').read_bytes()).hexdigest()!='cd8be91e82bdbc1c98b5dda4fa0d358b91a2187ea4571200760fac0c53cb7852':raise RuntimeError('1.0.21 route output does not match its pin')
    report=json.loads((route_out/'report.json').read_text())
    assert report['profile']=='ios1021' and report['host']=='1.0.21' and [c['offset'] for c in report['changes']]==[46796656,37435136] and report['deviceIO'] is False
    # One byte different (far from the two records): the input pin refuses it and no output folder appears.
    near=out/'ota-host-1021-near-App';data=bytearray(stock_app.read_bytes());data[4096]^=1;near.write_bytes(bytes(data))
    refused_out=out/'ota-host-1021-near-route';shutil.rmtree(refused_out,ignore_errors=True)
    r=subprocess.run(['node',str(P/'patch-route.mjs'),str(near),str(refused_out),'ios1021'],capture_output=True,text=True)
    (out/'ota-host-1021-near.log').write_text(r.stdout+r.stderr)
    if r.returncode==0 or 'Wrong host image: requires pinned 1.0.21/1' not in r.stderr or refused_out.exists():raise RuntimeError('patch-route.mjs ios1021 accepted an input one byte off the pin')
    near.unlink()
    test('ota-host-1021',['OTAHost1021Tests.m'],[stock_app,route_out/'App'])
else:
    skip('ota-host-1021','needs --app1021' if not args.app1021 else 'not selected by --only')
# Every host method the addon hooks or calls, with its exact type encoding, in each stock host given.
seen.add('host-selectors')
selector_apps=[a for a in (args.app1021,) if a]
if (only is None or 'host-selectors' in only) and selector_apps:
    run('host-selectors',['python3','-I',P/'tests/host_selectors.py',P,*selector_apps])
    groups.append('host-selectors');print('host-selectors: PASS')
else:skip('host-selectors','needs --app1021' if not selector_apps else 'not selected by --only')

# WP0 step 7: previously orphaned tests.
test('core',['Tests.m', 'Core.m'],argv=[],extra=['-fmodules', '-Wno-unused-parameter'])
test('knowledge-tool-flow',['KnowledgeToolFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('todo-tool-flow',['TodoToolFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('web-search-flow',['WebSearchFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('web-search',['WebSearchTests.m', 'WebSearch.m', 'Core.m'],argv=[],extra=['-fmodules'])
test('research-catalog',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1'])
# A wire log build: the recorder row also shows on the download-only host.
test('research-catalog-wire',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1','-DTIO_WIRE_LOG=1'])
test('todo-protocol',['TodoProtocolTests.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules'])
restart_dir=out/'protocol-restart-dir'
if only is None or 'protocol-restart' in only:
    import shutil
    shutil.rmtree(restart_dir,ignore_errors=True);restart_dir.mkdir()
test('protocol-restart',['ProtocolRestartTests.m', 'ProtocolContext.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules', '-DNSHomeDirectory=TIOTestHome'],runs=[['write',restart_dir],['read',restart_dir]])
test('recording-exports',['RecordingExportsTests.m', 'RecordingExports.m'],argv=[],extra=['-fmodules'])
test('firmware-export',['tests/FirmwareExportTests.m','FirmwareExport.m'],argv=[args.firmware],extra=['-fmodules','-lz'])
test('download-only-safety',['tests/DownloadOnlySafetyTests.m','DownloadOnlySafety.m'],argv=[],extra=['-fmodules'])
test('recording-text',['RecordingTextTests.m', 'RecordingText.m'],argv=[],extra=['-fmodules'])
test('alwayson-audio',['AlwaysOnAudioTests.m', 'AlwaysOnAudioFiles.m', 'AlwaysOnOgg.m'],argv=[],extra=['-fmodules'])
test('alwayson-ogg',['AlwaysOnOggTests.m', 'AlwaysOnOgg.m'],argv=[],extra=['-fmodules'])
# Clench Lab model (TIO_IMAGE_RX_LAB). Also writes one complete synthetic session under build/tests/clench-sample/
# for a separate run of the offline session validator; this group does not import or run that validator.
clench_sample=out/'clench-sample'
if only is None or 'clench-lab' in only:
    import shutil
    shutil.rmtree(clench_sample,ignore_errors=True)
test('clench-lab',['ClenchLabTests.m','ClenchLab.m','A2UIProtocol.m','AlwaysOnAudioFiles.m','AlwaysOnOgg.m'],argv=[clench_sample],extra=['-fmodules','-lz','-DTIO_IMAGE_RX_LAB=1','-DNSHomeDirectory=TIOTestHome'])
test('subtitle-hud',['SubtitleHUDTests.m', 'SubtitleHUDCore.m'],argv=[],extra=['-fmodules'])
test('hometab',['HomeTabLayoutTests.m', 'HomeTabLayout.m'],argv=[],extra=['-fmodules'])
test('tio-design',['TIODesignTests.m'],argv=[ROOT/'docs/design-system/tokens.json'])
seen.add('tio-design-literals')
if only is None or 'tio-design-literals' in only:
    run('tio-design-literals',['python3','-I',P/'tests/design_literals.py',P])
    groups.append('tio-design-literals');print('tio-design-literals: PASS')
seen.add('tio-design-swift')
if only is None or 'tio-design-swift' in only:
    run('tio-design-swift',['python3','-I',P/'tests/tio_design_swift.py',ROOT/'docs/design-system/tokens.json',P/'local-translation/src/TIODesign.swift'])
    groups.append('tio-design-swift');print('tio-design-swift: PASS')
test('a2ui-protocol',['A2UIProtocolTests.m', 'A2UIProtocol.m'],argv=[],extra=['-fmodules'])
test('dashboard-card',['DashboardCardTests.m', 'DashboardCard.m', 'A2UIProtocol.m', 'card.c'],argv=[],extra=['-fmodules'])
test('glasses-log-contract',['GlassesLogContractTests.m', 'GlassesLogContract.m', 'A2UIProtocol.m'],argv=[],extra=['-fmodules'])
test('glasses-log-gate',['GlassesLogGateTests.m', 'GlassesLogGate.m', 'GlassesLogContract.m', 'A2UIProtocol.m'],argv=[],extra=['-fmodules'])
test('syslog-pull',['SyslogPullTests.m', 'SyslogPull.m'],argv=[],extra=['-fmodules'])
test('wire-log',['WireLogTests.m', 'WireLog.m'],argv=[],extra=['-fmodules'])
test('image-upload',['ImageUploadTests.m', 'ImageUpload.m'],argv=[],extra=['-fmodules', '-DTIO_IMAGE_RX_LAB=1', '-DTIO_IMAGE_RX_WIDE=1', '-framework', 'ImageIO', '-framework', 'CoreGraphics'])

# WP0 step 8: previously orphaned tests.
test('display-delta',['DisplayDeltaTests.m', 'DisplayDelta.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-diagnostics',['DisplayDiagnosticsTests.m', 'DisplayDiagnostics.m', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-navigation',['DisplayNavigationTests.m', 'DisplayNavigation.m', 'DisplayPhoneSession.m', 'DisplayReplyObserver.m', 'DisplayDiagnostics.m', 'display_carrier.c', 'display_client.c', 'display_runtime.c', 'DisplayDelta.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-reply-observer',['DisplayReplyObserverTests.m', 'DisplayReplyObserver.m', 'display_carrier.c', 'display_client.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-phone',['DisplayPhoneTests.m', 'DisplayPhoneSession.m', 'DisplayPhoneTransport.m', 'DisplayReplyObserver.m', 'DisplayDiagnostics.m', 'DisplayDelta.c', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-task-binding',['DisplayTaskBindingTests.m', 'DisplayPhoneSession.m', 'DisplayPhoneTransport.m', 'DisplayReplyObserver.m', 'DisplayDiagnostics.m', 'DisplayDelta.c', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-delta-session',['DisplayDeltaSessionTests.m', 'DisplayPhoneSession.m', 'DisplayPhoneTransport.m', 'DisplayReplyObserver.m', 'DisplayDiagnostics.m', 'DisplayDelta.c', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])
test('display-frame-pacing',['DisplayFramePacingTests.m', 'DisplayPhoneSession.m', 'DisplayPhoneTransport.m', 'DisplayReplyObserver.m', 'DisplayDiagnostics.m', 'DisplayDelta.c', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_NATIVE_NAV=1', '-DTIO_IMAGE_RX_WIDE=1'])

# UIKit Catalyst attempts failed on baseline; see manifest exclusion reasons.

if only is None:
    missing={v['group'] for v in manifest.values() if v['status']=='run'}-set(groups)-{n for n,_ in skipped}
    if missing:raise SystemExit('manifest groups not executed: '+str(sorted(missing)))
elif only-seen-{'apple-ai-swift'}:
    raise SystemExit('unknown groups: '+str(sorted(only-seen)))
seen.add('apple-ai-swift')
if only is None or 'apple-ai-swift' in only:
    subprocess.run(['python3',str(P/'apple-ai/test.py')],check=True);groups.append('apple-ai-swift');print('apple-ai-swift: PASS')
(out/'report.json').write_text(json.dumps({'passed':True,'groups':groups,'deviceIO':False,'hardwareValidated':False,'skipped':skipped,'excluded':sum(v['status']=='excluded' for v in manifest.values())},indent=2)+'\n')
