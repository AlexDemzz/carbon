import Foundation

/// A calendar event reduced to plain values by the EventKit adapter, so that matching stays pure.
public struct CalendarEvent: Equatable, Sendable, Codable {
    public struct Attendee: Equatable, Sendable, Codable {
        public enum Kind: String, Sendable, Codable {
            case person, room, resource, group, unknown
        }

        public var name: String?
        /// The participant's URL, usually `mailto:…`. Nil when EventKit has none, which it does despite its signature.
        public var url: String?
        public var kind: Kind
        public var isCurrentUser: Bool
        public var declined: Bool

        public init(
            name: String?, url: String?, kind: Kind = .person, isCurrentUser: Bool = false, declined: Bool = false
        ) {
            self.name = name
            self.url = url
            self.kind = kind
            self.isCurrentUser = isCurrentUser
            self.declined = declined
        }

        /// The address of a `mailto:` URL, nil for anything else.
        public var email: String? {
            guard let url, url.lowercased().hasPrefix("mailto:") else { return nil }
            let address = url.dropFirst("mailto:".count).trimmingCharacters(in: .whitespaces)
            return address.isEmpty ? nil : address.removingPercentEncoding ?? address
        }
    }

    /// `calendarItemExternalIdentifier`, stored as `calendarEventId`. Shared by every occurrence of a recurring event.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCanceled: Bool
    public var url: String?
    public var location: String?
    public var notes: String?
    public var attendees: [Attendee]
    /// Nil when the event has none; it is not always among the attendees either.
    public var organizer: Attendee?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isCanceled: Bool = false,
        url: String? = nil, location: String? = nil, notes: String? = nil, attendees: [Attendee] = [],
        organizer: Attendee? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCanceled = isCanceled
        self.url = url
        self.location = location
        self.notes = notes
        self.attendees = attendees
        self.organizer = organizer
    }

    /// The same occurrence: recurring events share `id`, so the start tells occurrences apart.
    func isOccurrence(of other: CalendarEvent) -> Bool {
        id == other.id && start == other.start
    }
}
