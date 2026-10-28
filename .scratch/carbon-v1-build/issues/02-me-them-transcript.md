# 02: Me / Them Transcript with the full Turn rules

**What to build:** a manual Meeting now also captures the call's far side. Here that is a global system-audio tap that excludes Carbon; ticket 03 narrows it to the Meeting App. The file becomes a Me / Them Transcript laid out exactly as in "Transcript body format in Markdown" (`.scratch/carbon-v1/issues/18-transcript-markdown-format.md`). The ticket introduces TranscriptBuilder as a pure `CarbonCore` module and the anchored header parser `^\*\*(name)\*\* \[(time)\] `. Spec: Modules (Capture, Transcriber, TranscriptBuilder).

**Blocked by:** 01 (Manual Meeting from the menu bar to a Markdown file).

**Status:** done

- [x] Two SpeechTranscriber streams run live, Me from the mic and Them from the tap, and each one is recorded to its own CAF file.
- [x] Before each Meeting, Carbon checks the System Audio Recording permission with `TCCAccessPreflight`, loaded through `dlsym`. It never infers the permission from audio.
- [x] TranscriptBuilder applies every rule in the spec:
  - a sentence ends at `.?!…`, a pause of 1.5 s or more, or a Speaker change;
  - sentences from both streams are ordered by start time, with Me first on a tie;
  - a new Turn starts on a Speaker change, after 10 s or more of silence, or past a 90 s monologue;
  - timestamps are `m:ss` / `h:mm:ss`, truncated to the second;
  - the first letter of each Turn is capitalized, and text is Markdown-escaped;
  - `Me` and `Them` are reserved labels.
- [x] TranscriptBuilder has golden-file tests built from the transcript-format prototype's real AMI ES2004a words. The fallback sample is matched byte for byte.
- [x] A Recorder test with Me and Them WAV fixtures produces the expected Me / Them file.

**Notes (implementation):**

- The Them tap (`App/Sources/Adapters/SystemAudioTap.swift`) builds and is wired, but was not validated live: per the spec, the tap must be checked from the signed app by dogfooding, never from a terminal.
- `Transcriber.start(locale:stream:)` now names the stream (`.me` / `.them`); the replay fake uses it to pick its words.
- The permission check lives in `Recorder.start` (port `systemAudioPermission`): only `denied` refuses the Meeting; `notDetermined` lets the tap trigger the system prompt, and `unknown` (preflight missing) proceeds.
- Per-word attribution of diarization segments stays in ticket 07; this ticket's builder takes the Me / Them streams. `TranscriptBuilder.header(_:)` and `label(forName:)` (line breaks become spaces; `Me` / `Them`, case-insensitive, are refused) are ready for tickets 08 and 10.
