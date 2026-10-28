# 10: Naming Speakers from attendees

**What to build:** in the panel and in the editor's Speaker chips, every Speaker except Me has a chevron (unnamed Speakers are blue). It opens a menu with the Event's attendees plus "Other Name…". Picking a name rewrites only that Speaker's Turn headers in the file and records the name in `meetings.json`. Naming two Speakers the same is allowed, and renaming again works. Spec: Rename write-back in "Transcript body format in Markdown" (`.scratch/carbon-v1/issues/18-transcript-markdown-format.md` rule 8), Library `renameSpeaker`.

**Blocked by:** 06 (Calendar Event matching, Provider and participants), 07 (Speaker A/B/C from offline diarization, with the Me / Them fallback), 09 (Meeting actions, the editor window, Local Edits and reconcile).

**Status:** done

- [x] The rename rewrites only the header lines that match the anchored pattern for that Speaker's current label. Text is never touched and Turns are never re-grouped, even on a file with Local Edits.
- [x] Names drop `*`, `[`, `]` and line breaks. `Me` and `Them` are refused.
- [x] A name not yet in `participants` is added to the frontmatter and to `meetings.json`.
- [x] The `speakers` entry gets `name`, `label` and `match: "user"`.
- [x] Golden test against the prototype's renamed sample.

Notes (ticket/10):
- Core: `Library.renameSpeaker(_:label:name:)` in `LibrarySpeakers.swift`, through `writeSurgically`. `LibraryError.invalidSpeakerName` for `Me` / `Them` / empty names and for renaming Me.
- A label shared by two merged Speakers renames both: the file can't tell them apart.
- Fallback files: the first naming of `Them` (or the 1:1 attendee label) adds a `speakers` entry with `cluster: "Them"`, `speechSeconds: 0`.
- Editor chips rename only while the editor has no unsaved changes, then reload from disk.
- Deferred to 11: Voice Print enroll on rename and the "Not enough speech to remember this voice." note. The menus were built but not clicked through in the running app (smoke launch only).
