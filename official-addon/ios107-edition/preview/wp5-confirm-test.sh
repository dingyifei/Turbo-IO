#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
E=$PWD
IN=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
OUT="$IN/overnight/logs/wp5/race-test"
mkdir -p "$IN/locks" "$OUT"
LOCK="$IN/locks/sim.lock"
until mkdir "$LOCK" 2>/dev/null; do sleep 5; done
trap 'rmdir "$LOCK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -r "$IN/preview-sim.udid" ]] || { echo 'CONFIRM RACE FAIL: missing pinned preview-sim.udid' >&2; exit 1; }
DEV=$(cat "$IN/preview-sim.udid")
[[ "$DEV" =~ ^[0-9A-Fa-f-]{36}$ ]] || { echo 'CONFIRM RACE FAIL: invalid pinned UDID' >&2; exit 1; }
APP_REL=$(sed -n 's/^output=//p' preview/build.sh | head -1)
[[ -n "$APP_REL" ]] || { echo 'CONFIRM RACE FAIL: preview/build.sh has no output path' >&2; exit 1; }
APP="$E/$APP_REL"
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' preview/Info.plist)
[[ -x "$APP/TurboPreview" ]] || { echo 'CONFIRM RACE FAIL: build the ad-hoc preview app first' >&2; exit 1; }
rm -f "$OUT/confirm-race-report.json" "$OUT/launch.txt" "$OUT/check.txt"

xcrun simctl boot "$DEV" || true
xcrun simctl bootstatus "$DEV" -b
xcrun simctl terminate "$DEV" "$BID" || true
xcrun simctl install "$DEV" "$APP"
container=$(xcrun simctl get_app_container "$DEV" "$BID" data)
rm -f "$container/Documents/confirm-race-report.json"
xcrun simctl launch "$DEV" "$BID" --confirm-race-test -AppleLanguages '(en)' -AppleLocale en_US | tee "$OUT/launch.txt"

for ((attempt=0;attempt<40;attempt++)); do
    [[ -f "$container/Documents/confirm-race-report.json" ]] && break
    sleep 0.5
done
[[ -f "$container/Documents/confirm-race-report.json" ]] || { echo 'CONFIRM RACE FAIL: missing fresh report' >&2; exit 1; }
cp "$container/Documents/confirm-race-report.json" "$OUT/confirm-race-report.json"
xcrun simctl terminate "$DEV" "$BID" || true
python3 - "$OUT/confirm-race-report.json" <<'PY' | tee "$OUT/check.txt"
import json,sys
report=json.load(open(sys.argv[1],encoding='utf-8'))
cases=report.get('cases',[])
expected={(kind,state) for kind in ('notice','confirm','choose') for state in ('active','dismissing')}
actual={(case.get('kind'),case.get('state')) for case in cases}
passed=(report.get('pass') is True and len(cases)==6 and actual==expected and
        all(case.get('pass') is True and case.get('sourceWasVisible') is True and
            case.get('noPrematureTarget') is True and case.get('targetOnScreen') is True and case.get('callbackCount')==0
            for case in cases))
print('CONFIRM RACE PASS' if passed else 'CONFIRM RACE FAIL')
for case in cases:
    print(f"{case.get('kind')} {case.get('state')}: {'PASS' if case.get('pass') else 'FAIL'} ({case.get('observedTitle')})")
sys.exit(0 if passed else 1)
PY
