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

ROOT=P.parents[1];FW=ROOT/'firmware-research/strix-1.0.5.5-tmg2'
stock=ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip'
subprocess.run(['python3',FW/'build.py','--stock',stock,'--audit',args.firmware],check=True)
out=P/'build/tests';out.mkdir(parents=True,exist_ok=True)
def run(name,cmd,env=None):
    r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=180,env=env)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError(name+' failed: '+r.stdout+r.stderr)
flags=['xcrun','clang','-O1','-g','-fobjc-arc','-fblocks','-Wno-incompatible-pointer-types','-fsanitize=address,undefined','-framework','Foundation','-I',P]
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
test('host',['HostCompatibilityTests.m'])
test('stability',['RoadMap.m','nav_runtime.c','tests/StabilityTests.m'])
test('coordinates',['RoadMap.m','nav_runtime.c','tests/CoordinateTests.m'])
test('replay',['RoadMap.m','NativeNavigation.m','nav_runtime.c','tests/RoadMapTests.m'],[P/'tests/maps',out,'v2'])
test('guidance',['NavigationGuidance.m','tests/NavigationGuidanceTests.m'])
test('labels',['RoadMap.m','NavigationGuidance.m','RoadTiles.m','nav_runtime.c','tests/RoadMapLabelTests.m'],[],['-DTIO_MAPKIT_ENABLED=1'])
test('tiles',['RoadTiles.m','tests/RoadTilesTests.m'])
test('rate',['NativeNavigation.m','nav_runtime.c','tests/PoseRateTests.m'])
test('session',['NativeNavigationTests.m','NativeNavigation.m','TNVTransport.m','nav_runtime.c','tests/diagnostic_stub.m'])
test('menu-layout',['MenuLayoutTests.m','MenuLayout.m','menu_config.c'])
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
test('research-catalog',['ResearchCatalogTests.m','ResearchCatalog.m'],[],['-DTIO_MAPKIT_ENABLED=1','-DTIO_IMAGE_RX_LAB=1','-DTIO_DISPLAY_PHONE=1','-DTIO_DISPLAY_FLASH=1'])
test('todo-protocol',['TodoProtocolTests.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules'])
restart_dir=out/'protocol-restart-dir'
if only is None or 'protocol-restart' in only:
    import shutil
    shutil.rmtree(restart_dir,ignore_errors=True);restart_dir.mkdir()
test('protocol-restart',['ProtocolRestartTests.m', 'ProtocolContext.m', 'NewsTeleprompter.m', 'TodoProtocol.m'],argv=[],extra=['-fmodules', '-DNSHomeDirectory=TIOTestHome'],runs=[['write',restart_dir],['read',restart_dir]])
test('recording-exports',['RecordingExportsTests.m', 'RecordingExports.m'],argv=[],extra=['-fmodules'])
test('recording-text',['RecordingTextTests.m', 'RecordingText.m'],argv=[],extra=['-fmodules'])
test('alwayson-audio',['AlwaysOnAudioTests.m', 'AlwaysOnAudioFiles.m', 'AlwaysOnOgg.m'],argv=[],extra=['-fmodules'])
test('alwayson-ogg',['AlwaysOnOggTests.m', 'AlwaysOnOgg.m'],argv=[],extra=['-fmodules'])
test('subtitle-hud',['SubtitleHUDTests.m', 'SubtitleHUDCore.m'],argv=[],extra=['-fmodules'])
test('hometab',['HomeTabLayoutTests.m', 'HomeTabLayout.m'],argv=[],extra=['-fmodules'])
test('navigation-modes',['NavigationModesTests.m', 'NavigationModes.m'],argv=[],extra=['-fmodules'])
test('navigation-core',['NavigationCoreTests.m', 'A2UIProtocol.m', 'NavigationCore.m'],argv=[],extra=['-fmodules', '-Wno-unused-parameter'])
test('navigation-subtitle-hud',['NavigationSubtitleHUDTests.m', 'A2UIProtocol.m', 'NavigationCore.m', 'SubtitleHUDCore.m', 'NavigationSubtitleHUD.m'],argv=[],extra=['-fmodules'])
test('navigation-places',['NavigationPlacesTests.m', 'A2UIProtocol.m', 'NavigationCore.m', 'NavigationPlaces.m'],argv=[],extra=['-fmodules'])
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
elif only-seen:
    raise SystemExit('unknown groups: '+str(sorted(only-seen)))
(out/'report.json').write_text(json.dumps({'passed':True,'groups':groups,'deviceIO':False,'hardwareValidated':False,'skipped':skipped,'excluded':sum(v['status']=='excluded' for v in manifest.values())},indent=2)+'\n')
