# Documentation

New here? Start with the [project README](../README.md). Agents should read [AGENTS.md](../AGENTS.md) first.

Status column:
- **Current**: describes the build as it is today.
- **V1**: covers the standalone V1 client, not the ios107 addon.
- **Historical**: kept as a record of an older release or a removed feature.

## Guides

| Document | Status | What it covers |
|---|---|---|
| [AI setup](AI_SETUP.md) | Current | Pick a platform and have an assistant walk you through setup |
| [Agent skill](AGENT_SKILL.md) | Current | Installing the setup skill ([skill source](../skills/turbo-io/SKILL.md)) |
| [Developer ecosystem](DEVELOPER_ECOSYSTEM.md) | Current | Dashboard and mini-app SDKs: your server, your glasses apps |
| [TVP2 / TAR2](TVP2_TAR2.md) | Current | Clear screen casting: install and acceptance |
| [Clench tooling](../tools/clench/README.md) | Current | Offline tooth-tap recording and analysis |
| [Original app inputs](../official-apps/README.md) | Current | Where the stock app inputs come from, and their versions |
| [Licensing](LICENSING.md) | Current | Non-commercial terms and third-party boundaries |
| [Source release](SOURCE_RELEASE.md) | Current | What the public source includes and excludes |
| [Changelog](CHANGELOG.md) | Historical | Dated updates and acceptance records up to 2026-10-23, moved out of the README |

## Design system

[Design system](design-system/README.md) is the UI spec for the phone and the lens. It is backed by the [shared rules and tokens](design-system/SPEC.md) and one README per component under [`design-system/components/`](design-system/components/).

## V1 standalone client

Start with [the V1 overview](v1-sdk.md): what it can do, quick start and limits.

| Document | What it covers |
|---|---|
| [Architecture](ARCHITECTURE.md) | Protocol, audio and agent architecture |
| [Configuration](CONFIGURATION.md) | Build, credentials and pairing |
| [Validation](VALIDATION.md) | Build and test evidence, dated |

## Proposals

These are written up but neither approved nor built.

- [Addon refactor](proposals/addon-refactor.md): splitting up the iOS addon.
- [Module loader](proposals/module-loader.md): loadable firmware modules (TMB1).
- [License scan](proposals/LICENSE-SCAN.md): an inventory of licenses, with recommendations.

## Historical

- [WeRead research](history/WEREAD_RESEARCH.md): the reading integration, since removed.
- [AMap navigation](history/NAVIGATION.md) and [its background behaviour](history/NAVIGATION_BACKGROUND.md): replaced by MapKit navigation.
- [Turbo Display navigation](history/TURBO_DISPLAY_NAVIGATION.md): early display and navigation experiments.
- [V2 release](../official-addon/docs/RELEASE_V2.md) and [ios107 release](../official-addon/ios107-edition/RELEASE.md): the original addon release records.
- [Android validation](../android-addon/docs/VALIDATION.md): Android 1.0.5 device evidence.
- [Screenshots](screenshots/README.md) and [design artwork](design/developer-ecosystem-banner-20260926.md): provenance notes for images used in the README.
