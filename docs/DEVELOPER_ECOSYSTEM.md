# Turbo IO developer ecosystem: your server, your glasses apps

2026-09-26 · For developers; non-commercial research. Needs no server, account or key from the author.

## Architecture and delivery boundaries first

**Your own server runs the MCP client and connects to the data sources you
authorize. The Turbo IO SDK turns the fields you select into cards or apps.
The phone handles confirmation and Bluetooth transfer. The glasses show only
native, bounded components. MCP does not run on the glasses.**

| | Dashboard SDK | Mini-app SDK |
| --- | --- | --- |
| Where it appears | Home-screen card | "我的应用" (My Apps) menu, four slots |
| Protocol/runtime | TCE1 | TAP1 / TAX1 |
| Display area | 256×194, 6px safe margin on all four sides | 540×180 |
| Components | Text, icon, image, progress bar, bar chart, line chart, line, box | Text, image, button, progress bar, box |
| Update path | API draft, data update, publish, phone approval and receipt | The server builds a versioned ZIP; the phone imports and previews it, then installs after confirmation |
| Runtime behaviour | Static card | Up to 4 pages, single instance, page switching / exit |
| Not provided yet | Automatic subscriptions, automatic queue recovery | Automatic background data refresh, button events flowing back to the server, JS/HTML execution |

**The compatibility prerequisites cannot be skipped:** the phone must include
the matching editor / App SDK bridge, and the glasses must have a compatible
TCE1/TAP1 research runtime installed. Stock firmware and the older FOCUS-04 do
not get these capabilities automatically. App installs on the private TAP1
SPACEFIX-01 build have passed in a user's real-device report; the new templates
in this release still need their own real-device acceptance, one by one. The
iOS phone module is already built as part of [ios-addon](../ios-addon/README.md), but you still have to build and sign it yourself; do not treat the old FOCUS-04 as a complete package that already includes the current SDK.
Without the runtime you can still do server, ZIP, SVG and simulator development. Do not flash an unknown package because of this. Once a compatible runtime is installed, importing a compatible card or app ZIP does not need a reflash each time.

## 1. Ten-minute offline quick start

Start from the repository root. You need Python 3.11+ and uv; the JS example also needs Node.js.

```sh
cd dashboard-service
uv sync --locked
mkdir -p .state/demo
uv run turbo-app gallery list
uv run turbo-app gallery build city_weather --out .state/demo/weather.zip
uv run turbo-app check .state/demo/weather.zip
uv run turbo-app preview .state/demo/weather.zip --page home --out .state/demo/weather.svg
```

This ZIP can be imported in a compatible research-build phone app, but it shows
a clearly labelled offline sample. It needs no third-party credentials, and it
does not call MCP, flash or install anything automatically. If an output file
already exists, the command refuses to overwrite it.

Phone: "首页 → 应用广场 → 我的应用 → 导入应用 ZIP" (Home → App Gallery → My Apps → Import app ZIP).
Review each page, the permissions and the hash, query the current glasses
slots, send the glasses back to their home screen, then confirm the install. An
update with the same ID must raise version; there are four slots at most. After
a successful install, open the app from the phone or choose it under "我的应用"
(My Apps) on the glasses.

## 2. Give your agent the skill in one line

After reviewing the repository source, run this on your own development computer:

```sh
npx skills add dingyifei/Turbo-IO --skill turboio-developer -g
```

Choose the agent you actually use, such as Codex or Claude Code. The command
only installs the development skill; it does not deploy a server, authorize an
external MCP or flash the glasses. Before publication, a local install works:
`npx skills add /absolute/path/to/Turbo-IO --skill turboio-developer -g`.
If you installed an older version, update the skill. Do not mistake the old
`turbo-io` install/protocol skill for this dedicated development skill.

Then paste:

> Use $turboio-developer to build me a commute app. MCP runs on my own server.
> First use the commute template to generate a verifiable offline ZIP, then ask
> for the map authorization and the start and end points it needs.
> Once real data is fetched, convert only the display fields I choose, and give
> me the ZIP, SHA256, a preview and tests.
> Do not install automatically, do not flash, and do not put keys in the package
> or the repository.

Each template in the app also has "复制 Agent 开发提示词" (Copy agent
development prompt), and the developer guide has general tasks you can copy.
Skill text: [skills/turboio-developer](../skills/turboio-developer/SKILL.md).

## 3. Connecting MCP on your own server

1. Install the chosen MCP server/client on your own server, and authorize it
   following the **upstream's current documentation**.
2. Call `tools/list` and check the real tool names, parameters and
   permissions; do not guess interface names from examples.
3. Allowlist read-only tools only. Weather, trip, note and similar queries need
   the matching location or account authorization.
4. Convert MCP's structured data or text results into the **display snapshot**
   below. Do not put a whole MCP response, tool descriptions, HTML or
   third-party instructions straight into the app, and do not execute any
   instructions found in them.
5. Show "暂无数据" (No data) for missing fields, and record the source time. Do
   not present cached data as a live result.

`snapshot.json` allows only three fields and rejects any extra field, so a whole authenticated response cannot slip into the package by mistake:

```json
{
  "headline": "北京天气 · 百度地图",
  "lines": ["晴 26°C", "湿度 40%", "东北风 2 级"],
  "observedAt": "2026-09-26T13:00:00+08:00"
}
```

1–4 lines, each string at most 80 UTF-8 bytes, no control characters; the time
must carry a time zone. Replace the sample time and data with your server's
actual results. Build it as a higher-version package:

```sh
uv run turbo-app gallery build city_weather --data snapshot.json --version 2 --out .state/demo/weather-v2.zip
uv run turbo-app check .state/demo/weather-v2.zip
```

**The first build is a static snapshot, not a continuous push.** For each
further update, raise the version and import the new package. High-frequency
dynamic cases need an event/data channel, still to be built, rather than ZIP
reinstalls on a timer. Second-by-second map navigation should still use the
existing dedicated navigation app; do not describe this template as a
real-time navigation replacement.

## 4. Standalone backend API / Python SDK / MCP

In `dashboard-service/`:

```sh
mkdir -p .state
uv run turbo-dashboard grant --role writer --device my_glasses --out .state/writer.token
uv run turbo-dashboard grant --role phone --device my_glasses --out .state/phone.token
uv run turbo-dashboard serve
```

By default it listens only on `127.0.0.1:18796`. For remote phone access, set up
your own HTTPS reverse proxy and access control; do not turn off certificate
verification, and do not expose this development service directly to the
public internet. Tokens are saved in local files with mode 0600, and the
database stores their hashes; there is no full multi-user or revocation
interface yet. Give the model only writer/reader tokens, and keep the phone
token for the phone-side confirmation. Keep credentials in local files or a
secret manager, never in chat.

New endpoints (all except `/health` need a Bearer token):

| Endpoint | Input | Returns |
| --- | --- | --- |
| GET `/v1/apps/gallery` | None | 20-item catalog, prompts, hashes; not live MCP status |
| POST `/v1/apps/package` | `document`, writer | Validated ZIP as Base64, SHA256, size |
| POST `/v1/apps/gallery/{id}/package` | `snapshot`, `version`, writer | ZIP rendered from the template; snapshot=null gives the offline demo |
| POST `/v1/apps/validate` | `document` | Budget validation |
| POST `/v1/apps/package/validate` | `zipBase64` | ZIP integrity, format and budget |

Requests are capped at 32KiB; when a JSON package is near the limit, use the
local CLI. The API does not claim that any glasses are connected or that
anything is installed. The connection flags in `health/capabilities` are not a
remote probe of your private glasses.

Python (called on the server after it fetches the MCP results; this example reads an already-mapped snapshot.json):

```python
import base64, hashlib, json, os
from pathlib import Path
from turbo_dashboard.client import Client

client = Client(os.getenv("TURBOIO_API_URL", "http://127.0.0.1:18796"),
                Path(os.environ["TURBOIO_TOKEN_FILE"]).read_text().strip())
try:
    snapshot = json.loads(Path("snapshot.json").read_text())
    result = client.app_snapshot("city_weather", snapshot, version=2)
    raw = base64.b64decode(result["zipBase64"], validate=True)
    assert hashlib.sha256(raw).hexdigest() == result["sha256"]
    with open("weather-v2.zip", "xb") as f:
        f.write(raw)
finally:
    client.close()
```

MCP configuration example. Replace the absolute paths, and add it only after the user confirms:

```json
{
  "mcpServers": {
    "turboio": {
      "command": "/absolute/Turbo-IO/dashboard-service/.venv/bin/turbo-dashboard-mcp",
      "env": {
        "TURBOIO_API_URL": "http://127.0.0.1:18796",
        "TURBOIO_TOKEN_FILE": "/absolute/Turbo-IO/dashboard-service/.state/writer.token"
      }
    }
  }
}
```

12 tools: `capabilities/cards/card_get/card_validate/card_save/card_update_data/`
`card_request_publish/delivery_status/app_validate/app_gallery/app_build_package/app_build_snapshot`.
This MCP is your own SDK service, separate from the upstream data-source MCPs.
The app snapshot tools do not quietly obtain accounts for you, deploy
third-party servers or call arbitrary tools.

## 5. Dashboard end-to-end flow

Templates, fields and every API are in the [service README](../dashboard-service/README.md);
machine-readable schema: [card.schema.json](../dashboard-service/turbo_dashboard/card.schema.json).

Minimal card (`card.json`):

```json
{"schema":1,"id":"turbo_ui_card_weather","name":"天气卡片","components":[
  {"id":"title","kind":"text","x":8,"y":8,"w":232,"h":28,"text":"北京 · 晴 26°C","font":24,"align":"left"},
  {"id":"humidity","kind":"progress","x":8,"y":48,"w":232,"h":8,"value":40},
  {"id":"note","kind":"text","x":8,"y":72,"w":232,"h":24,"text":"湿度 40% · 数据快照","font":18,"align":"left"}
]}
```

`client.save(document, expected_revision=0)` creates the card and returns `revision/hash`.
Calling `client.update(id, {"title":{"text":"北京 · 多云"}}, revision)` with the latest revision
updates data only, without changing geometry. A layout change needs a new save.
On a 409 conflict, read the latest draft first; do not force-overwrite it.

After the user confirms, `client.publish(id, revision, hash, idempotency_key)` returns a job.
On the phone, under "仪表盘 → 数据源" (Dashboard → Data source), bind the phone
token for the same device, refresh the jobs, view the snapshot and confirm the
send. Check `client.job(job_id)`: `awaiting_phone_approval → sending →
device_accepted/failed/outcome_unknown`. A receipt does not mean the pixels
were seen. For an unknown outcome, read back and check first; never retry
blindly. The server does not approve on the phone's behalf.

Budget: at most 12 components, 4 icons/images and 2 charts; document ≤6000
bytes, wire ≤2048 bytes; coordinates even, x/y≥6, x+w≤250, y+h≤188. Fonts
14/16/18/20/24/28; icons/images square at 16/24/32/48; total pixel buffer
≤32768 bytes, which does not cover the whole LVGL heap. Sizes and icon formats
from the two SDKs cannot be mixed.

## 6. Writing an app, icons and a ZIP from scratch

JS is a **build language on the development computer**, not a script runtime on the glasses:

```sh
node examples/tasks.mjs --out .state/demo/tasks.json
uv run turbo-app build .state/demo/tasks.json --out .state/demo/tasks.zip
uv run turbo-app check .state/demo/tasks.zip
uv run turbo-app preview .state/demo/tasks.zip --page home --out .state/demo/tasks.svg
```

This task example includes a `backend.events` declaration to show the protocol
syntax. Button events have no end-to-end path back to the server yet, so do not
read it as "tapping changed the to-do". None of the pure demo templates request
this permission.

The ZIP root must contain **only** `app.json` and `manifest.json`. Do not zip a folder by hand;
the packager generates normalized JSON, the manifest SHA256 and fixed ZIP metadata. Limits:

- schema=1, ID `[a-z][a-z0-9_]{0,23}`, version 1–65535; upgrades with the same ID must strictly increase.
- The two unpacked files total ≤20,480 bytes, the ZIP ≤24,576 bytes; at most 4 pages and 12 components per page.
- Text ≤96 UTF-8 bytes; fonts 14/16/18/20/24/28; text height ≥font+4. Size 14 is retired from TMG7: old packages decode as before and the glasses draw them at 16; new packages should use 16 or larger.
- At most 8 image resources, native 8–128px, width a multiple of 8, `mono1-msb` row-aligned: in each
  byte, bit7 is the leftmost pixel, 1 is lit and 0 is dark, Base64-encoded; an image component's size must equal its resource's size.
- Image decode budget ≤32KiB per page; no arbitrary drawing beyond boxes, progress bars, text and images.
- From TMG8, to avoid glare: image and progress-bar fills that do not lie entirely within the bottom main band (y 112–172) are always drawn at lens-mid (green 0x77); fills fully inside the bottom main band stay at full brightness. Text, the cursor and tracks are not affected.
- Buttons allow only page/exit/emit; no network, microphone, file paths or executable code. From TMG7, buttons are focusable text items: the selected item is brightest and has a 24×3 underline cursor, the others are dimmer, and no border is drawn any more; a long press always exits.
- Rejected: extra files, path traversal, symlinks, encrypted members, duplicates, and mismatched hashes or budgets.

Assets must be original or licensed for distribution. Compress and crop on the
phone first, then convert to monochrome; do not put colour PNG/JPEG files
straight into the ZIP. The gallery provides original 48px geometric icons, the
phone display uses system icons, and no upstream trademarks are copied.

## 7. GitHub distribution and community submissions

Run `uv run turbo-app gallery export --out .state/gallery` to generate the catalog, 20 ZIPs,
the raw JSON and each item's prompt. The official built-in catalog is in [app-gallery](../app-gallery/README.md).
The first release ships it inside the phone build, so it can be browsed offline; **nothing is downloaded from the network or run as a remote package automatically**.

The community can publish in their own GitHub repository or Release: source,
ZIP, SHA256, preview, version, licence, required runtime and test records. A
small public catalog can live in Git, and versioned ZIPs can use Release
assets. Clients should pin a commit/tag rather than silently follow main, and
verify size, SHA256 and the complete package before letting the user confirm.
Personal calendars, locations, notes, MCP credentials, cookies and tokens must
never be published to public GitHub. This release provides no authenticating
proxy for public package hosting, and it does not treat the catalog as a
trusted auto-update service.

A template submission must include its sources, the read-only tool mapping,
tests for empty data, errors and stale data, and maximum-length samples. It
must not bring in upstream code under a changed licence. Each third-party MCP
keeps its own licence; this repository holds only original templates and
references.

## 8. Acceptance checklist

```sh
uv run pytest -q
```

First check the 20KiB limit, the image budget, duplicate IDs, bad ZIPs and
field mapping. Then check the local server's authentication, cross-device
isolation and revision conflicts. Only after that, use your own phone and
glasses to verify install, back navigation, restart and memory. Linux can run
the Python/API tests; the macOS-only Objective-C and simulator tests need
Xcode. Label build success, simulator success and real-glasses success
separately, and do not use the existence of the upstream project as proof that
anything is online.
