# Public meeting corpora for quality tests

Type: research
Status: resolved
Blocked by:

## Question

Which public, downloadable meeting or conversation corpora with ground-truth speaker timelines and reference transcripts (e.g. AMI, ICSI, VoxConverse, CALLHOME, plus French ones) can stand in for the hand-recorded "Real meeting test set" to judge diarization, transcription WER and Summary quality, in English and French, with licenses that allow local testing? Note what they cannot stand in for (separate mic and app-audio tracks, compressed call audio from Meet/Zoom, mixed EN/FR turns) and whether replaying a corpus file through a real Meet call would cover that. Outcome: which corpus per language, and how small the hand-recorded set can get.

## Assets

- [Public meeting corpora for quality tests](../../../docs/research/public-meeting-corpora.md): per-corpus language, size, kind, channels, annotations, access and license, with sources; plus the Meet-replay protocol.

## Answer

**Per language and judgement:**

| | English | French |
|---|---|---|
| Diarization (07) | **AMI** (headset mix or summed headsets; four-meeting series give Voice Print same-speaker pairs). VoxConverse as an optional stress test for research use only. | **SUMM-RE** dev/test, with the per-speaker tracks merged into a timeline. |
| WER (14) | **AMI** + **ICSI** (manual transcripts, per-speaker close-talk channels to build Me/Them streams). Earnings-21/22 for proper nouns and entities. | **SUMM-RE** dev/test (manual, word-aligned; includes some Zoom-recorded meetings). Simsamu for a small phone-compressed check. |
| Summary (10) | **AMI abstractive summaries** + **QMSum** (137 AMI + 59 ICSI). ICSI's ~1 h meetings for the 1-hour timing. | No public French meeting audio with released reference summaries. Use SUMM-RE transcripts with a rubric/pairwise judgement (its summaries exist but are not in the HF release). FREDSum (debates, text) only to tune the French prompt. |

All picks are free to download, and their licenses allow local and commercial evaluation: AMI and ICSI CC BY 4.0, QMSum MIT, SUMM-RE CC BY-SA 4.0, Simsamu MIT. Skip CALLHOME, DIHARD, CEFC-ORFEO, ESTER/ETAPE/REPERE and Common Voice: they are paid, non-commercial-only, broadcast or read speech, and Common Voice is not conversational.

**Replay through Meet** covers compressed call audio and the real process-tap path while keeping the ground truth. Feed the far-end mix from a second computer, not a phone speaker: Chrome `--use-fake-device-for-media-stream --use-file-for-fake-audio-capture=<wav>`. Play the "Me" channel locally into the Mac's mic, align references by cross-correlation, and score on ~3 AMI + ~3 SUMM-RE meetings (plus one each on Zoom). This keeps most of ticket 06's labelling off human hands.

**What still needs real hand-recorded calls:** mixed EN/FR turns, real muted stretches, the user's own speaker-to-mic echo in a live call with real people, Meet/Zoom behaviour with several genuine senders, the user's own meeting genre for Summary usefulness, and attendee proper nouns.

**Minimal hand-recorded set (ticket 06 shrinks to 4 Meetings, ~2 h of audio):**
1. EN 1:1 on headphones.
2. FR 3+ people on laptop speakers (echo).
3. Mixed EN/FR, 2–3 people.
4. One ~60 min Meeting with long muted stretches, held on Zoom while the others are on Meet.

Reuse at least one remote speaker across two of them for a real-world Voice Print false-match check. Only ~10 min per Meeting needs a hand-corrected transcript and speaker timeline (~40 min labelled in total). The public corpora carry the DER/WER/Summary numbers; this set checks that they hold on real calls.
