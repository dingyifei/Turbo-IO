# TVP2 / TAR2 · Clear Screen Casting: Install and Acceptance

> Archived: the TVP2 / TAR2 receiver and display modules (`official-addon/tar2-airplay`, `tar2-display`) were removed from the source tree in cleanup(3) and remain in git history. This page is a record only.

## Versions and what is public

| Part | Status in this release |
| --- | --- |
| iOS receiver | TAR2. The user tested it in a private integrated build on iPhone 17 Pro Max / 1.0.7 (230) and reported it passed. The standalone GPLv3 receiver SDK is public; no private merged or signed IPA is provided. |
| Glasses firmware | Stock 1.0.5.5 baseline + TVP2. Published: the ZIP/AP exactly as flashed, checksums, and reproducible extension source. |
| Android | The AirPlay receiver was not ported in this round. The Android plugin already in the repo does not mean this feature is supported there. |
| Stock older firmware / TMG2 / TVP1 | Cannot run the new 540×220 tiled protocol. The handshake rejects them; updating only the phone does not give you HD. |

Visible source does not mean any old phone plugin will work. Beginners should keep using the official app and firmware. The GPL receiver SDK has to be integrated, built and signed by the developer; combining it with a closed-source host, or redistributing binaries, also needs a licence review. WeChat Read and NetEase Cloud Music accounts are still your own problem; no login state ships with the package.

## Matching phone side

The full private integrated build contains personal assets and signing, and is **not available for public download**. Public developers build the receiver from the TAR2 SDK and connect it, following the integration contract, to an iOS host they are legally entitled to use. For the stock 1.0.7 inputs and the existing SDK reference, see [ios-addon](../../ios-addon/README.md). The historical APP107/TMG2 packager is still pinned to the old candidate; do not mistake it for TVP2 support.

If you port the existing OTA component yourself, keep the original protections and update the whole set to TVP2: the candidate ZIP, the AP, the 15 extracted files, and the size and hash of every chunk. Changing only the name or swapping the download URL is not enough. Do not replace the real read-back with a hard-coded "check passed".

## Firmware install (phone side that matches and has the TVP2 gate wired in)

1. Export or back up the phone app data you need. Make sure the glasses are at 50% battery or more, go back to the home screen, and end recording, Lifelog, navigation, music, reading, camera, Mentra and other tasks.
2. Download the full TVP2 ZIP for this release and check it against the pinned SHA with `shasum -a 256 <ZIP>`. The AP on its own is not a flash input.
3. On the phone, open TurboIO → "设置" (Settings) → "诊断与实验固件" (Diagnostics and experimental firmware) → TVP2. The built-in candidate or the imported ZIP must actually pass verification.
4. Turn on "15分钟只下载验收" (15-minute download-only acceptance), go back to the stock firmware page, check for and download the update, and wait for "软件就绪" (Software ready). This step does not authorize the install.
5. Read back the official extraction directory and check each of the 15 payloads and the manifest one by one. Stop on an old TVP1 cache, an incomplete package or any hash mismatch. Do not force-flash repeatedly.
6. Manually confirm the exact candidate **TVP2**, the battery level and that the home screen is idle, grant permission for this one upgrade, then start the install through the official flow. If the authorization expires, run the page's pre-check again; do not replay an old authorization.
7. During the upgrade, do not power off, do not drop the connection and do not start other tasks. If the state is unclear, do not tap repeatedly, restart or remove the protection.
8. After the glasses return to the home screen on their own and you have checked that the display is normal, complete "已自然回首页：允许只读回查" (Returned to home on its own: allow read-only check) and "已检查显示：解除结果保护" (Display checked: release result protection) on the protection page (the titles may change between client versions). Only resume everyday official features after you confirm authorization 0, no transfer in progress, and result protection ended. Otherwise the phone may keep blocking official features.

## Screen-casting test

Put the receiving iPhone and the sending device on the same Wi-Fi and allow local network access. Keep the receiver page in the foreground. Tap start, then on **another** iPhone, iPad or Mac open Control Center, choose "屏幕镜像 → Turbo IO" (Screen Mirroring → Turbo IO), and enter the PIN shown. No extra Mac or server is needed, but the receiving phone itself cannot be left out.

Start with a landscape desktop, the photo library or a large-text web page, not protected streaming media. The full picture keeps its aspect ratio, so portrait content can be very narrow; for small text, use partial zoom and drag to position it. The defaults are 8 gray levels and a 10 fps target; you can compare 4/8/16 gray levels. HD increases the transfer volume, and the target frame rate is not the actual frame rate.

Check acceptance stage by stage: Bonjour service published → connected → video received → phone decodes → glasses confirm complete frames → clearly visible on the lens. Short press pauses/resumes, long press exits. Afterwards, check that it closed normally, then test stock head-up wake, recording/Lifelog and the old apps. Receiving on the lock screen or in the background is not supported in this release.

## Measured results and limits

On 2026-10-23 the user reported the clear-version test finished with no problems. Metadata read back on the device: 1280×720 source, 540×220 output, 16 gray levels, 3470 decoded frames with zero decode errors, 186 frames confirmed complete by the glasses, normal close. Only these totals are published; raw logs, content, device identity and the PIN are not. This does not mean every sender, long-run stability, every stock feature or every model passes.

This release does not claim the Classic Bluetooth hardware limit, a fixed 30 fps, 4K or permanent background receiving, and does not count Bluetooth submissions as displayed frames. Preferring MFi does not by itself prove which link type is actually in use.
