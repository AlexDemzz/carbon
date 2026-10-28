# Transcription eval (PROTOTYPE, throwaway)

Answers the ticket "Transcription engine quality on real calls" (`../../issues/14-transcription-engine-on-real-calls.md`). It compares live SpeechTranscriber (en_US / fr_FR) with a post-Meeting FluidAudio Parakeet pass (v3 and Ultra, FluidAudio 0.17.7). Both run per stream on the real meeting test set (`~/Datasets/carbon-test-set`), and the run covers what it can of the nine open questions in `docs/research/speechtranscriber-vs-whisper-cpp.md`.

## Run

```sh
swift build -c release
uv run --with numpy python prep.py ~/Datasets/carbon-test-set clean             # clean/<meeting>/{me,them}.wav + clean/silence/*.wav
uv run --with numpy python mixed.py build ~/Datasets/carbon-test-set clean      # clean/mixed/mix.wav, EN/FR turns
./run.sh ~/Datasets/carbon-test-set st v3 ultra                                 # hyp/<engine>/<meeting>__<stream>.json
uv run --with jiwer --with num2words --with numpy python score.py ~/Datasets/carbon-test-set hyp clean results.md
./live.sh                                                                       # 60 min, two real-time streams
uv run --with jiwer --with num2words --with numpy python live_score.py ~/Datasets/carbon-test-set hyp clean
```

The extra runs (French silence fixtures, mixed turns, name boosting, cold loads) are listed with their commands in `results.md`.

`asr` is a single Swift CLI:
- `st` feeds a WAV to `SpeechAnalyzer` + `SpeechTranscriber` in 100 ms buffers through an `AsyncStream`, which is the live path Carbon will use. The options are volatile results and `audioTimeRange`. By default it feeds as fast as the analyzer takes input. `--realtime` paces the buffers to the audio clock.
- `pk` runs `AsrManager` on the whole file, as a post-pass would. It uses the library defaults (v3-family no-mel long-form path, seam-gap repair) and reads word timings from `tokenTimings`.
- Every run is one process per file with a timeout, the lesson from "Diarization and Voice Print quality on real calls".

## What is scored

- **Clean tracks.** In the test set, each stream is a close-talk headset that also picks up the other stream's voices. A tapped call carries no Me, and a headphone mic hears no Them. `prep.py` therefore mutes each stream wherever only the other stream speaks (padded 0.1 s). The muted stretches are digital zeros, which is exactly what a muted Carbon stream delivers (per "Audio capture probe across meeting apps").
- **WER.** Each stream is scored against the reference words of that stream, with one normalizer for every engine. The normalizer lowercases, strips punctuation, spells digits out (`num2words`), splits French elisions, joins AMI letter acronyms (`T_V_` → `tv`), and drops fillers (uh/um/hmm/mm-hmm, euh/heu/hum/bah) and SUMM-RE markers (`+ @ *`, anonymised `SPEAKER_n`). The score is corpus-level: total edits over total reference words. Simsamu is scored on its single mixed channel against its SRT.
- **Phantom text.**
  - Words whose midpoint falls inside a muted stretch (zeros ≥ 1 s) of a clean track, per hour of muted audio.
  - 10 min fixtures, scored on both the English and the French model: zeros, pink room noise at −55 dBFS, a synthetic hold-music chord loop, and US ringback.
- **Word timings (open question 6).** Matched words only. The offset is hypothesis minus reference at the start and at the end. "Oracle attribution" gives each matched Them word the reference Speaker turn it overlaps most, then checks it against the true Speaker. This isolates what an engine's timing alone costs the word-level merge decided in "Diarization and Voice Print quality on real calls".
- **Mixed language (open question 2).**
  - ~6 min of alternating English and French solo turns (`mixed.py`), scored per language.
  - On the French corpus, the share of output phrases that read as English.
- **Proper nouns (open question 9).**
  - Recall of the person names said in the English Meetings.
  - The same names passed as attendee names: `contextualStrings` for SpeechTranscriber, FluidAudio CTC vocabulary rescoring (`ctc110m`) for Parakeet.
- **Cost.**
  - Wall time, load time and peak RSS per file.
  - A 60 min, two-stream, real-time SpeechTranscriber run sampled with `top` (CPU, energy impact, memory of the `localspeechrecognition` XPC service) and `pmset` (thermal state).
  - A cold Core ML load from a fresh copy of each Parakeet model.
  - The on-disk and download sizes of every model and asset.

## Bar, fixed before the scored run

**Ship the hybrid (SpeechTranscriber live + Parakeet post-pass) for a language** if its best Parakeet variant clears all of these:

- it cuts pooled Me + Them WER by ≥ 15 % relative against SpeechTranscriber in that language;
- it adds no phantom text: phantom words per muted hour ≤ SpeechTranscriber's + 1, and no words on the zeros fixture;
- the post-pass on 2 × 60 min takes ≤ 2 min on this M3 Pro, so a base M1 at roughly a third of the speed stays within ~6 min.

**SpeechTranscriber only** if Parakeet clears the bar in neither language. If it clears it in one language only, the post-pass runs only when the Meeting Language is that language.

## Caveats known up front

- **No real tapped-call audio.** AMI, ICSI and SUMM-RE streams are close-talk headsets (SUMM-RE 018/020 recorded over Zoom), and Simsamu is phone-band. VoIP codecs, echo and packet loss are not represented.
- **Faster than real time.** SpeechTranscriber is fed faster than real time in the scored run. The 60 min real-time run checks whether that changes its output.
- **One Mac only.** Only an M3 Pro (18 GB) on AC power was available. There is no base M1/M2 and no battery reading; energy impact from `top` stands in for battery drain.
- **Few proper nouns.** The name check rests on ~140 mentions in the English Meetings. French names in SUMM-RE are anonymised.
