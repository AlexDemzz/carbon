# NVIDIA Nemotron 3.5 Transcribe vs Carbon's SpeechTranscriber

Researched 2026-10-29. The question: NVIDIA announced a new transcription model on 2026-10-28 ([tweet](https://x.com/nvidiaai/status/2115462300241141882)). Can it replace the engine Carbon transcribes Meetings with?

Sources are the NVIDIA model card and its Hugging Face metadata, the OpenMDW licence text, the Hugging Face cards of the community Apple-silicon ports, the FluidAudio PR and release that add one of them, and Carbon's own code. Benchmarks of Apple's engine are taken from [speechtranscriber-vs-whisper-cpp.md](speechtranscriber-vs-whisper-cpp.md), which cites them. Anything I concluded myself, rather than read in a source, is marked **(inference)**. Anything no primary source settles is marked **unverified**. No model was downloaded or run for this note.

Pinned revisions (Hugging Face commit SHAs, 2026-10-29):

- NVIDIA card: [`nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B@a99e33f`](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B/blob/a99e33f698257b8b69ca7834f19c73582eb1fa7e/README.md). Prefix **N** = that README.
- Core ML "Lite" port: [`FluidInference/nemotron-3.5-transcribe-lite-coreml@31ecb73`](https://huggingface.co/FluidInference/nemotron-3.5-transcribe-lite-coreml/blob/31ecb73ab8a541001c0952802b478384cf9f0691/README.md). Prefix **F** = that README.
- MLX ports: [`divergentlabs/Nemotron-3.5-Transcribe-30B-A4B-MLX@40d4c32`](https://huggingface.co/divergentlabs/Nemotron-3.5-Transcribe-30B-A4B-MLX/blob/40d4c323933d0a324ed9ab3f2112942903c7c1d5/README.md), [`nativ-community/Nemotron-3.5-Transcribe-30B-A4B-EA-4bit@c47153c`](https://huggingface.co/nativ-community/Nemotron-3.5-Transcribe-30B-A4B-EA-4bit/blob/c47153ca2ce4024d43e216b81e6db4f67b886545/README.md).
- GGUF port: [`sakasegawa/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B-GGUF@cf5239e`](https://huggingface.co/sakasegawa/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B-GGUF/blob/cf5239e0e20416a45b5b1c30955c8a0cf457addb/README.md).

## Short answer

**No, not as announced. Not yet for the one on-device port that exists.**

| | Carbon today: Apple SpeechTranscriber | Nemotron 3.5 Transcribe (full) | "Lite" Core ML port (encoder + CTC, no LLM) |
|---|---|---|---|
| What runs | System framework, out of process | 34B-parameter speech LLM, 4.3B active | NVIDIA's 600M encoder + CTC timestamp head, used as a recognizer |
| Official Mac support | Yes (macOS 26+) | **No**: Linux/Windows, NVIDIA GPUs only | Unofficial community port |
| Download / memory | No app download, no app memory | 67.5 GB BF16, 21.6 GB NVFP4; ~17 GB RAM via community MLX/GGUF | 1.36 GB download |
| Live streaming | Yes | **No**: "This is an offline model" | No (whole recording) |
| English accuracy | LibriSpeech clean 2.12 %, Earnings-22 14.0 % (third-party) | LibriSpeech clean 1.09 %, AMI 7.81 %, Open ASR mean 4.71 % | LibriSpeech clean **5.50 %**, AMI meeting **26.3 %** |
| French accuracy | FLEURS 6.6 % (third-party) | FLEURS **3.16 %** | **Not evaluated** |
| Speakers | No (Carbon adds FluidAudio) | Built in, up to `<spk:3>` in the prompt | Via Nemotron-3-Diarization |
| Word times | Start + end per run | Start + end, via a vLLM middleware only | **Start only**, 40 ms |
| Licence | System | OpenMDW-1.1, permissive | OpenMDW-1.1 |

The full model is the most accurate open model on paper and covers French as a "Leading" language. But it is a 34B data-centre model with no official Apple runtime. The community Mac ports need about 17 GB of memory, which no shippable Mac app can take. The only port small enough to ship strips out the language model, and its published English numbers are worse than what Carbon has today.

## 1. Which model the tweet announces

- The tweet introduces "Nemotron 3.5 Transcribe": an open-weight, promptable 30B MoE model with about 4B active parameters. It does transcription in 40 languages, speaker attribution, translation, contextual prompting and audio understanding in one checkpoint. It was posted 2026-10-28 15:14 UTC ([tweet via api.fxtwitter.com](https://api.fxtwitter.com/nvidiaai/status/2115462300241141882)). This is the first post of a thread. I read only that post.
- The checkpoint is `nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B`, with FP8, NVFP4 and DFlash2 (speculative-decoding draft) variants. It is released on Hugging Face, NGC, build.nvidia.com and NeMo on 10/28/2026 (N L147, L280-L285).
- It is "an offline speech and audio model": a Speech-Augmented Language Model (SALM) that turns recordings plus text instructions into text (N L108, L135-L137).
- **Size:** "34B (4.3B active), including the audio encoder" (N L145). It is built from a 600M Transformer ASR encoder, a ~99M Nemotron-3-Diarization speaker encoder, a CTC timestamp head, and the Nemotron-3.5 Lightning 30B-A3B Mamba-Transformer MoE language model (N L300-L306).
- **Inputs:** 16 kHz mono, recordings up to 1 hour, 65,536-token context (N L148, L378-L383).
- This is not the 0.6B **Nemotron 3.5 Streaming Multilingual** model that FluidAudio already ships. That one was compared in [speechtranscriber-vs-whisper-cpp.md §2](speechtranscriber-vs-whisper-cpp.md#2-streaming-two-concurrent-streams-for-one-hour).

## 2. What Carbon uses today

- **Engine:** Apple `SpeechAnalyzer` + `SpeechTranscriber`, behind the `Transcriber` port (`CarbonCore/Sources/CarbonCore/Ports.swift` L39-L42; `App/Sources/AppModel.swift` L59).
- **Where it runs:** on device, in the system. The app quits at launch if `SpeechTranscriber.isAvailable` is false (`App/Sources/CarbonApp.swift` L50-L60). Carbon targets macOS 26 and arm64 only (`project.yml` L4-L5, L19-L20).
- **Model and download:** nothing ships in the app. Each Meeting Language's system asset is reserved and downloaded through `AssetInventory` (`App/Sources/Adapters/MeetingLanguageAssets.swift` L50-L66). The adapter downloads it again if it is missing (`App/Sources/Adapters/SpeechTranscriberAdapter.swift` L28-L30).
- **Streaming vs batch:** one analyzer per stream, Me (mic) and Them (app audio), started when the Meeting starts (`CarbonCore/Sources/CarbonCore/Recorder.swift` L411-L414). The module asks for `.volatileResults` and `.audioTimeRange` (`SpeechTranscriberAdapter.swift` L19-L23). The adapter keeps only `isFinal` results, and returns the words when the session finishes (`SpeechTranscriberAdapter.swift` L39-L42, L68-L72).
  - So Carbon transcribes live, but it does not use the live text; it only wants a finished word list when the Meeting ends **(inference from the adapter)**. A batch engine could sit behind the same port by buffering audio and transcribing in `finish()`. The cost is the wait after the Meeting ends.
- **Languages:** one language per Meeting. The Meeting Languages offered in onboarding and Settings are exactly `SpeechTranscriber.supportedLocales`, with English and then French listed first (`MeetingLanguageAssets.swift` L26-L28; `CarbonCore/Sources/CarbonCore/MeetingLanguages.swift` L72-L90). The onboarding step says "Carbon transcribes each Meeting in one language, on your Mac" (`App/Sources/OnboardingWindow.swift` L96-L99). The default is the system language, or en-US (`App/Sources/AppModel+Languages.swift` L16). On macOS 27.0.1 that list is 45 locales, including `fr_FR`, `fr_CA`, `fr_BE` and `fr_CH` ([language-detection.md](language-detection.md), probe).
- **Speakers:** FluidAudio 0.17.7 (`project.yml` L13-L15) runs offline diarization (pyannote community-1, Core ML) on the recorded Them stream in a helper process, after the Meeting (`Diarizer/main.swift` L1, L25-L28; `Recorder.swift` L582-L591). Its models ship in the app (`App/DiarizationModels/SOURCE.md` L3-L6).

## 3. Languages

- **Coverage:** 40 languages. French (France, Canada) is rated "Leading", with ASR, translation, multi-speaker ASR and code-switching all ticked (N L327-L332). English, German, Spanish, Italian, Portuguese and Dutch are also "Leading" (N L329-L341).
- **Gaps against Apple:** Norwegian is listed with no ASR tick and scores 63.76 % WER on FLEURS (N L365, FLEURS table). Whether all 45 of Apple's locales are covered was not checked line by line (**unverified**). Opinion: for Carbon's English + French use, coverage is not the blocker.
- **Language identification and code-switching:** the model transcribes "Language: as spoken" (N L258) and supports code-switching in every listed language (N L327-L369). That would answer the open problem in [language-detection.md](language-detection.md), where Apple offers no language ID and Carbon makes the person pick a language per Meeting.

## 4. Accuracy

Full model, NVIDIA's own numbers on an H100 with vLLM (N L999-L1005):

- **English:** Open ASR Leaderboard 9-set mean **4.71 %**; AMI **7.81 %**; Earnings-22 (Open ASR subset) **5.29 %**; LibriSpeech clean/other **1.09 / 2.60 %** (N L576-L591). Long-form Earnings-22 **11.99 %**, against 13.37 % mean for Parakeet-TDT-0.6B-v3 on the long-form board (N L175, L607-L616).
- **French:** FLEURS **3.16 %**, CoVoST2 4.83 %. On the Multilingual Open ASR board, French averages 3.92 % (FLEURS 3.35, Common Voice 5.27, MLS 3.14) (N L634-L692).
- **Meetings with speakers:** AMI cpWER **10.29 %** on individual headsets, **17.34 %** on a single distant mic; NOTSOFAR-1 single-channel 25.91 % (N L710-L717).
- **Against what Carbon has:** third-party runs put SpeechTranscriber at 2.12 / 4.56 % on LibriSpeech, 14.0 % on an Earnings-22 subset, and 6.7 % EN / 6.6 % FR on FLEURS ([speechtranscriber-vs-whisper-cpp.md §1](speechtranscriber-vs-whisper-cpp.md#1-accuracy-english-and-french)). Normalizers and subsets differ, so treat this as indicative. On paper, the full model roughly halves Apple's French FLEURS WER **(inference)**.
- **Failure modes:** the card lists "substitutions, deletions, repetitions, hallucinated speech, incorrect language choice, and speaker attribution errors" (N L2030). It recommends a regex guardrail because the model can "fail to terminate generation and fall into a loop", and the published scores apply it (N L1396-L1412). This is an LLM decoder, so Whisper-style failures on silence are possible **(inference)**. Carbon's mic stream has long muted stretches.

The Lite Core ML port (encoder + CTC head, no LLM), on its publisher's M5 Pro:

- LibriSpeech test-clean **5.50 %** on all 2,620 utterances (4.64 % on an easier 400-utterance subset). AMI EN2002c, one 49.5-minute meeting: **26.3 % WER**, **28.7 % cpWER** (F "Speed and accuracy").
- "Only English was evaluated" (F). "Without the LLM the transcript is much rougher" (F intro).
- That is worse than Apple's third-party LibriSpeech figure (2.12 %) **(inference, different subsets and scorers)**.

## 5. Streaming and latency

- The full model is offline: "Internal audio chunking does not make it a real-time streaming ASR service" (N L266, L380).
- The MLX port can stream text, but "Streaming emits text after the full audio is encoded; this is not incremental microphone recognition" (nativ-community card, Limitations).
- Carbon does not use live text today (§2), so offline alone does not rule it out. What matters is how long the person waits after a Meeting ends **(inference)**:
  - Full model, MLX on an M5 Pro: RTFx **23.6**, measured on 40 LibriSpeech clips (divergentlabs card). That is about 2.5 minutes per hour-long stream, and Carbon has two streams **(inference, not measured on long audio)**.
  - Full model, GGUF with Metal on an M5 with 32 GB: RTFx **5.4 to 8.5** (sakasegawa card, "Speed"). That is 7 to 11 minutes per hour of audio.
  - Lite, Core ML: a 49.5-minute meeting in about 6 s warm, plus a one-time ~80 s Neural Engine compile for the diarizer (F intro and "Meeting demo").

## 6. Size, memory, and running on Apple silicon

- **Official runtimes:** vLLM 0.32, Hugging Face Transformers, SGLang-Omni, and GGML on two RTX Blackwell GPUs. Linux and Windows only, on NVIDIA Ampere, Hopper, Lovelace and Blackwell (N L400-L424). The reference deployment is "1× H100 80 GB" (N L152). There is no CoreML, MLX or Metal path from NVIDIA.
- **Checkpoint sizes** (Hugging Face API, sum of files): BF16 **67.5 GB**, FP8 34.7 GB, NVFP4 21.6 GB ([HF API](https://huggingface.co/api/models/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B?blobs=true)).
- **Community Mac ports of the full model, all from 2026-10-28 or 2026-10-29:**
  - divergentlabs MLX: a custom Metal kernel, mixed 3/4/8-bit weights, "~17 GB of memory", 15.7 GB of files. The author's own advice is "You're probably better of using a smaller model, this is just a research experiment."
  - nativ-community MLX via `mlx-audio` (pinned to a git commit): 4-bit is 19.3 GB, validated only with six synthetic smoke checks on an M3 Ultra. "Speaker tags ... do not provide timestamps."
  - sakasegawa GGUF: IQ4_NL takes **17.2 GiB** of process memory on an M5 with 32 GB. "The model needs its whole file in memory."
- **The Lite port is the only shippable size.** FluidAudio's download is 1.36 GB: a 1.26 GB encoder and a 101 MB CTC head. Variants run from 389 MB (4-bit palettized) to 1.36 GB, all fp16 ML Programs for macOS 15+ (F "Files"). On the GPU it peaks at "GPU ~32 W, Neural Engine ~4.6 W" (F "Speed and accuracy").
- **FluidAudio already has it.** PR #1069 adds `NemotronTranscribeLiteManager` and `transcribeWithSpeakers`, and was merged 2026-10-28 ([FluidAudio #1069](https://github.com/FluidInference/FluidAudio/pull/1069)). It shipped in v0.18.0 the same day ([releases](https://github.com/FluidInference/FluidAudio/releases)). Carbon pins 0.17.7 (`project.yml` L15).
- Opinion: 17 GB of resident memory rules out every 8 and 16 GB Mac, and still squeezes a 24-32 GB one running a video call. The full model cannot ship in Carbon.

## 7. Timestamps, punctuation, speakers

- **Full model:**
  - Punctuation, capitalization, verbatim or clean wording, and context terms are chosen in the prompt (N L256-L262).
  - Word start and end times, diarization segments, and a tag-to-speaker map come from a `ctc_timestamps` object. That object exists only with vLLM's `ctc_timestamp_middleware`, and only for single, non-streamed requests (N L194-L205, L1189-L1214).
  - Speakers are prompted as `<spk:0>`…`<spk:3>` (N L261). How it behaves with more than four speakers is **unverified**.
- **Lite port:** greedy CTC words, each with a "start time only" (F "Meeting demo"). Carbon builds Transcripts from timed words (`TranscribedWord`, `SpeechTranscriberAdapter.swift` L76-L80), so it would have to infer end times **(inference)**. Whether the CTC head outputs punctuation is **unverified**; the published WERs are scored after the Whisper normalizer.

## 8. Licence

- The licence is OpenMDW-1.1 (N L4-L5, L268-L270). The card says the model "is ready for commercial or non-commercial use" (N L139).
- OpenMDW grants the right "to deal in the Model Materials without restriction". Anyone who distributes the materials must keep a copy of the agreement and the copyright and origin notices. It sets no use restrictions and no obligations on outputs. The grant ends only for a party that sues claiming the materials infringe ([OpenMDW-1.1](https://openmdw.ai/license/1-1/)).
- The Lite port redistributes NVIDIA's weights under the same licence (F "License"). Opinion: compatible with a free closed-source Developer ID app. It adds a licence copy to About, next to the CC BY notice the diarization weights already need (`App/Sources/SettingsView.swift` L290).

## 9. Integration effort

- **Full model:** there is no Swift or Core ML path. Shipping it would mean bundling Python and MLX or a GGUF runtime, plus a ~16-20 GB download. Opinion: out of scope.
- **Lite port:** small effort, since FluidAudio is already a dependency.
  1. Bump FluidAudio to 0.18.0 and re-check the bundled diarizer revision (`App/DiarizationModels/SOURCE.md` L6).
  2. Implement `Transcriber` by buffering each stream and transcribing it in `finish()`.
  3. Download 1.36 GB on demand.
  4. Decide whether its Nemotron-3-Diarization replaces community-1.

  The blocker is accuracy (§4), not effort.

## Verdict (opinion)

**Do not replace SpeechTranscriber with Nemotron 3.5 Transcribe now.** Reasons:

1. **It cannot run on a customer's Mac.** NVIDIA supports only NVIDIA GPUs on Linux/Windows. The Mac ports are day-old community experiments that need about 17 GB of RAM and a 16-20 GB download.
2. **It is offline only.** Carbon could live with that, because it only uses final words (§2). But at the measured 6-24x real time, two one-hour streams would take minutes to tens of minutes after every Meeting.
3. **The shippable port loses the accuracy.** The Lite Core ML port drops the LLM. Its published LibriSpeech WER (5.5 %) is worse than Apple's third-party figure (2.12 %), though the scorers differ. Its AMI WER is 26 %, but no source gives an Apple AMI score to compare it with (**unverified**). It has no French evaluation at all.
4. **It has LLM failure modes.** NVIDIA documents generation loops and hallucinated speech, and ships a guardrail for them. That needs testing on Carbon's long silent mic stretches before it can be trusted.
5. **What it does well is real.** French FLEURS 3.16 %, AMI 7.8 %, built-in speakers, language ID and code-switching would remove Carbon's per-Meeting language choice. Those gains need the full model.

**What would make it viable:**

- A **small official variant** from NVIDIA (≤ ~2 GB, the LLM distilled or dropped with no big WER loss), or an Apple-silicon runtime with published French and meeting WER.
- Or a **Lite port that keeps a language model**, with FluidAudio publishing French WER and AMI WER below SpeechTranscriber's on the same scorer.
- Either way, it must pass Carbon's own test from issue 14 (`.scratch/carbon-v1/issues/14-transcription-engine-on-real-calls.md`): EN and FR, Me and Them streams, silence hallucination, and time after the Meeting on a base M-series Mac.

Until then, the earlier recommendation stands: SpeechTranscriber live, with an optional FluidAudio Parakeet v3 pass after the Meeting as the upgrade to prove ([speechtranscriber-vs-whisper-cpp.md](speechtranscriber-vs-whisper-cpp.md#recommendation-for-carbon)). A cheap next step would be to benchmark FluidAudio 0.18.0's Lite on the issue-14 English set, for speed and speakers only.

## Open questions and unverified

- The rest of the tweet thread (posts 2/ and on) was not read. Only post 1/ was, through a mirror.
- I did not read the [technical report](https://research.nvidia.com/labs/nemotron/files/NVIDIA-Nemotron-3.5-Transcribe-Technical-Report.pdf). All NVIDIA figures come from the model card.
- There is no Mac measurement of the full model on hour-long audio. The RTFx figures come from short clips (MLX) or FLEURS/Common Voice clips (GGUF).
- The Lite port's French quality, punctuation, and behaviour on silence are unknown.
- Whether the Lite port can run on the Neural Engine at useful speed for two streams on a base M1/M2 is unknown. The published speeds are from an M5 Pro, and its ANE speeds use the "standard tensor layout".
- Coverage against all 45 SpeechTranscriber locales was not checked one by one.
