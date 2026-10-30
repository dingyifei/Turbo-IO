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
[[ ${#screens[@]} -gt 0 ]] || screens=(hub ota music tiles layout layout-tmg7 runtime knob voice nav nav-active captions push-focus push-camera push-developerApps push-dashboardEditor editor-draft editor-ai editor-crop push-recordings push-subtitleHUD push-imageRXLab push-clenchLab)
for screen in "${screens[@]}"; do
  case "$screen" in hub|ota|music|tiles|layout|layout-tmg7|runtime|knob|voice|nav|nav-active|captions|tokens|push-*|editor-*) ;; *) echo "Unknown preview screen: $screen" >&2; exit 2;; esac
done

# The matrix every screen is shot in (tmg4-check.py asserts the same one):
#   en and zh-Hans x light and dark at the default text size, then one accessibility
#   content-size pass (en, light, accessibility-extra-extra-extra-large).
# Stems: <screen>-<lang>-<appearance> and <screen>-en-light-ax.
appearances=(light dark)
standard_size=large
ax_size=accessibility-extra-extra-extra-large

udid_file="$inputs/preview-sim.udid"
[[ -s "$udid_file" ]] || { echo 'PREVIEW SHOOT FAIL: missing pinned simulator' >&2; exit 1; }
udid=$(cat "$udid_file")
[[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]] || { echo 'PREVIEW SHOOT FAIL: invalid pinned simulator' >&2; exit 1; }

boot_started=$SECONDS
xcrun simctl bootstatus "$udid" -b
printf 'preview-first-boot real %s\n' "$((SECONDS-boot_started))" >> "$inputs/baseline/timings.txt"

# Appearance and text size are simulator-wide: remember them and put them back when done.
orig_appearance=$(xcrun simctl ui "$udid" appearance 2>/dev/null || true)
orig_size=$(xcrun simctl ui "$udid" content_size 2>/dev/null || true)
restore_ui() {
  [[ "$orig_appearance" =~ ^(light|dark)$ ]] && xcrun simctl ui "$udid" appearance "$orig_appearance" >/dev/null 2>&1 || true
  [[ -n "$orig_size" && "$orig_size" != "unsupported" ]] && xcrun simctl ui "$udid" content_size "$orig_size" >/dev/null 2>&1 || true
}
cleanup() { restore_ui; rmdir "$lock"; }
trap cleanup EXIT

xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl install "$udid" "$app"
# The navigation panel asks for location on appear; grant it so no system alert covers the shot.
xcrun simctl privacy "$udid" grant location "$bundle"
container=$(xcrun simctl get_app_container "$udid" "$bundle" data)

shoot() { # screen lang stem
  local screen=$1 lang=$2 stem=$3 locale settle=4
  case "$lang" in en) locale=en_US;; zh-Hans) locale=zh_CN;; esac
  case "$screen" in nav|nav-active) settle=7;; esac # map tiles
  : > "$stem.out"
  : > "$stem.err"
  # Remove the prior image so this run cannot pass using a stale screenshot.
  if [[ -e "$stem.png" ]]; then
    mv -f "$stem.png" "$stem.previous.png"
  fi
  rm -f "$container/Documents/ui-report.json"
  xcrun simctl launch --terminate-running-process \
    --stdout="$stem.out" --stderr="$stem.err" "$udid" "$bundle" \
    --screen "$screen" --report -AppleLanguages "($lang)" -AppleLocale "$locale"
  sleep "$settle"
  # A loaded machine can start the app slowly: wait for the report the app writes once it is ready.
  for _ in $(seq 1 30); do [[ -s "$container/Documents/ui-report.json" ]] && break; sleep 1; done
  xcrun simctl io "$udid" screenshot "$stem.png"
  cp "$container/Documents/ui-report.json" "$stem.json"
  if [[ ! -f "$stem.png" ]] || [[ $(stat -f %z "$stem.png") -le 20000 ]]; then
    echo "BAD_SCREENSHOT $stem" >&2; exit 1
  fi
  if ! xcrun simctl spawn "$udid" launchctl list | grep -F -- "$bundle" >/dev/null; then
    echo "CRASH $stem" >&2; exit 1
  fi
  if ! grep -q -- "PREVIEW_READY $screen " "$stem.err"; then
    echo "NOT_READY $stem" >&2
    tail -20 "$stem.err" >&2
    exit 1
  fi
}

# Shots from before the appearance axis used <screen>-<lang>; drop them so none is mistaken for current.
for screen in "${screens[@]}"; do rm -f "$shots/$screen-en".* "$shots/$screen-zh-Hans".*; done
xcrun simctl ui "$udid" content_size "$standard_size"
for appearance in "${appearances[@]}"; do
  xcrun simctl ui "$udid" appearance "$appearance"
  for screen in "${screens[@]}"; do
    for lang in en zh-Hans; do
      shoot "$screen" "$lang" "$shots/$screen-$lang-$appearance"
    done
  done
done
xcrun simctl ui "$udid" appearance light
xcrun simctl ui "$udid" content_size "$ax_size"
for screen in "${screens[@]}"; do
  shoot "$screen" en "$shots/$screen-en-light-ax"
done
xcrun simctl ui "$udid" content_size "$standard_size"

python3 preview/tmg4-check.py "$shots" "${screens[@]}"
xcrun simctl terminate "$udid" "$bundle"
restore_ui
# The lifecycle regression acquires the same lock for its own simulator calls.
rmdir "$lock"
trap - EXIT
bash preview/wp5-confirm-test.sh
printf 'preview-shoot real %s\n' "$((SECONDS-started))" >> "$inputs/baseline/timings.txt"
printf 'PREVIEW SHOOT PASS: %s\n' "$shots"
