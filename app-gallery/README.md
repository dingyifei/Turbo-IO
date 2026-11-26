English | [中文](README-zh.md)

# App Gallery · 20 MCP mini-app templates

2026-09-26. **MCP runs on your server; the glasses only show bounded native components.** These ZIPs use original demo content. They ship no third-party service code, authorization, accounts or keys. They are not 20 finished, network-connected apps.

On the phone: **TurboIO → App Gallery**, with three tabs: My Apps / App Gallery / Developer guide. Each template has a preview, a reference project, configuration requirements, an agent prompt and ZIP export. The four existing basic examples are still there. Under TAP1 the glasses hold at most four apps, so 20 templates in the gallery does not mean 20 installed apps.

Read the [full developer guide](../docs/DEVELOPER_ECOSYSTEM.md) first, then copy a prompt from the table to an agent such as Codex or Claude Code. The upstream projects were found through [awesome-china-mcp](https://github.com/zackchewa/awesome-china-mcp); the actual tool names, fields, authorization and licenses are whatever each project states. We don't copy upstream implementations or proxy upstream services.

| Use | Copyable prompt and setup requirements | Offline ZIP | MCP reference project |
| --- | --- | --- | --- |
| City weather | [Prompt](city_weather.md) | [Download](Gallery_city_weather.zip) | [Baidu Maps](https://github.com/baidu-maps/mcp) |
| Rain alerts | [Prompt](rain_watch.md) | [Download](Gallery_rain_watch.zip) | [Caiyun Weather](https://github.com/caiyunapp/mcp-caiyun-weather) |
| Commute helper | [Prompt](commute.md) | [Download](Gallery_commute.zip) | [Baidu Maps](https://github.com/baidu-maps/mcp) |
| Places nearby | [Prompt](nearby.md) | [Download](Gallery_nearby.zip) | [Baidu Maps](https://github.com/baidu-maps/mcp) |
| Road traffic | [Prompt](traffic.md) | [Download](Gallery_traffic.zip) | [Baidu Maps](https://github.com/baidu-maps/mcp) |
| Train tickets left | [Prompt](train_board.md) | [Download](Gallery_train_board.zip) | [12306](https://github.com/Joooook/12306-mcp) |
| Train transfers | [Prompt](train_transfer.md) | [Download](Gallery_train_transfer.zip) | [12306](https://github.com/Joooook/12306-mcp) |
| Flight status | [Prompt](flight_board.md) | [Download](Gallery_flight_board.zip) | [VariFlight](https://github.com/variflight/variflight-mcp) |
| Today's calendar | [Prompt](calendar.md) | [Download](Gallery_calendar.zip) | [Feishu (Lark)](https://github.com/larksuite/lark-openapi-mcp) |
| Work to-dos | [Prompt](work_tasks.md) | [Download](Gallery_work_tasks.zip) | [Feishu (Lark)](https://github.com/larksuite/lark-openapi-mcp) |
| Knowledge notes | [Prompt](knowledge.md) | [Download](Gallery_knowledge.zip) | [Yuque](https://github.com/yuque/yuque-mcp-server) |
| Reading notes | [Prompt](reading_notes.md) | [Download](Gallery_reading_notes.zip) | [WeChat Read](https://github.com/freestylefly/mcp-server-weread) |
| Video summary | [Prompt](video_digest.md) | [Download](Gallery_video_digest.zip) | [Bilibili](https://github.com/huccihuang/bilibili-mcp-server) |
| Trending topics | [Prompt](trending.md) | [Download](Gallery_trending.zip) | [Weibo](https://github.com/qinyuanpei/mcp-server-weibo) |
| Code to-dos | [Prompt](repo_tasks.md) | [Download](Gallery_repo_tasks.zip) | [Gitee](https://github.com/oschina/mcp-gitee) |
| Build board | [Prompt](build_status.md) | [Download](Gallery_build_status.zip) | [Alibaba Cloud DevOps (Yunxiao)](https://github.com/aliyun/alibabacloud-devops-mcp-server) |
| Service health | [Prompt](service_health.md) | [Download](Gallery_service_health.zip) | [Alibaba Cloud Observability](https://github.com/aliyun/alibabacloud-observability-mcp-server) |
| Holiday calendar | [Prompt](holiday.md) | [Download](Gallery_holiday.zip) | [China MCP Servers](https://github.com/zackchewa/china-mcp-servers) |
| News brief | [Prompt](news_digest.md) | [Download](Gallery_news_digest.zip) | [Bocha Search](https://github.com/BochaAI/bocha-search-mcp) |
| Menu nutrition | [Prompt](nutrition.md) | [Download](Gallery_nutrition.zip) | [McDonald's MCP](https://github.com/M-China/mcd-mcp-server) |

## From examples to real data

1. Deploy the MCP you picked on your own server and complete its authorization. Query `tools/list` and pick read-only tools. Don't enable payment, messaging, ordering or operations actions by default.
2. Reduce the authorized result to a `headline`, 1–4 `lines` and an `observedAt` with a time zone. Each string is at most 80 UTF-8 bytes. Pick only the fields you want to show; don't pass through the full response, tokens or cookies.
3. Run the SDK:

```sh
cd dashboard-service
uv sync --locked
uv run turbo-app gallery build city_weather --data snapshot.json --version 2 --out my-weather.zip
uv run turbo-app check my-weather.zip
uv run turbo-app preview my-weather.zip --page home --out weather.svg
```

4. On the phone: import the ZIP → preview → check the glasses' slots → confirm the install. This needs a compatible TAP1 runtime; the ZIP is not sent directly to old firmware. An update with the same ID must raise the version.

This is a **manually installed snapshot**, not a live background subscription. Reading notes does not provide full book text, Video summary does not play video, and Commute helper does not replace live navigation. Source APIs can change; the templates don't guarantee that the upstream services stay available.

## Catalog and reproducible generation

[`catalog.json`](catalog.json) holds each template's ID, relative resource name, ZIP size, SHA256, source and prompt. The `.json` file with the same name is the editable app document, and the `.md` file is the prompt. The icons are the SDK's own 48px monochrome geometric assets. The phone list uses system icons instead. No platform trademarks are included.

Regenerate into a **new directory**: `uv run turbo-app gallery export --out /path/to/new-gallery`. The generator is `dashboard-service/turbo_dashboard/gallery.py`. Generating from the same source should give the same hashes. All 20 templates pass the ZIP, schema, native encoding and C memory checks. Passing on the emulator pages does not mean each third-party service has passed a live, on-device acceptance test.

GitHub can host the public, keyless template catalog and small ZIPs; to publish real user data, use your own server under your control. This phone build uses the built-in catalog. It does not quietly fetch and auto-install new code from GitHub. When you download or update, pin the version, verify the SHA256 and preview the contents before you approve.
