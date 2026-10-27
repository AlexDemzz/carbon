# Prior art in Minute and meeting-transcriber

Type: research
Status: resolved
Blocked by:

## Question

What do the open-source macOS meeting transcribers [roblibob/minute](https://github.com/roblibob/minute) and [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber) already decide and ship, in their source code, for the open tickets on this map, so that those tickets need fewer hand-run meetings? Specifically:

- Detection and auto-stop: rules, thresholds (mic-held delay, silence, calendar end), ignored-process lists, handling of muting, Zoom/Teams holding the mic, back-to-back calls ("Detection and auto-stop rules on real usage").
- Diarization: engine, how they merge speaker segments with word timings, speaker-matching thresholds across meetings ("Diarization and Voice Print quality on real calls").
- Transcription engine, live vs post-meeting pass, silence hallucination guards ("Transcription engine quality on real calls").
- Summary: model, chunking within context limits ("On-device summary quality").
- Tests: fixtures, recorded audio, benchmarks or eval scripts we could reuse instead of recording our own.

Outcome: per open ticket, what is already answered by shipped code (with file:line links at a pinned commit), what is left for a hand-run check, and whether the ticket can shrink.

## Assets

- [Prior art in Minute and meeting-transcriber](../../../docs/research/prior-art-minute-meeting-transcriber.md): source read at Minute `97b5cd0` and pasrom `1765408`, with file:line links.

## Answer

Neither app uses SpeechTranscriber, Foundation Models or EventKit. Their code answers *how* questions (rules, thresholds, merge algorithms, test harnesses), not how well Apple's engines perform.

**Diarization and Voice Print quality on real calls (07)**
- *Answered by shipped code:* FluidAudio offline diarization. pasrom diarizes the app track separately and labels the mic "Me", as Carbon plans. Merge rule: segment-level max overlap, nearest-gap fallback, a new block after a 2 s pause. Voice Print bookkeeping: centroid plus 3 recent samples, ≥ 3 s of speech to update the centroid. Starting thresholds: cosine distance < 0.40 with a 0.10 margin over the runner-up (pasrom), cosine similarity ≥ 0.70 (Minute). Both are stricter than FluidAudio's documented bands. pasrom's MIT DER harness and a CC BY AMI clip are reusable.
- *Hand-run left:* DER on French and English VoIP "Them" tracks, the distance bands on tap audio, word-level vs segment-level merge, offline vs Sortformer on short calls (pasrom's clips favour Sortformer: 0.33 vs 0.36 on AMI), echo on speaker calls.
- *Shrink:* yes. It becomes a measurement run with a fixed method and starting thresholds.

**Detection and auto-stop rules on real usage (09)**
- *Answered by shipped code:* pasrom avoids the Zoom/Teams mic ambiguity by detecting calls from IOKit power assertions instead of mic ownership. Teams: keyword "call in progress" (its WebView holds "Video Wake Lock" while idle). Zoom: display-sleep assertion type. Webex: "On a call". Chromium: "WebRTC has active PeerConnections", which asks for consent. Timings: confirm in 2 × 3 s, stop after a 15 s end grace, 5 s cooldown between back-to-back calls, 4 h cap. Minute stops after 120 s of silence plus a 30 s countdown, measured on the summed mic and system levels. FaceTime's mic is reported by `com.apple.avconferenced`. Mic-in-use alone fires on voice messages.
- *Hand-run left:* does Zoom drop its assertion between back-to-back calls; Teams idle; Safari Meet; Slack huddle; dictation and voice memos; muting in Meet; overlapping events.
- *Shrink:* yes, if ticket 01 adopts power assertions as a second Detection signal (proposed, not decided). The run then becomes assertion and mic snapshots across the listed situations. The ignore list can come from logging unmatched mic holders.

**On-device summary quality (10)**
- *Answered by shipped code:* Minute's chunk-then-merge.
  - Per-pass input budget: context − 1024 output − 256 margin − 512 prompt overhead.
  - Line-boundary chunks.
  - Each pass returns only net-new JSON items, given the accepted state so far.
  - Code merges the items deterministically, and invalid JSON gets one repair pass.
  - Minute labels 4K a "debug-only minimum" and recommends 8K for 8 GB Macs.
- *Hand-run left:* Foundation Models quality in EN and FR, and the time per 1 h Meeting (about 6 passes at 4K by that formula).
- *Shrink:* yes, to a quality and latency run. It could use public transcripts instead of waiting on 06.

**Transcription engine quality on real calls (14)**
- *Answered by shipped code:*
  - Both apps ship post-meeting Parakeet v3; pasrom runs it per track.
  - A language hint exists and pasrom uses it against script drift. Q2 becomes "pass the Meeting Language".
  - Q9: both apps ship CTC vocabulary boosting.
  - Q6: the baseline merge rule from 07 applies.
  - A VAD-trim silence guard exists (pasrom, threshold 0.5, off by default). Minute shows what to avoid: it disables Whisper's no-speech gates.
  - pasrom's WER harness is reusable.
- *Hand-run left:*
  - SpeechTranscriber vs Parakeet WER on Carbon's calls. pasrom's clips show Parakeet behind Whisper turbo (0.37 vs 0.29 on AMI EN), so the hybrid's gain is not a given.
  - Phantom text on muted stretches.
  - Live cost of two streams.
  - Post-pass time and memory, downloads, Mac coverage, the effect of name boosting.
- *Shrink:* a little. Q2 and Q9 become confirmations, and Q6 moves to 07.
