# Conference data exposed by EventKit events

Researched 2026-10-27. Sources: Apple's EventKit reference (read through the DocC JSON behind developer.apple.com), Microsoft Graph docs, and the source of three open-source apps that read EventKit, pinned at a commit. No real calendar data was read for this note. Anything a primary source does not establish is marked **unverified**. Conclusions I drew from a source, which the source does not state outright, are marked **(inference)**.

Permalink bases:

- MeetingBar: [`leits/MeetingBar@93a0071`](https://github.com/leits/MeetingBar/tree/93a0071b826c088f55ff177d20de1e9cc7ae3374), a menu bar app that reads EventKit or the Google Calendar API and opens meeting links.
- Itsycal: [`sfsam/Itsycal@1a31050`](https://github.com/sfsam/Itsycal/tree/1a31050555a97e3b7aac5470ec147abfe7aa0d6a), a menu bar calendar built on EventKit.
- Hyprnote / Anarlog: [`fastrepl/anarlog@7165aba`](https://github.com/fastrepl/anarlog/tree/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9), the same commit as [local-meeting-capture.md](local-meeting-capture.md).

## Summary

| Question | Answer | Confidence |
|---|---|---|
| Does `EKEvent` have a conference field? | **No.** The fields that matter are `url`, `location` and `notes`, all free-form. | Apple docs |
| Google Calendar (CalDAV) | The Meet link sits in `notes`, in the block Google appends to the description. `url` and `location` were empty. | Apps' code + one empirical spike |
| Microsoft 365 / Exchange | Exchange puts the Teams join block into the event **body**, which should land in `notes`. The `location` is free text, often a room. | Graph docs; the EventKit side is **unverified** |
| iCloud | No source found. Links are wherever the organizer typed them, or wherever a virtual-conference extension stored them. | **unverified** |
| Attendees | `name`, `url` (usually `mailto:`), `participantRole`, `participantType`, `participantStatus`, `isCurrentUser`, `contactPredicate`. There is no `email` or `isOrganizer`. | Apple docs |

## 1. `EKEvent` has no structured conference field

- `EKCalendarItem` lists these properties: `calendar`, `title`, `location`, `creationDate`, `lastModifiedDate`, `timeZone` and `url`. Notes are `hasNotes` and `notes`, and attendees are `hasAttendees` and `attendees` ([EKCalendarItem](https://developer.apple.com/documentation/eventkit/ekcalendaritem)). `EKEvent` adds `organizer`, `status`, `structuredLocation`, `availability`, dates and birthday fields ([EKEvent](https://developer.apple.com/documentation/eventkit/ekevent)). None of these is a conference or join URL.
- The types are `url: URL?` ([url](https://developer.apple.com/documentation/eventkit/ekcalendaritem/url)), `location: String?`, which is "nil if the calendar item has no location" ([location](https://developer.apple.com/documentation/eventkit/ekcalendaritem/location)), and `notes: String?` ([notes](https://developer.apple.com/documentation/eventkit/ekcalendaritem/notes)). `structuredLocation` is "the event's location with a potential geocoordinate" ([structuredLocation](https://developer.apple.com/documentation/eventkit/ekevent/structuredlocation)), so it holds a place, not a link.
- EventKit does have a conference API, but it only **writes**. `EKVirtualConferenceProvider` is an app extension that lets an app such as Zoom offer "rooms" when someone creates an event in Calendar. It returns an `EKVirtualConferenceDescriptor` whose first URL "Calendar uses ... as the preferred way for users to join" ([EKVirtualConferenceProvider](https://developer.apple.com/documentation/eventkit/ekvirtualconferenceprovider), [EKVirtualConferenceDescriptor](https://developer.apple.com/documentation/eventkit/ekvirtualconferencedescriptor)). There is no getter on `EKEvent` to read it back. In an Apple Developer Forums thread, a developer says "I couldn't find any method to set up meetings in EKEvent", and the only Apple (DTS) reply asks for clarification ([forum thread 783375](https://developer.apple.com/forums/thread/783375)). Where Calendar stores a conference added by such an extension, and whether it shows up in `url`, `location` or `notes`, is **unverified**.
- MeetingBar states the gap in its model: its `conferenceURL` field (Google's `conferenceData`) has no EventKit equivalent, "so this is `nil` for those events" ([MBEvent.swift#L74-L79](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/MBEvent.swift#L74-L79)). Its EventKit mapper passes only `notes`, `location` and `url` to link detection ([EventKitEventStore.swift#L287-L305](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L287-L305)).

### How existing apps search the three fields

| App | Order searched | Source |
|---|---|---|
| MeetingBar | `url` (50) > `location` (40) > `notes` (30) > notes with HTML stripped (20) > custom regex (10). Within a field, a known conferencing service beats content links such as YouTube, which beat catch-alls; then the earliest match; then the longest URL. | [MeetingLinkDetector.swift#L113-L153](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingLinkDetector.swift#L113-L153), [#L180-L195](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingLinkDetector.swift#L180-L195) |
| Itsycal | `location` > `url` > `notes` (only if `hasNotes`) | [EventCenter.m#L500-L507](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/EventCenter.m#L500-L507) |
| Hyprnote / Anarlog | `location` > `notes`. It ignores `url` for Apple events, while its Google and Outlook API paths use the native `hangoutLink` / `onlineMeeting.joinUrl` first. | [convert.rs#L341-L342](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/calendar/src/convert.rs#L341-L342), [#L193-L200](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/calendar/src/convert.rs#L193-L200), [#L971-L982](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/calendar/src/convert.rs#L971-L982) |

Regexes MeetingBar uses for the three Providers Carbon cares about:

- Meet: `https?://meet.google.com/(_meet/)?[a-z-]+` ([MeetingProvider.swift#L188](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingProvider.swift#L188)).
- Zoom: any `*zoom.us|com|com.cn|de/(my|j|w|…|webinar)/…` link ([#L221](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingProvider.swift#L221)), plus `zoommtg://` and ZoomGov.
- Teams: `teams.microsoft.com|us` or `teams.live.com` with `/l/meetup-join/…` or `/meet/<id>?p=…` ([#L253](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingProvider.swift#L253)).

Itsycal matches on the URL **host** rather than on substrings, because `zoom.us/j/` would also match `https://evil.example/zoom.us/j/123` ([EventCenter.m#L420-L442](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/EventCenter.m#L420-L442)).

### Noise inside `notes` that the parser must handle

- **Outlook SafeLinks:** links wrapped as `https://<x>.safelinks.protection.outlook.com/?url=<encoded>`. MeetingBar unwraps them before detection ([MeetingLinkDetector.swift#L291-L295](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingLinkDetector.swift#L291-L295)).
- **Google redirects:** `https://www.google.<tld>/url?q=<encoded>&sa=D&source=calendar…`, which Google Calendar puts around links in the description ([MeetingLinkDetector.swift#L297-L316](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingLinkDetector.swift#L297-L316)).
- **HTML:** notes can contain HTML tags and entities. MeetingBar strips them with a pure-Foundation converter, because `NSAttributedString(html:)` on every refresh crashed it ("allocating too many mach ports") ([MeetingLinkDetector.swift#L500-L511](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Meetings/MeetingLinkDetector.swift#L500-L511)).
- **Several links for one meeting:** a Google Calendar Zoom add-on body has a `-::~:~::~:~…` delimited block. It holds the plain Zoom link, a `google.com/url` wrapped copy that is *longer* (and whose `pwd` breaks), and agenda and chat links on the same host ([ZoomGoogleRedirectRegressionTests.swift#L5-L45](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBarLogicTests/ZoomGoogleRedirectRegressionTests.swift#L5-L45)). A user also reports links in the notes winning over the conference actually attached to the event ([MeetingBar #847](https://github.com/leits/MeetingBar/issues/847)).

## 2. Per account type

### Google Calendar, synced over CalDAV

- In Google's own API, the link is structured: `conferenceData.entryPoints[entryPointType=video].uri` or `hangoutLink`. MeetingBar's Google path reads those, and says "the plain `url` field remains nil for Google events" ([GoogleCalendarEventStore.swift#L691-L703](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/Google/GoogleCalendarEventStore.swift#L691-L703)). EventKit gets none of this structure.
- Google's iCalendar output carries the link as `X-GOOGLE-CONFERENCE:<meet url>` (seen in a third-party ICS test fixture, [macro-inc/macro google.ics#L29](https://github.com/macro-inc/macro/blob/5a8a34947d9791492b49e1d5222fd640ad5f3e23/crates/email/fixtures/calendar/google.ics#L29); the fixture may be hand-written). EventKit has no property for X- properties (§1), so that value cannot be read.
- **Empirical:** a throwaway EventKit spike on a real Mac with a Google CalDAV account found `url` set on 0 of 50 events and `location` on 0. `notes` was set on 31, and 26 of those held a Meet link ([Maheidem/openstyle#68](https://github.com/Maheidem/openstyle/issues/68)). This is one developer's data, not documentation. The description block Google writes is the `-::~:~::~` section shown in the MeetingBar fixture above **(inference: the same block reaches `notes`)**.
- EventKit reports Google accounts as `EKSourceType.calDAV`, not as a dedicated type, in the same spike ([openstyle#68](https://github.com/Maheidem/openstyle/issues/68)). To recover the Google account email, MeetingBar parses `mailto:` out of `EKSource.description`, which it calls "Hacky and likely to break" ([EventKitEventStore.swift#L312-L324](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L312-L324)).

### Microsoft 365 / Exchange

- When an Outlook event is made an online meeting, the server appends the Teams join block, as HTML, to the event **body**: a "Join Microsoft Teams Meeting" anchor to `https://teams.microsoft.com/l/meetup-join/…`, dial-in numbers, and "Meeting options" / "Learn more" links on `teams.microsoft.com` and `aka.ms`. The `location` stays whatever the organizer set, e.g. "Cordova conference room". The structured `onlineMeeting.joinUrl` exists only in Graph ([Graph: online meetings](https://learn.microsoft.com/en-us/graph/outlook-calendar-online-meetings)).
- The body is the only place the link is guaranteed, so it is the only one EventKit could carry. Whether macOS Calendar's Exchange account maps the body to `notes` as plain text or as HTML is **unverified**. MeetingBar's HTML stripping and SafeLinks unwrapping exist because such bodies do reach `notes` **(inference)**.
- Several notes-parsing projects match the boilerplate "Microsoft Teams meeting" inside `event.notes` (e.g. [verveguy/tana-helper getcalendar.swift#L279](https://github.com/verveguy/tana-helper/blob/9b8089697fcca516202c4f5f41fbc5a71c8dd14c/service/service/scripts/getcalendar.swift#L279)). These are secondary sources.
- That Outlook clients set `location` to "Microsoft Teams Meeting" by default is **unverified**. The Graph example does not do it. Never parse a link out of `location` and treat a missing link there as normal.
- The openstyle spike had no Exchange source. On its second CalDAV account, `location` held room text on 32 of 43 events, never a link. `notes` held 40 links: 28 Meet, 11 Teams, 1 Zoom ([openstyle#68](https://github.com/Maheidem/openstyle/issues/68)).
- Apple notes an Exchange quirk: `calendarItemExternalIdentifier` "is different between iOS and macOS" for Exchange ([calendarItemExternalIdentifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier)). It is stable on one Mac, which is all Carbon needs.

### iCloud

- No primary source found. iCloud events carry whatever the organizer typed. Hand-made events often put the link in `location` (MeetingBar added location parsing because "my colleagues all put the meeting link in the location", [MeetingBar #46](https://github.com/leits/MeetingBar/issues/46)) or in `url`, which Calendar's event editor exposes and Itsycal writes ([EventViewController.m#L534](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/EventViewController.m#L534)).
- How FaceTime links and virtual-conference-extension rooms appear through EventKit is **unverified**. Invitations received from Google or Exchange organizers keep that organizer's body text **(inference)**.

## 3. Attendees (`EKParticipant`)

| Property | Type | What it gives | Source |
|---|---|---|---|
| `attendees` (on the item) | `[EKParticipant]?` | Read-only; `nil` if there are no attendees | [attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/attendees) |
| `organizer` (on the event) | `EKParticipant?` | `nil` if the event has no organizer | [organizer](https://developer.apple.com/documentation/eventkit/ekevent/organizer) |
| `name` | `String?` | Display name | [name](https://developer.apple.com/documentation/eventkit/ekparticipant/name) |
| `url` | `URL` (declared non-optional) | "The URL representing this participant", in practice `mailto:addr` | [url](https://developer.apple.com/documentation/eventkit/ekparticipant/url) |
| `participantRole` | `EKParticipantRole` | `unknown`, `required`, `optional`, `chair`, `nonParticipant` | [EKParticipantRole](https://developer.apple.com/documentation/eventkit/ekparticipantrole) |
| `participantType` | `EKParticipantType` | `unknown`, `person`, `room`, `resource`, `group` | [EKParticipantType](https://developer.apple.com/documentation/eventkit/ekparticipanttype) |
| `participantStatus` | `EKParticipantStatus` | pending, accepted, declined, tentative, delegated, completed, in process, unknown | [EKParticipant](https://developer.apple.com/documentation/eventkit/ekparticipant) |
| `isCurrentUser` | `Bool` | "whether this participant represents the owner of this account" | [isCurrentUser](https://developer.apple.com/documentation/eventkit/ekparticipant/iscurrentuser) |
| `contactPredicate` | `NSPredicate` | For `CNContactStore`, to fetch the matching `CNContact` "if one exists" | [contactPredicate](https://developer.apple.com/documentation/eventkit/ekparticipant/contactpredicate) |

Things the docs do not say, learned from code:

- **There is no `email` property.** Everyone derives it from `url`: `url.resourceSpecifier` (MeetingBar [EventKitEventStore.swift#L274](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L274), Itsycal [AgendaViewController.m#L1280](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/AgendaViewController.m#L1280)) or by stripping `mailto:` (Anarlog [contacts.rs#L55-L65](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/apple-calendar/src/apple/contacts.rs#L55-L65)). Anarlog falls back to `name` when the name itself looks like an email ([contacts.rs#L67-L74](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/apple-calendar/src/apple/contacts.rs#L67-L74)).
- **`url` can be nil despite its Swift signature.** Accessing it directly crashes with `EXC_BREAKPOINT` ([SO 40804131](https://stackoverflow.com/questions/40804131/workaround-for-ekparcipant-url-accessing-crash), still an issue on macOS 11.2 per [this answer](https://stackoverflow.com/a/66074963)). MeetingBar reads it through `perform(#selector(getter: EKParticipant.url))` ([EventKitEventStore.swift#L11-L16](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L11-L16)), and Anarlog uses `msg_send!` into an `Option` ([participant.rs#L23-L26](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/apple-calendar/src/apple/transforms/participant.rs#L23-L26)). Itsycal notes that "EKParticipant name and URL.resourceSpecifier (email addr) are nullable (why?...)" ([AgendaViewController.m#L1275-L1282](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/AgendaViewController.m#L1275-L1282)).
- **`contactPredicate` can throw an Objective-C exception.** Anarlog wraps it in `objc2::exception::catch` ([contacts.rs#L41-L53](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/apple-calendar/src/apple/contacts.rs#L41-L53)). Using it needs Contacts permission in addition to Calendars.
- **There is no organizer flag on an attendee, and the organizer is not always in `attendees`.** Itsycal adds `event.organizer` by hand and dedupes by comparing `URL.resourceSpecifier` ("Sometimes info.event.organizer isn't in info.event.attendees") ([AgendaViewController.m#L1226-L1241](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/AgendaViewController.m#L1226-L1241)). The openstyle spike counted 4 of 43 events whose organizer was missing from the list ([openstyle#68](https://github.com/Maheidem/openstyle/issues/68)). `participantRole == .chair` exists but is not reported as tied to the organizer **(unverified)**.
- **Rooms and resources show up as attendees.** MeetingBar keeps only `participantType == .person` ([EventKitEventStore.swift#L249-L252](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L249-L252)).
- **The person's own response comes from `isCurrentUser`.** MeetingBar takes the attendee with `isCurrentUser` as the user's participation status, which is how it can skip declined events ([MBEvent.swift#L140-L143](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/MBEvent.swift#L140-L143)).
- **Empirical coverage:** in the openstyle spike, all 312 CalDAV attendees had a name and a `mailto:` URL. `isCurrentUser` was found on every event with attendees. Roles seen were required and optional. Google CalDAV events had attendees on only 2 of 50, because most were solo events ([openstyle#68](https://github.com/Maheidem/openstyle/issues/68)). There is no data for Exchange or iCloud: **unverified**.

## 4. Open points to check on a real Mac (with test accounts, not the author's data)

- [ ] The exact `notes` text of an Exchange (EWS) event with Teams: plain text or HTML, SafeLinks or not, and what `location` shows.
- [ ] Where a Zoom virtual-conference-extension room and a FaceTime link land in `url`, `location` or `notes` for an iCloud event.
- [ ] Whether `isCurrentUser` is set on Exchange attendees and on invitations forwarded into iCloud.

## Recommendation (opinion)

**`provider`**

- Parse a conference link from, in order, `url`, `location`, then `notes`. Before matching `notes`, unwrap SafeLinks and `google.com/url?q=` redirects and strip HTML. Match on the URL host:
  - `meet.google.com` → Google Meet;
  - `*.zoom.us`, `zoomgov.com` or `zoommtg://` → Zoom;
  - `teams.microsoft.com` / `teams.live.com` with `meetup-join` or `meet` → Teams.
- Within one field, prefer a known Provider and then the first match (MeetingBar's tiering). That avoids picking up Teams "Meeting options" links or Zoom agenda links.
- Combine this with the mic-holding process. A native app is authoritative: `us.zoom.xos` → Zoom, `com.microsoft.teams2` / `com.microsoft.teams` → Teams (the bundle IDs Anarlog uses, [platform.rs#L44-L46](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax/platform.rs#L44-L46)). For a browser, take the Provider from the matched event's link. With no event, leave the Provider unknown rather than guess.

**`participants`**

- Take `attendees`, filtered to `participantType == .person`, plus `organizer` when it is absent. Dedupe on the lowercased `mailto:` address.
- Read `url` only through a nil-safe accessor.
- Drop the `isCurrentUser` entry, because it is "Me".
- Display `name`, falling back to the email. Skip `contactPredicate` in v1, since it needs a second permission.
- Treat this list as a roster of names to offer when naming Speakers, not as Speakers: the Glossary keeps Speakers unnamed until named.

**Matching a mic-holding process to an event**

1. Candidates: events with `start − 5 min ≤ now ≤ end + 15 min`. Exclude all-day events, events with `status == .canceled`, and events where the current user's attendee has `.declined`.
2. Rank the candidates:
   - (a) the event's link Provider equals the native app's Provider;
   - (b) for a browser holder, the event has any conference link;
   - (c) the event has at least 2 person attendees;
   - then the start closest to now.
3. If nothing is left, record a Meeting with no event.
4. Key the match on `calendarItemIdentifier` plus the occurrence start date. EventKit shares the identifier across a recurring series, which MeetingBar works around the same way ([EventKitEventStore.swift#L280-L289](https://github.com/leits/MeetingBar/blob/93a0071b826c088f55ff177d20de1e9cc7ae3374/MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift#L280-L289)).
