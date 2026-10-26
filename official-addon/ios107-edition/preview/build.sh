#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
started=$SECONDS
output=build/preview/TurboPreview.app
mkdir -p "$output"

# Remove only the AMap branch before deriving every product input.
awk '/TIO_AMAP_ENABLED:-0\} == 1 \]\]; then/{skip=1;next} skip&&/^fi$/{skip=0;next} !skip' \
  build.sh > build/preview/build-sh.filtered
if grep -q -- '-framework AMap' build/preview/build-sh.filtered; then
  echo 'PREVIEW BUILD FAIL: AMap frameworks survived filtering' >&2
  exit 1
fi
grep -oE '[A-Za-z0-9_./-]+\.(m|c)\b' build/preview/build-sh.filtered \
  | awk '!s[$0]++' > build/preview/sources.txt
grep -oE '\-framework [A-Za-z]+' build/preview/build-sh.filtered \
  | awk '!s[$0]++' > build/preview/frameworks.txt
sources=()
while IFS= read -r source; do
  [[ -f "$source" ]] || { echo "PREVIEW BUILD FAIL: missing source $source" >&2; exit 1; }
  sources+=("$source")
done < build/preview/sources.txt
frameworks=()
while read -r flag framework; do
  frameworks+=("$flag" "$framework")
done < build/preview/frameworks.txt
[[ ${#sources[@]} -gt 0 && ${#frameworks[@]} -gt 0 ]] || {
  echo 'PREVIEW BUILD FAIL: empty derived input list' >&2; exit 1;
}

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
cmd=(xcrun --sdk iphonesimulator clang
  -target arm64-apple-ios16.0-simulator -isysroot "$sdk"
  -fobjc-arc -fmodules -Wno-deprecated-declarations -Wno-incompatible-pointer-types
  -DTIO_UI_PREVIEW=1 -DTIO_MAPKIT_ENABLED=1
  -DTIO_IMAGE_RX_LAB=1 -DTIO_IMAGE_RX_WIDE=1
  -DTIO_DISPLAY_PHONE=1 -DTIO_DISPLAY_DIAGNOSTICS=1 -DTIO_NATIVE_NAV=1
  -DTIO_DISPLAY_FLASH=1 -DTIO_OTA_FLASH_ENABLED=1 -DTIO_OTA_FEED_ARMING_ENABLED=1
  '-DTIO_TARGET_BUNDLE_ID="com.rayneo.venus.pub"'
  -I. "-I$sdk/usr/include/libxml2"
  "${sources[@]}" preview/Main.m preview/PreviewFixtures.m
  "${frameworks[@]}" -lz -lsqlite3 -lxml2
  -o "$output/TurboPreview")
# One exact argument per line; the command is executed from the array below.
printf '%s\n' "${cmd[@]}" > build/preview/link-cmd.txt
"${cmd[@]}"
cp preview/Info.plist "$output/Info.plist"
codesign --force --sign - "$output"
printf 'PREVIEW BUILD PASS: %s (%s seconds)\n' "$output" "$((SECONDS-started))"
