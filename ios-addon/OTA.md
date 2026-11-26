# Flashing Turbo firmware

## What this covers

This guide flashes firmware onto the RayNeo iO glasses from the Turbo phone build, through RayNeo's own updater. You do every step yourself, on your own iPhone. Agents never install the app or flash the glasses. Flashing is high risk: a bad flash can leave the glasses unusable, and recovery is not guaranteed.

## Current release: C26 + TMG17

C26 carries two firmware packages. You pick one in the wizard: TMG17, or stock Strix OS 1.0.6.11.

| Package | ZIP | SHA-256 |
|---|---|---|
| TMG17 (selected at every launch) | `StrixOS-1.0.6.11-TurboIO-TMG17-CANDIDATE-NOT-APPROVED.zip` | `dab9cdbde8b5a29eb0f481b062ed3f82af4b56941eac8438d212dee3ffabae01` |
| Stock 1.0.6.11 | `Strix-OS-1.0.6.11-members-canonical.zip` | in [RELEASE.md](RELEASE.md#current-release-c26--tmg17) |

The glasses must report Strix OS 1.0.5.12 or 1.0.6.11. Both packages install Strix OS 1.0.6.11. Flash only these two ZIPs. Each SHA-256 must match the [release record](RELEASE.md#current-release-c26--tmg17) and the `c26` entry in [releases.json](releases.json). C26 carries both, so there is nothing to fetch from anywhere else. C26 cannot flash TMG15 or TMG16.

C26 + TMG17 was released on 2026-11-26 (tags `app/c26` and `fw/tmg17`). The full record, with every hash and the device status, is in [RELEASE.md](RELEASE.md). Locked glasses can be flashed; the update runs while they are locked.

Earlier releases are recorded in the git tags `fw/tmgN` (firmware) and `app/cN` (phone builds), and in [RELEASE.md](RELEASE.md). The flash steps that came with each older release are in this file's git history.

## Before you start

- RayNeo Auto Update is off. AI updates are off.
- The RayNeo app (`com.rayneo.venus.pub`) stays installed. Install every new build over it. Never delete it: deleting it wipes the pairing and the flash gate's state.

## Flash

The steps are the same for both packages. The first attempt is also the dry run. Before the transfer starts, the phone's gate refuses anything it does not expect, and nothing is flashed. If it refuses, go to [If the gate refuses](#if-the-gate-refuses).

1. Install C26 over the existing app. It must be packaged with `--wire-log`, or the Wire log row in step 2 is missing.
2. Open Turbo › Developer (expand it) › Wire log. Switch on **Record channel traffic** and **Start recording at launch**. Keep a wire log of every flash; if the gate refuses, this log is what you send.
3. In RayNeo › Glasses › Software version, switch Auto Update on, then off. This saves the setting the gate reads.
4. Open Turbo › Glasses › Glasses firmware. Charge the glasses above 50% and keep them connected.
5. **Check** step: under **Firmware to install**, pick the package. TMG17 is selected each time the app starts; pick **Stock 1.0.6.11** only to go back to stock.
6. Every row must pass. The package row reads "Verified on this phone", "Local download source" reads "Running", "Transfer protection" reads "On", and "Auto Update off" reads "Off". "Glasses version read" can wait until step 10. Tap **Continue**.
   - If "Auto Update off" shows **Fix**, tap it and follow the prompt.
   - If any other row fails, stop. Do not continue.
7. **Download** step: tap **Open download for 15 min**. Then tap **Go to RayNeo**.
8. In RayNeo › Glasses › Software version, tap Download. RayNeo offers "Turbo Menu TMG17 PRIVATE EXPERIMENT", or "Stock 1.0.6.11" if you picked stock. Wait for "Ready to install". Do not tap Start install yet. Go back to Turbo.
9. "Downloaded package" shows a check mark and reads "Every file matches TMG17", or "Every file matches Stock 1.0.6.11" with the stock package picked.
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

RayNeo keeps downloaded firmware in `ota/Strix_OS_1.0.6.11` inside its container. Both packages use that folder. After a TMG17 flash it holds TMG17; after a stock flash, or after RayNeo's own stock download, it holds stock. If it holds the other package, RayNeo may reuse those files instead of downloading the one you picked. The folder check then fails, usually on `OtaFileInfo.json`, the first file it checks, and flashing stays locked. The screen shows the start of the message; the full line ("… is missing from the folder or does not match <package>; not sent.") is in the wire log.

This cannot flash the wrong package. Authorization needs all 17 pinned files, `OtaFileInfo.json` included, to match the package you picked, byte for byte. Extra files in the folder are ignored.

1. Keep the download window open and tap Download again in RayNeo › Glasses › Software version. RayNeo has downloaded the Turbo package over its own stock files before.
2. If the check still fails, stop.
3. Do not delete the app. Do not move or edit RayNeo's files by hand. Do not relax any check.
4. Export the wire log (Turbo › Developer › Wire log › **Export logs**) and hand it to the developer.

## After the flash

1. Close and reopen the RayNeo app.
2. RayNeo › Glasses › Software version shows Strix OS 1.0.6.11. If it shows another version, stop and tell the developer.
3. After TMG17: Turbo › Developer (expand it) › Glasses runtime, row "Firmware and build", shows the TMG17 build identity given in [RELEASE.md](RELEASE.md#current-release-c26--tmg17). After stock, the Turbo glasses features are gone.
4. After TMG17, if the lock was on before the flash, the glasses start locked. Unlock with the PIN or from Turbo › Glasses › Glasses lock. If the lock was never set up, it is off until you set a PIN there.
5. After TMG17, run the device check in [firmware/README.md](../firmware/README.md#device-check).

## Going back

The glasses roll back on their own only before the new firmware confirms: if Bluetooth advertising has not started within about 10 s of its first boot, or if the glasses restart before that. They roll back to the last update that confirmed, and only if one exists; with none they stay in the installer. Neither case has been seen on a device. See [When an update goes wrong](../docs/recovery.md). Otherwise the flashed firmware stays until you flash something else.

If TMG17 misbehaves, pick one:

- **C24 + TMG15, the previous release.** Install C24 (tag `app/c24`) over the existing app, then flash TMG15 from it with the same steps. TMG15's ZIP SHA-256 and the build identity it shows after the flash are in [Way back](RELEASE.md#way-back) in RELEASE.md. Cost: TMG15's older PIN screen, and with Do Not Disturb on, its PIN screen goes dark about 3 s after it lights; unlock from the phone then.
- **Stock Strix OS 1.0.6.11, from C26.** Pick Stock 1.0.6.11 in the wizard and flash with the same steps. It restores the stock launcher and the stock Bluetooth image. Cost: the Turbo glasses features and the lock are gone until you flash TMG17 again, which C26 also does.
- **A corrected TMG17.** Wait for the fix. It comes as a new phone build and flashes with the same steps. Cost: the wait.

All three are same-version flashes. The 1.0.6.11 installer compares no version, so it does not refuse one. Same-version flashes of TMG packages worked on 2026-11-22, 2026-11-23 and 2026-11-24; a stock flash has not been tried.

Both need the phone link. If the glasses stop answering the phone, hold the knob down until they restart, then try again. After a restart the head-motion hook in the Bluetooth image is off until the phone reconnects.

The lock record stays on the glasses through a flash, stock included. If you want the lock gone, turn it off in Turbo › Glasses › Glasses lock before you flash stock. If you forget the PIN, unlock from the phone and set a new one; with no phone, the stock factory reset removes the lock with everything else on the glasses.

**Last resort: RayNeo's next version through the plain App Store app.** It replaces the Turbo app, so the Turbo phone features are gone, and you must pair the glasses again.

## Confirmed on a device

- **2026-11-15, C20.** TMG12 installed over the phone link from 1.0.5.12. The glasses came back on Strix OS 1.0.6.11 and confirmed the update after the first boot. RayNeo 1.0.21's update check and install requests matched what the gate expects (wire log); the tests replay that recorded order. RayNeo unpacked the ZIP flat into `ota/Strix_OS_1.0.6.11`, and the folder check passed.
- **2026-11-22, C23.** TMG14, a candidate for TMG15, installed over a TMG13 candidate. This was the first same-version flash on 1.0.6.11 and the first install of a modified `nuttx_bth.bin`. The glasses booted and the phone reconnected without pairing again.
- **2026-11-23, C24.** TMG15 installed over TMG14 with the glasses locked. The update completed, and the owner's device check passed ([firmware/README.md](../firmware/README.md#device-check)).
- **2026-11-24, C26.** The owner flashed TMG17 from C26, and the glasses run it. The owner accepted the pair on 2026-11-26; the checks of the new PIN screen, of PIN entry with Do Not Disturb on, and of the wrong-tries notice going dark were not reported one by one.
- The package picker, the single Authorize confirmation and the version read without a time limit were used for each of the flashes from C23, C24 and C26.

## Not yet confirmed on a device

- A flash of the stock package. The stock flash in the recorded file order is 310 slices, 15,576,146 bytes (computed, not flashed).
- That RayNeo 1.0.21 downloads again when the folder holds stock and you picked TMG17, or the other way round.
- A flash from 1.0.5.12 with C26.
- Going back from C26 to C24 by installing C24 over it.

## Why official updates are redirected

The Turbo build points RayNeo's update check at a small server inside the app, on the phone itself. That server offers no app update, and it offers firmware only while the download window is open, and then only the package picked in the wizard. Without this, RayNeo would offer its own stock Strix OS, which would overwrite TMG and remove the Turbo glasses features. The App Store does not update the re-signed Turbo build, so each new RayNeo version needs a new Turbo port.
