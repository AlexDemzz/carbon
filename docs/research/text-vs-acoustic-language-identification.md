# Text (lexical) vs acoustic language identification for switching the transcription locale

Researched 2026-10-31. The question: Carbon picks one `SpeechTranscriber` locale per Meeting. To switch it, Carbon has to tell which of the person's checked languages is being spoken. Today an acoustic classifier does that (Silero VAD gate, then SpeechBrain VoxLingua107 ECAPA on 4 s windows, voting among the checked languages; a switch re-transcribes the Meeting from the start). Could language identification on the **text** the running transcriber already produces (`NLLanguageRecognizer` on its output) **replace** the acoustic classifier, or only **complement** it? How do production and open-source systems choose and switch the ASR language mid-stream?

This builds on earlier notes and does not redo them:

- [language-detection.md](language-detection.md): Apple has no public spoken LID. It includes the TTS experiment where a wrong-locale model produced fluent English that `NLLanguageRecognizer` scored English 1.00, and the confidence race.
- [offline-spoken-language-identification.md](offline-spoken-language-identification.md): why VoxLingua107 ECAPA, and what Whisper `detect_language` costs.
- [language-identification-thresholds.md](language-identification-thresholds.md): how other projects threshold, aggregate and fuse acoustic LID, and the accent literature (Bafna & Wiesner 2025, speechbrain#2826).
- [multilingual-meeting-transcription.md](multilingual-meeting-transcription.md): what the French model does with English (it drops whole English turns, "Thanks a neww"), and the "words per second" idea.
- [competitor-meeting-language-handling.md](competitor-meeting-language-handling.md): how meeting apps choose a language, the Whisper engines (§9), and recommendation 9: "text-based dominant-language checks only work on text from a multilingual engine".
- [ADR 0005](../adr/0005-identify-the-meeting-language-with-a-bundled-classifier.md): the bundled acoustic classifier, decided once per Meeting.

Method: vendor documentation pages (fetched 2026-10-31), source code at the pinned commits below, the papers' own text (arXiv PDF or HTML), Apple's DocC JSON, plus Carbon's own measurements listed in §4. Nothing new was built or run for this note. Anything I concluded myself is marked **(inference)**. Anything I could not settle is marked **(unverified)**.

## Sources and pins

| Source | Pin / version | What it is |
|---|---|---|
| Gladia realtime router | [gladiaio/realtime-multilingual-asr-router@4e25d64](https://github.com/gladiaio/realtime-multilingual-asr-router/tree/4e25d6489624db46dca627a59c35ad0222c2636b) | Live router between monolingual Zipformers, acoustic LID + rollback |
| Kesha voice kit | [drakulavich/kesha-voice-kit@a43364e](https://github.com/drakulavich/kesha-voice-kit/tree/a43364e7853a62d8515daa3f6cda15fbfe75de43) | Parakeet CLI; `NLLanguageRecognizer` on the transcript plus VoxLingua107 |
| lingua-py | [pemistahl/lingua-py@754ce21](https://github.com/pemistahl/lingua-py/tree/754ce21122c083a7200763015fdaf7cda8d85453) | Text LID library that publishes accuracy by text length against CLD2, CLD3, langdetect, langid |
| CLD3 | [google/cld3@b48dc46](https://github.com/google/cld3/tree/b48dc46512566f5a2d41118c8c1116c4f96dc661) | Google's neural text LID |
| fastText lid.176 | [fasttext.cc language identification](https://fasttext.cc/docs/en/language-identification.html) | 176-language text LID |
| Apple NaturalLanguage | [`NLLanguageRecognizer`](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer) (DocC, fetched 2026-10-31) | The text LID Carbon would use |
| Azure AI Speech | [Language identification](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-identification) (doc source [@98579c2](https://github.com/MicrosoftDocs/azure-ai-docs-pr/blob/98579c26ac9020d58df56fbf9920763b49bf959f/articles/ai-services/speech-service/language-identification.md), updated 2026-08-10) | At-start and continuous LID |
| Amazon Transcribe | [Streaming language identification](https://docs.aws.amazon.com/transcribe/latest/dg/lang-id-stream.html) | Single- and multi-language streaming LID |
| Google Cloud STT | [V1 `RecognitionConfig`](https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v1/RecognitionConfig), [V2 multiple languages](https://docs.cloud.google.com/speech-to-text/docs/multiple-languages) | `alternativeLanguageCodes` / `language_codes` |
| Deepgram | [Language detection](https://developers.deepgram.com/docs/language-detection) | Batch-only detection |
| AssemblyAI | [Automatic language detection](https://www.assemblyai.com/docs/speech-to-text/pre-recorded-audio/automatic-language-detection) | Whisper-based LID, with the accent caveat |
| Microsoft Teams | [Use live captions in Teams meetings](https://support.microsoft.com/en-US/teams/meetings/use-live-captions-in-microsoft-teams-meetings) | Spoken-language mismatch prompt |
| Zoom | [Zoom blog, 2025-07-14](https://www.zoom.com/en/blog/ai-accessible-meetings-captions/) | Caption language switching claim |
| Papers | Kukk & Alumäe, Interspeech 2022 ([arXiv 2203.16972](https://arxiv.org/abs/2203.16972)); Wang et al. 2019 ([arXiv 1910.09687](https://arxiv.org/abs/1910.09687)); Chandak et al. 2020 ([arXiv 2006.00703](https://arxiv.org/abs/2006.00703)); Gitman et al. 2023 ([arXiv 2306.15824](https://arxiv.org/abs/2306.15824)); Peng et al., OWSM v4, Interspeech 2025 ([arXiv 2506.00338](https://arxiv.org/abs/2506.00338)) | ASR hypotheses and confidences as LID signals |

Not re-read here: the Whisper family (openai/whisper, faster-whisper, WhisperX, whisper.cpp, WhisperKit). Their detection windows, thresholds and fallbacks are in [competitor-meeting-language-handling.md §9](competitor-meeting-language-handling.md#9-what-the-engines-do) and [language-identification-thresholds.md](language-identification-thresholds.md), with pinned links. Apple's Speech framework still has no public LID ([language-detection.md §1](language-detection.md)).

## Summary

**Short answer.**

- **In the literature and in production, text-based signals from the recognizer complement acoustic LID. None of the sources here replaces it.** Google's multilingual recognizer feeds parallel recognizers' confidence, LM cost, N-best spread *and* a text LangID score into a model with the acoustic LangID score. That cut ID error from 5.5% to 4.3% ([Wang et al. 2019](https://arxiv.org/abs/1910.09687)). Amazon reports up to 50% relative error reduction from adding ASR-hypothesis embeddings to acoustic features ([Chandak et al. 2020](https://arxiv.org/abs/2006.00703)). Kukk & Alumäe show that a text classifier on the ASR output **beats** the acoustic model on accented speech, while the acoustic model wins on native speech, and the fusion beats both ([arXiv 2203.16972](https://arxiv.org/abs/2203.16972), Table 2).
- **Carbon's case is narrower than theirs, and that narrowness is what makes replacement plausible (inference).** Carbon has two to three candidates, a transcriber for every candidate, and a switch that re-transcribes from the recorded file. It can therefore *verify* a candidate lexically by running that locale's own transcriber on the buffered audio. None of the papers had that option cheaply.
- **Carbon's own numbers point the same way.** On the maintainer's French-accented English, the acoustic vote never decided. Text LID on the *French* model's transcript of the same speech said English (5 of 6 ten-word chunks above 0.99). On two French Meetings full of franglais, it said French at every length.
- **One failure needs a guard that is not text LID: the wrong model emitting almost nothing.** The English model on a French Meeting produced 4 words in 3 minutes ("What? Uh, okay. Okay."), which `NLLanguageRecognizer` scored English 1.00. A **words-per-second-of-speech** check catches it, and the Silero gate already supplies the denominator.
- **Bottom line (inference).** For two checked languages, lexical LID plus a word-rate guard plus a confirming re-transcription in the candidate locale can replace the ECAPA vote as the *decider*. Silero VAD stays: it is the word-rate denominator. The acoustic model's remaining job, if kept at all, is to **rank** candidates when there are three or more and the current model has gone quiet. Lexical evidence can say "this is not my language" but cannot say which other one it is. Treat it as optional.

| System | Signal that picks the language | Text / ASR-output signal used? | Mid-stream switching | Min. audio | Low-confidence behaviour |
|---|---|---|---|---|---|
| **Carbon today** | VoxLingua107 ECAPA, vote over 4 s windows | No | Once per Meeting (re-transcribe all) | 8 s of speech | Keep the default; give up at 60 s / 40 windows |
| Whisper family | Decoder language token on a 30 s window | Implicitly (the decoder is a language model) | Per 30 s window only in faster-whisper `multilingual=True` | 30 s (padded) | faster-whisper: 0.5 threshold, then majority vote |
| Gladia router | VoxLingua107, expanding 1/2/3/5 s windows after each VAD pause | **No** | Yes: swap model, roll back to the segment, re-infer buffered audio | 1 s window | Below 0.95 after confirmation: ignored |
| Azure AI Speech | Undocumented model over up to 4 (at-start) / 10 (continuous) candidates | Undocumented **(unverified)** | Continuous mode, not within a sentence | At-start: decides "in less than 5 seconds" | Returns `Unknown` / always one of the candidates |
| Amazon Transcribe streaming | Undocumented | Undocumented **(unverified)** | `identify-multiple-languages` | "minimum of one second of speech" | Picks "the closest language match" from the options |
| Google STT | V1 `alternativeLanguageCodes` (≤ 3 extra), V2 `language_codes` (≤ 3) | Paper: yes, `text_langid_score` + recognizer costs | Not documented | — | "most likely language"; V1 only for "Voice Command and Voice Search" |
| Deepgram | `detect_language` (batch only) | — | Streaming: use the `multi` code-switching model | — | `language_confidence` reported |
| AssemblyAI | "Whisper-based language identification" | No | — | "at least 15–90 seconds" recommended | `language_confidence_threshold` → error; `fallback_language` |
| Microsoft Teams | Undocumented mismatch detector | **(unverified)** | **Prompts** the organizer "Yes, change it"; no silent switch | — | — |
| Zoom (6.5.0+) | "improved speech AI", undocumented | **(unverified)** | Claims to follow switches for captions | — | — |
| Kesha | `NLLanguageRecognizer` on a **multilingual** (language-agnostic) ASR's transcript; audio LID as fallback or override | **Yes, text first** | n/a (files) | First 10 s for audio | Audio ≥ 0.95 in a non-ASR language overrides the text |
| ESPnet OWSM v4 (data cleaning) | fastText on text **and** VoxLingua107 on audio | **Yes: both must agree** with the label | n/a | Per utterance | Drop the utterance |

## Findings by topic

### 1. How production systems choose and switch the ASR language

**Gladia's open router is acoustic only, with rollback.**

- The README lays out the pipeline: "Active monolingual ASR transcribes in real time". Then "After each VAD boundary, LID runs on expanding windows in the background". Then "On a confident language switch, swap ASR model, roll the transcript back to the segment boundary, and re-infer buffered audio" ([README.md#L118-L124](https://github.com/gladiaio/realtime-multilingual-asr-router/blob/4e25d6489624db46dca627a59c35ad0222c2636b/README.md#L118-L124)).
- The switch rule looks only at the LID event: the language must be a candidate, the event must belong to the current segment, it must be ≥ 0.95 once a language is confirmed, it must differ from the current language, and the segment must not have switched already ([language_switch.py#L36-L64](https://github.com/gladiaio/realtime-multilingual-asr-router/blob/4e25d6489624db46dca627a59c35ad0222c2636b/src/realtime_multilingual_asr_router/coordinator/language_switch.py#L36-L64)). The ASR's text and confidence play no part.
- It works between utterances (about 13% WER on synthetic FLEURS code-switching, on par with Deepgram and ElevenLabs). Its stated limit: "Mid-sentence mixing (Spanglish, etc.) outpaces VAD boundaries; rollback rarely fires" ([README.md#L140](https://github.com/gladiaio/realtime-multilingual-asr-router/blob/4e25d6489624db46dca627a59c35ad0222c2636b/README.md#L140), [#L165](https://github.com/gladiaio/realtime-multilingual-asr-router/blob/4e25d6489624db46dca627a59c35ad0222c2636b/README.md#L165)).
- This is the design closest to Carbon's: monolingual models, acoustic LID, replay of buffered audio. Its 0.95 is applied per window, after the first decision, with no threshold on the first decision ([language-identification-thresholds.md](language-identification-thresholds.md)).

**Azure AI Speech: candidate list, at-start or continuous.**

- "You can include up to four languages for at-start LID or up to 10 languages for continuous LID. The Speech service returns one of the candidate languages provided even if those languages weren't in the audio" ([Azure LID](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-identification), "Candidate languages").
- "With at-start LID, a single language is detected and returned in less than 5 seconds." "Continuous LID doesn't support changing languages within the same sentence" (same page, "At-start and Continuous language identification").
- "For speech recognition, the initial latency is higher with language identification." The sample treats `Unknown` as "Speech Language could not be detected" (same page).
- Whether Azure's LID is acoustic, uses the recognizer's text, or both is not documented **(unverified)**.

**Amazon Transcribe streaming: closed set, ≥ 1 s.**

- "Amazon Transcribe requires a minimum of one second of speech to identify the language." It needs at least two language options, one dialect per language, and an optional preferred language that "can speed up the language identification process" ([AWS](https://docs.aws.amazon.com/transcribe/latest/dg/lang-id-stream.html)).
- "If none of the language codes you provide match the language … Amazon Transcribe selects the closest language match from your specified language codes." So it is a closed set, like Carbon's restricted vote.
- `identify-multiple-languages`: "if speakers change languages mid-conversation … your transcription output detects and transcribes each language correctly". With single-language identification, "any spoken language that is not the dominant language is transcribed incorrectly" (same page).
- With two channels, it identifies a language per channel (`ChannelIdentification`). That is the same idea as a language per Carbon stream (same page).

**Google Cloud STT: alternative languages, and what the paper says sits behind them.**

- V1 `alternativeLanguageCodes`: "up to 3 additional BCP-47 language tags … recognition result will contain recognition in the most likely language detected including the main languageCode". "Note: This feature is only supported for Voice Command and Voice Search use cases and performance may vary for other use cases (e.g., phone call transcription)" ([RecognitionConfig](https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v1/RecognitionConfig)).
- V2 `language_codes`: it uses "the best-fit language from the list", with "up to three languages". It is "ideal for apps that need to transcribe short statements like voice commands or search", and Google says to "constrain the language list to the bare minimum" ([multiple languages](https://docs.cloud.google.com/speech-to-text/docs/multiple-languages)).
- **How the choice is made** comes from Google's own paper on its "multilingual speech recognition system". Users "select two, or more, languages" and **parallel recognizers** run next to an acoustic LangID ([Wang et al. 2019](https://arxiv.org/abs/1910.09687)). The per-language signals are:
  - `langid_score` (acoustic);
  - the recognizer's `am_cost`, `lm_cost` and `confidence_score`;
  - `entropy_score` (Levenshtein spread of the 5-best);
  - **`text_langid_score`, "language ID score based on the recognized text"** (Table 1).
- Results: the acoustic-only baseline's 5.5% error fell to 4.3% with a DNN. On utterances where both recognizers produced features, error fell from 4.2% to 2.0%. In the live system, ID error fell from 4.0% to 3.3% and WER from 13.6% to 12.8% (Tables 2–3).
- The paper gives **no ablation of text LID alone or recognizer features alone**. Whether the public API still works this way is **(unverified)**.

**Deepgram, AssemblyAI.**

- Deepgram: "Language Detection is not currently supported for streaming." Batch detection can be restricted (`detect_language=en&detect_language=es`) and reports `language_confidence`. For streaming it points to the multilingual (code-switching) models ([Deepgram](https://developers.deepgram.com/docs/language-detection)). Anarlog and Screenpipe found the same in code ([competitor note §1, §3](competitor-meeting-language-handling.md)).
- AssemblyAI: "Automatic Language Detection uses Whisper-based language identification, which can sometimes misidentify heavily accented speech as a different language. For example, English spoken with a strong accent may be detected as Finnish, Latvian, Latin, or Arabic." It recommends "at least 15–90 seconds of spoken audio". Its remedies: constrain with `expected_languages` ("most effective"), set a `fallback_language`, and set a confidence threshold, which "catches some misdetections but not confident mistakes" ([AssemblyAI](https://www.assemblyai.com/docs/speech-to-text/pre-recorded-audio/automatic-language-detection), Troubleshooting).
- This is a vendor confirming, in its own docs, the accent failure Carbon measured with ECAPA.

**Microsoft Teams and Zoom.**

- Teams: "If people are speaking a different language than the meeting's set spoken language, Teams will detect the language mismatch". The organizer, co-organizer or transcript initiator "will be prompted to update the spoken language", with "Settings" or "Yes, change it" ([Teams live captions](https://support.microsoft.com/en-US/teams/meetings/use-live-captions-in-microsoft-teams-meetings)). The detector is undocumented **(unverified)**. **The UX is a prompt, not a silent switch.**
- Zoom says its captions can "detect when speakers switch between supported languages — like jumping from English to German" (6.5.0, [Zoom blog, 2025-07-14](https://www.zoom.com/en/blog/ai-accessible-meetings-captions/)). There are no technical details.

**Whisper family** (from the earlier notes, not re-read): one language token per 30 s window, decided by the decoder. The decoder is a language model, so Whisper's LID is not purely acoustic **(inference)**. Yet OpenAI still called it phonetics-driven on accents ("might be focusing too much on the phonetics", [openai/whisper#475](https://github.com/openai/whisper/discussions/475), quoted in [language-identification-thresholds.md](language-identification-thresholds.md)). Per-short-chunk detection was the main source of competitor bugs ([competitor note](competitor-meeting-language-handling.md), pattern 3).

### 2. Text LID on ASR output: what it can and cannot do

**What `NLLanguageRecognizer` documents** ([NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)):

- It identifies the dominant script first, then the language.
- "Language identification is most reliable for longer passages of text. For very short inputs of only a few words, accuracy is lower, and for some text there may be no well-defined answer at all. For example, personal names are shared across languages and don't belong definitively to any one of them."
- "When you work with short or ambiguous text, inspect the full set of candidates with `languageHypotheses(withMaximum:)` rather than relying on a single `dominantLanguage`."
- "When you have prior knowledge … bias the recognizer toward them with `languageHints`, or limit it to a known set with `languageConstraints`."
- "Don't use an instance … from more than one thread simultaneously."
- Apple gives no minimum length, no accuracy figure, and no word- or segment-level output.

**Accuracy vs length, from the one source that publishes it** (lingua-py's bundled reports: Leipzig Wortschatz test sets, 1,000 items each, **75-language open set**; [README §5](https://github.com/pemistahl/lingua-py/blob/754ce21122c083a7200763015fdaf7cda8d85453/README.md#L181-L210); values from the [accuracy-reports CSVs](https://github.com/pemistahl/lingua-py/tree/754ce21122c083a7200763015fdaf7cda8d85453/accuracy-reports)):

| Input | Lang | CLD2 | CLD3 | langdetect | langid | Lingua (high) |
|---|---|---|---|---|---|---|
| Single word (≥ 5 chars) | en | 11.9% | 21.9% | 23.2% | 83.7% | 54.5% |
| | fr | 12.2% | 21.7% | 48.0% | 41.8% | 73.7% |
| Word pair (≥ 10 chars) | en | 55.0% | 43.6% | 59.2% | 70.9% | 88.5% |
| | fr | 47.6% | 49.4% | 77.9% | 73.7% | 94.3% |
| Sentence (~110 chars) | en | 99.8% | 97.4% | 99.3% | 99.2% | 99.3% |
| | fr | 79.5% | 94.0% | 98.8% | 98.4% | 99.2% |

- Over 75 languages, one or two words are unreliable for every library, and a sentence is reliable for nearly all of them. A two-way en/fr decision with `languageConstraints` is much easier than a 75-way one, so these figures are a lower bound for Carbon **(inference)**. Carbon's measurement (§4) shows the constrained recognizer already at 0.97 on 5 words of clean ASR text.
- Lingua's README explains why short text fails: "The shorter the input text is, the less n-grams are available. The probabilities estimated from such few n-grams are not reliable." It also says: "it is always a good idea to restrict the set of languages" ([README §7](https://github.com/pemistahl/lingua-py/blob/754ce21122c083a7200763015fdaf7cda8d85453/README.md#L314-L346)).
- **CLD3 refuses to judge short text by default.** `kMinNumBytesToConsider = 140`, and a result counts as `is_reliable` only at probability ≥ 0.7. That threshold "was optimized on a set of text segments extracted from wikipedia" ([nnet_language_identifier.cc#L95-L101](https://github.com/google/cld3/blob/b48dc46512566f5a2d41118c8c1116c4f96dc661/src/nnet_language_identifier.cc#L95-L101), [.h#L100-L118](https://github.com/google/cld3/blob/b48dc46512566f5a2d41118c8c1116c4f96dc661/src/nnet_language_identifier.h#L100-L118)). 140 bytes is roughly 25 English words **(inference)**.
- **fastText lid.176** documents 176 languages, 126 MB (`.bin`) or 917 kB (`.ftz`), trained on Wikipedia, Tatoeba and SETimes, under CC BY-SA 3.0. It publishes **no accuracy-vs-length figure** ([fasttext.cc](https://fasttext.cc/docs/en/language-identification.html)). Nothing suggests it would beat `NLLanguageRecognizer` for en/fr inside Carbon, and the share-alike licence would complicate bundling **(inference)**.
- **Scores are not comparable across detectors.** Kesha found that "the same correct detection reads ~0.98 from the engine [`NLLanguageRecognizer`] and ~0.2 from `tinyld`" ([SKILL.md#L139](https://github.com/drakulavich/kesha-voice-kit/blob/a43364e7853a62d8515daa3f6cda15fbfe75de43/SKILL.md#L139), [CHANGELOG.md#L28](https://github.com/drakulavich/kesha-voice-kit/blob/a43364e7853a62d8515daa3f6cda15fbfe75de43/CHANGELOG.md#L28)). Carbon's thresholds must be set on `NLLanguageRecognizer`'s own output.

**Failure modes of text LID on a single-locale ASR's output** (sources plus Carbon's probes):

1. **The wrong model writes its own language.** DictationTranscriber `en_US` on French TTS wrote "See that you called me please log out", and `NLLanguageRecognizer` scored it English 1.00 ([language-detection.md §3](language-detection.md)). This is the core reason earlier notes said "never rely on NL alone". Whisper's equivalent is translation into the forced language ([multilingual note §2](multilingual-meeting-transcription.md)). SpeechTranscriber has no translate task, but its language model still pulls output toward real words of its locale **(inference)**.
2. **The wrong model writes (almost) nothing.** `fr_FR` dropped a whole English turn to "Thanks a neww" ([multilingual note §1](multilingual-meeting-transcription.md)). `en_US` on a real French Meeting wrote 4 words in 3 minutes (§4). Text LID on 4 filler words is meaningless but confident ("en 1.00"). **A text-only detector cannot see this. The signal is the word rate.**
3. **The wrong model writes phonetic gibberish in its own script.** `en_US` SpeechTranscriber on French gave "Bonjour, a douce, merci, d'etre la". NL scored it French 1.00, which is right but by luck ([language-detection.md §3](language-detection.md)). This is the helpful case, and the one Kukk & Alumäe exploit on purpose (below).
4. **Short output.** Covered above: one or two words are a coin toss in the open set.
5. **Code-switching and loanwords.** French tech Meetings carry English jargon. The French model keeps the loanwords it knows: "build", "CI", "Daily Standup" ([multilingual note §1](multilingual-meeting-transcription.md)). On Carbon's two franglais Meetings this never tipped the constrained recognizer: English share 0.00 at every N and every chunk (§4). Azure and Gladia both state that within-sentence switches are out of scope for their LID too.
6. **Named entities.** Apple's own example: "personal names are shared across languages". A chunk dominated by names, product names or acronyms carries little language evidence **(inference)**.

**Using the target-language ASR's own output as an LID feature is an established technique, and it is the one that fixes accents.**

- Kukk & Alumäe (Interspeech 2022) run **monolingual**, lexicon-free (character CTC) English and Estonian recognizers. They train a character 4-gram Naive Bayes classifier on the transcripts these produce for *all* 107 VoxLingua107 languages. The classifier learns what the English model writes when it hears Estonian, and so on (§2.3.3). They note the lexicon-free output is "not constrained to in-vocabulary words, resulting in very expressive character ASR-transcripts for languages other than the ASR target language" ([arXiv 2203.16972](https://arxiv.org/abs/2203.16972)).
- Table 2, accuracy (acoustic XLS-R vs text on the English ASR vs fused):

  | Test set | Acoustic (B) | NB on en-ASR text (D) | Fusion (I) |
  |---|---|---|---|
  | L2 Arctic (non-native English) | 74.6 | **79.8** | 90.5 |
  | CSLU FAE (non-native English) | 79.5 | **84.7** | 88.2 |
  | CMU Arctic (native English) | 87.6 | 83.8 | 95.5 |
  | VoxLingua107 dev (33 languages, native) | **95.3** | 54.6 | 95.3 |

- Their reading: "having the target language ASR transcripts available is more helpful for LID than other ASR transcripts". The Estonian-ASR text model reaches 71% on native Estonian but "only 20% when using English ASR transcripts". Also: "on native speech, acoustic representations result in much higher accuracy than the ASR-based features", so fusion weights tuned on native data collapse to acoustic-only (§3).
- Takeaway for Carbon **(inference)**:
  - On accented speech, lexical evidence from the target-language recognizer beats the acoustic model. That matches Carbon's maintainer recording.
  - The weak text results in that paper come from the 107-way open set, and from transcripts by a recognizer for a *different* language than the speech.
  - Carbon's problem is 2-way, and Carbon can always obtain the target-language transcript by re-transcribing in that locale.
  - One difference cuts the other way. Apple's transcriber is word-based with a language model, so its wrong-language output is *less* expressive than their character CTC output (failure modes 1–2). That is why Carbon needs the word-rate guard and the confirming re-transcription, not text LID alone.

**Confidence of parallel recognizers as the language signal.**

- Gitman et al. (NVIDIA, 2023) pick among monolingual end-to-end models by a per-model entropy confidence plus logistic regression. That gives about 10% relative WER reduction over choosing by LID ([arXiv 2306.15824](https://arxiv.org/abs/2306.15824)). They credit the idea to Metze et al.'s "confidence scores of multiple monolingual HMM-based ASR models" (original not read).
- At 3 s on VoxPopuli, model-selection accuracy was 90.63 for confidence, 93.45 for XLS-R LID, and **96.00 for the two combined**. The confidence ensembles "underperform the best baseline for shorter durations" (Table 3).
- Carbon's TTS probes found matching-locale mean confidence 0.61–0.90 against 0.18–0.24 for the wrong locale. But `fr_FR` on English kept middling confidence (0.62–0.69) on the few words it kept ([language-detection.md §3](language-detection.md), [multilingual note §1](multilingual-meeting-transcription.md)). Carbon does not request `.transcriptionConfidence` today; it only asks for `.audioTimeRange` ([SpeechTranscriberAdapter.swift#L21-L22](../../App/Sources/Adapters/SpeechTranscriberAdapter.swift)).

### 3. Hybrid designs and who runs them

| Who | Acoustic | Lexical / ASR-output | Combination | Cost |
|---|---|---|---|---|
| Google multilingual ASR ([Wang et al.](https://arxiv.org/abs/1910.09687)) | LangID score | Parallel recognizers: AM/LM cost, confidence, N-best spread, **text LangID** | Pairwise DNN | One recognizer per candidate, for the whole utterance |
| Amazon ([Chandak et al.](https://arxiv.org/abs/2006.00703)) | Acoustic representations | Embeddings of ASR hypotheses | Learned; stops early at a confidence level ("1500 ms early identification for more than 50% of utterances") | Parallel monolingual ASRs until the decision |
| Kukk & Alumäe ([2203.16972](https://arxiv.org/abs/2203.16972)) | XLS-R LID | NB on monolingual ASR transcripts | Equal-weight fusion | One ASR per language |
| NVIDIA ([Gitman et al.](https://arxiv.org/abs/2306.15824)) | Optional LID scores | Per-model confidence | Logistic regression | All models run |
| ESPnet OWSM v4 ([Peng et al.](https://arxiv.org/abs/2506.00338) §2.1.2) | VoxLingua107 ECAPA | fastText on the transcript | **Keep only if both match the label.** 345k h → 284k h, 83 → 75 languages (§2.1.1–2.1.2) | Offline |
| Kesha ([language-routing.ts#L37-L75](https://github.com/drakulavich/kesha-voice-kit/blob/a43364e7853a62d8515daa3f6cda15fbfe75de43/src/language-routing.ts#L37-L75)) | VoxLingua107, first 10 s | `NLLanguageRecognizer` on Parakeet's transcript ([README.md#L106](https://github.com/drakulavich/kesha-voice-kit/blob/a43364e7853a62d8515daa3f6cda15fbfe75de43/README.md#L106)) | **Text first.** The engine's (`NLLanguageRecognizer`) result is taken as-is. Audio is used only when there is no text result (or only a `tinyld` fallback below 0.5), or when audio is ≥ 0.95 sure of a language the ASR cannot do (#1463: "zh audio 0.999 vs text 0.63") | One multilingual ASR, so the text is honest |
| Gladia router | VoxLingua107 | — | Acoustic only | One ASR + LID per VAD pause |
| hayamimi, NeMo Curator ([thresholds note](language-identification-thresholds.md)) | Two acoustic/ASR models | — | Agreement | Two models |

Patterns **(inference)**:

1. **Everyone with a text signal also has an acoustic one**, and the published gains are from fusion: 22–52% relative at Google, up to 50% at Amazon, 35–63% on accented speech in Kukk & Alumäe.
2. **The one system that trusts text first (Kesha) gets its text from a language-agnostic recognizer** (Parakeet v3 has no language token). Its text therefore reflects the speech, not a forced locale. Carbon's text comes from a single-locale model, which is why earlier notes rejected text-first. Carbon's new measurements soften that rejection; they do not remove it.
3. **Parallel recognizers are the production way to get lexical evidence for every candidate.** They cost one recognizer per candidate. Carbon can get the same evidence *after the fact and only on demand*, because a candidate locale can be run over the recorded audio. The probe measured two `SpeechTranscriber`s at 0.83 s for 19 s of audio, against 0.48–0.58 s for one ([multilingual note §1](multilingual-meeting-transcription.md)).
4. **Nobody here publishes a word-rate test**, but the closest precedents are crude versions of it. Minute retries in English when a non-English pass returns an empty transcript ([competitor note §5](competitor-meeting-language-handling.md)). Whisper's `no_speech_prob` and `logprob_threshold` skip segments the model cannot decode ([thresholds note](language-identification-thresholds.md)).

### 4. Carbon's own measurements (maintainer, local, 2026-10-30/31)

These are Carbon's own data, measured outside this note on real recordings. They are few: one 40 s recording and three Meetings.

**Acoustic vote on French-accented English** (the maintainer's voice, 40 s, 32 s of speech):

- It ended **fr-FR ahead by 0.4–0.5 log-odds/s**, against a threshold of ln 20 ≈ 3.0. Undecided.
- Top unrestricted labels per window were sw/ps/br/no. `en` won 5 of 8 windows, but one window at −12 log-odds for `en` flipped the sum.
- 8 s and 12 s windows did not decide either.
- This is the accent failure the model card, speechbrain#2826, Bafna & Wiesner 2025 and AssemblyAI's docs all describe ([thresholds note](language-identification-thresholds.md); §1 above).

**`NLLanguageRecognizer` constrained to [en, fr]; English share by the first N words, and by 10-word chunks:**

| Transcriber | Speech | 5 w | 10 w | 20 w | 40 w | 10-word chunks |
|---|---|---|---|---|---|---|
| `fr_FR` | Accented English (same 40 s) | 0.97 | 1.00 | 0.64 | 0.85 | 5 of 6 > 0.99 |
| `en_US` | Accented English | ~1.00 | ~1.00 | ~1.00 | ~1.00 | — |
| `fr_FR` | Two French Meetings with franglais | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 every chunk |
| `en_US` | French Meeting A | **4 words in 3 min**: "What? Uh, okay. Okay." → en 1.00 | | | | |
| `en_US` | French Meeting B | 63 words, French share ≥ 0.94 from 5 words | | | | |

- **Cost:** about 1.5 ms per call, flat from 30 to 500 words.

What these show **(inference)**:

- In the one place the acoustic vote failed, the lexical signal was right from either model's output. The French model, given English, wrote English words, and enough of them (≥ 40 words in 32 s of speech, about 1.25 words/s or more).
- The cumulative share wobbles (0.64 at 20 words) where the per-chunk view does not (5 of 6 chunks > 0.99). **Vote over chunks, don't threshold one running share.**
- Franglais did not produce a single false "English" chunk on two Meetings.
- The only wrong lexical verdict was failure mode 2. Meeting A was about 0.02 words/s against roughly 1+ words/s for real recognition. A word-rate guard separates those by about two orders of magnitude.
- Meeting B shows the other wrong-model behaviour (failure mode 3), which text LID gets right.
- Missing from the data: an English Meeting run through `fr_FR` with native speakers, a 3-language case, and VoIP-degraded "Them" audio. The earlier TTS probe hints that `fr_FR` *drops* native English instead of transcribing it ("Thanks a neww"). That would land in the word-rate branch, not the text branch.

## What this means for Carbon

**Can lexical LID replace the acoustic model?** For Carbon's setup (Apple `SpeechTranscriber`, two checked languages, re-transcription from the recorded file), **yes as the decider, provided it never decides from text alone (inference).** The literature only ever adds text to acoustics, because its systems lacked one of Carbon's assets: a transcriber in every candidate locale, cheaply re-runnable over buffered audio. With that asset, "is this really language X?" can be answered the way Kukk & Alumäe found most reliable, from X's own recognizer output. Carbon's only measurement of the accent case says the acoustic model is the weaker signal for this user.

Proposed rule (all thresholds **(inference)**, to calibrate on recorded Meetings like the existing ones):

1. **Per stream, not per Meeting.** Run the checks on Me and Them separately, as the earlier notes recommend. AWS does it per channel.
2. **Speech denominator from the existing Silero gate.** Count VAD speech seconds per stream (≥ 0.85, as today). Count finalized words from the transcriber per stream, using `.audioTimeRange` to attribute them.
3. **Word-rate guard (the "wrong model emits almost nothing" case).**
   - After at least ~20 s of VAD speech on a stream, words per VAD-second below about **0.2** means "this locale is not hearing its language". Measured: ~0.02 in the failure case, ≥ ~1.25 in working cases.
   - That is evidence *against* the current locale. It is **not** evidence for a particular other one, and text LID on those few words must be ignored.
4. **Lexical vote (the "wrong model writes the other language" case).**
   - Run `NLLanguageRecognizer` with `languageConstraints` = the checked languages on each new **10-word chunk** of finalized text. Use `languageHypotheses(withMaximum:)`, as Apple advises for short text.
   - Count a chunk for a language at share ≥ **0.9**.
   - Suggest a switch when ≥ **3 of the last 4** chunks (≥ 30–40 words) favour another checked language.
   - Optionally ignore chunks that are mostly names or acronyms (Apple's named-entity caveat; `NLTagger` `.nameType` could flag them **(unverified)** whether worth it).
   - Cost is negligible (1.5 ms per call).
5. **Confirm before switching (replaces "trust the text").**
   - When step 3 or 4 fires, re-transcribe the stream's last ~30 s of speech from the recorded file in the candidate locale. Carbon already reads back from the file for its switch.
   - Switch only if the candidate's output passes the same tests in its favour: a word rate at least ~2× the current locale's, and ≥ 0.9 share for the candidate on most chunks.
   - This is Google's parallel recognizer plus text LangID, run once on demand instead of continuously. It is also the guard against failure mode 1 (fluent own-language hallucination at a normal word rate). Without it, that case stays in the wrong language; it is a miss, not a false switch.
6. **Margins and give-up.**
   - Keep the default language when nothing fires. Never fall back to English (Handy, the competitor bugs).
   - Stop checking a stream after N failed confirmations, or after ~3 minutes of speech with no signal, as `maximumSpeech` and `maximumWindows` do today.
   - A switch back needs the same evidence (hysteresis).
   - Because the lexical checks run on text Carbon produces anyway, they can keep running all Meeting long at no cost. That lets Carbon follow a later language change, which the once-per-Meeting acoustic vote cannot (ADR 0005, consequence 2).
7. **Ask, don't just switch, at least at first.** Teams *prompts* the organizer ("Yes, change it") instead of switching silently. Carbon already has a notification and the Meeting Language menu. A confirmed lexical switch could auto-apply, and an unconfirmed one (for example, a confirmation run that ended in a tie) could prompt.
8. **Optional: add `.transcriptionConfidence`.** It is a third, independent signal. The TTS gap was large (0.61–0.90 against 0.18–0.24), and Gitman et al. found confidence plus LID beat either alone. It is not needed for the rule above. Add it if calibration shows the confirmation run ties often.

**What remains the acoustic model's job, if anything (inference).**

- **The speech gate stays (Silero VAD).** It is the word-rate denominator, and it keeps silence and music from looking like "the model emits nothing". That is VAD, not LID.
- **Ranking candidates when there are three or more.** When the current locale goes quiet (step 3), lexical evidence says "not mine" but not "whose". With two checked languages the answer is the other one. With three or more, Carbon must either run a confirmation per remaining candidate (cost linear in candidates, still on demand), or let ECAPA *rank* them and confirm only the top one. That is the one place ECAPA's 11 ms per window is still worth its 43 MB. Restricted ranking among candidates is something it did well on native TTS ([offline note](offline-spoken-language-identification.md)).
- **Not needed: deciding the accent case.** Carbon's measurement, Kukk & Alumäe, AssemblyAI's docs and the model card all agree that acoustic LID is the weak signal there.
- **A cheap prior, if kept.** It could pick which candidate to confirm first even with two languages. That only saves a confirmation run that costs a fraction of a second of compute per 30 s of audio, so it is not worth keeping the model for this alone.

**Recommendation (inference).** Prototype the lexical rule (steps 1–6) behind the existing switch, and replay it offline on the recordings Carbon already has: the 40 s accented-English clip and the three Meetings. Then add the missing cases: an English Meeting through `fr_FR`, VoIP "Them" audio, and a Meeting that changes language halfway. If it decides every two-language case correctly, retire ECAPA for two languages. Keep it, or drop it and accept per-candidate confirmations, only for three or more checked languages. Either way, ADR 0005 would need a successor ADR: the decider changes from acoustic to lexical, with acoustic at most a ranker. "Once per Meeting" becomes "continuously, per stream".

## Appendix: offline replay of the lexical rule (maintainer, local, 2026-10-31)

Before ADR 0006, the rule above was replayed offline: TTS clips (native, accented, phone-band, and two that change language halfway) and the maintainer's real recordings, through the real Silero gate, real `SpeechTranscriber` sessions per locale and `NLLanguageRecognizer`. A trigger re-transcribed only the stretch that fired, in the candidate locale; the Meeting then went on in the confirmed locale, as Carbon's switch does.

**Acoustic classifier replayed on the same clips.** With four candidates (fr, en, de, es), ECAPA confidently picked the speaker's native language on every accented clip (5 of 5 wrong), and never followed a mid-Meeting language change, by design of its once-per-Meeting vote.

**Two candidates (fr-FR, en-US), confirmation "candidate words ≥ current words and most chunks ≥ 0.9".** Every clip ended in the right locale, with no false switch:

| Clip | Started in | What fired | Outcome |
|---|---|---|---|
| English, native (US, GB) | fr-FR | vote at 11–12 s | en-US |
| English, French accent (2 voices, plus phone band) | fr-FR | vote at 19–23 s, or the rate guard at 21 s (0.05 words/s) | en-US |
| French, native, franglais, phone band | fr-FR | nothing | stays fr-FR (0 of 14–16 chunks read as English) |
| English then French | fr-FR | vote → en-US at 23 s; first vote back rejected (fewer words), second confirmed at 58 s | follows both changes |
| Maintainer's accented English, 40 s | fr-FR | vote at 32 s (en-US 2.19 against fr-FR 1.27 words/s, 6 of 6 chunks) | en-US |
| Two real French Meetings, 3 min, both streams | fr-FR | nothing | stays fr-FR (0 of 39–51 chunks read as English) |
| French native, French Meetings | en-US | vote (first one rejected at 11 s, confirmed at 23 s), or the rate guard at 25 s (0.05 words/s) | fr-FR |
| English native and accented | en-US | nothing | stays en-US |

A stricter confirmation, "candidate writes twice the current words", would have missed every vote-triggered switch: a wrong locale on native speech still writes 1.1–1.8 words per second of speech against 2.6–3.4 for the right one.

**Four candidates (fr-FR, en-US, de-DE, es-ES), rate guard at 1.0 words per second of speech.** Native German, Spanish and English, accented English (German, Spanish, French accents), Spanish with French accent, Spanish full of loanwords, and German then English all ended in the spoken language, by vote or by the guard trying every other candidate and keeping the best words-per-second × share. German with a French accent was the one miss: every candidate's transcript was rejected (de-DE 0.84 words/s at a 0.66 share), so it stayed fr-FR, a miss rather than a false switch. With the guard at 0.2 instead of 1.0, Spanish clips through fr-FR (0.4–1.0 words/s) waited for the vote, up to 37 s.

What these show **(inference)**: the transcript is the stronger signal for accented speech, the rate guard covers the case where the wrong model writes almost nothing, and the confirmation run is what keeps a vote from switching on its own. Real VoIP "Them" audio and three-language real Meetings remain to be measured on recorded Meetings, from the diagnostic log.
