#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
mode=${1:-embedded}
bundle=${2:-com.rayneo.venus.pub}
if [[ ! "$bundle" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$ ]]; then
  echo 'Invalid explicit target Bundle ID' >&2; exit 2
fi
case "$mode" in
  jailbreak) output=build/TurboIOPrivateAddon.dylib; install_name=/var/jb/usr/lib/TweakInject/TurboIOPrivateAddon.dylib ;;
  embedded) output=build/embedded/TurboIOPrivateAddon.dylib; install_name=@rpath/TurboIOPrivateAddon.dylib; mkdir -p build/embedded ;;
  *) echo 'Usage: build.sh [jailbreak|embedded] [target.bundle.id]' >&2; exit 2 ;;
esac
[[ ${TIO_DEV:-0} != 1 ]] || export TIO_IMAGE_RX_LAB=1
[[ ${TIO_MAPKIT_ENABLED:-0} != 1 ]] || export TIO_DISPLAY_PHONE=1
diag=${TIO_DEV:-${TIO_IMAGE_RX_LAB:-0}}
[[ ${TIO_AMAP_ENABLED:-0} != 1 ]] || { echo 'AMap navigation was removed; use TIO_MAPKIT_ENABLED=1' >&2; exit 2; }
nav_options=()
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
link_options=()
if [[ ${TIO_OTA_FLASH_ENABLED:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Flash gate requires separate embedded build' >&2; exit 2; }
  link_options+=(-DTIO_OTA_FLASH_ENABLED=1 -DTIO_OTA_FEED_ARMING_ENABLED=1)
fi
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
image_options=()
if [[ ${TIO_IMAGE_RX_LAB:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Image RX lab is private embedded only' >&2; exit 2; }
  output=build/image-rx-lab/TurboIOPrivateAddon.dylib
  mkdir -p build/image-rx-lab
  image_options=(-DTIO_IMAGE_RX_LAB=1 \
  -framework PhotosUI \
  -framework ImageIO \
  -framework CoreGraphics \
  ImageUpload.m \
  ImageUploadTransport.m \
  ImageUploadNative.m \
  ImageUploadUI.m \
  ClenchLab.m \
  ClenchLabUI.m)
  [[ ${TIO_IMAGE_RX_WIDE:-0} != 1 ]] || image_options+=(-DTIO_IMAGE_RX_WIDE=1)
  # Clench Lab manifests record the build commit: short SHA plus -dirty, else unknown.
  clench_commit=$(git rev-parse --short=12 HEAD 2>/dev/null || true)
  if [[ -n "$clench_commit" && -n "$(git status --porcelain 2>/dev/null | head -n 1)" ]]; then clench_commit="$clench_commit-dirty"; fi
  [[ "$clench_commit" =~ ^[0-9a-f]{7,40}(-dirty)?$ ]] || clench_commit=unknown
  image_options+=("-DTIO_BUILD_COMMIT=\"$clench_commit\"")
fi
# Opt-in diagnostic for the iOS 16 jailbreak injector's chained-fixup stall.
# Keep the normal embedded build unchanged until the device comparison passes.
if [[ ${TIO_DISPLAY_PHONE:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Display phone core is embedded only' >&2; exit 2; }
  image_options+=(-DTIO_DISPLAY_PHONE=1 \
  -DTIO_DISPLAY_DIAGNOSTICS=$diag \
  -DTIO_NATIVE_NAV=1 \
  nav_runtime.c \
  RoadMap.m \
  NativeNavigation.m \
  TNVTransport.m \
  NativeNavigationUI.m \
  display_runtime.c \
  display_client.c \
  display_carrier.c \
  DisplayDelta.c \
  DisplayNavigation.m \
  DisplayHUDRenderer.m \
  DisplayReplyObserver.m \
  DisplayPhoneSession.m \
  DisplayPhoneTransport.m \
  DisplayPhoneUI.m \
  DisplayDiagnostics.m)
fi
if [[ ${TIO_DISPLAY_FLASH:-0} == 1 ]]; then
  [[ ${TIO_DISPLAY_PHONE:-0} == 1 && ${TIO_OTA_FLASH_ENABLED:-0} == 1 && "$mode" == embedded ]] || exit 2
  link_options+=(-DTIO_DISPLAY_FLASH=1)
fi
# Apple Maps navigation panel.
if [[ ${TIO_MAPKIT_ENABLED:-0} == 1 ]]; then
  [[ "$mode" == embedded && ${TIO_DISPLAY_PHONE:-0} == 1 ]] || { echo 'MapKit navigation requires embedded mode and TIO_DISPLAY_PHONE=1' >&2; exit 2; }
  output=build/mapkit/TurboIOPrivateAddon.dylib
  mkdir -p build/mapkit
  nav_options=(-DTIO_MAPKIT_ENABLED=1 \
  -framework MapKit \
  NavigationGuidance.m \
  MapKitNavigationUI.m \
  RoadTiles.m)
fi
if [[ ${TIO_CLASSIC_BINDINGS:-0} == 1 ]]; then
  link_options+=(-Wl,-no_fixup_chains)
fi
apple_options=()
if [[ ${TIO_APPLE_AI:-0} == 1 ]]; then
  [[ "$mode" == embedded ]] || { echo 'Apple AI bridge is embedded only' >&2; exit 2; }
  apple_options=(-DTIO_APPLE_AI=1 -framework Speech AppleAICore.m AppleAI.m AppleAIPanel.m RecordingTranscribe.m NoNetworkTurn.m NoNetworkTurnHost.m -framework Network)
fi
echo "TurboIO profile: $([[ ${TIO_IMAGE_RX_LAB:-0} == 1 ]] && echo dev || echo daily)" >&2
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=16.0 \
  -fobjc-arc \
  -fmodules \
  -dynamiclib \
  -Wall \
  -Wextra \
  -Wno-unused-parameter \
  -Wno-incompatible-pointer-types \
  lang_flag.c \
  lang_store.c \
  knob_calibration.c \
  LanguageFlag.m \
  LanguageFlagRuntime.m \
  MenuLayout.m \
  MenuLayoutUI.m \
  menu_config.c \
  tile_config.c \
  Brightness.m \
  BrightnessCodec.m \
  camera-v1/camera.c \
  camera-v1/CameraLink.m \
  camera-v1/CameraImage.m \
  camera-v1/CameraUI.m \
  camera-v1/CameraProfiles.c \
  camera-v1/CameraCapture.m \
  -framework Photos \
  -framework Foundation \
  -framework NaturalLanguage \
  -framework UIKit \
  -framework Security \
  -framework UniformTypeIdentifiers \
  -framework CoreLocation \
  -framework AVFAudio \
  -framework WatchConnectivity \
  WatchRemoteGate.m \
  WatchGlobalBridge.m \
  remote.c \
  WatchRemoteAddon.m \
  LocalTranslationEntry.m \
  ExperimentalOTA.m \
  ExperimentalOTAGuard.m \
  ExperimentalOTAFlash.m \
  ExperimentalOTAFeed.m \
  ExperimentalOTAUI.m \
  ProtocolContext.m \
  ${nav_options[@]+"${nav_options[@]}"} \
  ${image_options[@]+"${image_options[@]}"} \
  ${apple_options[@]+"${apple_options[@]}"} \
  "-DTIO_TARGET_BUNDLE_ID=\"$bundle\"" -install_name "$install_name" ${link_options[@]+"${link_options[@]}"} \
  -I. \
  Core.m \
  TIOLanguage.m \
  TIOTextLanguage.m \
  Localization.m \
  KnowledgeClient.m \
  KnowledgeUI.m \
  HomeTabLayout.m \
  HomeTabBridge.m \
  ResearchCatalog.m \
  TIODesign.m \
  ResearchUI.m \
  TIOConfirm.m \
  OTAWizardModel.m \
  PrivateBootstrap.m \
  WebSearch.m \
  GlassesChannelHook.m \
  TodoProtocol.m \
  TodoRuntime.m \
  AppPackage.m \
  AppTransport.m \
  AppBridge.m \
  AppUI.m \
  app.c \
  app_command.c \
  app_runner.c \
  app_store.c \
  app_view.c \
  EditorModel.m \
  EditorCodec.m \
  EditorTransport.m \
  EditorCanvas.m \
  EditorCrop.m \
  EditorUI.m \
  EditorAI.m \
  EditorBackend.m \
  EditorBackendUI.m \
  editor.c \
  DashboardCard.m \
  DashboardPhone.m \
  card.c \
  A2UIProtocol.m \
  A2UIProbe.m \
  SubtitleHUDCore.m \
  SubtitleHUD.m \
  GlassesLogContract.m \
  GlassesLogGate.m \
  GlassesLogProbe.m \
  RecordingExports.m \
  RecordingExportsUI.m \
  RecordingExportsMenu.m \
  RecordingText.m \
  RecordingTextUI.m \
  RecordingTextMenu.m \
  AlwaysOnAudioFiles.m \
  AlwaysOnOgg.m \
  AlwaysOnAudioNative.m \
  AlwaysOnAudioUI.m \
  TDPhoneStore.m \
  TDPhoneRun.m \
  TDPhoneUI.m \
  TDPhoneReply.m \
  TDPhoneBridge.m \
  TIOGlassesFileTransport.m \
  diagnostics.c \
  command.c \
  FocusBridge.m \
  focus.c \
  -lz \
  VoiceTTS.m \
  VoiceTTSText.m \
  SpotifyHTTP.m \
  SpotifyLyrics.m \
  SpotifyAuth.m \
  SpotifyAPI.m \
  SpotifyCover.m \
  SpotifySignIn.m \
  MusicBridge.m \
  MusicPlayer.m \
  MusicUI.m \
  music.c \
  -framework AVFoundation \
  -framework AuthenticationServices \
  -framework Network \
  -framework CoreImage \
  -framework ImageIO \
  Addon.m \
  -o "$output"
codesign --force --sign - "$output"
plutil -lint TurboIOPrivateAddon.plist
shasum -a 256 "$output"
