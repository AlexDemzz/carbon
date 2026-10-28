# 11: Voice Prints: remember, recognize, manage

**What to build:** naming a Speaker with at least 10 s of speech stores a Voice Print. In later Meetings Carbon recognizes that voice and writes the name straight into the first file write. It never names anyone it is unsure about. The Voice Prints tab in Settings lists the remembered voices: delete one, delete all, or turn "Recognize voices" off. Spec: Modules (VoicePrintMatcher, VoicePrintStore), Settings › Voice Prints.

**Blocked by:** 10 (Naming Speakers from attendees).

**Status:** done

- [x] Prints are stored in `voiceprints.json` with the spec's schema (id, name, email, model id, base64 centroid, at most 3 recent embeddings, meetings, createdAt, lastHeardAt). The file is excluded from backups.
- [x] A cluster with less than 10 s of speech gets the name but no print. Its menu says "Not enough speech to remember this voice."
- [x] Matching:
  - a match needs a cosine distance < 0.30 and a margin of at least 0.10 over the runner-up;
  - each print matches at most one cluster per Meeting, assigned greedily by smallest distance;
  - prints from another model id are ignored;
  - each best distance is written to the diagnostic log.
- [x] Updates come from auto-matched or person-confirmed Speakers only: the centroid plus the 3 recent embeddings.
- [x] Renaming an auto-matched Speaker moves that Meeting's link to the new print.
- [x] Deleting a print clears `voicePrintId` everywhere and leaves the names in the files.
- [x] The Settings › Voice Prints tab: the toggle; rows of name and "Heard in N Meetings · last <date>" with a delete button; "Delete All…" with a confirmation; the privacy note from the spec.
- [x] Turning recognition off stops matching and enrolling, and asks once whether to delete the existing prints.
- [x] VoicePrintMatcher tests use boundary cases from the diarization-eval distances: 0.237 same-person, 0.312 impostor, a margin failure, a model mismatch.
- [x] Recorder test: a known voice gets named in the first write.

**Notes (implementation):**
- Model id is `fluidaudio/community-1@0.17.7` (`VoicePrint.currentModel`): the FluidAudio package version stands in for the weights revision. Bump it with FluidAudio.
- "Excluded from backups": Carbon's `Backups/` only ever copy `meetings.json`; `voiceprints.json` is also marked `isExcludedFromBackup` (Time Machine).
- Prints are updated when auto-matched (in `Recorder.file`, so recovered Meetings too) and when the person names a Speaker. A new print starts with `recent: []`. An auto-matched name is added to the Meeting's participants with the print's email. A voice match wins over the 1:1 attendee naming.
- Renaming a linked Speaker to another name moves the link and takes one Meeting off the old print (deleted at 0). Deferred: the old print's recent embeddings and centroid are not rolled back.
- Diagnostic log lines carry no names: "Voice Print best distance 0.123 for Speaker A: matched|not matched".
- Settings UI was built and compiled only, never looked at.
