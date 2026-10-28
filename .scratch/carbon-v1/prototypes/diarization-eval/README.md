# Diarization eval (PROTOTYPE, throwaway)

Answers the ticket "Diarization and Voice Print quality on real calls" (`../../issues/07-diarization-quality-on-real-calls.md`): FluidAudio offline diarization (`OfflineDiarizerManager`, pyannote community-1, v0.17.7) on the Them track of the real meeting test set (`~/Datasets/carbon-test-set`), and a Voice Print threshold from same-speaker series.

## Run

```sh
swift build -c release
uv run --with numpy python mute_me.py ~/Datasets/carbon-test-set clean      # clean/<meeting>/themclean.wav
for f in ~/Datasets/carbon-test-set/meetings/*/{them,me,mix}.wav clean/*/themclean.wav; do
  gtimeout 300 .build/release/diarize hyp 0.4,0.5,0.6,0.7,0.8 "$f" || gtimeout 300 .build/release/diarize hyp 0.4,0.5,0.6,0.7,0.8 "$f"
done
uv run --with numpy --with scipy python score.py ~/Datasets/carbon-test-set hyp results.md
```

One process per file with a timeout: in one long-lived process, CoreML once threw a segmentation prediction timeout and once stalled silently. `diarize` skips outputs that already exist, so a rerun resumes. It loads the models once, runs segmentation + embeddings once per file (`prepare`), then re-clusters at each AHC threshold (`cluster`), so the threshold sweep costs almost nothing. It writes the segments and one L2-normalized centroid per cluster (`speakerDatabase`), the vector Carbon would keep as a Voice Print.

## What is scored

- **Them DER**: the Them track against the RTTM rows of the Them speakers, 10 ms frames, optimal speaker mapping, overlap scored (FluidAudio emits exclusive segments, so overlapped speech counts as missed). Reported at collar 0.25 s (primary) and 0 s.
- **Me bleed removed (primary)**: in the test set, Them is a sum of close-talk headsets, so Me's voice leaks into it. A tapped call has no Me in it. The primary run diarizes `themclean.wav` (`mute_me.py`: Them muted wherever the reference has only Me speaking, padded 0.1 s), and frames where only Me speaks are left out of every score. The raw `them.wav` result is reported next to it. *Added after the first look at the data, which showed the leak forming its own cluster; the bar below is unchanged.*
- **Speaker count**: clusters with ≥ 10 s of speech against the true number of Them speakers.
- **Word attribution**: reference word timings stand in for SpeechTranscriber `audioTimeRange`. Word level (each word takes the cluster that overlaps it most, nearest segment within 1 s otherwise) vs segment level (speaker-agnostic pseudo-ASR phrases split at 0.8 s pauses, each phrase takes its majority cluster). Accuracy = share of Them words given the right Speaker after mapping.
- **Simsamu** (phone FR, one mixed channel, 2–3 speakers) is scored as a single track.
- **Voice Prints**: each cluster is mapped to its reference speaker (≥ 60 % purity, ≥ 10 s of speech); Me tracks give the Me speaker's print from their largest cluster that is ≥ 60 % Me. Same-speaker pairs are the same person in two different Meetings; impostor pairs are two different people. An identification run then enrolls each recurring person from their first Meeting and probes every later appearance (non-recurring speakers are probes that should come back "new"), with pasrom's rule: auto-match when the nearest print is below the threshold and beats the runner-up by ≥ 0.10.

## Bar, fixed before the run

**Speaker A/B/C (diarization)** per language, on the default clustering threshold or one chosen value for both languages:

- **Ship in v1** if mean Them DER (primary) ≤ 20 %, the speaker count is within ±1 in ≥ 80 % of Meetings, and word-level attribution ≥ 85 %.
- **Defer to v1.1** if mean DER > 30 % or word attribution < 75 % in either language.
- In between: ship, with the weak case written down for dogfooding.

**Voice Print threshold**: the largest cosine distance at which no impostor pair falls below it (false-match rate 0 % on this set, ≤ 1 % if 0 % costs more than half the true matches), rounded down to 0.05. Ship Voice Prints in v1 if that threshold auto-matches ≥ 60 % of same-speaker pairs in the identification run with no false auto-match; otherwise Voice Prints move to v1.1 (Speakers stay unnamed or named per Meeting).

## Caveats known up front

- No real tapped call audio: AMI/ICSI/SUMM-RE "Them" are summed headsets (cleaner than VoIP), SUMM-RE 020 is a Zoom recording, Simsamu is phone-band.
- Same person, same headset across a series: same-speaker distances are likely optimistic against a real person switching from AirPods to a laptop mic.
- Small set: 8 + 15 recurring people, so the threshold is a starting value for dogfooding, not a tuned constant.

## Status (2026-10-28)

Run complete, see `results.md` and the ticket's Answer. Verdict: ship Speaker A/B/C (middle band: EN DER 21.5 %, word attribution 84 %) and Voice Prints (auto-match < 0.30 cosine distance, ≥ 0.10 margin) in v1. Hypothesis JSONs are not committed: rerun to regenerate (~25 min).
