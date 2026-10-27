# SpeechTranscriber vs whisper.cpp for Meeting transcription

Type: research
Status: resolved
Blocked by:

## Question

"Carbon v1 product design" picked Apple SpeechAnalyzer/SpeechTranscriber for transcription. Is that still the best engine for Carbon compared with [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (and, briefly, the Swift-native Whisper/Parakeet runtimes it would compete with, such as WhisperKit or FluidAudio's ASR, since FluidAudio is already a dependency)?

Judge them on what Carbon actually needs: accuracy on real meeting audio (English and French, far-field mic and compressed call audio), live streaming with two concurrent streams (mic + app audio) for a whole 1-hour Meeting, word-level timings to merge with diarization, spoken-language identification (which SpeechTranscriber lacks, see "Native spoken-language detection") and code-switching, speed and battery/thermal cost on Apple Silicon, memory, model download size and distribution (bundled vs on-demand, Sparkle/notarization impact), licensing of code and weights, supported macOS versions and Macs, and maintenance burden. Outcome: keep SpeechTranscriber, switch, or a hybrid (e.g. one engine live, another for the post-Meeting pass), with the reasons.

## Answer

Researched 2026-10-27, findings in `docs/research/speechtranscriber-vs-whisper-cpp.md`.

- **Keep SpeechTranscriber as the live engine for v1.** It needs no download, runs out of process, has no concurrent-stream limit on macOS, and gives word time ranges. Its French accuracy matches Whisper turbo (FLEURS 6.6 % each), but its English on call audio is mid-tier (Earnings-22: 14.0 % vs Parakeet v2 11.7 %, Whisper small 12.8 %).
- **Drop whisper.cpp** (naive streaming, experimental word timestamps, open silence-hallucination issue #1724, largest model and memory, C/XCFramework integration) **and WhisperKit** (same Whisper hallucination profile, best streaming is in the paid Pro SDK).
- **Hybrid candidate to prove:** re-transcribe each stream after the Meeting with FluidAudio Parakeet v3/Ultra. It is already a dependency, CC-BY-4.0, auto-detects among 25 European languages, gives token timings on the diarizer's timeline, and processes 1 h in tens of seconds. Adopt it only if a prototype on real EN/FR Meetings shows a clear WER gain with no new hallucinations. The doc lists the nine open questions that prototype must answer.
