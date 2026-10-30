---
license: apache-2.0
language:
  - multilingual
tags:
  - coreml
  - speechbrain
  - ecapa-tdnn
  - language-identification
base_model: speechbrain/lang-id-voxlingua107-ecapa
library_name: coreml
pipeline_tag: audio-classification
---

# SpeechBrain ECAPA VoxLingua107 Core ML

This is a pinned, validated compiled Core ML export of
[`speechbrain/lang-id-voxlingua107-ecapa`](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa).
It identifies one of 107 spoken-language labels on Apple devices.

## Model

| Property | Value |
|---|---:|
| Parameters | 21.25 million |
| Format | Compiled Core ML, FLOAT16 compute |
| Compiled size | 40.8 MiB |
| Input | SpeechBrain log-mel `[1, frames, 60]` |
| Sample rate | 16 kHz |
| Output | 107 log probabilities |
| Mel frames | 10 to 3,001 (about 0.1 to 30 seconds) |
| Minimum deployment | macOS 15 / iOS 18 |

Unlike several earlier community conversions, this graph includes the
sentence-level mean normalization used by the official SpeechBrain inference
pipeline. The release also validates an independent audio frontend against
SpeechBrain itself.

## Files

| File | Description |
|---|---|
| `SpeechBrainECAPAVoxLingua107.mlmodelc/` | Precompiled Core ML model |
| `frontend.py` | Reproducible SpeechBrain log-mel frontend |
| `labels.json` | Stable upstream index, code, and name mapping |
| `config.json` | Frontend, graph, source revisions, and checksums |
| `artifact_manifest.json` | SHA-256 and size of every compiled artifact file |
| `validation.json` | Conversion parity and local latency measurements |
| `requirements.txt` | Pinned standalone runtime dependencies |
| `LICENSE` | Apache 2.0 license |

## Validation

| Check | Result |
|---|---:|
| Minimum PyTorch/Core ML output cosine | 0.999967 |
| Maximum absolute error | 0.217239 |
| Warm local inference | 3.7 ms |

The upstream card reports 6.7% classification error on the VoxLingua107
development set. That development set contains only 1,609 manually verified
clips across 33 of the 107 labels, so it is not a complete 107-language
evaluation.

## Usage

```python
import coremltools as ct
import numpy as np
import soundfile as sf

from frontend import compute_fbank

model = ct.models.CompiledMLModel("SpeechBrainECAPAVoxLingua107.mlmodelc")
audio, sample_rate = sf.read("recording.wav", dtype="float32")
assert sample_rate == 16000 and audio.ndim == 1
mel = compute_fbank(audio, 60)[None, :, :]
log_probabilities = model.predict({"mel_features": mel})["log_probabilities"]
```

This is a closed-set classifier: it always ranks a known label. Applications
need confidence calibration and an unknown-language rejection policy.

## Source

Converted from the official SpeechBrain checkpoint at revision
`0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9`. Source and checkpoint hashes are recorded in
`config.json`. Upstream legacy codes such as `iw` and `jw` are preserved in
`labels.json` so class indexes never change.

## Links

- [speech-swift](https://github.com/soniqo/speech-swift) — Apple SDK
- [Docs](https://soniqo.audio/getting-started) — install and CLI docs
- [soniqo.audio](https://soniqo.audio)
- [blog](https://soniqo.audio/blog)
