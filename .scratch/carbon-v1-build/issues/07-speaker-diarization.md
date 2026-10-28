# 07: Speaker A/B/C from offline diarization, with the Me / Them fallback

**What to build:** after a Meeting ends, the Them stream is split into Speaker A, Speaker B, Speaker C… by FluidAudio. The file is written with those labels, attributed word by word. If diarization hangs or fails twice, the file falls back to Me / Them, with nothing written about which path ran. Spec: Modules (Diarizer, TranscriptBuilder attribution); rules in "Diarization and Voice Print quality on real calls" (`.scratch/carbon-v1/issues/07-diarization-quality-on-real-calls.md`).

**Blocked by:** 02 (Me / Them Transcript with the full Turn rules).

**Status:** ready-for-agent

- [ ] FluidAudio is pinned at 0.17.7, using `OfflineDiarizerManager` (community-1) with a clustering threshold of 0.6.
- [ ] Diarization runs in a separate helper process under a watchdog: a timeout of 2 min + 10 s per audio minute, then one retry in a fresh process, then the fallback.
- [ ] The adapter returns segments plus, per cluster, an L2-normalized centroid and its speech seconds. These are saved in `meetings.json` `speakers`, with `transcript: "speakers" | "fallback"`.
- [ ] Per-word attribution: the most-overlapping segment, else the nearest one within 1 s, else the previous Them word's Speaker. Clusters are lettered in order of their first word.
- [ ] TranscriptBuilder golden test against the prototype's diarized sample.
- [ ] Recorder tests: a Diarizer fake that fails, and one that hangs, both produce the Me / Them file.
