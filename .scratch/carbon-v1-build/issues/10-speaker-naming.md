# 10: Naming Speakers from attendees

**What to build:** in the panel and in the editor's Speaker chips, every Speaker except Me has a chevron (unnamed Speakers are blue). It opens a menu with the Event's attendees plus "Other Name…". Picking a name rewrites only that Speaker's Turn headers in the file and records the name in `meetings.json`. Naming two Speakers the same is allowed, and renaming again works. Spec: Rename write-back in "Transcript body format in Markdown" (`.scratch/carbon-v1/issues/18-transcript-markdown-format.md` rule 8), Library `renameSpeaker`.

**Blocked by:** 06 (Calendar Event matching, Provider and participants), 07 (Speaker A/B/C from offline diarization, with the Me / Them fallback), 09 (Meeting actions, the editor window, Local Edits and reconcile).

**Status:** ready-for-agent

- [ ] The rename rewrites only the header lines that match the anchored pattern for that Speaker's current label. Text is never touched and Turns are never re-grouped, even on a file with Local Edits.
- [ ] Names drop `*`, `[`, `]` and line breaks. `Me` and `Them` are refused.
- [ ] A name not yet in `participants` is added to the frontmatter and to `meetings.json`.
- [ ] The `speakers` entry gets `name`, `label` and `match: "user"`.
- [ ] Golden test against the prototype's renamed sample.
