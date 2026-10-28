# 06: Calendar Event matching, Provider and participants

**What to build:** a Meeting picks up its title and participants from the matching calendar Event, and its Provider from the Meeting App or the Event's link. In a 1:1 Event, the other attendee's name replaces Them. A browser call with an Event also ends on the Event rule: mic released, 30 s of silence and the Event over. Back-to-back Events split the Meeting. Spec: Modules (EventMatcher, Provider resolution), Detector stop and back-to-back rules; details in "Conference data exposed by EventKit events" (`.scratch/carbon-v1/issues/08-calendar-event-conference-data.md`).

**Blocked by:** 03 (Auto-start and auto-stop on microphone Detection).

**Status:** ready-for-agent

- [ ] EventKit events are reduced to plain values; EventMatcher is pure.
- [ ] Matching window: start −5 min to end +15 min, preferring an Event whose link host maps to the Meeting App's Provider.
- [ ] Links are parsed from `url`, `location`, then `notes`.
- [ ] Participants are the person attendees plus the organizer, without the current user, deduplicated by email. A nil `mailto:` is skipped without crashing.
- [ ] Provider: the native app's bundle ID, else the link host, else the Meeting App's display name.
- [ ] `providerMeetingId` and `calendarEventId` are stored in `meetings.json`.
- [ ] Stop rule with an Event: mic released + 30 s of silence + Event ended.
- [ ] Back-to-back: the matched Event ends and another one starts while the mic is held. The 10 min hold rule applies.
- [ ] 1:1 Event: the lone Them Speaker (or `Them`) is written as the attendee's name, with `match: "attendee1to1"`.
- [ ] EventMatcher tests cover Google, Exchange and iCloud event shapes from the EventKit research, a missing organizer and a nil `mailto:`.
