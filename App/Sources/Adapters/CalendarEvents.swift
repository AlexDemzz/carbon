import CarbonCore
import EventKit
import Foundation
import Synchronization

/// Detection's calendar signal: the EventKit events around now, reduced to plain values for the EventMatcher.
/// Refreshed every 30 s and whenever the event store changes, so a 1 s mic snapshot never waits on EventKit.
/// Reads nothing without Calendar full access; the first-launch prompts ask for it.
// The store and the timer are used only on `queue`, and `observer` only in init and deinit; the cache is behind a Mutex.
final class CalendarEvents: @unchecked Sendable {
    /// Wider than the matching window (start −5 min, end +15 min) by the refresh interval.
    private static let lookBehind: TimeInterval = 16 * 60
    private static let lookAhead: TimeInterval = 6 * 60
    private static let refreshInterval: TimeInterval = 30

    private let store = EKEventStore()
    private let cache = Mutex<[CalendarEvent]>([])
    private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.calendar-events")
    private let timer: DispatchSourceTimer
    private var observer: (any NSObjectProtocol)?

    init() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.refreshInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        let token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.refresh() }
        }
        observer = token
    }

    deinit {
        timer.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The events last read around now, empty without Calendar access.
    var current: [CalendarEvent] { cache.withLock { $0 } }

    private func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            cache.withLock { $0 = [] }
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-Self.lookBehind), end: now.addingTimeInterval(Self.lookAhead),
            calendars: nil)
        let events = store.events(matching: predicate).map(Self.reduce)
        cache.withLock { $0 = events }
    }

    private static func reduce(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            isCanceled: event.status == .canceled, url: event.url?.absoluteString, location: event.location,
            notes: event.hasNotes ? event.notes : nil, attendees: (event.attendees ?? []).map(reduce),
            organizer: event.organizer.map(reduce))
    }

    private static func reduce(_ participant: EKParticipant) -> CalendarEvent.Attendee {
        CalendarEvent.Attendee(
            name: participant.name, url: url(of: participant)?.absoluteString, kind: kind(participant.participantType),
            isCurrentUser: participant.isCurrentUser, declined: participant.participantStatus == .declined)
    }

    /// `EKParticipant.url` is declared non-optional but can be nil, and reading it directly then crashes.
    private static func url(of participant: EKParticipant) -> URL? {
        participant.perform(#selector(getter: EKParticipant.url))?.takeUnretainedValue() as? URL
    }

    private static func kind(_ type: EKParticipantType) -> CalendarEvent.Attendee.Kind {
        switch type {
        case .person: .person
        case .room: .room
        case .resource: .resource
        case .group: .group
        default: .unknown
        }
    }
}
