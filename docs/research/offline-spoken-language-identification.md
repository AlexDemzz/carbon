# Offline spoken language identification (non-Apple models)

Researched 2026-10-29 against primary sources: model cards and Hugging Face API metadata at pinned revisions, papers (arXiv), source code at pinned commits, licence texts, and a small measurement run on this Mac (Apple M3 Pro, 18 GB, macOS 27). Every claim carries a source. My own conclusions are marked **(inference)**. Anything not confirmed from a primary source is marked **unverified**.

This note builds on [language-detection.md](language-detection.md). That note found no public Apple audio language-ID API, and proposed a native fallback: race `en_US` and `fr_FR` transcribers in one analyzer and compare word confidence ("the native race"). This note looks at dedicated spoken language identification (LID) models instead, and compares them with the race.

### Pins

| Source | Pin |
|---|---|
| `speechbrain/lang-id-voxlingua107-ecapa` | HF revision `0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9` |
| `aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML` | HF revision `2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0` |
| `soniqo/speech-swift` | commit `d53bcb333882ebbd7444ae059b270127565594a0` |
| `k2-fsa/sherpa-onnx` | commit `935e5ded3d949a8b557ac44ef4dad03a7d2038e7` (release v2.0.1) |
| `csukuangfj/sherpa-onnx-whisper-tiny` / `-base` | HF revisions `65176e2deb88badc814a94058666cadccc29b61c` / `bb53ee204431c90d314c1cc08d28d23e5b7927cc` |
| `argmaxinc/argmax-oss-swift` (WhisperKit, renamed from `argmaxinc/WhisperKit`) | commit `9f99b5cb6a907730543823ad271b82532782a899` |
| `argmaxinc/whisperkit-coreml` | HF revision `0f63a7800b00dd0226abd051b906c246e1907482` |
| `ggml-org/whisper.cpp` | commit `e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1` |
| `openai/whisper` | commit `86098128c0b4f24f0e2aa2994de830614b474227` |
| `snakers4/silero-vad` | commit `0480df078b4429db314feec47853b9bfd2bbba49` (last with the language classifier) |
| `FluidInference/FluidAudio` | commit `fc5c5f06270e20c1c58ce4b102cee5d6896d2cf7` (Carbon pins 0.18.0 in [project.yml](../../project.yml)) |
| `facebook/mms-lid-126` | HF revision `53da6e311f3ce48f324fe335924216187e3109a4` |

## Short answer

- **A small, permissive, Core ML-ready LID model exists: SpeechBrain's VoxLingua107 ECAPA-TDNN.** It has 21.25M parameters. The compiled Core ML export is 42.7 MB (FP16), and the licence is Apache-2.0. It covers 107 languages, English and French included. On this Mac it classified a 2–10 s clip in about **11 ms on CPU**.
- **Restrict its output to the person's candidate languages.** Over all 107 labels, it got 2 s of degraded French wrong more than half the time. Restricted to {en, fr}, it got every normal clip right from 2 s on (TTS audio, indicative only).
- **Whisper `detect_language` works, but costs more.** Whisper tiny is 39M parameters and 76–103 MB on disk, because the decoder carries the whole vocabulary. Most runtimes pad the input to 30 s. It used 5x the CPU time of ECAPA here, and was less accurate on 2 s clips.
- **The rest don't fit.** MMS-LID is about 1B parameters (3.9 GB) and non-commercial (CC-BY-NC-4.0). NVIDIA AmberNet is a `.nemo` checkpoint under NGC terms with no Apple runtime. Silero's language classifier was removed from its repo in 2021. FluidAudio ships no LID.
- **Both approaches fail on heavily accented speech.** In the test, English read by French TTS voices was called French by every model. Real accents are milder than TTS reading English with French rules, but the model card itself warns about foreign accents.
- **Compared with the native race:** ECAPA adds a 43 MB download and a third-party model. In return, it needs one transcriber per stream instead of two during the detection window, and it scales to many candidate languages at no extra cost. The race scales linearly with the number of candidates. Both still need the target locale's SpeechTranscriber assets installed before Carbon can switch.
- **Carbon already has the switch.** `Recorder.switchLanguage(to:)` re-transcribes both streams from the start of the recorded file ([Recorder.swift](../../CarbonCore/Sources/CarbonCore/Recorder.swift), `handStreams`; [StreamRecorder.swift](../../CarbonCore/Sources/CarbonCore/StreamRecorder.swift), `hand(to:)`). An LID result can call it. No extra audio buffering is needed.

## Comparison

| Candidate | Params | Download | Licence (commercial OK?) | en / fr | Reported accuracy on short clips | Apple runtime | Swift effort |
|---|---|---|---|---|---|---|---|
| **SpeechBrain ECAPA VoxLingua107** | 21.25M | 84.5 MB FP32 ckpt; **42.7 MB Core ML FP16**; 26.7 MB GGUF Q8 | Apache-2.0 (yes) | yes / yes | 6.7% error on VoxLingua107 dev (33 langs). **11.9% on ≤5 s, 6.7% on 5–20 s** (TitaNet-LID paper, Table 1) | Core ML (`.mlmodelc`), MLX, GGUF | Low–medium: Core ML model plus a ~100-line log-mel frontend |
| Whisper tiny `detect_language` | 39M | 76 MB Core ML (WhisperKit); 103 MB ONNX int8 | MIT code and weights (yes) | yes / yes | Not tabulated per size. Large-v2 scores 64.5% on Fleurs (102 langs), and smaller models score lower (Whisper paper, Table 5, Fig. 8) | Core ML (WhisperKit), ONNX (sherpa-onnx), ggml (whisper.cpp) | Low with WhisperKit (`detectLangauge(audioArray:)`), but a large package |
| Whisper base `detect_language` | 74M | 147 MB Core ML; 160 MB ONNX int8 | MIT (yes) | yes / yes | Same as above | Same | Same |
| NVIDIA AmberNet (TitaNet-LID) | ~29M **(inference)** | 110.7 MB `.nemo` | NGC Terms of Use (**unverified** for redistribution) | yes / yes | 5.22% error on VoxLingua107 dev (NGC). TitaNet-LID-3x5x1024: 7.5% on 0–5 s | None official. A third-party ONNX mirror exists | High: conversion plus a NeMo frontend |
| Silero lang classifier 95 | 4.7M | 17 MB ONNX | MIT (yes) | yes / yes | "85% validation accuracy among 95 languages" (dataset unstated) | ONNX | Medium. **Abandoned**: deleted from the repo in 2021 |
| Meta MMS-LID-126/256/4017 | ~1B (3.86 GB FP32) | 3.9 GB | **CC-BY-NC-4.0 (no)** | yes / yes | not checked | Third-party Core ML ports | Not viable (size and licence) |
| FluidAudio | — | — | Apache-2.0 | — | **No LID module** | Core ML | — |
| Native race ([prior note](language-detection.md)) | 0 extra | 0 extra (but needs both locales' assets) | Apple | yes / yes | TTS: right locale 0.61–0.90 mean confidence vs. wrong 0.18–0.24 | Speech.framework | Low, but 2x transcription during the window |

## Candidates

### 1. SpeechBrain ECAPA-TDNN on VoxLingua107

- **Model:** an ECAPA-TDNN encoder with a classifier head, trained on VoxLingua107 (YouTube audio, 107 languages, about 62 h per language). Input is 16 kHz mono. Output is 107 log-likelihoods ([model card](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa/blob/0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9/README.md)). The frontend is 60 log-mel bins with sentence-level mean normalization ([hyperparams.yaml](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa/blob/0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9/hyperparams.yaml)).
- **Size:** `embedding_model.ckpt` is 84.5 MB (HF API, same revision). The Core ML export reports **21,246,443 parameters** ([config.json](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML/blob/2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0/config.json)).
- **Licence:** Apache-2.0 ([model card](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa/blob/0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9/README.md) front matter). The VoxLingua107 dataset licence does not bind the weights' users. That reading is **unverified**; I did not check the dataset terms.
- **Accuracy:** "Error rate: 6.7% on the VoxLingua107 development dataset" ([model card](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa/blob/0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9/README.md)). That set has 1,609 verified clips in 33 languages, lasting 1.7–20 s ([TitaNet-LID paper](https://arxiv.org/abs/2210.15781), §3). The same paper re-scored this exact checkpoint: **11.9% error on clips of 0–5 s, 6.7% on 5–20 s, 7.5% overall** (Table 1, footnote 2). These numbers are over 33 languages. A two-way en/fr decision is easier **(inference)**.
- **Known limits:** the card says it "doesn't work well on speech with a foreign accent", "probably works worse on female speech", and uses legacy codes `iw` and `jw` ([model card](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa/blob/0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9/README.md), "Limitations and bias"). It is a closed-set classifier: it always ranks one of its labels, even on silence or music ([Core ML card](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML/blob/2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0/README.md)).
- **Core ML export:** `aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML` is a compiled `.mlmodelc`, FP16, 42.7 MB, macOS 15+. Its input is log-mel `[1, frames, 60]` for 10 to 3,001 frames (0.1–30 s), and its output is 107 log probabilities. The graph includes the mean normalization. Its parity check against PyTorch shows all top-1 predictions match (minimum cosine 0.99997). It reports a 3.7 ms warm latency on unstated hardware. Licence Apache-2.0 ([README](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML/blob/2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0/README.md), [config.json](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML/blob/2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0/config.json)). The export is from a single community publisher, created 2026-08-09. Its long-term upkeep is **unverified**.
- **Other conversions:** an MLX export (42.6 MB, same publisher), `beshkenadze/lang-id-voxlingua107-ecapa-coreml` (an 85 MB FP32 `.mlpackage`; the Core ML card above says some earlier conversions omit the mean normalization, which is **unverified** for this one), and `handy-computer/lang-id-voxlingua107-ecapa-gguf` (F16 45 MB, Q8_0 26.7 MB). All are Apache-2.0 (HF API).
- **Swift package:** `soniqo/speech-swift` (Apache-2.0) has a `SpeechLanguageID` library. It offers `SpeechLanguageIdentifier.fromPretrained(engine: .coreML or .mlx)` and `identify(audio:sampleRate:topK:)`. It splits audio longer than 30 s into windows and weights their probabilities by duration ([docs/inference/language-identification.md](https://github.com/soniqo/speech-swift/blob/d53bcb333882ebbd7444ae059b270127565594a0/docs/inference/language-identification.md)). But the target depends on `mlx-swift` even when Core ML is used ([Package.swift#L586-L594](https://github.com/soniqo/speech-swift/blob/d53bcb333882ebbd7444ae059b270127565594a0/Package.swift#L586-L594)). Opinion: pulling MLX into Carbon for a 43 MB classifier is not worth it. Vendoring the `.mlmodelc` and porting the frontend (`SpeechBrainFbank.swift`, 250 lines, or the 60-line Python reference in `frontend.py`) to Accelerate is a small job.

### 2. Whisper `detect_language` (tiny, base)

- **How it works:** run the encoder on the log-mel input, then run one decoder step from `<|startoftranscript|>`. Mask every logit except the language tokens and take the softmax ([openai/whisper decoding.py#L19-L68](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/decoding.py#L19-L68); the mask is at L61). Both the encoder pass and the decoder step are full model passes.
- **Size:** tiny has 39M parameters and base 74M ([Whisper paper](https://arxiv.org/abs/2212.04356), Table 1). On disk:
  - WhisperKit Core ML tiny: `AudioEncoder` 16.4 MB plus `TextDecoder` 59.2 MB. Base totals 146.7 MB ([argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-tiny)).
  - sherpa-onnx int8 tiny: encoder 12.9 MB plus decoder 89.9 MB. Base: 29.1 plus 130.7 MB (HF API). The decoder dominates because of the 51k-token embedding matrix **(inference)**.
- **Accuracy:** the paper gives LID only for the best model, large-v2: **64.5% on Fleurs** (102 languages, 20 of them absent from training), and 80.3% on the 82 languages it was trained on (Table 5, §3.6). Figure 8 shows accuracy rising with model size. Tiny and base are lower but not tabulated. I found no per-language en/fr LID figure.
- **Cost: the 30 s pad.** openai/whisper and WhisperKit pad or trim the input to 30 s before encoding ([WhisperKit.swift#L562-L606](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/WhisperKit/Core/WhisperKit.swift#L562-L606), "Detect language using up to the first 30 seconds"). whisper.cpp runs the full encoder at the given offset, then one decode ([whisper.cpp#L4162-L4200](https://github.com/ggml-org/whisper.cpp/blob/e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1/src/whisper.cpp#L4162-L4200); encoder context defaults to 1500 frames, which is 30 s, [L598](https://github.com/ggml-org/whisper.cpp/blob/e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1/src/whisper.cpp#L598)). So a 5 s check pays for a 30 s encoder pass. sherpa-onnx instead feeds the real length plus 10 s of zero padding, capped at 30 s ([spoken-language-identification-whisper-impl.h#L49-L79](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/sherpa-onnx/csrc/spoken-language-identification-whisper-impl.h#L49-L79)).
- **Outputs:**
  - WhisperKit returns `(language, langProbs: [String: Float])`, so Carbon could renormalize over its candidates.
  - whisper.cpp's `whisper_lang_auto_detect` fills a `lang_probs` array ([L4243-L4250](https://github.com/ggml-org/whisper.cpp/blob/e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1/src/whisper.cpp#L4243-L4250)).
  - sherpa-onnx's LID API returns only the language string. It passes no candidates (`DetectLanguage(..., {})`, [L97](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/sherpa-onnx/csrc/spoken-language-identification-whisper-impl.h#L97)), even though the decoder supports a candidate list ([offline-whisper-model.cc#L212-L250](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/sherpa-onnx/csrc/offline-whisper-model.cc#L212-L250); [offline-whisper-language-candidates.h](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/sherpa-onnx/csrc/offline-whisper-language-candidates.h), used by the ASR path).
- **Licences:** openai/whisper is MIT (GitHub API). WhisperKit (now `argmax-oss-swift`) and `whisperkit-coreml` are MIT. whisper.cpp is MIT. sherpa-onnx is Apache-2.0. The sherpa-onnx Whisper ONNX repos carry no licence tag; they presumably inherit Whisper's MIT (**unverified**).
- **Swift:** WhisperKit is a Swift package with a public `detectLangauge(audioArray:)` (sic). sherpa-onnx ships a Swift example ([spoken-language-identification.swift](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/swift-api-examples/spoken-language-identification.swift)) over its C API, plus macOS static and shared libraries (v2.0.1 release, about 20 MB for the arm64 static lib). Both are heavy dependencies to add for one decision **(inference)**.

### 3. NVIDIA AmberNet (`langid_ambernet`, TitaNet-LID)

- The NGC card reports **5.22% error** on the VoxLingua107 dev set (1,609 clips, 33 languages). It was trained on VoxLingua107 (107 languages) and takes 16 kHz mono input. The download is 110.67 MB. The latest version is 1.12.0, from 2023-04-04. The licence is the NGC Terms of Use "unless another license is specified" ([NGC catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nemo/models/langid_ambernet)). I found no official Hugging Face card.
- The paper calls it TitaNet-LID. TitaNet-LID-3x5x1024 has 29M parameters and scores **7.5% error on 0–5 s, 5.2% on 5–20 s**. A 12M variant scores 10.7% and 6.3%. It was trained on 3 s segments, and "performs well even on short utterances less than 5s" ([arXiv 2210.15781](https://arxiv.org/abs/2210.15781), Table 1, §4.1). That AmberNet is the 29M variant is my **(inference)** from the 110 MB checkpoint.
- **Runtime:** a NeMo `.nemo` checkpoint (PyTorch). No official Core ML or ONNX export exists. A third-party mirror, `surogate/ambernet-langid`, ships `ambernet.onnx` under an "other" licence tag (HF API, revision `3b7b3fbfcc51753745f1d9abd107c9530c391d5b`). Its provenance and terms are **unverified**.
- Opinion: it is slightly more accurate on short clips than ECAPA, but the licence is unclear and Carbon would have to convert it and port the frontend itself. Not worth it for en/fr.

### 4. Silero language classifier

- The README at the last commit that had it lists `silero_lang_detector_95`: 4.7M parameters, 95 languages (French included). It reports "85% validation accuracy among 95 languages, 90% … among 58 language groups", on an unstated validation set, and "network was trained using audio shorter than 20 seconds" ([README#L537-L548](https://github.com/snakers4/silero-vad/blob/0480df078b4429db314feec47853b9bfd2bbba49/README.md#L537-L548)). `files/lang_classifier_95.onnx` is 16.97 MB. Licence MIT.
- Commit `f67e68e` (2021-12-10, "delete big files from repo") removed it. The current repo ships only VAD models (tree at `066409f`). Opinion: abandoned and unbenchmarked. Skip it.

### 5. Meta MMS-LID

- `facebook/mms-lid-126`, `-256` and `-4017` are each 3.86 GB as FP32 safetensors, which is about 1B parameters **(inference)**. Their licence is **CC-BY-NC-4.0** (HF API). Third-party Core ML ports exist (`aoiandroid/mms-lid-*-coreml`), but the non-commercial licence carries over. Not viable.

### 6. Swift packages that already ship LID

- **FluidAudio:** no language-ID module at `fc5c5f0`. Its tree has ASR, Diarizer, VAD, TTS, Enhancement and ITN. The only language-related piece is `TokenLanguageFilter`, which suppresses wrong-alphabet tokens in Parakeet v3 given a caller-supplied language ([TokenLanguageFilter.md](https://github.com/FluidInference/FluidAudio/blob/fc5c5f06270e20c1c58ce4b102cee5d6896d2cf7/Documentation/ASR/TokenLanguageFilter.md)). It does ship a VAD, which could gate LID input (the VAD directory in the same tree).
- **WhisperKit:** Whisper LID, as in section 2.
- **speech-swift:** ECAPA LID, as in section 1, with an MLX dependency.

## Measurement on this Mac (indicative)

The setup is in the session scratchpad (`lid/scripts/measure.py`, `lid/results.txt`). I generated 13 clips with `say`, each trimmed of leading silence and cut to its first 2, 3, 5 and 10 s:

- 4 English voices.
- 5 French voices, `fr_CA` Amélie included.
- 2 "Franglais" French clips full of English jargon ("mergé la pull request", "shipper la feature").
- 2 clips of English text read by French voices.

The "voip" condition band-limits to 300–3400 Hz and adds white noise at 15 dB SNR. Models:

- ECAPA via the Core ML export, through coremltools.
- Whisper tiny and base, int8, via sherpa-onnx 2.0.1, with 2 threads.

This is TTS, not real meeting audio.

**Accuracy on the 11 clips whose voice matches the text language** (correct / 11):

| Condition | Length | ECAPA, 107-way | **ECAPA, restricted to en/fr** | Whisper tiny | Whisper base |
|---|---|---|---|---|---|
| clean | 2 s | 10 | **11** | 7 | 11 |
| clean | 3 s | 10 | **11** | 11 | 11 |
| clean | 5 s | 11 | **11** | 11 | 11 |
| clean | 10 s | 11 | **11** | 11 | 11 |
| voip | 2 s | 5 | **11** | 6 | 10 |
| voip | 3 s | 9 | **11** | 10 | 10 |
| voip | 5 s | 10 | **11** | 11 | 11 |
| voip | 10 s | 11 | **11** | 11 | 11 |

- Unrestricted errors were nearby or random languages: Occitan, Norwegian Nynorsk, Japanese, Korean, Swedish, Tibetan.
- **Restricting to {en, fr} removed every error.** French clips often scored only 0.01–0.3 probability for `fr` across 107 labels, but `en` was lower still.
- **French voices reading English text:** every model said French at every length, ECAPA with p(fr) up to 0.90. macOS reads English text with French letter-to-sound rules, so this is harsher than a real French speaker talking English **(inference)**. It still shows that acoustic LID judges the accent, not the words.
- Franglais French was detected as French by all models from 3 s, and from 2 s by ECAPA restricted to en/fr.

**Cost** (warm, median per call over 2–10 s clips):

| Model | Median latency | Peak RSS, process with model loaded vs. libraries only |
|---|---|---|
| ECAPA Core ML, `CPU_ONLY` | **10.9 ms** (max 36) | ~180 MB vs. ~100 MB (+80 MB) |
| ECAPA Core ML, `.all` | 20.9 ms (max 294; ANE or GPU dispatch overhead) | — |
| Whisper tiny int8, ONNX, 2 threads | 58.9 ms (max 155) | ~415 MB (+315 MB) |
| Whisper base int8, ONNX, 2 threads | 126 ms (max 210) | ~655 MB (+555 MB) |

For scale: running an ECAPA check on a 10 s window every 30 s of speech costs well under 0.1% of one core **(inference from the numbers above)**. The native race's extra cost is a second full transcriber for 20–30 s of speech. The prior note measured two transcribers at about 4–6 s of wall time for 34 s of audio from a file ([language-detection.md](language-detection.md), section 3).

## How much audio is needed

- **Published numbers** (33-language closed set): ECAPA 11.9% error on ≤5 s and 6.7% on 5–20 s. TitaNet-LID 7.5% and 5.2% ([arXiv 2210.15781](https://arxiv.org/abs/2210.15781), Table 1). Error keeps falling with longer segments (§4.1, Figure 3).
- **Binary en/fr (TTS test):** ECAPA restricted to en/fr was right on every normal clip from 2 s, clean and degraded.
- **(inference):** Decide after about **8–10 s of detected speech**, pooled across windows, and require a clear margin. Below that, keep the current language. Real VoIP, crosstalk, accents and silence will need more than TTS did. The thresholds must be calibrated on recorded Meetings, as the prior note already recommends.

## Integration design (inference)

**What Carbon already has**
- `MeetingLanguages` (chosen locales plus a default) and `AppModel.switchLanguage(to:)`, wired to `Recorder.switchLanguage(to:)` ([AppModel+Languages.swift](../../App/Sources/AppModel+Languages.swift)).
- `switchLanguage` starts new `SpeechTranscriber` sessions for **both** streams and hands each stream to them. `StreamRecorder.hand(to:)` replays "everything recorded so far, read back from the file, then the audio that arrived meanwhile, then the live audio: no gap". The old sessions' words are dropped, and the file is written entirely in the new language ([Recorder.swift](../../CarbonCore/Sources/CarbonCore/Recorder.swift), `switchLanguage` and `handStreams`; [StreamRecorder.swift](../../CarbonCore/Sources/CarbonCore/StreamRecorder.swift), `hand(to:)`).
- So **no new buffering or `setModules` swap is needed.** LID only has to decide and then call the existing switch. A Meeting has one language, so the decision is per Meeting, not per stream.

**Proposed flow**
1. **Candidates.** Use `MeetingLanguages.chosen`, which is seeded from `Locale.preferredLanguages` ([prior note](language-detection.md), recommendation 3). Map each candidate to its VoxLingua label (`en`, `fr`, …). Only offer candidates whose SpeechTranscriber assets are installed (`MeetingLanguageAssets`). With one candidate, skip LID entirely.
2. **Start** the Meeting in the default language, as today.
3. **Tap** the 16 kHz mono audio each stream already produces. Gate it with VAD: `SpeechDetector` in the same analyzer, FluidAudio's VAD, or an energy gate. Keep only speech frames. Silence and music must never reach the classifier, because it is closed-set.
4. **Score** each speech window of 3–5 s with ECAPA. Restrict the output to the candidates, renormalize, and add the log-probabilities into one Meeting-level score per language, weighted by speech duration. Pool both streams. "Them" carries more weight in a Meeting where the person speaks the local language with an accent (opinion).
5. **Decide** once there are at least about 8–10 s of speech and the top candidate leads by a calibrated margin. If the winner differs from the current language, call `switchLanguage(to:)`. It re-transcribes from t=0 at a few seconds of compute, then shows the existing banner ("Transcribing in French").
6. **Re-check** for mid-Meeting switches. Keep scoring a sliding window of the last 30 s of speech. Switch again only if another candidate wins N consecutive windows (hysteresis). Note that `switchLanguage` re-transcribes the **whole** Meeting in the new language. A true mixed-language Meeting would need per-segment locales, which is out of scope here. Treat a second switch as "the first decision was wrong", not as code-switching.
7. **Correct by hand.** The Meeting Language submenu stays the manual override. After a manual choice, stop auto-switching for that Meeting.

**Combining with the native race.** ECAPA is acoustic and can be fooled by accent (see the measurement). The race is lexical and can be fooled by noise and hallucination. When ECAPA's margin is small, a short race over just the top two candidates can break the tie at 2x cost for about 20 s **(inference)**.

## Does constraining to candidate languages help?

- **Yes, a lot, on short or noisy clips.** In the TTS test, ECAPA over 107 labels was right on 5 of 11 degraded 2 s clips. Restricted to {en, fr}, it was right on 11 of 11. Whisper's own LID masks the logits to language tokens before the argmax ([decoding.py#L61](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/decoding.py#L61)), so restricting further to the candidates is the same operation, and sherpa-onnx's decoder supports it natively ([offline-whisper-model.cc#L240-L242](https://github.com/k2-fsa/sherpa-onnx/blob/935e5ded3d949a8b557ac44ef4dad03a7d2038e7/sherpa-onnx/csrc/offline-whisper-model.cc#L240-L242)).
- It also fits Carbon: the person can only be transcribed in a SpeechTranscriber locale they have installed. Detecting Occitan is useless.
- **Risk:** with a closed candidate set, a Meeting in a third language is forced onto one of the candidates. Keep the unrestricted top-1 as a signal. If it is confidently outside the candidate set, suggest adding that language instead of switching (opinion).

## Recommendation (opinion)

1. **Use SpeechBrain's VoxLingua107 ECAPA-TDNN through Core ML** (`aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML`, pinned revision). It is 43 MB, Apache-2.0, about 11 ms per check on CPU, and covers every SpeechTranscriber language Carbon is likely to offer. Vendor the `.mlmodelc`, or download it with the locale assets. Port the log-mel frontend to Accelerate. Don't take `speech-swift` (MLX dependency) or WhisperKit (large package; Whisper LID is costlier and worse at 2 s).
2. **Always restrict the result to `MeetingLanguages.chosen`.** Skip LID when only one language is chosen, which is the default US setup.
3. **Decide after about 8–10 s of VAD-gated speech pooled over both streams.** Then reuse `Recorder.switchLanguage(to:)`. It already re-transcribes from the start with no gap.
4. **Keep the native race as a tie-breaker, not the primary detector.** It doubles transcription work and scales with the number of candidates. ECAPA scales for free.
5. **Before shipping, calibrate on real audio.** Record Meetings in EN, FR, accented EN by French speakers, and Franglais FR. Measure the ECAPA en/fr margin per 5 s window. The accent case is the known weak spot: ECAPA labelled French-accented TTS English as French with high confidence. If real accented English also fails, use the race's confidence to veto the switch.
6. **Recheck Apple's private `LanguageDetector` every June** ([prior note](language-detection.md)). If it goes public, it replaces all of this.
