# Source release notes

> **Historical document, not the current release record.** This page describes how the upstream project released its source between 2026-09 and 2026-10: the Android GUARD-07 exception release, the stock 1.0.5 / 1.0.6 IPA inputs distributed through a separate Release, and the split between the private workspace and the public candidate directory. The text was not updated for later releases, so its paths, releases and gates may no longer apply. The current release record is [ios-addon/RELEASE.md](../ios-addon/RELEASE.md).

Release goal: someone who gets the source can configure and build it from the instructions, without retracing the reverse-engineering work. No personal developer cloud credentials or binding data are provided.

**2026-09-27 release exception:** The [Android GUARD-07 Release](https://github.com/Turbo1123/Turbo-IO/releases/tag/android-105-guard07-tap1-test01) provides a complete unofficial modified APK signed with a separate research key, the TAP1-TEST-01 experimental firmware, and checksums. The APK contains no author account, key, cookie or signing private key, and no WeChat Read web-text adaptation. The public derived APK has not been through another flash acceptance on a real device. iOS still ships no merged IPA; the stock decrypted IPA is only an explicitly listed host input. HarmonyOS ships no HAP and is no longer updated. The general source-export exclusions below do not mean that these separately listed Release attachments do not exist.

## Two directories, kept apart

- Private research workspace: holds historical logs, recordings, screenshots, decompiled material and temporary configuration. It cannot be published as a whole.
- Public candidate directory: source, tests, public docs and build configuration, copied from an explicit allowlist. Its root README is the user-facing version, without internal forensic links.

The research workspace maintainer runs:

```sh
node scripts/export-source.mjs /absolute/new/turbo-io-source
```

The target must be a new directory, outside the workspace, that does not exist yet. The script does not overwrite an old directory, delete originals, create a Git repository, upload anything, or build an IPA or ZIP. If the scan finds something, the script keeps the candidate for inspection and exits with a failure; do not publish in that case. The V1 client and its vendor frameworks, Opus, VAD and ZIPFoundation dependencies were removed from the source tree in cleanup(2), and `DEPENDENCIES.json` was removed with them; they remain in git history.

Check the candidate directory:

```sh
node scripts/check-source.mjs /absolute/new/turbo-io-source
```

The scan prints only the path, line number and rule; it does not print the matched secret. Pattern matching cannot prove that no secrets are present, so also review the code and dependency list by hand and run an independent secret scan. An exposed service credential must be rotated by its owner on the server side; deleting the text from the source does not invalidate the token.

With Gitleaks installed you can also run `gitleaks dir . --redact=100`, and after committing, `gitleaks git . --redact=100`. The repository rules inherit the default detection and exclude only two exact UserDefaults storage key names that are false positives; they do not exclude whole source files or whole dependency directories. The public version uses the neutral `io.turboio` identifier prefix. The maintainer's private Git history and local commit email are not published.

## Exclusions

- IPAs and APKs, pre-signed apps, build caches, xcresult bundles, temporary files, and personal audio, video, image and text logs.
- Private SSH/WDA configuration, device IDs and binding databases, production environment variables, API keys, developer-only hosts, temporary tunnel addresses, signing material, certificates and provisioning profiles.
- Historical research Markdown is not published by default, so that device paths, private quotes and meaningless internal evidence links stay out.
- Vendor and third-party dependencies are labelled separately with their source and license and are not mixed into this project's noncommercial license notice. Whether they ship with the source is decided by the final manifest.

## Pre-release gates

1. Build the local version from the candidate directory and run the unit tests. Confirm that nothing depends on absolute paths in the private workspace.
2. For the device build, check that the dependencies are complete and their versions match. A real phone needs your own signing and configuration; no developer key is provided.
3. Check the source against what is actually distributed, the license and third-party notices, the placeholders in example configuration, and the exclusion of user data and signing material.
4. State the current known issues: the reverse merge still on the to-do list, long-running background work and reliable push, compatibility with more devices and firmware, hardware regression testing of the latest voice configuration, and so on. Do not promise that "any device configuration works".
5. Commit and publish only after the owner confirms where the public repository will be. Generating a candidate directory does not mean it has been published.

The current original content is licensed under PolyForm Noncommercial 1.0.0 and may be used only within the noncommercial scope that license allows. Rights already granted under the earlier MIT license are not revoked retroactively; see [Licensing and earlier versions](LICENSING.md). This source package has no Apple signature and grants no additional license to third-party components.

## Separately listed firmware research attachments

The front page separately lists the [stock IPA input index](../official-apps/ios/README.md): 1.0.6 (218) is a stock decrypted, fully unsigned input, and 1.0.5 (201) keeps its historical attachment form. Neither contains Turbo IO, and neither is a personal pre-signed package. They are distributed only through a separate Release and are not in the source Git history. A merged IPA is still not provided. The firmware research attachments also list their versions, risks and checksums separately; TMIG1 (deleted, see `git show 5b6c63d:firmware-research/strix-1.0.5.5/README.md`) must not be mixed with the historical packages. A change limited to AP content does not mean you can flash only the AP, and it does not guarantee rollback. The stock copyright is unchanged. No personal keys, accounts, signing material or raw device logs have been published.
