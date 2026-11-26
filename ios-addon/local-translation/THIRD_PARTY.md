# Third-party sources and licenses

Pinned versions checked on 2026-09-24. This page only records which license each part originally carries. It does not put third-party code or models under this project's terms. The full terms are those of each source.

| Content | Pinned source | License / distribution limits |
| --- | --- | --- |
| Turbo IO's own UI, pipeline, bridge, scheduling and tests | This folder | [PolyForm Noncommercial](../../LICENSE); noncommercial research |
| Apple Translation / AVFoundation / CoreML | The user's Apple SDK and system | Apple SDK and platform terms; this repo does not ship the SDK or system language packs |
| Hy-MT2 GGUF | [Tencent model card](https://huggingface.co/tencent/Hy-MT2-1.8B-1.25Bit-GGUF/tree/9df5c824a00a744fb0512a29c640466f4d97dfb0) | The model card states Apache-2.0; you download the weights from upstream yourself, and they are not uploaded to this repo |
| llama.cpp STQ branch | [Pinned commit](https://github.com/sjl623/llama.cpp/tree/1e411d8f5a1e23525fa3265dfb4bd76265465397) | MIT, see `licenses/llama-MIT.txt`; we do not claim that mainline llama.cpp supports this quantization |
| FluidAudio | [Pinned commit](https://github.com/FluidInference/FluidAudio/tree/eabcd9e36dab48f1f7180165396d84b9688650e0) | Apache-2.0; upstream's third-party notices are kept in `licenses/`; this is not the license of the model weights |
| Parakeet EOU 120M CoreML | [Pinned model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355) | NVIDIA Open Model License, see the [official terms](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/); never describe it as Apache or as this repo's noncommercial license |

At build time SwiftPM may resolve and cache FluidAudio's optional binary dependencies. The build passes `--disable-default-traits` to drop the NeMo text-processing link, which this build does not need, but that does not make the upstream build fully offline, and we do not claim it does. At runtime only Parakeet is enabled; no other FluidAudio cloud service or TTS engine is called.

The GGUF compatibility conversion accepts only the original file whose hash the manifest names, and writes a new file: 224 tensor type IDs change from 42 to 43, and one `general.file_type` field changes. The tensor payloads are unchanged. The original file is kept. The copy is not Tencent's original release file, and it is not a requantization. The pinned kernel and the copy must be used together.

Nothing here includes the maintainer's keys, private host, cookies, accounts, certificates, recordings or test-device details. Users supply their own signing, a legitimate host app and resources they have the right to use. This folder contains no web book-fetching adapter and does not change the publication limits that apply to WeRead (微信读书).
