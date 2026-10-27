# Diarization and Voice Print quality on real calls

Type: prototype
Status: open
Blocked by: 05, 06

## Question

On the real meeting test set, does FluidAudio offline diarization of the "Them" track split speakers well enough (English and French) to ship Speaker A/B/C in v1, and what cosine-distance threshold makes Voice Print recognition across Meetings reliable without false matches? Includes merging diarization segments with SpeechTranscriber `audioTimeRange` word timings. Outcome: ship / defer to v1.1, plus the threshold.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.
