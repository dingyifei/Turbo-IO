# Porting flow

How Turbo-IO moves to a new RayNeo release (a new Strix OS firmware, a new RayNeo AI app, or both). This is the regular flow. It was set by the owner on 2026-11-15, after the TMG12 port to Strix OS 1.0.6.11 took far longer than it needed to. The safety rules in [AGENTS.md](../AGENTS.md) still apply to every step.

## Before any work: the whole plan, once

Present the owner with the full plan before starting, from the first build to the flash, in one piece:

- every step below with a rough size;
- what changes for the user (anything that is not like for like), as questions with the default after each;
- what is left out and why.

The owner cuts or adds, then gives one go. Do not approve the firmware part first and discover the phone part later.

## The steps

1. **Rebase.** Move every patch site and stock address to the new stock image. The address table is derived from the image bytes and re-derived by an independent test.
2. **Port.** Carry the module over like for like. Change behaviour only where the new stock forces it (a moved field, a new stock tile) or where the owner asked. Stock layout facts get a name and a proof from the stock image.
3. **Build.** One build, the normal release candidate ZIP (`...-CANDIDATE-NOT-APPROVED.zip`). No separate emulator-only build: a ZIP cannot be flashed until it is pinned in `releases.json`, and it is not pinned until the owner says so.
4. **Check.** On the last commit: the firmware-only gate and the quick gate, a second build that is byte-identical, and the static check that no patch sits on the path from boot to Bluetooth advertising (the glasses roll back on their own only if advertising has not started within 10 s).
5. **Emulator.** One round on the candidate: boot, advertising, the menu arms, each page opens and closes, plus one case for each behaviour change. Fix real defects. Run again only if code bytes changed.
6. **Phone.** Make the phone build for the current RayNeo AI version able to flash the candidate: the update-route patch for that app version, the host checks, a release entry with generated pins. Flashing first; phone features that depend on the new firmware (for example the tile list) can follow in a later build if they fail safely in the meantime.
7. **Flash.** One question to the owner: flash, yes or not yet. The owner installs the phone build, arms it and flashes. The phone's gate refuses anything it does not expect and nothing is flashed in that case, so a refused first attempt is the dry run: export the log, fix the build, try again.
8. **After.** The owner's device check. Tags, pushes and release notes follow on the owner's OK.

## How careful

Careful work, with an independent review, goes only where a mistake can brick the glasses or lock the phone out:

- the path from boot to Bluetooth advertising;
- the menu's arming check and its fall-back to stock behaviour;
- the build reproducing byte for byte;
- the phone's flash gate and arming logic.

Everything else gets one pass and the gates.

## Not part of the flow

Do these only when the owner asks for them:

- a rollback plan, a recovery build made in advance, or a stock-first flash. If a build does not work, the owner waits for a corrected build, or goes back to the stock firmware the build is based on. Both flash from the same phone build; the stock package is pinned as a release when it is needed, not before;
- spec and critic rounds, acceptance matrices, per-commit gates;
- static studies of stock code that the port does not touch;
- lint, naming and witness work beyond the lines the port changes;
- forced-failure images, extra emulator rounds on unchanged code;
- a multi-question decision package.

## Records

One status file per port, kept current, and the owner's decisions as questions with defaults on the progress page. When an answer could be read two ways, ask again with lettered options before building on it.
