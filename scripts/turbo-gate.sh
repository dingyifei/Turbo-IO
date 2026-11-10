#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device
REPO=$(cd "$(dirname "$0")/.." && pwd)
ED=$REPO/official-addon/ios107-edition
TURBO_INPUTS=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
preview=0
only_build=0
skip_tests=0
for arg in "$@"; do
  case "$arg" in
    --preview) preview=1 ;;
    --only-build) only_build=1 ;;
    --skip-tests) skip_tests=1 ;;
    *) printf 'Usage: %s [--preview] [--only-build] [--skip-tests]\n' "$0" >&2; exit 2 ;;
  esac
done
if [[ $only_build == 1 && $preview == 1 ]]; then
  echo '--only-build and --preview cannot be combined' >&2
  exit 2
fi
GATE=$ED/build/gate
mkdir -p "$GATE"
REPORT=$GATE/report.json
started=$(python3 -c 'import time; print(time.monotonic())')
active=setup
report() {
  python3 - "$REPORT" "$@" <<'PY'
import json, os, sys, time
path,event,*args=sys.argv[1:]
if event=='init':
    data={'status':'RUNNING','passed':False,'stages':[],'skipped':[],
          'seconds':0,'deviceIO':False,'hardwareValidated':False}
else:
    with open(path) as stream: data=json.load(stream)
if event=='stage':
    name,start,status,code=args
    data['stages'].append({'name':name,'seconds':round(time.monotonic()-float(start),3),
                           'status':status,'exitCode':int(code),'log':name+'.log'})
elif event=='skip': data['skipped'].append({'name':args[0],'reason':args[1]})
elif event=='finish':
    status,start,code,active=args
    data.update(status=status,passed=status=='PASS',seconds=round(time.monotonic()-float(start),3),exitCode=int(code))
    if status!='PASS': data['failedStage']=active
temporary=path+'.tmp'
with open(temporary,'w') as stream: json.dump(data,stream,indent=2); stream.write('\n')
os.replace(temporary,path)
PY
}
report init
on_exit() {
  rc=$?
  trap - EXIT
  if [[ $rc != 0 ]]; then
    report finish FAIL "$started" "$rc" "$active" || true
    if [[ $active == setup ]]; then echo 'GATE FAIL setup' >&2; fi
  fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stage() {
  local name=$1 begin rc
  shift
  active=$name
  begin=$(python3 -c 'import time; print(time.monotonic())')
  # Run outside a conditional so errexit remains active inside shell functions.
  set +e
  (set -e; "$@") >"$GATE/$name.log" 2>&1
  rc=$?
  set -e
  if [[ $rc == 0 ]]; then
    report stage "$name" "$begin" PASS 0
    printf '%s: PASS\n' "$name"
  else
    report stage "$name" "$begin" FAIL "$rc"
    printf 'GATE FAIL %s\n' "$name" >&2
    tail -n 30 "$GATE/$name.log" >&2
    exit 1
  fi
}
# The external configuration is the only source of packaging inputs.
# TURBO_APP1011 (optional, read-only test input) may also come from the environment.
inherited_app1011=${TURBO_APP1011:-}
unset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107 TURBO_PATCHED_APP TURBO_APP1011
[[ -f "$TURBO_INPUTS/package.env" ]] || { echo 'Missing external package.env' >&2; exit 1; }
set -a
source "$TURBO_INPUTS/package.env"
set +a
TURBO_APP1011=${TURBO_APP1011:-$inherited_app1011}
private_stage() {
  local backup=$TURBO_INPUTS/private-backup/ios107 file
  for file in PrivateBootstrap.h PrivateBootstrap.m; do
    if [[ ! -e "$ED/$file" ]]; then cp -p "$backup/$file" "$ED/$file"; fi
  done
  (cd "$backup"; shasum -a 256 -c SHA256SUMS)
  for file in PrivateBootstrap.h PrivateBootstrap.m; do cmp "$backup/$file" "$ED/$file"; done
}
build_stage() {
  cd "$ED"
  TIO_MAPKIT_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 \
    TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_OTA_FLASH_ENABLED=1 \
    TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub
}
symbols_stage() {
  local addon=$ED/build/mapkit/TurboIOPrivateAddon.dylib marker_count
  nm -g "$addon" >"$GATE/symbols.txt"
  grep -Fq '_TIOOTAFlashBuild' "$GATE/symbols.txt"
  grep -Fq 'OBJC_CLASS_$_TIOMapKitNavigationPanel' "$GATE/symbols.txt"
  grep -Fq 'TIOMenuLayoutController' "$GATE/symbols.txt"
  grep -Fq 'OBJC_CLASS_$_TIORoadMap' "$GATE/symbols.txt"
  if grep -Fq 'AMapNavi' "$GATE/symbols.txt"; then echo 'Unexpected AMapNavi symbol' >&2; return 1; fi
  # The default build carries no wire log: its recorder exists only in TIO_WIRE_LOG=1 builds.
  bash "$REPO/scripts/wirelog-absent.sh" "$addon"
  marker_count=$(grep -a -c 'display extension=APP107-OTA-PHONE-01;' "$addon" || true)
  [[ $marker_count -ge 1 ]] || { echo 'Missing APP107 display marker' >&2; return 1; }
  # G1/G2: the flag-independent 1.0.11 download-only guard is in every build.
  local name
  for name in _TIOOTADownloadOnlyHost _TIOOTADownloadOnlyBlockCall _TIOOTADownloadOnlyGuardMarker \
    _TIOGlassesChannelHookFailure _TIOChannelHookTargetFailure _TIODownloadOnlyGuardActiveFor _TIOFirmwareExportSafetyModel _TIOHostDownloadOnlyGuardActive \
    _TIOStockTeleprompterSendAllowed; do
    grep -Eq " $name\$" "$GATE/symbols.txt" || { echo "Missing 1.0.11 guard symbol $name" >&2; return 1; }
  done
  grep -aFq 'ota guard=IOS1011-DOWNLOAD-GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed' "$addon" || { echo 'Missing 1.0.11 guard marker' >&2; return 1; }
  # C15: the flag-independent disarm guard and the arm step of the full 1.0.11 host are in every build too.
  for name in _TIOOTAArmRequired _TIOOTADisarmedBlockCall _TIOOTADisarmedReadAllowed _TIOOTAArmGuardMarker \
    _TIOOTAFlashArm _TIOOTAFlashDisarm _TIOOTAFlashArmed _TIOOTAFlashArmStatus _TIOFirmwareExportSafetyModelFull; do
    grep -Eq " $name\$" "$GATE/symbols.txt" || { echo "Missing 1.0.11 arm guard symbol $name" >&2; return 1; }
  done
  grep -aFq 'ota guard=IOS1011-FULL-DISARM-01; flag-independent; disarmed until armed on this install' "$addon" || { echo 'Missing 1.0.11 arm guard marker' >&2; return 1; }
}
# Release configurations (releases.json). The phone pins of every release are generated from the release ZIPs,
# found under $TURBO_INPUTS at the paths releases.json names and checked by size and SHA-256.
PINS=$REPO/firmware/tools/phone_pins.py
pins_stage() {
  python3 -I "$PINS" --check "$ED" --inputs "$TURBO_INPUTS"
}
# The ZIP built from the current firmware tree (RELEASE, build-inputs.json), for test.py's tree audit.
tree_zip() {
  python3 -I "$PINS" --resolve "$(python3 -I "$PINS" --tree-release)" --inputs "$TURBO_INPUTS"
}
named_releases() {
  python3 -I -c 'import json,sys;print(" ".join(n for n in json.load(open(sys.argv[1]))["releases"] if n!="default"))' "$ED/releases.json"
}
# The named releases as a checked list: a failed read aborts the stage (an assignment keeps errexit), and an
# empty list fails rather than silently testing nothing.
release_list() {
  local names
  names=$(named_releases)
  [[ -n $names ]] || { echo 'releases.json lists no named release' >&2; return 1; }
  printf '%s\n' "$names"
}
test_stage() {
  : "${TURBO_FIRMWARE:?package.env must set TURBO_FIRMWARE}"
  : "${TURBO_APP107:?package.env must set TURBO_APP107}"
  : "${TURBO_PATCHED_APP:?package.env must set TURBO_PATCHED_APP}"
  local tree
  tree=$(tree_zip)
  cd "$ED"
  # The default release (C14/C15) with TURBO_FIRMWARE; test.py's pins group refuses any other ZIP.
  python3 test.py --firmware "$TURBO_FIRMWARE" --tree-firmware "$tree" --app107 "$TURBO_APP107" --patched-app "$TURBO_PATCHED_APP"
}
# Every named release (C16, C17): its pins, archive, directory, gate, feed, wizard and 1.0.11 full-host groups,
# compiled with its TIO_RELEASE define against its own ZIP and stock base.
RELEASE_GROUPS=pins,archive,directory,flash,feed,feed-restart,wizard,tmg4-wizard,tmg4-wizard-1011,ios1011-arm-store,ios1011-full-guard,ios1011-full-edge,phone-ota-gate,firmware-export
release_stage() {
  local tree name zip names
  tree=$(tree_zip)
  names=$(release_list)
  cd "$ED"
  for name in $names; do
    zip=$(python3 -I "$PINS" --resolve "$name" --inputs "$TURBO_INPUTS")
    rm -rf "build/tests-$name"
    python3 test.py --release "$name" --out "build/tests-$name" --firmware "$zip" --tree-firmware "$tree" ${TURBO_APP1011:+--app1011 "$TURBO_APP1011"} --only "$RELEASE_GROUPS"
  done
}
package_test_stage() {
  : "${TURBO_FIRMWARE:?package.env must set TURBO_FIRMWARE}"
  cd "$ED"
  unset IOS107_TEST_UNSIGNED_APP IOS107_TEST_RUNNER IOS107_TEST_APP_IMAGE
  : "${TURBO_APP107:?package.env must set TURBO_APP107}"
  # The unsigned-app baseline probe passed. The separate runner/image probe
  # failed its fixed patched-output hash (500d3360... versus fd68e86b...),
  # so those two optional inputs stay unset. See package-probe-pair.log.
  export IOS107_TEST_UNSIGNED_APP=$TURBO_APP107
  IOS107_TEST_FIRMWARE="$TURBO_FIRMWARE" node --test package.test.mjs apple-ai/package-resources.test.mjs local-translation/package-resources.test.mjs
}
# Optional: 1.0.11/259 host checks, download-only and full (C15). Runs only when TURBO_APP1011 is set.
host1011_stage() {
  : "${TURBO_FIRMWARE:?package.env must set TURBO_FIRMWARE}"
  [[ -d "$TURBO_APP1011" ]] || { echo 'TURBO_APP1011 is not a directory' >&2; return 1; }
  local tree
  tree=$(tree_zip)
  cd "$ED"
  python3 test.py --firmware "$TURBO_FIRMWARE" --tree-firmware "$tree" --app1011 "$TURBO_APP1011" --only host,ios1011-guard,ios1011-host,ios1011-full-guard,ota-host-1011,host-selectors
  unset IOS107_TEST_UNSIGNED_APP IOS107_TEST_RUNNER IOS107_TEST_APP_IMAGE IOS107_TEST_FIRMWARE
  IOS1011_TEST_APP="$TURBO_APP1011" node --test package.test.mjs
  # The full 1.0.11 package path up to (not including) signing: fresh addon build and both 1.0.11 guards,
  # for the default release and for every named release (its TIO_RELEASE build and its checked ZIP).
  bash "$REPO/scripts/turbo-package.sh" --host 1011-full --build-only gate-1011-full
  local name names
  names=$(release_list)
  for name in $names; do
    bash "$REPO/scripts/turbo-package.sh" --host 1011-full --release "$name" --build-only "gate-1011-full-$name"
  done
}
source_audit_stage() {
  cd "$REPO"
  node --input-type=module -e "const m=await import('./scripts/check-source.mjs');const r=m.audit(process.cwd());const f=r.findings.filter(x=>!x.file.startsWith('.remember/'));if(f.length){console.log(JSON.stringify(f,null,1));process.exit(1)}console.log(r.files+' files clean')"
}
preview_stage() {
  bash "$ED/preview/build.sh"
  bash "$ED/preview/shoot.sh"
}
stage private private_stage
stage build build_stage
stage symbols symbols_stage
stage pins pins_stage
if [[ $only_build == 1 ]]; then
  for name in test releases package-test host1011 source-audit preview; do report skip "$name" '--only-build'; done
else
  if [[ $skip_tests == 1 ]]; then
    report skip test '--skip-tests'
    report skip releases '--skip-tests'
    report skip package-test '--skip-tests'
    report skip host1011 '--skip-tests'
  else
    stage test test_stage
    stage releases release_stage
    stage package-test package_test_stage
    if [[ -n "$TURBO_APP1011" ]]; then stage host1011 host1011_stage; else report skip host1011 'TURBO_APP1011 not set'; fi
  fi
  stage source-audit source_audit_stage
  if [[ $preview == 1 ]]; then stage preview preview_stage; else report skip preview 'not requested'; fi
fi
active=timings
report finish PASS "$started" 0 ''
mkdir -p "$TURBO_INPUTS/baseline"
python3 - "$REPORT" "$TURBO_INPUTS/baseline/timings.txt" <<'PY'
import json,sys
with open(sys.argv[1]) as stream: report=json.load(stream)
with open(sys.argv[2],'a') as stream:
    stream.write('turbo-gate.sh PASS '+str(report['seconds'])+' s\n')
    for stage in report['stages']:
        if stage['name']=='test': stream.write('test.py full '+str(stage['seconds'])+' s (gate)\n')
print('GATE PASS '+str(report['seconds'])+' s')
PY
trap - EXIT
