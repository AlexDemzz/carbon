# Transcript format (PROTOTYPE, throwaway)

Answers the ticket "Transcript body format in Markdown" (`../../issues/18-transcript-markdown-format.md`). `render.py` writes a Carbon Meeting file from real engine output on one test-set Meeting, AMI ES2004a (17 min, English, Me + 3 other people):

- live SpeechTranscriber words with `audioTimeRange` for both streams (`../transcription-eval/hyp/st/ami-ES2004a__{me,them}.json`, from "Transcription engine quality on real calls");
- FluidAudio offline diarization of the Me-muted Them track at threshold 0.6 (`ami-ES2004a__them__diarization.json`, `../diarization-eval/.build/release/diarize`), which found 3 Speakers, the true count.

## Run

```sh
H=../transcription-eval/hyp/st/ami-ES2004a
python3 render.py ${H}__me.json ${H}__them.json ami-ES2004a__them__diarization.json sample-diarized.md
python3 render.py ${H}__me.json ${H}__them.json ami-ES2004a__them__diarization.json sample-renamed.md "Speaker B=Sam Rivera"
python3 render.py ${H}__me.json ${H}__them.json - sample-fallback.md
```

The transcription hypotheses are gitignored; rerun "Transcription engine quality on real calls" to regenerate them.

## Samples

- [`sample-diarized.md`](sample-diarized.md): the file as first written after the diarization pass (Me, Speaker A/B/C).
- [`sample-renamed.md`](sample-renamed.md): the same file after the person names Speaker B "Sam Rivera".
- [`sample-fallback.md`](sample-fallback.md): the Me/Them fallback when the diarization pass fails.

Frontmatter, attendees and the Summary are placeholders (invented names, a fake Meet id): only the `## Transcript` body is the subject here. The text is SpeechTranscriber's real output, errors included.

## What it showed

- 134 turns for 17 min (61 Me, 39/17/17 for A/B/C). Median line 56 characters, the longest 1,202 (Me's opening monologue, cut at the 90 s rule).
- Ordering by sentence keeps the conversation readable: a quick "Okay." from Me lands between the other person's sentences, never inside one.
- One turn per line keeps `grep` useful: every hit carries the Speaker and the time.
- A rename that also re-grouped neighbouring turns (first try) undid the timestamp splits made on purpose. Renames now touch labels only.

Source: AMI Meeting Corpus, CC BY 4.0, University of Edinburgh and the AMI consortium.
