# Diarization models

FluidAudio's offline diarizer (pyannote community-1) models, shipped in the app so diarization never downloads anything. `CarbonDiarizer` loads them from `Carbon.app/Contents/Resources/DiarizationModels` with FluidAudio's offline mode on.

- Source: https://huggingface.co/FluidInference/speaker-diarization-coreml at revision `df2625ac79a7ac6b65ad868fee6d80f320da4232`, the revision FluidAudio 0.18.0 pins for this repo, as 0.17.7 did. Only the files `OfflineDiarizerModels.load(from:)` reads are kept, plus the upstream `LICENSE`, `NOTICE.md` and `README.md` (citations).
- `.fluidaudio-revision` is the marker FluidAudio checks before trusting a local copy. When FluidAudio is bumped, update the files and the marker to the revision it pins (`Repo.diarizer.revision`).
- License: CC BY 4.0. Modified Core ML conversions by Fluid Inference of pyannote's speaker-diarization-community-1 (pyannote, WeSpeaker) with PLDA parameters from BUT Speech@FIT. See `speaker-diarization/NOTICE.md`.

## SHA-256

```
8d6706436639b53830b4dbe8aaf9c9a843f7f582d63e16f3cb8bb7c6ccd58682  Embedding.mlmodelc/analytics/coremldata.bin
4a705bac27d151d9642f37609296042a15602a42253039e0921dc9e75da7e004  Embedding.mlmodelc/coremldata.bin
1854371eb6b438fb8aeac96afb45c999af7902581c06afdfcd7ff3cb1ce66be5  Embedding.mlmodelc/metadata.json
22fa958aef72a561c21f874a07cbdcd30fdf40ee961c0bc2fb67c119273b46d3  Embedding.mlmodelc/model.mil
99356b2985b8d43880a657024d941d450b38820451ccff903f76ed4e52d1868b  Embedding.mlmodelc/weights/weight.bin
0e8bd3a8b82ac123580989f490e4d9245127c535857630b543311268accc3f0a  FBank.mlmodelc/analytics/coremldata.bin
57ac436bb0671cbb5527a339134d695f752eb77f7a18966b93c6835335595759  FBank.mlmodelc/coremldata.bin
2623785f5d186893b82d01e84aa33a7704ef763c3309e02055f22dc9d871ce9a  FBank.mlmodelc/metadata.json
27aaeb21569e81bdbe2eef87789f50a37cfea800039bd134448a9417de2f30ed  FBank.mlmodelc/model.mil
9e83fdd3ea78064b078069e4d9141603c61c47a27fd19e7e3142ff7476f8db36  FBank.mlmodelc/weights/weight.bin
736763bf08829e36266b8a3bebcc041ac68575424e976490671a7e6b43a525cf  LICENSE
0964a66893fa5c3a574758257d30d2944669f44eeed5784b30ec3bab902012b3  NOTICE.md
8940ea6044dbcbefa22da8cc41e0b485e1fb5ed89aecaf37c6e0c483a97ddcd7  PldaRho.mlmodelc/analytics/coremldata.bin
4d9741477f721c79b09fcdfe455110c4b7d4272e2de3496bf1729d966d3ee418  PldaRho.mlmodelc/coremldata.bin
b314cf25a93e46b4076883a6f5a2f8848b73c3851bd9d36074d067f35a1c7945  PldaRho.mlmodelc/metadata.json
83aee2e5310d19b5f202aea97d07a0e12102556d1b32ef3ed08b36f7f9725041  PldaRho.mlmodelc/model.mil
80f7d229202636d372428c90596f11a91545f07da77259f07153aaf225914a36  PldaRho.mlmodelc/weights/weight.bin
d0488f898df6da6e9d36f28b0704a65a13578d598c8685a9c5af0f5f8af13978  README.md
64265f8e7ad41a5f68d630c15288c2499cca5892ad49e20096819cdeac004cdb  Segmentation.mlmodelc/analytics/coremldata.bin
ea51481b8bd3e496ad3cf16f066ddaa37f20e8772eaac76b3393c28de20e06bc  Segmentation.mlmodelc/coremldata.bin
88dbf0b07208fe142e1729c2b4c974ad3599fcb2ae5d5f18fce782b225384124  Segmentation.mlmodelc/metadata.json
d37e4ce30b406a6b34f765f769b9baed3178cc0c2b2e299c641daa43a052dd3f  Segmentation.mlmodelc/model.mil
c3189a64946c75bc24fcb98afe89ad78c52bdbadfdf65e857fb1b81e2cc9fbb2  Segmentation.mlmodelc/weights/weight.bin
38ee28d4269c076cef254ee760bbd811f0738a92e0f01f9699ad372828c5de8f  plda-parameters.json
```
