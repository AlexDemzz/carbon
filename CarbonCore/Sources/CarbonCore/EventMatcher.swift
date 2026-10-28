import Foundation

/// Finds the calendar Event a Meeting belongs to, and what it says: title, participants, conference link.
public struct EventMatcher: Sendable {
    private let vendorTable: VendorTable

    public init(vendorTable: VendorTable = .shipped) {
        self.vendorTable = vendorTable
    }

    static let beforeStart: TimeInterval = 5 * 60
    static let afterEnd: TimeInterval = 15 * 60

    /// The Event a Meeting on `app` at `time` belongs to, or nil. Candidates run from 5 min before their start to
    /// 15 min after their end, and are neither all-day, canceled nor declined. The best one has a link on the native
    /// app's Provider (for any other app, any conference link), then the start closest to `time`.
    public func match(
        _ events: [CalendarEvent], app: MeetingApp?, at time: Date, excluding excluded: CalendarEvent? = nil
    ) -> CalendarEvent? {
        let native = app.flatMap { vendorTable.providers[$0.bundleID] }
        func rank(_ event: CalendarEvent) -> (Int, TimeInterval) {
            let link = link(in: event)
            let preferred = native.map { link?.provider == $0 } ?? (link != nil)
            return (preferred ? 0 : 1, abs(event.start.timeIntervalSince(time)))
        }
        return events
            .filter { Self.isCandidate($0, at: time) && !(excluded.map($0.isOccurrence(of:)) ?? false) }
            .min { rank($0) < rank($1) }
    }

    static func isCandidate(_ event: CalendarEvent, at time: Date) -> Bool {
        !event.isAllDay && !event.isCanceled
            && !event.attendees.contains { $0.isCurrentUser && $0.declined }
            && event.start.addingTimeInterval(-beforeStart) <= time && time <= event.end.addingTimeInterval(afterEnd)
    }

    /// The person attendees plus the organizer, without the current user, deduplicated by email.
    /// Each is shown by name, else by email; one with neither is left out.
    public static func participants(of event: CalendarEvent) -> [Participant] {
        var seenEmails: Set<String> = []
        var seenNames: Set<String> = []
        var participants: [Participant] = []
        let people = event.attendees.filter { $0.kind == .person } + [event.organizer].compactMap(\.self)
        for person in people where !person.isCurrentUser {
            let email = person.email
            let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? email
            guard let name else { continue }
            if let email {
                guard seenEmails.insert(email.lowercased()).inserted else { continue }
            } else {
                guard seenNames.insert(name.lowercased()).inserted else { continue }
            }
            participants.append(Participant(name: name, email: email))
        }
        return participants
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A conference link found in an Event, reduced to what Carbon keeps.
public struct ConferenceLink: Equatable, Sendable {
    public var provider: String
    /// The Provider's meeting code (`abc-defg-hij`, a Zoom meeting number), when the link carries one.
    public var meetingId: String?

    public init(provider: String, meetingId: String?) {
        self.provider = provider
        self.meetingId = meetingId
    }
}

extension EventMatcher {
    /// The Event's conference link: the first link of a known Provider in `url`, then `location`, then `notes`.
    public func link(in event: CalendarEvent) -> ConferenceLink? {
        for field in [event.url, event.location, event.notes].compactMap(\.self) {
            if let link = Self.urls(in: field).lazy.compactMap(link(at:)).first { return link }
        }
        return nil
    }

    private func link(at url: URLComponents) -> ConferenceLink? {
        guard let host = url.host?.lowercased() else { return nil }
        for rule in vendorTable.links where host == rule.host || host.hasSuffix("." + rule.host) {
            guard let regex = try? Regex(rule.path), let match = try? regex.prefixMatch(in: url.percentEncodedPath)
            else { continue }
            let code = match.output.count > 1 ? match.output[1].substring.map(String.init) : nil
            return ConferenceLink(provider: rule.provider, meetingId: code)
        }
        return nil
    }

    /// The http(s) links in free text or HTML, with Outlook SafeLinks and Google redirects unwrapped.
    static func urls(in text: String) -> [URLComponents] {
        text.matches(of: /https?:\/\/[^\s"'<>]+/.ignoresCase()).compactMap { match in
            let raw = String(match.output).replacingOccurrences(of: "&amp;", with: "&")
            return URLComponents(string: raw).map(unwrapped)
        }
    }

    private static func unwrapped(_ url: URLComponents) -> URLComponents {
        let host = url.host?.lowercased() ?? ""
        let wrapped: String? =
            if host.hasSuffix(".safelinks.protection.outlook.com") {
                url.queryItems?.first { $0.name == "url" }?.value
            } else if host.hasPrefix("www.google.") || host.hasPrefix("google."), url.path == "/url" {
                url.queryItems?.first { $0.name == "q" }?.value
            } else {
                nil
            }
        return wrapped.flatMap(URLComponents.init(string:)) ?? url
    }
}
