import CarbonCore
import Foundation
import Testing

/// Event shapes from `docs/research/eventkit-conference-data.md`: Google (CalDAV) puts the Meet link in `notes`,
/// Exchange appends the Teams join block to the body (`notes`, HTML, SafeLinks), iCloud has it wherever the
/// organizer typed it (`url` or `location`).
struct EventMatcherTests {
    typealias Attendee = CalendarEvent.Attendee

    let matcher = EventMatcher()
    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    let teams = MeetingApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")
    let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

    let me = Attendee(name: "Alex Joly", url: "mailto:alex@example.com", isCurrentUser: true)
    let sam = Attendee(name: "Sam Rivera", url: "mailto:sam@example.com")
    let kim = Attendee(name: "Kim Lee", url: "mailto:Kim.Lee@example.com")

    static let googleNotes = """
        Weekly sync agenda.

        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        Join with Google Meet: https://meet.google.com/abc-defg-hij
        Or dial: (US) +1 555-0100 PIN: 123456789#
        More phone numbers: https://tel.meet/abc-defg-hij?pin=123456789

        Learn more about Meet at: https://support.google.com/a/users/answer/9282720
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        """

    static let exchangeNotes = """
        <html><body><div>Agenda: roadmap.</div>
        <div>________________________________________________________________________________</div>
        <div><b>Microsoft Teams meeting</b></div>
        <div><a href="https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_NjA5%2540thread.v2%2F0%3Fcontext%3D%257b%257d&amp;data=05%7C01&amp;reserved=0">Join the meeting now</a></div>
        <div>Meeting ID: 245 123 456 789</div>
        <div><a href="https://teams.microsoft.com/meetingOptions/?organizerId=1&amp;tenantId=2">Meeting options</a> | <a href="https://aka.ms/JoinTeamsMeeting">Learn more</a></div>
        </body></html>
        """

    func event(
        _ id: String, _ title: String, from start: String, to end: String, url: String? = nil,
        location: String? = nil, notes: String? = nil, attendees: [Attendee] = [], organizer: Attendee? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, title: title, start: date(start), end: date(end), url: url, location: location, notes: notes,
            attendees: attendees, organizer: organizer)
    }

    // MARK: Participants

    @Test func participantsAreThePersonAttendeesAndTheOrganizerWithoutMeDedupedByEmail() {
        let room = Attendee(name: "Room 4.01", url: "mailto:room401@example.com", kind: .room)
        let samAgain = Attendee(name: "Sam R.", url: "mailto:SAM@example.com")
        let organizer = Attendee(name: "Pat Organizer", url: "mailto:pat@example.com")
        let google = event(
            "g1", "Weekly sync", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z",
            notes: Self.googleNotes, attendees: [me, sam, room, kim, samAgain], organizer: organizer)

        #expect(EventMatcher.participants(of: google) == [
            Participant(name: "Sam Rivera", email: "sam@example.com"),
            Participant(name: "Kim Lee", email: "Kim.Lee@example.com"),
            Participant(name: "Pat Organizer", email: "pat@example.com"),
        ])
    }

    @Test func anOrganizerAlreadyListedAsAnAttendeeIsListedOnce() {
        let exchange = event(
            "x1", "Roadmap", from: "2026-10-23T13:00:00Z", to: "2026-10-23T14:00:00Z",
            notes: Self.exchangeNotes, attendees: [sam, me, kim],
            organizer: Attendee(name: "Kim Lee", url: "mailto:kim.lee@example.com"))

        #expect(EventMatcher.participants(of: exchange) == [
            Participant(name: "Sam Rivera", email: "sam@example.com"),
            Participant(name: "Kim Lee", email: "Kim.Lee@example.com"),
        ])
    }

    @Test func aMissingOrganizerAndANilMailtoAreSkipped() {
        let noURL = Attendee(name: "Dana Fox", url: nil)
        let nameless = Attendee(name: nil, url: nil)
        let emailOnly = Attendee(name: nil, url: "mailto:lee@example.com")
        let icloud = event(
            "i1", "Coffee", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z",
            url: "https://zoom.us/j/98765432100?pwd=abc", attendees: [me, noURL, nameless, emailOnly], organizer: nil)

        #expect(EventMatcher.participants(of: icloud) == [
            Participant(name: "Dana Fox"),
            Participant(name: "lee@example.com", email: "lee@example.com"),
        ])
    }

    @Test func theCurrentUserAsOrganizerIsNotAParticipant() {
        let mine = event(
            "i2", "1:1", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", attendees: [sam], organizer: me)

        #expect(EventMatcher.participants(of: mine) == [Participant(name: "Sam Rivera", email: "sam@example.com")])
    }
    // MARK: Conference links

    @Test func googleKeepsTheMeetLinkInTheNotes() {
        let google = event("g1", "Weekly sync", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", notes: Self.googleNotes)

        #expect(matcher.link(in: google) == ConferenceLink(provider: "Google Meet", meetingId: "abc-defg-hij"))
    }

    @Test func exchangeWrapsTheTeamsJoinLinkInSafeLinksAmongOtherTeamsLinks() {
        let exchange = event("x1", "Roadmap", from: "2026-10-23T13:00:00Z", to: "2026-10-23T14:00:00Z", location: "Cordova conference room", notes: Self.exchangeNotes)

        #expect(matcher.link(in: exchange) == ConferenceLink(provider: "Microsoft Teams", meetingId: nil))
    }

    @Test func iCloudHasTheLinkWhereverTheOrganizerTypedIt() {
        let inURL = event("i1", "Coffee", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", url: "https://us02web.zoom.us/j/98765432100?pwd=abc")
        let inLocation = event("i2", "Coffee", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", location: "https://meet.google.com/xyz-abcd-efg", notes: "Backup: https://zoom.us/j/111")

        #expect(matcher.link(in: inURL) == ConferenceLink(provider: "Zoom", meetingId: "98765432100"))
        #expect(matcher.link(in: inLocation) == ConferenceLink(provider: "Google Meet", meetingId: "xyz-abcd-efg"))
    }

    @Test func googleRedirectsAreUnwrappedAndLookalikeHostsAreNotLinks() {
        let redirected = event("g2", "Zoom via Google", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", notes: """
            Agenda: https://evil.example/zoom.us/j/123
            Join: https://www.google.com/url?q=https%3A%2F%2Fzoom.us%2Fj%2F5551234567%3Fpwd%3Dx&sa=D&source=calendar
            """)
        let lookalike = event("g3", "Nope", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", notes: "https://meet.google.com.evil.example/abc-defg-hij")

        #expect(matcher.link(in: redirected) == ConferenceLink(provider: "Zoom", meetingId: "5551234567"))
        #expect(matcher.link(in: lookalike) == nil)
    }

    // MARK: Matching

    @Test func anEventMatchesFrom5MinutesBeforeItsStartTo15MinutesAfterItsEnd() {
        let sync = event("g1", "Weekly sync", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", notes: Self.googleNotes)

        let matched = ["12:54:59", "12:55:00", "13:45:00", "13:45:01"].map {
            matcher.match([sync], app: chrome, at: date("2026-10-23T\($0)Z"))?.title
        }

        #expect(matched == [nil, "Weekly sync", "Weekly sync", nil])
    }

    @Test func anEventWhoseLinkIsOnTheMeetingAppsProviderWinsOverACloserOne() {
        let teamsCall = event("x1", "Roadmap", from: "2026-10-23T13:00:00Z", to: "2026-10-23T14:00:00Z", notes: Self.exchangeNotes)
        let meetCall = event("g1", "Weekly sync", from: "2026-10-23T13:30:00Z", to: "2026-10-23T14:00:00Z", notes: Self.googleNotes)
        let at = date("2026-10-23T13:30:00Z")

        #expect(matcher.match([meetCall, teamsCall], app: teams, at: at)?.title == "Roadmap")
        #expect(matcher.match([teamsCall, meetCall], app: zoom, at: at)?.title == "Weekly sync")
    }

    @Test func inABrowserAnEventWithAConferenceLinkWinsOverOneWithout() {
        let lunch = event("i1", "Lunch", from: "2026-10-23T13:00:00Z", to: "2026-10-23T14:00:00Z")
        let sync = event("g1", "Weekly sync", from: "2026-10-23T12:00:00Z", to: "2026-10-23T13:05:00Z", notes: Self.googleNotes)

        #expect(matcher.match([lunch, sync], app: chrome, at: date("2026-10-23T13:01:00Z"))?.title == "Weekly sync")
    }

    @Test func allDayCanceledAndDeclinedEventsNeverMatch() {
        let at = date("2026-10-23T13:10:00Z")
        let declinedMe = Attendee(name: "Alex Joly", url: "mailto:alex@example.com", isCurrentUser: true, declined: true)
        let events = [
            CalendarEvent(id: "a", title: "Offsite", start: date("2026-10-23T04:00:00Z"), end: date("2026-10-24T04:00:00Z"), isAllDay: true),
            CalendarEvent(id: "c", title: "Canceled", start: date("2026-10-23T13:00:00Z"), end: date("2026-10-23T13:30:00Z"), isCanceled: true),
            event("d", "Declined", from: "2026-10-23T13:00:00Z", to: "2026-10-23T13:30:00Z", attendees: [declinedMe, sam]),
        ]

        #expect(matcher.match(events, app: chrome, at: at) == nil)
    }
}
