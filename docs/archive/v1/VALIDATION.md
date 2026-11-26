# Source Release Validation

> Archived: the V1 client code (apps, core-probe, codex-bridge, display-observer, rayneo-session, rayneo-archive, third-party) was removed from the source tree in cleanup(2) and remains in git history. This file is a record only; its commands and paths no longer work.

Date: 2026-09-08. Validation ran from a standalone source directory with no build dependency on the private research workspace, using Xcode 27.0, XcodeGen 2.45.4 and Node.js 26.3.0.

## Completed

- Device target `RayNeoCompanionDevice`: built unsigned from a fresh DerivedData, using only the dependencies shipped with the source. This is not an install or lens acceptance check.
- Simulator app unit tests: 214 passed, 0 failed. They cover the explicit ASR host, rejection of invalid addresses, key-service isolation and the notification-name migration.
- Simulator UI smoke test: the custom notification test page and system Reminders import/dedup. The log shows 2 cases passed, 0 failed. The Xcode beta stalled in the report wrap-up after the cases finished; this run killed the wrap-up process and got no complete xcresult. It does not count as a full green UI runner, and it does not replace on-device checks of notification delivery or system permission prompts.
- Node bridge / display observer tests: 23 passed, 0 failed.
- Standalone Swift package tests: protocol 94, session 82, session-runtime 35, display 121, archive 39, audio-container 21, transport-ios 53; 445 passed in total.
- Vendor frameworks, Opus, VAD and ZIPFoundation: per-file SHA-256 recorded in `DEPENDENCIES.json`.

## Release privacy check

### Skill and license update (2026-09-08)

- The `turbo-io` skill passed structure validation. Skills 1.5.24 installed it into the Codex and Claude Code directories inside an isolated temporary project; all five skill files matched one by one, and the maintainer's global skills were not modified.
- The local link check on the README, skill and license docs passed. The root license matches the license shipped with the skill; both are the original PolyForm Noncommercial 1.0.0 text. Third-party licenses were not replaced.
- The Node bridge / display observer tests were re-run in this round: 23 passed. The source release rules and a Gitleaks directory scan found nothing.
- This round changed only the skill, licenses and docs. It did not re-check the iOS build, signing, hardware or cloud APIs, and a successful skill install is not taken to mean that both assistants can run the full on-device flow by themselves.

A fresh source directory was generated from the research workspace through an allowlist. It carries no original Git history, user containers, recordings, chats, raw logs, device IDs, signing material or private configuration. The public namespace is separate from the maintainer's original test app.

The source rule scan, Gitleaks default rules (plus exclusions for two false positives on exact settings key names) and a printable-strings scan of the vendor binaries found no credentials. Checks for the maintainer's personal cloud host and personal identifiers found nothing left behind. The original vendor binaries may contain their upstream build paths; these are not the maintainer's private directories. The vendor ABI was not rewritten, and the vendor binaries are not presented as self-developed open-source libraries.

Scanning cannot prove that no secret or vulnerability in an unknown format exists. Any key that was ever shared outside the repository should be rotated by its owner; redaction for release does not revoke old keys. Do not commit your own real configuration, recordings or debug dumps to a public repository.

## On-device confirmation and acceptance limits

- The user confirmed that on-device acceptance passed on a non-jailbroken device. This confirmation does not extend to every phone, every firmware or every feature.
- The release build was not run with the maintainer's cloud key. Users who fill in their own host / key must test the real APIs, audio and background behavior themselves.
- This does not mean Claude Code, Hermes Agent, OpenClaw or WorkBuddy are integrated, nor that every glasses feature has been fully verified.
- No IPA, Apple signing, credentials, personal recordings or raw research logs are provided.

A successful build, a protocol acknowledgement, a real display and long-running background operation are different levels of evidence. Known issues and unverified features are listed in the root README; the source release does not change their status.
