# Turbo IO: how it works

> Archived: the V1 client code (apps, core-probe, codex-bridge, display-observer, rayneo-session, rayneo-archive, third-party) was deleted from the source tree in cleanup(2) and is kept in git history. This page is a record only. Its commands and paths no longer work.

## In one sentence

The glasses are treated as a wearable input and display device. The iPhone handles the connection, audio and sessions; cloud services handle recognition and answers; a computer runs Codex tasks. The product does not modify the glasses firmware, and it does not use jailbreak scripts to read the official app's sandbox.

## 1. Start from observed behavior, not from guessing the protocol

The research is based on the user's own devices and the official app material the user provided. We first look statically at resources, symbols, serialized structures and call relationships, then check them against real actions and logs in the official app. Events are told apart by business type, message type, direction, session ID, length and time, so that neighboring log lines are not mistaken for the same feature.

Each feature is verified separately: initiated by the phone, initiated by the glasses, accepted for sending by the SDK, acknowledged by the device, and the actual effect on the lens or in sound. A passing unit test or success in the official app does not count as success in the new app. Intrusive observation once affected stability, so debugging prefers non-injecting logs and our own receive path.

## 2. Reuse the communication core first and ship the product

The current working route reuses RayneoNet and the other communication dependencies, and manages pairing inside our own bundle, signature and container. Business adapters receive and send protobuf, JSON and other messages. This lets us verify voice, recording, display and reverse operations first, instead of waiting until the whole lower layer is rewritten.

`core-probe` holds both historical probes and the implementation that the current device build reuses. The recovered interfaces are coupled to versions and ABI. A replacement library must be verified again; renaming a file or assuming that all versions behave the same is not enough. Ordinary development signing has been used on the test device, and the user later confirmed that on-device acceptance also passed on a non-jailbroken device. A different device or a different vendor library version still needs a compatibility check.

In parallel, the logic that can be pinned down is split into Swift packages: protocol (frames and calculations), transport (a byte channel over the public API), session (sessions), display (business types), archive (copies and revisions) and audio-container (structure checks). They exist for testing and for step-by-step replacement. The current app's success is not presented as a finished, self-contained pure-Swift SDK.

## 3. Voice is a continuous session, not a single request

```text
Glasses wake → audio → phone decodes → cloud ASR / VAD
                                       ├─ recognized text → top half of the lens
                                       └─ valid end of sentence → DeepSeek
                                                                  └─ streamed answer → bottom half of the lens

Valid new sentence within the session → cancel the old model call / bump the send generation → new round
Model stream ended and the completion message submitted → silence timer → close the page → stay on standby
```

Cloud ASR output and model output can exist at the same time. A valid new sentence triggers an interruption; not every empty event may trigger a new request. Each round has its own ID and protection against late callbacks, and after a disconnect, content from an old round must not reach the new connection.

"Model EOF", "text handed to the SDK", "lens finished displaying" and "TTS finished playing" are different events. The phone-side close timer currently starts after the text stream finishes, but there is no verified lens-render-complete ACK. Our own TTS does not yet close the product loop.

There is research evidence that the official app has local Sherpa/Zipformer and cloud ASR. Turbo IO's default path currently uses the user's cloud ASR and does not claim to reproduce the official app's full arbitration.

## 4. Recordings: keep the original first, then derive text

An ordinary glasses recording goes through receiving, offset and end handling, writing the raw packets to disk, container handling and decoding, then checking and archiving. Only a manual transcription by the user sends the converted audio to the user's own ASR. The voice-chat timeline stores text events and must not be confused with the recording library.

Once, the service returned "task-finished" with an empty result. Comparing the left and right channels of the same recording with the PCM actually uploaded showed that the uploaded side was close to silent. The fix was to mix both channels with equal weight and then convert to 16 kHz mono, rather than changing the error message or switching APIs blindly. This approach has its own edge cases, such as phase cancellation, and must not be advertised as universally lossless.

A copy hash proves only the local copy. An Ogg CRC proves only the subset of the structure the checker covers. Decodable does not mean the content is correct. A finished transcription does not mean the file has reached the NAS or Obsidian. Each layer records its state separately, and derived files never overwrite the original audio.

"全天智记" (all-day Lifelog) has a different lifecycle and its own real-time and cached messages; conclusions about ordinary recordings do not carry over to it. So far only time-limited raw packets and decoding/recognition experiments are done. Proper long-duration segmentation, re-upload and archiving are still in development.

## 5. Codex: the model picks the tool, the computer runs it

DeepSeek receives only three function tools: `codex_message`, `codex_status` and `codex_stop`. The phone checks the arguments and the current task, then calls a restricted HTTPS bridge on the computer. The bridge starts a separate Codex app-server and manages threads and turns over stdio JSON-RPC. It does not take over the current desktop chat.

A task being accepted does not mean it is done. Completed, failed and needs-confirmation events are produced on the computer; the phone polls them, removes duplicates, and shows a summary through a glasses business notification. This is not MCP, and there is no APNs or guaranteed delivery during long offline periods. A notification does not approve a task. When confirmation is needed, the user handles it on the phone; the model has no tool to approve automatically.

This stdio event architecture follows the [Codex App Server docs](https://learn.chatgpt.com/docs/app-server). This project's `/v1/*` is a custom wrapper, not an official HTTP API. The binary and schema change between versions and must be tested after every upgrade.

## 6. Display observation is not a screenshot

Our own receive path extracts an allowlist (`glass_preview`, raw screen-state values, business type and length, and similar) into a time-limited in-memory snapshot. The Mac reaches the phone's loopback interface through USB forwarding, and a browser redraws the page.

The green-on-black text, dialogs and one-app-icon-per-page view are a maintainable SVG/HTML layout. Real page reports, text the app has submitted, and style demos are labeled separately. No usable framebuffer or lens screenshot stream has been found, so this page is not advertised as a screen mirror.

## 7. Why connection and voice are kept separate

An app update ends the process. If the reconnect timer were tied to voice standby, a user who turned voice off might be unable to recover the connection without help. So maintenance of an existing paired connection is independent of ASR and recording: it picks the single existing pairing, fetches the current object again from the SDK, and backs off a limited number of times. It never silently re-pairs or grabs another target.

Background mode allows some system behaviors but does not guarantee that a timer keeps running. Force quit, suspension, long screen lock, radio disconnects and reopening after an upgrade each need their own acceptance check.

## 8. The most important gaps now

Merging the to-do completion sent back from the glasses still has an unfixed problem. The following still need verification: the full file picker for sharing, finishing the latest voice turn, long-term background running, compatibility with more devices and firmware, our own TTS, turning "全天智记" (all-day Lifelog) into a product, and automatic NAS import. The source is open for reproducibility and collaboration. A research prototype is not presented as a general SDK that covers every hardware edge case.
