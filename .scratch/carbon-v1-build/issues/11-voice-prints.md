# 11: Voice Prints: remember, recognize, manage

**What to build:** naming a Speaker with at least 10 s of speech stores a Voice Print. In later Meetings Carbon recognizes that voice and writes the name straight into the first file write. It never names anyone it is unsure about. The Voice Prints tab in Settings lists the remembered voices: delete one, delete all, or turn "Recognize voices" off. Spec: Modules (VoicePrintMatcher, VoicePrintStore), Settings › Voice Prints.

**Blocked by:** 10 (Naming Speakers from attendees).

**Status:** ready-for-agent

- [ ] Prints are stored in `voiceprints.json` with the spec's schema (id, name, email, model id, base64 centroid, at most 3 recent embeddings, meetings, createdAt, lastHeardAt). The file is excluded from backups.
- [ ] A cluster with less than 10 s of speech gets the name but no print. Its menu says "Not enough speech to remember this voice."
- [ ] Matching:
  - a match needs a cosine distance < 0.30 and a margin of at least 0.10 over the runner-up;
  - each print matches at most one cluster per Meeting, assigned greedily by smallest distance;
  - prints from another model id are ignored;
  - each best distance is written to the diagnostic log.
- [ ] Updates come from auto-matched or person-confirmed Speakers only: the centroid plus the 3 recent embeddings.
- [ ] Renaming an auto-matched Speaker moves that Meeting's link to the new print.
- [ ] Deleting a print clears `voicePrintId` everywhere and leaves the names in the files.
- [ ] The Settings › Voice Prints tab: the toggle; rows of name and "Heard in N Meetings · last <date>" with a delete button; "Delete All…" with a confirmation; the privacy note from the spec.
- [ ] Turning recognition off stops matching and enrolling, and asks once whether to delete the existing prints.
- [ ] VoicePrintMatcher tests use boundary cases from the diarization-eval distances: 0.237 same-person, 0.312 impostor, a margin failure, a model mismatch.
- [ ] Recorder test: a known voice gets named in the first write.
