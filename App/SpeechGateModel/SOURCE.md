# Speech gate model

Silero VAD v6.2.1, a voice activity model, shipped in the app so identifying the Meeting Language never downloads anything. It is the speech gate in front of the language classifier: only the chunks it calls speech reach the classifier, so music, ringtones and noise don't. Carbon loads it from `Carbon.app/Contents/Resources/SpeechGateModel` once a Meeting that needs its language identified starts hearing audio, before the language identification model, and lets it go with that model. ADR-0005 says why this model and why plain Core ML rather than FluidAudio.

- Source: https://huggingface.co/FluidInference/silero-vad-coreml at revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`, Fluid Inference's Core ML conversion of [snakers4/silero-vad](https://github.com/snakers4/silero-vad) v6.2.1, the model FluidAudio 0.17.7 loads (`ModelNames.VAD.sileroVad`). FluidAudio 0.17.7 doesn't pin a revision for this repo (`ModelNames.Repo.revision` is `main` for every repo but the diarizer's): this is `main` on the day it was vendored. Kept: `silero-vad-unified-256ms-v6.2.1.mlmodelc` (256 ms chunks at 16 kHz, plus 64 samples of context and an LSTM state carried from chunk to chunk) and the upstream `README.md`. Left out: the other conversions, the `.mlpackage`s and the graphs.
- Every Hugging Face file was checked against the Hugging Face API at that revision (SHA-256 for LFS files, git blob SHA-1 for the others) before being copied here. The `.mlmodelc` is byte-identical to the copy FluidAudio downloaded for the measurements.
- `LICENSE` is Silero VAD's, from https://github.com/snakers4/silero-vad at tag `v6.2.1` (commit `7e30209a3e901f9842f81b225f3e93d8199902b1`). The Hugging Face repo has no licence file; its model card says MIT.
- License: MIT, for the model (Silero Team) and the conversion. See `LICENSE`.

## SHA-256

```
2e63e9a38b6e8fc0c7bc37ce174caca1862870856c6daf5697cfb785e925520b  LICENSE
c31dbec3e24a014a51fc06c645b3cb04897c97ecdbad9a90645466019c933ef4  README.md
8067594eb3126ab8318af507f0c00cabfed40d5fedb8a0ee5075dd02e903d909  silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin
7db35a4fd995222a7fb0129713473b15d1462572ab4a2e5e4d56bcaad9e40f41  silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin
2740be542c611e1ba358e1849b4e265c65cdf0b17192767e1e5de86a31ac94d6  silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json
c6a9d1bf22d413265da0a07a1d14151c3ea2fad296b3aa5859275b33ef1c3270  silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil
53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063  silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin
```
