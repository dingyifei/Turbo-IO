# Set up Turbo IO with Claude Code or Codex

**Current iOS route:** RayNeo AI 1.0.21 (1) uses the [ios-addon folder](../ios-addon/README.md). Prepare your own lawful, unencrypted 1.0.21 input, then follow the [flashing guide](../ios-addon/OTA.md) to check the current pinned pair, the single-use authorization and the post-flash cleanup. The old 1.0.6 NAVS3 docs can be viewed with `git show 27ad86e:official-addon/navs3-edition/README.md`; their old gates do not carry over. **AMap (高德) navigation has been removed from the current build.** The [old navigation doc](archive/history/NAVIGATION.md) does not describe a current feature or install path. Never edit a version allowlist to fake compatibility.

The goal is to hand the repetitive work (environment checks, builds, merging and troubleshooting) to a coding assistant, so the developer mainly handles accounts, signing, device confirmation and real-device testing. **This is not a promise that one prompt gets past every install restriction, and it is not a finished-app install service.** For non-commercial study and research only.

## Give the assistant three things first

1. This repository: <https://github.com/dingyifei/Turbo-IO>. It is forked from the upstream project [Turbo1123/Turbo-IO](https://github.com/Turbo1123/Turbo-IO); for builds and flashing, this repository is the reference.
2. **The iOS official addon can use the [explicitly listed stock decrypted inputs](../official-apps/ios/README.md), or a compatible copy you prepare yourself and have the right to use. The current route uses a matching 1.0.21 (1) input. The stock inputs this repo published for 1.0.7 and earlier match only those old versions, and the current build does not accept them. Stock inputs contain no addon; you still merge and sign them yourself.** No decryption or signing is done on your behalf. Installing from the App Store still does not give you an unencrypted Runner.app you can merge, and it cannot skip the version and hash checks.
3. The [full prompt on the front page](../README.md#use-a-coding-assistant), ready to copy, plus your chosen platform. Do not ask the assistant to set up every component at once.

Open your own working folder in a desktop coding assistant and let it read files and run build commands within the scope of the task. For using Codex on a local project, see the [official quickstart](https://learn.chatgpt.com/docs/quickstart). Claude Code works with the same plain-language prompt in the project folder and does not need any cloud account specific to this project. If the assistant can only chat remotely, have it produce a checklist first, then continue in an environment that can reach your development computer; the cloud cannot see your phone on USB.

**Do not send API keys, signing passwords or login verification codes in the prompt as a "third thing".** Enter these only in your own app settings, the local credential store or the interactive signing tool.

## Routes

| Goal | Assistant does first | User provides / confirms | Current bar |
| --- | --- | --- | --- |
| iOS official addon | [Addon guide](../ios-addon/README.md): tests and the zero-key preview first, then a local merge when the conditions are met | A lawful, compatible, unencrypted `Runner.app`, a personal certificate and provisioning profile, and device authorization | Currently 1.0.21 (1); must pass the packager's exact input check. A normal encrypted App Store IPA cannot be merged directly |

The iOS official addon **is not a second, independent Bluetooth client**; it reuses the host app's pairing and recognition. Do not automatically uninstall the official app you are using. A signing conflict may need a separate test device or a recovery plan.

## Recommended setup flow

### 1. Environment and version precheck

The assistant first reports the chosen route, the current source commit, missing tools and the target device. In an existing project it first checks for uncommitted changes and does not overwrite or reset them.

When stock input is needed, iOS uses a lawful, compatible, unencrypted copy that the user prepares separately; keep the original and record its checksums. **Do not treat the "最新版" (latest version) shown on a download page as the version this project supports.** For an unknown version, report the actual version and the reason it was rejected, and wait for a compatible package or a new port. Do not change a SHA/UUID allowlist to fake compatibility, and do not provide or run a decryption bypass.

### 2. Verify first without touching the phone

- On iOS you can build the no-account, no-key preview first.
- If a build is missing an SDK or tool, install it following the platform guide or list what is missing. You do not need to reset the glasses first.
- You do not need to embed any key in the source to run this project. Merged outputs go in an ignored local folder and must not be uploaded to GitHub.

### 3. Signing, install and connection

The assistant can prepare commands and check outputs; the user picks their own certificate, unlocks the device and confirms trust or debugging authorization. Before any real install, restart, uninstall or rebinding, confirm the device and the current task, and keep the recoverable originals and personal data.

On iOS, keeping the Bundle ID does not mean you have the stock push or keychain entitlements. The platform guide is the reference for how to handle this.

### 4. Fill in your own services and start with a minimal test

The official addon keeps the stock ASR. Test first with random text or a short Q&A, then configure the model URL, the model ID and your own key, and turn on TinyFish and the knowledge base as needed.

Once the model answers, test barge-in, wrap-up and file sharing. Accept navigation separately, and only on a platform that still supports it; the current ios107 build does not include AMap navigation. The user confirms the glasses display in person; a success receipt does not replace checking the lens. Do not turn on every paid service or upload long recordings at the start.

## Tasks you can add for the assistant

These goals are appended after the full prompt above. They do not widen the authorization for signing, credentials or device actions:

**Connect the glasses to your own knowledge base**

```text
After the basic phone conversation works, connect my own Codex knowledge base following the doc for the platform I chose.
First ask me which workspace and which data sources you may read. Default to read-only, keep authentication on, and do not expose a bare service.
Use a query with no sensitive content to verify task creation, completion, retrieval on the phone and display on the lens. Do not turn on auto-approve.
```

"Have Claude Code/Codex set it up for me" and "the glasses call a computer agent through Tools" are two different things. The second needs its own bridge, network and permission setup, and the implementation and acceptance differ by platform. A successful Claude Code build does not mean the Claude Code backend is connected.

## What you should end up with

The assistant should give you: the source folder and version, reproducible commands, the outputs or the preview address, the test results, the settings the user must fill in, the items not yet accepted, and how to clean up the processes it started. When it stops at a certificate, a compatible input or a physical confirmation, it should say so exactly, and not claim "all done". It may continue with local steps it is able to do, but it does not confirm the lens, signing or logins on the user's behalf.
