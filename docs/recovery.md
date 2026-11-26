# When a firmware update goes wrong

This page covers what the RayNeo iO glasses do when a firmware update fails, and what your way back is. It covers Strix OS 1.0.6.11 and the TMG builds on it. TMG15 ships the stock installer unchanged, so everything here applies to it.

Every statement carries one of three labels:

- **Device-tested**: seen on the owner's glasses.
- **Emulator only**: seen when the stock firmware ran in our emulator. The emulator is a model of the hardware, so a result there is evidence, not proof.
- **Not tested**: read from the firmware code, or not known. Nobody has seen it happen.

None of the failure cases below has been seen on real glasses. Nothing here makes flashing safe. A bad flash can leave the glasses unusable, and this page does not promise a way back from every case.

## How an update works

1. The phone app checks every file of the package against its pinned hash, then sends it. The glasses store it in a staging folder and check each file's checksum as it arrives.
2. The glasses restart into the installer, a small program kept in its own area of flash, apart from the main firmware.
3. The installer writes the new images, reads the main ones back, and marks them bootable last. Then it writes a pending-update record and restarts.
4. On every start, a boot check decides whether to run the installer or the main firmware. With a pending update, it lets the new firmware start once.
5. The new firmware must confirm within about 10 s of its update service starting. It confirms when Bluetooth advertising starts successfully. Confirming clears the pending record.
6. After confirming, the new firmware copies the package into a separate backup area. That copy is now the backup of the last confirmed firmware. A later failed update restores it.

**Device-tested:** the flow end to end. TMG12, TMG14 and TMG15 were flashed this way and came back running. After TMG12 the glasses reported the update as confirmed. The phone's hash check runs before every flash.
**Emulator only:** steps 2 to 6 one by one, from stock to TMG15 and from TMG15 to stock.
**Not tested:** the glasses' own checksum check in step 1.

The backup is the last update that confirmed, not stock. If your last confirmed update was TMG15, a rollback brings back TMG15. (Emulator only.)

## What happens if…

These results come from 15 emulator runs: one clean update as a control, and 14 runs with one fault each. One of the 14 stopped on an emulator limit and was run again with a fix.

| If… | What the glasses do | How sure |
|---|---|---|
| The new firmware does not confirm in time | They restart into the installer on their own, restore the backup and start it. The old firmware then reports a failed update. | Emulator only |
| The new firmware crashes, or the glasses restart for any reason, before it confirms | One restart is enough. The next start goes to the installer, which restores the backup and starts it. The new firmware gets no second try. | Emulator only |
| The package is corrupt | The phone app refuses a package whose files do not match the pinned hashes, before it sends anything. The installer itself checks no hash, and does not compare file sizes with the package list. In the emulator it wrote a corrupted image and a cut-short image without complaint, and a wrong checksum in the package list was ignored. The corrupted one crashed at start and was rolled back, as in the row above. The cut-short one crashed and then hung in a crash loop. It never restarted. A corrupt image that does not crash before it confirms would be confirmed and become the backup. | Phone check: device-tested. The rest: emulator only. The last sentence: not tested |
| A restart interrupts the install | The installer starts the interrupted step again and finishes. The glasses end on the new firmware. | Emulator only |
| Power loss interrupts the install | This depends on whether a boot-mode flag survives a power loss, which only a device can show. If the flag is lost: a cut early in the install starts the old firmware, and the update is not applied. A cut during the main write lets the installer resume and finish. A cut in a very short window at the end, after the images are marked bootable and before the pending record is written, starts the new firmware with no check at all. Nothing can then roll it back on its own. | Emulator only, partial model |
| There is no backup from an earlier confirmed update | If the new firmware then fails to confirm, or crashes, the installer finds nothing to restore. It keeps the failure state and restarts to try again, every few seconds, with no end. Neither firmware starts again. | Emulator only |
| Something interrupts the glasses after the new firmware confirmed | They run the new firmware normally. If the cut landed while the backup was being copied, they are expected to redo the copy on the next start, as long as the staged files are still there (read from code, not run). | Not tested |

## What we do not know

- **The real boot loader.** The code that runs first at power-on is in no package we have. The emulator starts the installer directly on every restart. It cannot show which of the installer's two copies a real loader picks.
- **The phone transfer.** The emulator does not run it. It puts the package on the glasses' storage itself and triggers the restart into the installer. So the glasses' own checks during the transfer never ran in these tests.
- **Power loss.** Whether the boot-mode flag and memory survive a power loss, a flat battery or a watchdog reset is not known. The emulator keeps both across a restart; its power-loss variant clears only the flag. Every interruption result above depends on this. The emulator also finishes each flash write instantly, so no cut ever lands inside one write.
- **Hangs.** Whether a watchdog restarts glasses that hang in a crash loop is not known. If they do restart, we expect the rollback of the second row, but no run showed it.
- **The screen.** What the glasses show while the installer runs is not known. Our display model does not show the installer's pictures.

## Practical advice

Before you flash:

- Charge the glasses above 50%. Keep the glasses and the phone on and connected for the whole update.
- Keep the Turbo build of the RayNeo app installed, and install every new build over it. It is the only flashing route we support. Deleting it wipes the pairing and the flash gate's state.
- Flash only the pinned packages in [OTA.md](../ios-addon/OTA.md). The installer checks no hash, so the phone's check is the only tested one a corrupt package meets.
- Do not interrupt the update. Wait until the glasses have restarted and reconnected to the phone.
- After the flash, let the glasses start and reconnect before you restart them. A restart before the new firmware confirms rolls the update back, and with no backup it leaves them in the installer. (Emulator only.)

If something seems wrong:

- **The glasses stop answering the phone.** Hold the knob down (a very long press) until they restart, then reconnect. (Device-tested on locked glasses.)
- **They restart on their own once or twice after an update.** Wait. A rollback runs in the installer and needs one or two restarts. (Emulator only.)
- **The flashed firmware misbehaves, but the glasses still talk to the phone.** Flash stock 1.0.6.11 from the phone app, as in [Going back](../ios-addon/OTA.md#going-back). Flashing TMG builds from the app is device-tested, and so is flashing while the glasses are locked. A stock flash from the app has not been tried on the glasses. In the emulator, an install from TMG15 to stock completed.
- **They keep restarting and never come back to either firmware.** We have no tested way out of this. Stop, and tell the developer what you saw.

## What survives a flash and a factory reset

All of this is **not tested**. It comes from reading the firmware.

**A flash** rewrites the firmware images (the main one, Bluetooth, the co-processor and audio) and a few small support files. It does not touch the user files in the glasses' data storage, the small settings file system, or the factory and calibration areas. On TMG builds the lock record survives a flash, stock included.

**The backup area** is written, as far as we read, only by the update itself. It is also reformatted, and the backup lost, if it fails to mount at start.

**A factory reset**: the stock firmware has three wipe routines. All three erase the user-data, report and log areas in flash. One then deletes everything in the data storage except the update folder. The other two reformat the whole data storage, update folder included. As far as we read, none of them touches the firmware images or the backup area. Which routine the five-press factory reset on the glasses reaches is not established. On TMG builds the factory reset also deletes the lock record.
