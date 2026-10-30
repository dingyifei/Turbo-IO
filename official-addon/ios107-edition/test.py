"""Portable macOS offline tests. No phone, network, signing or flashing."""
from pathlib import Path
import argparse, fnmatch, json, os, subprocess, tempfile, zipfile
P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--firmware',type=Path,required=True)
parser.add_argument('--app107',type=Path)
parser.add_argument('--patched-app',type=Path)
parser.add_argument('--only',help='comma-separated test groups')
args=parser.parse_args()
only=set(args.only.split(',')) if args.only else None
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

ROOT=P.parents[1];FW2=ROOT/'firmware-research/strix-1.0.5.5-tmg2'
FW4=ROOT/'firmware-research/strix-1.0.5.5-tmg7'
FW8=ROOT/'firmware-research/strix-1.0.5.5-tmg8'  # TMG8 tests that do not exist in FW7; the whole group moves to FW8 at the test-retarget step
FW=FW4
stock=ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip'
subprocess.run(['python3',FW/'build.py','--stock',stock,'--audit',args.firmware],check=True)
out=P/'build/tests';out.mkdir(parents=True,exist_ok=True)
def run(name,cmd,env=None):
    r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=180,env=env)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError(name+' failed: '+r.stdout+r.stderr)
flags=['xcrun','clang','-O1','-g','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types','-fsanitize=address,undefined','-framework','Foundation','-I',P]
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
def ctest(name,files,inc):
    run(name+'-build',['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra',
        '-fsanitize=address,undefined','-I',inc,*files,'-o',out/name])
    run(name,[out/name])
    if 'PASS' not in (out/(name+'.log')).read_text():
        raise RuntimeError(name+' did not report PASS')
seen.add('tmg4-host')
if only is None or 'tmg4-host' in only:
    run('tmg7-host',['python3','-I',FW4/'tests/tmg7_host_test.py','--out',out/'tmg7-host'])
    ctest('tmg6-passing',[FW4/'tests/tmg6_passing_test.c',FW4/'src/navigation-runtime-v1/nav_runtime.c'],FW4/'src')
    ctest('tmg4-diagnostics',[FW4/'src/diagnostics-v1/diagnostics_test.c',FW4/'src/diagnostics-v1/diagnostics.c'],FW4/'src/diagnostics-v1')
    ctest('tmg8-caps',[FW8/'tests/tmg8_caps_test.c',FW8/'src/menu-grid-v2/menu_config.c',FW8/'src/diagnostics-v1/diagnostics.c'],FW8/'src')
    ctest('tmg8-wheel',[FW8/'tests/tmg8_wheel_test.c'],FW8/'src')
    ctest('tmg8-music-input',[FW8/'src/music-runtime-v1/music_input_test.c'],FW8/'src/music-runtime-v1')
    run('tmg8-icons',['python3','-I',FW8/'tests/tmg8_icons_test.py'])
    ctest('tmg8-tile-state',[FW8/'tests/tmg8_tile_state_test.c',FW8/'src/common-v1/tio_text.c'],FW8/'src')
    ctest('tmg8-nav-title',[FW8/'tests/tmg8_nav_title_test.c',FW8/'src/common-v1/tio_text.c'],FW8/'src')
    ctest('tmg4-command',[FW4/'src/diagnostics-v1/command_test.c',FW4/'src/diagnostics-v1/command.c',FW4/'src/diagnostics-v1/diagnostics.c'],FW4/'src/diagnostics-v1')
    ctest('tmg4-status',[FW4/'tests/runtime_status_test.c',FW4/'src/diagnostics-v1/diagnostics.c',FW4/'src/diagnostics-v1/command.c'],FW4/'src')
    ctest('tmg4-timer-wrap',[FW4/'tests/timer_wrap_test.c',FW4/'src/menu-grid-v2/tile_config.c',FW4/'src/menu-grid-v2/menu_config.c'],FW4/'src')
    ctest('tmg4-knob',[FW4/'tests/knob_test.c',FW4/'src/diagnostics-v1/knob_calibration.c'],FW4/'src')
    run('tmg4-identity',['python3','-I',FW4/'tests/identity_test.py'])
    ctest('tmg4-tile-config',[FW4/'tests/tile_config_test.c',FW4/'src/menu-grid-v2/tile_config.c'],FW4/'src')
    ctest('tmg4-menu-tiles',[FW4/'tests/menu_tiles_test.c'],FW4/'src')
    ctest('tmg4-menu-lang',[FW4/'tests/menu_lang_test.c',FW4/'src/global-remote-v1/lang_flag.c',FW4/'src/global-remote-v1/lang_store.c'],FW4/'src')
    ctest('tmg4-lang-store',[FW4/'tests/lang_store_test.c',FW4/'src/global-remote-v1/lang_store.c'],FW4/'src')
    ctest('tmg4-text',[FW4/'tests/tio_text_test.c',FW4/'src/common-v1/tio_text.c'],FW4/'src')
    ctest('tmg4-grid',[FW4/'tests/focus_grid_test.c',FW4/'src/focus-v1/focus_menu.c',FW4/'src/common-v1/tio_text.c',FW4/'src/menu-grid-v2/tile_config.c'],FW4/'src')
    ctest('tmg5-music',[FW4/'src/music-runtime-v1/music_test.c',FW4/'src/music-runtime-v1/music.c'],FW4/'src/music-runtime-v1')
    ctest('tmg5-noncardinal',[FW4/'tests/noncardinal_smoothing_test.c'],FW4/'src')
    ctest('tmg5-smoothing',[FW4/'tests/smoothing_test.c',FW4/'src/navigation-runtime-v1/nav_runtime.c'],FW4/'src')
    ctest('tmg4-prediction',[FW4/'tests/pose_prediction_test.c',FW4/'src/navigation-runtime-v1/nav_runtime.c'],FW4/'src')
    run('tmg4-native-ui',['python3','-I',FW4/'tests/native_ui_host_test.py','--out',out/'tmg4-native-ui-host'])
    run('tmg4-native-status',['python3','-I',FW4/'tests/native_status_host_test.py','--out',out/'tmg4-native-status-host'])
    run('tmg4-native',['python3','-I',FW4/'tests/native_host_test.py','--out',out/'tmg4-native-host'])
    run('tmg4-stock-abi',['python3','-I',FW4/'tests/stock_abi_test.py','--stock',stock])
    run('tmg4-kept',['python3','-I',FW4/'tools/check_kept.py',FW2,FW4])
    run('tmg4-cjk',['python3','-I',FW4/'tools/check_cjk.py',FW4])
    groups.append('tmg4-host');print('tmg4-host: PASS')
else:skip('tmg4-host','not selected by --only')
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
        if phone.read_bytes()!=(FW4/'src'/name).read_bytes():
            raise RuntimeError('shared source mismatch: '+name)
    for name in ['menu-grid-v2/tile_config.c','menu-grid-v2/tile_config.h','global-remote-v1/lang_store.c','global-remote-v1/lang_store.h','diagnostics-v1/diagnostics.c','diagnostics-v1/diagnostics.h','diagnostics-v1/command.h','diagnostics-v1/knob_calibration.c','diagnostics-v1/knob_calibration.h']:
        phone=P/Path(name).name
        if not phone.is_file() or phone.read_bytes()!=(FW4/'src'/name).read_bytes():
            raise RuntimeError('TMG4 shared source missing/mismatch: '+name)
    groups.append('shared-sources');print('shared-sources: PASS')
else:skip('shared-sources','not selected by --only')

seen.add('pins')
if only is None or 'pins' in only:
    run('pins',['python3','-I',FW4/'tools/phone_pins.py','--zip',args.firmware,'--check',P])
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
test('tile-layout',['tests/TileLayoutTests.m','MenuLayout.m','menu_config.c','tile_config.c'])
if only is None or 'tile-layout' in only:
    run('tile-roundtrip',['python3','-I',P/'tests/tile_roundtrip.py',out/'tile-roundtrip'])
test('apple-ai-core',['AppleAICoreTests.m','AppleAICore.m'])
test('no-network-turn',['tests/NoNetworkTurnTests.m','NoNetworkTurn.m','NoNetworkTurnHost.m','Core.m'],extra=['-framework','Network','-DTIO_NO_NETWORK_TESTING=1'])
test('catalog',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1'])
test('research-catalog-apple',['ResearchCatalogTests.m','ResearchCatalog.m','AppleAICore.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1','-DTIO_APPLE_AI=1'])
test('music-compatibility',['tests/MusicCompatibilityTests.m','MusicBridge.m','TIOGlassesFileTransport.m','music.c','tests/diagnostic_stub.m'])
test('music-clock',['tests/MusicClockTests.m'])
test('spotify-lyrics',['SpotifyHTTP.m','SpotifyLyrics.m','tests/SpotifyLyricsTests.m'],[P/'tests/fixtures/spotify'])
test('spotify-auth',['SpotifyHTTP.m','SpotifyAuth.m','tests/SpotifyAuthTests.m'],[P/'tests/fixtures/spotify'],['-framework','Security'])
test('spotify-api',['SpotifyHTTP.m','SpotifyAuth.m','SpotifyAPI.m','tests/SpotifyAPITests.m'],[P/'tests/fixtures/spotify'],['-framework','Security'])
test('spotify-cover',['SpotifyCover.m','tests/SpotifyCoverTests.m'],[],['-framework','CoreGraphics','-framework','ImageIO'])
test('language-flag',['tests/LanguageFlagTests.m','LanguageFlag.m','lang_flag.c'])
test('runtime-status',['tests/TDRuntimeTests.m','TDPhoneRun.m','TDPhoneStore.m','TDPhoneReply.m','command.c','diagnostics.c','knob_calibration.c'])
if only is None or 'runtime-status' in only:
    run('tmg5-native-status',['python3','-I',ROOT/'firmware-research/strix-1.0.5.5-tmg5/tests/native_status_host_test.py','--out',out/'tmg5-native-status'])
test('voice-tts',['VoiceTTSTests.m','VoiceTTSText.m'])
with tempfile.TemporaryDirectory(prefix='turbo-navs3-test-') as tmp:
    root=Path(tmp)
    for name,archive in [('stock',stock),('candidate',args.firmware)]:
        target=root/name;target.mkdir()
        with zipfile.ZipFile(archive) as z:
            for member in z.namelist():
                assert Path(member).name==member
                (target/member).write_bytes(z.read(member))
    test('archive',['ExperimentalOTATests.m','ExperimentalOTA.m'],[args.firmware,stock],['-lz'])
    test('directory',['ExperimentalOTADirectoryTests.m','ExperimentalOTA.m'],[root/'candidate',root/'stock'],['-lz'])
    gate=['ExperimentalOTA.m','ExperimentalOTAFlash.m','ExperimentalOTAGuard.m']
    test('flash',['ExperimentalOTAFlashTests.m',*gate,'ExperimentalOTAFeed.m'],[root/'candidate',root/'stock'],['-lz'])
    test('feed',['ExperimentalOTAFeedTests.m',*gate,'ExperimentalOTAFeed.m'],[args.firmware],['-lz','-DTIO_OTA_FEED_ARMING_ENABLED=1'])
    test('feed-restart',['tests/OTAFeedRestartTests.m',*gate,'ExperimentalOTAFeed.m'],[],['-lz'])
    test('wizard',['OTAWizardModelTests.m','OTAWizardModel.m',*gate,'ExperimentalOTAFeed.m'],[],['-lz'])
    seen.add('tmg4-wizard')
    if only is None or 'tmg4-wizard' in only:
        # Execute the unchanged phone policy on macOS. Only platform imports
        # and OS-owned providers are substituted; policy/body bytes are kept.
        source=(P/'ExperimentalOTAFlash.m').read_text()
        substitutions={
            '#include <TargetConditionals.h>':'#include <TargetConditionals.h>\n#undef TARGET_OS_IPHONE\n#define TARGET_OS_IPHONE 1',
            '#import "DisplayPhoneUI.h"':'BOOL TDPPhonePauseForOTA(void);',
            'NSHomeDirectory()':'TMG4Home()',
            'NSProcessInfo.processInfo.systemUptime':'TMG4Now()',
            'NSBundle.mainBundle.infoDictionary':'TMG4HostInfo()',
            'NSUserDefaults.standardUserDefaults.dictionaryRepresentation':'TMG4Prefs()'}
        for old,new in substitutions.items():
            assert old in source, 'wizard platform seam changed: '+old
            source=source.replace(old,new)
        adapted=out/'tmg4-wizard-policy.m'
        adapted.write_text('#import "tests/TMG4WizardHost.h"\n'+source)
        run('tmg4-wizard-build',flags+[P/'tests/TMG4WizardTests.m',P/'OTAWizardModel.m',P/'ExperimentalOTA.m',P/'ExperimentalOTAGuard.m',adapted,'-lz','-DTIO_DISPLAY_FLASH=1','-DTIO_OTA_FLASH_ENABLED=1','-o',out/'tmg4-wizard'])
        for version in ('1.0.4.12','1.0.5.5'):
            run('tmg4-wizard-'+version,[out/'tmg4-wizard',root/'candidate',root,'Strix OS '+version])
        groups.append('tmg4-wizard');print('tmg4-wizard: PASS')
    else:skip('tmg4-wizard','not selected by --only')

for name,files in [('camera-link',['CameraLink.m','CameraProfiles.c']),('camera-image',['CameraImage.m']),('camera-capture',['CameraCapture.m'])]:
    main={'camera-link':'CameraLinkTests.m','camera-image':'CameraImageTests.m','camera-capture':'CameraCaptureTests.m'}[name]
    test(name,['camera-v1/'+main,'camera-v1/camera.c',*['camera-v1/'+f for f in files]],[],['-framework','CoreGraphics','-framework','AVFoundation'])
# WP0 step 6: previously orphaned tests.
test('ota-guard',['ExperimentalOTAGuardTests.m', 'ExperimentalOTAGuard.m'],argv=[],extra=['-fmodules'])
test('phone-ota-gate',['PhoneOTAGateTests.m', 'ExperimentalOTA.m', 'ExperimentalOTAFlash.m', 'ExperimentalOTAGuard.m', 'ExperimentalOTAFeed.m', 'DisplayPhoneTransport.m', 'DisplayDiagnostics.m', 'display_client.c', 'display_carrier.c', 'display_runtime.c'],argv=[],extra=['-fmodules', '-lz', '-DTIO_DISPLAY_PHONE=1', '-DTIO_DISPLAY_DIAGNOSTICS=1', '-DTIO_DISPLAY_FLASH=1', '-DTIO_OTA_FLASH_ENABLED=1', '-DTIO_OTA_FEED_ARMING_ENABLED=1'])
test('image-upload-transport',['ImageUploadTransportTests.m', 'ImageUploadTransport.m', 'ImageUpload.m', 'ExperimentalOTA.m', 'ExperimentalOTAFlash.m', 'ExperimentalOTAGuard.m', 'ExperimentalOTAFeed.m'],argv=[],extra=['-fmodules', '-lz', '-DTIO_IMAGE_RX_LAB=1', '-DTIO_IMAGE_RX_WIDE=1'])
if args.app107 and args.patched_app:
    test('ota-host',['OTAHostTests.m'],[args.app107/'Frameworks/App.framework/App',args.patched_app/'Frameworks/App.framework/App'])
else:
    skip('ota-host','needs --app107/--patched-app')

# WP0 step 7: previously orphaned tests.
test('core',['Tests.m', 'Core.m'],argv=[],extra=['-fmodules', '-Wno-unused-parameter'])
test('knowledge-tool-flow',['KnowledgeToolFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('todo-tool-flow',['TodoToolFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('web-search-flow',['WebSearchFlowTests.m', 'Core.m', 'WebSearch.m'],argv=[],extra=['-fmodules'])
test('web-search',['WebSearchTests.m', 'WebSearch.m', 'Core.m'],argv=[],extra=['-fmodules'])
test('research-catalog',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-framework','AppKit','-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1'])
test('todo-protocol',['TodoProtocolTests.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules'])
restart_dir=out/'protocol-restart-dir'
if only is None or 'protocol-restart' in only:
    import shutil
    shutil.rmtree(restart_dir,ignore_errors=True);restart_dir.mkdir()
test('protocol-restart',['ProtocolRestartTests.m', 'ProtocolContext.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules', '-DNSHomeDirectory=TIOTestHome'],runs=[['write',restart_dir],['read',restart_dir]])
test('recording-exports',['RecordingExportsTests.m', 'RecordingExports.m'],argv=[],extra=['-fmodules'])
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
