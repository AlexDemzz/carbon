# Diarization and Voice Print quality on real calls

Type: prototype
Status: resolved
Blocked by: 05, 06
Assignee: alexandre

## Question

On the real meeting test set, does FluidAudio offline diarization of the "Them" track split speakers well enough (English and French) to ship Speaker A/B/C in v1, and what cosine-distance threshold makes Voice Print recognition across Meetings reliable without false matches? Includes merging diarization segments with SpeechTranscriber `audioTimeRange` word timings. Outcome: ship / defer to v1.1, plus the threshold.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.

## Assets

- Prototype: [`prototypes/diarization-eval/`](../prototypes/diarization-eval/README.md): Swift CLI on FluidAudio 0.17.7 (`OfflineDiarizerManager`, community-1) plus `score.py` (DER, speaker count, word attribution, Voice Print pairs and identification). The bar was fixed in its README before the run.
- Results: [`prototypes/diarization-eval/results.md`](../prototypes/diarization-eval/results.md): clustering threshold sweep 0.4–0.8, per-Meeting table, Voice Print distance bands.
- Run AFK on 2026-10-28 on the 28 Meetings of "Real meeting test set" (18 Me/Them Meetings in EN and FR, 10 Simsamu phone calls), M3 Pro.

## Answer

Resolved 2026-10-28, fully AFK. The author pre-approved the recommendation (map Notes, overnight).

**Verdict: ship Speaker A/B/C and Voice Prints in v1.** Diarization lands in the README's middle band ("ship, with the weak case written down"), not the clear-ship band. Voice Prints clear their bar with room to spare.

**How the Them track was built.** In the test set, Them is a sum of close-talk headsets, so Me's voice leaks into it. A tapped call carries no Me. On the raw track the diarizer gave that leak its own Speaker in 9 of 10 English Meetings: 1/10 had the right count. The primary run therefore mutes Them wherever only Me speaks (`mute_me.py`), as a tapped call would. Both numbers are in the results.

**Diarization at FluidAudio's default clustering threshold (0.6).** Collar 0.25 s, overlap scored.

| | Them DER | Missed / false alarm / confusion | Speaker count ±1 (exact) | Word attribution |
|---|---|---|---|---|
| English (AMI + ICSI, 10) | 21.5 % (16.5 % without ICSI Bed016) | 17.1 / 2.6 / 1.8 | 10/10 (8/10) | 84.4 % |
| French (SUMM-RE incl. Zoom, 8) | 12.8 % | 7.9 / 2.2 / 2.7 | 8/8 (6/8) | 84.3 % |
| French phone (Simsamu, 10) | 14.4 % | 7.0 / 0.2 / 7.2 | 9/10 (9/10) | n/a |

- **Errors are mostly missed speech, not confusion.** FluidAudio emits exclusive segments, so overlapped talk is lost. Speakers are rarely swapped: confusion is 1.8 % in English and 2.7 % in French. French is no worse than English.
- **Weak cases for dogfooding:**
  - ICSI Bed016 (DER 67 %): 5 Them speakers on low-separation headsets with tape playback; one speaker went unfound.
  - Two-cluster outcomes when a third person talks little: SUMM-RE 020b/c over Zoom, AMI ES2011a, Simsamu arme_2.
  - Overlap-heavy talk.
- **Clustering threshold: keep 0.6.** It is best or tied in English and SUMM-RE French. 0.7 helps only Simsamu, and Minute's 0.8 is clearly worse: English DER 37 %, 6/10 counts. No per-language tuning.
- **Speed:** ≈ 300× real time on M3 Pro, so ≈ 12 s for a 1 h Meeting.
- **Hangs:** CoreML hung twice in about 64 files within one long-lived process: one segmentation "prediction timeout" error, and one silent stall at ~5 % CPU. One process per file with a timeout and retry ran clean. The app must run the pass under a watchdog (timeout, then retry in a fresh process), and fall back to Me/Them if the retry fails too.

**Merge: word level, as planned.** Reference word timings stood in for `audioTimeRange`. Each word takes the Speaker whose segment overlaps it most, or the nearest segment within 1 s. That beat phrase level (a speaker-agnostic phrase split at 0.8 s pauses, given its majority Speaker) by about 5 points: 84.4 vs 78.6 % in English, 84.3 vs 79.9 % in French. So Carbon attributes per word, then groups consecutive same-Speaker words into turns. Prior art's segment-level merge is the weaker choice for a Them track with several people.

**Voice Print threshold: auto-match below 0.30 cosine distance, with ≥ 0.10 margin over the runner-up.** Data: 72 prints of 33 people, 64 same-person pairs across Meetings, 2,492 impostor pairs.

- Same person: median 0.057, max 0.237. The max is speaker 057 recorded in person vs over Zoom (018 vs 020).
- Impostors: min 0.312 (057 vs 017 on the same Zoom call), p5 0.65. The hardest are ES2011's four women, at 0.33–0.43.
- 0.30 is the largest cutoff with no impostor below it. At 0.30, with the margin rule (each person enrolled from their first Meeting, every later appearance probed):
  - 39/39 later appearances auto-matched correctly, with no wrong match;
  - 0 of 11 never-seen people were matched to anyone.
- pasrom's 0.40 would put 8 impostor pairs below the cutoff, and FluidAudio's 0.5–0.65 bands would put 38–131. Both are too loose for auto-naming.
- The real risk is a missed match: a person on AirPods one week and a laptop mic the next can drift past 0.30 (in-person vs Zoom already reached 0.24). A miss only leaves "Speaker B" unnamed, which is the safe failure. Dogfooding should log best distances to widen the cutoff if misses show up.

**Voice Print rules for the spec:**
- A print is the L2-normalized centroid of one Speaker's cluster (`speakerDatabase`), taken only from ≥ 10 s of that Speaker's speech, the minimum measured here.
- Each stored name matches at most one Speaker per Meeting.
- Store the embedding model id next to each print, since a model change invalidates prints.
- Updating a print from later Meetings was not measured. Keep pasrom's "centroid + 3 recent" only from auto-matched or user-confirmed Speakers.

**Not covered** (caveats in the README):
- No real tapped-call audio. The closest were SUMM-RE's Zoom recordings and Simsamu's phone band.
- Within a series, each person keeps the same headset, so same-person distances are optimistic.
- Echo on speaker calls and Sortformer on short calls were not run. Sortformer exposes no embeddings (per "On-device speaker diarization options"), and offline already handles 2-person phone calls at ≈ 10 % DER.
