"""Portable macOS offline tests. No phone, network, signing or flashing."""
from pathlib import Path
import argparse, fnmatch, json, subprocess, tempfile, zipfile
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
def run(name,cmd):
    r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=180)
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
if only is None:
    missing={v['group'] for v in manifest.values() if v['status']=='run'}-set(groups)-{n for n,_ in skipped}
    if missing:raise SystemExit('manifest groups not executed: '+str(sorted(missing)))
elif only-seen:
    raise SystemExit('unknown groups: '+str(sorted(only-seen)))
(out/'report.json').write_text(json.dumps({'passed':True,'groups':groups,'deviceIO':False,'hardwareValidated':False,'skipped':skipped,'excluded':sum(v['status']=='excluded' for v in manifest.values())},indent=2)+'\n')
