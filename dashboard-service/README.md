English | [中文](README-zh.md)

# Turbo IO Developer SDK · Self-hosted backend

2026-09-26. Standalone and self-hosted. It does not depend on the author's services, model keys or project management system.

**Start here: [full developer guide](../docs/DEVELOPER_ECOSYSTEM.md) · [20 MCP app templates](../app-gallery/README.md) · [Agent Skill](../skills/turboio-developer/SKILL.md). MCP runs on the user's own server, not on the glasses.**

In place: the card API / Python SDK / MCP, the phone approval bridge, and the JS → ZIP → phone preview/install protocol → AP native runtime. The user has verified installing and launching basic small apps on the private SPACEFIX-01 build. That does not mean older firmware in the public repo is automatically TAP1-compatible, and it does not mean third-party MCP, background refresh or button events flowing back to the backend have all passed acceptance. The public source builds and tests on its own; a real device needs a phone and firmware that match TCE1/TAP1. The test boundaries below do not replace acceptance on a specific device.

## Current scope

| Module | Implemented | Not done |
| --- | --- | --- |
| Dashboard API | Templates, schema, validation, SVG preview, drafts, revisions, data updates, immutable published snapshots; iOS foreground manual bridge (beta) | Full joint acceptance from API to lens, automatic data-source subscription |
| Common service | SQLite, device-scoped Tokens, idempotency keys, expiry states, explicit phone approval and receipts | Automatic retry, queue recovery, Token management UI |
| Python SDK / MCP / Skill | Shared API; 12 MCP tools; installable repo Skill | Does not configure any Agent or third-party service automatically |
| App toolchain | JS build template, two-page task example, ZIP validation, SVG preview, native record encoding | JSX/HTML syntax, UI for uploading user resources |
| App runtime | Four slots with two files each, single instance, TAP1/TAX1 protocol; basic install and launch on the private build confirmed by the user | Full public runtime package released separately; real power-loss and on-device acceptance of all templates |
| App phone | My Apps / App Gallery / Developer guide; 4 basic examples and 20 MCP-direction templates; ZIP import and install protocol | Third-party services are configured by the user; backend event flow-back and automatic recovery not connected |

## Start the API locally

Run these commands in this directory. They need Python 3.11+ and `uv`. They do not deploy a public service and do not connect to the phone or the glasses.

```sh
uv sync --locked
mkdir -p .state
uv run turbo-dashboard grant --role writer --device my_glasses --out .state/writer.token
uv run turbo-dashboard serve
```

The service listens on `http://127.0.0.1:18796` by default, on the local machine only. The Token is generated at random and written to a new file with permissions 0600; it is not printed. If the output file already exists, the command refuses to overwrite it. The database stores only Token hashes. In another terminal:

```sh
TURBOIO_TOKEN_FILE="$PWD/.state/writer.token" uv run python examples/backend_metrics.py
```

The example writes only CPU demo data into a draft. **It does not read your real accounts and does not publish automatically.** Backend authors can replace it with their own data-fetching code; third-party keys never need to be sent to the glasses.

Roles are `reader`, `writer` and `phone`. Each Token can act only on the device it belongs to. Tokens are currently long-lived; this version has no revoke command and no user system, and is meant only for single-owner local preview. Do not expose this service to the internet. Remote use requires the user to set up HTTPS, access control and full credential management. The SDK refuses remote plaintext HTTP, credentials in URLs and cross-site redirects.

`GET /health` needs no authentication. Every other endpoint, OpenAPI included, requires `Authorization: Bearer <token>`; Tokens are never passed as query parameters. HTTP access logs are off by default. Error responses do not echo user documents or secrets.

## Dashboard API

| Method/path | Purpose |
| --- | --- |
| `GET /v1/capabilities` | Card schema, templates and actual integration status |
| `GET /v1/identity` | Role / device of the current Token; checked when binding the phone |
| `POST /v1/cards/validate` | `{"document": …}`, returns the byte/pixel budget |
| `POST /v1/cards/preview` | Same input, returns an SVG layout preview |
| `GET /v1/cards`, `GET /v1/cards/{id}` | Drafts within the current Token's device scope |
| `PUT /v1/cards/{id}` | `expectedRevision` + `document`; a new card starts at revision 0 |
| `PATCH /v1/cards/{id}/data` | `expectedRevision` + `updates`; cannot change position or component type |
| `POST /v1/cards/{id}/publish` | `revision`, `hash`, `idempotencyKey`, `ttlSeconds` |
| `GET /v1/jobs`, `GET /v1/jobs/{id}` | Reports the actual stage; never fakes "displayed" |
| `POST /v1/phone/jobs/{id}/approve` | Phone role confirms the exact `hash` and gets a one-time receiptToken |
| `POST /v1/phone/jobs/{id}/receipt` | Phone role submits receiptToken, state, code |

The layout follows the existing TCE1: a 256×194 content area, at most 12 components, 4 images/icons and 2 charts, with a 32 KiB image pixel budget. That budget is not all of the LVGL memory. Supported: text, icons, small images, progress bars, bar/line charts, dividers and borders. The SVG uses desktop fonts and shows system icons only as numbered boxes; it is not an actual lens screenshot.

`publish` only moves the job to `awaiting_phone_approval`. It moves to `sending` only after the phone previews and approves it. The beta phone app sends over the existing TCE1 transport, reads the configuration back and then reports `device_accepted`; that does not mean the pixel content or what the user sees has been verified. Current test receipts come from a simulator, with no real Bluetooth acceptance. The service also cannot tell that the phone is online from the fact that the source code exists.

### iOS backend connection (beta)

Source: `../ios-addon/EditorBackend*`. Entry point: **My Dashboard → Data source**.

1. The user puts controlled access in front of their own HTTPS endpoint. Do not expose the default local service directly to the internet. The computer can still debug over loopback HTTP; the phone accepts only HTTPS and does not ignore certificate errors.
2. Issue a separate `phone` Token for the same device; the model keeps using `writer` / `reader`. During setup the phone must be connected to the target glasses; after checking the role, it binds the service device to these glasses. The Token is stored only in the phone's local Keychain.
3. After the backend publishes a card, refresh the jobs on the phone, check the static preview, confirm that the **TCE1** companion firmware is installed, and then send manually. The old TDC1 cannot stand in for TCE1. This entry point never flashes firmware automatically.
4. Keep the app in the foreground while sending. OTA sessions are blocked, and the app checks that the device has not changed. Approval is bound to the preview hash. Redirects are refused and network responses are limited to 128 KiB. If the result is unknown or saving the receipt fails, nothing is resent automatically.

Issue the phone-only credential (read it yourself on this computer and enter it on the phone; do not send it into a chat):

```sh
uv run turbo-dashboard grant --role phone --device my_glasses --out .state/phone.token
```

In the first version every snapshot needs confirmation on the phone; **it is not automatic background refresh yet**. Token revocation, job recovery after the system suspends the app, automatic subscription and a key rotation workflow still need work.

Jobs are not retried automatically by default. A timeout during sending turns into `outcome_unknown` and blocks the next job until the phone checks it and completes the receipt. A published snapshot does not change when the draft is edited later. A repeated idempotency key with different content is rejected, and an old revision cannot overwrite a newer one. Limits are 128 drafts per device and 1000 job records; once a limit is reached, new entries are rejected and history is never deleted silently.

## MCP and Skill

MCP is pinned to the v1 SDK, `mcp>=1.28,<2`, and dependency versions are locked in `uv.lock`. This round ran a real stdio initialize, tool listing and tool calls against a temporary local HTTP service. It was not a device test.

Users add the configuration to their own Agent themselves. Example (replace the paths):

```json
{
  "command": "/absolute/path/dashboard-service/.venv/bin/turbo-dashboard-mcp",
  "env": {
    "TURBOIO_API_URL": "http://127.0.0.1:18796",
    "TURBOIO_TOKEN_FILE": "/absolute/path/dashboard-service/.state/writer.token"
  }
}
```

Give the model only a writer / reader Token, **never the phone Token**. The tools have no entry point for phone approval, arbitrary Bluetooth or firmware flashing. The Skill has moved to `skills/turboio-developer/` at the repository root and can be installed with `npx skills add dingyifei/Turbo-IO --skill turboio-developer -g`. Installing it does not set up a Bluetooth connection or deploy a public service.

### MCP app templates → your own server → ZIP

```sh
uv run turbo-app gallery list
uv run turbo-app gallery prompt city_weather
uv run turbo-app gallery build city_weather --out weather-demo.zip
uv run turbo-app check weather-demo.zip
uv run turbo-app preview weather-demo.zip --page home --out weather.svg
```

All 20 packages are original, installable **offline examples**, not 20 signed-in services. Copy a prompt to your Agent and have it discover and call authorized read-only MCP tools on your own server, map the results to `headline / lines / observedAt`, and then build a real data snapshot with `--data snapshot.json --version 2`. Credentials never go into the ZIP. Every ZIP update must increase the version and be confirmed manually on the phone. Frequent reinstalls cannot pass for live navigation or music playback.

New endpoints: `GET /v1/apps/gallery` (reads the catalog, authenticated), `POST /v1/apps/package` (writer builds from a document) and `POST /v1/apps/gallery/{id}/package` (writer builds from a snapshot/version). They return the ZIP as Base64, its SHA256 and `installed: false`. There is no fake endpoint that lets the server install straight onto the glasses. The matching MCP tools are `app_gallery`, `app_build_package` and `app_build_snapshot`.

## App SDK: JS template → ZIP

JS runs only on the development computer at build time, and only trusted source is executed. The glasses render bounded data natively; they do not run Node, a browser, a DOM or arbitrary JS. At this stage it is not a full HTML/JSX framework.

```sh
mkdir -p .state/examples
node examples/tasks.mjs --out .state/examples/tasks.json
uv run turbo-app build .state/examples/tasks.json --out .state/examples/tasks.zip
uv run turbo-app check .state/examples/tasks.zip
uv run turbo-app preview .state/examples/tasks.zip --page home --out .state/examples/home.svg
```

Each output must be a new file, so an original is never overwritten. The template provides a two-page task list, a details view, exit and backend event declarations. Demo events are currently returned only in the host state model; that does not mean they reach a business backend.

A package contains only `app.json` and `manifest.json`, and the manifest pins the file names and SHA256. The total uncompressed size is ≤20,480 bytes and the ZIP is ≤24,576 bytes. Resources are inline `mono1-msb` images. A package carries no API key, cookie, system path, executable or script. Unknown files, path traversal, duplicate entries, symlinks, encrypted entries and format/size/hash mismatches are rejected.

Apps currently support: 540×180, at most 4 pages with 12 components per page; text, buttons, images, progress bars and borders; images of 8–128 pixels with a width that is a multiple of 8, and ≤32 KiB of decoded images per page. Declarative button actions are limited to switching page, sending an event and exiting. Long press is the system exit; touch is not knob scrolling. The phone maps the numeric component index in a native event back to the stable component ID and event name, using the same verified package.

The native `app_store` provides at most 4 slots with two bounded files each: versions increase, it switches only after verification, it verifies on read, and it refuses to overwrite an app that is running. `app_runner` keeps one active instance; while rendering is busy it keeps the buffer and frees it once rendering finishes. The file API and LVGL are wired up and built into the TAP1 candidate. **Simulation does not show persistence or power-loss safety on the real device.** The ZIP→TAP1/TAX1 encodings from the phone and from Python match byte for byte.

HTTP: `POST /v1/apps/validate` accepts `document`; `POST /v1/apps/package/validate` accepts `zipBase64`. These only validate; there is no install endpoint that pretends to succeed. A JSON HTTP request is currently limited to 32 KiB in total, so a Base64 upload close to the ZIP limit may need the local CLI. A binary upload endpoint will come later.

## Tests and device boundaries

```sh
uv run pytest -q
```

On 2026-09-26, 47 tests passed locally. They cover the API, isolation, concurrency, duplicate publishing, timeouts, persistence, malicious packages, JS packaging, HTTP/MCP stdio, Python/Objective-C document and encoding consistency, and native C under ASan/UBSan. The 20 templates (40 pages in total) get a separate native memory test. UIKit checks cover 12 bridge scenarios, the 4 basic examples, the 20 template previews and the three sections. macOS-only tests are skipped on other platforms. Simulation is not real-device acceptance of Bluetooth, power loss or every upstream service.

Native protocol, package decoding and memory source: the glasses runtime is in `../firmware/src/app-runtime-v1/` and the phone module is in `../ios-addon/`. The test drivers are in `tests/native/`, and the tests compile the current source in those two places directly. The public reference modules are not a complete flashable OTA, and they include no hard-coded private configuration and no automatic commands that modify the official firmware. This round changed only the phone App Gallery and the host SDK; it did not flash or change the AP.

Still to do: App backend event/field flow-back, queue recovery, and authorization plus joint device acceptance on each user's own server. The physical flags in `capabilities` are not device probe results and stay at conservative values; the service must not claim the phone is online just because the code exists.
