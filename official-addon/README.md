# official-addon (leftovers)

The active iOS addon moved to [ios-addon/](../ios-addon/README.md) in C21. It targets RayNeo AI 1.0.21 (1). Build, test and package it from there.

What stays here:

| Path | Purpose |
| --- | --- |
| research/ | app-runtime-v1 and dashboard-editor-v1, plus the menu8 and navigation headers they include; compiled by the dashboard-service tests. |
| `Core.h` | Header kept for the research sources. The addon has its own copy. |
| `PrivateBootstrap.h/.m`, `PrivateBootstrapTests.m` | The tracked root parser and its tests, kept for compatibility. Builds use ignored private copies. No private configuration belongs in the source release. |

<a id="1-兼容性门槛"></a>
## Archived

navs3-edition, tmig1-edition, focus-edition, the root V2 sources, music/ and preview/ were removed from the tree and are kept in commit `27ad86e`, which is on `main`'s history. cleanup(3) then removed knowledge-bridge/, tar2-airplay/, tar2-display/, docs/ and the research modules nothing builds any more (focus, music, weread, most of navigation). The 1.0.7 and 1.0.11 host code left with C21. All of it is in git history.

```sh
git show 27ad86e:official-addon/navs3-edition/README.md
git checkout 27ad86e -- official-addon/navs3-edition
```

<a id="本地合并签名安装"></a>

Original code uses [PolyForm Noncommercial 1.0.0](../LICENSE); third-party code retains its own terms.
