#!/bin/bash
set -euo pipefail
umask 077
# never installs to a device
REPO=$(cd "$(dirname "$0")/.." && pwd)
ED=$REPO/official-addon/ios107-edition
TURBO_INPUTS=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
if [[ $# != 1 || ! $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  printf 'Usage: %s <label>\n' "$0" >&2
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
# Ignore inherited credentials and paths; require the external configuration.
unset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107 TURBO_PATCHED_APP
[[ -f "$TURBO_INPUTS/package.env" ]] || { echo 'PACKAGE FAIL: missing external package.env' >&2; exit 1; }
set -a
source "$TURBO_INPUTS/package.env"
set +a
for name in TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_PRODUCT TURBO_FIRMWARE TURBO_APP107; do
  [[ -n ${!name:-} ]] || { printf 'PACKAGE FAIL: package.env must set %s\n' "$name" >&2; exit 1; }
done
ADDON=$ED/build/mapkit/TurboIOPrivateAddon.dylib
[[ -f "$ADDON" ]] || { echo 'PACKAGE FAIL: missing addon' >&2; exit 1; }
[[ -f "$TURBO_PROFILE" && -f "$TURBO_FIRMWARE" && -d "$TURBO_APP107" ]] || { echo 'PACKAGE FAIL: missing configured input' >&2; exit 1; }
OUT=$TURBO_INPUTS/signed-$(date +%Y%m%d-%H%M)-$label
[[ ! -e "$OUT" && ! -L "$OUT" ]] || { echo 'PACKAGE FAIL: output already exists' >&2; exit 1; }
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
# The local codesign manual documents that --dryrun uses the identity and
# normal access checks but discards the signature without writing anything.
# Probe once because package.mjs deliberately hides child-process stderr.
run_logged signing-preflight codesign --dryrun --force --sign "$TURBO_SIGN_ID" --timestamp=none "$ADDON"
run_logged package node "$ED/package.mjs" --app "$TURBO_APP107" --addon "$ADDON" \
  --profile "$TURBO_PROFILE" --identity "$TURBO_SIGN_ID" --device "$TURBO_DEVICE" \
  --out "$OUT" --bundle com.rayneo.venus.pub --firmware "$TURBO_FIRMWARE" --product "$TURBO_PRODUCT"
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
