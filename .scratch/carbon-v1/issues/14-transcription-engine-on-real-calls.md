# Transcription engine quality on real calls

Type: prototype
Status: resolved
Blocked by: 05, 06
Assignee: alexandre

## Question

On the real meeting test set, does a post-Meeting re-transcription of both streams with FluidAudio Parakeet (v3 / Ultra) beat live SpeechTranscriber (en_US / fr_FR) clearly enough, with no new phantom text on silence, to ship the hybrid in v1? Answer the nine open questions in `docs/research/speechtranscriber-vs-whisper-cpp.md` (WER per stream and language, Parakeet's language pick on French and mixed turns, silence hallucinations, live battery/thermal cost of two streams over an hour, post-pass time and memory on a base M1/M2, word-to-Speaker alignment, download sizes, Mac coverage, proper nouns with attendee-name boosting). Outcome: SpeechTranscriber only / SpeechTranscriber live + Parakeet post-pass, plus any change to the Meeting Language design if Parakeet's auto-detection holds.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.

## Answer

Resolved 2026-10-28, fully AFK. The author pre-approved the recommendation (map Notes, overnight).

**Verdict: SpeechTranscriber only in v1, with no Parakeet post-pass.** The bar was fixed in the README before the scored run, and Parakeet clears it in neither language. Its best variant, Ultra, cuts pooled Me + Them WER by 13.6 % relative in English and 10 % in French, short of the 15 % required. Ultra passes the phantom-text and speed parts of the bar. The Meeting Language design stays unchanged.

**WER (1, 3).** The test set has 28 Meetings, about 17.8 h of streams. Each stream is muted where only the other stream speaks, the way a tapped call or a headphone mic would be (`prep.py`). All engines share one normalizer, and scores are corpus-level.

| | SpeechTranscriber | Parakeet v3 | Parakeet Ultra |
|---|---:|---:|---:|
| English (AMI + ICSI) | 21.3 % | 21.9 % | **18.4 %** |
| French (SUMM-RE + Simsamu) | 24.1 % | 28.7 % | **21.7 %** |
| Me streams (AMI / ICSI / SUMM-RE) | 11.7 / 18.3 / 13.5 % | 12.7 / 23.1 / 21.0 % | 10.5 / 18.7 / 14.9 % |
| Them streams (AMI / ICSI / SUMM-RE) | 17.1 / 35.6 / 26.7 % | 15.8 / 37.4 / 35.1 % | 13.7 / 31.1 / 25.3 % |
| FR phone (Simsamu, mixed channel) | 35.4 % (31.5 % deletions) | 20.8 % | 22.0 % |

- On headset speech, SpeechTranscriber is level with Ultra in French (SUMM-RE) and a few points behind in English. Most of its error is deletions on far or overlapped Them speech.
- **Phone-band audio is the weak case.** On Simsamu, SpeechTranscriber drops whole passages, up to 15 s at a time, and Parakeet is 13 points better. This is the case for dogfooding to watch on dial-in callers.
- **Phantom text** (words wholly inside ≥ 1 s of digital zeros, per muted hour):
  - SpeechTranscriber: 0 in English and 3.5 on French Them.
  - Ultra: 0–1.6.
  - v3: up to 15.5, mostly timing spill at the edges of a mute.
  - 10 min of zeros, pink room noise, a hold-music chord loop and US ringback gave 0 words from every engine, on both the en_US and the fr_FR model.

**Language (2).** Parakeet's automatic language is no reason to drop the person-chosen Meeting Language.
- v3 slips into English in 6.2 % of French phrases, and Ultra in 0.3 %.
- FluidAudio's `language:` hint only filters script (Latin vs Cyrillic), so it cannot stop an FR→EN slip.
- On a file of alternating EN/FR turns, no engine follows the switch:
  - SpeechTranscriber fr_FR leaves 62 % of English turns empty.
  - Ultra leaves 52 % empty and outputs 21 % in French.
  - v3 scores 35–40 % WER on both languages.

Mid-Meeting switching stays in later versions.

**Live cost (4).** Two real-time en_US streams ran for 60 min (ICSI Bmr006).
- CPU: about 6 % of one core in total. The XPC service `localspeechrecognition` took 4.5 % median (7.8 % p95), and the two feeding processes 1.7 %.
- Memory: 27–51 MB in the service.
- Thermals: no thermal or performance warning.
- Results: final results arrive 1.9 s after the audio (p95 3.7 s, max 4.3 s), with no drift over the hour.
- Live words equal batch words exactly (WER 12.9 / 24.9 % both ways). Feed rate does not change the output, which the 10 Simsamu real-time runs also showed.
- Battery drain was not measurable, because the charger was plugged in mid-run.

**Post-pass cost (5), recorded in case a v1.1 post-pass comes back.**
- Speed on the M3 Pro: Parakeet runs at 180–210× real time, so 2 × 60 min takes ≈ 35 s.
- Peak RSS: 190 MB median, 670 MB max.
- Cold Core ML compile: 16 s for v3, 12 s for Ultra; 0.1 s once cached.
- No base M1/M2 was available.

**Timing (6).** On matched words, the median absolute start offset is 0.09–0.13 s and p90 0.25–0.33 s for every engine. Oracle Speaker attribution per word is 95.7 % EN and 96.7 % FR with SpeechTranscriber `audioTimeRange`, against 94.7–96.0 % with Parakeet `tokenTimings`. The word-level merge from "Diarization and Voice Print quality on real calls" keeps SpeechTranscriber timings as is.

**Downloads (7).**

| Asset | Download | On disk |
|---|---:|---:|
| fr_FR SpeechTranscriber | 142.6 MB (installed in 15.4 s) | ~347 MB |
| en SpeechTranscriber | 138.4 MB | ~389 MB |
| Parakeet v3 | | 461 MB |
| Parakeet Ultra | | 603 MB |

- An installation request reserves the locale automatically, with `AssetInventory.maximumReservedLocales` = 5.
- Whether assets survive weeks of non-use is not testable here. Carbon should call `AssetInventory.reserve(locale:)` for the Meeting Language, check `AssetInventory.status` when a Meeting starts, and download the asset again when needed.

**Mac coverage (8).**
- `SpeechTranscriber.isAvailable` is true on the M3 Pro (macOS 27), and the supported locales include en_* and fr_FR/BE/CA/CH.
- Intel was not testable. Carbon is Apple-silicon-only in practice: the Summary needs Apple Intelligence, and diarization runs on the ANE. Check `isAvailable` at launch.

**Names (9).** These are the 111 person-name mentions in the English Meetings.

| Engine | Recall | Invented |
|---|---:|---:|
| SpeechTranscriber | 83 % | 4 |
| Parakeet Ultra | 86 % | 3 |

Attendee-name boosting is not usable in v1:
- `contextualStrings` (EventKit names via `AnalysisContext`) changed no word.
- FluidAudio CTC rescoring raises recall to 97–99 % but invents 3,500+ names, turning ordinary words into "William William William".
- Names stay a manual edit.

**For the spec:**
- One `SpeechTranscriber` per stream in the Meeting Language, with `volatileResults` and `audioTimeRange`, fed straight from the capture tap.
- Reserve both shipped locales and check asset status at Meeting start.
- No post-pass, and no name boosting.

**Not covered:**
- No real tapped VoIP audio (codecs, echo, packet loss). SUMM-RE's Zoom recordings and Simsamu's phone band are the nearest.
- One Mac only, and no battery figure.
- French names in SUMM-RE are anonymised, so the names check is English-only.

## Assets

- Prototype: [`prototypes/transcription-eval/`](../prototypes/transcription-eval/). [README](../prototypes/transcription-eval/README.md) has the method and the pre-fixed bar; [results](../prototypes/transcription-eval/results.md) has every table, extra runs and the live test.
