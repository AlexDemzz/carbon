# 06: Calendar Event matching, Provider and participants

**What to build:** a Meeting picks up its title and participants from the matching calendar Event, and its Provider from the Meeting App or the Event's link. In a 1:1 Event, the other attendee's name replaces Them. A browser call with an Event also ends on the Event rule: mic released, 30 s of silence and the Event over. Back-to-back Events split the Meeting. Spec: Modules (EventMatcher, Provider resolution), Detector stop and back-to-back rules; details in "Conference data exposed by EventKit events" (`.scratch/carbon-v1/issues/08-calendar-event-conference-data.md`).

**Blocked by:** 03 (Auto-start and auto-stop on microphone Detection).

**Status:** done

- [x] EventKit events are reduced to plain values; EventMatcher is pure.
- [x] Matching window: start −5 min to end +15 min, preferring an Event whose link host maps to the Meeting App's Provider.
- [x] Links are parsed from `url`, `location`, then `notes`.
- [x] Participants are the person attendees plus the organizer, without the current user, deduplicated by email. A nil `mailto:` is skipped without crashing.
- [x] Provider: the native app's bundle ID, else the link host, else the Meeting App's display name.
- [x] `providerMeetingId` and `calendarEventId` are stored in `meetings.json`.
- [x] Stop rule with an Event: mic released + 30 s of silence + Event ended.
- [x] Back-to-back: the matched Event ends and another one starts while the mic is held. The 10 min hold rule applies.
- [x] 1:1 Event: the lone Them Speaker (or `Them`) is written as the attendee's name, with `match: "attendee1to1"`.
- [x] EventMatcher tests cover Google, Exchange and iCloud event shapes from the EventKit research, a missing organizer and a nil `mailto:`.

**Implementation notes:**
- With an Event, the Meeting also ends after 10 min of silence while the Event still runs, so leaving a long Event early doesn't record for hours.
- A hold that began less than 10 min before the next Event moves the live Meeting onto that Event (`Detector.Command.event`) instead of splitting it.
- 1:1 in the Me / Them fallback: the Them Turns carry the attendee's name, but `speakers` stays empty (there is no cluster to record), so `match: "attendee1to1"` only appears with diarization.
- Deferred: the back-to-back restart waits for the previous Meeting's `finish()` (diarization included), so the second Meeting starts late by that long. The Calendar permission prompt is ticket 04's first-launch flow. `zoommtg://` links aren't parsed. The Exchange and iCloud shapes come from the research note, not from a real account. The EventKit adapter (`CalendarEvents`) builds but hasn't been run.
