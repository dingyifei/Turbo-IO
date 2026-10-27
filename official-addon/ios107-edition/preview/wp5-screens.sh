#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
E=$PWD
IN=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
mkdir -p "$IN/locks" "$IN/overnight/logs/wp5" "$E/build/wp5"
LOCK="$IN/locks/sim.lock"
until mkdir "$LOCK" 2>/dev/null; do sleep 5; done
trap 'rmdir "$LOCK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -r "$IN/preview-sim.udid" ]] || { echo 'WP5 SCREENS FAIL: missing pinned preview-sim.udid' >&2; exit 1; }
DEV=$(cat "$IN/preview-sim.udid")
[[ "$DEV" =~ ^[0-9A-Fa-f-]{36}$ ]] || { echo 'WP5 SCREENS FAIL: invalid pinned UDID' >&2; exit 1; }

APP_REL=$(sed -n 's/^output=//p' preview/build.sh | head -1)
[[ -n "$APP_REL" ]] || { echo 'WP5 SCREENS FAIL: preview/build.sh has no output path' >&2; exit 1; }
APP="$E/$APP_REL"
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' preview/Info.plist)
[[ -x "$APP/TurboPreview" ]] || { echo 'WP5 SCREENS FAIL: build the ad-hoc preview app first' >&2; exit 1; }

OUT="$IN/overnight/logs/wp5/shots"
[[ ! -L "$OUT" ]] || { echo 'WP5 SCREENS FAIL: shots path is a symlink' >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
SCREEN_LOG="$E/build/wp5/screens.txt"
CHECK_LOG="$E/build/wp5/screens-check.txt"
STDOUT_IS_SCREEN_LOG=0
if [[ -e "$SCREEN_LOG" ]] && python3 - "$SCREEN_LOG" <<'PY'
import os,sys
stdout=os.fstat(1)
target=os.stat(sys.argv[1])
sys.exit(0 if (stdout.st_dev,stdout.st_ino)==(target.st_dev,target.st_ino) else 1)
PY
then
    STDOUT_IS_SCREEN_LOG=1
else
    : > "$SCREEN_LOG"
fi

xcrun simctl boot "$DEV" || true
xcrun simctl bootstatus "$DEV" -b
xcrun simctl uninstall "$DEV" "$BID" || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl status_bar "$DEV" override --time 9:41 --batteryLevel 100 --cellularBars 4

shoot() {
    local name=$1 lang=$2 locale apple_lang stem container
    shift 2
    case "$lang" in
      en) locale=en_US; apple_lang=en ;;
      zh) locale=zh_CN; apple_lang=zh-Hans ;;
      *) echo "Unknown language: $lang" >&2; return 2 ;;
    esac
    stem="$OUT/$name-$lang"
    xcrun simctl terminate "$DEV" "$BID" || true
    container=$(xcrun simctl get_app_container "$DEV" "$BID" data)
    rm -f "$container/Documents/ui-report.json" "$stem.png" "$stem.json"
    xcrun simctl launch --stdout="$stem.out" --stderr="$stem.err" "$DEV" "$BID" "$@" --report \
        -AppleLanguages "($apple_lang)" -AppleLocale "$locale"
    python3 -c 'import time; time.sleep(3)'
    xcrun simctl io "$DEV" screenshot "$stem.png"
    [[ -f "$container/Documents/ui-report.json" ]] || { echo "WP5 SCREENS FAIL: missing fresh report for $name-$lang" >&2; return 1; }
    cp "$container/Documents/ui-report.json" "$stem.json"
}

fixtures=(unavailable missing-key auto-on ready-download download-open stale-version ready-authorize authorized installing failed)
for lang in en zh; do
    shoot hub "$lang" --hub
    shoot hub-dev "$lang" --hub --expand-developer --scroll-bottom
    shoot more "$lang" --hub --push assistantMore
    shoot lifelog "$lang" --hub --push lifelog
    for fixture in "${fixtures[@]}"; do
        shoot "ota-$fixture" "$lang" --ota-wizard --ota-fixture "$fixture"
    done
done
xcrun simctl terminate "$DEV" "$BID" || true

set +e
python3 preview/wp5-check.py "$OUT" | tee "$CHECK_LOG"
check_statuses=("${PIPESTATUS[@]}")
set -e
if [[ "$STDOUT_IS_SCREEN_LOG" == 0 ]]; then
    cp "$CHECK_LOG" "$SCREEN_LOG"
fi
if (( check_statuses[0] != 0 || check_statuses[1] != 0 )); then
    exit 1
fi

# Step 17 still opens this legacy path. Copy only after the new matrix passes.
MIRROR="$E/build/wp5-screens"
rm -rf "$MIRROR"
mkdir -p "$MIRROR"
cp "$OUT"/*.png "$OUT"/*.json "$MIRROR"/
printf 'WP5 SCREENS PASS: %s\n' "$OUT"
