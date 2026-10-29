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

# The Apple captions panel is Swift. Build it for the simulator from the same unit lists as
# apple-ai/build.py, plus -DTIO_UI_PREVIEW for its canned fixture entry, and load it at run
# time the way the device build does. Only the Apple panel is built here: the offline panel
# needs FluidAudio, which is not available on the host.
frameworks_dir="$output/Frameworks"
rm -rf "$frameworks_dir"
mkdir -p "$frameworks_dir"
swift_sources=()
while IFS= read -r source; do swift_sources+=("$source"); done < <(python3 - <<'PY'
import re
text=open('apple-ai/build.py').read()
for name in ('UNITS','SHARED'):
    items=re.search(name+r"=\[([^\]]*)\]",text).group(1)
    for unit in re.findall(r"'([A-Za-z0-9]+)'",items):
        print(('apple-ai/src/' if name=='UNITS' else 'local-translation/src/')+unit+'.swift')
PY
)
[[ ${#swift_sources[@]} -gt 0 ]] || { echo 'PREVIEW BUILD FAIL: no Swift sources derived' >&2; exit 1; }
swift_cmd=(xcrun --sdk iphonesimulator swiftc -swift-version 5 -O -parse-as-library
  -DTIO_UI_PREVIEW -target arm64-apple-ios26.0-simulator -sdk "$sdk"
  -emit-library -module-name TurboAppleAI "${swift_sources[@]}"
  -framework FoundationModels -framework Speech -framework Translation -framework AVFoundation
  -Xlinker -install_name -Xlinker @rpath/TurboAppleAI.dylib
  -o "$frameworks_dir/TurboAppleAI.dylib")
printf '%s\n' "${swift_cmd[@]}" > build/preview/swift-cmd.txt
if ! "${swift_cmd[@]}" > build/preview/swift.log 2>&1; then
  grep -E 'error' -A4 build/preview/swift.log >&2 || true
  echo 'PREVIEW BUILD FAIL: Swift captions panel' >&2; exit 1
fi
codesign --force --sign - "$frameworks_dir/TurboAppleAI.dylib"
codesign --force --sign - "$output"
printf 'PREVIEW BUILD PASS: %s (%s seconds)\n' "$output" "$((SECONDS-started))"
