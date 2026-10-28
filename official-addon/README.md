# Official iOS addon sources

V2 extends the compatible official RayNeo app with phone-side tools, glasses protocols and local diagnostics. The active port targets RayNeo AI 1.0.7 (230).

| Directory | Purpose |
| --- | --- |
| [ios107-edition](ios107-edition/README.md) | Active addon: build.sh, package.mjs, test.py, tests/ and local-translation/. |
| [knowledge-bridge](knowledge-bridge/README.md) | Optional local knowledge server. |
| research/ | Shared phone/glasses reference modules, also consumed by android-addon and dashboard-service. |
| tar2-airplay/ and tar2-display/ | Separately licensed display SDKs; see [third-party notices](../THIRD_PARTY_NOTICES.md). |
| docs/ | Historical V2 documentation. |

The tracked root PrivateBootstrap parser and its tests remain for compatibility; ios107 builds receive ignored parser copies from the private external backup. No private configuration belongs in the source release.

<a id="1-兼容性门槛"></a>
## Compatibility

The current port requires the exact 1.0.7 (230) host described in [ios107-edition](ios107-edition/README.md). Historical V2 compatibility and installation instructions remain in `git show archive/editions-2026-10:official-addon/README.md`.

## Archived

navs3-edition, tmig1-edition, focus-edition, the root V2 sources, music/ and preview/ are preserved in the local tag `archive/editions-2026-10`. A small navs3 README pointer remains so frozen firmware documentation keeps a valid link.

```sh
git show archive/editions-2026-10:official-addon/navs3-edition/README.md
git checkout archive/editions-2026-10 -- official-addon/navs3-edition
```

<a id="本地合并签名安装"></a>
## Build and test

From ios107-edition, after preparing compatible external inputs and ignored parser copies:

```sh
TIO_MAPKIT_ENABLED=1 TIO_IMAGE_RX_LAB=1 TIO_DISPLAY_PHONE=1 TIO_DISPLAY_FLASH=1 TIO_OTA_FLASH_ENABLED=1 TIO_CLASSIC_BINDINGS=1 bash build.sh embedded com.rayneo.venus.pub
python3 test.py --firmware /absolute/TMG3-CANDIDATE-NOT-APPROVED.zip
node --test package.test.mjs local-translation/package-resources.test.mjs
```

These commands do not install or communicate with hardware. Signing is a separate local checkpoint; see the active addon README.

Original code uses [PolyForm Noncommercial 1.0.0](../LICENSE); third-party code retains its own terms.
