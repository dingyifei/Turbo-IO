# Glasses PIN lock — design

Written by manager, 2026-11-21. Sources: the owner's decisions (`DECISIONS.md`), Block B (`b/REPORT-B.md`, `b/logs/b3-b5-design.md`). Block A (`a/REPORT-A.md`) is folded in. Block C (`b/REPORT-C.md`) is folded in. Block D (`a/REPORT-D.md`) is folded in. Block E (the Bluetooth-image motion hook) is folded in. The owner approved building from this design on 2026-11-21 at 19:18. The investigation reports are private working notes outside the repo; the file names are kept so findings can be traced. This file is the master copy of the design; owner changes are recorded in the decisions log and folded in here.

Releases: firmware TMG13 on stock 1.0.6.11 (modified `nuttx_ap.bin` and, for the first time, `nuttx_bth.bin`), phone build C22.

## 1. What it does

When the glasses have stayed folded for the fold delay, or have sat unfolded with the screen off and unused for the idle time, they lock. While locked the display shows nothing. A knob press brings up a PIN screen; four correct digits unlock. The phone paired with the glasses can also unlock from the addon. The phone link, and everything the phone and glasses do over it, keeps running underneath.

It protects against a person who picks the glasses up. It does not protect against someone who reads the flash chip, and a factory reset removes it (with everything else stored on the glasses).

## 1a. What it is for

The owner's purpose (14:37): stop a co-worker from using the glasses as the owner. Examples given: "hey RayNeo, add to memory that I hate my boss", "tick my most recent to-do", or getting data back out of the glasses. The person may pick the glasses up and wear them, and may never touch a control at all, only speak.

So "locked" means three things, in this order of importance:

1. **Nothing can be started.** No voice assistant session, no voice command, no key or knob action reaches any app. This is what stops writes.
2. **Nothing comes out.** No stored or phone-side content is shown.
3. **The owner finds out.** Wrong tries are counted and shown after the next unlock.

Consequences for the rest of this design:

- The assistant gate (§6a) is a release requirement, like knob capture.
- The rebond and factory-reset gestures are stock's and are left alone.
- The idle rule measures a continuous still period. Once it has been reached the glasses are locked, even if they are then picked up and moved; motion only keeps glasses unlocked that have not yet been still that long.
- Whatever the fold delay and idle time are set to is a window in which the glasses are open to anyone, including by voice from nearby. Shorter is safer; with head motion counting as use, a short idle time no longer costs the wearer anything.

**Scope (owner, 14:44): "防君子不防小人".** The lock is for honest people and casual misuse. It does not try to resist deliberate effort: re-pairing the glasses with another phone, physical access to the electronics, or someone holding the owner's unlocked phone. Where a simpler mechanism covers the casual case, the design uses it and adds no further hardening.

## 2. States

| State | Meaning | Display |
|---|---|---|
| Off | No PIN set | Normal |
| Unlocked | PIN set, in use | Normal |
| Locked, dark | Locked, nobody interacting | Off; nothing lights for any wake source |
| Locked, PIN entry | Knob pressed while locked | PIN screen only |
| Locked, waiting | A wrong-entry delay is running | "Try again in m:ss" only |
| Failure notice | Just unlocked after wrong tries | Notice only, until pressed |

Transitions:

- **Boot** with a PIN set → Locked, dark. Always, whatever the state before the reboot.
- **Unfold**: if folded time ≥ fold delay → Locked, dark.
- **Screen about to turn on**: if screen-off time with no use ≥ idle time → Locked, dark. The check runs before anything draws.
- **Phone "Lock now"** → Locked, dark.
- **Knob press while Locked, dark** → PIN entry (or Waiting, if a delay is running).
- **Correct PIN, or phone unlock** → Unlocked; if there were wrong tries since the last unlock, show the Failure notice first.
- **30 s without input on the PIN screen, or long press on the first slot** → Locked, dark.
- **Damaged lock record** → Locked, dark (fail closed). See §8.

The locked flag is held in RAM only. That is safe because every boot starts locked.

### 2a. Rules settled in the build

These follow from §2, §3 and §7 and are what `firmware/src/lock-v1/lock_core.c` implements and its host test checks.

- Two counters. *Wrong tries* (consecutive, drives the delay and the glasses' failure notice) resets at any successful unlock. *Wrong tries not yet acknowledged* (shown on the phone page) is cleared only by the phone's ACK_FAILURES.
- The delay follows from the wrong-try count: 1 to 3 wrong tries no delay, then 30 s after the 3rd, 1 min after the 4th, 5 min after the 5th, 15 min after every later one.
- Time for the delay, the fold lock and the idle lock is PMU clock seconds. A reading of zero, or earlier than the stored one, counts as elapsed for the fold and idle locks. For the delay it restarts the full delay for the current step; while no valid reading exists the delay counts as running, so knob entry waits and the phone unlock is the way in.
- "Wrong PIN" shows for 2 s, then the slots again (all at 0) or the waiting screen.
- The 30 s without-input rule applies to the PIN screen and the waiting screen; both return to dark. When a delay ends while the waiting screen is up, the slots appear.
- The idle check runs whenever the glasses leave a screen-off period: a screen-on request, and any knob, key or motion input while the screen is off. The last-use time is the later of the last knob or key input, the last motion message and the last unlock. If that check finds the idle time passed, the glasses lock first and the input is then handled as locked input.
- SET_PIN enables the lock, resets the wrong-try count and the delay, and keeps the current state (it unlocks nothing and locks nothing; from Off it becomes Unlocked). DISABLE turns the lock Off from any state. While the lock record is damaged, knob entry and SET_TIME are refused; UNLOCK, LOCK_NOW, SET_PIN and DISABLE work. Back (0x3b) passes to stock while the glasses are dark and is consumed while any lock screen is up. While the failure notice is up every knob and key input is consumed; a press dismisses it.

## 3. On the glasses

All screens follow the glasses rules in `docs/design-system/README.md`: 540×180 page, primary content in band B, no boxes, focus shown by brightness and the caret, hints in band T for 3 s.

**PIN entry.** Four slots centred in band B at `lens-hero`. Entered slots are dots at `lens-high`. The focused slot shows a digit at `lens-full` with the caret under it. Empty slots are short `lens-track` bars. The focused digit starts at 0 for every slot (never at the previous digit, which would leak it). Band T shows the time and battery at `lens-mid`, and the hint "Wheel: digit · Press: next" for 3 s.

- Turn: change the digit, one step per `lens-wheel-detent`, wrapping 9 → 0.
- Press: accept the digit and move on. The fourth press submits.
- Long press: back one slot. On the first slot, leave to dark.
- Five-press and the 5 s and 8 s holds are never consumed. They stay stock.

**Wrong PIN.** Band B shows "Wrong PIN" for 2 s, then the slots again, or the waiting screen. Free tries and delays: 3 free tries, then 30 s, 1 min, 5 min, then 15 min before every later try. The count resets on a successful unlock by knob or phone.

**Waiting.** Band M "3 wrong tries", band B "Try again in 0:30", counting down. Knob input is ignored. The remaining delay is kept across a reboot (§7).

**Failure notice** (owner requirement). After an unlock that follows wrong tries: band M "since last unlock", band B "3 wrong tries". A press dismisses it and shows whatever was on screen before the lock. The phone page shows the same count until the user dismisses it there.

**After unlock.** The cover lifts and the page underneath is as it was. Notifications that arrived while locked are not shown later.

**No menu item.** Locking on demand is on the phone only.

## 4. On the phone

A hub row "Glasses lock" in the Glasses section, shown only when the glasses report the lock capability. Its subtitle is the state: "Off", "Unlocked", "Locked".

The page (inset grouped, per the phone rules):

- **Lock with PIN** switch. Turning it on asks for a new 4-digit PIN twice, then sets it. Turning it off asks for confirmation.
- **Status** row: symbol plus word. When there were wrong tries: `status-warn` "3 wrong tries since last unlock" with a "Dismiss" action.
- **Unlock glasses** (the one filled button) while locked; **Lock now** (secondary) while unlocked.
- **After folded** and **When idle**: 1 to 240 minutes each, defaults 5 and 5.
- **Stay unlocked while worn** switch, with the footer "Uses head motion. Works after this phone has connected to the glasses. When off, the glasses lock after the idle time even while worn." See §7.
- **Change PIN**. Does not ask for the old PIN, so it is also the "forgot PIN" path.
- Footer: "The phone paired with the glasses can always unlock them."

No secret is kept (owner, 14:52). Whichever phone is currently paired with the glasses and runs the addon can do everything on this page. Nothing about the lock is stored on the phone except the "Stay unlocked while worn" switch and its early-drop counter (§7): the page reads the state from the glasses each time.

Strings in EN and ZH through `TIOText()`. Preview fixtures for: off, unlocked, locked, locked with wrong tries.

## 5. Phone command

One new command family, `TLK:` (phone to glasses, record magic `TLK1`) and `TKA:` (reply, record magic `TKA1`; `TLA:` is already the language family's reply tag), in the existing 74-byte carrier on business 15, with the existing 32-byte CRC'd record and the existing query-then-set exchange (a QUERY returns a token; a change must carry it within 120 s). Block B's layout in `b/logs/b3-b5-design.md` §B3 is the starting point, simplified because there is no secret:

| Op | Does |
|---|---|
| QUERY | Returns enabled, locked, wrong tries since last unlock, seconds of delay remaining, the two times, and a token |
| UNLOCK | Unlocks; clears the knob wrong-try count and delay |
| LOCK_NOW | Locks |
| SET_PIN | Sets or replaces the PIN (4 digits) and enables the lock |
| SET_TIME | Sets the fold delay and idle time |
| DISABLE | Turns the lock off |
| ACK_FAILURES | Clears the "wrong tries since last unlock" count |
| MOTION_ON | Switches the motion hook on until the next reboot (§7). QUERY reports whether it is on. |

There is no keyed hash and no answer field. The protection is what the other commands already have: bonded, connected, a fresh token.

The `TLK:` gate is: no OTA running, bonded, connected. It does not depend on fold state or on which app is on top. While locked, `TGR` input injection, the knob lease and all other settings commands are refused; `TLK:` is the only family that answers.

A new capability bit (`TD_CAP_PIN_LOCK`, bit 11) tells the phone the firmware has the lock; both copies of the diagnostics codec change together.

## 6. Hiding the display

- Primary: while Locked, dark, the display is kept off by gating the screen-on requests (§7), so nothing has to be covered.
- During PIN entry: a cover object on the system layer with the active screen and top layer hidden (Block B1, shown in the emulator), and the PIN view created on top of it. Whenever the system layer gains a child while the cover is up, the cover and PIN view are re-created so they stay last in z-order.
- Backstop: if the cover cannot be created or is not the last child, force the display off (`nav_force_off`). A dark panel is always the failure state.

Not yet shown: a toast, call or assistant view arriving during PIN entry. It goes on the owner's device checklist.

## 6a. Nothing can be started while locked (from Block C, `b/REPORT-C.md`)

This is the part the lock exists for (§1a). Three gates, each at a point every path has to pass:

1. **Input gate.** The key and knob capture of §7. While locked it stops the knob double press, which in stock starts the assistant, and with it every quick-launch slot (recorder, AI subtitle, prompter, lifelog, to-do, conversation, navigation), the media gestures and the app list. Shown in the emulator: with the locked flag set a double press started nothing and no assistant message left the glasses; with it clear the stock chain ran.
2. **Assistant gate.** Every assistant start on the glasses, including the wake word, passes stock's own check `AssistantService::canWakeup` (0x1057f034), which already refuses for eight reasons. "Locked" becomes a ninth. It sits before the only place the glasses tell the phone a session began, so nothing leaves the glasses.
3. **Microphone gate.** The phone can start a session in a way that skips that check, so the single function that opens the microphone (`openRemoteAudioStream`, 0x10582878) also refuses while locked. This one point covers assistant, recorder, captions, lifelog and conversation assist, whoever started them. Nothing is exempt.

Also:

- **Wake word.** Stock already switches the wake-word engine off while folded and in sleep. While locked and unfolded, the design switches it off with stock's own switch to save power. That switch is not acknowledged, so it is a saving only; gates 2 and 3 are what guarantee nothing starts.
- **Unlock must not replay input.** Events that arrived while locked are consumed and dropped, and the button queue is flushed at unlock. In the test, a gate that merely skipped the read let one stale event start the assistant at unlock.
- **Stock gestures left alone:** five-press with the 3 s hold (factory reset) and the 5 s hold (rebond, which stock allows only while folded). Block C proposed consuming the rebond hold while locked; under the owner's scope it stays stock.
- **Five-press alone opens stock's factory test page.** With the display gated and input captured it should be invisible and inert; the build must confirm that, and close the page if it opened.
- The phone page says "Locked", so the user knows why the assistant does not answer.

Not shown in the emulator, so on the owner's device checklist: the wake word while locked (the emulator has no model of that processor), and a phone-started session while locked (the emulator's phone side cannot answer one). Both rest on reading the code. One stock callback on a wake-word hit (0x1058098c) is undecoded and may drive an LED or vibration; the build decodes it and gates it if so.

**What is being protected on the glasses themselves:** the to-do and schedule lists and the dashboard widget configuration are stored on the glasses. Whether memories, recordings or cached notifications are too was not traced; most assistant data lives on the phone or in the cloud and is reached through the gates above.

## 7. Input, timing and reboot (from Block A; A3 idle signal and A5 still to come)

**Input while locked.** Two hooks, both shown in the emulator with a stock app on top (`a/REPORT-A.md`, runs LKON-R3 to R7):

- Keys: a node at the tail of the stock input interceptor registry. While locked it consumes confirm (0x3a), double (0x45), triple (0x46) and the hold keys 0x43 and 0x3c. The 5 s hold (0x44, rebond) is passed through to stock. It never sees five-press (0x42/0x47), which stock's own head node takes first, so the factory-reset gesture is untouched by construction. Back/hold-1 (0x3b) is consumed only while the PIN screen is up, where it means "back one slot".
- Knob: a wrap of the encoder read callback. While locked it does not call the original, which is intended to stop both the LVGL step and the raw wheel broadcast that feeds the launcher carousel.

Must be proven by the build before any device step:

1. Not calling the original really freezes the launcher carousel, and the undrained wheel topic does not replay a backlog of steps at unlock.
2. Stock lifecycles reset the read-callback slot (1 to 2 times per test window). The test patch re-asserted it on a 1 s tick. The build must close that gap (re-assert from the events that reset it, not only from a tick) so that no knob step reaches a stock app while locked.
3. Keys 0x43, 0x44, 0x3c, 0x45 at the tail node were read statically only; exercise each in the emulator.

**Staying dark.** Gate the screen-on request (`nav_screen_on`; `focus_screen_on` is only a getter on 1.0.6.11) on the lock state and hold the module's existing type-3 wake-lock pattern, the same way stock stays dark while folded. The stock fold veto is left alone. The wake-source list on 1.0.6.11 (charger, alarm) is not complete; the backstop in §6 covers what the gate misses.

**Clock.** The boot-relative millisecond clock resets at reboot and is not shown to count through sleep. The only source that should survive both is the PMU real-time clock (getter at 0x1045e794 on 1.0.6.11). It counts through sleep in the emulator; on the real glasses that is a device check.

- Fold and idle decisions compare PMU clock readings at unfold and at screen-on.
- If a reading is missing, zero, or earlier than the stored one, treat the time as elapsed and lock. A clock fault never keeps the glasses unlocked.
- Until the device check passes, this is the weakest part of the design.

**Idle (from Blocks D and E; owner decision 19:18).** "In use" is knob or key input, or head motion. Glasses that are worn stay unlocked; glasses lying still lock after the idle time.

*Where the motion signal comes from.* The head-up detector runs on the Bluetooth processor (`nuttx_bth.bin`). For every window of samples it already computes a spread value and a "moving" flag. A small patch there (Block E: 8 stock bytes changed, a hook of about 344 bytes appended) sends the main processor one short message when motion is seen, at most once every 30 s, and nothing while still. Our module on the main processor receives it and records the time of the last motion.

*Off by default, switched on by the phone.* This is the first time the Bluetooth image is modified, and a fault in the hook stops that processor, which drops the phone link. So:

- After every boot the hook is off. Off means the patched site does exactly what stock does: its first instructions test an enable flag that is zero at boot.
- The phone page has a switch, "Stay unlocked while worn". When it is on, the addon sends a "motion on" command each time it connects to the glasses. The module then sets the enable flag. Nothing on the glasses switches the hook on by itself, and the setting is not stored on the glasses.
- If the link drops within 60 s of sending "motion on", the addon counts it. After two such drops in a row it turns the switch off and says why. The user can also turn the switch off at any time, including while disconnected; the next boot of the glasses is then clean.
- A reboot always returns the hook to off.

*The rule.* The glasses lock once the last motion message and the last knob or key input are both older than the idle time. Once that has happened they are locked, even if they are then picked up. Motion never delays the fold lock. A display wake caused by a notification, a call or the phone does not count as use.

*While the hook is off* (switch off, or no phone has connected since boot) there is no motion signal, and only knob and key input count as use. The glasses then lock after the idle time even if worn. The phone page says so under the switch.

*Thresholds.* The first build uses the detector's own "moving" flag and spread value. Whether the vendor's bar separates "on a head" from "on a desk" well enough is a device calibration.

Accepted limits (owner): unfolded glasses in a bag or a moving car do not idle-lock. A wearer who stays perfectly still for the whole idle time is locked and enters the PIN.

Must be established by the build before the owner is asked to flash, because the emulator cannot show them:

1. What the update installer and the boot code check on the Bluetooth image (Block E found one marker word checked at boot; the installer's own checks, the partition size limit and who writes the marker are unknown). If these cannot be established from the code, the hand-off says so plainly.
2. That with the flag clear the patched image behaves as stock in the emulator, run against a stock control, including pairing, head-up, sleep and wake.
3. How the main processor sets the enable flag on the real hardware (the emulator shows that memory through an alias; that may not hold on the device), or another way to deliver "on".
4. Every branch of the hook executed in the emulator with scripted sensor values, including a stop, still, resume cycle with a second message.
5. What a user does to restart the glasses if the Bluetooth processor stops, and that a restart brings it back with the hook off.

Not used: forwarding the raw sensor stream to the main processor (Block D). It changes no stock bytes and stays the fallback if the Bluetooth patch cannot be shipped.

**Boot.** Lock state is read from the stored record at the first point our module runs, and the display is gated before the first content frame. The boot animation is stock's own and comes earlier. Measured in the emulator: launcher view appears at 21.2 s, first frame ready at 22.2 s, the first launcher message reaches our module at 23.2 s. The build must show which of our hooks runs before 22.2 s and that the gate is set there; if none does, a new early hook is needed.

**Reboot routes.** Power off and on, and the restart after an OTA, are ordinary cold boots and start locked. Battery-flat shutdown, crash restarts and the watchdog are not characterised. The design does not depend on them: the enabled flag is stored, so any boot of any kind starts locked.

**Wrong-entry delay across reboot.** The record stores the delay step and a PMU-clock deadline. After a reboot, if the clock is valid the remaining delay continues; if not, the full delay for that step starts again.

## 8. Stored data

One file in the existing two-copy, CRC'd, generation-numbered pattern under `/mnt/nand_data/`: `turbo_lock_v1_{0,1}.cfg`, holding enabled, fold and idle minutes, salt, salted PIN hash, wrong-try count, wrong tries since last unlock, delay step and delay-until.

Start-up rules:

| Lock record | Result |
|---|---|
| No file exists | Off |
| Good, enabled | Locked |
| Good, disabled | Off |
| Both copies damaged | Locked; knob entry refused: a press shows "Use phone" in band B for 2 s, then dark; the paired phone unlocks and sets a new PIN |

"No file exists" must mean Off, or an upgrade from TMG12 would boot locked. Disabling the lock deletes nothing; it writes enabled = 0, so a missing file is never the result of normal use.

Writes happen on settings changes, on wrong tries, and when wrong tries are cleared (an unlock that follows wrong tries, and the phone's ACK_FAILURES).

## 9. Ways out

| Situation | Way out |
|---|---|
| Forgot the PIN | Change PIN from the paired phone |
| Phone lost, PIN known | Unlock by knob. A new phone, once paired, can manage the lock. |
| Phone lost and PIN forgotten | Pair a new phone and use Change PIN, or the stock factory reset: five knob presses, then a 3 s hold within 15 s. The reset erases everything under `/mnt/nand_data/` except the OTA folder, so the lock file goes, along with the pairing. Read from the code only (`a/a5-factory-reset.md`); one call hop to the erase routine is unproven and no reset has been run. |
| A lock bug leaves the glasses dark | Unlock from the phone, or re-flash from the phone. The lock never touches the OTA path or the link. A re-flash of our firmware keeps the lock file; flashing stock 1.0.6.11 leaves it unread. |

Because flashing our firmware again brings an old PIN back, the firmware README must say so.

## 10. Not in this release

Automatic unlock near the phone, Face ID, PINs longer than 4 digits, a lock item in the glasses menu, a phone-only lock without knob entry, wear-sensor based locking.

## 11. Tests

- Host tests: every row of the state and start-up tables; delay schedule; delay kept across a simulated reboot; `TLK:` with a good, a replayed and an expired token; `TGR` refused while locked; the focused digit always starts at 0; every trigger in the Block C list does nothing while locked.
- Emulator on 1.0.6.11: lock at unfold after the delay and not before; idle lock; knob PIN entry over a stock app; nothing visible while locked; assistant trigger starts nothing while locked; phone unlock; failure notice; 24 boots all locked; reboot during a delay; upgrade from TMG12 with no lock files boots unlocked.
- Phone: command tests in the `MenuLayoutTests.m` pattern, catalog test, preview matrix for the four fixtures.
- Owner device checklist: PMU clock counts through sleep, deep sleep and reboot; phone link while folded and after 2 h folded; call and toast during PIN entry; OTA while locked; real knob feel for digit entry; motion thresholds against real wear and a desk; motion hook on and off, and the app switching it off after two early link drops; battery with the lock on and off; wake word and assistant key while locked; idle lock while worn.

## 12. Open points for the owner

None at present. Settled at 14:44 to 14:52: the failure warning is on the glasses and the phone page only; the PIN alone does not turn the lock off; no shared secret.
