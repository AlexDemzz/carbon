# Real meeting test set

Type: task
Status: resolved
Blocked by:

## Question

Assemble the test set (AFK, no hand-recorded Meetings), following "Public meeting corpora for quality tests":

1. **Public corpora (AFK):** download AMI (EN, headset channels split into Me/Them, abstractive summaries, same-speaker series for Voice Prints), QMSum reference summaries, ICSI (~1 h meetings for Summary timing), SUMM-RE dev/test (FR, per-speaker tracks, word timings) and Simsamu (phone-compressed FR). Pick a small subset per language, convert it to Me/Them tracks with references in one shared layout, and record where it lives (outside the repo).

Optional, only if fully scriptable on this Mac: replay corpus files through a real call for compressed call audio (pasrom's no-account Jitsi replay test, Chrome fake-audio flags), then realign the references by cross-correlation.

## Assets

- Test set: `~/Datasets/carbon-test-set/` (outside the repo, 1.9 GB). `README.md` there gives the layout, picks and licenses; `index.json` lists every Meeting and the recurring speakers.
- Rebuild: `tools/download.sh` (raw corpora, ~6 GB, deleted after the build) then `tools/build.py`.

## Answer

**28 Meetings in one shared layout** (`meetings/<corpus>-<id>/`): `me.wav` + `them.wav` (16 kHz mono, sample-aligned; Them = sum of the other close-talk channels), `meeting.json`, and `reference/` with `timeline.rttm`, `segments.jsonl` and `words.jsonl` (each row tagged `me`/`them`), plus `summary.md` and `qmsum.json` where the corpus has them.

| Corpus | Meetings | Language | Length | Covers |
|---|---|---|---|---|
| AMI | ES2004a–d, ES2011a–d | EN | 17–39 min | Diarization, WER, Summary (AMI abstractive + QMSum); two series of four with the same 4 people. Me = Project Manager. |
| ICSI | Bed016 (47 min), Bmr006 (79 min) | EN | | Summary on ~1 h (ICSI abstractive + QMSum), 6–7 speakers. Me = most words. |
| SUMM-RE dev | 018a/b, 020b/c (Zoom), 021a/b (at home), 032a/b (studio) | FR | 18–22 min | Diarization, WER (manual word timings); same people across each pair, speaker 057 in both 018 and 020. No reference summary (rubric judgement). |
| Simsamu | 10 recordings | FR | short | Phone-compressed far voice; one `mix.wav` + RTTM + SRT, no Me/Them. |

Voice Print pairs: 8 recurring AMI speakers (4 Meetings each) and 15 recurring SUMM-RE speakers (2–4 Meetings), listed under `recurring_speakers` in `index.json`.

Facts later tickets depend on:
- Sanity check: each stream's speech is 2–60× louder than the rest of the stream. ICSI Them streams sit at the low end (~2×: headset crosstalk), and SUMM-RE 032a's Me only at 1.5× (studio bleed).
- Bed003 was dropped: its chan1 headset (gain too high) picks up every speaker equally, so it was replaced by Bed016.
- ICSI speakers heard without a close mic (tape playback in Bed016, the recorder in some meetings) are not in the references but leak faintly into the audio.
- The SUMM-RE dev split is ~14 GB, not ~5 GB as `docs/research/public-meeting-corpora.md` says; only 8 of its 29 shards were fetched.

**Not done: the optional live-call replay.** It needs a second browser in a real call and Carbon's capture path recording it, so it isn't fully scriptable on this Mac yet. Compressed call audio is covered only by the SUMM-RE Zoom Meetings and Simsamu.
