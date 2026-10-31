# Native module loader: implementation proposal (TMB1)

Status: PROPOSAL, docs only. No code, no firmware change, no patch site, no image. Nothing here is approved, built or flashed.

Basis: the TMG4 stock-loader research (`overnight/tmg4/loader-research.md` in the `turboio-inputs` workspace, dated 2026-10-27, static analysis of stock Strix OS 1.0.5.5 `nuttx_ap.bin`, SHA-256 `b3d6d9d7a4ece97e1dbaa64fc080eb5db8a5f7c9fecf340888ebb97a9112cc6c`), plus the firmware notes in `firmware-research/` (current candidate tree `firmware-research/strix-1.0.5.5-tmg7/`). Every stock address below belongs to that one SHA and to no other build. This document adds no new evidence; where the research is silent it says so.

## 1. Summary

Stock firmware contains native-library loading code. The research found `dlopen`, `dlsym`, `dlclose`, `dlerror`, `insmod`, `rmmod`, `exec`, `execve` and `posix_spawn` with real export-table entries, plus a builtin `loadable_lib_test` application that calls `dlopen(path, 5)`, resolves five demo functions and calls them. That proves a compiled call path exists. It does not prove that a module can be loaded and run on the glasses.

The proposal is to not use the stock loader at all. Instead, define a small custom container (TMB1), a narrow numeric host API, a signed manifest, two NAND slots with an A/B selector, and explicit launch only. The stock ELF modlib backend is not relied on, because its relocation, architecture and allocation behaviour is not audited.

Native loading is gated behind five stages (section 8). The first blockers are unresolved facts about the hardware and firmware, not design choices. If they cannot be resolved, the correct outcome is to stop and keep declarative apps (`firmware-research/strix-1.0.5.5-tmg7/src/app-runtime-v1/app_runner.c`) as the product direction.

## 2. What is established and what is not

| Question | State |
|---|---|
| Stock has loader code with export pointers | Established (static) |
| Stock has a builtin loadable-library demo that calls `dlopen`/`dlsym`/`dlclose` | Established (static) |
| The modlib backend is ELF-oriented (reads a 52-byte header, checks `7f 45 4c 46`, checks type 1 to 3) | Established (static) |
| `execve` reaches an `exec` that walks registered binary-format handlers | Established (static) |
| Which handlers are registered at runtime, and whether an external ELF handler exists | UNKNOWN |
| Full ET_REL / ET_EXEC / ET_DYN and relocation support, architecture restrictions | UNKNOWN (not audited) |
| Whether any shell or menu exposes the demo, and whether permissions allow it | UNKNOWN |
| Whether any matching file exists on NAND or any load has ever succeeded | UNKNOWN (nothing was run) |
| An executable region for loaded code | NOT ESTABLISHED (see 6) |
| Cache maintenance and MPU transitions for freshly written code | UNKNOWN |
| Total PSRAM, free headroom, aliasing, permissions of module allocations | UNKNOWN |
| Per-module fault containment or restart | NOT ESTABLISHED; none assumed |
| Execute-in-place from NAND | NOT ESTABLISHED; treated as absent |
| A stable vendor ABI, version negotiation, C++ ctor/dtor or exception guarantees | NOT ESTABLISHED |
| How the supplied `dlopen` mode argument is used | Not used in the inspected wrapper; do not assume RTLD semantics |

Negative finding worth repeating: the stock PSRAM protection routine loads two text-bound literals that are both `0x18000000`, so that interval is empty and the branch is skipped. A PSRAM diagnostic name is not evidence of an executable PSRAM region.

Method limits of the source research: linear disassembly of a raw binary, literal pools decode as instructions, branch scans are candidate references only, and the temporary ELF wrapper used for disassembly carries no real stock symbols. Findings are strong for "this code exists" and weak for "this code is reachable and works".

## 3. The TMB1 container (design only)

A small custom container, produced by an offline packer. A standard ELF toolchain may be an offline intermediate only; the packer emits a restricted deterministic runtime image and rejects anything outside the accepted profile. Little-endian throughout.

### 3.1 Header (160 bytes)

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | magic `TMB1` |
| 4 | 2 | version, `1` |
| 6 | 2 | header bytes, `160` |
| 8 | 4 | flags, initially `0` (nonzero rejected) |
| 12 | 2 | machine (ARM) |
| 14 | 2 | ABI id (an explicit Cortex-M33 Thumb, hard-float profile) |
| 16 | 4 | total file bytes |
| 20 | 4 | code bytes |
| 24 | 4 | read-only data bytes |
| 28 | 4 | initialized data bytes |
| 32 | 4 | zero-data (bss) bytes, no file bytes |
| 36 | 4 | entry offset, inside code, halfword-aligned (loader sets the Thumb bit) |
| 40 | 4 | relocation count |
| 44 | 4 | import count |
| 48 | 4 | requested stack bytes |
| 52 | 4 | requested context/heap quota bytes |
| 56 | 32 | exact accepted firmware build identity hash |
| 88 | 32 | numeric host-API schema hash |
| 120 | 32 | payload SHA-256 |
| 152 | 8 | reserved, all zero |

The firmware build identity is the same kind of value as the build-identity sha256 that proves which TMG build is running (`identity.sha256` in the build output, see the TMG7 README). A module is bound to one exact build; there is no cross-build compatibility promise, which matches the research finding that no stable vendor ABI exists.

### 3.2 Payload

In order: code, read-only data, initialized data, sorted relocation records, sorted `u16` import IDs. Section padding and the execute/write boundaries are canonical, counted in the sizes and the hash, and aligned to the memory and MPU requirements once those are proven (they are not proven today).

### 3.3 Relocation subset

Each record is 12 bytes: destination offset `u32`, source/addend `u32`, kind `u16`, reserved `u16 = 0`.

Allowed kinds only:

- Local-image absolute pointer (an address inside the module's own image).
- Allowlisted host-function import, resolved by numeric import ID.
- Local Thumb function pointer, only through an explicit checked kind or a single defined bit-0 convention. Ambiguous encodings are rejected.

Rejected: symbol strings, external absolute addresses, ELF dynamic sections, TLS, C++ constructors, exceptions, dependency loading, lazy binding, general branch relocations. Modules are compiled to call the host through the host table (indirect calls), and the packer checks the instruction and relocation profile offline. This is a compatibility check, not a sandbox.

Parser rules: check every sum, product and interval before allocating; require the exact file length; reject overlapping or duplicate relocation destinations and any write outside validated regions; resolve every import before entry is called.

### 3.4 Numeric host-API IDs

Imports are `u16` IDs into a versioned host table, never names and never stock addresses. The stock export table (627 records, 614 unique names, a runtime export table and not a linker map) is deliberately not exposed. Proposed host operations, all handle-based and bounded:

- UI actions through a host executor (no raw LVGL pointers).
- Scoped storage (a per-module directory, no unrestricted filesystem handle).
- Monotonic time.
- Bounded logging.

No direct OTA or boot access. The ID assignments, the table layout and the schema hash are all unwritten; this document does not invent them. They are a stage 4 deliverable.

Lifecycle: one entry point receives the versioned host table and a per-instance context and returns a validated descriptor for `start`, `event` and `stop`. The context owns all state; the module image has no writable global registry. The existing heap `Control` and bounded timer lookup in `firmware-research/strix-1.0.5.5-tmg7/src/global-remote-v1/remote_native.c` are an ownership precedent only. Host caps do not constrain arbitrary native stores unless a hardware boundary is separately proven.

### 3.5 Size caps (provisional)

One resident module. File at most 64 KiB. Total image including zero-data at most 96 KiB. Stack at most 8 KiB. Context/heap quota at most 16 KiB. At most 256 relocations. At most 64 imports.

These are parser and allocator rejection limits for host tests. They are not a claim that the device has that much free executable memory. They are expected to be lowered after measurement, and the measurement does not exist yet.

### 3.6 Signed manifest

The whole header and payload are bound to a release manifest authenticated with a pinned signing key (or an equivalent trust scheme the user approves). A CRC or SHA alone detects corruption and does not authorize code. Signature verification does not exist in stock and is a requirement of this design, not an inherited capability. There must be no unauthenticated native-code carrier, and in particular the existing declarative app transfer must not be reused as one.

Open decisions for the user: which key scheme, where the public key lives, how it is rotated or revoked, and who holds the signing key. None of these is decided.

## 4. A/B NAND slots and explicit launch

Storage: NAND is a littlefs file store (`/mnt/nand_data`). A module file lives in a dedicated bounded directory below `nand_data`, separate from the resource A/B device names and from any OTA or boot namespace. NAND bytes are never executed in place.

Slots: two fixed package slots (A and B) and a small selector record, distinct from boot and OTA metadata. A write is complete only after write, flush/fsync, full readback, digest check and manifest verification; only then is the selector moved to the new slot. The existing application store reread and generation check (`firmware-research/strix-1.0.5.5-tmg7/src/app-runtime-v1/app_store.c`) is a local precedent, and its declarative codec is not the native codec. If the selector is missing, corrupt or ambiguous, behaviour reverts to stock with no module available. Generation counter exhaustion must be handled and tested.

Launch: explicit only. Selecting a slot makes a module available for a later user-initiated launch. Nothing is loaded at boot, nothing scans directories at startup, and no module can be started by a phone message alone without the same gate the declarative path uses. Loading is lazy and the feature ships disabled. The existing `allowed()` policy in `remote_native.c` is a policy reference, not permission to add a native-code transport.

## 5. Memory and fault policy

Memory (policy, because the facts are missing):

- Code runs only from a region proven executable. Today none is proven (section 6). Candidate paths are the appended flash mapping (how current firmware additions run: `firmware-research/strix-1.0.5.5-tmg7/link.ld` places the module near `0x1086fec0` and asserts it ends below `0x10b7fff8`, with no writable `.data` or `.bss`) or an executable RAM/PSRAM region that has not been shown to exist. Flash-resident additions are build-time only; they do not give runtime-loaded code a home.
- Loading is: validate from NAND, copy into the proven region, relocate while writable and not executable, then perform a proven cache and MPU transition and instruction synchronization before the first call. If that transition cannot be done without weakening existing protections, native execution is rejected, not worked around.
- `malloc` alone gives no executable-memory guarantee.
- A module cannot be allowed to overwrite startup, OTA or boot metadata by host API design; whether hardware prevents it is a separate unproven question.

Fault policy:

- Initially modules are trusted, signed code. A fault in a module can be a fault in the firmware. The research found hard-fault handler strings but no per-module containment or restart, and a task is a scheduling context and stack, not a memory boundary. Do not claim crash isolation from task creation.
- Watchdog and cooperative instruction or time budgets can detect some failures. They cannot make arbitrary native code safe.
- Unload: `dlclose` cannot repair corrupted memory or guarantee that callbacks, timers, threads and LVGL objects have stopped. The first prototype keeps one validated module resident until reboot, with a logical `stop` only. Real unload needs a quiescence protocol that is not designed yet.
- On any fault, validation failure or ambiguous state, the stock behaviour stands and the module is not auto-retried at the next boot (there is no boot-time launch).

If native isolation cannot be established, the options are to restrict native modules to trusted signed code with that risk stated plainly, or to drop native modules and keep the declarative runtime.

## 6. Open blockers

1. Executable region unproven. No executable heap or safe PSRAM code allocator is shown. The PSRAM protect routine's empty interval is not evidence for one.
2. binfmt handlers unknown. The exec path walks a handler list; the list contents, its initialization and any external ELF handler are not established. The modlib ELF loader must not be equated with a registered exec handler. `posix_spawn` may only reach builtins.
3. No XIP. NAND is file storage; code must be copied and cache-synchronized.
4. No isolation. Module function pointers are called directly in the caller's context in the stock demo; no MPU use for add-ons is shown.
5. No safe `dlclose`. See section 5.
6. Cache and MPU behaviour on freshly written code, and free RAM or PSRAM headroom: unmeasured.
7. No signature scheme or key custody exists yet.
8. ABI: no vendor contract; the host table is ours, bound per build identity.

Blockers 1, 2 and 4 are the first-order ones. A module proposal that does not resolve 1 stops there.

## 7. Non-goals

No loader code in any TMG build. No change to `firmware-research/` trees, patch sites or pins. No use of the stock `dlopen` or exec path from the phone. No NAND write, flash or device communication as part of any stage before stage 5. No change to OTA or boot logic.

## 8. Gated path

Each gate has exit criteria and what it needs from the user. A later gate does not start until the earlier one is accepted.

### Stage 1: static mapping

Goal: turn the candidate findings into corroborated facts about the stock AP.

Work: pin the same AP hash; trace binary-format registration, builtin command dispatch, exec symbol-table initialization, modlib allocation, relocation and cache code, and architecture checks; identify function boundaries by corroborating call sites rather than string names; resolve whether `exec` handles an external ELF or only builtins; produce a minimal export allowlist with source and ABI receipts.

Exit criteria: written receipts for every item above, each with addresses against the pinned SHA; a yes/no answer on external-ELF exec; an explicit list of what stays unknown.

Needs from the user: approval to spend analysis time; confirmation of the AP hash to analyse (stock only, and whether other builds matter); no device access.

### Stage 2: host-only fuzzed parser

Goal: a TMB1 packer, parser, manifest verifier and relocation resolver that run on the host against fixtures and a fake allocator and fake host API. No image integration.

Work includes ASan and UBSan, and fuzzing: truncated headers; oversize and overflowing sizes and counts; overlaps; duplicate relocations and imports; unknown ABI or flags; bad signatures and hashes; entry out of bounds; every allocation failure; interrupted A/B writes; corrupt or missing banks; generation exhaustion. Accepted metadata is compared against an independent reference parser. Packer output must be byte-deterministic.

Exit criteria: fuzz corpus and sanitizer runs clean for an agreed duration or iteration count; zero disagreements with the reference parser; deterministic packer receipt; documented reject reasons for every malformed class.

Needs from the user: decisions on the signature scheme and key custody (section 3.6); the fuzz budget; acceptance of the size caps as host-test limits only.

### Stage 3: offline ARM proof

Goal: show that one freestanding Cortex-M33 arithmetic module with a context and no hardware calls can be packed within the accepted profile.

Work: cross-compile it; inspect every import and relocation; exercise it only on an already-available, accurate-enough local emulator or harness. Nothing is installed for this.

Exit criteria: packed module passes the stage 2 parser; the relocation and import inventory matches the profile; emulator run result recorded, with the emulator's fidelity limits stated. Hardware, MPU and cache behaviour are explicitly recorded as still open.

Needs from the user: whether an emulator may be installed if none exists (the research did not authorize any install), and whether stopping after stage 3 for lack of one is acceptable.

### Stage 4: implementation proposal

Goal: a separate reviewed proposal, not code.

Contents: the TMG-specific patch budget; the executable-region answer from stages 1 and 2 (or a decision to stop); the host table with real ID assignments and schema hash; heap quotas; lifecycle and stop behaviour; fault policy; recovery path; proof that boot and OTA boundaries are unchanged; the feature stays disabled by default and absent from the current candidate.

Exit criteria: user sign-off on the document, or a recorded decision to abandon native modules.

Needs from the user: the go or no-go decision, the risk acceptance for trusted-code-only if isolation is absent, and the target TMG version for the work.

### Stage 5: hardware acceptance

Goal: device verification on glasses. This is a separate phase and requires its own new approval and a recoverability plan; nothing before it authorizes it, and no host test or static call path counts as device acceptance.

Checks: RAM headroom; a known-good inert module loads; incompatible and corrupt modules are rejected; stop behaviour; watchdog and fault handling; power-loss recovery of slot selection.

Exit criteria: each check recorded on the device with the build identity, and a rollback verified.

Needs from the user: explicit approval, the device and its recovery path, and acceptance of the known risk that a bad flash can brick the device. The firmware notes already state that rollback is not guaranteed (`firmware-research/README.md`).

## 9. What remains unknown, plainly

- Whether any native module can run at all on this hardware.
- Where it would run from.
- Whether the stock exec path accepts an external file.
- What the cache and MPU rules are for code written at runtime.
- How much memory is free.
- Whether a faulting module can be contained (current evidence says no).
- Which signing scheme the user will accept.
- Whether the stock loader's behaviour is the same on other firmware builds (not examined).
- Everything about real device behaviour, since no code was ever executed on the device.
