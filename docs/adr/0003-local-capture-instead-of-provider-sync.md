# Transcribe Meetings locally instead of syncing Provider transcripts

Carbon v1 detects Meetings on the Mac (microphone in use, matched against calendar events read through EventKit) and transcribes mic and system audio on-device, instead of pulling Google Meet transcripts from Drive. This removes Google OAuth, restricted-scope verification and CASA, works on every Provider and on Google accounts without Meet transcription, and keeps all data on the Mac.

## Consequences

- Carbon must be running during the Meeting; nothing can be recovered afterwards.
- Other participants are not notified by any platform banner: the person is responsible for consent (all-party consent states in the US, art. 226-1 code pénal in France). Carbon still starts automatically by default, signalling it with a notification that offers Stop and a red menu bar indicator for the whole Meeting.
- Speaker attribution beyond "me vs. others" needs on-device diarization (FluidAudio, see docs/research/on-device-diarization.md).
- No echo handling in v1: Apple's native voice processing ducks the call audio, and anything else would have to be built.
- Provider sync (official transcripts and Gemini summaries) remains a possible later addition.
