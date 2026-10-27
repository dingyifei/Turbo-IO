#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
started=$SECONDS
inputs=${TURBO_INPUTS:-"$HOME/projects/personal/turboio-inputs"}
mkdir -p "$inputs/locks" "$inputs/baseline"
lock="$inputs/locks/sim.lock"
until mkdir "$lock" 2>/dev/null; do sleep 5; done
trap 'rmdir "$lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bundle=io.turboio.ios107.preview
app="$PWD/build/preview/TurboPreview.app"
shots="$PWD/build/preview-shots"
[[ -x "$app/TurboPreview" ]] || { echo 'PREVIEW SHOOT FAIL: build preview first' >&2; exit 1; }
mkdir -p "$shots"
screens=("$@")
[[ ${#screens[@]} -gt 0 ]] || screens=(hub ota music)
for screen in "${screens[@]}"; do
  case "$screen" in hub|ota|music) ;; *) echo "Unknown preview screen: $screen" >&2; exit 2;; esac
done

udid_file="$inputs/preview-sim.udid"
[[ -s "$udid_file" ]] || { echo 'PREVIEW SHOOT FAIL: missing pinned simulator' >&2; exit 1; }
udid=$(cat "$udid_file")
[[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]] || { echo 'PREVIEW SHOOT FAIL: invalid pinned simulator' >&2; exit 1; }

boot_started=$SECONDS
xcrun simctl bootstatus "$udid" -b
printf 'preview-first-boot real %s\n' "$((SECONDS-boot_started))" >> "$inputs/baseline/timings.txt"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"

for screen in "${screens[@]}"; do
  for lang in en zh-Hans; do
    case "$lang" in en) locale=en_US;; zh-Hans) locale=zh_CN;; esac
    stem="$shots/$screen-$lang"
    : > "$stem.out"
    : > "$stem.err"
    # Remove the prior image so this run cannot pass using a stale screenshot.
    if [[ -e "$stem.png" ]]; then
      mv -f "$stem.png" "$stem.previous.png"
    fi
    xcrun simctl launch --terminate-running-process \
      --stdout="$stem.out" --stderr="$stem.err" "$udid" "$bundle" \
      --screen "$screen" -AppleLanguages "($lang)" -AppleLocale "$locale"
    sleep 4
    xcrun simctl io "$udid" screenshot "$stem.png"
    if [[ ! -f "$stem.png" ]] || [[ $(stat -f %z "$stem.png") -le 20000 ]]; then
      echo "BAD_SCREENSHOT $screen $lang" >&2; exit 1
    fi
    if ! xcrun simctl spawn "$udid" launchctl list | grep -F -- "$bundle" >/dev/null; then
      echo "CRASH $screen $lang" >&2; exit 1
    fi
    if ! grep -q -- "PREVIEW_READY $screen " "$stem.err"; then
      echo "NOT_READY $screen $lang" >&2
      tail -20 "$stem.err" >&2
      exit 1
    fi
  done
done
xcrun simctl terminate "$udid" "$bundle"
# The lifecycle regression acquires the same lock for its own simulator calls.
rmdir "$lock"
trap - EXIT
bash preview/wp5-confirm-test.sh
printf 'preview-shoot real %s\n' "$((SECONDS-started))" >> "$inputs/baseline/timings.txt"
printf 'PREVIEW SHOOT PASS: %s\n' "$shots"
