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
2. Open Turbo › Developer (expand it) › Wire log. Switch on **Record channel traffic** and **Start recording at launch**. If the gate refuses, this log is what you send.
3. In RayNeo › Glasses › Software version, switch Auto Update on, then off. This saves the setting the gate reads.
4. Open Turbo › Glasses › Glasses firmware. Charge the glasses above 50% and keep them connected.
5. **Check** step: every row must pass. "TMG12 package" reads "Verified on this phone", "Local download source" reads "Running", "Transfer protection" reads "On", and "Auto Update off" reads "Off". "Glasses version read" can wait until step 10. Tap **Continue**.
   - If "Auto Update off" shows **Fix**, tap it and follow the prompt.
   - If any other row fails, stop. Do not continue.
6. **Download** step: tap **Open download for 15 min**. Then tap **Go to RayNeo**.
7. In RayNeo › Glasses › Software version, tap Download. Wait for "Ready to install". Do not tap Start install yet. Go back to Turbo.
8. "Downloaded package" shows a check mark and reads "Every file matches TMG12".
   - If it shows a red cross and starts with "ota/Strix_OS_1.0.6.11 already holds other…", see [Folder already in use](#folder-already-in-use-文件夹已被占用).
   - If the 15 minutes run out first, open the download window again and repeat step 7.
9. Tap **Install** in the step bar at the top. On the row "TMG flashing on this install", tap **Arm**, then **Arm flashing**. The row reads "Armed on this install: the other checks still decide".
10. On "Glasses version read", tap **Fix**, then **Go to RayNeo**. Open RayNeo › Glasses › Software version so it reads the glasses. Come back within 2 minutes. The row shows "…s ago · …s left". The glasses must report Strix OS 1.0.5.12 or 1.0.6.11.
11. "Downloaded package" still shows a check mark.
12. Tap **Authorize install**. Read the dialog, then tap **Authorize**. The Install row reads "Authorized · tap Start install in RayNeo". This allows one transfer. Tap Start install within 15 minutes and keep the glasses connected; otherwise the authorization lapses and you authorize again from step 10.
13. Tap **Go to RayNeo**. In Software version, tap Start install.
14. Wait. Keep both devices on and connected. The Install row reads "Installing · N parts verified". RayNeo finishes, then the glasses restart and reconnect.
15. Close and reopen the RayNeo app.
16. Open Turbo › Glasses › Glasses firmware › **Install** and tap **Disarm** on "TMG flashing on this install".

While armed, the Install step always opens from the step bar, so Disarm is always reachable. You can disarm at any time before the transfer starts. From the start of the transfer until you restart the app, you cannot disarm. Restart the app, then disarm.

Being left armed permits nothing by itself: every transfer needs a fresh authorization.

If the Install row reads "Stopped: …" after the transfer started, do not try again. Restart the app, disarm, and export the wire log (see below).

## If the gate refuses

A refusal shows either as a message in the wizard, or as RayNeo's install failing while the wizard still reads "Authorized" or "Not authorized". Take a screenshot of both apps. Then:

1. Do not change any setting to get past the refusal. Never relax a version, hash or authorization check.
2. Write down the failure line the wizard shows on the Install step.
3. Open Turbo › Developer (expand it) › Wire log and tap **Export logs**.
4. Disarm if you armed.
5. Hand the screenshots, the failure line and the exported log to the developer. Wait for a corrected build.

## Folder already in use (文件夹已被占用)

RayNeo keeps downloaded firmware in `ota/Strix_OS_1.0.6.11` inside its container. If that folder holds other files with the same version name, such as RayNeo's own stock 1.0.6.11 download, RayNeo may reuse them instead of downloading TMG12. The wizard then says the folder holds other firmware and keeps flashing locked.

This cannot flash stock firmware by mistake. Authorization needs all 17 files to match TMG12 exactly, and the stock `nuttx_ap.bin` never does.

1. Keep the download window open and check for an update again in RayNeo › Glasses › Software version. RayNeo has downloaded the Turbo package over its own stock files before.
2. If the wizard still says the folder is in use, stop.
3. Do not delete the app. Do not move or edit RayNeo's files by hand. Do not relax any check.
4. Export the wire log (Turbo › Developer › Wire log › **Export logs**) and hand it to the developer.

## After the flash

1. Close and reopen the RayNeo app, then disarm (steps 15 and 16 above).
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

## Confirmed by the 2026-11-15 flash

- C20 installed TMG12 over the phone link from 1.0.5.12. The glasses came back on Strix OS 1.0.6.11 and confirmed the update after the first boot.
- RayNeo 1.0.21's update check and install requests matched what the gate expects (wire log).
- RayNeo 1.0.21 unpacked the ZIP flat into `ota/Strix_OS_1.0.6.11`: the gate's folder check passed.
- The owner's first check of the glasses and the phone passed.

## Not yet confirmed on a device

- That RayNeo 1.0.21 downloads again when the folder already holds other files.
- A same-version or stock flash on 1.0.6.11.
- A full TMG12 device checklist and the full set of C20 phone features.

## Why official updates are redirected

The Turbo build points RayNeo's update check at a small server inside the app, on the phone itself. That server offers no app update, and it offers firmware only while the download window is open, and then only the pinned TMG ZIP. Without this, RayNeo would offer stock Strix OS, which would overwrite TMG and remove the Turbo glasses features. The App Store does not update the re-signed Turbo build, so each new RayNeo version needs a new Turbo port.
