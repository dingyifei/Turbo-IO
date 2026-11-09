#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device
REPO=$(cd "$(dirname "$0")/.." && pwd)
ED=$REPO/official-addon/ios107-edition
TURBO_INPUTS=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
apple_ai_out=''
apple_args=()
# --host 107 (default): the 1.0.7/230 TMG build. --host 1011: the download-only
# 1.0.11/259 build (stock App.framework, no firmware, no flashing), from TURBO_APP1011.
# --wire-log: build the addon with the passive channel recorder (TIO_WIRE_LOG=1).
# --build-only: build and check the addon as a package run would, then stop before
# anything touches the signing identity or writes a package.
host=107
wire_log=0
build_only=0
usage='Usage: turbo-package.sh [--apple-ai <new-directory>] [--host 107|1011] [--wire-log] [--build-only] <label>'
while [[ $# -gt 1 ]]; do
  case "$1" in
    --apple-ai) [[ -n ${2:-} && -z $apple_ai_out ]] || { echo "$usage" >&2; exit 2; }; apple_ai_out=$2; shift 2 ;;
    --host) [[ ${2:-} == 107 || ${2:-} == 1011 ]] || { echo "$usage" >&2; exit 2; }; host=$2; shift 2 ;;
    --wire-log) wire_log=1; shift ;;
    --build-only) build_only=1; shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
if [[ $# != 1 || ! $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "$usage" >&2
  exit 2
fi
label=$1
mkdir -p "$TURBO_INPUTS/package-logs"
LOG_DIR=$(mktemp -d "$TURBO_INPUTS/package-logs/$(date +%Y%m%d-%H%M)-$label.XXXXXX")
REPORT=$LOG_DIR/harness-report.json
printf '{"stages":[]}\n' >"$REPORT"
started=$(python3 -c 'import time; print(time.monotonic())')
active=setup
status=FAIL
OUT=''
finish() {
  local rc=$?
  trap - EXIT
  python3 - "$REPORT" "$started" "$status" "$rc" "$active" "$OUT" <<'PY'
import json,os,sys,time
path,start,status,code,stage,out=sys.argv[1:]
with open(path) as stream: data=json.load(stream)
data.update(status=status,passed=status=='PASS',exitCode=int(code),stage=stage,
            seconds=round(time.monotonic()-float(start),3),output=out,deviceIO=False)
with open(path+'.tmp','w') as stream: json.dump(data,stream,indent=2); stream.write('\n')
os.replace(path+'.tmp',path)
PY
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
keychain_error() {
  LC_ALL=C grep -Eiq 'errSecInternalComponent|keychain[^[:cntrl:]]*(locked|is not unlocked)|user interaction is not allowed|interaction with the Security Server is not allowed' "$1"
}
run_logged() {
  local name=$1 rc begin
  shift
  active=$name
  begin=$(python3 -c 'import time; print(time.monotonic())')
  set +e
  "$@" >"$LOG_DIR/$name.log" 2>&1
  rc=$?
  set -e
  python3 - "$REPORT" "$name" "$begin" "$rc" <<'PY'
import json,os,sys,time
path,name,start,code=sys.argv[1:]
with open(path) as stream: data=json.load(stream)
data['stages'].append({'name':name,'status':'PASS' if code=='0' else 'FAIL',
                       'seconds':round(time.monotonic()-float(start),3),
                       'exitCode':int(code),'log':name+'.log'})
with open(path+'.tmp','w') as stream: json.dump(data,stream,indent=2); stream.write('\n')
os.replace(path+'.tmp',path)
PY
  if [[ $rc != 0 ]]; then
    if keychain_error "$LOG_DIR/$name.log"; then
      status=BLOCKED
      echo 'PACKAGE BLOCKED: keychain' >&2
      exit 3
    fi
    printf 'PACKAGE FAIL: %s (see %s)\n' "$name" "$LOG_DIR/$name.log" >&2
    exit 1
  fi
}
# Ignore inherited credentials and paths; require the external configuration.
unset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107 TURBO_PATCHED_APP TURBO_APP1011
[[ -f "$TURBO_INPUTS/package.env" ]] || { echo 'PACKAGE FAIL: missing external package.env' >&2; exit 1; }
set -a
source "$TURBO_INPUTS/package.env"
set +a
# Build flags come only from the options below, never from the caller's environment
# or package.env: the addon build also runs in an emptied environment (env -i).
for name in $(compgen -e); do [[ $name != TIO_* ]] || unset "$name"; done
if [[ $host == 1011 ]]; then required=(TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_APP1011)
else required=(TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107); fi
for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || { printf 'PACKAGE FAIL: package.env must set %s\n' "$name" >&2; exit 1; }
done
# Every package run builds the addon itself, for both hosts, so a dylib left over
# from an earlier build (other flags, other commit) is never packaged. The flag
# sets are the ones these builds already used: the gate's set by default, the
# Apple AI set with --apple-ai. --wire-log adds TIO_WIRE_LOG=1 to either.
if [[ -n "$apple_ai_out" ]]; then
  build_flags=(TIO_APPLE_AI=1 TIO_MAPKIT_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_OTA_FLASH_ENABLED=1 TIO_CLASSIC_BINDINGS=1)
else
  build_flags=(TIO_MAPKIT_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_IMAGE_RX_WIDE=1 TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_OTA_FLASH_ENABLED=1 TIO_CLASSIC_BINDINGS=1)
fi
[[ $wire_log != 1 ]] || build_flags+=(TIO_WIRE_LOG=1)
ADDON=$ED/build/mapkit/TurboIOPrivateAddon.dylib
rm -f "$ADDON"
[[ ! -e "$ADDON" ]] || { echo 'PACKAGE FAIL: cannot remove the previous addon build' >&2; exit 1; }
printf '%s\n' "${build_flags[@]}" >"$LOG_DIR/addon-flags.txt"
run_logged addon-build env -i PATH="$PATH" HOME="$HOME" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} "${build_flags[@]}" bash "$ED/build.sh" embedded com.rayneo.venus.pub
[[ -f "$ADDON" ]] || { echo 'PACKAGE FAIL: the addon was not built in this run' >&2; exit 1; }
addon_check() {
  local symbols
  symbols=$(nm "$ADDON")
  if [[ $wire_log == 1 ]]; then
    grep -Eq ' _TIOWireLogStart$' <<<"$symbols" || { echo 'wire log requested but missing from the addon' >&2; return 1; }
  else
    bash "$REPO/scripts/wirelog-absent.sh" "$ADDON"
  fi
  shasum -a 256 "$ADDON" | cut -d' ' -f1
}
run_logged addon-check addon_check
# Everything after this point uses a private copy of the checked dylib, so a later
# build into build/mapkit cannot change what is signed. Its SHA-256 is checked
# again right before packaging.
addon_sha=$(tail -n 1 "$LOG_DIR/addon-check.log")
mkdir "$LOG_DIR/addon"
cp -p "$ADDON" "$LOG_DIR/addon/TurboIOPrivateAddon.dylib"
ADDON=$LOG_DIR/addon/TurboIOPrivateAddon.dylib
addon_unchanged() { [[ $(shasum -a 256 "$ADDON" | cut -d' ' -f1) == "$addon_sha" ]] || { echo 'addon changed after its check' >&2; return 1; }; }
run_logged addon-copy addon_unchanged
if [[ -n "$apple_ai_out" ]]; then
  run_logged apple-ai-build python3 "$ED/apple-ai/build.py" --out "$apple_ai_out"
  apple_args=(--apple-ai-dylib "$(cd "$apple_ai_out" && pwd)/TurboAppleAI.dylib")
fi
download_only_guard() {
  local symbols name
  symbols=$(nm -g "$1")
  for name in _TIOOTAFlashBlockCall _TIOOTADownloadOnlyHost _TIOOTADownloadOnlyBlockCall _TIOOTADownloadOnlyGuardMarker \
    _TIOInstallGlassesChannelHook _TIOGlassesChannelHookFailure _TIOChannelHookTargetFailure \
    _TIODownloadOnlyGuardActiveFor _TIOFirmwareExportSafetyModel _TIOHostDownloadOnlyGuardActive \
    _TIOStockTeleprompterSendAllowed; do
    grep -Eq " $name\$" <<<"$symbols" || { echo "missing $name" >&2; return 1; }
  done
  grep -aFq 'ota guard=IOS1011-DOWNLOAD-GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed' "$1" || { echo 'missing 1.0.11 guard marker' >&2; return 1; }
}
if [[ $build_only == 1 ]]; then
  [[ $host != 1011 ]] || run_logged download-only-guard download_only_guard "$ADDON"
  status=PASS
  active=complete
  printf 'built %s (%s)\n' "$ADDON" "$addon_sha"
  exit 0
fi
if [[ $host == 1011 ]]; then
  [[ -f "$TURBO_PROFILE" && -d "$TURBO_APP1011" ]] || { echo 'PACKAGE FAIL: missing configured input' >&2; exit 1; }
else
  [[ -f "$TURBO_PROFILE" && -f "$TURBO_FIRMWARE" && -d "$TURBO_APP107" ]] || { echo 'PACKAGE FAIL: missing configured input' >&2; exit 1; }
fi
OUT=$TURBO_INPUTS/signed-$(date +%Y%m%d-%H%M)-$label
[[ ! -e "$OUT" && ! -L "$OUT" ]] || { echo 'PACKAGE FAIL: output already exists' >&2; exit 1; }
# The local codesign manual documents that --dryrun uses the identity and
# normal access checks but discards the signature without writing anything.
# Probe once because package.mjs deliberately hides child-process stderr.
run_logged signing-preflight codesign --dryrun --force --sign "$TURBO_SIGN_ID" --timestamp=none "$ADDON"
if [[ $host == 1011 ]]; then
# G1/G2: fail closed unless the addon carries the flag-independent 1.0.11 guard
# (package.mjs repeats this check with the same symbol list before signing).
run_logged download-only-guard download_only_guard "$ADDON"
# Download-only: no firmware resource and no device-model list; package.mjs keeps App.framework stock.
run_logged addon-unchanged addon_unchanged
run_logged package node "$ED/package.mjs" --host ios1011-download --app "$TURBO_APP1011" --addon "$ADDON" \
  --profile "$TURBO_PROFILE" --identity "$TURBO_SIGN_ID" --device "$TURBO_DEVICE" \
  --out "$OUT" --bundle com.rayneo.venus.pub ${apple_args[@]+"${apple_args[@]}"}
run_logged codesign codesign --verify --deep --strict "$OUT/Payload/Runner.app"
run_logged unzip unzip -tq "$OUT/TurboIO-local-only.ipa"
run_logged report python3 - "$OUT" <<'PY'
import hashlib,json,pathlib,plistlib,sys
out=pathlib.Path(sys.argv[1])
with (out/'report.json').open() as stream: report=json.load(stream)
assert report['status']=='SIGNED_NOT_DEVICE_ACCEPTED', 'unexpected package status'
assert report['hostProfile']=='ios1011-download' and report['flashAuthorized'] is False, 'unexpected host profile or flash authorization'
assert report['firmwareBundled'] is False and report['routePatched'] is False and report['experimentalOTA'] is False, 'download-only build carries OTA material'
app=out/'Payload/Runner.app'
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info.get('TIOHostProfile')=='ios1011-download', 'missing host profile marker'
for key in ('TIOExperimentalOTAQueryRouting','TIOExperimentalOTABuild','UISupportedDevices'):
    assert key not in info, 'unexpected '+key
assert not (app/'TurboWeReadCandidate.zip').exists(), 'unexpected firmware resource'
digest=hashlib.sha256((out/'TurboIO-local-only.ipa').read_bytes()).hexdigest()
assert report['ipaSHA256']==digest, 'IPA digest mismatch'
print(digest)
PY
else
run_logged addon-unchanged addon_unchanged
run_logged package node "$ED/package.mjs" --app "$TURBO_APP107" --addon "$ADDON" \
  --profile "$TURBO_PROFILE" --identity "$TURBO_SIGN_ID" --device "$TURBO_DEVICE" \
  --out "$OUT" --bundle com.rayneo.venus.pub --firmware "$TURBO_FIRMWARE" --product "$TURBO_PRODUCT" ${apple_args[@]+"${apple_args[@]}"}
run_logged codesign codesign --verify --deep --strict "$OUT/Payload/Runner.app"
run_logged unzip unzip -tq "$OUT/TurboIO-local-only.ipa"
run_logged plist plutil -extract UISupportedDevices json -o "$LOG_DIR/supported-devices.json" "$OUT/Payload/Runner.app/Info.plist"
run_logged report python3 - "$OUT" "$TURBO_PRODUCT" "$LOG_DIR/supported-devices.json" <<'PY'
import hashlib,json,pathlib,sys
out=pathlib.Path(sys.argv[1])
with (out/'report.json').open() as stream: report=json.load(stream)
assert report['status']=='SIGNED_NOT_DEVICE_ACCEPTED', 'unexpected package status'
assert report['flashAuthorized'] is False, 'unexpected flash authorization'
with open(sys.argv[3]) as stream: products=json.load(stream)
assert isinstance(products,list) and sys.argv[2] in products, 'configured product absent'
digest=hashlib.sha256((out/'TurboIO-local-only.ipa').read_bytes()).hexdigest()
assert report['ipaSHA256']==digest, 'IPA digest mismatch'
print(digest)
PY
fi
active=timings
mkdir -p "$TURBO_INPUTS/baseline"
python3 - "$started" "$TURBO_INPUTS/baseline/timings.txt" "$label" <<'PY'
import sys,time
with open(sys.argv[2],'a') as stream:
    stream.write('turbo-package.sh '+sys.argv[3]+' '+str(round(time.monotonic()-float(sys.argv[1]),3))+' s\n')
PY
status=PASS
active=complete
printf '%s\n' "$OUT"
printf 'ipaSHA256 %s\n' "$(cat "$LOG_DIR/report.log")"
