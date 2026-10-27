# Public meeting corpora for quality tests

Researched 2026-10-27 against primary sources (corpus home pages, catalogue entries, dataset cards, license files, papers). Every claim carries a source link. Anything I could not confirm from a primary source is marked **unverified**.

## What the test set must judge

From tickets 06, 07, 10 and 14:

- **Diarization (07):** FluidAudio offline diarization of the mixed "Them" track, EN and FR, scored against a speaker timeline. Also the Voice Print cosine threshold, which needs **the same speakers across several Meetings**.
- **WER (14):** SpeechTranscriber live vs a Parakeet post-pass, per stream (Me / Them) and per language. Also phantom text on silence, Parakeet's language pick on French and mixed EN/FR turns, and proper nouns.
- **Summary (10):** Foundation Models chunk-then-merge on a 1-hour Meeting, EN and FR, judged against reference summaries or a rubric, plus the time it takes.

Carbon-specific conditions: a separate mic track and app-audio (process tap) track, VoIP-compressed far-end audio from Meet or Zoom, the user's own speaker-to-mic echo when not on headphones, long muted stretches, and mixed EN/FR turns.

## Candidates

"Separate tracks" means per-speaker close-talk channels. With these you can build Carbon's two streams: one speaker's channel stands in for "Me", and the sum of the others stands in for "Them".

### English

**AMI Meeting Corpus** (meetings, recommended for EN)
- 100 hours of meetings in English, mostly from non-native speakers. About two-thirds are role-played design-team scenarios with four roles; the rest are natural meetings ([overview](https://groups.inf.ed.ac.uk/ami/corpus/overview.shtml), [home](https://groups.inf.ed.ac.uk/ami/corpus/)).
- Audio streams per meeting: **four individual headset WAVs**, a headset mix, two table-top arrays, and lapels (lapels not for TS meetings). Download is a per-meeting chooser with no registration ([download](https://groups.inf.ed.ac.uk/ami/download/)).
- Annotations: orthographic transcripts with word timings, dialogue acts, topics, named entities, and **abstractive summaries** of about 200 words under ABSTRACT / DECISIONS / PROBLEMS / ACTIONS, plus extractive summaries, for scenario and non-scenario meetings ([annotation](https://groups.inf.ed.ac.uk/ami/corpus/annotation.shtml)). How many meetings have summaries is **unverified**.
- The HF mirror `edinburghcstr/ami` (ihm and sdm configs, about 29 GB) carries `speaker_id`, `begin_time`, `end_time` and `text` per segment ([HF card](https://huggingface.co/datasets/edinburghcstr/ami)).
- **License: CC BY 4.0** for signals, transcripts and some annotations ([license](https://groups.inf.ed.ac.uk/ami/corpus/license.shtml)). CC BY 4.0 has no non-commercial clause, so both local and commercial evaluation are fine with attribution.
- Voice Print: scenario meetings come in series of four with the same four people ([overview](https://groups.inf.ed.ac.uk/ami/corpus/overview.shtml)). That gives same-speaker-across-Meetings pairs for free.
- FluidAudio already self-reports DER on AMI SDM ([FluidAudio Benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)), so AMI results can be compared to it directly.

**ICSI Meeting Corpus** (meetings)
- 75 natural research-group meetings, 17–103 min each, usually just under an hour. 53 speakers, 3–10 per meeting (average 6), English with many non-native speakers. Each speaker wears a close-talk mic (mostly head-mounted); there are also 6 table-top mics ([LDC2004S02](https://catalog.ldc.upenn.edu/LDC2004S02)).
- LDC sells it for a fee ([LDC](https://catalog.ldc.upenn.edu/LDC2004S02)), but Edinburgh distributes it free: about 70 h, close-talk channels as separate SPH files or one mixed WAV, transcripts and dialogue acts, **CC BY 4.0** ([ICSI at Edinburgh](https://groups.inf.ed.ac.uk/ami/icsi/)).
- Useful because its meetings are **about 1 hour long**, which is what ticket 10's timing question needs; AMI meetings are shorter.

**QMSum** (summaries over AMI and ICSI)
- 1,808 query-summary pairs over 232 meetings: **137 AMI, 59 ICSI**, and 36 parliamentary committee meetings (25 Welsh, 11 Canadian). It includes "summarize the whole meeting" style general queries, plus specific queries ([paper](https://arxiv.org/abs/2104.05938), [repo](https://github.com/Yale-LILY/QMSum)).
- **License: MIT** (repo sidebar) ([repo](https://github.com/Yale-LILY/QMSum)). This is text only; the audio comes from AMI and ICSI.

**VoxConverse** (broadcast / YouTube, not meetings)
- Dev: 216 videos, 1,218 min, 1–20 speakers (mean 4.5). Test: 232 videos, 2,612 min, 1–21 speakers (mean 6.5). Sources are political debates, panels, interviews, talk shows and documentaries ([paper](https://arxiv.org/abs/2007.01216)).
- RTTM speaker timelines only, **no transcripts** ([repo](https://github.com/joonson/voxconverse)). Audio zips are downloadable (dev about 2.0 GB, test about 4.3 GB; HTTP 200 checked) ([repo README](https://github.com/joonson/voxconverse)).
- License: annotations CC BY 4.0, "free for research use", and "the copyright remains with the original owners of the video" ([repo](https://github.com/joonson/voxconverse)). Local research testing is fine; **commercial evaluation on the audio is a grey area**.
- Mostly English. Its language mix is **unverified**.

**CALLHOME American English** (telephone, two-party)
- 120 calls, about 56 h, up to 30 min each, 2-channel 8 kHz u-law. Transcripts are a separate LDC product (LDC97T14). LDC fee required ([LDC97S42](https://catalog.ldc.upenn.edu/LDC97S42)).
- HF mirror `talkbank/callhome` covers EN, ZH, DE, JA and ES (**no French**). It is gated, has speaker timestamps but no transcript text, and is **CC BY-NC-SA 4.0** ([HF](https://huggingface.co/datasets/talkbank/callhome)), so it is non-commercial only.
- Two speakers, one per channel. This is a weak proxy for Them diarization, since Them usually has 1–6 speakers.

**DIHARD III** (mixed domains)
- The eval set is about 33 h of English and Mandarin from 10 domains, including meetings, restaurant, clinical and YouTube audio. Annotations are RTTM and HTK labels with **no transcripts**. LDC fee required ([LDC2022S14](https://catalog.ldc.upenn.edu/LDC2022S14), [challenge](https://dihardchallenge.github.io/dihard3/)).
- Paid, and not meeting-centred. Skip it.

**Earnings-21 / Earnings-22** (earnings conference calls)
- Earnings-21: 44 calls, about 39 h. Earnings-22: 125 calls, about 119 h, English with global accents. Both have `.nlp` token files with a speaker column; Earnings-21 also ships RTTMs ([repo](https://github.com/revdotcom/speech-datasets), [Earnings-22 README](https://github.com/revdotcom/speech-datasets/tree/main/earnings22)).
- License: **CC BY-SA 4.0 for "the transcripts and associated text files"** ([LICENSE.md](https://github.com/revdotcom/speech-datasets/blob/main/earnings21/LICENSE.md)). The rights to the audio itself are not stated (**unverified**).
- Calls are mostly monologue (prepared remarks, then Q&A), with telephone-bridge audio. They are good for proper nouns and entity WER (they carry entity tags), but not for meeting diarization or summaries.

**NOTSOFAR-1** (meetings, English)
- Real meetings in about 30 Microsoft conference rooms, about 6 min each, 4–8 attendees ([paper](https://arxiv.org/abs/2401.08887)). The README counts 237 recorded meetings, plus eval-small (80 meetings) and eval-full (129). Download is from HF with a token; **CC BY 4.0** ([README](https://raw.githubusercontent.com/microsoft/NOTSOFAR1-Challenge/main/README.md)).
- The recordings are far-field, single room. Whether close-talk channels exist on every split is **unverified**. The meetings are short and have no summaries. It is a backup to AMI, not a replacement.

### French

**SUMM-RE** (meeting-style conversations, recommended for FR)
- 283 conversations of about 20 min each, about 91 h in total: train 210, dev 36, test 37. There are usually 3–4 speakers. **Each participant has an individual microphone and a separate audio track** (938 tracks) ([HF card](https://huggingface.co/datasets/linagora/SUMM-RE)).
- Dev and test are **manually transcribed and aligned**, with word-level timestamps per track. Train is Whisper-transcribed. The card says diarization "can also be evaluated if several tracks of a same meeting are merged" ([HF card](https://huggingface.co/datasets/linagora/SUMM-RE)).
- Recording location is coded in the meeting ID: L (lab), H (studio), **Z (Zoom, 32 kHz)**, D (at home). Some meetings therefore went through a real video-call path. How many is **unverified**: the dataset viewer could not scan the shards. There were "three meetings per experiment" ([HF card](https://huggingface.co/datasets/linagora/SUMM-RE)). Whether the same people sit in all three is **unverified**, but likely, and it would give Voice Print pairs.
- **Summaries are not in this release.** The card says "the full SUMM-RE corpus, which includes meeting summaries" exists, but this HF version is an extract ([HF card](https://huggingface.co/datasets/linagora/SUMM-RE)). Whether the summaries are public is **unverified**.
- **License: CC BY-SA 4.0**, not gated ([HF card](https://huggingface.co/datasets/linagora/SUMM-RE)). Local and commercial evaluation are fine; share-alike only bites if you redistribute adaptations. Size: dev and test are each about 5 GB per the HF info API, so download dev or test only.
- Paper: Hunter et al., TALN 2024, "SUMM-RE: A corpus of French meeting-style conversations", about 95 h ([HAL](https://hal.science/hal-04623038/), [ACL Anthology author page](https://aclanthology.org/people/julie-hunter)).

**Simsamu** (simulated medical dispatch calls)
- 61 recordings, 3 h 15 min, two roles (doctor and caller) ([HF medkit/simsamu](https://huggingface.co/datasets/medkit/simsamu)).
- Each recording comes as `.m4a`, `.rttm` and `.srt` ([file tree](https://huggingface.co/api/datasets/medkit/simsamu/tree/main/dj_2022_brulures)). The caller's voice "is transmitted through the phone network and re-emitted by a phone speaker", while the doctor is on a direct microphone. Audio is 8 kHz ([card](https://huggingface.co/datasets/medkit/simsamu)).
- **MIT**. It is a small but real French "near voice vs far, phone-compressed voice" sample on one channel.

**CEFC-ORFEO** (spoken French, many genres)
- About 4 M spoken words from 14 source corpora (conversations, service encounters, **meetings**, public speech), over 2,500 speakers, word and phoneme alignment, free download ([HF mirror card](https://huggingface.co/datasets/datasets-CNRS/CEFC-ORFEO/blob/main/README.md)).
- **CC BY-NC-SA 4.0**: non-commercial only. Which subcorpora are meetings, and whether there are per-speaker channels, is **unverified**. It is a fallback for extra French WER only.

**MLC-SLM (FR subset)** (two-party conversations)
- About 107 h of French: two speakers per roughly 20-min conversation, recorded on mobile phones (for example iPhones) at 16 kHz, with segmentation, speaker labels and transcripts ([summary paper](https://arxiv.org/html/2509.13785v1)).
- The eval annotations are on HF under **CC BY-SA 4.0**, about 6.5 MB, so audio is likely not included ([bsmu/MLC-SLM-Eval](https://huggingface.co/datasets/bsmu/MLC-SLM-Eval)). Audio access goes through Nexdata's challenge page, and its terms are **unverified** ([Nexdata](https://www.nexdata.ai/competition/mlc-slm)).

**FREDSum** (French debate summaries, text)
- French political debate transcripts with speaker tags, two extractive and three abstractive human summaries, **CC BY-SA 4.0** ([repo](https://github.com/linto-ai/FREDSum)).
- No audio in the repo (**unverified**). It is usable only to check the French Summary prompt on text, and debates are not meetings.

**ESTER 2 / ETAPE / REPERE** (broadcast, paid)
- ESTER 2 (ELRA-S0338): about 100 h of French radio broadcast news, plus 6 h of African radio ([ELRA](https://catalogue.elra.info/en-us/repository/browse/ELRA-S0338/)).
- ETAPE (ELRA-E0046): 30 h of TV and radio, mostly spontaneous speech, with multi-speaker and overlap annotation ([ELRA](https://catalogue.elra.info/en-us/repository/browse/ELRA-E0046/), [paper](https://aclanthology.org/L12-1270/)).
- REPERE (ELRA-E0044): 60 h of French TV news and debates (BFM, LCP), TRS transcripts, person and speaker identity ([ELRA](https://catalogue.elra.info/en-us/repository/browse/ELRA-E0044/)).
- All three are ELRA-licensed for a fee. The catalogue lists separate non-commercial (END USER), evaluation and commercial (VAR) licences, in the hundreds to tens of thousands of euros. The per-row mapping of prices was ambiguous in the rendered pages; confirm with ELDA.
- They are broadcast, not meetings, and have no summaries. Not worth buying for v1.

**CALLFRIEND Canadian French** (LDC96S48)
- 60 two-party phone calls, 5–30 min, 2-channel 8 kHz. Transcripts are not listed. LDC fee required ([LDC](https://catalog.ldc.upenn.edu/LDC96S48)). Skip it.

**Common Voice: not conversational.** Contributors record themselves reading single prompt sentences from a CC0 sentence pool ([repo: sentences CC0](https://github.com/common-voice/common-voice)). There are no multi-speaker recordings and no turns. Since October 2025 it is distributed only through Mozilla Data Collective ([HF notice](https://huggingface.co/datasets/mozilla-foundation/common_voice_17_0)). I did not find an explicit primary-source sentence saying "read speech" (**unverified wording**). It is useless for diarization and Summary, and at most a sanity check for read-speech WER.

### Mixed EN/FR

I found no public corpus of meetings with English/French code-switched turns (**absence unverified**; nothing turned up in the catalogues above).

## Summary table

| Corpus | Lang | Kind | Spk/rec | Timeline | Ref. transcript | Summaries | Per-speaker channels | Access | Commercial eval |
|---|---|---|---|---|---|---|---|---|---|
| AMI | EN | meeting | 4 | yes | yes | yes (abstractive) | yes (4 headsets) | free download | yes (CC BY 4.0) |
| ICSI (Edinburgh) | EN | meeting | 3–10 | yes | yes | via QMSum | yes (close-talk) | free download | yes (CC BY 4.0) |
| QMSum | EN | summaries | — | — | AMI/ICSI text | yes | — | GitHub | yes (MIT) |
| NOTSOFAR-1 | EN | meeting | 4–8 | eval sets | eval sets | no | unverified | HF token | yes (CC BY 4.0) |
| VoxConverse | mostly EN | broadcast | 1–21 | yes | no | no | no | free zip | grey (video copyright) |
| CALLHOME | EN + 4 others, no FR | phone | 2 | yes | LDC extra | no | 2 ch | LDC fee / HF gated | no (HF NC) |
| DIHARD III | EN, ZH | mixed | varies | yes | no | no | no | LDC fee | LDC terms |
| Earnings-21/22 | EN | conf. call | several | E21 RTTM | yes | no | no | GitHub | text yes; audio unverified |
| SUMM-RE | FR | meeting (some on Zoom) | 3–4 | from tracks | dev/test manual | not in release | yes | free HF | yes (CC BY-SA 4.0) |
| Simsamu | FR | phone sim. | 2 | yes | yes | no | no | free HF | yes (MIT) |
| CEFC-ORFEO | FR | mixed genres | varies | unverified | yes | no | unverified | free | no (NC) |
| MLC-SLM FR | FR | phone 2-party | 2 | yes | yes | no | unverified | Nexdata | unverified |
| FREDSum | FR | debate text | several | — | text | yes | — | GitHub | yes (CC BY-SA) |
| ESTER2/ETAPE/REPERE | FR | broadcast | many | yes | yes | no | no | ELRA fee | VAR licence fee |
| Common Voice | many | read sentences | 1 | n/a | prompt text | no | n/a | MDC | — |

## What public corpora cannot stand in for

1. **Carbon's real two-stream capture.** Per-speaker channels let you synthesize Me and Them streams, but not the process tap of a real Meeting App, nor the user's mic hearing the Mac speakers when not on headphones. Carbon's mic capture sees that echo before any app-side echo cancellation.
2. **Meet or Zoom compression and voice processing on the far end:** Opus (mandatory WebRTC codec per [RFC 7874 §3](https://www.rfc-editor.org/rfc/rfc7874)), packet loss, AGC, and Meet's noise cancellation. Meet's noise cancellation removes typing, doors and echo, is on by default for most paid Workspace tiers and 2 TB+ Google One plans, and is off for Education tiers ([Meet help](https://support.google.com/meet/answer/9919960?hl=en)). SUMM-RE's Zoom subset and Simsamu partly cover this, for French only.
3. **Mixed EN/FR turns.** No corpus found.
4. **Long muted stretches.** These can be simulated by splicing silence or room tone into corpus audio, but a real hour with the mic muted (digital zeros vs low noise) is a different signal.
5. **The user's own meeting genre and proper nouns,** for Summary usefulness and attendee-name boosting.

## Replaying corpus audio through a real Meet call

The approach is sound, with caveats. It covers points 1 and 2 above while keeping a ground truth. Setup notes:

- **Do not play from a phone speaker into the phone mic.** iOS cannot feed a file as the call microphone. That leaves an acoustic hop (speaker, room, phone mic, phone echo cancellation) that real remote participants don't have, and it can trip noise cancellation.
- Instead, join from a second computer running Chrome with `--use-fake-device-for-media-stream --use-file-for-fake-audio-capture=<file.wav>`. Chromium's switch "must also be used with kDisableAudioInput or kUseFakeDeviceForMediaStream" and accepts `%noloop` ([media_switches.cc](https://raw.githubusercontent.com/chromium/chromium/main/media/base/media_switches.cc)). A virtual input device on that machine also works. Either way the file goes straight into the WebRTC encoder.
- Send the **sum of the non-Me channels** as the far end. Play the "Me" channel locally: through the Mac's speakers into its built-in mic to reproduce echo and room acoustics, or through a virtual input selected as Carbon's mic for a clean case. This needs per-speaker channels, which means AMI, ICSI or SUMM-RE (not VoxConverse or Earnings).
- Ground truth shifts by network and processing latency. Estimate the offset by cross-correlating the captured Them track against the sent mix, shift the reference RTTM and word timings, and score DER with the usual 0.25 s collar.
- Limits:
  - All remote speakers arrive as one Meet participant. Meet's per-participant noise suppression and its speaker-switching behaviour differ from N real senders. For diarization of a mixed Them track this matters little, since Carbon sees a mix either way.
  - Record which Meet account tier was used, since that decides whether noise cancellation was on.
  - Repeat a few files on Zoom.
  - Overlap is real: the corpora have crosstalk, so the far-end mix contains overlapping speech.

## Answer (also recorded in ticket 16)

See the ticket's `## Answer`.
