# SpeechTranscriber vs whisper.cpp (and WhisperKit, FluidAudio Parakeet) for Meeting transcription

Researched 2026-10-27 against primary sources: GitHub repos, READMEs, headers, issues and release notes (fetched through the GitHub API), Hugging Face model cards and API metadata, Apple developer documentation (DocC JSON), the WWDC25 SpeechAnalyzer session, the macOS SDK in `/Applications/Xcode-26.4.0.app` (SDK 26.4), and papers on arXiv. Every claim carries a source. Anything not confirmed from a primary source is marked **unverified**. No third-party code or model was downloaded, built or run for this note.

Vocabulary follows `GLOSSARY.md`: a **Meeting** is transcribed into a **Transcript** in one **Meeting Language**, with **Speakers** "Me" (mic stream) and "Them" (app-audio stream).

## Problem framing

- Carbon v1 picked Apple `SpeechAnalyzer` + `SpeechTranscriber`, one analyzer per stream (mic and app audio). The Meeting Language is picked by the person, and switching it re-transcribes from the start ([product design](../../.scratch/carbon-v1/issues/01-carbon-v1-product-design.md)).
- What Carbon needs from the engine:
  - English and French accuracy on far-field mic audio and compressed VoIP audio.
  - Live results on two concurrent streams for a full 1-hour Meeting.
  - Word-level timings, to merge with FluidAudio diarization ([on-device-diarization.md](on-device-diarization.md)).
  - Ideally spoken-language identification, which `SpeechTranscriber` lacks ([language-detection.md](language-detection.md)).
  - Low battery and thermal cost, a small memory footprint and a reasonable download.
  - Licences compatible with a free, closed-source app distributed through Developer ID and Sparkle.
  - macOS 26 support and little maintenance.
- Candidates:
  1. **Apple SpeechTranscriber**: system framework, macOS 26+.
  2. **whisper.cpp**: C/C++ Whisper runtime, Metal plus an optional Core ML encoder.
  3. **WhisperKit** (Argmax, `argmax-oss-swift`): Swift and Core ML Whisper.
  4. **FluidAudio ASR**: Swift and Core ML Parakeet / Nemotron. FluidAudio is already a Carbon dependency for diarization.

## 1. Accuracy (English and French)

Apple publishes no WER figures for `SpeechTranscriber`. Every Apple number below comes from a third party, and most of those third parties sell a competing engine. Keep that in mind when reading the tables.

### Reference numbers for the open models (Open ASR Leaderboard paper, model cards)

| Model | English avg WER (Open ASR, 8 sets) | AMI (meetings) | Earnings-22 (calls) | French WER |
|---|---|---|---|---|
| Whisper large-v3 | 7.44 % | n/a in source | n/a in source | 6.59 % (Open ASR multilingual avg) |
| Parakeet TDT 0.6B v3 | 6.32 % | 11.31 % | 11.42 % | 5.38 % (Open ASR avg); FLEURS 5.15, MLS 4.97, CoVoST 6.05 |
| Parakeet TDT 0.6B v2 (English only) | 6.05 % | n/a | n/a | n/a |

Sources:
- Open ASR Leaderboard paper, Table 3 (English averages and RTFx) and Table 4 (French) ([arXiv 2510.06961v3](https://arxiv.org/html/2510.06961v3)).
- Parakeet v3 per-dataset and French numbers come from its model card ([HF nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)).
- Caveat from the paper: punctuation and casing are stripped with a Whisper-style English normalizer, and far-field speech is listed as future work ([same paper](https://arxiv.org/html/2510.06961v3), Sections 2.3 and 4).
- I did not find a large-v3-turbo row in the paper text I read (**unverified**). OpenAI calls turbo "an optimized version of large-v3 ... with a minimal degradation in accuracy" ([openai/whisper README](https://github.com/openai/whisper)).

### Head-to-heads that include Apple SpeechTranscriber

| Study (author's stake) | Audio | Apple SpeechTranscriber | Whisper | Parakeet |
|---|---|---|---|---|
| Argmax, June 2025, M4 Mac mini, macOS 26 beta 1 (sells WhisperKit / Pro SDK) | 10 % of Earnings-22, ~12 h of English calls | **14.0 %**, speed 70x | base.en 15.2 % (111x); small.en **12.8 %** (35x) | parakeet-v2 (Pro SDK) **11.7 %** (359x) |
| founden-bot, 2026-10-19, M2 Pro, macOS 26.6.2 (author makes a Parakeet dictation app) | FLEURS test, 100 clips per language, read speech | EN **6.7 %**, FR **6.6 %**, median 64x | large-v3-turbo q5_0 on whisper.cpp 1.9.4 Metal: EN **3.9 %**, FR **6.6 %**, 13x | v3 via FluidAudio 0.17.4: EN **4.5 %**, FR **5.3 %**, 20x |
| Lyonesse, 2026-07, M2 Pro, macOS 26.5.1 (makes a transcription app) | LibriSpeech test-clean / test-other, read English | **2.12 % / 4.56 %** | small (WhisperKit) 3.74 / 7.95 %; base 5.42 / 12.51 % | not tested |
| Dictato, 2026-04 (vendor; model versions not stated) | 13k "real recordings", 5 languages | best in FR (7.3 %), DE, IT | WhisperKit best in EN (5.2 %), ES | "wins disfluent speech in 3 of 5 languages", no figures |

Sources: [Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax), [founden-bot/on-device-asr-benchmark](https://github.com/founden-bot/on-device-asr-benchmark), [Lyonesse benchmark](https://lyonesse.app/blog/apple-speech-api-benchmark.html), [Dictato blog](https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/).

FluidAudio's own Parakeet numbers (self-reported, M4/M5 Pro):
- FLEURS full test: EN 5.4 %, FR 5.9 % for v3 ([Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)).
- 60-minute Earnings-22 concatenation: v3 16.5 % WER at 335x, Parakeet Ultra 13.5 % at 457x ([same](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)). This is a different subset from Argmax's, so the two are not comparable.

What the numbers say (opinion):
- **English:** Apple sits around Whisper small on conversational call audio. Parakeet and Whisper large-v3/turbo beat it on every independent set except LibriSpeech, where only the small Whisper models were tested.
- **French:** Apple is level with Whisper turbo on FLEURS (6.6 % each), and Parakeet v3 is about 1 point better.
- No study used far-field mic audio, VoIP-compressed audio or French meetings. The only meeting-like evidence is the Earnings-22 runs and Parakeet's AMI 11.31 %. For Carbon, real-Meeting WER is still **unverified** for every engine.

## 2. Streaming: two concurrent streams for one hour

- **SpeechTranscriber:** built for this.
  - Volatile results "delivered almost as soon as they're spoken", plus finalized results.
  - Pitched as "good for long-form and distant audio, such as lectures, meetings, and conversations" ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
  - `.fastResults` "reduces result latency by using a smaller context window" ([fastResults](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/fastresults)).
  - "There is currently no limit on macOS" on concurrent engine instances ([setModules(_:)](https://developer.apple.com/documentation/speech/speechanalyzer/setmodules(_:))). Instances "can share the same backing engine instances and models" ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)).
  - Running for a full hour is **unverified**; the earlier probes used short clips ([language-detection.md](language-detection.md)).
- **whisper.cpp:** no real streaming API.
  - The `whisper-stream` example is described as "a naive example": it re-runs `whisper_full` every 500 ms on a rolling window, or after a basic energy VAD fires in `--step 0` mode ([stream README](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/README.md)).
  - Two streams would share one model through two `whisper_state`s (the `*_with_state` API in [whisper.h](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h)).
  - Carbon would have to build chunking, de-duplication and stable-prefix logic itself (opinion).
  - Whisper's encoder works on 30 s windows (`transcribe()` uses "a sliding 30-second window", [openai/whisper README](https://github.com/openai/whisper)), so live latency means re-encoding padded audio.
- **WhisperKit:** has a stream mode, and its paper describes real streaming.
  - The paper uses block-diagonal encoder masking over 15 s chunks plus LocalAgreement to confirm text, and reports 0.46 s latency ([arXiv 2507.10860](https://arxiv.org/html/2507.10860)).
  - The open-source CLI has `--stream` ([README](https://github.com/argmaxinc/argmax-oss-swift)).
  - "Real-time transcription with speakers" is a paid Argmax Pro SDK feature ([README](https://github.com/argmaxinc/argmax-oss-swift)). How much of the paper's streaming stack is in the open-source edition is **unverified**.
- **FluidAudio:**
  - Parakeet TDT v3 is a batch model. `SlidingWindowAsrManager` chunks and stitches long audio ([Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)).
  - The true streaming models are Parakeet EOU (English only), Nemotron Streaming English, and **Nemotron 3.5 Streaming Multilingual** (en/es/fr/it/pt/de, 0.56–4.48 s tiers, 2.24 s recommended) ([Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)).
  - Nemotron Multilingual on FLEURS: EN 8.96 %, FR 9.52 % at the 2.24 s tier. Its normalizer differs from founden-bot's, so the numbers are not strictly comparable, but it is not obviously better than Apple live ([Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)).
  - A `multi-stream` CLI demo exists ([ASR GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md)).

## 3. Word timings

| Engine | What you get | Status |
|---|---|---|
| SpeechTranscriber | `.audioTimeRange` on each run of the attributed string ("CMTimeRange", sample-precise timeline), plus `.transcriptionConfidence` | Public API ([WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/); [audioTimeRange](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange); SDK swiftinterface lines 384–386) |
| whisper.cpp | Segment `t0/t1`. Token timestamps via `token_timestamps`, or `dtw_token_timestamps`, both marked **"[EXPERIMENTAL]"**. The README's word-level mode (`-ml 1`) is also "experimental". | [whisper.h](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h) lines 121–148, 505; [README](https://github.com/ggml-org/whisper.cpp) |
| WhisperKit | Word timestamps (its server exposes `timestamp_granularities[]` word/segment) | [README](https://github.com/argmaxinc/argmax-oss-swift) |
| FluidAudio Parakeet | `ASRResult.tokenTimings: [TokenTiming]` (token, start, end, confidence), and a `WordTiming` type | [AsrTypes.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift). The model card claims "accurate word-level and segment-level timestamps" ([HF](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)) |

FluidAudio's diarizer and its Parakeet ASR share a timeline and a vendor. That makes a Parakeet Transcript the easiest one to merge with Speakers (opinion).

## 4. Language identification and code-switching

- **SpeechTranscriber:** one locale per transcriber and no public language ID. A private `LanguageDetector` exists but cannot be used ([language-detection.md](language-detection.md)).
- **whisper.cpp:**
  - `whisper_lang_auto_detect` and `detect_language` work on the first window ([whisper.h](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h) lines 364–388, 534).
  - Auto-detect cannot yet be restricted to a candidate set such as {en, fr}. A PR adding that is still open ([#3822](https://github.com/ggml-org/whisper.cpp/issues/3822)).
  - Whisper decodes one language token per 30 s window, so code-switching inside a window is not modelled. That follows from the 30 s window design ([openai/whisper README](https://github.com/openai/whisper)); per-window language switching in whisper.cpp is **unverified**.
- **WhisperKit:** language detection is supported ([Argmax feature table](https://www.argmaxinc.com/blog/apple-and-argmax); server `language` defaults to auto-detect in the [README](https://github.com/argmaxinc/argmax-oss-swift)).
- **Parakeet v3:**
  - "The model automatically detects the language of the audio and transcribes it without requiring additional prompting" ([HF card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)).
  - FluidAudio's `ASRResult` has **no detected-language field** ([AsrTypes.swift](https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/ASR/Parakeet/AsrTypes.swift)). Carbon would get correct-language text but no label; `NLLanguageRecognizer` on the output could supply one (opinion).
  - Code-switching behaviour is not documented (**unverified**).
- **Nemotron Multilingual (FluidAudio):** Models.md mentions an `auto` language mode, but the CoreML model card shows the language passed explicitly ([Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md); [HF card](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML)). The sources conflict, so treat auto mode as **unverified**.

## 5. Speed, energy, memory, size

| | SpeechTranscriber | whisper.cpp | WhisperKit | FluidAudio Parakeet v3 / Ultra |
|---|---|---|---|---|
| Compute | System, out of process | Metal GPU ("runs fully on the GPU via Metal"). Optional Core ML encoder on the ANE ("more than x3 faster compared with CPU-only"); the decoder stays on Metal/CPU. | Core ML, ANE-first | Core ML; encoder on the ANE by default |
| Measured speed (Mac) | 64x median (FLEURS, M2 Pro); 70x (Earnings-22, M4) | 13x median, turbo q5_0 Metal (M2 Pro) | small.en 35x, base.en 111x (M4) | 20x median in founden-bot (M2 Pro, "CPU and GPU"); FluidAudio self-reports ~190x (M4 Pro), 335–457x on a 60-min file (M5 Pro) |
| App memory | "does not increase ... the run-time memory size. It operates outside of your application's memory space" | large ~3.9 GB, medium ~2.1 GB, small ~852 MB (README table); turbo q5_0 RAM **unverified** | turbo compressed: 1.6 GB → 0.6 GB model | **unverified** for ASR (diarizer peaks 100–400 MB) |
| Model download | None bundled; system asset per locale, shared between apps; size **unverified** | large-v3-turbo 1.5 GiB, turbo q5_0 547 MiB, small 466 MiB | large-v3 turbo compressed 626 MB | v3 ~480 MB, Ultra ~630 MB (int8 encoder 595 MB), Redux ~220 MB (macOS 15+) |
| Energy | **unverified** (no published figure) | **unverified** | Paper: moving the text decoder to the ANE cut one forward pass "1.5W → 0.3W" | "efficiently on Apple's ANE ... minimal power consumption" (claim, no figure) |

Sources:
- Apple: [WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/), [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [founden-bot](https://github.com/founden-bot/on-device-asr-benchmark), [Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax).
- whisper.cpp: [README](https://github.com/ggml-org/whisper.cpp) ("Memory usage" table, "Core ML support"), [models/README](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md).
- WhisperKit: [README](https://github.com/argmaxinc/argmax-oss-swift), [arXiv 2507.10860](https://arxiv.org/html/2507.10860).
- FluidAudio: [README](https://github.com/FluidInference/FluidAudio), [Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md).

Two streams × 1 hour is well within every engine's throughput on paper. The real questions are battery and thermals during a live Meeting, and peak memory next to diarization and Foundation Models. No source measures either for this workload.

## 6. Distribution, notarization, Sparkle

- **SpeechTranscriber** adds nothing to the app.
  - The model "is retained in system storage and does not increase the download or storage size of your application" ([WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
  - Assets download per locale, and the system may unsubscribe unused ones ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)).
  - The model updates with the OS: "the system will automatically install updates" ([WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
  - Argmax notes the flip side: model updates come "at Apple's discretion" and fixes come in the "next OS update at the earliest" ([Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax)).
- **whisper.cpp** ships as a prebuilt XCFramework.
  - The README shows a `binaryTarget` ([README](https://github.com/ggml-org/whisper.cpp)). Recent XCFramework zips are attached to the nightly `bNNNN` releases (`whisper-b5454-xcframework.zip`, 62 MB), not to the `v1.9.x` tags ([releases](https://github.com/ggml-org/whisper.cpp/releases)).
  - The Core ML encoder has to be generated with Python (`ane_transformers`, `coremltools`, `generate-coreml-model.sh`), and "the first run on a device is slow" while the ANE compiles it ([README](https://github.com/ggml-org/whisper.cpp)).
- **WhisperKit / FluidAudio:** SPM packages. Models download from Hugging Face on first use or load from a local URL ([FluidAudio README](https://github.com/FluidInference/FluidAudio) `AsrModels.load(from:)`; [WhisperKit README](https://github.com/argmaxinc/argmax-oss-swift)).
- **Notarization:** Apple requires Developer ID signing, the Hardened Runtime and a secure timestamp ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
  - A whisper.cpp XCFramework is nested code and must be re-signed with Carbon's identity (opinion, standard practice).
  - Models fetched at runtime are data, not code. That they are outside notarization's scope is **unverified** against Apple's text.
- **Sparkle:** bundling a 0.5–1.5 GB model would inflate every DMG.
  - Delta updates send "only the changed parts", so an unchanged model would not be re-downloaded on update ([Sparkle delta updates](https://sparkle-project.org/documentation/delta-updates/)).
  - First install would still be large. Opinion: download third-party models on demand (from Hugging Face or Carbon's R2), never in the DMG.

## 7. Licences

| | Code | Weights |
|---|---|---|
| SpeechTranscriber | System framework | System asset |
| whisper.cpp | MIT ([GitHub API](https://api.github.com/repos/ggml-org/whisper.cpp)) | OpenAI: "Whisper's code and model weights are released under the MIT License" ([openai/whisper README](https://github.com/openai/whisper)). The HF card metadata for large-v3 says apache-2.0 and turbo says mit ([HF API](https://huggingface.co/api/models/openai/whisper-large-v3)); both are permissive. |
| WhisperKit | MIT | MIT on `argmaxinc/whisperkit-coreml` ([HF API](https://huggingface.co/api/models/argmaxinc/whisperkit-coreml)). Pro features are commercial. |
| FluidAudio | Apache-2.0 | Parakeet v3 / Ultra CoreML: **CC-BY-4.0** ([HF API](https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml)). Nemotron Multilingual CoreML: OpenMDW-1.1 ([HF](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML)). |

CC-BY-4.0 needs attribution. Carbon already plans a CC-BY notice in About for the diarization weights ([product design](../../.scratch/carbon-v1/issues/01-carbon-v1-product-design.md)), so Parakeet adds one line.

## 8. macOS versions and Macs

- **SpeechTranscriber:** macOS 26.0+ (SDK `@available(macOS 26.0, ...)`). Check `isAvailable`, which reports availability "given the device's hardware and capabilities" ([isAvailable](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable)). Which Macs return false (for example Intel Macs on macOS 26) is **unverified**. If it is false, Apple points to `DictationTranscriber` ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)).
- **whisper.cpp:** any macOS. For the Core ML path the README recommends macOS 14+, "as older versions of macOS might experience issues with transcription hallucination" ([README](https://github.com/ggml-org/whisper.cpp)).
- **WhisperKit:** macOS 14+ ([README](https://github.com/argmaxinc/argmax-oss-swift)).
- **FluidAudio:** macOS 14+. Parakeet Redux and Phonon-2 need macOS 15+ ([on-device-diarization.md](on-device-diarization.md); [Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)).
- Carbon targets macOS 26, so only `isAvailable` matters.

## 9. Hallucination on silence

- **Whisper (all runtimes):**
  - OpenAI's model card: predictions "may include texts that are not actually spoken in the audio input (i.e. hallucination)", and the architecture "makes it prone to generating repetitive texts" ([model card](https://github.com/openai/whisper/blob/main/model-card.md)).
  - An independent study found "roughly 1% of audio transcriptions contained entire hallucinated phrases or sentences", "38% of hallucinations include explicit harms", and they "disproportionately occur" with longer non-vocal durations ([Koenecke et al., arXiv 2402.08021](https://arxiv.org/abs/2402.08021)).
  - In whisper.cpp, "Hallucination on silence" is still open ([#1724](https://github.com/ggml-org/whisper.cpp/issues/1724)). Long-form repetition loops are tracked in [#3744](https://github.com/ggml-org/whisper.cpp/issues/3744) (open). A docs PR lists the mitigations: language pinning, `--suppress-nst`, `--no-fallback`, thresholds, VAD and `--suppress-regex` ([#4099](https://github.com/ggml-org/whisper.cpp/issues/4099)).
  - whisper.cpp ships Silero VAD support to skip non-speech ([README](https://github.com/ggml-org/whisper.cpp)). Meetings contain long silences on the mic stream (muted, listening), so this matters for Carbon (opinion).
- **SpeechTranscriber:** I found no public report of silence hallucination (**unverified**, absence of evidence). Carbon's own probe showed wrong-locale output that looked fluent in the wrong language ([language-detection.md](language-detection.md)), which is a different failure.
- **Parakeet (TDT transducer):** no hallucination statement on the card ([HF](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)). A repeated-token loop in whisper.cpp's new Parakeet port was "reproduceable with 1.9.2 but no more with master" ([#4088](https://github.com/ggml-org/whisper.cpp/issues/4088)). Opinion: transducers emit blanks on silence by design, so they are structurally less prone than Whisper's free-running decoder. Still to be checked on real Meetings.

## 10. Maintenance

| | Activity (2026-10-27) | Integration burden for Carbon |
|---|---|---|
| SpeechTranscriber | Ships with the OS; no Speech session at WWDC26 ([language-detection.md](language-detection.md)) | Already in the design. Zero third-party code. Black box: no fixes between OS releases. |
| whisper.cpp | ~54.7k stars, v1.9.5 on 2026-10-06, pushed today. Recent releases are mostly ggml syncs. It now also runs Parakeet (`parakeet-cli`, merged 2026-06-16, [#3735](https://github.com/ggml-org/whisper.cpp/issues/3735)). | C API bridged into Swift, a binary XCFramework from nightly tags, a hand-rolled streaming layer, a Python step for Core ML. Highest. |
| WhisperKit | v1.1.1 on 2026-10-08, ~6.4k stars | Swift-native. The repo also bundles SpeakerKit/TTSKit. The best streaming is Pro. |
| FluidAudio | v0.17.7 on 2026-10-08, pushed today, ~3.2k stars | Already a dependency. ASR comes with the same package (the `traits: []` build is "ASR + VAD only"). Lowest extra burden. |

Sources: GitHub API for [whisper.cpp](https://api.github.com/repos/ggml-org/whisper.cpp), [argmax-oss-swift](https://api.github.com/repos/argmaxinc/argmax-oss-swift) and [FluidAudio](https://api.github.com/repos/FluidInference/FluidAudio), plus their release pages; [FluidAudio README](https://github.com/FluidInference/FluidAudio).

## Verdict per candidate (opinion)

- **whisper.cpp: no.**
  - Its strengths (99 languages, language ID, portability) mostly do not matter for an English + French, Apple-only app.
  - It has the weakest live story: a naive sliding window. Word timings are experimental, the GPU-default runtime carries the largest memory and model, and Whisper's silence hallucinations meet Meetings full of muted stretches.
  - Its turbo model is the most accurate English option in founden-bot's FLEURS run (3.9 %), but only level with Apple in French.
- **WhisperKit: no.** It fixes whisper.cpp's integration and ANE problems, but keeps Whisper's hallucination profile and download size. Its best streaming is Pro, and it would add a second ML package next to FluidAudio.
- **FluidAudio Parakeet v3 / Ultra: best post-Meeting candidate.**
  - It is already a dependency, and its weights are CC-BY like the diarizer's.
  - It leads every independent comparison against Apple on English and French (Earnings-22 via Argmax with v2; FLEURS via founden-bot with v3).
  - It auto-detects the language among 25 European languages, gives token and word timings on the same timeline as the diarizer, and runs one hour in tens of seconds on the ANE.
  - It is not a live engine: v3 is batch, and the multilingual streaming model (Nemotron) is not clearly better than Apple live.
- **SpeechTranscriber: keep it as the live engine.** It needs no download, runs out of process with no memory cost to Carbon, streams two inputs with no macOS limit, gives word time ranges and confidence, matches Whisper turbo on French, and is native. Its weaknesses are mid-tier English WER on calls, no language ID, no custom vocabulary (`contextualStrings` is documented for `DictationTranscriber` ([contextualStrings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings))), and OS-paced fixes.

## Recommendation for Carbon

**Keep SpeechTranscriber for v1. Plan a hybrid and prove it before shipping it: SpeechTranscriber live, then an optional FluidAudio Parakeet pass after the Meeting.**

1. **v1 baseline (no change):** SpeechTranscriber live, one analyzer per stream, Meeting Language picked by the person, as designed.
2. **Hybrid candidate:** when a Meeting ends, Carbon already holds the audio and already runs FluidAudio's offline diarizer. Re-transcribe each stream with Parakeet v3 or Ultra in the same pass, then merge it with the Speakers. The final Transcript is the Parakeet one; the live SpeechTranscriber text is a preview.
   - Expected gains: better English call WER, better French WER, automatic language for European languages, and one timeline with diarization.
   - It could also retire the "switch language re-transcribes from the start" flow, since the post-pass ignores the live locale.
   - Cost: a ~480–630 MB on-demand model download, a few tens of seconds per hour of audio, and a CC-BY credit.
3. **Adopt the hybrid only if the prototype shows a real gain** on Carbon's own Meetings. Opinion: a WER drop of a few points on VoIP and far-field audio in both languages, with no new silence hallucinations. Otherwise SpeechTranscriber alone is simpler and fully native, which the map's standing preferences favour.
4. **Drop whisper.cpp and WhisperKit** from consideration unless the prototype shows Parakeet failing on French Meetings. In that case, whisper large-v3-turbo through WhisperKit (Swift, ANE) is the fallback to benchmark, not whisper.cpp.
5. **Proper nouns:** if attendee names matter, FluidAudio's Parakeet CTC models "boost domain-specific terms (names, jargon)" ([Models.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)). EventKit attendee names could feed them. Treat this as a post-pass extra, not a v1 requirement.

## Open questions for the prototype ticket (need real Meetings)

> Answered on the public test set in "Transcription engine quality on real calls" (`.scratch/carbon-v1/issues/14-transcription-engine-on-real-calls.md`): SpeechTranscriber only in v1. Not covered: Whisper as a reference point, a base M1/M2, battery drain, Intel, asset survival over weeks.

Test set: about 10 real Meetings per language (EN, FR, plus a few mixed), each with both streams recorded separately (mic far-field, VoIP app audio) and a hand-corrected reference.

1. **WER per stream and per language** for SpeechTranscriber (en_US / fr_FR) vs Parakeet v3 vs Parakeet Ultra, with Whisper large-v3-turbo as a reference point only. Use the same normalizer for all.
2. **Parakeet's automatic language on French Meetings:** how often does it slip into English (or another language) on short turns, accents or English loanwords? What does it do on code-switched turns?
3. **Silence and hallucination:** phantom text on long muted or silent stretches (mic stream) and music or hold tones (app stream), per engine.
4. **Live cost:** battery drain, CPU/ANE load and thermals (`powermetrics`) for two SpeechTranscriber streams over 60 minutes, and whether volatile results stay stable for the whole hour.
5. **Post-pass cost:** wall time and peak memory for Parakeet on 2 × 60 min, run alongside the offline diarizer, on a base M1/M2 Mac, plus first-run ANE compile time.
6. **Merge quality:** word-timing alignment of SpeechTranscriber `audioTimeRange` vs Parakeet `tokenTimings` against FluidAudio Speaker segments (words assigned to the wrong Speaker at turn boundaries).
7. **Downloads:** actual size and time of the fr_FR SpeechTranscriber asset (still **unverified**) vs the Parakeet model, and whether Apple's assets survive the "unsubscribe" policy across weeks of non-use.
8. **Mac coverage:** `SpeechTranscriber.isAvailable` on the oldest Macs Carbon wants to support (any Intel on macOS 26?), and Parakeet's ANE behaviour there.
9. **Proper nouns:** the error rate on participant and company names, and whether CTC boosting with EventKit attendee names fixes it.
