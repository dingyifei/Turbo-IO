#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device
REPO=$(cd "$(dirname "$0")/.." && pwd)
ED=$REPO/ios-addon
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
# TURBO_APP1021 (the stock 1.0.21/1 Runner.app, a read-only test input) may also come from the environment; the
# stages that need the real app (test, package-test, host1021) require it.
if [[ $firmware_only == 0 ]]; then
  inherited_app1021=${TURBO_APP1021:-}
  unset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_APP1021
  [[ -f "$TURBO_INPUTS/package.env" ]] || { echo 'Missing external package.env' >&2; exit 1; }
  set -a
  source "$TURBO_INPUTS/package.env"
  set +a
  TURBO_APP1021=${TURBO_APP1021:-$inherited_app1021}
fi
# The stock 1.0.21/1 app, for the stages that test or package against the real host.
require_app1021() {
  [[ -n ${TURBO_APP1021:-} ]] || { echo 'package.env (or the environment) must set TURBO_APP1021' >&2; return 1; }
  [[ -d "$TURBO_APP1021" ]] || { echo 'TURBO_APP1021 is not a directory' >&2; return 1; }
}
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
  # Localization.m must be exactly what i18n/strings.jsonl generates.
  python3 -I i18n/tio_strings.py gen --check
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
  marker_count=$(grep -a -c 'display extension=TMG-OTA-PHONE-01;' "$addon" || true)
  [[ $marker_count -ge 1 ]] || { echo 'Missing TMG-OTA-PHONE-01 display marker' >&2; return 1; }
  # G1/G2: the flag-independent download-only guard is in every build.
  local name
  for name in _TIOOTADownloadOnlyHost _TIOOTADownloadOnlyBlockCall _TIOOTADownloadOnlyGuardMarker \
    _TIOGlassesChannelHookFailure _TIOChannelHookTargetFailure _TIODownloadOnlyGuardActiveFor _TIOFirmwareExportSafetyModel _TIOHostDownloadOnlyGuardActive \
    _TIOStockTeleprompterSendAllowed; do
    grep -Eq " $name\$" "$GATE/symbols.txt" || { echo "Missing download-only guard symbol $name" >&2; return 1; }
  done
  grep -aFq 'ota guard=DOWNLOAD-ONLY-GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed' "$addon" || { echo 'Missing download-only guard marker' >&2; return 1; }
  # The flag-independent full-host gate (every business-9 frame through the one gate on the full host) is in every build too.
  for name in _TIOOTAFullHost _TIOOTAFullHostGuardMarker _TIOOTAFlashBlockCallSnapshot _TIOOTAFlashAuthorize \
    _TIOOTAFlashNoteRefused _TIOFirmwareExportSafetyModelFull; do
    grep -Eq " $name\$" "$GATE/symbols.txt" || { echo "Missing full host gate symbol $name" >&2; return 1; }
  done
  grep -aFq 'ota guard=FULL-HOST-GATE-01; flag-independent; business 9 transfer frames refused without one confirmation; reads and the exact size query pass' "$addon" || { echo 'Missing full host gate marker' >&2; return 1; }
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
# The releases in releases.json, in order, as a checked list: a failed read aborts the stage (an assignment keeps
# errexit), and an empty list fails rather than silently testing nothing.
release_list() {
  local names
  names=$(python3 -I -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["releases"]))' "$ED/releases.json")
  [[ -n $names ]] || { echo 'releases.json lists no release' >&2; return 1; }
  printf '%s\n' "$names"
}
# The release the full test.py run tests (the first in releases.json; today C26, the only one) and its checked ZIP.
first_release() {
  local names
  names=$(release_list) || return 1
  printf '%s\n' "${names%% *}"
}
first_release_zip() {
  local name
  name=$(first_release) || return 1
  python3 -I "$PINS" --resolve "$name" --inputs "$TURBO_INPUTS"
}
# The stock package of a release (releases.json packages, STOCK-<base>) and its checked ZIP; empty when it lists none.
stock_package_label() {
  python3 -I -c 'import json,sys
r=json.load(open(sys.argv[1]))["releases"][sys.argv[2]]
print(next((p["label"] for p in r["packages"][1:] if p["label"]=="STOCK-"+r["stockBase"]),""))' "$ED/releases.json" "$1"
}
stock_package_zip() {
  local label
  label=$(stock_package_label "$1") || return 1
  [[ -z $label ]] || python3 -I "$PINS" --resolve "$1" --package "$label" --inputs "$TURBO_INPUTS"
}
# The release groups of test.py: pins, archive, directory, gate, the recorded 1.0.21 flash sequence, feed, wizard and
# full-host groups, compiled with the release's TIO_RELEASE define against its own ZIP and stock base.
# flash-packages runs both packages of the release (TMG17 and stock 1.0.6.11) through the gate.
RELEASE_GROUPS=pins,archive,directory,flash,flash-sequence-1021,flash-packages,feed,feed-restart,wizard,tmg4-wizard,ios1021-full-guard,ios1021-full-edge,phone-ota-gate,firmware-export
# One full test.py run for the first release (it includes every release group and the real 1.0.21 app's groups), then
# the release groups alone for each other release, so no group runs twice for the same release. With one release
# (C26) that is the full run only.
test_stage() {
  require_app1021
  local tree name zip stock names first
  local -a stock_args
  tree=$(tree_zip)
  names=$(release_list)
  first=$(first_release)
  cd "$ED"
  for name in $names; do
    zip=$(python3 -I "$PINS" --resolve "$name" --inputs "$TURBO_INPUTS")
    stock=$(stock_package_zip "$name")
    stock_args=()
    [[ -z $stock ]] || stock_args=(--stock-package "$stock")
    if [[ $name == "$first" ]]; then
      python3 test.py --release "$name" --firmware "$zip" --tree-firmware "$tree" --tree-stock "$STOCK" --app1021 "$TURBO_APP1021" ${stock_args[@]+"${stock_args[@]}"}
    else
      rm -rf "build/tests-$name"
      python3 test.py --release "$name" --out "build/tests-$name" --firmware "$zip" --tree-firmware "$tree" --tree-stock "$STOCK" --app1021 "$TURBO_APP1021" ${stock_args[@]+"${stock_args[@]}"} --only "$RELEASE_GROUPS"
    fi
  done
}
# The node tests, with the release ZIP and the real 1.0.21 app for the tests that read them.
package_test_stage() {
  require_app1021
  local zip stock
  zip=$(first_release_zip)
  stock=$(stock_package_zip "$(first_release)")
  cd "$ED"
  TIO_TEST_RELEASE_ZIP="$zip" TIO_TEST_STOCK_ZIP="$stock" IOS1021_TEST_APP="$TURBO_APP1021" node --test package.test.mjs apple-ai/package-resources.test.mjs local-translation/package-resources.test.mjs
}
# The releases built for one packager host (releases.json hosts), space separated; empty when there is none.
releases_for_host() {
  python3 -I -c 'import json,sys;print(" ".join(n for n,r in json.load(open(sys.argv[1]))["releases"].items() if sys.argv[2] in r.get("hosts",[])))' "$ED/releases.json" "$1"
}
# The package path of both 1.0.21/1 hosts up to signing (--build-only): download-only (C19), and full for every
# release built for 1021-full. The real app's test groups run in test_stage and package_test_stage.
host1021_stage() {
  require_app1021
  local name names
  bash "$REPO/scripts/turbo-package.sh" --host 1021 --build-only gate-1021
  names=$(releases_for_host 1021-full)
  [[ -n $names ]] || { echo 'host1021: no release in releases.json is built for 1021-full' >&2; return 1; }
  for name in $names; do
    bash "$REPO/scripts/turbo-package.sh" --host 1021-full --release "$name" --build-only "gate-1021-full-$name"
  done
}
source_audit_stage() {
  cd "$REPO"
  # The audit's own rules and the strings tool, before the audit itself.
  node --test scripts/check-source.test.mjs
  python3 ios-addon/i18n/test_tio_strings.py
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
  python3 -I "$REPO/firmware/tools/check_layout.py" --self-test "$REPO/firmware"
  for name in render_idle native_ui native_status native tmg9_wheel menu_tail nav_service unarmed_services; do
    python3 -I "$REPO/firmware/tests/${name}_host_test.py" --out "$GATE/fw-layout/$name"
  done
  python3 -I "$REPO/firmware/tests/native_light_host_test.py" --stock "$STOCK" --out "$GATE/fw-layout/native_light"
  python3 -I "$REPO/firmware/tests/native_display_host_test.py" --out "$GATE/fw-layout/native_display"
  python3 -I "$REPO/firmware/tests/tio_tokens_test.py" --out "$GATE/fw-layout/tio_tokens"
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
  rm -rf "$GATE/fw-light-off"
  python3 -I "$REPO/firmware/tests/sensors_light_off_link_test.py" --stock "$STOCK" --llvm-bin "$TC" --out "$GATE/fw-light-off"
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
  local tag base dir stock zips=() file
  tag=$(git -C "$REPO" tag --merged HEAD --list 'fw/tmg*' --sort=-version:refname | head -n 1) || return 1
  [[ -n $tag ]] || { echo 'no fw/tmgN tag is merged into HEAD' >&2; return 1; }
  base=$(git -C "$REPO" show "$tag":firmware/build-inputs.json | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["stockBase"])') || return 1
  [[ $base =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad stock base in $tag: $base" >&2; return 1; }
  dir=$GATE/reproduce
  rm -rf "$dir" || return 1
  mkdir -p "$dir" || return 1
  if git -C "$REPO" cat-file -e "$tag:firmware-research/strix-$base/stock" 2>/dev/null; then
    git -C "$REPO" archive "$tag" firmware "firmware-research/strix-$base/stock" | tar -x -C "$dir" || return 1
    stock=$dir/firmware-research/strix-$base/stock/Strix-OS-$base-original.zip
  else
    # The tag's base keeps its stock ZIP outside the repo (1.0.6.11): the tag's own build.py names it.
    git -C "$REPO" archive "$tag" firmware | tar -x -C "$dir" || return 1
    stock=$(python3 -I "$dir/firmware/build.py" --show stock-zip --inputs "$TURBO_INPUTS") || return 1
  fi
  [[ -f $stock ]] || { echo "stock ZIP for $tag not found" >&2; return 1; }
  python3 -I "$dir/firmware/build.py" --stock "$stock" --llvm-bin "$TC" --out "$dir/out" || return 1
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
  for name in private build symbols pins test package-test host1021 preview; do report skip "$name" '--firmware-only'; done
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
  for name in test package-test host1021 source-audit preview; do report skip "$name" '--only-build'; done
else
  if [[ $skip_tests == 1 ]]; then
    report skip test '--skip-tests'
    report skip package-test '--skip-tests'
    report skip host1021 '--skip-tests'
  else
    stage test test_stage
    stage package-test package_test_stage
    stage host1021 host1021_stage
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
