# On-device speaker diarization for the "Them" stream

Researched 2026-10-27 against primary sources (repos, source code at pinned commits, model cards, license texts, papers). Every claim carries a source link. Anything not confirmed from a primary source is marked **unverified**.

## Problem framing

- Carbon records two streams: the mic ("Me") and the meeting app's audio through a Core Audio process tap ("Them"). "Me" is already attributed, so only "Them" needs diarization: one mixed channel, usually 1 to 6 remote speakers, compressed VoIP audio.
- `SpeechTranscriber` (macOS 26+) has no speaker output. It can attach time codes to its result text: `ResultAttributeOption.audioTimeRange` "includes time-code attributes in a transcription's attributed string", carried as `TimeRangeAttribute` ("the time range in the source audio corresponding to the associated transcription text"). Sources: [audioTimeRange](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange), [SpeechTranscriber.Result](https://developer.apple.com/documentation/speech/speechtranscriber/result), [TimeRangeAttribute](https://developer.apple.com/documentation/foundation/attributescopes/speechattributes/timerangeattribute). I found no diarization module on the [SpeechTranscriber page](https://developer.apple.com/documentation/speech/speechtranscriber). That Apple has no diarization API anywhere is **unverified** (I did not audit every Speech framework symbol).
- Three needs: (1) split "Them" into Speaker A/B/C, (2) let the user name them, (3) recognize the same voices in later Meetings. Need (3) needs an exposed **speaker-embedding** vector, not only labels.

## Candidates

### 1. FluidAudio (FluidInference)

- **Maintained:** yes. Latest release v0.17.7 on 2026-10-08, last push 2026-10-25, about 3.2k stars ([GitHub API, repo](https://api.github.com/repos/FluidInference/FluidAudio), [releases](https://github.com/FluidInference/FluidAudio/releases)).
- **Code license:** Apache-2.0 ([repo](https://github.com/FluidInference/FluidAudio)).
- **Swift/SPM:** pure Swift package with no dependencies, `swift-tools-version: 6.0`, platforms `.macOS(.v14)`, `.iOS(.v17)` ([Package.swift](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Package.swift)). Since 0.17.x a `Diarizer` package trait enables diarization (`traits: ["Diarizer"]`, Swift 6.2 / Xcode 26) ([README](https://github.com/FluidInference/FluidAudio)).
- **Diarizers offered** ([README](https://github.com/FluidInference/FluidAudio), [GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)):
  - **Offline, recommended:** `OfflineDiarizerManager`, a CoreML port of **pyannote community-1** (powerset segmentation + WeSpeaker + VBx).
  - **Streaming:** `LSEENDDiarizer` (default online choice, up to 10 speakers, 100 ms updates, ~900 ms tentative window), `SortformerDiarizer` (up to 4 speakers), and legacy `DiarizerManager` (pyannote 3.1 + WeSpeaker, chunked, needs ≥5 s chunks).
  - The source tree also has a `Nemotron3Diarizer`, a "streaming 8-speaker diarizer backed by NVIDIA's Nemotron 3 Diarization" ([source](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Sources/FluidAudio/Diarizer/Nemotron3/Nemotron3Diarizer.swift)). I did not find it in the docs I read, so treat its readiness as **unverified**.
- **Offline API:** `prepareModels()`, then `process(audio:)` (16 kHz mono Float32) or `process(_ url:)` (memory-mapped). The result exposes `segments` (`speakerId`, `startTimeSeconds`, `endTimeSeconds`) and `speakerDatabase: [String: [Float]]?`, one embedding per speaker. `embedSpans(audioSource:spans:)` returns embeddings for arbitrary time ranges with no segmentation or clustering ([GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)). Post-processing emits **exclusive** (non-overlapping) segments by default (`exclusiveSegments: true`). `numSpeakers`, `minSpeakers` and `maxSpeakers` clustering constraints exist ([OfflineDiarizerTypes.swift](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerTypes.swift), [OfflineDiarizerManager.swift](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift)).
- **Embeddings for voice memory:** 256-dim WeSpeaker vectors. `embedSpans` output matches the `speakerDatabase` values and can be compared with cosine similarity ([GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)). `SpeakerManager` provides `cosineDistance`, known-speaker enrollment (`initializeKnownSpeakers`, `upsertSpeaker`, permanent speakers), a default match threshold of 0.65 cosine distance, and distance bands (<0.5 same speaker, ≥0.7 different, 0.5–0.7 uncertain). `Speaker` is `Codable`. **However, `SpeakerManager` works only with the streaming `DiarizerManager`, not `OfflineDiarizerManager`** ([SpeakerManager.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/SpeakerManager.md)). With the offline pipeline, Carbon would store `speakerDatabase` vectors itself and match them by cosine distance.
- **Compute units:** the offline pipeline runs segmentation, embedding and PLDA with `.all` by default (CoreML picks ANE/GPU/CPU) and fbank with `.cpuOnly` ([OfflineDiarizerModels.swift](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerModels.swift)). LS-EEND defaults to `.cpuOnly`, which the docs call its fastest option ([LS-EEND.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/LS-EEND.md)). How much of the offline pipeline actually lands on the ANE is **unverified**.
- **Benchmarks** ([Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)), all self-reported:
  - Offline community-1, **AMI SDM** (16 meetings), M5 Pro: **DER 10.6 %**, JER 17.4 %, **RTFx 323** (one hour of audio in about 11 s). The page notes this table predates a threshold-semantics change (#801).
  - Offline community-1, **VoxConverse** (232 clips): average DER 13.9–15.1 %, RTFx 65–122 depending on config. Hardware not stated. The page gives the PyTorch baseline as about 11 %.
  - Streaming community-1 chunks, AMI SDM: DER 38–56 %. That makes it unusable for live labelling.
  - LS-EEND streaming, AMI SDM, M4 Max CPU: **DER 20.7 %**, RTFx 74.5.
  - Sortformer streaming, AMI SDM, M2: DER 31.7 %. The `highContextV2_1` streaming variant reaches 26.4 %.
- **Memory:** each 10 s segmentation window adds about 13 MB at peak. `batchSize` 32 peaks around 400 MB; 8 windows peak around 100 MB, with identical output ([GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)).
- **Model download:** the docs say "about 100 MB" of CoreML models ([GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)). Measured from the HF file tree, the community-1 compiled set (Segmentation 6.0 + Embedding 13.4 + FBank 1.8 + PLDA/PldaRho 0.4 MB) is about **22 MB**. The ~100 MB figure includes the legacy artifacts ([HF tree API](https://huggingface.co/api/models/FluidInference/speaker-diarization-coreml/tree/main?recursive=true)). Models download from Hugging Face on first use, or can be bundled.
- **Model weights licenses:**
  - community-1 CoreML artifacts: **CC-BY-4.0**. Legacy artifacts derive from pyannote/segmentation-3.0 (MIT) and wespeaker-voxceleb-resnet34-LM (CC-BY-4.0). The repo is not gated ([HF FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml)).
  - LS-EEND CoreML: MIT ([HF ls-eend-coreml](https://huggingface.co/FluidInference/ls-eend-coreml)). Upstream `LS-EEND/LICENSE` is MIT ([upstream LICENSE](https://github.com/Audio-WestlakeU/FS-EEND/blob/main/LS-EEND/LICENSE)).
  - Sortformer CoreML: CC-BY-4.0 on HF ([HF](https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml)), based on NVIDIA's diar_streaming_sortformer_4spk-v2.1. The FluidAudio README instead says "NVIDIA Open Model License" ([README](https://github.com/FluidInference/FluidAudio)). The sources conflict; NVIDIA's v2 card says CC-BY-4.0 ([HF nvidia v2](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2)).
  - Nemotron-3-Diarization: OpenMDW 1.1, "ready for commercial or non-commercial use" ([HF](https://huggingface.co/nvidia/Nemotron-3-Diarization)).
- **Min macOS:** package and offline diarizer require macOS 14. macOS 14 can crash in BNNS during CoreML predictions; Apple fixed this in macOS 15 ([GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)). This does not matter for Carbon, which targets macOS 26.
- **French / multilingual:** the diarization docs I read give no language claims. LS-EEND CoreML is tagged "English" ([HF](https://huggingface.co/FluidInference/ls-eend-coreml)). community-1's French evidence comes from upstream pyannote (see section 3).

### 2. Argmax SpeakerKit (argmax-oss-swift, formerly WhisperKit repo)

- **Maintained:** yes. v1.1.1 on 2026-10-08, last push 2026-10-11, about 6.4k stars ([GitHub API](https://api.github.com/repos/argmaxinc/argmax-oss-swift), [releases](https://github.com/argmaxinc/argmax-oss-swift/releases)).
- **Code license:** MIT ("Argmax OSS is released under the MIT License") ([README](https://github.com/argmaxinc/WhisperKit)). Real-time transcription with speakers is a paid **Argmax Pro SDK** feature ([README](https://github.com/argmaxinc/WhisperKit)). The [SpeakerKit blog](https://www.argmaxinc.com/blog/speakerkit) describes a commercial "SpeakerKit Pro" under the subscription Argmax SDK.
- **Swift/SPM:** `.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")` with a `SpeakerKit` product. Platforms `.macOS(.v13)`, `.iOS(.v16)` ([Package.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Package.swift)). The package bundles WhisperKit and TTSKit targets, so it is a heavier dependency than FluidAudio. Whether the `SpeakerKit` product links only what it needs is **unverified**.
- **Pipeline:** the README says it "runs Pyannote v4 (community-1)" ([README](https://github.com/argmaxinc/WhisperKit)). In source, the default segmenter and embedder model versions are `"pyannote-v3"`, with a `"pyannote-v4"` PLDA clusterer and VBx clustering ([PyannoteConfig.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/Pyannote/PyannoteConfig.swift), [VBxClustering.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/Pyannote/VBxClustering.swift)). Offline / whole-file only in the OSS edition.
- **Compute units:** embedder `.cpuAndNeuralEngine`, segmenter `.cpuOnly`, clusterer `.cpuOnly` by default ([PyannoteConfig.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/Pyannote/PyannoteConfig.swift)).
- **Embeddings:** `DiarizationResult.speakerCentroidEmbeddings: [Int: [Float]]` gives one centroid per speaker, the mean of per-window embeddings. It also offers `centroidCosineDistance(between:and:)` and `nearestSpeakerCentroid(to:)`, a cosine nearest-neighbour lookup against an external embedding ([DiarizationResult.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/DiarizationResult.swift)). The embedding dimension is not documented; 256 (WeSpeaker ResNet34) is **unverified**. No enrollment or known-speaker API.
- **Transcript merge helper:** `addSpeakerInfo(to:strategy:)` takes WhisperKit `TranscriptionResult` only, so it does not apply directly to `SpeechTranscriber`. Its algorithm is the reference to copy (see "Merging" below) ([DiarizationResult.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/DiarizationResult.swift), [SpeakerInfo.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/SpeakerInfo.swift)).
- **Speed / size:** "~1 second for 4 minutes of audio on an iPhone", "~10 megabytes in total" ([blog](https://www.argmaxinc.com/blog/speakerkit)). The HF repo holds about 33 MB across all variants (embedder 25.2 MB, segmenter 7.7 MB, clusterer 0.2 MB) ([HF tree API](https://huggingface.co/api/models/argmaxinc/speakerkit-coreml/tree/main?recursive=true)). Default variants are W8A16 quantized on macOS 15+ ([PyannoteConfig.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/Pyannote/PyannoteConfig.swift)). Memory: **unverified**.
- **Benchmarks:** the SDBench paper (Interspeech 2025) reports SpeakerKit "9.6x faster than Pyannote v3 while achieving comparable error rates" over 13 datasets on an M2 Ultra in fp16. Its ablation table shows DER 0.255–0.257 at speed factor 373–446 ([arXiv 2507.16136](https://arxiv.org/html/2507.16136v2)). Per-dataset numbers are only in figures, and none of the 13 datasets is French (same source). The repo's BENCHMARKS.md covers ASR only ([BENCHMARKS.md](https://github.com/argmaxinc/argmax-oss-swift/blob/main/BENCHMARKS.md)).
- **Model weights license:** "SpeakerKit the Swift framework has MIT license. The models SpeakerKit is built on have CC BY 4 license." ([HF argmaxinc/speakerkit-coreml](https://huggingface.co/argmaxinc/speakerkit-coreml)).

### 3. pyannote (upstream, Python): community-1 and 3.1

- **Maintained:** yes. pyannote.audio 4.0.7 on 2026-06-30, last push 2026-10-25, MIT code license ([GitHub API](https://api.github.com/repos/pyannote/pyannote-audio), [repo](https://github.com/pyannote/pyannote-audio)).
- **Licenses:** community-1 is **CC-BY-4.0** and gated (users must accept the conditions and share HF info) ([HF community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)). 3.1 is **MIT** and gated ([HF 3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)). The WeSpeaker embedding model is CC-BY-4.0 ([HF wespeaker](https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM)). CC-BY-4.0 allows commercial use "for any purpose, even commercially", with attribution ([CC BY 4.0 deed](https://creativecommons.org/licenses/by/4.0/)). For a closed-source free app this means an attribution notice (for example in About / Acknowledgements).
- **Not directly usable** in a Swift app: PyTorch, no CoreML, no streaming mentioned ([repo](https://github.com/pyannote/pyannote-audio)). FluidAudio and SpeakerKit are the CoreML ports.
- **Speed (reference only):** community-1 at 31 s per hour of audio on an NVIDIA H100 ([repo](https://github.com/pyannote/pyannote-audio)). FluidAudio measured about 1.5–2 RTFx on CPU and 20–25 RTFx on MPS for the PyTorch pipeline on Mac ([FluidAudio Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)).
- **DER (%), no collar, overlap scored** ([HF community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)):

| Dataset | 3.1 | community-1 |
|---|---|---|
| AMI (IHM) | 18.8 | 17.0 |
| AMI (SDM) | 22.7 | 19.9 |
| DIHARD 3 | 21.4 | 20.2 |
| VoxConverse v0.3 | 11.2 | 11.2 |
| CALLHOME part 2 | 28.5 | 26.7 |
| AISHELL-4 | 12.2 | 11.7 |
| AliMeeting ch1 | 24.5 | 20.3 |
| MSDWild | 25.4 | 22.8 |
| **REPERE phase 2** | **7.9** | **8.9** |

- **French:** REPERE is a French TV video corpus built for person recognition, including "who is speaking?" ([LREC 2012, aclanthology L12-1410](https://aclanthology.org/L12-1410/)). It is the only French data point I found for any candidate. community-1 does slightly *worse* than 3.1 there (8.9 vs 7.9). REPERE is broadcast TV, not VoIP meetings, so transfer to Carbon's audio is **unverified**.
- community-1 adds an **exclusive diarization** output that "simplifies the reconciliation" with transcription timestamps ([HF community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)). FluidAudio's offline port emits exclusive segments by default (see section 1).

### 4. sherpa-onnx (k2-fsa)

- **Maintained:** very active. v2.0.1 on 2026-10-26, about 15.5k stars, Apache-2.0 code ([GitHub API](https://api.github.com/repos/k2-fsa/sherpa-onnx), [releases](https://github.com/k2-fsa/sherpa-onnx/releases)).
- **Swift/SPM:** a `Package.swift` ships prebuilt static and shared xcframeworks plus an onnxruntime dependency. Platforms `.macOS(.v10_15)`, `.iOS(.v15)` ([Package.swift](https://github.com/k2-fsa/sherpa-onnx/blob/master/Package.swift)). Swift examples exist: `speaker-diarization.swift` and `compute-speaker-embeddings.swift` ([swift-api-examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)). The API is a C bridge rather than idiomatic Swift (**unverified**, from file layout only).
- **Pipeline:** pyannote segmentation-3.0 (ONNX, 5.7 MB / int8 1.5 MB) or Reverb diarization v1, plus a speaker embedding model (3D-Speaker ERes2Net or NeMo TitaNet), then clustering. The examples use `sherpa-onnx-offline-speaker-diarization`, so offline only ([models page](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html)).
- **License trap:** Reverb diarization v1 is "accessible under a non-commercial license" ([models page](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html)). Licenses of the 3D-Speaker and TitaNet ONNX exports are not stated there: **unverified**.
- **ANE:** runs on onnxruntime. A `coreml` execution provider exists in source ([provider.cc](https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/csrc/provider.cc)). Whether diarization models actually run on the ANE through it is **unverified**.
- **Benchmarks:** RTF only (for example 0.297 for pyannote + 3D-Speaker). No DER published ([models page](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html)).
- **Embedding API:** a speaker-embedding extractor plus examples exist ([swift-api-examples](https://github.com/k2-fsa/sherpa-onnx/tree/master/swift-api-examples)). Dimensions depend on the chosen model: **unverified**.

### 5. Others found

- **NVIDIA Streaming Sortformer 4spk v2:** CC-BY-4.0, max 4 speakers, "primarily in English" training data. DER: DIHARD III 18.91 %, CALLHOME 2–4 speakers 6.6–12.4 % ([HF](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2)). Exposes no speaker embedding: it uses arrival-order slots (**unverified** for v2; FluidAudio offers enrollment-by-audio only, per [GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md)). Max 4 speakers is tight for some meetings.
- **NVIDIA Nemotron-3-Diarization:** OpenMDW 1.1 (commercial OK), up to 8 speakers, multilingual training data (English, Mandarin, Hindi and others; French not listed). DER: DIHARD III 12.7–13.6 %, CALLHOME 9.1–11.3 %, AliMeeting 6.4–7.2 % ([HF](https://huggingface.co/nvidia/Nemotron-3-Diarization)). A CoreML port exists in FluidAudio (`FluidInference/nemotron-3-diarization-coreml`, referenced in [source](https://github.com/FluidInference/FluidAudio/blob/1b0ed50d686873128a4129b3510ce3914c849bab/Sources/FluidAudio/Diarizer/Nemotron3/Nemotron3Models.swift)). Its maturity and Mac benchmarks are **unverified**.
- **LS-EEND:** end-to-end streaming, MIT. Variants: AMI DER 20.76 % (max 4 speakers), CALLHOME 12.11 %, DIHARD III 19.61 % (max 10 speakers). Mostly simulated training data, "no API for per-slot similarity outputs" (no embeddings), and enrollment "less reliable" than the WeSpeaker speaker database ([LS-EEND.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/LS-EEND.md)).
- **pyannoteAI precision-2:** hosted, cloud-only ([HF community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)). Excluded because Carbon is fully on-device.

## Merging diarization with SpeechTranscriber word timings

Inputs:
- `SpeechTranscriber` finalized results with `.audioTimeRange` enabled. Each run of the `AttributedString` carries a `TimeRangeAttribute` (`CMTimeRange`) in source-audio time ([audioTimeRange](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange), [TimeRangeAttribute](https://developer.apple.com/documentation/foundation/attributescopes/speechattributes/timerangeattribute)). `AttributedString.rangeOfAudioTimeRangeAttributes(intersecting:)` is the reverse lookup: text range for a time range ([doc](https://developer.apple.com/documentation/foundation/attributedstring/rangeofaudiotimerangeattributes(intersecting:))). Whether runs are exactly one per word or can span several words is **unverified**. Treat a run as the smallest timed token.
- Diarization segments `(speakerId, start, end)` for the "Them" file, ideally exclusive (non-overlapping).

Steps (adapted from SpeakerKit's `subsegment` strategy, [DiarizationResult.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/DiarizationResult.swift), [SpeakerInfo.swift](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/SpeakerKit/SpeakerInfo.swift)):

1. **Use one time origin.** Run diarization on the same "Them" samples fed to the analyzer, so both timelines start at sample 0 of that stream. The "Me" stream is attributed directly and skips this.
2. **Flatten timed runs** from all finalized results into `(text, start, end)` tokens. Volatile results are skipped because they are replaced later ([SpeechTranscriber.Result](https://developer.apple.com/documentation/speech/speechtranscriber/result)).
3. **Group tokens into sub-segments**, splitting where the gap between consecutive tokens exceeds a threshold. SpeakerKit uses 0.15 s by default.
4. **Assign a speaker** to each sub-segment: the diarization speaker with the largest temporal intersection. SpeakerKit uses intersection for sub-segments and IoU for whole segments.
5. **Fall back to the previous speaker** when nothing overlaps, for example a token in a gap between diarization segments. SpeakerKit does this.
6. **Coalesce** consecutive sub-segments with the same speaker into Transcript turns. Interleave "Me" and "Them" turns by start time.
7. Prefer **exclusive** diarization output so each instant has at most one speaker. Overlapped speech in "Them" then goes to the dominant speaker rather than being duplicated ([HF community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)).

## Cross-meeting voice memory (design notes)

- Store one or more L2-normalized centroid embeddings per named person (FluidAudio `speakerDatabase` values or `embedSpans` output). After each Meeting, match each new speaker's centroid to stored people by cosine distance. FluidAudio's documented bands give a starting point: <0.5 auto-match, 0.5–0.7 ask the user, ≥0.7 new person ([SpeakerManager.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/SpeakerManager.md)). These thresholds were tuned for that library, not for VoIP-compressed tap audio: **unverified for Carbon**.
- FluidAudio's own clean-embedding helper skips speakers with less than 4 s of clean speech, fewer than 2 kept chunks, or under 60 % clean coverage ([SpeakerManager.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/SpeakerManager.md)). Reuse the same gate before saving a voice.
- Embeddings are tied to a specific embedding model. A model upgrade invalidates stored vectors, so store the model id and version next to each vector. (Design inference, not from a source.)
- Voice embeddings are biometric data. Keeping them local in the Library matches Carbon's stance; GDPR classification is outside this research's scope.

## Comparison

| | FluidAudio (offline community-1) | FluidAudio LS-EEND (streaming) | Argmax SpeakerKit (OSS) | sherpa-onnx | pyannote upstream |
|---|---|---|---|---|---|
| Maintained (latest release) | yes, 2026-10-08 | same package | yes, 2026-10-08 | yes, 2026-10-26 | yes, 2026-06-30 |
| Code license | Apache-2.0 | Apache-2.0 | MIT | Apache-2.0 | MIT |
| Weights license | CC-BY-4.0 | MIT | CC-BY-4.0 | varies; Reverb non-commercial | CC-BY-4.0 (c1) / MIT (3.1) |
| Native Swift / SPM | yes, zero deps | yes | yes (bundles WhisperKit) | xcframework + onnxruntime | no (Python) |
| Runs via CoreML/ANE | CoreML `.all` | CPU-only by default | embedder on ANE | onnxruntime (CoreML EP unverified) | no |
| Mode | post-meeting | live | post-meeting | post-meeting | post-meeting |
| DER AMI SDM | 10.6 % (self-reported) | 20.7 % | not published per dataset | none published | 19.9 % |
| French evidence | via upstream REPERE 8.9 % | none | none | none | REPERE 8.9 % |
| Speaker embeddings | 256-dim, `speakerDatabase`, `embedSpans` | no | per-speaker centroids | yes, model-dependent | internal only |
| Model download | ~22 MB (c1 set) | unverified | ~10 MB claimed, ~33 MB repo | ~2–10 MB seg + embedder | n/a |
| Min macOS | 14 | 14 | 13 | 10.15 | n/a |

## Recommendation (my opinion)

1. **Use FluidAudio's `OfflineDiarizerManager` (community-1) as a post-meeting pass on the "Them" stream.** It has the best published Mac DER (10.6 % AMI SDM at about 323× real time), a pure-Swift zero-dependency SPM package, commercially usable weights (CC-BY-4.0, which needs an attribution line in the app), small models (~22 MB), and, unlike the alternatives, a first-class embedding API (`speakerDatabase` and `embedSpans`, 256-dim, cosine). That API covers naming and cross-meeting recognition without a second model.
2. **Keep live attribution coarse:** "Me" vs "Them" while the meeting runs, then relabel "Them" into Speaker A/B/C when the pass finishes, which takes seconds for a one-hour meeting. Streaming options are clearly worse in published DER (LS-EEND 20.7 %, Sortformer 26–32 %) and expose no embeddings. Revisit LS-EEND or Nemotron-3 only if live speaker labels become a product requirement.
3. **Build cross-meeting memory in Carbon, not in the library.** `SpeakerManager` is streaming-only, so store per-person centroids with the embedding model version, and match by cosine distance with an "ask the user" band.
4. **Validate on French VoIP audio before committing.** No candidate publishes DER on French meeting audio. REPERE (French TV) is the only proxy. Record 5–10 real Meet/Zoom calls through the tap, hand-label them, and measure DER and the cosine thresholds.
5. **Keep SpeakerKit as the fallback.** It is the same pyannote family under a permissive license with centroid embeddings, but it pulls WhisperKit and TTSKit into the package and has no enrollment API. **Avoid sherpa-onnx** for this use: no published DER, non-Swift-native, and a non-commercial model in its default list.
