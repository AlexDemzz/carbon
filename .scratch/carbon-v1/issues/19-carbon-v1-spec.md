# Carbon v1 spec

Type: spec
Status: ready-for-agent
Blocked by:

Synthesized 2026-10-28 from the map (`../map.md`), every resolved ticket it links, `GLOSSARY.md`, `docs/adr/`, `docs/research/`, the prototypes and `Design/`. Where this spec decides something the map listed as "Not yet specified", the decision is marked **(new)**. One part is **pending**: the Summary, until "On-device summary quality" (issues/10) gives its verdict.

## Problem Statement

People take meetings on Google Meet, Zoom, Teams, FaceTime and more. Afterwards, what was said is gone, or it sits in one Provider's cloud, behind sign-ins, admin settings and a bot that announces itself. More and more of their work goes through an AI agent, and the agent cannot read any of it. The tools that do keep transcripts upload the audio, need a Google or Microsoft account with transcription turned on, or cover only one Provider.

The person wants every Meeting they take on their Mac turned into a plain file on that Mac, without thinking about it, that they and their agent can open, grep and paste. Nothing should leave the machine.

## Solution

Carbon is a free, native macOS 26 menu bar app for Apple silicon. It notices when the person is in a Meeting on any Provider and transcribes it on-device. It separates the person ("Me") from the other participants, then tells those participants apart and recognizes the voices it has heard before. With a calendar event it takes the title and participants from it. When the Meeting ends it writes one Markdown file per Meeting into a visible Library folder: YAML frontmatter, then a Transcript with one `**Speaker** [m:ss] text` Turn per line.

A split window lists the Meetings with search, shows a Meeting's participants and Transcript, and lets the person name Speakers, edit the file, copy its path for an agent, or delete it. Carbon starts transcribing automatically by default. It says so with a notification that offers Stop and language switches, and with a red dot in the menu bar for the whole Meeting.

It ships as a signed, notarized DMG from https://carbon.alexandrejoly.me/download and updates itself through Sparkle.

## User Stories

### Detection and starting

1. As a person joining a Google Meet in Chrome, I want Carbon to notice the call without any setup, so that I don't have to remember to start anything.
2. As a person joining a Zoom, Teams or Webex call in the native app, I want Carbon to start even if I join muted, so that a call where I mostly listen is still captured.
3. As a person on a FaceTime call or an iPhone call relayed to the Mac, I want it treated as a Meeting, so that those conversations are kept too.
4. As a person using a dictation app, a voice assistant, a screen recorder or my editor's voice input, I want Carbon to ignore them, so that it never transcribes something that isn't a Meeting.
5. As a person, I want to add any app to the Ignored Apps list in Settings, so that I can silence an app Carbon gets wrong.
6. As a person, I want to remove an app from the Ignored Apps list, so that I can undo a mistake.
7. As a person with auto-transcribe on (the default), I want a notification "Transcribing in English" naming the Meeting and its Provider, so that I know Carbon is recording.
8. As a person, I want Stop on that notification to discard everything captured, so that I can refuse a recording in one click.
9. As a person who speaks several languages, I want one "Switch to <language>" action per other Meeting Language on the notification, so that I can fix the language immediately.
10. As a person with auto-transcribe off, I want a notification "<title>" / "<Provider> is using the microphone." with Transcribe and Transcribe in <language>, so that I choose each time.
11. As a person who ignores that offer, I want it to go away after 60 s, so that it doesn't pile up.
12. As a person who declines the offer, I want that app not to ask again for 10 minutes, so that one call doesn't nag me twice.
13. As a person, I want a "Never" choice on the offer that adds the app to Ignored Apps, so that I can stop an app permanently from the banner.
14. As a person, I want "Start Transcribing" in the menu bar menu, so that I can capture a Meeting Carbon didn't notice.
15. As a person, I want Carbon to match the Meeting to my calendar event, so that it gets the right title and participants.
16. As a person in a Meeting with no calendar event, I want a default title like "Meeting Oct 23, 9:15 AM", so that the file is still findable and I can rename it later.
17. As a person with two events overlapping my call, I want Carbon to prefer the event whose meeting link matches the Provider I'm on, so that the title is right.

### During a Meeting

18. As a person in a Meeting, I want the menu bar glyph's central dot red for the whole Meeting, so that I can see at a glance that Carbon is recording.
19. As a person in a Meeting, I want the menu bar menu to show "Transcribing "<title>"", the Provider and the start time, so that I know exactly what is being captured.
20. As a person in a Meeting, I want Stop in the menu bar menu to end the Meeting and keep it, so that I can end it early.
21. As a person in a Meeting, I want Discard in the menu bar menu to end it and keep nothing, so that I can drop a Meeting after the notification is gone.
22. As a person who realizes the Meeting is in French, I want to switch the Meeting Language from the menu bar menu and have it re-transcribed from the start, so that the whole Transcript is in the right language.
23. As a person switching AirPods on mid-call, I want capture to continue without a gap, so that I don't lose part of the Meeting.
24. As a person whose call app adds or removes helper processes mid-call, I want Carbon to keep capturing them, so that the far side isn't lost.
25. As a person already in a Meeting when a second call app starts a call, I want Carbon to keep the current Meeting and offer to switch, so that it never mixes two calls into one Transcript.

### Ending a Meeting

26. As a person leaving a Zoom, Teams or Webex call, I want the Meeting to end shortly after I hang up even if the calendar event runs on, so that Carbon doesn't record what comes next.
27. As a person leaving a browser call, I want the Meeting to end once the mic is released, 30 s have passed in silence and the event is over, so that a brief drop doesn't split it.
28. As a person in a browser call with no event, I want the Meeting to end after the mic is released and 10 minutes of silence, so that it doesn't stop on a pause.
29. As a person in back-to-back calls on the same app, I want each call to become its own Meeting, so that every file covers a single conversation.
30. As a person who forgot about a running call, I want a Meeting to end at 4 hours and start fresh if the call is still live, so that files stay a sane size.
31. As a person, I want a notification when the Transcript is ready, with an action to show it, so that I can check it right away.

### Speakers and Voice Prints

32. As a person, I want my own voice labelled "Me", so that I can tell my words from everyone else's.
33. As a person in a group call, I want the other voices split into Speaker A, Speaker B, Speaker C, so that I can follow who said what.
34. As a person in a 1:1 with a calendar event, I want the other person's name used for their lines, so that I don't have to name them.
35. As a person, I want to click an unnamed (blue) Speaker and pick a name from the event's attendees, so that naming takes one click.
36. As a person, I want "Other Name…" when the Speaker isn't an attendee, so that I can name anyone.
37. As a person who names a Speaker, I want Carbon to remember their voice, so that it names them in later Meetings automatically.
38. As a person, I want Carbon never to guess a name when it isn't confident, so that a wrong name never appears in my files.
39. As a person whose Speaker got split in two, I want to give both the same name, so that their lines read as one person.
40. As a person, I want renaming to change only the Speaker labels in the file, so that my own edits to the text are never touched.
41. As a person, I want to rename a Speaker again later, so that I can fix a wrong name.
42. As a person, I want to see every Voice Print in Settings, with how many Meetings it was heard in and when it was last heard, so that I know what Carbon remembers.
43. As a person, I want to delete one Voice Print, or all of them, so that I control what is kept about other people's voices.
44. As a person, I want to turn voice recognition off entirely, so that Carbon never stores a Voice Print.
45. As a person, I want Carbon to fall back to Me / Them when it can't tell the voices apart, so that I still get a Transcript.

### Summary (not in v1)

"On-device summary quality" dropped the Summary from v1. Stories 46–48 and 65 are kept for v1.1+ and are not built now. Story 49 holds as written.

46. As a person, I want a short Summary at the top of each Meeting file, with key points and next steps, so that I or my agent can see what happened without reading everything.
47. As a person in a French Meeting, I want the Summary written in French, so that it matches what was said.
48. As a person whose Mac can't summarize right now (Apple Intelligence off or its model still downloading), I want the Transcript written anyway and the Summary added when it becomes possible, so that I'm never blocked on it.
49. As a person, I want the Transcript file available as soon as the Meeting ends, before the Summary is done, so that I can paste it to an agent right away.

### Library and files

50. As a person, I want every Meeting as a Markdown file in a folder in Documents, organized by year, so that any tool can read it.
51. As an AI agent, I want frontmatter with the Provider, date, title, duration, language and participants, so that I can filter Meetings without parsing the body.
52. As an AI agent, I want every Transcript line to carry the Speaker and the time, so that a grep hit is self-explanatory.
53. As a person, I want to pick another folder for the Library in Settings and have existing Meetings moved there, so that I can keep it in a synced or work folder.
54. As a person, I want edits I make to a file to be kept, so that Carbon never overwrites my work.
55. As a person who renames or moves a file in Finder, I want Carbon to keep tracking it, so that my Library stays consistent.
56. As a person who deletes a file in Finder, I want it to leave the Library list, so that the app matches the folder.
57. As a person, I want the option to keep the audio of each Meeting, so that I can listen back; off by default.
58. As a person whose Mac crashed or whose Carbon quit mid-Meeting, I want the Meeting recovered at next launch, so that I don't lose the call.

### Main window

59. As a person, I want a global shortcut (⌥⌘C by default) to show and hide Carbon, so that I can reach it from anywhere.
60. As a person, I want the Meetings listed newest first, each with a bold title and "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1" in grey, so that I can scan them.
61. As a person, I want the full participant list on hover, so that I can see everyone without opening the Meeting.
62. As a person, I want to search titles, participants and the full text, with the matching line shown under the row, so that I can find what was said.
63. As a person, I want a Meeting's title, "date · length · Provider · Meeting Language" in the title bar, so that the panel stays focused on content.
64. As a person, I want participants shown as Mail-style tokens with Copy Email Address and New Email, so that I can follow up.
65. As a person, I want the Summary shown as Key points and Next steps notes above the Transcript, so that the recap comes first.
66. As a person, I want the Transcript shown as "Speaker · 0:19" above each Turn, so that it reads like a conversation.
67. As a person, I want Edit (↩, double-click or the context menu) to open the Meeting's Markdown in its own editor window with Speaker chips on top, so that I can fix mistakes.
68. As a person, I want Copy Path (⇧⌘C) to copy the file's absolute path, so that I can hand it to an AI agent.
69. As a person, I want Copy Markdown (⌘C) and Reveal in Finder, so that I can paste or open the file.
70. As a person, I want to give a Meeting a color dot, so that I can mark the ones that matter.
71. As a person, I want Delete (⌫) to ask first and then move the file to the Trash, so that a mistake is recoverable.
72. As a person, I want to rename a Meeting's title, so that Meetings without an event get a useful name.

### Menu bar, Settings, permissions

73. As a person, I want Carbon in the menu bar only, with no Dock icon, so that it stays out of the way.
74. As a person, I want the menu bar menu to offer Show Carbon, Reveal in Finder, the Meeting Language submenu, Check for Updates…, Settings… and Quit Carbon, so that everything is one click away.
75. As a person outside a Meeting, I want the Meeting Language submenu to set the default for the next Meeting, so that I can prepare for a French call.
76. As a person, I want to choose which Meeting Languages I use and which is the default, so that the switcher only shows mine.
77. As a person, I want the system permission prompts at first launch and nothing else, so that there's no onboarding to sit through.
78. As a person who denied a permission, I want Settings › Permissions to show what's missing with a button to open System Settings, and the menu bar menu to flag it, so that I can fix it.
79. As a person, I want Carbon to launch at login (on by default), so that it never misses a Meeting.
80. As a person, I want Carbon to update itself, with a toggle for automatic checks, so that I always run the latest version.
81. As a person using VoiceOver or only the keyboard, I want every control named and reachable, so that I can use Carbon fully.
82. As a person, I want the About tab to credit FluidAudio's CC BY 4.0 models and link the privacy page, so that licenses and privacy are clear.

### Download and release

83. As a visitor to carbon.alexandrejoly.me, I want "Download Carbon for Mac" to give me the latest signed DMG, so that installing takes one drag.
84. As a person opening Carbon for the first time, I want no Gatekeeper warning, so that I trust it.
85. As the author, I want to push a version tag and have the app built, signed, notarized, uploaded and offered to every user through Sparkle, so that releasing takes no manual steps.
86. As the author, I want the vendor strings that Detection depends on to be data shipped with each update, so that a Zoom or Teams change is fixed by a release, not a rewrite.

## Implementation Decisions

### Platform and project

- Swift 6, SwiftUI, macOS 26 minimum, Apple silicon only (`arm64`). `SpeechTranscriber.isAvailable` is checked at launch; without it Carbon shows one alert and quits.
- Menu bar agent app (`LSUIElement`), not sandboxed: process taps, the responsible-PID lookup and `~/Documents/Carbon` need it. Hardened runtime is on for notarization, with the audio-input entitlement. Usage strings for microphone, system audio capture and calendar.
- Bundle ID `me.alexandrejoly.carbon`. The app icon is `Design/Carbon.icon` (Icon Composer document) used as the target's App Icon, with no `AppIcon` asset catalog. The menu bar glyphs come from the icon board's final SVGs: an 18 pt template image when idle, and a non-template image with a systemRed dot while recording.
- Dependencies: FluidAudio (pinned at the version the prototypes ran, 0.17.7, Apache-2.0 code, CC BY 4.0 weights) and Sparkle 2. Everything else is Apple frameworks.
- Code is split into one `CarbonCore` Swift package and the app target. `CarbonCore` holds every rule and every file format and imports no AppKit or SwiftUI. The app target holds the UI and the adapters to Core Audio, EventKit, IOKit, Speech, FoundationModels, FluidAudio, UserNotifications and Sparkle.

### Modules

Each module is deep: a small interface over a lot of behavior.

- **Detector** (pure, in `CarbonCore`). A state machine. In: timestamped signal snapshots (mic holders with responsible-app bundle ID, call assertions with `AssertionId`, calendar events in window, live Meeting state, Ignored Apps, auto-transcribe setting). Out: commands such as `start(app, event?)`, `offer(app, event?)`, `end(meetingId, reason)` and `split(meetingId)`. It encodes every rule in "Power assertions as a Detection signal":
  - Start: the mic held ≥ 15 s by a non-ignored app, or a call assertion confirmed on 2 consecutive 3 s polls. With auto-transcribe on that starts a Meeting, otherwise it offers one. An Event or a browser WebRTC assertion never starts anything.
  - Stop with a call assertion: assertion and mic released 15 s, then 30 s of silence.
  - Stop otherwise: mic released + 30 s of silence + Event ended; with no Event, mic released + 10 min of silence.
  - Cap: 4 h, then the start rules run again.
  - Back-to-back: the three triggers in issues/17, with a 5 s cooldown.
  - Offers: 60 s timeout, a decline mutes the app for 10 min, "Never" adds it to Ignored Apps.
  - Always ignored: Carbon itself and `com.apple.CoreSpeech`. CoreSpeech never counts as a mic release or a hold.
  - **(new) Overlapping Meetings.** At most one live Meeting. While one is live, a start signal from a *different* Meeting App never starts a second Meeting. It posts "<Provider or app> is using the microphone" with **Switch to <app>**, which ends the current Meeting normally and starts one on the other app with the usual cooldown waived. When the live Meeting's own app releases, its stop rules apply, and the other app's start rules are evaluated after the 5 s cooldown as for back-to-back.
- **SignalSampler** (app adapter). Lists processes through `kAudioHardwarePropertyProcessObjectList`, with property listeners on `kAudioProcessPropertyIsRunningInput` / `IsRunningOutput` and a 1 s poll as backstop. It never caches process object IDs. It resolves each process to its owner app through the responsible PID (`responsibility_get_pid_responsible_for_pid` via `dlsym`), falling back to the outermost `.app` path. It polls `IOPMCopyAssertionsByProcess()` every 3 s while the mic is held or an Event is in its window. It logs each unmatched mic holder and each call or WebRTC assertion once, to a diagnostic log the person can reveal from Settings › About.
- **Vendor table** (data in `CarbonCore`, shipped in the bundle). Call-assertion matchers (Zoom, Teams "call in progress", Webex "On a call", modern and legacy type spellings), the initial Ignored Apps from issues/17, the never-ignored list (`com.apple.avconferenced`, `com.apple.WebKit.GPU`, `com.apple.TelephonyUtilities.callservicesd`, browser and Electron helpers), and the bundle ID → Provider and link host → Provider maps. A release changes it; the person's additions live in Settings, not in the table.
- **EventMatcher** (pure). In: EventKit events reduced to plain values (title, start, end, `url`, `location`, `notes`, attendees with name, `mailto:` email, type, `isCurrentUser`, organizer), the Meeting App and the start time. Out: the best Event, or none. Window: start −5 min to end +15 min, preferring an Event whose parsed link host maps to the same Provider as the Meeting App. It parses links from `url`, `location`, then `notes`. Participants are person attendees plus the organizer, without the current user, deduplicated by email. A `mailto:` that is nil is skipped, never force-read.
- **Provider resolution** (pure). A native app's bundle ID wins (Zoom, Microsoft Teams, Webex, FaceTime, Slack, Discord…). Otherwise the matched Event's link host (`meet.google.com` → Google Meet…). Otherwise the Meeting App's display name ("Google Chrome").
- **Capture** (app adapter). One Core Audio process tap on every process whose owner is the Meeting App. When the Meeting App's processes change, it updates `kAudioTapPropertyDescription` on the running tap; it rebuilds the tap-only aggregate and the mic capture only when the device list changes. The mic is captured separately as the Me stream.
  - Fallback: while a Meeting App process reports `IsRunningOutput` and the tap has had no callbacks for 5 s, Capture re-resolves the processes, then switches to a global tap excluding Carbon.
  - Full-rate zeros are silence. Permission comes from `TCCAccessPreflight("kTCCServiceAudioCapture")` before each Meeting, never inferred from audio.
  - Both streams are converted to the analyzer format. Each one feeds its SpeechTranscriber and is appended to an on-disk CAF file in the Meeting's in-progress folder (Recovery below), flushed every 5 s.
- **Transcriber** (app adapter behind a `CarbonCore` port). One `SpeechAnalyzer` + `SpeechTranscriber` per stream in the Meeting Language, with `volatileResults` and `audioTimeRange`, fed straight from Capture. No post-pass, no `contextualStrings`, no name boosting.
  - At launch and when Meeting Languages change, it reserves every chosen locale with `AssetInventory`.
  - At Meeting start it checks the asset status and downloads the asset again if needed.
  - A language switch starts a new analyzer pair on the new locale. It feeds the recorded CAF files from the start in batch, then continues live; batch and live output are word-for-word identical (issues/14).
  - Out: final words per stream with text, start and end time.
- **Diarizer** (app adapter behind a port). FluidAudio `OfflineDiarizerManager` (community-1), clustering threshold 0.6, on the Them CAF after the Meeting ends. It runs in a separate helper process under a watchdog: a timeout of 2 min + 10 s per audio minute, one retry in a fresh process, then fallback. Out: segments (start, end, cluster) and, per cluster, the L2-normalized centroid embedding and speech seconds. Any failure gives `nil`, which means the Me / Them fallback.
- **TranscriptBuilder** (pure, in `CarbonCore`). In: Me words, Them words, diarization segments or nil, the Speaker → label map. Out: the Turns and the rendered `## Transcript` body. It encodes every rule in "Transcript body format in Markdown": per-word attribution (most-overlapping segment, else nearest within 1 s, else the previous Them word's Speaker); clusters lettered by first word; sentences end at `.?!…`, a ≥ 1.5 s pause or a Speaker change, ordered across streams with Me first on ties; a new Turn on a Speaker change, ≥ 10 s of silence or a 90 s monologue; `m:ss` / `h:mm:ss` timestamps truncated to the second; capitalized first letter; Markdown escaping; reserved `Me` / `Them`; 1:1 naming. It also provides the anchored header parser `^\*\*(name)\*\* \[(time)\] ` that the app uses to display Turns and that rename write-back relies on.
- **VoicePrintMatcher** (pure). In: the clusters' centroids and speech seconds, the stored Voice Prints and the current embedding model id. Out: a cluster → Voice Print assignment.
  - Only clusters with ≥ 10 s of speech are matched.
  - A match needs a cosine distance < 0.30 and a margin ≥ 0.10 over the runner-up.
  - Each Voice Print matches at most one cluster per Meeting: greedy by smallest distance.
  - Prints with another model id are ignored.
  - Each best distance is logged to the diagnostic log, matched or not, so dogfooding can widen the cutoff.
- **VoicePrintStore** (**new**, in `CarbonCore`). Stored apart from `meetings.json` so that deleting voices is one clear action, in `~/Library/Application Support/Carbon/voiceprints.json`:

  ```jsonc
  {
    "version": 1,
    "prints": [{
      "id": "UUID",
      "name": "Sam Rivera",
      "email": "sam@example.com",          // optional, from the attendee picked
      "model": "fluidaudio/community-1@<weights revision>",
      "centroid": "<base64 Float32 × 256, L2-normalized>",
      "recent": ["<base64 Float32 × 256>"], // at most 3
      "meetings": 4,
      "createdAt": "…", "lastHeardAt": "…"
    }]
  }
  ```

  - **Enroll**: naming a Speaker whose cluster has ≥ 10 s of speech creates or updates the print with that name. A shorter cluster gets the name but no print, and the menu says "Not enough speech to remember this voice."
  - **Update**: centroid + 3 recent, and only from auto-matched or person-confirmed Speakers. The centroid is the normalized mean of the original centroid and the recent ones.
  - **Rename**: renaming an auto-matched Speaker to another name moves that Meeting's link to the other print; it never edits the first print's name.
  - **Delete**: deleting a print removes it and clears `voicePrintId` in every Meeting that links it. The names already written in Markdown files stay: they are the person's text.
  - **Switch**: "Recognize voices" (on by default) in Settings › Voice Prints. Off, Carbon neither matches nor enrolls, and asks once whether to delete the existing prints.
  - The file never leaves the Mac, is not in the Library folder, and is excluded from the timestamped backups.
- **Summarizer** (app adapter behind a port; a no-op in v1, see below).
- **Library** (in `CarbonCore`). Owns the Markdown files and `meetings.json`. Its interface: `create(meeting, transcript)`, `insertSummary(id, summary)`, `renameSpeaker(id, label, name)`, `rename(id, title)`, `setColor`, `delete(id)`, `save(id, editedMarkdown)`, `reconcile()`, `search(query)`, and an observable list of Meetings. Details under "Library and `meetings.json`".
- **Recorder** (in `CarbonCore`, the orchestrator). In: Detector commands and the ports (Capture, Transcriber, Diarizer, Summarizer, EventMatcher input, clock). Out: Library writes and UI state (`idle`, `live(meeting)`, `finishing(meeting)`). It runs the Meeting lifecycle: in-progress folder → live transcription → end → diarization → Voice Print match → TranscriptBuilder → Library create → Summary → Library insertSummary → cleanup. It is the main test seam (see Testing).
- **Updater** (app adapter). Sparkle `SPUStandardUpdaterController`. Its feed URL comes from Info.plist, its automatic-check toggle is bound to Settings, and its menu item is "Check for Updates…".

### Library and `meetings.json` (new)

- **Folder.** `~/Documents/Carbon/YYYY/YYYY-MM-DD-slug.md`, as in ADR-0002.
  - Slug: the title lowercased, ASCII-folded, non-alphanumerics → `-`, trimmed to 60 characters at a word boundary. On a collision Carbon adds `-2`, `-3`…
  - The file name is fixed at creation. Renaming the title changes the frontmatter only, so a path already handed to an agent keeps working.
  - Changing the folder in Settings moves the whole Library, after a confirmation that says how many files will move.
- **Frontmatter.** `provider`, `id`, `date` (ISO 8601 with offset, Meeting start), `title`, `duration` (`m:ss` or `h:mm:ss`, as in the samples), `language` (BCP 47, e.g. `en-US`, added so agents know the language) and `participants` (`Name <email>`, or `Name` alone).
  - `id` is Carbon's Meeting UUID, the join key with `meetings.json`; the transcript-format samples' Meet code was a placeholder.
  - The Provider's meeting code, when parsed from the Event link, lives in `meetings.json`.
  - Participants are the matched Event's people, plus any name given to a Speaker that isn't already listed.
- **Body.** `## Summary` (when present), then `## Transcript`. The headings are always English: they are structure, not prose.
- **Write order.** The file is created once the Transcript is final, after diarization or its fallback, with Voice Print names already in. The Summary is inserted above `## Transcript` when it is ready, and only while the line `## Transcript` still exists in the file.
- **`meetings.json`.** In `~/Library/Application Support/Carbon/`. It is written atomically (temp file + rename). Before the first save of each launch, and then at most once a day, Carbon copies it to `Backups/meetings-<ISO timestamp>.json` and keeps the 14 newest (Copper's pattern).

  ```jsonc
  {
    "version": 1,
    "meetings": [{
      "id": "UUID",
      "file": "2026/2026-10-27-remote-control-kickoff.md", // relative to the Library folder
      "title": "Remote control kickoff",
      "start": "2026-10-27T10:00:00-04:00", "end": "…",
      "language": "en-US",
      "provider": "Google Meet",
      "providerMeetingId": "abc-defg-hij",     // parsed from the Event link, optional
      "meetingApp": "com.google.Chrome",
      "calendarEventId": "<calendarItemExternalIdentifier>", // optional
      "participants": [{ "name": "Sam Rivera", "email": "sam@example.com" }],
      "speakers": [{
        "label": "Speaker A",                  // label in the Markdown headers right now
        "cluster": "A",                         // stable letter from the diarization
        "name": "Sam Rivera",                   // null while unnamed
        "voicePrintId": "UUID",                 // null when no print
        "match": "auto" | "user" | "attendee1to1" | null,
        "distance": 0.12,                       // best Voice Print distance, logged
        "speechSeconds": 312
      }],
      "transcript": "speakers" | "fallback",
      "summary": "done" | "pending" | "unavailable" | "failed" | "off",
      "color": "red" | null,
      "audio": "2026/2026-10-27-remote-control-kickoff.m4a", // only with Keep audio
      "writtenHash": "<sha256 of the file as Carbon last wrote it>"
    }],
    "deleted": [{ "id": "UUID", "deletedAt": "…" }]
  }
  ```

- **Local Edit** = the file's hash differs from `writtenHash`. Every Carbon write after creation is surgical: inserting the Summary, rewriting the Speaker header lines on a rename, changing the frontmatter `title`. The person's text is never rewritten. After a surgical write, Carbon refreshes `writtenHash` only if the file matched it before; otherwise it stays a Local Edit.
- **Reconcile.** On launch and on FSEvents in the Library folder:
  - A file missing at its `file` path is found again by frontmatter `id` anywhere in the Library, and its path is updated.
  - A file not found anywhere becomes a Deleted Meeting.
  - A Markdown file with an unknown `id` is ignored: the person's own notes can live in the folder.
- **Delete** moves the Markdown file and its kept audio to the Trash, removes the entry and adds a tombstone to `deleted`. Tombstones keep a recovered or re-found file from reappearing.
- **Search** is in memory, built from the files at launch and refreshed by FSEvents. It is case- and diacritic-insensitive over title, participants and body. The sidebar shows the first matching line under the row.
- **Keep audio** (off by default). At the end of a Meeting the two CAF files are encoded to one stereo AAC `.m4a` next to the Markdown file (Me left, Them right). Off, they are deleted once the Transcript is written.

### Recovery after a crash (new)

- Each live Meeting has an in-progress folder in `~/Library/Application Support/Carbon/InProgress/<id>/` holding `state.json` (start, Meeting App, matched Event, Meeting Language, auto/manual) and the two CAF files flushed every 5 s. Nothing is written to the Library until the Meeting ends.
- At launch, an in-progress folder means the Meeting was interrupted. Carbon finishes it:
  - It transcribes the CAF files in batch in the saved Meeting Language, then runs diarization, Voice Prints, Library create and Summary, as for a normal end.
  - The end time is the end of the recorded audio.
  - It notifies "Recovered "<title>" after Carbon quit unexpectedly."
  - Unreadable audio is discarded with a notification instead of a silent loss.
- A Meeting the person stopped with Stop (discard) or Discard deletes its folder at once.
- If recovery itself crashes twice on the same folder (counted in `state.json`), the folder is moved to `InProgress/Failed/` and Carbon stops retrying.

### Summary (dropped from v1)

**Verdict of issues/10: drop.** Apple Foundation Models has an 8,192-token context on macOS 27. On the 18 AMI, ICSI and SUMM-RE Meetings it scored a mean usefulness of 2.7 in English and 2.1–2.9 in French, against a bar of 3. Each Summary carried 1.4–2.4 wrong or unsupported items, mostly invented next steps, and 1 Meeting in 18 hit a guardrail false positive. Speed passed (≤ 3 min per hour of audio).

**v1:** the Summarizer port gets a no-op adapter and `summary` is `off` for every Meeting. `## Summary` is never written, and the Meeting panel shows no notes section. Nothing else changes: the port and the `summary` field stay, so a later model can be plugged in. As built (ticket 18): `Summarizer.summarize(transcript:language:) async throws -> Summary?` in `CarbonCore/Ports.swift`, where nil means off. `NoSummarizer` always answers nil. The Recorder calls it after `library.create`, so the file is already on disk, and ignores both its answer and any error it throws. `Library.insertSummary`, the rendering and the retry are not built; they land with the v1.1 adapter, on `writeSurgically`.

The design below is kept as the starting point for v1.1+, when the summary-eval harness passes on a newer model. Map-reduce was the better variant: fewer wrong items, and less noise in French.

- Apple Foundation Models (`SystemLanguageModel.default`), chunk-then-merge inside the model's context (`contextSize`, 8K on macOS 27), written in the Meeting Language.
  - Guided generation (`@Generable`) with two fields, key points and next steps (with the owner when known), greedy sampling and a fresh session per pass.
  - The input is the rendered Transcript, one Turn per line.
  - The chunk budget comes from `tokenCount(for:)`: context − output reserve − prompt overhead.
  - Chunks break at line boundaries.
- Variant: map-reduce, with a final 3–8 key points (it beat Minute's rolling deltas). The port: `summarize(transcript, language) async throws -> Summary { keyPoints, nextSteps }`.
- Written as:

  ```markdown
  ## Summary

  ### Key points

  - …

  ### Next steps

  - …
  ```

  When nothing was agreed, the "Next steps" heading is left out.
- Availability: if the model is unavailable (`modelNotReady`, Apple Intelligence off, unsupported device or language), the Meeting is marked `summary: unavailable`. Carbon retries pending and unavailable Meetings when `availability` turns available, oldest first, one at a time.
- Failures: a guardrail violation, a context overflow, or invalid output after one repair pass marks the Meeting `failed`, with no retry. The panel then shows "No Summary for this Meeting." in secondary text.

### UI

As validated in "Main window, menus and notification mock" (issues/12), which wins over the UI part of the product design. Summary:

- **Main window**: native split view. Sidebar: "Search Meetings" field, then rows (color dot, bold title, grey "date · length · participants" with full participants on hover), newest first.
- **Meeting panel**: title and "date · length · Provider · Meeting Language" in the title bar; Edit and More (⋯) as separate toolbar buttons. Body: participant tokens, then the Transcript (the Summary notes go above it once a Summary ships, not in v1) as "Speaker · 0:19" over each Turn, with tabular digits. Every Speaker except Me has a chevron menu (attendees + "Other Name…"); unnamed ones are blue.
- **Editor window**: the whole Markdown file in a plain-text editor with Speaker chips on top. Save (⌘S) writes the file. Closing with unsaved changes asks first. An editor save is a Local Edit.
- **Menus**:
  - Context menu: Copy Path ⇧⌘C, Copy Markdown ⌘C, Reveal in Finder, Edit ↩, color palette, Delete ⌫.
  - More: Copy Path, Copy Markdown, Reveal in Finder, Delete.
  - Delete confirmation: "Delete "<title>"?", with the button "Delete Meeting".
- **Title rename (new)**: double-click the title in the title bar, or press Rename… in More and the context menu.
- **Menu bar menu**:
  - While live: "Transcribing "<title>"", "<Provider> · since <time>", Stop, Discard.
  - Otherwise: Start Transcribing on top.
  - Then: Show Carbon ⌥⌘C, Reveal in Finder, Meeting Language ▸, Check for Updates…, Settings… ⌘,, Quit Carbon ⌘Q.
  - A missing permission adds "Carbon needs <permission> access…" on top, which opens Settings › Permissions.
- **Notifications**:
  - Start: "Transcribing in <language>", body "<title> · <Provider>", actions Stop and one "Switch to <language>" per other Meeting Language.
  - Offer: "<title>", "<Provider> is using the microphone.", actions Transcribe, Transcribe in <language>, Never.
  - Ready **(new)**: "<title>", "Transcript ready.", action Show.
  - Recovery **(new)**: as above.
  - Overlap **(new)**: "<app> is using the microphone.", body "Carbon is still transcribing "<title>".", action Switch to <app>.
- **First launch (new)**: no window and no onboarding. Carbon asks the system prompts in a row (Notifications, Calendar full access, Microphone, System Audio Recording), registers launch at login, and puts the glyph in the menu bar. Later launches stay silent.
- **Settings (new, final layout)**: a native `TabView` settings window with six tabs:
  - **General**: "Transcribe Meetings automatically" (on), with the footnote "Carbon shows a notification and a red dot whenever it transcribes. You're responsible for telling others they're being recorded." "Keep audio after transcribing" (off). "Library folder" with the path and "Change…". "Show Carbon" with a shortcut recorder (⌥⌘C). "Launch at login" (on). "Check for updates automatically" (on).
  - **Languages**: a checklist of the locales `SpeechTranscriber` supports, filtered to English and French variants for the US-first launch plus any the system offers. "Default language" picker among the checked ones. Each row shows its download state ("Downloading…", "Ready").
  - **Ignored Apps**: the person's added apps, with + (app picker) and −, plus "Carbon also ignores dictation apps, screen recorders and voice assistants it knows." Built-in entries are not listed.
  - **Permissions**: Microphone, System Audio Recording, Calendar and Notifications, each "Allowed" with a green check or "Not allowed" with "Open System Settings".
  - **Voice Prints**: the "Recognize voices" toggle. A list of name, "Heard in 4 Meetings · last Oct 27" and a delete button per row; "Delete All…" asks first. The note: "When you name a Speaker, Carbon remembers their voice and recognizes it in later Meetings. Voice Prints are stored only on this Mac, and Carbon never sends them anywhere."
  - **About**: version; "Speaker diarization by FluidAudio. Models licensed CC BY 4.0." with a link; links to the privacy page and the website; "Reveal Diagnostic Log".
- **Accessibility pass (new, acceptance criteria)**:
  - Every control has an accessible name. The Speaker menu says "Speaker A, unnamed, rename" or "Sam Rivera, rename".
  - Turns read as "Speaker, time, text".
  - The whole window works from the keyboard: ↑↓ in the list, ↩ to Edit, ⌫ to Delete, ⌘F to Search, Tab through the panel.
  - Light and dark mode are both checked, with secondary rather than tertiary text for contrast.
  - Color is never the only cue: the chevron marks Speakers, and the color dot is announced.
  - Reduced motion is honored.

### Distribution and release pipeline

- **Signing**: Developer ID Application certificate on the author's existing Apple Developer account, hardened runtime, timestamped signature. The DMG is signed with the same identity.
- **Notarization**: `xcrun notarytool submit --wait` with an App Store Connect API key, then `stapler staple` on the DMG.
- **Versioning**: a tag `vX.Y.Z` sets `CFBundleShortVersionString`; `CFBundleVersion` is the Action's run number, increasing, which is what Sparkle compares.
- **GitHub Action** (in `AlexDemzz/carbon`, on `v*` tags, macOS 26 runner):
  1. import the Developer ID `.p12` into a temporary keychain;
  2. `xcodebuild archive` and export with the Developer ID method;
  3. run the `CarbonCore` tests, the appcast script tests and the release Worker tests;
  4. build `Carbon-X.Y.Z.dmg` with `hdiutil`, holding the app and an Applications symlink;
  5. sign, notarize and staple the DMG;
  6. sign the DMG with Sparkle's `sign_update` (EdDSA private key from secrets);
  7. regenerate `appcast.xml` from the previous one plus this item (release notes from the tag's annotation);
  8. deploy the release Worker from `worker/` with `wrangler deploy`;
  9. upload `releases/Carbon-X.Y.Z.dmg`, then `appcast.xml`, then `latest.json` (`{ "version", "build", "file" }`) to the R2 bucket `carbon-releases` with `wrangler`.
  10. publish a GitHub Release for the tag with the DMG attached and the tag's annotation as notes (`gh release create --verify-tag` with `GITHUB_TOKEN`, so the job has `contents: write`); a rerun re-uploads the DMG to the existing release with `--clobber`.

  Uploading the DMG first means a half-failed release never points at a missing file.

  **Dry run**: a run that is not on a `v*` tag (e.g. started by hand), or that is missing any signing secret, builds unsigned, runs the tests, builds the DMG and uploads it as an Action artifact. Every signing, notarization, Worker deploy, upload and GitHub Release step is skipped and reported.
- **Secrets**:
  - `DEVELOPER_ID_P12` (base64) and `DEVELOPER_ID_P12_PASSWORD`;
  - `NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`;
  - `SPARKLE_ED_PRIVATE_KEY`;
  - `CLOUDFLARE_API_TOKEN` (Workers Scripts Edit on the account, Workers Routes Edit on the `alexandrejoly.me` zone, R2 Edit) and `CLOUDFLARE_ACCOUNT_ID`.

  The Sparkle public key goes in Info.plist as `SUPublicEDKey`, and `SUFeedURL` is `https://carbon.alexandrejoly.me/appcast.xml`.
- **Serving**: a standalone release Worker `carbon-releases`, in this repository's `worker/` (its own `package.json`, `wrangler.jsonc` and tests), with an R2 binding `RELEASES` → `carbon-releases`. All Carbon code lives in the carbon repository; the alexandrejoly.me monorepo only holds the landing page, whose Worker `carbon` owns `carbon.alexandrejoly.me` as a Custom Domain. The release Worker takes three zone routes on `alexandrejoly.me` (`carbon.alexandrejoly.me/download`, `/appcast.xml` and `/releases/*`), which run ahead of the Custom Domain Worker; any other request it gets is passed on with `fetch(request)`:
  - `GET /download` → 302 to `/releases/<file from latest.json>`, `Cache-Control: no-store`, so the site's `DOWNLOAD_URL = "/download"` stays as is.
  - `GET /appcast.xml` → the R2 object, `application/rss+xml`, `Cache-Control: max-age=300`.
  - `GET /releases/<name>.dmg` → the R2 object streamed with `application/x-apple-diskimage`, `Content-Disposition: attachment`, immutable caching, `Range` supported, 404 for unknown names.

  The bucket stays private: the release Worker is its only reader. Each release redeploys the release Worker (step 8), never the landing Worker.
- **Vendor table updates** ship inside app releases. There is no separate remote config fetch, so the app makes no network calls beyond Sparkle's.

## Testing Decisions

- **What a good test is.** It drives Carbon through a public interface with realistic inputs and checks what a person or an agent would see: the Markdown file, `meetings.json`, the voice prints file, and the Detector's commands. No asserting on private state or call order, and no tests that restate the implementation (tautological tests are banned).
- **Main seam: Recorder in `CarbonCore`**, the highest point where Carbon is still Apple-framework-free. Its ports are the test boundary:
  - a scripted **signal source** (timestamped mic holders, call assertions, Events, clock);
  - an **audio source** that plays Me/Them WAVs;
  - a **Transcriber** that replays recorded SpeechTranscriber words;
  - a **Diarizer** that replays recorded FluidAudio segments and embeddings, or fails or hangs on demand;
  - a **Summarizer** that returns a fixed Summary, throws "unavailable", or throws a guardrail error;
  - a **Library** on a temporary folder.

  A test is "this scripted afternoon of signals and audio → these files on disk". Scenarios: auto-start and stop per Provider type, back-to-back split, the 4 h cap, an overlapping second app, Stop/Discard leaving nothing, a language switch re-transcribing from the start, diarization timeout → Me/Them file, a Voice Print auto-match naming a Speaker in the first write, a rename after a Local Edit, Summary pending then inserted, a crash (kill between flushes) then recovery at the next launch.
- **Pure deep modules tested at their own interface**, because their rules are dense and stateless:
  - Detector: signal sequences → commands, one test per rule in issues/17.
  - TranscriptBuilder: golden files.
  - VoicePrintMatcher: threshold, margin, one-per-Meeting, model mismatch.
  - EventMatcher: Google, Exchange and iCloud event shapes from `docs/research/eventkit-conference-data.md`, nil `mailto:`, a missing organizer.
  - Library: reconcile, surgical writes, slug collisions, backups.
- **Prior art.**
  - The transcript-format prototype's real AMI ES2004a words and diarization, and its three sample files (diarized, renamed, fallback), become TranscriptBuilder's golden fixtures; `render.py` is the reference implementation to port.
  - The diarization-eval Voice Print pairs and distances (64 same-person, 2,492 impostor pairs) give VoicePrintMatcher its boundary cases.
  - The ticket 17 rule list is the Detector test table.
- **Fixtures** are small and committed: a few minutes of words and segments. The full 28-Meeting test set stays outside the repo in `~/Datasets/carbon-test-set`; the prototypes' quality scripts (`score.py` in transcription-eval, diarization-eval and summary-eval) stay manual, AFK checks rerun when an engine or threshold changes, not part of CI.
- **Adapters** (Capture, SignalSampler, Transcriber, Diarizer, Summarizer, Sparkle) get no unit tests. They are checked by dogfooding the signed app and by the diagnostic log. The tap must be validated from the signed app, never from a terminal, because the terminal becomes the responsible process.
- **Release pipeline**: the Action runs `CarbonCore` tests before signing. The release Worker's tests (`worker/`, Vitest + Miniflare via `getPlatformProxy`) cover the three routes against a local R2: `/download` redirect, appcast content type, a range request, a 404, and requests passed on to the landing Worker.
- **Not hand-tested** (map Notes): no hand-recorded Meetings and no hand-run Detection checks. Real-usage tuning comes from the author dogfooding the built app and sending the diagnostic log.

## Out of Scope

- Hand-recorded Meetings and hand-run Detection tuning ("Detection and auto-stop rules on real usage", the hand part of "Real meeting test set").
- A Parakeet post-pass (including for phone-band audio), attendee-name boosting, automatic or mid-Meeting language switching, echo cancellation, participant names via Accessibility or a browser extension, syncing Provider transcripts or Gemini summaries, multiple accounts, an on-device Summary ("On-device summary quality"): v1.1+.
- Google Drive / Meet API sync with OAuth (ADR-0001, superseded by ADR-0003).
- Isolating one browser tab's audio: other audio of the Meeting App lands in Them (issues/05).
- Intel Macs, macOS before 26, Mac App Store distribution, localization of the UI (English only).
- Landing page content (live already). The privacy page's content is drafted in Further Notes, but building it belongs to the website repo.
- Real-time display of the Transcript during a Meeting, and writing partial files before a Meeting ends.

## Further Notes

- **Summary dropped** by "On-device summary quality". Re-run `prototypes/summary-eval` (`run-all.sh`, `score.py`, `judge-rubric.md`, the same bar) when Apple ships a stronger on-device model.
- **Weak cases to watch while dogfooding** (from the resolved tickets):
  - phone-band dial-in audio (SpeechTranscriber drops passages);
  - overlap-heavy talk (missed by diarization);
  - a third person who talks little (two-cluster outcome);
  - Voice Print misses across headsets;
  - Zoom/Teams assertion behavior between back-to-back calls;
  - Slack huddles, Discord, Safari's mic holder;
  - Siri and dictation daemons.

  The diagnostic log records unmatched mic holders, assertions seen and Voice Print best distances, so each of these can be tuned from what the author sends back.
- **Privacy page content** (for carbon.alexandrejoly.me/privacy):
  - Carbon processes audio only on the Mac. It deletes the audio after transcribing unless the person turns on "Keep audio".
  - Transcripts and Summaries are plain files in the person's chosen folder. Voice Prints are numeric voice signatures stored only on the Mac and deletable in Settings.
  - Carbon has no account, no analytics and no server. The only network traffic is Sparkle checking `appcast.xml` and downloading updates, plus Apple's own model and speech-asset downloads.
  - The person is responsible for consent: some US states require all-party consent, and so does France (art. 226-1 du code pénal).
  - The author never receives any audio, Transcript or Voice Print. That is also why biometric-data collection rules aimed at services that hold such data don't apply to the author. The page should still say it plainly.
- **Private API use**: `responsibility_get_pid_responsible_for_pid`, `TCCAccessPreflight` and `TCCAccessRequest` are loaded through `dlsym`, as shipped by FineTune, pasrom, AudioCap and Hyprnote. `TCCAccessRequest` shows the System Audio Recording prompt at first launch. All three are fine for Developer ID distribution and all could break on an OS update. If the lookup is missing, capture falls back to the `.app` path, permission falls back to showing "Unknown" in Settings › Permissions, and the prompt falls back to appearing with the first tap.
- **Steps that need the author** are in the morning checklist: the Developer ID certificate, the App Store Connect API key and the GitHub secrets.
- **Vocabulary**: this spec uses `GLOSSARY.md` terms throughout. No new domain terms; "in-progress folder" and "diagnostic log" are implementation words, not domain language.
