#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device
REPO=$(cd "$(dirname "$0")/.." && pwd)
ED=$REPO/official-addon/ios107-edition
TURBO_INPUTS=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
export TURBO_INPUTS   # phone_pins_test.py reads release ZIPs that test.py does not pass
preview=0
only_build=0
skip_tests=0
firmware_only=0
tree_zip_arg=
usage() {
  printf 'Usage: %s [--preview] [--only-build] [--skip-tests]\n       %s --firmware-only [--tree-zip ZIP]\n' "$0" "$0" >&2
  exit 2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview) preview=1 ;;
    --only-build) only_build=1 ;;
    --skip-tests) skip_tests=1 ;;
    --firmware-only) firmware_only=1 ;;
    --tree-zip) [[ $# -ge 2 && -n $2 ]] || usage; tree_zip_arg=$2; shift ;;
    *) usage ;;
  esac
  shift
done
if [[ $only_build == 1 && $preview == 1 ]]; then
  echo '--only-build and --preview cannot be combined' >&2
  exit 2
fi
if [[ $firmware_only == 1 && ( $preview == 1 || $only_build == 1 || $skip_tests == 1 ) ]]; then
  echo '--firmware-only cannot be combined with --preview, --only-build or --skip-tests' >&2
  exit 2
fi
if [[ -n $tree_zip_arg && $firmware_only == 0 ]]; then
  echo '--tree-zip is valid only with --firmware-only' >&2
  exit 2
fi
if [[ -n $tree_zip_arg ]]; then
  [[ -f $tree_zip_arg ]] || { echo "--tree-zip: no such file: $tree_zip_arg" >&2; exit 2; }
  tree_zip_arg=$(cd "$(dirname "$tree_zip_arg")" && pwd)/$(basename "$tree_zip_arg")
fi
# The firmware-only gate has its own directory, so it never overwrites the full gate's report.
if [[ $firmware_only == 1 ]]; then GATE=$ED/build/gate-firmware; else GATE=$ED/build/gate; fi
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
elif event=='set': data[args[0]]=args[1]
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
if [[ $firmware_only == 1 ]]; then
  report set mode firmware-only
  if [[ -n $tree_zip_arg ]]; then report set build compile-only; else report set build plain; fi
fi
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
# The stock ZIP of the tree's base and the toolchain, in both modes. A tree ZIP built by an earlier run is never reused.
STOCK=$(python3 -I "$REPO/firmware/build.py" --show stock-zip --inputs "$TURBO_INPUTS")
TC=$TURBO_INPUTS/toolchain/llvm-bin
rm -rf "$GATE/tree-build"
# The external configuration is the only source of packaging inputs. The firmware-only gate reads none of it.
# TURBO_APP1011 (optional, read-only test input) may also come from the environment.
if [[ $firmware_only == 0 ]]; then
  inherited_app1011=${TURBO_APP1011:-}
  unset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107 TURBO_PATCHED_APP TURBO_APP1011
  [[ -f "$TURBO_INPUTS/package.env" ]] || { echo 'Missing external package.env' >&2; exit 1; }
  set -a
  source "$TURBO_INPUTS/package.env"
  set +a
  TURBO_APP1011=${TURBO_APP1011:-$inherited_app1011}
fi
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
# A plain build of the tree into the fresh directory $1; prints the path of the one StrixOS-*.zip it wrote.
# The build's own output goes to stderr (callers capture stdout). Command substitutions do not keep errexit,
# so every step ends in an explicit "|| return 1".
build_tree_zip() {
  local out=$1 zips=() file
  rm -rf "$out" || return 1
  python3 -I "$REPO/firmware/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$out" >&2 || return 1
  for file in "$out"/StrixOS-*.zip; do [[ -f $file ]] && zips+=("$file"); done
  [[ ${#zips[@]} == 1 ]] || { echo "expected exactly one StrixOS-*.zip in $out" >&2; return 1; }
  printf '%s\n' "${zips[0]}"
}
# The ZIP built from the current firmware tree (RELEASE, build-inputs.json), for test.py's tree audit.
# An emulator-only tree has no phone release and no pinned ZIP: it is built once, into $GATE/tree-build, and reused
# by the stages after it (the directory is cleared at the start of every run). Any other tree is its pinned release ZIP.
tree_zip() {
  local zips=() file
  for file in "$GATE"/tree-build/StrixOS-*.zip; do [[ -f $file ]] && zips+=("$file"); done
  if [[ ${#zips[@]} == 1 ]]; then printf '%s\n' "${zips[0]}"; return 0; fi
  local emu
  emu=$(python3 -I "$REPO/firmware/build.py" --show emu-only) || return 1
  if [[ $emu == true ]]; then build_tree_zip "$GATE/tree-build"; return; fi
  local release
  release=$(python3 -I "$PINS" --tree-release) || return 1
  python3 -I "$PINS" --resolve "$release" --inputs "$TURBO_INPUTS"
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
  python3 test.py --firmware "$TURBO_FIRMWARE" --tree-firmware "$tree" --tree-stock "$STOCK" --app107 "$TURBO_APP107" --patched-app "$TURBO_PATCHED_APP"
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
    python3 test.py --release "$name" --out "build/tests-$name" --firmware "$zip" --tree-firmware "$tree" --tree-stock "$STOCK" ${TURBO_APP1011:+--app1011 "$TURBO_APP1011"} --only "$RELEASE_GROUPS"
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
  python3 test.py --firmware "$TURBO_FIRMWARE" --tree-firmware "$tree" --tree-stock "$STOCK" --app1011 "$TURBO_APP1011" --only host,ios1011-guard,ios1011-host,ios1011-full-guard,ota-host-1011,host-selectors
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
# The firmware-only gate: the firmware tree's own checks, with no phone build, no package.env, no releases.json
# entry and no phone_pins.py call. Without --tree-zip it builds the tree (a plain build, which asserts every pin);
# with it, only the compile path runs and the given ZIP is audited and tested (the tree's pins may not match it).
fw_tree_zip() {
  local zips=() file
  if [[ -n $tree_zip_arg ]]; then printf '%s\n' "$tree_zip_arg"; return 0; fi
  for file in "$GATE"/fw-build/StrixOS-*.zip; do [[ -f $file ]] && zips+=("$file"); done
  [[ ${#zips[@]} == 1 ]] || { echo "expected exactly one StrixOS-*.zip in $GATE/fw-build" >&2; return 1; }
  printf '%s\n' "${zips[0]}"
}
fw_rebase_stage() {
  python3 -I "$REPO/firmware/tools/rebase_apply.py" --check --stock "$STOCK"
}
# The stock layout checks: stock_layout.h proven against the stock AP, no raw stock offset in the tree, and the host
# drivers that run on the tree's base. They need no tree ZIP, so they run before the build in both modes.
fw_layout_stage() {
  local name
  rm -rf "$GATE/fw-layout"
  mkdir -p "$GATE/fw-layout"
  python3 -I "$REPO/firmware/tests/stock_layout_test.py" --stock "$STOCK"
  python3 -I "$REPO/firmware/tools/check_layout.py" "$REPO/firmware"
  for name in render_idle native_ui native_status native tmg9_wheel menu_tail; do
    python3 -I "$REPO/firmware/tests/${name}_host_test.py" --out "$GATE/fw-layout/$name"
  done
  python3 -I "$REPO/firmware/tests/native_light_host_test.py" --stock "$STOCK" --out "$GATE/fw-layout/native_light"
  python3 -I "$REPO/firmware/tests/native_display_host_test.py" --out "$GATE/fw-layout/native_display"
  python3 -I "$REPO/firmware/tests/rebase_independent_test.py"
  python3 -I "$REPO/firmware/tests/stock_abi_test.py" --stock "$STOCK"
  python3 -I "$REPO/firmware/tests/stock_base_test.py"
  python3 -I "$REPO/firmware/tools/check_kept.py" "$REPO/firmware/baseline/kept" "$REPO/firmware"
  python3 -I "$REPO/firmware/tools/check_cjk.py" "$REPO/firmware"
  python3 -I "$REPO/firmware/tests/remote_app_name_test.py" --stock "$STOCK"
  python3 -I "$REPO/firmware/tests/grid_label_stock_test.py" --stock "$STOCK"
  # The tile model in both shapes: 13 items without a base define (the 1.0.5.12 pair), 14 items on 1.0.6.11.
  for name in '' -DTD_STOCK_10611=1; do
    xcrun clang -std=c11 -O1 -g -Wall -Wextra -fsanitize=address,undefined $name -I "$REPO/firmware/src" \
      "$REPO/firmware/tests/tile_model_test.c" "$REPO/firmware/src/menu-grid-v2/tile_config.c" -o "$GATE/fw-layout/tile-model"
    "$GATE/fw-layout/tile-model"
  done
}
fw_build_stage() {
  local built
  if [[ -n $tree_zip_arg ]]; then
    rm -rf "$GATE/fw-compile"
    python3 -I "$REPO/firmware/build.py" --stock "$STOCK" --llvm-bin "$TC" --out "$GATE/fw-compile" --compile-only
    printf 'compile-only build; tree ZIP given, not built: %s\n' "$tree_zip_arg"
  else
    built=$(build_tree_zip "$GATE/fw-build")
    printf 'plain build: %s\n' "$built"
  fi
}
fw_audit_stage() {
  local zip
  zip=$(fw_tree_zip)
  python3 -I "$REPO/firmware/build.py" --stock "$STOCK" --audit "$zip"
}
fw_tests_stage() {
  local zip
  zip=$(fw_tree_zip)
  cd "$ED"
  rm -rf build/tests-firmware
  python3 test.py --firmware-only --tree-firmware "$zip" --tree-stock "$STOCK" --out build/tests-firmware
}
# C18's firmware is the newest released fw/tmgN tag. The tree itself may no longer build that ZIP (build.py's identity
# moves with every edit), so the tag is exported and rebuilt with its own build.py and pins, which require its ZIP.
fw_reproduce_stage() {
  local tag base dir zips=() file
  tag=$(git -C "$REPO" tag --merged HEAD --list 'fw/tmg*' --sort=-version:refname | head -n 1) || return 1
  [[ -n $tag ]] || { echo 'no fw/tmgN tag is merged into HEAD' >&2; return 1; }
  base=$(git -C "$REPO" show "$tag":firmware/build-inputs.json | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["stockBase"])') || return 1
  [[ $base =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad stock base in $tag: $base" >&2; return 1; }
  dir=$GATE/reproduce
  rm -rf "$dir" || return 1
  mkdir -p "$dir" || return 1
  git -C "$REPO" archive "$tag" firmware "firmware-research/strix-$base/stock" | tar -x -C "$dir" || return 1
  python3 -I "$dir/firmware/build.py" --stock "$dir/firmware-research/strix-$base/stock/Strix-OS-$base-original.zip" --llvm-bin "$TC" --out "$dir/out" || return 1
  for file in "$dir"/out/StrixOS-*.zip; do [[ -f $file ]] && zips+=("$file"); done
  [[ ${#zips[@]} == 1 ]] || { echo "expected exactly one StrixOS-*.zip in $dir/out" >&2; return 1; }
  printf 'tag %s\nzip %s\n' "$tag" "$(basename "${zips[0]}")"
  printf 'sha256 %s\n' "$(shasum -a 256 "${zips[0]}" | cut -d' ' -f1)"
}
if [[ $firmware_only == 1 ]]; then
  stage fw-rebase fw_rebase_stage
  stage fw-layout fw_layout_stage
  stage fw-build fw_build_stage
  stage fw-audit fw_audit_stage
  stage fw-tests fw_tests_stage
  stage fw-reproduce fw_reproduce_stage
  stage source-audit source_audit_stage
  for name in private build symbols pins test releases package-test host1011 preview; do report skip "$name" '--firmware-only'; done
  active=finish
  report finish PASS "$started" 0 ''
  if [[ -n $tree_zip_arg ]]; then
    echo 'GATE PASS (firmware-only, compile-only build; tree ZIP given, not built)'
  else
    echo 'GATE PASS (firmware-only, plain build)'
  fi
  trap - EXIT
  exit 0
fi
stage private private_stage
stage build build_stage
stage symbols symbols_stage
stage pins pins_stage
stage fw-layout fw_layout_stage
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
