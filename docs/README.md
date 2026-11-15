# Documentation

New here? Start with the [project README](../README.md). Agents should read [AGENTS.md](../AGENTS.md) first.

Status column:
- **Current**: describes the build as it is today.
- **V1**: covers the standalone V1 client, whose code was removed in cleanup(2).
- **Historical**: kept as a record of an older release or a removed feature.

## Guides

| Document | Status | What it covers |
|---|---|---|
| [AI setup](AI_SETUP.md) | Current | Pick a platform and have an assistant walk you through setup |
| [Agent skill](AGENT_SKILL.md) | Current | Installing the setup skill ([skill source](../skills/turbo-io/SKILL.md)) |
| [Developer ecosystem](DEVELOPER_ECOSYSTEM.md) | Current | Dashboard and mini-app SDKs: your server, your glasses apps |
| [Porting flow](porting-flow.md) | Current | How Turbo-IO moves to a new RayNeo firmware or app release |
| [Clench tooling](../tools/clench/README.md) | Current | Offline tooth-tap recording and analysis |
| [Original app inputs](../official-apps/README.md) | Current | Where the stock app inputs come from, and their versions |
| [Licensing](LICENSING.md) | Current | Non-commercial terms and third-party boundaries |
| [Source release](SOURCE_RELEASE.md) | Current | What the public source includes and excludes |
| [Changelog](CHANGELOG.md) | Historical | Dated updates and acceptance records up to 2026-10-23, moved out of the README |

## Design system

[Design system](design-system/README.md) is the UI spec for the phone and the lens. It is backed by the [shared rules and tokens](design-system/SPEC.md) and one README per component under [`design-system/components/`](design-system/components/).

## V1 standalone client (archived)

The V1 client (apps, core-probe, codex-bridge, display-observer and its Swift packages except the four kept as clean-room reference) was removed from the tree in cleanup(2) and is in git history. Its docs are kept under [archive/v1/](archive/v1/) as a record; their commands no longer work. Start with [the V1 overview](archive/v1/v1-sdk.md).

| Document | What it covers |
|---|---|
| [Architecture](archive/v1/ARCHITECTURE.md) | Protocol, audio and agent architecture |
| [Configuration](archive/v1/CONFIGURATION.md) | Build, credentials and pairing |
| [Validation](archive/v1/VALIDATION.md) | Build and test evidence, dated |

## Proposals

These are written up but neither approved nor built.

- [Addon refactor](proposals/addon-refactor.md): splitting up the iOS addon.
- [Module loader](proposals/module-loader.md): loadable firmware modules (TMB1).
- [License scan](proposals/LICENSE-SCAN.md): an inventory of licenses, with recommendations.

## Historical

- [TVP2 / TAR2](archive/TVP2_TAR2.md): clear screen casting. Its receiver SDK (`official-addon/tar2-airplay`, `tar2-display`) was removed in cleanup(3).
- [WeRead research](history/WEREAD_RESEARCH.md): the reading integration, since removed.
- [AMap navigation](history/NAVIGATION.md) and [its background behaviour](history/NAVIGATION_BACKGROUND.md): replaced by MapKit navigation.
- [Turbo Display navigation](history/TURBO_DISPLAY_NAVIGATION.md): early display and navigation experiments.
- [ios107 release](../official-addon/ios107-edition/RELEASE.md): the original addon release record. The older V2 release docs (`official-addon/docs/`) were removed in cleanup(3) and are in git history.
- [Screenshots](screenshots/README.md) and [design artwork](design/developer-ecosystem-banner-20260926.md): provenance notes for images used in the README.
