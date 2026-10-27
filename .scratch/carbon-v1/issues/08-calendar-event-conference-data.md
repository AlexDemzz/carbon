# Conference data exposed by EventKit events

Type: research
Status: resolved
Blocked by:

## Question

For events synced into macOS Calendar from Google Calendar, Microsoft 365/Exchange and iCloud, where does the conference link (Meet, Zoom, Teams) appear on `EKEvent` (`url`, `location`, `notes`, other), and what do `attendees` expose (display name, email, organizer, self)? Outcome: how Carbon infers `provider` and `participants` and matches a mic-in-use process to an event.

## Answer

- `EKEvent` has no conference field; the link is free text in `url`, `location` or `notes`. EventKit's virtual-conference API only writes.
- Google (CalDAV): the Meet link sits in `notes`, in Google's appended description block; `url` and `location` are empty. Exchange/M365: the server appends the Teams join block to the body, so it should land in `notes`, but the exact EventKit text is unverified. iCloud: whatever the organizer typed (unverified).
- `EKParticipant` exposes `name?`, `url` (a `mailto:` you parse for the email; it can be nil and crash if read directly), role, type (rooms included), status, `isCurrentUser` and `contactPredicate`. There is no email or organizer flag, and `organizer` is sometimes missing from `attendees`.
- Opinion: Provider comes from the native app's bundle ID when there is one, otherwise from the event link's host. Participants are person attendees plus the organizer, without Me. Match events in the window start −5 min to end +15 min, preferring one whose link Provider matches.
- Details: [docs/research/eventkit-conference-data.md](../../../docs/research/eventkit-conference-data.md)
