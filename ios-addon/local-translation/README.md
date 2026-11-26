English | [中文](README-zh.md)

# Local translation and offline English captions · iOS 26+

2026-09-24. An original implementation of the public OFFLINE-ENGLISH-05 build. It offers **Apple local translation, Hy-MT2 local translation, or English only**. It runs on the iPhone and loads no large model on the glasses. It **needs no firmware flash and no service key**. No signed IPA and no model bundle are provided for download.

## What it does

| Part | Implementation and limits |
| --- | --- |
| Text translation | Apple system Translation, or Hy-MT2-1.8B-1.25Bit GGUF; the current UI translates between Chinese and English |
| Offline English ASR | Parakeet Realtime EOU 120M CoreML / FluidAudio, 320 ms model chunks; this is not a 320 ms end-to-end latency, and it is not Chinese ASR |
| Audio input | The phone microphone, or an AirPods/Bluetooth HFP input that the system actually lists; a route change stops capture instead of switching silently |
| Caption translation | "Fast pre-translation" (快速预译) is on by default: after about 6 recognized words it tries a short prefix and keeps the trailing context; Hy-MT streams its output, Apple returns a whole result for each prefix |
| Lens sync | The stock caption display-only channel, service 19: set → match the SID receipt → text → exit; the stock recording uplink is not started |
| Runtime limits | Foreground only, started by the user; leaving the page, going to the background, an interruption or an input route change stops it; 20-minute guard |

Pre-translation gets corrected; it is not simultaneous interpretation. Only one translation task runs at a time, at most 4 final segments wait, and audio holds at most 32 buffers; a backlog reports an explicit error. Glasses output is throttled to one send per 0.5 seconds, with a 384-byte frame limit, a single pending packet, and the latest content merged in. The old navigation limits of 3 seconds / 80 frames / 4 minutes are unchanged.

**Not included**: directional raw capture from the glasses ("front"/"surround"), a settings UI for custom cloud ASR or live translation, multilingual offline ASR, unlimited background recording, automatic saving of transcripts or audio, and a cloud fallback on failure. A working Bluetooth HFP input does not mean the glasses' proprietary directional protocol is implemented.

## 1. Prepare the dependencies

You need an Apple Silicon Mac, CMake, Python 3.10+, Node.js and full Xcode (this run used the iOS 27 SDK and Swift 6.4 in Swift 6 language mode; the minimum target is iOS 26). You need enough disk and memory: the models are about 462 MB + 224 MB, and the compatibility conversion keeps the originals, so the download directory exceeds 1 GB. Runtime memory also includes compute buffers, caches and the host app, so the weight size is not the peak RAM.

Read the [third-party licenses](THIRD_PARTY.md) first. Run the commands below from the repository root. The directories must be new; do not overwrite an existing experiment:

```sh
mkdir -p ios-addon/local-translation/work
git clone https://github.com/sjl623/llama.cpp.git ios-addon/local-translation/work/llama.cpp
git -C ios-addon/local-translation/work/llama.cpp checkout --detach 1e411d8f5a1e23525fa3265dfb4bd76265465397
git clone https://github.com/FluidInference/FluidAudio.git ios-addon/local-translation/work/FluidAudio
git -C ios-addon/local-translation/work/FluidAudio checkout --detach eabcd9e36dab48f1f7180165396d84b9688650e0
python3 ios-addon/local-translation/models.py \
  --out ios-addon/local-translation/work/models --accept-model-licenses
```

The downloader fetches only fixed public versions and checks each file's length and SHA-256. On failure it keeps the `.download` file for inspection; retry with a new output directory. Do not swap in other weights under the same file names to get past the check. Apple language packs are not downloaded here: in the app, tap "Prepare Apple language packs" (准备 Apple 语言包) and explicitly agree to the system download. Offline translation works only after that.

## 2. Build the translation module and the host entry

```sh
python3 ios-addon/local-translation/build.py \
  --llama ios-addon/local-translation/work/llama.cpp \
  --fluid ios-addon/local-translation/work/FluidAudio \
  --out ios-addon/local-translation/work/module
TIO_LOCAL_TRANSLATION=1 bash ios-addon/build.sh embedded
python3 ios-addon/local-translation/test.py
```

The first command produces `module/TurboCaptionTranslation.dylib` and its resources; it uses no developer certificate. The second produces `ios-addon/build/local-translation/TurboIOPrivateAddon.dylib`, which adds the "TurboIO → Library → Apple / Hy-MT2 local translation" entry. The default build has no such entry, and older iOS versions do not load the 26+ module. You can combine it with the existing navigation and music build switches, but each still follows its own firmware gate, and none of this authorizes a flash.

Hy-MT uses a fixed STQ CPU/ARM NEON kernel, not a Metal or ANE backend. The default thread count is at most 6, selectable up to 8 but never above the device's core count. It keeps thermal and low-power step-down, cancellation, a 15-second per-call timeout, a 1024-token context, a 384-token output limit, and release on exit.

## 3. Sign and package it yourself

Follow the [host version and signing notes](../README.md). You need a legally obtained, unencrypted thin-arm64 `Runner.app` that passes the repository checks; this document does not describe decryption. The private predecessor was tested with the official iOS host 1.0.5 (201) on an iPhone Air; do not extrapolate directly to other versions.

```sh
node ios-addon/package.mjs \
  --app /absolute/Runner.app \
  --addon /absolute/Turbo-IO/ios-addon/build/local-translation/TurboIOPrivateAddon.dylib \
  --translation-module-dir /absolute/Turbo-IO/ios-addon/local-translation/work/module \
  --translation-models /absolute/Turbo-IO/ios-addon/local-translation/work/models \
  --profile /absolute/your.mobileprovision \
  --identity YOUR_CERTIFICATE_SHA1 \
  --device YOUR_DEVICE_ID \
  --out /absolute/new-local-output
```

Replace the placeholder paths and signing arguments with your own. **Do not enter the maintainer's account.** The packager checks that the entry and resources match, verifies the model hashes, copies only the files it lists explicitly, and refuses to overwrite translation resources already in the host. It adds the dylib, models and resources before the existing signing step. This command does not install anything, does not flash the glasses, and does not grant you entitlements your certificate does not have. You still have to check the full package with your own certificate on your own device.

## 4. Use it on the phone

1. Open "TurboIO → Library → Apple / Hy-MT2 local translation". Test a short sentence first. For Apple, prepare the language packs first; Hy-MT verifies the bundled on-device model automatically.
2. Tap the microphone at the top right to enter "Offline English captions" (英语离线字幕). Choose English only or a translation engine, the input device, and whether to sync to the glasses.
3. First stop other tasks such as music, TTS, conversation, recording and navigation. Then tap start yourself and allow the microphone. The first model check and load can take a few seconds.
4. With lens sync on, wait for this session's SID success receipt. If it fails, turn lens sync off and test capture on the phone first. It does not seize the official session.
5. Speak English. The English text appears first, then the translation marked "pre-translation" (预译). For steadier output, turn off "Fast pre-translation". Stopping or leaving the page cancels capture and translation.

Other features of the official app may still use the network. "Local translation" means only that this recognition and translation chain has no cloud fallback; it does not mean the whole host app is offline.

## Validation and known issues

- Private predecessor: the user confirmed that text translation works and that real English recognition in build 04 was very good; build 05 is installed. Do not take this feedback as a full device acceptance of this public package.
- Historical device combination probe for build 05: the audio callback and ASR passed, but the Apple translation stage returned `CaptionFailure`. The error branch was not identified, and the language resources may need checking. **We do not claim the combination probe fully passed.**
- The build and test results for this public release are in [VALIDATION.md](VALIDATION.md). No user phone or glasses were touched.
- AirPods and other Bluetooth microphones, long-run heating, real lens latency and multilingual quality still need dedicated acceptance. Zero latency is not promised.
- This is a new, separate caption entry. It does not replace every behavior of the official translation page. Under memory pressure, thermal limits or a backlog it stops or steps down instead of forcing itself to keep running.

Original code follows the repository's non-commercial license; third-party models and dependencies keep their own licenses, see [THIRD_PARTY.md](THIRD_PARTY.md). Do not upload keys, cookies, personal prompts, model weights, signing material or IPAs.
