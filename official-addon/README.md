# official-addon (leftovers)

The active iOS addon moved to [ios-addon/](../ios-addon/README.md) in C21. It targets RayNeo AI 1.0.21 (1). Build, test and package it from there.

What stays here:

| Path | Purpose |
| --- | --- |
| `Core.h` | An older copy of the addon's core header. Nothing builds it now; the addon uses its own `ios-addon/Core.h`. |
| `PrivateBootstrap.h/.m`, `PrivateBootstrapTests.m` | An older copy of the settings parser and its tests, kept for compatibility. Builds use the tracked `ios-addon/PrivateBootstrap.h/.m`. The settings file itself (`TurboIOPrivateBootstrap.json`) is private and never belongs in the repo. |

<a id="1-兼容性门槛"></a>
## Archived

navs3-edition, tmig1-edition, focus-edition, the root V2 sources, music/ and preview/ were removed from the tree and are kept in commit `27ad86e`, which is on `main`'s history. cleanup(3) then removed knowledge-bridge/, tar2-airplay/, tar2-display/, docs/ and the research modules nothing builds any more (focus, music, weread, most of navigation). The 1.0.7 and 1.0.11 host code left with C21. post17(2) removed research/ once the dashboard-service tests compiled the live sources; its last state is in commit `b389cc6`. All of it is in git history.

```sh
git show 27ad86e:official-addon/navs3-edition/README.md
git checkout 27ad86e -- official-addon/navs3-edition
```

<a id="本地合并签名安装"></a>

Original code uses [PolyForm Noncommercial 1.0.0](../LICENSE); third-party code retains its own terms.
