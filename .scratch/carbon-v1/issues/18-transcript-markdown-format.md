# Transcript body format in Markdown

Type: prototype
Status: resolved
Blocked by:
Assignee: alexandre

## Question

How is a Transcript written in the Meeting's Markdown file, now that "Diarization and Voice Print quality on real calls" ships Speaker A/B/C with per-word attribution? Specifically:

- Speaker labels: Me / Speaker A… / a named person.
- Turn grouping: consecutive same-Speaker words, and the pause that starts a new turn.
- Timestamp granularity, given the "Speaker · 0:19" style in "Main window, menus and notification mock".
- How a rename or a Voice Print match is written back into an existing file.
- The Me/Them fallback when the diarization pass fails or times out.

Outcome: a sample Transcript file plus the rules for writing it.

## Assets

- Prototype: [`prototypes/transcript-format/`](../prototypes/transcript-format/README.md): `render.py` turns real SpeechTranscriber words and real FluidAudio diarization into the Meeting file.
- Samples from AMI ES2004a (17 min, Me + 3): [diarized](../prototypes/transcript-format/sample-diarized.md), [after a rename](../prototypes/transcript-format/sample-renamed.md), [Me/Them fallback](../prototypes/transcript-format/sample-fallback.md).

## Answer

Resolved 2026-10-28, AFK. The author pre-approved the recommendation (map Notes, overnight).

**One turn per paragraph, on one line:**

```markdown
## Transcript

**Me** [0:10] Are we - we're not allowed to dim the lights, so people can see that a bit better.

**Speaker A** [0:24] So we've got both of these clipped on. Is she gonna answer me or not?

**Sam Rivera** [4:48] Oh, yep, thank you.
```

Each line reads as plain text and renders cleanly in any Markdown viewer. A `grep` hit always carries the Speaker and the time. The app parses it with one anchored pattern: `^\*\*(name)\*\* \[(time)\] `. The app shows it as "Speaker · 0:19" over the text, per "Main window, menus and notification mock". The file does not copy that two-line layout: two lines would either run together in other viewers or need a blank line per header.

**Rules for writing it:**

1. **Speaker labels.**
   - `Me` for the mic stream.
   - `Speaker A`, `Speaker B`… for Them clusters, lettered in order of each cluster's first word in the Meeting.
   - The person's name once named or matched by a Voice Print.
   - `Them` only in the fallback.
   - In a 1:1 calendar event, a lone Them Speaker (or `Them` in the fallback) is written as the other attendee's name, per "Carbon v1 product design".
   - Names drop `*`, `[`, `]` and line breaks. `Me` and `Them` are reserved.
2. **Attribution.** Per word, as decided in "Diarization and Voice Print quality on real calls": the most-overlapping segment, else the nearest one within 1 s. A word no segment reaches keeps the previous Them word's Speaker.
3. **Sentences.** A sentence is a run of one Speaker's words. It ends at SpeechTranscriber's `.` `?` `!` `…`, at a pause of 1.5 s or more, or where the Speaker changes. Both streams' sentences are ordered by start time, with `Me` first on a tie. Overlapping talk therefore interleaves by sentence, never word by word.
4. **Turns.** Consecutive sentences from one Speaker form a turn. A new turn, with its own timestamp, starts when:
   - the Speaker changes;
   - the same Speaker resumes after 10 s or more of silence;
   - a monologue passes 90 s, at the next sentence end.

   Two consecutive turns can share a Speaker; that is how a long monologue gets fresh timestamps.
5. **Timestamps.** The turn's first word, as elapsed time from the start of the Meeting, truncated to the second: `m:ss`, then `h:mm:ss` past an hour, with no leading zero hour (same as the UI).
6. **Text.**
   - Words are joined with single spaces as SpeechTranscriber writes them, with its punctuation and casing; the first letter of a turn is capitalised.
   - `\` `` ` `` `*` `_` `[` `]` `<` `>` are backslash-escaped, so recognised text never turns into markup.
   - No fillers are dropped and nothing is rewritten.
7. **When it's written.** The Transcript is final once the Meeting ends and the diarization pass finishes or falls back. A Voice Print match is not a later edit: the matched name goes straight into the first write.
8. **Rename write-back.** Naming a Speaker rewrites the label in that Speaker's turn headers only. It never touches the text and never re-groups turns. This means:
   - It is safe on a file with Local Edits, since only lines that still match the header pattern change.
   - It works the same for "Other Name…".
   - Naming two Speakers the same person is allowed (the way to merge an over-split cluster): their turns then simply share a name.
   - Renaming a named Speaker again works the same way. The Speaker → name and Voice Print link lives in `meetings.json` (still fog), not in the file.
9. **Fallback.** If the diarization pass fails twice or times out, the same rules apply with `Me` / `Them`, as in the [fallback sample](../prototypes/transcript-format/sample-fallback.md). The file never states which path ran: the labels show it.

**Rejected:**
- A two-line header like the UI (`**Me** · 0:19` over the text): grep loses the Speaker, and other viewers run the two lines together.
- A heading per turn: 134 headings in 17 min would flood the outline.
- Word-by-word interleaving of overlap: it shreds sentences.
- Re-grouping turns after a rename: in the first try it re-glued Me's deliberately split monologue.
