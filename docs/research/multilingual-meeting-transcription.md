# Transcribing multilingual and code-switching Meetings on-device

Researched 2026-10-30 against primary sources: the macOS SDK in `/Applications/Xcode-26.4.0.app` (SDK 26.4, Speech module 3520.77.1), Apple developer documentation (DocC JSON), the WWDC25 SpeechAnalyzer session, model cards and Hugging Face API metadata at pinned revisions, source code at pinned commits, papers, and a small probe on this Mac (Apple M3 Pro, macOS 27.0.1, build 26A434). My own conclusions are marked **(inference)**. Claims I could not confirm from a primary source are marked **(unverified)**.

The question: can Carbon transcribe a Meeting whose language is not constant?

- **(a) Per-turn switching.** One Speaker talks French and another English, or the whole Meeting moves from one language to the other halfway.
- **(b) Intra-sentence code-switching.** French sentences with English words and phrases ("on a mergé la pull request, le build est cassé sur la CI"), which is normal in French tech Meetings.

This note builds on earlier notes and does not redo them:

- [language-detection.md](language-detection.md): Apple has no public spoken language ID. The private `LanguageDetector` exists. It covers the confidence race and `setModules` mid-stream.
- [offline-spoken-language-identification.md](offline-spoken-language-identification.md): VoxLingua107 ECAPA as the language ID model, plus Whisper `detect_language` cost.
- [language-identification-thresholds.md](language-identification-thresholds.md): how the bundled classifier's vote is calibrated.
- [competitor-meeting-language-handling.md](competitor-meeting-language-handling.md): how open-source meeting apps choose and switch language, and when each engine detects it.
- [speechtranscriber-vs-whisper-cpp.md](speechtranscriber-vs-whisper-cpp.md): accuracy and speed of SpeechTranscriber, whisper.cpp, WhisperKit and Parakeet.
- [ADR 0005](../adr/0005-identify-the-meeting-language-with-a-bundled-classifier.md): one Meeting Language per Meeting, identified once, with whole-Meeting re-transcription on a switch.

### Pins

| Source | Pin |
|---|---|
| Carbon | `45b94abc0816ee15b1d512d4fe71376f456df48d` (plus the uncommitted working tree) |
| `FluidInference/FluidAudio` | `6924debcefeb0c52aa48350ef2e7f0ce0ce4e700` (v0.18.0 era; Carbon pins 0.17.7 in [project.yml](../../project.yml)) |
| `nvidia/parakeet-tdt-0.6b-v3` | HF `541d1f99c6b0c3cd0b11a95167540bb8edefd82b` |
| `nvidia/canary-1b-v2` | HF `d455706339a6b32e1aa40f82c713a482a0c938e2` |
| `nvidia/nemotron-3.5-asr-streaming-0.6b` | HF `ea30d66debe3740a08b573244286791d423d6b3e` |
| `senstella/parakeet-mlx` | `a47079fb1bdc324d1228af6455f1eef8e97e6fae` |
| `kyutai/stt-1b-en_fr` / `-mlx` | HF `1c34c6b4f7e9299bb61985f145052ff131005dde` / `2b995724eef1e964b7ccb6a762b35a665c4abe0d` |
| `kyutai-labs/delayed-streams-modeling` | `4c4f65e147df056adf3346290d64c7b9649b18c9` |
| `mistralai/Voxtral-Mini-3B-2507` | HF `3060fe34b35ba5d44202ce9ff3c097642914f8f3` |
| `mistralai/Voxtral-Mini-4B-Realtime-2602` | HF `2769294da9567371363522aac9bbcfdd19447add` |
| `Qwen/Qwen3-ASR-0.6B` / `-1.7B` | HF `5eb144179a02acc5e5ba31e748d22b0cf3e303b0` / `7278e1e70fe206f11671096ffdd38061171dd6e5` |
| `QwenLM/Qwen3-ASR` | `7c6daf77a2421100f5fb066495372c00129d39ff` |
| `ibm-granite/granite-speech-3.3-2b` / `-8b` | HF `4ac2f02f413c6169ae8c0ccc217115a366e552d7` / `5670dcfae4a296e6993ac53eb25f638c6aaa54d0` |
| `moonshine-ai/moonshine` | `234f60faa0eb388b01cdf7e60aca232af37aefda` |
| `FunAudioLLM/SenseVoiceSmall` | HF `3847d57b6bdf2dd8875cb1508d2af43d80a16bf7` |
| `facebook/seamless-m4t-v2-large`, `facebook/mms-1b-all` | HF `5f8cc790b19fc3f67a61c105133b20b34e3dcb76`, `3d33597edbdaaba14a8e858e2c8caa76e3cec0cd` |
| `openai/whisper-large-v3-turbo` | HF `41f01f3fe87f28c78e2fbf8b568835947dd65ed9` |
| `ggerganov/whisper.cpp` (ggml weights) | HF `5359861c739e955e79d9a303bcbc70fb988958b1` |
| `ggml-org/whisper.cpp`, `argmaxinc/argmax-oss-swift` (WhisperKit) | `e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1`, `9f99b5cb6a907730543823ad271b82532782a899` (same pins as the earlier notes) |

## Short answer

- **Apple cannot do either case in one module.** Each `SpeechTranscriber` or `DictationTranscriber` takes exactly one locale at init, and its locale never changes. There is no multilingual locale for English plus French (`mul_IN` is the only `mul_*` locale), and there is no public auto-detect.
- **(a) per-turn switching is buildable on Apple's engine**, at a cost:
  - Attach a second transcriber in the other locale to the same analyzer. macOS sets no limit on that.
  - Or re-identify per turn with the bundled ECAPA classifier and re-transcribe only the flagged segment.
  - The cheapest version is a **Meeting Language per stream** (Me vs Them), which needs no extra compute.
- **(b) intra-sentence code-switching has no good on-device answer today.**
  - The French `SpeechTranscriber` keeps English loanwords that it knows and that are pronounced natively ("build", "CI", "Daily Standup" in the probe). It mangles the rest: "pull request" became "Powerquest", "rollback" became "long back".
  - `contextualStrings` changed nothing in the probe.
  - No open model on the list claims intra-sentence French–English code-switching. The only French–English code-switching benchmark I found is synthetic. It ranks cloud models first, Parakeet v3 and Voxtral in the middle, and Whisper last, because Whisper translates.
- **Whisper is the wrong tool for both cases.** It picks one language token per 30 s window. On mixed audio it is known to translate into the window's language instead of transcribing.
- **The most interesting new candidate is NVIDIA Nemotron 3.5 ASR Streaming (0.6B, multilingual).**
  - It is cache-aware streaming. With `target_lang=auto`, it emits a language tag per utterance.
  - Its licence (OpenMDW-1.1) is permissive.
  - **FluidAudio, already a Carbon dependency, has a Core ML/ANE port** that reaches 40–73x real time on an M2.
  - On FLEURS French it scores worse than Apple: 9.4% WER, against 6.6% for Apple in a different harness.
  - FluidAudio's manager currently exposes only the *first* language tag per session.
- **Kyutai `stt-1b-en_fr`** is the only open streaming model trained for exactly English and French. It runs on MLX and is CC-BY-4.0, but it makes no code-switching claim and would need a Swift MLX runtime.

## Comparison

"Per-turn" means the model can change language between utterances or segments without being told. "Intra" means it is documented, or measured by a primary source, to handle mixed languages inside a sentence. RTFx is audio duration ÷ processing time. A higher RTFx is faster.

| Model | On-device on Mac | Languages (en+fr?) | Code-switching | Streaming | Size | RTFx on M-series | License |
|---|---|---|---|---|---|---|---|
| Apple `SpeechTranscriber` | System framework (model runs out of process) | 45 locales on this Mac; one per module; yes | **None per module.** Per-turn only by running 2 modules or swapping. Intra: knows some loanwords (probe) | Yes (volatile + final) | 0 in app; per-locale system assets | ~64x (M2 Pro, third party) | Apple SDK |
| Apple `DictationTranscriber` | Same | 54 locales; one per module; yes | Same. Custom LM with pronunciations (`customizedLanguage`) can add English terms **(unverified effect)** | Yes | Same | Not measured | Apple SDK |
| Whisper large-v3 | whisper.cpp (ggml/Metal, Core ML encoder), WhisperKit (Core ML), MLX | 99; yes | Per 30 s window with `language=None` (faster-whisper `multilingual=True`). Intra: poor, **tends to translate** | Pseudo-streaming (re-decode sliding windows) | 1.55B; ggml f16 3.1 GB, q5_0 1.1 GB | Slower than turbo | MIT |
| Whisper large-v3-turbo | Same | 99; yes | Same. Ranked last on the code-switching benchmark | Same | 809M; ggml f16 1.6 GB, q5_0 574 MB | ~13x (whisper.cpp q5_0 Metal, M2 Pro, third party) | MIT |
| NVIDIA Parakeet TDT 0.6B v3 | FluidAudio (Core ML/ANE), parakeet-mlx (MLX) | 25 European; yes | "Automatically detects the language" with no prompt, and is language-agnostic, so it can follow per-turn switches **(inference)**. Middle rank on the code-switching benchmark | Batch; FluidAudio sliding window; parakeet-mlx local-attention streaming | 0.6B; ~600 MB int8 encoder (Ultra) | ~20x (third party, M2 Pro) to ~150x (FluidAudio, M5 Pro) | CC-BY-4.0 |
| NVIDIA Canary-1B-v2 | No Apple port found **(unverified)** | 25 European; yes | Takes `source_lang`; no LID or code-switching claim | No (chunked batch) | 978M | — | CC-BY-4.0 |
| **NVIDIA Nemotron 3.5 ASR Streaming 0.6B** | **FluidAudio `StreamingNemotronMultilingualAsrManager` (Core ML/ANE)** | 40 locales, 19 "transcription-ready"; yes | **Per-utterance language tag in `auto` mode.** Intra: not claimed | **Yes, cache-aware** (560/1120/2240 ms chunks in FluidAudio) | 0.6B, int8 encoder | **40.5–73.1x** (FluidAudio, M2, FLEURS) | OpenMDW-1.1 (permissive) |
| Kyutai `stt-1b-en_fr` | MLX (`moshi-mlx`, `moshi-swift`) | **en + fr only** | Not claimed | **Yes, 0.5 s delay**, semantic VAD | ~1B (bf16 ≈ 2 GB) | Real time on an iPhone 16 Pro (vendor). Mac not measured | CC-BY-4.0 weights; code MIT/Apache |
| Mistral Voxtral Mini 3B (2507) | Community MLX/llama.cpp **(unverified)** | 8 incl. en, fr | "Automatically predicts the source audio language". Intra: not claimed. Voxtral Small 24B is middle rank on the code-switching benchmark | No (30 min file) | 4.7B total; ~9.5 GB bf16 | — | Apache-2.0 |
| Mistral Voxtral Mini 4B Realtime (2602) | vLLM; MLX community port "untested" | 13 incl. en, fr | Not claimed | **Yes, 80 ms–2.4 s delay** | 4.4B; GPU ≥ 16 GB | — | Apache-2.0 |
| Qwen3-ASR 0.6B / 1.7B | Community MLX ports (`mlx-audio`, `mlx-qwen3-asr`) | 30 languages + 22 dialects; yes | LID "via natural-language prompting before ASR decoding". Code-switching claimed only for the aligner | Yes (vLLM only, 2 s chunks) | 0.94B / 2.35B | — | Apache-2.0 |
| IBM Granite Speech 3.3 2B / 8B | Transformers; no Apple port found | en, fr, de, es, pt | Not claimed | No | 3.0B / 8.6B | — | Apache-2.0 |
| SenseVoice Small | FluidAudio (Core ML) | zh, yue, en, ja, ko; **no French** | Auto LID tag | No | small | — | Custom "model-license" |
| Moonshine (streaming) | ONNX Runtime (macOS) | en, ar, de, ja, zh, es, tl, vi…; **no French** | No | Yes | 34–245M | — | MIT (legacy non-English: non-commercial) |
| Meta MMS-1B-all / SeamlessM4T v2 | Possible | 1,100+ / ~100; yes | — | No | ~1B / 2.3B | — | **CC-BY-NC-4.0 (not usable)** |

Sources for each cell are in the sections below. The SpeechTranscriber, turbo and Parakeet RTFx figures come from [speechtranscriber-vs-whisper-cpp.md §1](speechtranscriber-vs-whisper-cpp.md), which cites [founden-bot/on-device-asr-benchmark](https://github.com/founden-bot/on-device-asr-benchmark) and FluidAudio's benchmarks. They are not directly comparable to each other.

## 1. Apple SpeechAnalyzer, SpeechTranscriber and DictationTranscriber

### One locale per module, fixed for its lifetime (SDK)

From `Speech.swiftmodule/arm64e-apple-macos.swiftinterface` (Xcode 26.4, macOS 26.4 SDK, 682 lines):

```swift
// line 335
final public class SpeechTranscriber : Speech.SpeechModule, Speech.LocaleDependentSpeechModule {
  convenience public init(locale: Foundation.Locale, preset: Speech.SpeechTranscriber.Preset)
  convenience public init(locale: Foundation.Locale, transcriptionOptions: ..., reportingOptions: ..., attributeOptions: ...)
// line 409
  final public var selectedLocales: [Foundation.Locale] { get }
```

```swift
// line 49
final public class DictationTranscriber : Speech.SpeechModule, Speech.LocaleDependentSpeechModule {
  convenience public init(locale: Foundation.Locale, preset: Speech.DictationTranscriber.Preset)
```

- Each initializer takes a single `locale:`. `selectedLocales` is get-only, and no locale setter exists, so **a module's locale cannot change mid-stream**. Switching means creating a new module.
- The protocol is `LocaleDependentSpeechModule { static var supportedLocales …; var selectedLocales: [Locale] { get } }` (lines 41–45). The plural is only the asset set; the earlier probe returned exactly the one locale passed in ([language-detection.md §1](language-detection.md)).
- **No multilingual locale for en+fr.** `SpeechTranscriber.supportedLocales` on this Mac contains one `mul_*` entry, `mul_IN`, whose behaviour Apple does not document (probe, below).
- **No public auto-detect.** The only detector in the public interface is `SpeechDetector` (voice activity). The `LanguageDetector` SPI is not public ([language-detection.md §1](language-detection.md)).
- WWDC25: "We set up our SpeechTranscriber by initializing it with a locale object and options that we need. The locale's language code corresponds to the language in which we want to receive transcription." The session never mentions several languages at once ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).

### Several modules on one analyzer (docs, SDK)

- The analyzer takes a module array, and modules can be swapped while it runs (SDK lines 209–216):

```swift
final public actor SpeechAnalyzer : Swift.Sendable {
  public convenience init(modules: [any Speech.SpeechModule], options: Speech.SpeechAnalyzer.Options? = nil)
  final public var modules: [any Speech.SpeechModule] { get }
  final public func setModules(_ newModules: [any Speech.SpeechModule]) async throws
```

- From [`setModules(_:)`](https://developer.apple.com/documentation/speech/speechanalyzer/setmodules(_:)):
  - "Modules can be added or removed to the analyzer mid-stream. A newly-added module will immediately begin analysis on new audio input, but it will not have access to already-analyzed audio."
  - "Several transcriber instances can share the same backing engine instances and models, so long as the transcribers are configured similarly in certain respects."
  - "For iOS and visionOS, this roughly translates to two ongoing recognition instances (or two incompatible modules running simultaneously). **There is currently no limit on macOS.**"
- So an `fr_FR` and an `en_US` `SpeechTranscriber` can run on the same analyzer, over the same audio, at the same time. Carbon has two streams, so that is four modules.
- **Reserved locales.** `AssetInventory.maximumReservedLocales` (SDK line 13) is still **5** on this Mac. Two or three Meeting Languages fit. WWDC25: "Your app can have language support for a limited number of languages at a time. If you exceed the limit, you can ask AssetInventory to deallocate one or more of them" ([session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
- **CPU, ANE and memory cost.** Apple publishes no figures. WWDC25 says the model "operates outside of your application's memory space", so the app's own CPU and RSS do not show its cost ([session 277](https://developer.apple.com/videos/play/wwdc2025/277/)). The probe's wall time (below) is the only measurement: two locales took 0.83 s for 19 s of audio, against 0.48–0.58 s for one. That is roughly 1.5–1.7x, not 2x, from a file, warm **(indicative only)**. Whether the engine runs on the ANE is **(unverified)**: the session never mentions it.

### Per-result confidence (SDK)

- `.transcriptionConfidence` is a `ResultAttributeOption` on both transcribers (lines 117 and 386). It is read as `AttributeScopes.SpeechAttributes.ConfidenceAttribute`, a 0–1 `Double` per run (lines 173–175).
- It combines with `.audioTimeRange`, so each word carries a time and a confidence. That is enough to compare two parallel transcribers per window ([language-detection.md §3](language-detection.md)).
- `Result.alternatives` (lines 153 and 424) are alternatives within one locale. They do not compare languages.

### Vocabulary hooks for English words in French (SDK, docs)

- `AnalysisContext.contextualStrings: [ContextualStringsTag: [String]]` sits on the analyzer (lines 467–483, `setContext` at line 232). Apple documents it only for DictationTranscriber: "With the DictationTranscriber module, you can use this property to specify short custom phrases … Limit the total number of phrases across all tags to no more than 100" ([contextualStrings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)).
- `DictationTranscriber.ContentHint.customizedLanguage(modelConfiguration: SFSpeechLanguageModel.Configuration)` (line 74) loads a custom language model built from `SFCustomLanguageModelData`. That data includes `CustomPronunciation(grapheme:phonemes:)` (lines 523–535). The docs suggest it for terms whose "pronounciation" the system "may not estimate … correctly" ([same page](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)). **`SpeechTranscriber` has no `contentHints`**, so this path only exists on the older DictationTranscriber model.

### Probe: how the French model handles English (TTS, this Mac)

Setup:

- Clips were made with `say`, and the scripts are in the session scratchpad (`probe/cs.swift`, `probe/dt.swift`).
- Each run used an analyzer over a 16 kHz file with `finishAfterFile: true`.
- French `SpeechTranscriber` assets are now installed (`fr_FR`, `fr_CA`, `fr_BE`, `fr_CH`, plus nine `en_*`). `DictationTranscriber` has `en_GB`, `en_US` and `fr_FR`.

This is TTS, one voice per language, clean audio. Real speakers, VoIP and accents will differ.

**Intra-sentence, English terms pronounced natively.** The clip was spliced from French and English "Eddy" voices, 16.5 s:

| Module | Output |
|---|---|
| ST `fr_FR` | "Bon, on a meré la **Powerquest** hier soir, mais le **build** est cassé sur la **CI**. Il fall faire un **long back** du déploiement et en parler au **Daily Standup** avec le **product over**" (mean confidence 0.87) |
| ST `fr_FR` + `contextualStrings` | identical |
| DT `fr_FR`, with and without `contextualStrings` | "Bon, on a merdé là pour le test hier soir, mais le build est cassé sur la CI il faudrait faire du développement et parler au Dado avec le pro" |
| ST `en_US` | 33 commas, confidence ≈ 0.02 |

**Intra-sentence, English terms pronounced the French way** (one French voice reading the whole sentence): ST `fr_FR` gave "on a meré la cul requette … le bruit est cassé sur l'Asie … un rôleack … checker les logs … aux avec le rôle collier". ST `en_US` returned **nothing**.

**Per-turn switch** (FR 0–6 s by Thomas, EN 6–13 s by Samantha, FR 13–19 s by Thomas):

| Module | English turn came out as | Mean confidence by 3 s bin (0, 3, 6, 9, 12, 15, 18 s) |
|---|---|---|
| ST `fr_FR` | "**Thanks a neww.**" (the turn is **dropped**, not translated) | 0.98, 1.00, 0.69, 0.62, 0.91, 0.99, 1.00 |
| ST `en_US` | Correct English. The French turns became phonetic garbage ("Bonjour, a tus, merci d'etrela") | 0.39, 0.31, 0.88, 0.98, 0.30, 0.34, 0.25 |
| DT `fr_FR` | Dropped entirely | — |
| Both ST modules on one analyzer | Same texts as above; wall 0.83 s vs 0.48 s (`fr_FR`) and 0.58 s (`en_US`) alone | — |

What the probe shows **(inference)**:

1. **Wrong-locale behaviour is asymmetric.** `en_US` on French writes low-confidence phonetic words, which is a clear signal. `fr_FR` on English mostly *drops* the speech, and the few words left keep middling confidence (0.62–0.69). Confidence alone under-detects "English spoken into the French model". **Words per second of detected speech** is the stronger signal there.
2. **The French model has English loanwords in its vocabulary**: build, CI, Daily Standup, checker, logs. Native English pronunciation helped it a lot. So case (b) degrades rather than fails. The worst errors hit multi-word English terms the model does not know (pull request, rollback, product owner).
3. **`contextualStrings` did not help either model here.** Apple documents it for DictationTranscriber only. DT also lost more words than ST.

## 2. Whisper on-device (whisper.cpp, WhisperKit, MLX)

- **Detection window.** whisper.cpp detects once per `whisper_full` call, on the first 30 s. faster-whisper `multilingual=True` re-detects every 30 s segment. WhisperKit detects inside each window's decode only if `detectLanguage` is set, and it falls back to `en` on an unknown token. All of this is in [competitor-meeting-language-handling.md §9](competitor-meeting-language-handling.md#9-what-the-engines-do), with pinned links. The 30 s pad cost is covered in [offline-spoken-language-identification.md §2](offline-spoken-language-identification.md).
- **One language token per window.** The decoder is conditioned on a single `<|xx|>` token, so a window holding French and English is decoded "as" one language **(inference from the decoding design in [openai/whisper decoding.py](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/decoding.py#L19-L68))**.
- **It translates instead of transcribing.**
  - [whisper.cpp #1843](https://github.com/ggml-org/whisper.cpp/issues/1843) (2024-02, closed stale, no maintainer reply): "whisper with language set when other language spoken it return translated to the language in option", and "my audio is in French and yet it is automatically translated to English despite the translate parameter is set to false".
  - ServiceNow's code-switching benchmark: "When called without an explicit language parameter on code-switched audio, Whisper defaults to translating into English rather than transcribing, failing to preserve the language spoken in the audio." Whisper large-v3-turbo "sits at the bottom, with WER ranging from 0.16 to 0.61" ([HF blog, 2026-06-09](https://huggingface.co/blog/ServiceNow-AI/code-switching)).
- **The language prompt matters a lot on code-switched audio.** On Mandarin–English SEAME, zero-shot Whisper scored 101.9% MER with `<|en|>`, 80.8% with `<|zh|>` and 67.8% with auto. Fine-tuning closed the gap ([Yang et al., arXiv 2311.17382](https://arxiv.org/abs/2311.17382), Table 3). This is not French, but it is the same mechanism.
- **Streaming** is pseudo-streaming: re-decoding a sliding buffer. See whisper.cpp `examples/stream/stream.cpp` ([pin](https://github.com/ggml-org/whisper.cpp/tree/e4acdfdf214836d6ce5c7f8ac6b43b9912f361a1/examples/stream)) and WhisperKit's `AudioStreamTranscriber` ([pin](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift)). Each re-decode pays a full 30 s encoder pass ([offline-spoken-language-identification.md §2](offline-spoken-language-identification.md)).
- **Sizes.** large-v3 has 1.55B parameters and large-v3-turbo 809M (HF safetensors total 808,878,080). ggml files: `large-v3` 3.1 GB, `large-v3-q5_0` 1.1 GB, `large-v3-turbo` 1.6 GB, `-q5_0` 574 MB, `-q8_0` 874 MB ([HF ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1)).
- **Speed:** about 13x real time for turbo q5_0 on an M2 Pro through whisper.cpp Metal (third party; [speechtranscriber-vs-whisper-cpp.md §1](speechtranscriber-vs-whisper-cpp.md)). That is about a fifth of SpeechTranscriber's speed. Running two live streams with re-decoding would be heavy **(inference)**.
- Opinion: Whisper's per-window language ID makes it a per-turn switcher of sorts, but its translation failure on mixed windows is the worst possible behaviour for (b). The output looks fluent and is wrong.

## 3. NVIDIA Parakeet TDT v3, Canary and Nemotron 3.5 ASR

### Parakeet TDT 0.6B v3

- The [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/blob/541d1f99c6b0c3cd0b11a95167540bb8edefd82b/README.md) says: "The model automatically detects the language of the audio and transcribes it without requiring additional prompting". It covers 25 European languages, has "600 million model parameters", handles "up to 24 minutes … with full attention" or "up to 3 hours with local attention", and is CC-BY-4.0.
- The card makes **no code-switching claim**. Its output is text only, with no language ID output. The [paper](https://arxiv.org/abs/2509.14128) does not discuss LID or code-switching either.
- It has no language token, so it is language-agnostic by design. FluidAudio's optional `language` only filters tokens by script ([competitor note §4](competitor-meeting-language-handling.md#4-pasrommeeting-transcriber)). It should follow a per-turn switch because nothing locks it to a language **(inference)**.
- Code-switching evidence: on ServiceNow's synthetic benchmark (298 French–English records, ElevenLabs TTS of GPT-5 sentences), "Deepgram/Nova-3, Mistral/Voxtral Small, and Nvidia/Parakeet occupy the middle ranks". "Nvidia/Parakeet is the weakest of the three overall but closes the gap on German-English". Six of seven models had errors that rose significantly with the number of language switches on French–English ([HF blog](https://huggingface.co/blog/ServiceNow-AI/code-switching)). Per-model French–English numbers are only in images, so they are **(unverified)**.
- **Apple ports:**
  - FluidAudio, Core ML/ANE. It offers batch v3, plus "Ultra" and "Redux" post-trainings of v3 that are "more accurate than v3 on every benchmark". Long audio goes through `SlidingWindowAsrManager` ("chunked, overlapped, and stitched"), not true streaming ([Models.md](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/Documentation/Models.md)).
  - [parakeet-mlx](https://github.com/senstella/parakeet-mlx/tree/a47079fb1bdc324d1228af6455f1eef8e97e6fae) (Apache-2.0, MLX, default `parakeet-tdt-0.6b-v3`) has `transcribe_stream` with local attention `context_size=(256, 256)`. It publishes no speed claims.

### Canary-1B-v2

- 978M parameters, 25 languages, CC-BY-4.0. Every example passes `source_lang`. The card mentions no LID, no code-switching and no streaming ("dynamic chunking with 1-second overlap") ([model card](https://huggingface.co/nvidia/canary-1b-v2/blob/d455706339a6b32e1aa40f82c713a482a0c938e2/README.md)). I found no Core ML or MLX port **(unverified)**.
- It needs the language up front, so it does not help with either case.

### Nemotron 3.5 ASR Streaming 0.6B (multilingual)

- **What it is.** "A multilingual, streaming Automatic Speech Recognition (ASR) model". It is cache-aware FastConformer-RNNT with "language-ID prompt conditioning to support transcription across 40 language-locales from a single model". French (fr-FR, fr-CA) and English (en-US, en-GB) are both in the "Transcription-ready" tier ([model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/blob/ea30d66debe3740a08b573244286791d423d6b3e/README.md)).
- **Per-utterance language.** "When run with `target_lang=auto`, the model detects the spoken language and emits the corresponding language code/tag in the output following the terminal punctuation. This lets a single deployment transcribe mixed-language traffic and automatically label each utterance with its detected language" (same card). This is the closest open-model answer to case (a). **Intra-sentence switching is not claimed.**
- **Accuracy, FLEURS, auto vs given language** (same card):

  | Language | 1.12 s chunk, language given | 1.12 s chunk, auto |
  |---|---|---|
  | French | 9.03% | 9.02% |
  | English | 7.91% | 8.84% |

  Auto costs almost nothing for French.
- **Licence:** OpenMDW-1.1: "permission is hereby granted, free of charge, to deal in the Model Materials without restriction", provided the notices are kept ([OpenMDW 1.1](https://openmdw.ai/license/1-1/)).
- **FluidAudio port, `StreamingNemotronMultilingualAsrManager`:**
  - Core ML, int8 encoder pinned to `.cpuAndNeuralEngine`. Latency tiers are 560, 1120 and 2240 ms.
  - FLEURS on an Apple M2: `fr_fr` **9.44% WER at 1120 ms** and `en_us` 8.73%. Aggregate RTFx is **40.5x / 66.0x / 73.1x** across the three tiers ([NemotronMultilingual.md](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/Documentation/ASR/NemotronMultilingual.md)).
  - API: `setLanguage("fr-FR")` or `"auto"`, then `detectedLanguage()`.
- **Caveats for Carbon:**
  1. **One language per session.** FluidAudio's `detectedLanguage()` returns the "First language-tag piece … emitted by the decoder this session" ([StreamingNemotronMultilingualAsrManager.swift#L345-L347](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L345-L347)), and `reset()` clears it (L827). Per-utterance tags would mean resetting at each VAD pause, or reading the tag tokens out of the token stream **(inference)**.
  2. **Distribution is unclear.** That doc says the model "is local-path-only at the moment — no HuggingFace repo yet" and must be converted on Linux with CUDA. The same commit's `Models.md` lists `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML` as its repo. The docs contradict each other, and I did not download the repo to check **(unverified)**.
  3. Carbon pins FluidAudio **0.17.7**. Whether that release ships this manager is **(unverified)**; 0.18.0 came out on 2026-10-28.
  4. French WER is worse than Apple's on FLEURS (9.4% vs 6.6%). The harnesses differ, so the gap is indicative only ([speechtranscriber-vs-whisper-cpp.md §1](speechtranscriber-vs-whisper-cpp.md)).
- FluidAudio also lists **Nemotron Unified ASR 0.6B**: 25 European languages, streaming at 2.08, 1.12 or 0.56 s latency, with a `.auto` "language-agnostic" prompt. Its note warns "int8 lost accuracy on French in the conversion check, so fp16 is the CLI default" ([Models.md](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/Documentation/Models.md)).

## 4. Other open models

- **Kyutai STT.** `kyutai/stt-1b-en_fr` is "an English and French model with ~1B parameters, a 0.5 second delay, and a semantic VAD". It is streaming and returns "word level timestamps" ([README](https://github.com/kyutai-labs/delayed-streams-modeling/blob/4c4f65e147df056adf3346290d64c7b9649b18c9/README.md#L22-L35)).
  - Training: pretrained on "2.5 million hours of publicly available audio", then fine-tuned on "1000 hours in English, 600 hours in French" ([model card](https://huggingface.co/kyutai/stt-1b-en_fr/blob/1c34c6b4f7e9299bb61985f145052ff131005dde/README.md)).
  - Weights are CC-BY-4.0. The MLX export is `kyutai/stt-1b-en_fr-mlx` (989M parameters, HF API).
  - On Mac: "the 1b model has been tested to work fine on an iPhone 16 Pro" through `moshi-swift` ([README#L199-L201](https://github.com/kyutai-labs/delayed-streams-modeling/blob/4c4f65e147df056adf3346290d64c7b9649b18c9/README.md#L199-L201)).
  - No code-switching claim. Because one model covers both languages, it needs no language choice. Whether it keeps English words inside French sentences is **(unverified)** and is the obvious thing to test.
- **Mistral Voxtral.**
  - Mini 3B (2507): 8 languages including en and fr. It "automatically predicts the source audio language", handles up to 30 minutes, needs about 9.5 GB in bf16, and is Apache-2.0 ([card](https://huggingface.co/mistralai/Voxtral-Mini-3B-2507/blob/3060fe34b35ba5d44202ce9ff3c097642914f8f3/README.md)).
  - Mini 4B Realtime (2602): "natively streaming" with "configurable transcription delays (240ms to 2.4s)". It is ≈4B parameters, needs a GPU with ≥ 16 GB, is "currently only support[ed] in vLLM", and has an MLX integration marked untested. FLEURS at 480 ms: en 4.90%, fr 6.42% (column order read from a flattened table, so **verify**) ([card](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602/blob/2769294da9567371363522aac9bbcfdd19447add/README.md)).
  - Neither card claims code-switching. Voxtral Small 24B is middle rank on the ServiceNow benchmark.
- **Qwen3-ASR (0.6B, 1.7B).** Apache-2.0. "Support language identification and ASR for 52 languages and dialects". Streaming works only on the vLLM backend ([README#L59-L63, L291](https://github.com/QwenLM/Qwen3-ASR/blob/7c6daf77a2421100f5fb066495372c00129d39ff/README.md)).
  - The [technical report](https://arxiv.org/abs/2601.21337) says LID runs "via natural-language prompting before ASR decoding", so one language per input **(inference)**. It claims "code-switched scenarios" only for the forced aligner.
  - French: 1.7B scores 4.75% on FLEURS-fr and 0.6B 7.72%. LID accuracy is 97.9% on average (1.7B), against 94.1% for Whisper large-v3.
  - Community MLX ports exist (`mlx-audio`, `mlx-qwen3-asr`), and their speed is **(unverified)**.
- **IBM Granite Speech 3.3 (2B, 8B).** Apache-2.0, en/fr/de/es/pt. A "two-pass design" speech-LLM. No code-switching or streaming claim ([card](https://huggingface.co/ibm-granite/granite-speech-3.3-2b/blob/4ac2f02f413c6169ae8c0ccc217115a366e552d7/README.md)). It is 3.0B / 8.6B parameters (HF API), too heavy for two live streams **(inference)**.
- **SenseVoice Small.** zh, yue, en, ja, ko, with a custom licence. **No French**, so it is out. FluidAudio ports it ([Models.md](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/Documentation/Models.md)).
- **Moonshine.** Its streaming models cover English, Arabic, German, Japanese, Mandarin, Spanish, Tagalog and Vietnamese. **No French** ([available-models.md](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/docs/models/available-models.md)). It is out.
- **Meta MMS-1B-all and SeamlessM4T v2.** Both are **CC-BY-NC-4.0** (HF API), so not usable in Carbon.
- **Trained for French–English code-switching:** I found no open on-device model that claims it. The only French–English code-switching benchmark I found is ServiceNow's synthetic one ([HF blog](https://huggingface.co/blog/ServiceNow-AI/code-switching)). CAFE is Algerian Arabic–French–English, not tech French ([arXiv 2411.13424](https://arxiv.org/abs/2411.13424)).

## 5. Competitors: what is new beyond the existing note

[competitor-meeting-language-handling.md](competitor-meeting-language-handling.md) already covers Anarlog, Meetily, Screenpipe, pasrom, Minute, Vexa, Attendee and the others, including Anarlog's lesson that "Most meetings are monolingual, so prefer detection over code-switching". The new points:

- **Deepgram `multi` is cloud only.** "Multilingual Code Switching is available on Nova-2, Nova-3" and also on Flux Multilingual. It streams over a websocket with `language=multi`, and the docs recommend "an endpointing value of 100 ms for code-switching" ([Deepgram docs](https://developers.deepgram.com/docs/multilingual-code-switching)). No local equivalent exists.
- **The best code-switching results are all cloud.** On ServiceNow's benchmark, "ElevenLabs Scribe V2 remains at the first place", followed by AssemblyAI Universal 3-Pro and Gemini 3 Flash. Every open model tested (Voxtral Small, Parakeet v3, Whisper turbo) ranked lower ([HF blog](https://huggingface.co/blog/ServiceNow-AI/code-switching)).
- **Mac apps shipping FluidAudio streaming.** Hedy and Subtitles list "Nemotron streaming ASR" ([FluidAudio README](https://github.com/FluidInference/FluidAudio/blob/6924debcefeb0c52aa48350ef2e7f0ce0ce4e700/README.md), showcase table). Whether they use the multilingual `auto` mode is **(unverified)**.

## What this means for Carbon (options ranked by cost)

What Carbon has today:

- One `SpeechAnalyzer` with one `SpeechTranscriber` per stream ([SpeechTranscriberAdapter.swift](../../App/Sources/Adapters/SpeechTranscriberAdapter.swift), `start(locale:stream:)`).
- One Meeting Language.
- ECAPA identification once, early in the Meeting.
- `changeLanguage(to:)`, which re-transcribes **both** streams from the start in the new language ([Recorder.swift](../../CarbonCore/Sources/CarbonCore/Recorder.swift)).

Case (a) is reachable in steps. Case (b) is not solvable on-device today, only mitigated.

1. **Make the limitation honest (zero cost).**
   - The probe shows that `fr_FR` silently *drops* English turns: "Thanks a neww" for a whole sentence.
   - Low word density on a stream that the speech gate says is speaking is a cheap "this may be another language" signal.
   - Carbon can surface it as a notice offering to switch, or as a marker in the Transcript **(inference)**.
2. **Meeting Language per stream: Me vs Them (low cost, no extra compute).**
   - Each stream already has its own analyzer. ECAPA could vote per stream instead of pooling both, and a stream could switch alone.
   - This covers "I speak French, they speak English", and the common mirror case.
   - It changes ADR 0005 ("A Meeting has one language, so the decision is per Meeting, not per stream"), the GLOSSARY's Meeting Language, and `changeLanguage` (re-transcribe one stream).
   - It does not cover a speaker who switches, or a mixed "Them" stream.
3. **Per-turn re-identification with the bundled ECAPA (low–medium cost).**
   - Keep scoring VAD segments after the first decision. ECAPA costs about 11 ms per check ([offline-spoken-language-identification.md](offline-spoken-language-identification.md)).
   - When a run of segments on a stream votes for another chosen language, re-transcribe **only those segments** with a second, short-lived analyzer in that locale. Feed it from the recorded file, as `StreamRecorder.hand(to:)` already reads back. Then replace the words in that time range.
   - Live text is wrong for a few seconds, then corrected.
   - Risks: accent bias (French-accented English scored as French), and hysteresis tuning. The thresholds work in [language-identification-thresholds.md](language-identification-thresholds.md) carries over.
4. **Parallel transcribers for the whole Meeting (medium cost).**
   - Attach `fr_FR` and `en_US` transcribers to each stream's analyzer. macOS sets no limit, and two locales fit under `maximumReservedLocales` = 5.
   - Per window or utterance, keep the locale with the better **confidence and words per second**. Confidence alone misses the `fr_FR`-drops-English case.
   - Cost: about 1.5–2x the Apple engine for the whole Meeting (probe wall time, indicative), plus merge logic for misaligned segments. It gives instant per-turn switching with no re-transcription, but does nothing for (b).
5. **Swap the live engine to Nemotron 3.5 ASR Streaming through FluidAudio (high cost, best fit for (a)).**
   - One model covers en+fr with `auto` and per-utterance tags, on Core ML/ANE, at 40–73x real time, under a permissive licence, inside a dependency Carbon already ships.
   - Before committing:
     - upgrade past FluidAudio 0.17.7;
     - settle the model distribution question;
     - add a per-utterance reset or tag reading;
     - add the download size to the app;
     - measure French accuracy on real Meetings, since FLEURS suggests it is worse than Apple's.
   - Keep SpeechTranscriber as the monolingual default and offer Nemotron only for Meetings with several chosen languages **(inference)**.
6. **Prototype Kyutai `stt-1b-en_fr` for (b) (high cost, speculative).** It is the only open streaming model trained on exactly English and French. Test it on recorded Franglais Meetings before considering an MLX runtime in the app: about 2 GB of weights and an MLX dependency, which [offline-spoken-language-identification.md](offline-spoken-language-identification.md) already judged too heavy for a 43 MB classifier.
7. **Do not use Whisper for this.** Its per-window language token and its translation failure mode make code-switched output fluent and wrong.
8. **Post-Meeting mitigation for (b) (low–medium cost, (inference)).** No engine fixes intra-sentence English. A post-pass could rewrite known mis-hearings ("Powerquest" → "pull request") from a per-person glossary, by rules or with an on-device LLM over the Transcript. `contextualStrings` showed no effect in the probe, and `customizedLanguage` exists only on the weaker DictationTranscriber. Measure both on real audio before relying on them.

Before building any of this, record real bilingual and Franglais Meetings: French and English turns, French-accented English, English jargon in French. Then measure per-window confidence, words per second and ECAPA margins. Every number above is TTS or vendor-reported.

## Appendix: probe

The scripts are in the session scratchpad. Run with `xcrun swiftc -parse-as-library -O` on macOS 27.0.1, Xcode 26.4. No microphone was used.

- `probe/loc.swift`:
  - `maximumReservedLocales` = 5, `reservedLocales` = [].
  - `SpeechTranscriber.installedLocales` = `en_AU, en_CA, en_GB, en_IE, en_IN, en_NZ, en_SG, en_US, en_ZA, fr_BE, fr_CA, fr_CH, fr_FR`.
  - `DictationTranscriber.installedLocales` = `en_GB, en_US, fr_FR`.
  - The only `mul_*` supported locale is `mul_IN`.
- `probe/cs.swift <file> <locales>`: one `SpeechAnalyzer(inputAudioFile:modules:finishAfterFile:)` with one `SpeechTranscriber` per locale, options `[.audioTimeRange, .transcriptionConfidence]`. It prints the text, the mean confidence per 3 s bin and the words under 0.5.
- `probe/dt.swift <file> <locale> <speech|dictation> <ctx>`: the same, optionally with `AnalysisContext.contextualStrings[.general]` = pull request, merger, build, CI, rollback, checker, logs, daily standup, product owner.
- Audio: `say` voices Eddy (fr_FR, en_US), Thomas (fr_FR) and Samantha (en_US), converted to 16 kHz mono WAV and joined with ffmpeg:
  - `splice.wav`: French and English phrases alternated inside one sentence, 16.5 s.
  - `franglais.wav`: one French voice, 11.0 s.
  - `turns.wav`: FR, EN, FR, 19.1 s.
