# 07: Speaker A/B/C from offline diarization, with the Me / Them fallback

**What to build:** after a Meeting ends, the Them stream is split into Speaker A, Speaker B, Speaker C… by FluidAudio. The file is written with those labels, attributed word by word. If diarization hangs or fails twice, the file falls back to Me / Them, with nothing written about which path ran. Spec: Modules (Diarizer, TranscriptBuilder attribution); rules in "Diarization and Voice Print quality on real calls" (`.scratch/carbon-v1/issues/07-diarization-quality-on-real-calls.md`).

**Blocked by:** 02 (Me / Them Transcript with the full Turn rules).

**Status:** done

- [x] FluidAudio is pinned at 0.17.7, using `OfflineDiarizerManager` (community-1) with a clustering threshold of 0.6.
- [x] Diarization runs in a separate helper process under a watchdog: a timeout of 2 min + 10 s per audio minute, then one retry in a fresh process, then the fallback.
- [x] The adapter returns segments plus, per cluster, an L2-normalized centroid and its speech seconds. These are saved in `meetings.json` `speakers`, with `transcript: "speakers" | "fallback"`.
- [x] Per-word attribution: the most-overlapping segment, else the nearest one within 1 s, else the previous Them word's Speaker. Clusters are lettered in order of their first word.
- [x] TranscriptBuilder golden test against the prototype's diarized sample.
- [x] Recorder tests: a Diarizer fake that fails, and one that hangs, both produce the Me / Them file.

## Notes

- The watchdog (timeout, one retry, fallback) lives in `Recorder`, so it is tested with fakes; the timeout is injectable. The adapter `HelperProcessDiarizer` launches `CarbonDiarizer` (an embedded tool target at `Contents/MacOS/CarbonDiarizer`) once per attempt and SIGKILLs it when cancelled. The helper also exits when its parent dies.
- Centroids are stored per Speaker in `meetings.json` as `centroid` (base64 of little-endian Float32s, as in `voiceprints.json`), so a print can be enrolled when a Speaker is named.
- A diarization that reaches no Them word gives the Me / Them file. Words before the first attributed word take the next one's Speaker (as `render.py` does).
- Deferred: the first-ever run downloads the FluidAudio models inside the watchdog window, so a slow first download can fall back to Me / Them; prefetching the models is left to a later ticket. The helper's stderr is inherited, not yet routed to the diagnostic log. Checked by one real helper run on the 6 s Them clip (1 cluster, 256-d unit centroid); no full Meeting was run from the app.
