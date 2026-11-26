# Public source validation · 2026-09-24

This run covered only a local Mac build, inference with the pinned models, and synthetic tests. Nothing was installed on a phone, no microphone audio was recorded, the glasses were not touched, and no cloud service key was used.

## Current validation

- The pinned llama.cpp STQ and FluidAudio upstream commits rebuilt cleanly. The build produces an arm64 / iOS 26+ translation dynamic library, and the public host entry point `TIO_LOCAL_TRANSLATION=1` compiles and links in full.
- Swift 6 mode: tests pass for incremental source/translation isolation, deduplication, bounded buffers, UTF-8 display, merging of pre-translations, single-task inference, final-segment priority, and stopping on backlog.
- Synthetic silence test through the same production audio callback: passes for 16 kHz mono / 48 kHz stereo resampling, 158 background callbacks with 158 deliveries, 383,994 output frames, 3 stop/restart cycles, and rejection of late callbacks. This is not an ASR accuracy test.
- Objective-C under ASAN/UBSAN: passes for caption SID/ACK, non-preempting preview, the 0.5 second / 384 byte / 20 minute limits, and the original navigation 3 second / 4 minute limits.
- Native Hy-MT on the Mac: passes for fixed short Chinese and English sentences, streaming prefixes, input/output caps, timeout, cancel, reuse after cancel, 30 consecutive runs, and unload. This does not prove phone latency, heat, or freedom from leaks over long use.
- Swift-to-C++ bridge with the real model: passes for rejecting the original unadapted model, SHA check of the adapted model, streaming prefixes, busy rejection, cancel, recovery, and unload.
- Model downloads are checked against public pinned hashes. The public converter keeps the original GGUF and changes only 225 header fields; the tensor payload stays identical. Models are not stored in Git.
- The packaging entry point requires the module and model parameters to be given together. It does not allow the UI without the module, and it does not allow translation resources to be packed into an ordinary extension by mistake. The existing firmware packaging gate is still in place.
- Resource preflight and copy pass with the actually rebuilt dylib and the pinned model, and the step was checked to refuse overwriting existing resources. The main extension's `test.sh` regression passes. This run did not sign an IPA with a personal certificate and did not install on a real device.

The build still shows compiler warnings from upstream FluidAudio code paths this feature does not use, and the host's existing deprecation warnings. "Build passes" is not a claim that all third-party code is risk-free. The default build and the full public module each need their own device acceptance.

## Earlier device feedback and current unknowns

Users reported success with text translation in earlier private builds and with live English recognition in build 04. The public predecessor, build 05, was installed, but the combined result of the last device probe was not a full pass: the ASR/audio pipeline passed, and the Apple Translation stage returned `CaptionFailure`. Which branch failed is not known.

This run did not repeat any real-device tests. The user must accept each of these separately for the public package: install, signing, login and audio routing; Apple language assets; AirPods; continuous lens display; stopping in the background; long-run memory and heat; and translation quality. Do not treat the "320 ms model chunk", the "500 ms send interval", or Mac file processing time as the real speech-to-lens latency.
