# Documentation index

Status describes scope, not device acceptance: **current** is an active guide/specification (a proposal is not implemented); **historical** records an older release or removed feature; **V1** is the independent client, not the ios107 addon. Start with the [project overview](../README.md) and [contributor rules](../AGENTS.md).

## Setup and reference

| Document | Status | Purpose |
|---|---|---|
| [This index](README.md) | current | Entry point for every Markdown document under `docs/` and related guides. |
| [AI setup](AI_SETUP.md) | current | Choose a platform and guide an assistant through authorized setup. |
| [Agent skill](AGENT_SKILL.md) | current | Install and use the setup skill. |
| [Licensing](LICENSING.md) | current | Noncommercial terms and third-party boundaries. |
| [Source release](SOURCE_RELEASE.md) | current | Public-source scope, exclusions and release exceptions. |
| [Developer ecosystem](DEVELOPER_ECOSYSTEM.md) | historical | Server-to-glasses app architecture and its original delivery boundaries. |
| [Architecture](ARCHITECTURE.md) | V1 | Independent-client protocol, audio and agent architecture. |
| [Configuration](CONFIGURATION.md) | V1 | Independent iOS client build, credentials and pairing. |
| [Validation](VALIDATION.md) | V1 | Dated independent-client build and test evidence. |
| [TVP2 / TAR2](TVP2_TAR2.md) | historical | Version-pinned AirPlay experiment and acceptance limits. |

## Design system

| Document | Status | Purpose |
|---|---|---|
| [Design-system overview](design-system/README.md) | current | UI specification entry point and design resources. |
| [Specification](design-system/SPEC.md) | current | Shared phone/lens rules, priorities and tokens. |
| [AmbientStatus](design-system/components/AmbientStatus/README.md) | current | Ambient-status component contract. |
| [Button](design-system/components/Button/README.md) | current | Button variants and behavior. |
| [ConfirmSheet](design-system/components/ConfirmSheet/README.md) | current | Confirmation-sheet contract. |
| [EmptyState](design-system/components/EmptyState/README.md) | current | Empty-state component contract. |
| [FocusCaret](design-system/components/FocusCaret/README.md) | current | Lens focus-caret contract. |
| [LensPreview](design-system/components/LensPreview/README.md) | current | Lens-preview component contract. |
| [LensType](design-system/components/LensType/README.md) | current | Lens typography contract. |
| [ListRow](design-system/components/ListRow/README.md) | current | List-row component contract. |
| [LyricStack](design-system/components/LyricStack/README.md) | current | Lyric-stack component contract. |
| [PriorityBands](design-system/components/PriorityBands/README.md) | current | Lens priority-band contract. |
| [ProgressTrack](design-system/components/ProgressTrack/README.md) | current | Progress-track component contract. |
| [SectionHeader](design-system/components/SectionHeader/README.md) | current | Section-header component contract. |
| [StatusPill](design-system/components/StatusPill/README.md) | current | Status-pill component contract. |
| [TransientHint](design-system/components/TransientHint/README.md) | current | Transient-hint component contract. |
| [TurnCard](design-system/components/TurnCard/README.md) | current | Navigation turn-card contract. |

## Proposals (not implementation or approval)

These retain the original text and base commits from the documentation branch.

| Document | Status | Purpose |
|---|---|---|
| [License scan](proposals/LICENSE-SCAN.md) | historical | Dated licensing inventory and recommendations, not a license change. |
| [Addon refactor](proposals/addon-refactor.md) | historical | Proposed decomposition of the addon at its recorded base. |
| [Module loader](proposals/module-loader.md) | historical | TMB1 implementation proposal; no built or approved firmware. |

## Removed features and historical guides

| Document | Status | Purpose |
|---|---|---|
| [WeRead research](history/WEREAD_RESEARCH.md) | historical | Reading integration research removed from the current ios107 build. |
| [Turbo Display navigation](history/TURBO_DISPLAY_NAVIGATION.md) | historical | Early display/navigation experiments, not current setup. |
| [AMap navigation](history/NAVIGATION.md) | historical | Removed iOS AMap integration and its old build route. |
| [Navigation background](history/NAVIGATION_BACKGROUND.md) | historical | Old AMap background-location behavior and limitations. |

## Images and design provenance

| Document | Status | Purpose |
|---|---|---|
| [Screenshots overview](screenshots/README.md) | historical | Capture provenance and privacy/acceptance boundaries. |
| [Mid-Autumn artwork](screenshots/MIDAUTUMN_20260925.md) | historical | 2026-09-25 artwork notes. |
| [Android / iOS hero](screenshots/android-ios-release-hero-20260927.md) | historical | Cross-platform release artwork notes. |
| [Android update hero](screenshots/android-release-update-wide-20260927.md) | historical | Android release artwork notes. |
| [NAVS3 / TMG2 hero](screenshots/navs3-tmg2-hero-20261019.md) | historical | NAVS3 release artwork notes. |
| [TMIG1 hero](screenshots/tmig1-prerelease-hero-20261014.md) | historical | TMIG1 prerelease artwork notes. |
| [Design artwork](design/) | historical | Design-art provenance directory. |
| [Developer ecosystem banner](design/developer-ecosystem-banner-20260926.md) | historical | Developer-ecosystem banner provenance. |

## Related guides outside `docs/`

| Document | Status | Purpose |
|---|---|---|
| [Clench tooling](../tools/clench/README.md) | current | Offline tooth-tap recording and analysis tooling. |
| [V2 release](../official-addon/docs/RELEASE_V2.md) | historical | Original official-app addon release boundaries. |
| [ios107 release](../official-addon/ios107-edition/RELEASE.md) | historical | Original APP107 release record, not current device acceptance. |
| [Setup skill](../skills/turbo-io/SKILL.md) | current | Multi-platform assistant setup workflow. |
| [Original app inputs](../official-apps/README.md) | current | Legal input and version-index entry point, not an installed addon. |
| [Android validation](../android-addon/docs/VALIDATION.md) | historical | Version-specific Android test and device evidence. |
