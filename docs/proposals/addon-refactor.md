# Addon.m refactor plan

Status: proposal, docs only. No code is changed by this document.
Base: `main` at 659fd67. All paths are repo-relative. Line numbers refer to that commit and will drift as moves land; re-derive them with the commands in "Re-deriving the map" before each step.

## 1. Why and what this plan promises

`official-addon/ios107-edition/Addon.m` is 890 lines and 71,155 bytes. Most lines are dense one-liners (many over 200 columns), and the file mixes a dozen unrelated jobs that share a handful of file-scope statics. Every feature that touches the hub, the voice takeover or the entry button lands here, so it is the highest-conflict file in the edition and nothing tests it directly: `test.py` has no `Addon*Tests.m`, and `Addon.m` is only exercised by the device build, the symbol audit and the simulator preview.

Promises of this plan:

- Behaviour-neutral. Every step is a move or a mechanical rename. No logic is rewritten, no string, key, selector, class name, load order or `#if` shape changes.
- Each step is one commit and is gated by the existing checks, plus the safety net named for that step (section 6).
- The OTA gate logic is not touched. `ExperimentalOTA*.m`, `OTAWizardModel.m`, `FirmwarePins.h` and the OTA wiring in `scripts/turbo-gate.sh` are out of scope (section 7).
- `PrivateBootstrap.h` and `PrivateBootstrap.m` are not edited, moved or renamed (section 5).

Non-goals: new features, renaming `TIOPanel`/`TIOController`/`TIORequest`, changing the Prefs suite or keychain service, reformatting dense lines. Reformatting is its own later commit, because a move whose diff is also a reflow cannot be reviewed as a pure move.

## 2. Responsibility map of `Addon.m`

| Lines | Responsibility | Notes |
| --- | --- | --- |
| 1-66 | Imports and feature switches | `TIO_APPLE_AI` (1-5), `TIO_MAPKIT_ENABLED` (27-29), `TIO_IMAGE_RX_LAB` (61-63), `TIO_DISPLAY_PHONE` (64-66). `PrivateBootstrap.h` is imported at 26. `AddonUILanguage()` is defined twice behind `__has_include("TIOLanguage.h")` at 55-60. |
| 68-72 | Target bundle id | `TargetBundle` from `TIO_TARGET_BUNDLE_ID`; build.sh passes `-DTIO_TARGET_BUNDLE_ID`. |
| 74-88 | Module state | `Domain`, `Prefs`, `Archive`, `ArchiveQueue`, `Diagnostic`, `HooksReady`, `Entry`, the five `Original*` IMPs, `VoiceExitReady`, `CompletionEvents`, `VoiceTTS`. All file-scope statics. `HooksReady` is read at 595 but never assigned `YES` anywhere in the file; the "status" row therefore always reads "off". That is existing behaviour and must be preserved by the moves, not fixed in them. |
| 90-104 | Settings: keychain | `KeyQuery`, `ReadKey`, `StoreKey` (service `Domain`, account = host), plus `TTSOn` (96). |
| 105-119 | Settings: private bootstrap import | `ImportPrivateBootstrap()`: reads `TurboIOPrivateBootstrap.json` from the bundle, validates through `TIOPrivateBootstrapConfig`, writes keychain and Prefs. Only user of `PrivateBootstrap.h`. |
| 120-131 | Support helpers | `Get` (KVC with `@try`), `String`, `TopController`, `Alert`. |
| 133-183 | Voice: model request | `TIORequest : TIOWebChatRequest`; `TIO_APPLE_AI` adds `startAppleQuestion:` and a `cancel` override (145-156) and branches inside `startQuestion:` (158-175). |
| 185-328 | Voice: takeover controller | `TIOController` (properties 185-208), the global `Controller` (209), `CopyResponse` (211-220), and the methods `acceptAsr:`, `emitText:`, `receiveNlp:`, `takeLocalTurn:` (303-310, `TIO_APPLE_AI`), `observeOfficialVoice:`, `completeOfficialVoice`. |
| 330-405 | Voice: hook trampolines | `AsrHook` (331-347 with `TIO_APPLE_AI`, 349-361 without), `AudioStartHook` (364-373), `NlpHook` (375-386), `CompleteHook` (388-397), `AlwaysOnHook` (398-405). Each of the first four exists twice under `#if TIO_APPLE_AI` / `#else`. |
| 406-443 | Hub: glasses status card | `TIOHubStatusCard(...)` view builder (413-443), preceded by its comment. Pure UIKit, reads no statics. |
| 445-466 | Hub: panel interface and status bounding | `@interface TIOPanel : UITableViewController` (445-449) and `TIOHubBoundStatus` (453-466, pure string logic). |
| 468-531 | Hub: panel shell | `catalogRowForKey:`, `updateCard`, `fitHeader`, layout/trait overrides, `refresh` (495-518), `viewDidLoad` (519-526), lifecycle and `close` (527-530). |
| 531-560 | Hub: table data source | sections/rows/headers/footers (531-560). |
| 561-602 | Catalog wiring: row status | `statusForKey:` maps a catalog key to a status string from Prefs, keychain, `TIOLanguageFlagStatus`, the focus suite, OTA snapshots, `VoiceExitReady`, `HooksReady`. |
| 603-631 | Hub: accessory and cell | `accessoryForKey:` and `tableView:cellForRowAtIndexPath:`. |
| 633-683 | Settings actions | `thinking:`, `ttsSpeed`, `ttsToggle:`, `testTTS`, `voiceExit:`, `searchToggle:`, `configureAboutMe`, `configureSearch`, `testSearch`, `capture:`, `configure`. |
| 685-748 | Catalog wiring: routing | `tableView:didSelectRowAtIndexPath:` (685-690) and `openKey:` (691-748), a key-to-controller ladder with `#if TIO_APPLE_AI` (692-694), `TIO_MAPKIT_ENABLED` (697-699), `TIO_IMAGE_RX_LAB && TIO_DISPLAY_PHONE` (725-727), `TIO_IMAGE_RX_LAB` (728-730). |
| 749-772 | Feature launchers and one-shot actions | `performKey:` (mode chooser 749-760, then api, search, todo, tools, history, prompt, apiTest, archive, status). |
| 775-790 | Preview entry | `TIOCreateTurboPreview()` under `#if TIO_UI_PREVIEW`; builds a `TIOPanel` root and returns `TIOCreateTurboHub(root)` (from `ResearchUI.m:109`). It re-creates the statics the real `Load` creates. |
| 792-810 | Entry button target | `TIOInsideTurboHub` (792-797) and `TIOEntryTarget` (799-810), which presents the hub. |
| 811-823 | Host compatibility | `Signature` (811-815), the `HostCompatibility.h` import (816), `VersionMatches` (817-823). |
| 824-830 | Entry button and home tab | `AddEntry()`: creates the floating `Entry` button, then calls `TIOStartHomeTabBridge(Entry, ...)` (829) when `VersionMatches()`. |
| 831-890 | Load sequence | `__attribute__((constructor)) static void Load(void)`: defers everything to the main queue; bundle gate; `TIOStartExperimentalOTAFeedIfMarked`; Prefs suite; `TIOLanguageFlagStart`; keychain cleanup; defaults; `Controller`; `ImportPrivateBootstrap`; `VoiceTTS`; archive; class and `Signature` validation; hook installation (857-862); `TIONoNetworkInstall` under `TIO_APPLE_AI` (863-870); `TIOInstallGlassesChannelHook`/`TIOInstallTodoRuntime` (871); `TCCameraReportLoaded` (872); load report (873-884); the three entry observers (885-887). |

Observed coupling, which drives the move order: `Prefs` is read by nearly every region; `Controller` and `VoiceTTS` are used by the hooks, the hub actions and `Load`; `Signature`/`VersionMatches` are used by `Load` and `AddEntry`; `TIOPanel` is looked up by name at runtime (see risks).

### Re-deriving the map

```
grep -nE '^(@interface|@implementation|@end|static |#if|#endif|#else|__attribute__)' official-addon/ios107-edition/Addon.m
grep -nE '^- \(' official-addon/ios107-edition/Addon.m
```

## 3. Build layout and naming rules the new files must follow

From `official-addon/ios107-edition/build.sh`:

- Sources are one flat list handed to one `xcrun --sdk iphoneos clang -dynamiclib` call, ending with `Addon.m \` and then `-o "$output"`. New `.m` files are added as extra lines immediately before `Addon.m \`, after `music.c \` and the `-framework` lines that follow it. `Addon.m` stays last so its constructor remains the last initializer in link order.
- No target-specific file list exists for the core: only the `nav_options`, `image_options` and `apple_options` arrays are conditional. The new files are unconditional (the `#if` blocks stay inside them), so the three arrays are not touched.
- `-I.` is on the command line, so headers are imported by bare name. Headers are `.h` with a `FOUNDATION_EXPORT` or `extern` API of `TIO`-prefixed C functions (see `ResearchUI.h`, `HomeTabBridge.h`).
- `preview/build.sh` derives its source list by grepping `build.sh` for `*.m`/`*.c` tokens, so the new files enter the simulator preview automatically. This also means a stray `Foo.m` mentioned in a `build.sh` comment would be compiled; do not mention source names in comments there.
- `test.py` fails with "manifest mismatch" unless every `*Tests.m` under the edition is listed in `tests/manifest.json` with `status: run` and a `group`, or `status: excluded` with a `reason`. A new test needs both entries.

Naming (observed in the tree): `<Feature>.m` for logic, `<Feature>Core.m` for platform-free logic (`SubtitleHUDCore.m`, `AppleAICore.m`), `<Feature>UI.m` for UIKit, `<Feature>Bridge.m` for adapters (`HomeTabBridge.m`, `MusicBridge.m`), `<Feature>Tests.m` at the edition root for host tests, and the `TIO` prefix on exported C symbols. Proposed new files, all prefixed `Addon` so they sort with `Addon.m` and cannot collide with a feature name:

| New file(s) | Receives | Source lines |
| --- | --- | --- |
| `AddonState.h` | `extern` declarations of the shared state, marked hidden-visibility through one `TIO_ADDON_INTERNAL` macro; the only place `Prefs`, `Controller`, etc. are declared | 74-88, 209 |
| `AddonSupport.h` / `AddonSupport.m` | `Get`, `String`, `TopController`, `Alert`, `TIOHubBoundStatus` as `TIOAddon*` functions; also owns the state definitions | 120-131, 453-466 |
| `AddonSettings.h` / `AddonSettings.m` | keychain, `TTSOn`, `ImportPrivateBootstrap` (sole `PrivateBootstrap.h` importer) | 90-119 |
| `AddonHost.h` / `AddonHost.m` | `Signature`, `VersionMatches`, `TIOInsideTurboHub` | 792-797, 811-823 |
| `AddonVoice.m` | `TIORequest`, `TIOController`, `CopyResponse` | 133-328 |
| `AddonVoiceHooks.h` / `AddonVoiceHooks.m` | the five hook trampolines, the `Original*` IMPs, and `TIOAddonInstallVoiceHooks(...)` | 330-405, 857-862 |
| `AddonHubStatus.m` | `TIOHubStatusCard` and `TIOPanel (Status)` (`statusForKey:`, `accessoryForKey:`) | 406-443, 561-618 |
| `AddonHubSettings.m` | `TIOPanel (Settings)`: the settings actions | 633-683 |
| `AddonHubRoutes.m` | `TIOPanel (Routes)`: `openKey:`, `performKey:` | 691-772 |
| `AddonHub.h` / `AddonHub.m` | `@interface TIOPanel`, the shell, data source, selection | 445-449, 468-560, 685-690 |
| `AddonEntry.m` | `TIOEntryTarget`, `AddEntry`, the entry observers | 799-810, 824-830, 887-889 |
| `Addon.m` (residual, about 100 lines) | imports, `TargetBundle`, `Load`, `TIOCreateTurboPreview` | 68-72, 775-790, 831-890 |

Test files added alongside, in the same style: `AddonSupportTests.m`, `AddonSettingsTests.m`, `AddonVoiceTests.m` (only if the controller ends up host-compilable; otherwise it stays excluded in the manifest with a reason, like `HUDPreviewTests.m`).

Why categories on `TIOPanel` rather than free functions for the hub: `TIOPanel` is the receiver of runtime swizzles (section 5) and the table data-source; keeping a single class with its selectors intact, split across category files, leaves its method set identical. All category files compile in the same clang invocation, so no `-ObjC` link flag question arises. Each category method is moved, not copied: a duplicate method in a category and the main implementation is undefined behaviour in ObjC.

## 4. Ordered, behaviour-neutral move sequence

Common gate for every step (all must pass before the commit):

1. `python3 official-addon/ios107-edition/test.py ...` (as run by the gate's `test` stage; includes the manifest check and `tio-design-literals`).
2. `scripts/turbo-gate.sh --preview`: stages `private`, `build`, `symbols`, `test`, `package-test`, `source-audit`, `preview`.
3. The step-specific safety nets from section 6.
4. The surface diff (S1 below) shows no change, or only the explicitly expected additions listed in the step.

| Step | Move | Why in this position |
| --- | --- | --- |
| M0 | No code change. Land the safety nets S1-S5 on `Addon.m` as it is now, and record baselines. | Everything later is judged against these. |
| M1 | `AddonSupport` (`Get`, `String`, `TopController`, `Alert`, `TIOHubBoundStatus`). Rename call sites mechanically. | Leaf functions with no state, except `Alert` calling `TIONotice`. Smallest possible first move; proves the build.sh, manifest, preview and source-audit plumbing on a trivial diff. |
| M2 | `AddonState.h` and the state definitions (lines 74-88, 209) become non-static globals with hidden visibility. Assignments at 839-854 and 780-786 stay as written. | Unlocks every later split. Done before any code that reads the statics moves, so the later steps are pure moves. |
| M3 | `AddonSettings` (keychain, `TTSOn`, `ImportPrivateBootstrap`). | Depends only on `Prefs`/`Domain`. Isolates the `PrivateBootstrap.h` import to one file. |
| M4 | `AddonHost` (`Signature`, `VersionMatches`, `TIOInsideTurboHub`). | Needed by both the voice installer and the entry code; no UI. |
| M5 | `AddonHubStatus`: `TIOHubStatusCard`, then `statusForKey:` and `accessoryForKey:` as a `TIOPanel` category. | First UIKit move; confirmed visible in the preview `hub` screen. |
| M6 | `AddonHubSettings` (633-683) as a category. | Pure move of actions. |
| M7 | `AddonHubRoutes` (`openKey:`, `performKey:`). | Carries the highest `#if` density, so it follows two easier category moves and uses the flag-matrix compile check (S4). |
| M8 | `AddonHub` shell (`@interface TIOPanel` to a header, shell, data source, selection). | After this `Addon.m` no longer defines `TIOPanel`; the class name and selectors are unchanged. |
| M9 | `AddonVoice` (`TIORequest`, `TIOController`, `CopyResponse`). | Moved before the hooks because the hooks reference `Controller`. |
| M10 | `AddonVoiceHooks`: hooks plus a single `TIOAddonInstallVoiceHooks` that contains lines 857-862 verbatim, called from `Load` at the same position. | Riskiest step, taken last among the logic moves. The statement order within `Load` does not change. |
| M11 | `AddonEntry`: `TIOEntryTarget`, `AddEntry`, observers. `Load` keeps the same `addObserver`/`dispatch_after` calls in the same order, now calling `TIOAddonAddEntry`. | Last because `AddEntry` is a callback registered by `Load`. |
| M12 | Residual `Addon.m`: confirm it holds only imports, `TargetBundle`, `Load` and the preview entry. Optional, separate, later commit: reflow dense lines. | Closing check; no code move. |

Each step also edits `build.sh` by adding exactly its new file(s) before `Addon.m \`, and, where a host test is added, `test.py` and `tests/manifest.json`. A step is reverted by reverting its single commit; no step depends on a later step existing.

## 5. Risks

1. **PrivateBootstrap coupling.** `PrivateBootstrap.h`/`.m` are not in git (`.gitignore:26` ignores `**/*PrivateBootstrap*`). `scripts/turbo-gate.sh` `private_stage` restores both from `private-backup/ios107` outside the repo, checks `SHA256SUMS` and requires a byte-identical `cmp`. Consequences for the plan: never edit these two files; import `PrivateBootstrap.h` from exactly one file (`AddonSettings.m`, step M3), so a clean public checkout needs the restore in one place; keep `TIOPrivateBootstrapConfig` and its 16384-byte limit untouched; and keep the keychain service string (`Domain`, line 74) byte-identical, otherwise already-installed users lose the stored model and search keys.
2. **`HomeTabBridge`.** `AddEntry` passes the `Entry` button as `fallback` to `TIOStartHomeTabBridge` (`HomeTabBridge.h`), and `HomeTabBridge.m` holds it in a `weak` property (`TIOHomeTabBridge.fallback`). `Entry` must remain a strong global that outlives the bridge; the state move (M2) must keep it a strong global, not a local. `HomeTabBridge.m` is an accessibility-tree adapter over the official Flutter tab bar, is exempted by file name in `tests/design_literals.py` (`EXEMPT_FILES['HomeTabBridge.m']`), and is not moved or renamed in this plan. `VersionMatches()` gates the call (line 829) and must keep gating it.
3. **Symbol audit.** `scripts/turbo-gate.sh` `symbols_stage` runs `nm -g` on `build/mapkit/TurboIOPrivateAddon.dylib` and requires `_TIOOTAFlashBuild`, `OBJC_CLASS_$_TIOMapKitNavigationPanel`, `TIOMenuLayoutController` and `OBJC_CLASS_$_TIORoadMap`, forbids `AMapNavi`, and requires the `display extension=APP107-OTA-PHONE-01;` marker string in the binary. Turning statics into globals widens the exported surface: use `TIOAddon*` names and hidden visibility, and do not assume `nm -g` omits hidden symbols; confirm with the S1 baseline diff. The marker string is built in `Load` (875-879) and must not be altered by the load-report move.
4. **Source audit.** `scripts/check-source.mjs` (`source_audit_stage`) scans every tracked file for private keys, `/Users/...` paths, temporary public endpoints and binary extensions. New files and this document use repo-relative paths only. `tests/design_literals.py` (test group `tio-design-literals`) forbids literal colors and fixed fonts in phone UI sources; moved code already passes in `Addon.m`, but any moved code that was exempt through the `Addon.m` filename would newly fail (none is exempt today: `EXEMPT_FILES` has no `Addon.m` entry).
5. **Load order.** `Load` is a constructor that only schedules a main-queue block; the order that matters is (a) the statement order inside that block and (b) the relative order of main-queue blocks from the other constructors, which follows link order. Other constructors exist in `WatchRemoteAddon.m:157` (unconditional) and, only under hot-load defines, `RecordingExportsMenu.m:72`, `RecordingTextMenu.m:22`, `AlwaysOnAudioUI.m:43`. Keep `Addon.m` last in `build.sh`, and keep the statements of `Load` in order. Two inversions to avoid specifically: `Prefs` must be created (839) before `ImportPrivateBootstrap` (845) reads it, and hooks must be installed only after `Controller` and `VoiceTTS` exist. Keep the `TIOStartExperimentalOTAFeedIfMarked()` call where it is, before the Prefs suite.
6. **`TIOPanel` is addressed by name.** `RecordingExportsMenu.m:53` and `RecordingTextMenu.m:15` look it up with `NSClassFromString(@"TIOPanel")` and swizzle `tableView:numberOfRowsInSection:`, `tableView:cellForRowAtIndexPath:`, `tableView:titleForHeaderInSection:`, `tableView:titleForFooterInSection:`, `tableView:didSelectRowAtIndexPath:` and `viewDidLoad`, after checking argument counts and types. Those installers are reachable only through hot-load defines in this build, but the name, the six selectors and their type encodings must not change. The class stays in `AddonHub.m`; categories add other methods only.
7. **`TIO_APPLE_AI` is not built by the gate.** `scripts/turbo-package.sh:54` builds the shipped variant with `TIO_APPLE_AI=1`; `build_stage` in `scripts/turbo-gate.sh` does not, and `preview/build.sh` does not define it. Eighteen lines of `Addon.m` mention `TIO_APPLE_AI` (lines 1, 135, 145, 158, 173, 205, 290, 302, 330, 363, 374, 387, 570, 575, 692, 752, 756, 863). A move that breaks only that variant would pass the whole gate. Safety net S4 closes this.
8. **Duplicated hooks.** The first four hooks exist in two `#if TIO_APPLE_AI` / `#else` versions that are textually similar. Move both together, never merge them.
9. **Cross-file macro and symbol shadowing.** `Get`, `String`, `Alert`, `Signature` and `Load` are generic names; other files define their own `Signature` and `Load` statics (for example `RecordingExportsMenu.m`, `RecordingTextMenu.m`). Exporting them unprefixed would collide. Hence `TIOAddon*` for all exported names.
10. **Dead state.** `HooksReady` is never set; `Entry` is shown or hidden from `TIOEntryTarget` (808) and `AddEntry` (826-828). Preserve both exactly. Fixing either is a behaviour change and belongs to a separate commit with its own device check.
11. **Hardware evidence.** No gate stage runs `Load` against the real host process: `Load` returns at the bundle-id check in the simulator preview. Host and preview evidence is not hardware acceptance (see `RELEASE.md`/`README.md` language). Steps M10 and M11 therefore also need the human device check described in section 6 before the series is merged.

## 6. Test safety net to add before each move

Nets are added in M0 (before any move) unless noted. Each is cheap, runs on macOS and fits the existing `test.py` / `turbo-gate.sh` / preview structure.

- **S1. Exported-surface baseline.** Record `nm -g` output of the gate's dylib (`build/gate/symbols.txt` is already produced) plus the ObjC runtime surface (`otool -ov` class and method lists for `TIOPanel`, `TIOController`, `TIORequest`, `TIOEntryTarget`) as pinned fixtures under `tests/fixtures/`. Add a comparison to the `symbols` stage that reports any symbol or selector added, removed or re-encoded. Expected additions per step are written in the commit message (for example M2: none if hidden visibility holds).
- **S2. `Load` statement-order check.** A text-level script `tests/addon_load_order.py`, run from `test.py` like `design_literals.py`, extracts the ordered list of call names inside `Load` (and, after M10/M11, the helper functions it delegates to) and compares it with a pinned list. This is the only host-side guard for load order, since `Load` cannot run on the host.
- **S3. Preview screenshot parity.** Before M0 run `scripts/turbo-gate.sh --preview` and keep the `build/preview-shots` set for the screens `hub`, `push-*`, `ota`, `music`, `nav`, `captions`, `tiles` and `voice` in the full matrix `preview/shoot.sh` already produces (en and zh-Hans, light and dark, plus the accessibility-size pass). After each step the shots must be byte-identical (same pinned simulator, same fonts). Hash the set into a baseline file outside the repo, next to the existing `baseline/timings.txt`. Steps M5-M8 depend on this; `preview/tmg4-check.py` and `preview/wp5-check.py` remain as they are.
- **S4. Flag-matrix compile check.** `clang -fsyntax-only` of `Addon.m` and every new `Addon*.m` for these define sets: default; `TIO_MAPKIT_ENABLED=1`; the gate set (`TIO_MAPKIT_ENABLED`, `TIO_IMAGE_RX_LAB`, `TIO_DISPLAY_PHONE`, `TIO_DISPLAY_FLASH`, `TIO_OTA_FLASH_ENABLED`); and the package set adding `TIO_APPLE_AI=1` and `TIO_CLASSIC_BINDINGS` (the exact set in `scripts/turbo-package.sh:54`). The simplest form is one extra stage, `variant-syntax`, in `scripts/turbo-gate.sh`; it needs no signing and no device.
- **S5. Pure-function tests added with the step that moves them** (registered in `tests/manifest.json` and `test.py`):
  - M1: `AddonSupportTests.m` for `TIOHubBoundStatus`: limits 20 (zh) and 40 (other), emoji and ZWJ sequences not split, the ellipsis counts toward the limit, `nil`/empty/non-string return `nil`.
  - M3: `AddonSettingsTests.m` pinning the exact `KeyQuery` dictionary (class, service `io.turboio.official-private-addon`, account) so an accidental service change fails; plus `TIOPrivateBootstrapConfig` is already covered by the existing private-bootstrap checks and is not touched. Keychain reads and writes are not exercised on the host.
  - M5: a pure mapping test is only added if `statusForKey:` is first reshaped, which is itself a logic change; so none is added. Parity is carried by S3 (statuses are visible on the `hub` shots).
  - M9, M10: `AddonVoiceTests.m` is added only if the controller compiles on the host without UIKit; otherwise `tests/manifest.json` records an `excluded` entry with a reason, as `HUDPreviewTests.m` does. The existing `Tests.m`, `TodoToolFlowTests.m`, `KnowledgeToolFlowTests.m` and `WebSearchFlowTests.m` already cover `Core.m` flows used by the controller.
- **S6. Human device check for M10 and M11 only.** Install the private build and confirm: the entry button and home-tab entry appear and open the hub; one voice turn in each mode behaves as before; the hub "status" row, language row and settings rows read as before. This is outside the scripted gate, matches the project rule that host evidence is not hardware acceptance, and should be done once at the end of the series, not per commit.

## 7. The two next-largest files

### `MapKitNavigationUI.m` (741 lines, 72,232 bytes)

Compiled only with `TIO_MAPKIT_ENABLED=1`, which requires `TIO_DISPLAY_PHONE=1`; `build.sh` adds it in `nav_options` together with `NavigationGuidance.m` and `RoadTiles.m`. Structure:

| Lines | Content |
| --- | --- |
| 14-72 | file-scope C helpers: formatting (`Meters`, `Minutes`, `Clock`, 29-31), `SimSpeed`, `Transport`, `ChromeFont`, `GuideRoute`, `TurnText`, `LensSymbol` |
| 73-133 | `TIONavLensView`, the phone-side drawing of the glasses navigation page |
| 135-178 | `TIOMapKitNavigationPanel` interface (dozens of navigation-state properties) |
| 180-366 | UI construction and layout (`viewDidLoad` 216-313, sheet handling 343-366) |
| 368-437 | lifecycle, location, search |
| 438-587 | routing, start/stop, the 1 Hz `tick`, `updateAt:...`, glasses start and arrival |
| 589-737 | trace file, lens model, refresh, menu |

Proposal, same rules as above: first split out the platform-free parts, then the lens view. `NavigationLens.m` receives the formatters and `TurnText`/`LensSymbol` (lines 29-31, 51-72) together with `TIONavLensView` (73-133); the already-extracted `NavigationGuidance.m`, `RoadMap.m` and `NativeNavigation.m` stay as they are. The panel class and its routing/tick section (438-587) are not split in this plan, because the navigation state is interleaved with UI and `tests/TMG5NavigationTests.m`, `NavigationGuidanceTests.m` and `DisplayNavigationTests.m` do not drive the panel. Required net before that move: a screenshot-parity pass of the preview `nav` and `nav-active` screens (S3). The symbol audit requires `OBJC_CLASS_$_TIOMapKitNavigationPanel` and `TIORoadMap`; both names stay.

### `ExperimentalOTAUI.m` (822 lines, 43,611 bytes): frozen

This is the firmware wizard UI and carries the confirmation path to the flash gate. Its injected closures (lines 14-24 and the `+initialize` wiring at 110-135) connect to `TIOOTAFlashAuthorize`, `TIOOTAFlashCancel` and `TIOOTAFlashDisableAutoUpdate` (117-119), the `Authorize(&error)` call in `primaryTapped` (around 764, which runs on the main thread because of `TDPPhonePauseForOTA`), `refreshSnapshot` (326-356) and the action runner (689-715).

Proposal: no change in this plan. Nothing in `ExperimentalOTAUI.m`, `ExperimentalOTA*.m`, `OTAWizardModel.m` or `FirmwarePins.h` is moved, renamed, reformatted or re-exported. If the user later wants a presentation-only split, the only candidates are `buildTable`/`buildActionBar` (155-275) and `configureCell:at:` (536-647), and only with explicit user approval, the `ota` preview matrix identical before and after (S3), and the existing OTA test groups (`archive`, `directory`, `flash`, `feed`, `feed-restart`, `wizard`, `tmg4-wizard`, `ota-guard`, `phone-ota-gate`, `image-upload-transport`) unchanged and passing. The gate logic regions listed above are never part of such a split.

Because `AddonHubStatus.m` (M5) calls `TIOOTAWizardSnapshot`, `TIOOTAFlashStatus` and `TIOExperimentalOTAFeedStatus` for the "experimentalOTA" row status (lines 596-600), that code is moved verbatim as an unchanged call expression; it only reads status and does not change any gate decision. Reviewers should diff that one line before and after the move, nothing else in the OTA path is in scope.

## 8. Open points for the user

- Approve the `Addon*` file names and the category-based split of `TIOPanel` (M5-M8), or ask for a single `AddonHub.m`.
- Decide whether S4 (`variant-syntax`) goes into `scripts/turbo-gate.sh` or stays a local script; adding it edits the gate, which is outside this document.
- Confirm that S6 is acceptable as a once-per-series human check.
- Confirm that dense-line reflow is a separate, later series.
