# Transcription engine quality on real calls

Type: prototype
Status: open
Blocked by: 05, 06

## Question

On the real meeting test set, does a post-Meeting re-transcription of both streams with FluidAudio Parakeet (v3 / Ultra) beat live SpeechTranscriber (en_US / fr_FR) clearly enough, with no new phantom text on silence, to ship the hybrid in v1? Answer the nine open questions in `docs/research/speechtranscriber-vs-whisper-cpp.md` (WER per stream and language, Parakeet's language pick on French and mixed turns, silence hallucinations, live battery/thermal cost of two streams over an hour, post-pass time and memory on a base M1/M2, word-to-Speaker alignment, download sizes, Mac coverage, proper nouns with attendee-name boosting). Outcome: SpeechTranscriber only / SpeechTranscriber live + Parakeet post-pass, plus any change to the Meeting Language design if Parakeet's auto-detection holds.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.
