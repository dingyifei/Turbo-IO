# Flashing Turbo firmware

## What this covers

This guide flashes firmware onto the RayNeo iO glasses from the Turbo phone build, through RayNeo's own updater. You do every step yourself, on your own iPhone. Agents never install the app or flash the glasses. Flashing is high risk: a bad flash can leave the glasses unusable, and recovery is not guaranteed.

## Current build: C21

C21 carries two firmware packages. You pick one in the wizard.

| | |
|---|---|
| Phone build | C21: RayNeo AI 1.0.21 (1), full build |
| Glasses must report | Strix OS 1.0.5.12 or Strix OS 1.0.6.11 (both packages) |
| Target version | Strix OS 1.0.6.11 (both packages) |

| Package | ZIP | Size | SHA-256 |
|---|---|---|---|
| TMG12 (selected at every launch) | `StrixOS-1.0.6.11-TurboIO-TMG12-CANDIDATE-NOT-APPROVED.zip` | 9,549,211 bytes | `3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373` |
| Stock 1.0.6.11 (the way back) | `Strix-OS-1.0.6.11-members-canonical.zip` | 9,447,267 bytes | `5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e` |

Flash only these two ZIPs. Each SHA-256 must match the line above and the `c21` entry in [releases.json](releases.json). The C21 build carries both, so there is nothing to fetch from anywhere else.

TMG12 is TMG11 ported to stock Strix OS 1.0.6.11. It changes only the launcher file `nuttx_ap.bin`; the other 15 payload files, the installer among them, are stock 1.0.6.11. The stock package is every official 1.0.6.11 file, unchanged. The two ZIPs differ only in `nuttx_ap.bin` and `OtaFileInfo.json`.

The glasses already run TMG12: C20 flashed it on 2026-11-15. C21 has not been installed yet.

Earlier releases are recorded in the git tags `fw/tmgN` (firmware) and `app/cN` (phone builds), and in [firmware/README.md](../firmware/README.md). The flash steps that came with each older release are in this file's git history.

## Before you start

- RayNeo Auto Update is off. AI updates are off.
- The RayNeo app (`com.rayneo.venus.pub`) stays installed. Install every new build over it. Never delete it: deleting it wipes the pairing and the flash gate's state.

## Flash

The steps are the same for both packages. The first attempt is also the dry run. Before the transfer starts, the phone's gate refuses anything it does not expect, and nothing is flashed. If it refuses, go to [If the gate refuses](#if-the-gate-refuses).

1. Install C21 over the existing app. It must be packaged with `--wire-log`, or the Wire log row in step 2 is missing.
2. Open Turbo › Developer (expand it) › Wire log. Switch on **Record channel traffic** and **Start recording at launch**. Keep a wire log of every flash; if the gate refuses, this log is what you send.
3. In RayNeo › Glasses › Software version, switch Auto Update on, then off. This saves the setting the gate reads.
4. Open Turbo › Glasses › Glasses firmware. Charge the glasses above 50% and keep them connected.
5. **Check** step: under **Firmware to install**, pick the package. TMG12 is selected each time the app starts; pick **Stock 1.0.6.11** only to go back to stock.
6. Every row must pass. The package row reads "Verified on this phone", "Local download source" reads "Running", "Transfer protection" reads "On", and "Auto Update off" reads "Off". "Glasses version read" can wait until step 10. Tap **Continue**.
   - If "Auto Update off" shows **Fix**, tap it and follow the prompt.
   - If any other row fails, stop. Do not continue.
7. **Download** step: tap **Open download for 15 min**. Then tap **Go to RayNeo**.
8. In RayNeo › Glasses › Software version, tap Download. RayNeo offers "Turbo Menu TMG12 PRIVATE EXPERIMENT", or "Stock 1.0.6.11" if you picked stock. Wait for "Ready to install". Do not tap Start install yet. Go back to Turbo.
9. "Downloaded package" shows a check mark and reads "All 16 files match" the package you picked.
   - If it shows a red cross and a line that starts with a file name and "is missing from the…" (cut short on screen), see [Folder already in use](#folder-already-in-use-文件夹已被占用).
   - If the 15 minutes run out first, open the download window again and repeat step 8.
10. Tap **Install** in the step bar at the top. "Glasses version read" must read "Read · <package> accepts it". If it reads "Read it on the RayNeo firmware page", tap **Fix**, then **Go to RayNeo** in the dialog. Open RayNeo › Glasses › Software version so it reads the glasses, then come back. The read has no time limit. It is cleared when the glasses disconnect or the app restarts. Each new report replaces it, and a report counts only if it names Strix OS 1.0.5.12 or 1.0.6.11 with the last update confirmed.
11. Tap **Authorize install**. Read the dialog, then tap **Authorize**. The row reads "Authorized · tap Start install in RayNeo". This allows one transfer. Tap Start install within 15 minutes and keep the glasses connected; otherwise the authorization lapses and you authorize again.
12. Tap **Go to RayNeo**. In Software version, tap Start install.
13. Wait. Keep both devices on and connected. The Install row reads "Installing · N parts verified". RayNeo finishes, then the glasses restart and reconnect.
14. Close and reopen the RayNeo app.

To cancel before the transfer starts, tap **Revoke authorization**, or change the package under Firmware to install: a change while authorized cancels the authorization and returns to the Check step. Once the transfer has started, the package cannot change until RayNeo restarts.

Every transfer needs a fresh authorization.

If the Install row reads "Stopped: …" after the transfer started, do not try again. Restart the app and export the wire log (see below).

## If the gate refuses

A refusal shows either as a message in the wizard, or as RayNeo's install failing while the wizard still reads "Authorized" or "Not authorized". Take a screenshot of both apps. Then:

1. Do not change any setting to get past the refusal. Never relax a version, hash or authorization check.
2. If the Install row reads "Stopped: …", write that line down. Otherwise note what the Install row reads.
3. Open Turbo › Developer (expand it) › Wire log and tap **Export logs**.
4. Hand the screenshots, the failure line and the exported log to the developer. Wait for a corrected build.

## Folder already in use (文件夹已被占用)

RayNeo keeps downloaded firmware in `ota/Strix_OS_1.0.6.11` inside its container. Both packages use that folder. After a TMG12 flash it holds TMG12; after a stock flash, or after RayNeo's own stock download, it holds stock. If it holds the other package, RayNeo may reuse those files instead of downloading the one you picked. The folder check then fails, usually on `OtaFileInfo.json`, the first file it checks, and flashing stays locked. The screen shows the start of the message; the full line ("… is missing from the folder or does not match <package>; not sent.") is in the wire log.

This cannot flash the wrong package. Authorization needs all 17 pinned files, `OtaFileInfo.json` included, to match the package you picked, byte for byte. Extra files in the folder are ignored.

1. Keep the download window open and tap Download again in RayNeo › Glasses › Software version. RayNeo has downloaded the Turbo package over its own stock files before.
2. If the check still fails, stop.
3. Do not delete the app. Do not move or edit RayNeo's files by hand. Do not relax any check.
4. Export the wire log (Turbo › Developer › Wire log › **Export logs**) and hand it to the developer.

## After the flash

1. Close and reopen the RayNeo app.
2. RayNeo › Glasses › Software version shows Strix OS 1.0.6.11. If it shows another version, stop and tell the developer.
3. After TMG12: Turbo › Developer (expand it) › Glasses runtime, row "Firmware and build", shows the build identity `0f43c519fc964dc4bd578cf9d7193e502b5c5daa17f3061fba26ccec0280fc55`. After stock, the Turbo glasses features are gone.
4. After TMG12, check the glasses features. There is no TMG12 device checklist in [firmware/README.md](../firmware/README.md) yet. Until there is one, use the TMG11 owner check there (IMU, fold, knob, Sensors screen, sensor log) and the TMG12 section's list of changes (14-item carousel, Turbo Nav tile, new Light line).

## Going back

The glasses roll back on their own only if Bluetooth advertising has not started within 10 s of first boot. Otherwise the flashed firmware stays until you flash something else.

If TMG12 misbehaves, pick one:

- **Stock Strix OS 1.0.6.11, from C21.** Pick Stock 1.0.6.11 in the wizard and flash with the same steps. Cost: the Turbo glasses features are gone until you flash TMG12 again, which C21 also does.
- **A corrected TMG12.** Wait for the fix. It comes as a new phone build and flashes with the same steps. Cost: the wait.

Both are same-version flashes. The 1.0.6.11 installer compares no version, so it does not refuse one. A same-version flash already worked once on 1.0.5.12 (TMG11 over TMG10, 2026-11-12).

**Last resort: RayNeo's next version through the plain App Store app.** It replaces the Turbo app, so the Turbo phone features are gone, and you must pair the glasses again.

## Confirmed by the 2026-11-15 flash (C20)

- C20 installed TMG12 over the phone link from 1.0.5.12. The glasses came back on Strix OS 1.0.6.11 and confirmed the update after the first boot. The transfer was 313 slices, 15,741,262 bytes.
- RayNeo 1.0.21's update check and install requests matched what the gate expects (wire log). C21's tests replay that recorded sequence.
- RayNeo 1.0.21 unpacked the ZIP flat into `ota/Strix_OS_1.0.6.11`: the gate's folder check passed.
- The owner's first check of the glasses and the phone passed.

## Not yet confirmed on a device

- C21 on the phone: the package picker, one-confirmation authorization and the version read without a time limit.
- A stock or same-version flash on 1.0.6.11. The stock flash in the recorded file order is 310 slices, 15,576,146 bytes (computed, not flashed).
- That RayNeo 1.0.21 downloads again when the folder holds the other package.
- A full TMG12 device checklist and the full set of phone features.

## Why official updates are redirected

The Turbo build points RayNeo's update check at a small server inside the app, on the phone itself. That server offers no app update, and it offers firmware only while the download window is open, and then only the package picked in the wizard. Without this, RayNeo would offer its own stock Strix OS, which would overwrite TMG and remove the Turbo glasses features. The App Store does not update the re-signed Turbo build, so each new RayNeo version needs a new Turbo port.
