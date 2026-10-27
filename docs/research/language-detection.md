# Native spoken-language detection for Transcripts

Researched 2026-10-27 against primary sources: Apple developer documentation (fetched as DocC JSON from `developer.apple.com/tutorials/data/documentation/...`), WWDC session transcripts, the macOS SDK in `/Applications/Xcode-26.4.0.app` (SDK 26.4), and probes run on this Mac (macOS 27.0.1, build 26A434). Every claim carries a source. Anything not confirmed from a primary source is marked **unverified**.

Probe scripts and test audio live in the session scratchpad (`scripts/probe.swift`, `scripts/xp.swift`, `scripts/par.swift`). The test audio was macOS text-to-speech (`say`), not microphone audio and not real meeting audio. The numbers below are indicative only.

## Problem framing

- `SpeechTranscriber` and `DictationTranscriber` take a locale at init. Their only initializers are `init(locale:preset:)` and `init(locale:...options...)` ([SDK swiftinterface](#sdk-paths), lines 50–51 and 336–337; [SpeechTranscriber docs](https://developer.apple.com/documentation/speech/speechtranscriber)). WWDC25: "We tell it the locale that we want to transcribe into" ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
- Carbon's question: can Apple frameworks pick that locale for the person (US English by default, French for the author's French Meetings) without a manual picker?

## 1. Does the Speech framework offer spoken language identification?

**Short answer: not as public API.** A language detector exists inside Speech.framework, but it is not public.

### Public API (SDK 26.4 and the live docs for 27)

- I grepped the public Swift interface (`Speech.swiftmodule/arm64e-apple-macos.swiftinterface`, 682 lines) for `languag`, `detect`, `identif`, `confidence` and `alternative`. Language-related hits are only `SFCustomLanguageModelData` (custom vocabulary) and `DictationTranscriber.ContentHint.customizedLanguage`. The only `detect` hit is `SpeechDetector` ([SDK swiftinterface](#sdk-paths)).
- The public modules are `SpeechTranscriber`, `DictationTranscriber`, `SpeechDetector`, `SpeechModule` and `LocaleDependentSpeechModule` (the "Modules" topic of the [Speech framework page](https://developer.apple.com/documentation/speech), as of 2026-10-27).
- `SpeechDetector` does voice activity detection, not language detection. Its result has a single public field, `speechDetected: Bool`, and its options are a `SensitivityLevel` ([SDK swiftinterface](#sdk-paths), lines 256–292; [SpeechDetector](https://developer.apple.com/documentation/speech/speechdetector)).
- `LocaleDependentSpeechModule.selectedLocales` is plural, but it is documented as "the set of asset locales specified by the module's configuration" ([docs](https://developer.apple.com/documentation/speech/localedependentspeechmodule/selectedlocales)). Both transcribers only take one `locale:` at init. On this Mac, `selectedLocales` returned exactly the one locale passed in (`["en_US"]`, `["fr_FR"]`) ([probe](#probes)).
- What's new in Speech for the 27 OS releases: only `AssetInputSequenceProvider`, `CaptureInputSequenceProvider` and `AnalyzerInputConverter` (macOS 27.0). No language identification ([Speech updates](https://developer.apple.com/documentation/updates/speech), [AssetInputSequenceProvider](https://developer.apple.com/documentation/speech/assetinputsequenceprovider)).
- The WWDC25 SpeechAnalyzer session never mentions automatic language identification or switching languages. Transcription is always configured with an explicit locale ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
- The 2026 WWDC session list ([WWDC26 videos](https://developer.apple.com/videos/wwdc2026/)) has no Speech-framework session. The only speech-to-text session is "Discover generated subtitles and subtitle styles" ([WWDC26 session 256](https://developer.apple.com/videos/play/wwdc2026/256/)), a system playback feature with no developer API. In macOS 27 it does English audio only: "English subtitles can be generated from English audio."
- `SFSpeechRecognizer`: "Each speech recognizer supports only one language, which you specify at creation time" ([SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)).
- Developer Forums: I found no Apple-engineer answer offering language identification. Threads under the [speech tag](https://developer.apple.com/forums/tags/speech) and [thread 790108](https://developer.apple.com/forums/thread/790108) cover locale support and model download problems. **Unverified** that no such answer exists; I only saw search snippets.

### Non-public: `LanguageDetector` exists in Speech.framework

- The SDK's link stub `Speech.framework/Versions/A/Speech.tbd` exports Swift symbols that demangle to a full module: `LanguageDetector.init(options:clientInfo:)`, `LanguageDetector.results`, `LanguageDetector.Result.dominantLocale`, `.alternatives`, `.detectedLanguageCode`, `LanguageDetector.LocaleAlternative.locale` / `.confidence`, `LanguageDetectorOptions.init(languageConstraints:alternativeCount:resultReportingFrequency:useVAD:)`, and `LanguageDetectorResultReportingFrequency` with cases `.once`, `.everySecond` and `.continuous`. It also exports ObjC symbols `SFLanguageDetectorResult`, `SFSpeechAnalyzerLanguageDetectorOptions` and `_SFEntitledAssetConfigForLanguageDetector` (demangled with `swift-demangle` from the [SDK .tbd](#sdk-paths)).
- `dlsym` finds `$s6Speech16LanguageDetectorCMa` (its type-metadata accessor) in the running macOS 27.0.1 Speech.framework ([probe](#probes)).
- **It is not in the public `.swiftinterface`.** It is SPI, so a normal `import Speech` cannot see it. Using it would mean private API, which is grounds for App Store rejection ([App Review Guidelines 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)). The `clientInfo:` parameter and the "EntitledAssetConfig" symbol suggest it is gated behind an entitlement (**unverified**).
- Opinion: this is the API Carbon wants, and its shape (language constraints, per-second reporting, confidences) points to Apple using it internally. It may go public in a future release. Watch the Speech "What's new" page each June.

## 2. Other native audio language-ID APIs

- **SoundAnalysis:** the built-in classifier `SNClassifierIdentifier.version1` has 303 labels on this Mac. The only speech-related one is `"speech"`, with no per-language labels ([probe](#probes); [SNClassifySoundRequest](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest)). A custom Core ML model through `SNClassifySoundRequest(mlModel:)` is possible ([same page](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest)), but Apple ships no language-ID model, so Carbon would have to supply one.
- **NaturalLanguage `NLLanguageRecognizer`:** text only. "Automatically detects the language of a piece of text"; it supports `languageHypotheses(withMaximum:)`, `languageHints` and `languageConstraints`; it is "most reliable for longer passages of text" ([NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)).
- **Foundation Models:** the 27 release notes list image input ("including an image in your prompt") but no audio input ([Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)). That it cannot take audio is **unverified** beyond that page. It could classify transcript text, but `NLLanguageRecognizer` already does that more cheaply.
- **Translation:** `TranslationError.unableToIdentifyLanguage` and `LanguageAvailability.status(for text:...)` show the framework identifies the language of text, not audio (`Translation.swiftinterface` in the [SDK](#sdk-paths)).
- **`Locale.preferredLanguages`:** not detection, but a native, zero-UI signal. It holds the person's ordered language list from System Settings and could seed the candidate set (for example `["en-US", "fr-FR"]`) ([Locale.preferredLanguages](https://developer.apple.com/documentation/foundation/locale/preferredlanguages)).

## 3. Workable native fallbacks

### Building blocks (verified)

- **Per-word confidence exists.** `SpeechTranscriber.ResultAttributeOption.transcriptionConfidence` "includes confidence attributes in a transcription's attributed string" ([docs](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/transcriptionconfidence)). `ConfidenceAttribute` is "a confidence level (0–1) of the associated transcription text", typed `Double` ([docs](https://developer.apple.com/documentation/foundation/attributescopes/speechattributes/confidenceattribute); [SDK swiftinterface](#sdk-paths), line 175). `DictationTranscriber` has the same option (line 117). It combines with `.audioTimeRange`, so each confidence can be mapped to a time window.
- **Alternatives exist** (`.alternativeTranscriptions`, "in descending order of likelihood") but are per locale. They do not compare languages ([Result.alternatives](https://developer.apple.com/documentation/speech/speechtranscriber/result/alternatives)).
- **Several transcribers can share one analyzer.** "Modules can be added or removed to the analyzer mid-stream." The limit on concurrent engine instances is "roughly ... two ongoing recognition instances" on iOS/visionOS, but "there is currently no limit on macOS" ([setModules(_:)](https://developer.apple.com/documentation/speech/speechanalyzer/setmodules(_:))). One analyzer handles one input sequence, and Carbon already runs one analyzer per stream ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer); [local-meeting-capture.md](local-meeting-capture.md)).
- **Reserved locales are capped.** `AssetInventory.maximumReservedLocales` is "the largest allowed count of reservedLocales. The value may vary between devices according to storage space" ([docs](https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales)). **It is 5 on this Mac** ([probe](#probes)). `reserve(locale:)` throws "if the number of locales would exceed maximumReservedLocales" ([docs](https://developer.apple.com/documentation/speech/assetinventory/reserve(locale:))). `assetInstallationRequest` reserves automatically when needed ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)). Two locales (en + fr) fit comfortably.
- **Assets download per locale.** "These assets are machine-learning models downloaded from Apple's servers ... shares it with other apps ... The system may unsubscribe your app from assets that haven't been used in a while" ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)). On this Mac, `SpeechTranscriber.installedLocales` held only English variants, while `DictationTranscriber.installedLocales` was `en_GB, en_US, fr_FR` ([probe](#probes)). So **French SpeechTranscriber assets would need a download on first use.** I found no primary source for asset size or download time (**unverified**; I did not download to measure). Download French ahead of time (at onboarding, or when the person adds French), never at Meeting start.
- **Supported locales:** 45 for `SpeechTranscriber` on macOS 27.0.1, including `en_US`, `fr_FR`, `fr_CA`, `fr_BE`, `fr_CH`, and 54 for `DictationTranscriber` ([probe](#probes)). The list also contains `mul_IN`, which looks like a multilingual Indian model. Apple has not documented it, so what it does is **unverified**. No `mul` locale exists for English + French.
- **`supportedLocale(equivalentTo:)` is not detection.** It maps a locale to a supported one that shares the language code, and Apple warns: "your application should ideally still provide a way for the user to correct the locale" ([docs](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocale(equivalentto:))).

### Experiment: confidence vs. text language ID (TTS audio, this Mac)

Clips: about 12 s of French and about 11 s of English, from `say` voices "Eddy (French (France))" and "Eddy (English (US))". Each clip was transcribed from a file by each installed configuration with `.transcriptionConfidence`. Then I ran `NLLanguageRecognizer` (constrained to en/fr) on the output ([probe `xp.swift`](#probes)).

| Audio | Module / locale | Mean word confidence | NL verdict on output | Output excerpt |
|---|---|---|---|---|
| French | SpeechTranscriber en_US | **0.22** | fr 1.00 | "Bonjour, a douce, merci, d'etre la. Bonjour, a douce.." (truncated) |
| French | DictationTranscriber en_US | **0.24** | **en 1.00** (wrong) | "See that you called me please log out I'm about to" |
| French | DictationTranscriber fr_FR | **0.61** | fr 1.00 | "Bonjour à tous merci d'être là aujourd'hui on va faire le point…" |
| English | SpeechTranscriber en_US | **0.90** | en 1.00 | "Hi everyone. Thanks for joining. Today we will review…" |
| English | DictationTranscriber en_US | **0.79** | en 1.00 | "Hi everyone thank you for joining today…" |
| English | DictationTranscriber fr_FR | **0.18** | **en 1.00** (wrong locale, right language) | "I Everyone Thing For Today and and Real Next Thing…" |

Wall time per run, file input on an Apple Silicon Mac: 0.19–1.6 s for about 12 s of audio, model warm-up included.

Findings:

- **The hallucination pitfall is real.** The en_US model given French audio produced fluent-looking *English* ("See that you called me please log out"), and `NLLanguageRecognizer` scored it **English 1.00**. So "transcribe with the system locale, then run NL on the text" can confidently confirm the wrong language. It only works by luck when the model echoes the foreign phonetics (the SpeechTranscriber row).
- **Confidence separates them well.** The matching locale scored 0.61–0.90 and the mismatched one 0.18–0.24. The wrong locale also emits fewer words (French audio: 11 words with en_US vs. 35 with fr_FR).
- **Two locales in one analyzer, mixed clip** (EN 0–11 s, FR 11–23 s, EN 23–34 s; `par.swift`, DictationTranscriber en_US + fr_FR, binned by `audioTimeRange` into 5 s windows): en won 0–5 s (0.64 vs 0.26), 5–10 s (0.80 vs 0.22), 25–30 s and 30–35 s; fr won 10–15 s (0.58 vs 0.52) and 15–20 s (0.56 vs 0.24). The 20–25 s window, which held the switch, was a near-tie (0.50 vs 0.53). The whole 34 s ran in about 4–6 s.
- Caveats: this is TTS, a single voice, clean audio, with DictationTranscriber standing in for French because French SpeechTranscriber assets were not installed. Real VoIP audio, accents and code-switching will narrow the gap. The thresholds need calibrating on real Meetings (**unverified** for SpeechTranscriber fr_FR and for real audio).

### Fallback options compared

| Option | How | Latency | Cost / risk |
|---|---|---|---|
| A. Parallel race, then commit | Run en_US and fr_FR transcribers in the same analyzer for the first ~20–30 s of speech (gate on `SpeechDetector`). Pick the locale with the higher mean confidence (plus word count), then `setModules` to drop the loser. | Decision after ~20–30 s of speech. No audio lost: both transcripts exist from t=0, so keep the winner's. | 2x compute during the window. French assets must be installed. Can mis-pick on short or noisy openings. |
| B. Parallel for the whole Meeting | Keep both transcribers running. Per segment or window, keep the higher-confidence text. | None | 2x compute for the whole Meeting. Segment boundaries from the two models don't line up, so merging is fiddly. Near-ties at switch points. Handles code-switching, partly. |
| C. System locale, then NL on the text | Transcribe with `Locale.current`, run `NLLanguageRecognizer` on the text. | Low | **Unreliable**: the wrong-locale model hallucinates text in its own language (see the table). Use it only as a secondary signal. |
| D. Text hints before the Meeting | Run `NLLanguageRecognizer` on the calendar event title and description, or remember the language used in past Meetings with the same participants. | Zero | Only a prior. Titles are short, and NL is weak on short text ([NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)). |
| E. Private `LanguageDetector` | SPI | n/a | Private API: rejection and breakage risk. Not viable. |

## 4. Mid-meeting language switches

- **No locale property can be changed on a transcriber.** The public interface has no locale setter, and `selectedLocales` is get-only ([SDK swiftinterface](#sdk-paths), lines 138 and 409).
- **The analyzer does not need restarting, though.** `setModules(_:)` adds or removes modules mid-stream: "A newly-added module will immediately begin analysis on new audio input, but it will not have access to already-analyzed audio. However, you may keep a copy of previously-analyzed audio and provide it to a separate analyzer." Also: "Modules cannot be reused from a different analyzer" ([setModules(_:)](https://developer.apple.com/documentation/speech/speechanalyzer/setmodules(_:))).
- So a switch means creating a new `SpeechTranscriber(locale:)` and calling `setModules` with it in place of (or next to) the old one. The new module only sees audio from that moment on. To re-transcribe audio from before the switch, Carbon must buffer it and feed it to a second analyzer.
- Detecting the switch natively means option B: keep both locales live and watch for confidence crossing over. A single-locale pipeline gives no signal other than falling confidence. Opinion: falling confidence alone can't tell "switched language" from "bad audio".
- **Prewarming:** `prepareToAnalyze(in:)` "may improve how quickly the modules return their first results", and `ModelRetention` (`whileInUse`, `lingering`, `processLifetime`) keeps models loaded between analyzers ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer); [ModelRetention](https://developer.apple.com/documentation/speech/speechanalyzer/options/modelretention-swift.enum)). How long a cold locale swap takes is **unverified**. Granola reports "a brief pause in transcription while the new transcription model loads" for its own (non-Apple) stack ([Granola docs](https://docs.granola.ai/help-center/customising-granola/multi-language)).

## 5. Competitors (from their own docs)

- **Granola:** on desktop, Settings > Preferences > Language offers English, or "Multi-language" that "seamlessly transcribes all the desktop languages" and lets you switch during a Meeting. On iOS/Android, Multi-language is on by default: it "will analyze the transcript and choose a single language to transcribe in", so "stick to one language per meeting." You can change language mid-meeting in the controls ("brief pause ... while the new transcription model loads"). Language "can't be changed" after transcription. 31 languages on desktop, 17 on mobile, from a third-party "transcription provider" ([Granola multi-language](https://docs.granola.ai/help-center/customising-granola/multi-language)).
- **MacWhisper:** "Select transcription language (or use auto detect)" ([MacWhisper docs](https://docs.macwhisper.com/article/33-macwhisper-for-ios)). Its auto-detect comes from Whisper, whose README shows `detect_language` run on a 30 s padded/trimmed window (`pad_or_trim`) ([openai/whisper README](https://github.com/openai/whisper)). That MacWhisper samples only the first 30 s is **unverified** from MacWhisper's own docs.
- **Notion AI Meeting Notes:** lists 16 supported transcription languages, French and English included, and says "Speaker labeling is currently available in English only." It does not say how the language is chosen or detected ([Notion help](https://www.notion.com/help/ai-meeting-notes)). **Unverified** whether it auto-detects.
- **Superwhisper:** has an "Automatic" language mode, but warns that with it "non-English dictation sometimes comes out as English text" because the model "sometimes defaults to English". "The most reliable fix: edit the mode and set its Language to your language instead of Automatic". It recommends Automatic "only when you mix languages inside a single dictation" ([Superwhisper docs](https://superwhisper.com/docs/common-issues/language-detection)). This is the same English-bias failure seen in the experiment above.
- None of the four documents an Apple-native detector. Granola and MacWhisper rely on their model vendors' multilingual models.

## Recommendation (opinion)

1. **Don't promise automatic detection from Apple APIs.** No public one exists. The private `LanguageDetector` shows Apple has one, so recheck every June.
2. **Default to zero setup for the US market.** The Meeting language is `SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)`. A US person never sees a language picker.
3. **Offer a "Meeting languages" setting** with up to two locales, pre-filled from `Locale.preferredLanguages` (the author's Mac would offer English + French). Download each locale's assets when it is added, never at Meeting start. Two locales are well under `maximumReservedLocales` (5 here).
4. **With two languages configured, use option A (parallel race, then commit).** Attach both transcribers to each stream's analyzer. After about 20–30 s of detected speech, compare mean `transcriptionConfidence` and word count per locale. Keep the winner's transcript from t=0 and `setModules` the loser away. If the result is a near-tie, keep both running a little longer. Show the chosen language on the Meeting with a one-click "Re-transcribe in French", which re-runs the saved audio offline. Never rely on `NLLanguageRecognizer` alone (option C).
5. **Treat mid-meeting switching as phase 2.** Option B (both locales for the whole Meeting, keeping the higher-confidence window) is feasible on macOS, where there is no engine limit, but it doubles compute and needs careful merging. Ship it only after calibrating on real bilingual Meetings. The "Me" stream could even pick its language separately from "Them".
6. **Before building, run the experiment on real audio.** Record about 10 real Meetings (EN, FR, mixed) and measure SpeechTranscriber en_US vs fr_FR confidence gaps per window to set the thresholds. The TTS numbers above only show that the signal exists.

## Appendix

### SDK paths

- Public Speech Swift interface: `/Applications/Xcode-26.4.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface` (module version 3520.77.1, target macOS 26.4).
- Speech link stub with the `LanguageDetector` exports: `.../Speech.framework/Versions/A/Speech.tbd` (same SDK).
- Translation interface: `.../Translation.framework/Versions/A/Modules/Translation.swiftmodule/arm64e-apple-macos.swiftinterface`.

### Probes

Run on macOS 27.0.1 (26A434) with `xcrun swiftc` from Xcode 26.4. No microphone was used.

- `probe.swift`: `maximumReservedLocales` = 5. `reservedLocales` = []. `SpeechTranscriber.isAvailable` = true. 45 SpeechTranscriber supported locales, of which only `en_*` were installed. 54 DictationTranscriber supported locales, with `en_GB, en_US, fr_FR` installed. `AssetInventory.status` = `.supported` for both en_US and fr_FR SpeechTranscriber configs. 303 SoundAnalysis labels, only `speech` speech-related.
- `xp.swift`: the confidence and NL table in section 3.
- `par.swift`: two DictationTranscribers in one `SpeechAnalyzer` over a 34 s EN/FR/EN clip, with confidence binned per 5 s.
- `dl.c`: `dlsym` of `$s6Speech16LanguageDetectorCMa` in `/System/Library/Frameworks/Speech.framework/Speech` returns non-NULL.
