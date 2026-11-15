# Flashing Turbo firmware

## What this covers

This guide flashes Turbo firmware onto the RayNeo iO glasses from the Turbo phone build, through RayNeo's own updater. You do every step yourself, on your own iPhone. Agents never install the app or flash the glasses. Flashing is high risk: a bad flash can leave the glasses unusable, and recovery is not guaranteed.

## Current pair: C20 + TMG12

| | |
|---|---|
| Phone build | C20: RayNeo AI 1.0.21 (1), full build |
| Firmware | TMG12: TMG11 ported to stock Strix OS 1.0.6.11 |
| ZIP | `StrixOS-1.0.6.11-TurboIO-TMG12-CANDIDATE-NOT-APPROVED.zip` |
| ZIP size | 9,549,211 bytes |
| ZIP SHA-256 | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| Glasses must report | Strix OS 1.0.5.12 or Strix OS 1.0.6.11 |
| Target version | Strix OS 1.0.6.11 |

Flash only this ZIP. Its SHA-256 must match the line above and the `c20` entry in [releases.json](releases.json).

TMG12 changes only the launcher file `nuttx_ap.bin`. The other 15 payload files, the installer among them, are stock 1.0.6.11.

Earlier releases are recorded in the git tags `fw/tmgN` (firmware) and `app/cN` (phone builds), and in [firmware/README.md](../../firmware/README.md). The flash steps that came with each older release are in this file's git history.

## Before you start

- RayNeo Auto Update is off. AI updates are off.
- The RayNeo app (`com.rayneo.venus.pub`) stays installed. Install every new build over it. Never delete it: deleting it wipes the pairing and the flash gate's state.

## Flash TMG12

The first attempt is also the dry run. Before the transfer starts, the phone's gate refuses anything it does not expect, and nothing is flashed. If it refuses, go to [If the gate refuses](#if-the-gate-refuses).

1. Install C20 over the existing app.
2. In RayNeo › Glasses › Software version, switch Auto Update on, then off. This saves the setting the gate reads.
3. Open Turbo › Glasses › Glasses firmware. Charge the glasses above 50% and keep them connected.
4. **Check** step: every row must pass. "TMG12 package" reads "Verified on this phone", "Local download source" reads "Running", "Transfer protection" reads "On", and "Auto Update off" reads "Off". "Glasses version read" can wait until step 9. Tap **Continue**.
   - If "Auto Update off" shows **Fix**, tap it and follow the prompt.
   - If any other row fails, stop. Do not continue.
5. **Download** step: tap **Open download for 15 min**. Then tap **Go to RayNeo**.
6. In RayNeo › Glasses › Software version, tap Download. Wait for "Ready to install". Do not tap Start install yet. Go back to Turbo.
7. "Downloaded package" shows a check mark. Its text reads "All 16 files match TMG12"; TMG12 has 17 files, and the check covers all 17.
   - If it shows a red cross and starts with "ota/Strix_OS_1.0.6.11 already holds other…", see [Folder already in use](#folder-already-in-use-文件夹已被占用).
   - If the 15 minutes run out first, open the download window again and repeat step 6.
8. Tap **Install** in the step bar at the top. On the row "TMG flashing on this install", tap **Arm**, then **Arm flashing**. The row reads "Armed on this install: the other checks still decide". The dialog asks you to record a wire log first. Skip that: the first attempt is the dry run.
9. On "Glasses version read", tap **Fix**, then **Go to RayNeo**. Open RayNeo › Glasses › Software version so it reads the glasses. Come back within 2 minutes. The row shows "…s ago · …s left". The glasses must report Strix OS 1.0.5.12 or 1.0.6.11.
10. "Downloaded package" still shows a check mark.
11. Tap **Authorize install**. Read the dialog, then tap **Authorize**. The Install row reads "Authorized · tap Start install in RayNeo". This allows one transfer. Tap Start install within 15 minutes and keep the glasses connected; otherwise the authorization lapses and you authorize again from step 9.
12. Tap **Go to RayNeo**. In Software version, tap Start install.
13. Wait. Keep both devices on and connected. The Install row reads "Installing · N parts verified". RayNeo finishes, then the glasses restart and reconnect.
14. Close and reopen the RayNeo app.
15. Open Turbo › Glasses › Glasses firmware › **Install** and tap **Disarm** on "TMG flashing on this install".
   - If the Install step does not open, leave it. Nothing transfers without a new authorization, and the next Turbo build starts disarmed. Tell the developer.

You can disarm at any time before the transfer starts. From the start of the transfer until you restart the app, you cannot disarm. Restart the app, then disarm.

If the Install row reads "Stopped: …" after the transfer started, do not try again. Restart the app, disarm, and hand the status file to the developer.

## If the gate refuses

A refusal shows either as a message in the wizard, or as RayNeo's install failing while the wizard still reads "Authorized" or "Not authorized". Take a screenshot of both apps. Then:

1. Do not change any setting to get past the refusal. Never relax a version, hash or authorization check.
2. Copy `Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA/preparation-status.json` from the app's container (Xcode › Devices and Simulators › the app › Download Container). If Download Container is not available, send the screenshots and say so.
3. If the build has the wire log (Turbo › Developer (expand it) › Wire log), tap **Export logs** too.
4. Disarm if you armed.
5. Hand the screenshot, the status file and any log to the developer. Wait for a corrected build.

What to read in `preparation-status.json`:

| Field | Expected | If not |
|---|---|---|
| `flashGate.armHost` | `ios1021` | The installed build is not C20. |
| `flashGate.armed` | `true` once you armed | Arming did not stick. Arm again. |
| `flashGate.automaticUpdateDisabled` | `true` | Switch Auto Update on, then off, in RayNeo. |
| `flashGate.recentTargetVersionRead` | `true` | No valid version read in the last 2 minutes, or the glasses reported another version, or the glasses have not confirmed their last update. |
| `feed.firmwareQueries`, `feed.downloadRequests` | above 0 | `downloadRequests` 0: RayNeo did not download from Turbo. See [Folder already in use](#folder-already-in-use-文件夹已被占用). |
| `feed.unknownQueries` | `0` | RayNeo 1.0.21 asks for updates in a form the local source does not answer. Developer fix. |
| `officialDirectory.candidate` / `checkedMembers` / `integrityPassed` | `Turbo Menu TMG12` / `17` / `true` | `officialDirectory.note` says what is wrong with the folder. |
| `flashGate.lastRefusedFrame` | absent, or from before you armed | It names the last refused frame. `type 4` with `Mode` other than 2: RayNeo asked for an install mode the gate does not accept. Developer fix. |
| `flashGate.stage` / `failure` | `0` / empty before you authorize | `3` means the transfer stopped; `failure` gives the reason. A `failure` at stage `0` means Start install was tapped before you authorized. |

## Folder already in use (文件夹已被占用)

RayNeo keeps downloaded firmware in `ota/Strix_OS_1.0.6.11` inside its container. If that folder holds other files with the same version name, such as RayNeo's own stock 1.0.6.11 download, RayNeo may reuse them instead of downloading TMG12. The wizard then says the folder holds other firmware and keeps flashing locked.

This cannot flash stock firmware by mistake. Authorization needs all 17 files to match TMG12 exactly, and the stock `nuttx_ap.bin` never does.

1. Keep the download window open and check for an update again in RayNeo › Glasses › Software version. RayNeo has downloaded the Turbo package over its own stock files before.
2. If the wizard still says the folder is in use, stop.
3. Do not delete the app. Do not move or edit RayNeo's files by hand. Do not relax any check.
4. Hand `preparation-status.json` to the developer.

## After the flash

1. Close and reopen the RayNeo app, then disarm (steps 14 and 15 above).
2. RayNeo › Glasses › Software version shows Strix OS 1.0.6.11. If it shows another version, stop and tell the developer.
3. Turbo › Developer (expand it) › Glasses runtime, row "Firmware and build", shows the build identity `0f43c519fc964dc4bd578cf9d7193e502b5c5daa17f3061fba26ccec0280fc55`.
4. Check the glasses features. There is no TMG12 device checklist in [firmware/README.md](../../firmware/README.md) yet. Until there is one, use the TMG11 owner check there (IMU, fold, knob, Sensors screen, sensor log) and the TMG12 section's list of changes (14-item carousel, Turbo Nav tile, new Light line). TMG12 starts with the default tile order; the TMG11 order is not carried over.

## Going back

The glasses roll back on their own only if Bluetooth advertising has not started within 10 s of first boot. Otherwise TMG12 stays until you flash something else. No recovery build is made in advance.

If TMG12 misbehaves, pick one:

- **A corrected TMG12.** Wait for the fix. It comes as a second build of the same phone code, pinned to the corrected package, and flashes with the same steps. Cost: the wait.
- **Stock Strix OS 1.0.6.11.** It comes as a second build of the same phone code, pinned to stock 1.0.6.11, made only when needed. All 16 official 1.0.6.11 files and their hashes are kept, and that build packs them itself. Cost: the Turbo glasses features are gone until the next TMG flash.

Both are same-version flashes. The 1.0.6.11 installer compares no version, so it does not refuse one. A same-version flash already worked once on 1.0.5.12 (TMG11 over TMG10, 2026-11-12).

**Last resort: RayNeo's next version through the plain App Store app.** It replaces the Turbo app, so the Turbo phone features are gone, and you must pair the glasses again.

C18 cannot help. It accepts only glasses on 1.0.5.12.

## Not yet confirmed on a device

- TMG12 has never run on glasses. Every check so far is offline or in the emulator.
- The install of a 17-file 1.0.6.11 package over the phone link, and the glasses' confirm after the first boot.
- That RayNeo 1.0.21's update check and install requests match what the gate expects.
- That RayNeo 1.0.21 unpacks the ZIP flat into `ota/Strix_OS_1.0.6.11` instead of installing from the ZIP.
- That RayNeo 1.0.21 downloads again when the folder already holds other files.
- That the Install step still opens after the flash, so you can disarm (it needs the Check step to pass and the folder to still match TMG12).
- A same-version or stock flash on 1.0.6.11.
- The C20 phone features on RayNeo AI 1.0.21.

## Why official updates are redirected

The Turbo build points RayNeo's update check at a small server inside the app, on the phone itself. That server offers no app update, and it offers firmware only while the download window is open, and then only the pinned TMG ZIP. Without this, RayNeo would offer stock Strix OS, which would overwrite TMG and remove the Turbo glasses features. The App Store does not update the re-signed Turbo build, so each new RayNeo version needs a new Turbo port.
