# Carbon v1 product design

Type: grilling
Status: resolved
Blocked by:

## Question

What is Carbon v1: what it captures, how, where it stores it, what the UI and distribution look like?

## Answer

Resolved in a live grilling session on 2026-10-27. Vocabulary: `GLOSSARY.md`. Hard-to-reverse choices: `docs/adr/0002-json-index-plus-markdown-library.md`, `docs/adr/0003-local-capture-instead-of-provider-sync.md` (supersedes 0001).

**Product.** Free, public macOS app, US market first, English-only UI. Detects the person's Meetings on any Provider (Meet, Zoom, Teams…) and transcribes them fully on-device so an AI agent can read them. No Google OAuth, no cloud. Prefer native Apple frameworks wherever one exists.

**Detection & capture.**
- Detection = which process holds the mic (`kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput`), ~15 s threshold, ignored-apps list, matched to calendar events read through EventKit (no Google sign-in). Zoom/Teams/Webex in-call power assertions added as a second signal; rules, thresholds and Ignored Apps in "Power assertions as a Detection signal" (issues/17).
- Auto-transcribe **on by default**: native notification "Transcribing in <language>" with **Stop** (discards captured audio) and **Switch language ▸**; red dot on the menu bar icon for the whole Meeting. When auto is off: native banner asking to transcribe. No first-launch onboarding screen.
- Audio: Core Audio process tap on the meeting app's whole bundle/process family; fall back to a global system-audio tap if the targeted tap is silent. Only the "system audio recording" permission (no Screen Recording).
- Auto-stop when all hold: mic released + 30 s silence + calendar event ended; no event → mic released + 10 min silence. Manual Stop always available. A Meeting caught by a call assertion stops on its release without waiting for the event end (issues/17).
- No echo handling in v1 (native voice processing ducks call audio). Audio deleted after transcription; setting to keep it.
- Meetings without a calendar event are transcribed with a default title ("Meeting Oct 27, 14:02"), renamable.

**Transcription.**
- Apple SpeechAnalyzer/SpeechTranscriber, one analyzer per stream (mic, app audio).
- Meeting Language: system locale by default, default overridable in Settings. No automatic detection, no dual transcription. Hot-swap from the menu bar menu (languages from Settings, current one checked) or from the start notification; switching **re-transcribes from the start** of the Meeting (audio is kept until the Meeting ends).
- Speakers: "Me" (mic) / "Them" (app audio) live. After the Meeting, FluidAudio offline diarization splits Them into Speaker A/B/C. In a 1:1 calendar event, Them = the other attendee. Renaming a Speaker (picked from event attendees) stores a Voice Print; later Meetings recognize it automatically. Voice Prints stay local, deletable in Settings. CC-BY attribution in About. Ships in v1 only if quality on real calls holds (else Me/Them only).
- Summary: Apple Foundation Models, chunked (4K context), at the top of the file, in the Meeting Language.

**Library.**
- `~/Documents/Carbon/YYYY/YYYY-MM-DD-slug.md`, frontmatter `provider`, `id`, `date`, `title`, `duration`, `participants`; body `## Summary` then `## Transcript`.
- App state in `~/Library/Application Support/Carbon/meetings.json` + timestamped `Backups/` (Copper's pattern).
- Local Edits are kept; Delete removes the file.

**UI** (inspired by shadcn's Copper, SwiftUI, macOS 26).
- Menu bar icon only (no Dock icon): Show Carbon · Reveal in Finder · language switcher · Check for Updates… · Settings… ⌘, · Quit ⌘Q. Global show/hide shortcut.
- Window: Search (full text, title, participants) + rows: bold title; date · duration · participants in grey; optional color dot; newest first. No checkbox.
- ⋯ menu: Start Transcribing · Keep on Top · Close.
- Context menu: Copy ⌘C · Copy Path ⇧⌘C · Reveal in Finder · Edit Inline ↩ · Edit in New Window ⌘↩ · color dots · Delete ⌫. Double-click edits.
- Settings: permissions (mic, system audio, calendar), storage folder, auto-transcribe, keep audio, Meeting Languages + default, launch at login, global shortcut, auto-update, Voice Prints.

**Distribution.** Developer ID signed + notarized (existing Apple Developer account). Sparkle auto-updates. Cloudflare Worker on `carbon.alexandrejoly.me` serves site + `appcast.xml`; DMGs in R2. Private code repo; GitHub Action builds, signs, notarizes, publishes on tag.
