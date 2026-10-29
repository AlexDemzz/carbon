import AppKit
import CarbonCore
import EventKit
import SwiftUI

/// An account Apple Calendar reads, with its event calendars.
struct CalendarAccount: Identifiable, Equatable {
    struct Calendar: Identifiable, Equatable {
        let id: String
        let title: String
        let color: Color
    }

    let id: String
    let title: String
    let kind: CalendarAccountKind
    let calendars: [Calendar]
}

/// The onboarding's Calendar step: the accounts Apple Calendar is connected to, so a missing work account shows
/// before the first Meeting. Empty without Calendar full access.
@MainActor
@Observable
final class CalendarAccounts {
    private(set) var accounts: [CalendarAccount] = []
    /// Made on the first read with access: a store made before the grant never sees the calendars.
    @ObservationIgnored private var store: EKEventStore?

    func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            store = nil
            if !accounts.isEmpty { accounts = [] }
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        store.refreshSourcesIfNecessary()
        let fresh = store.sources.map(Self.account).filter { !$0.calendars.isEmpty }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if fresh != accounts { accounts = fresh }
    }

    static func openInternetAccounts() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func account(_ source: EKSource) -> CalendarAccount {
        let calendars = source.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return CalendarAccount(
            id: source.sourceIdentifier, title: source.title, kind: kind(of: source, calendars: calendars),
            calendars: calendars.map {
                CalendarAccount.Calendar(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor))
            })
    }

    private static func kind(of source: EKSource, calendars: [EKCalendar]) -> CalendarAccountKind {
        switch source.sourceType {
        case .local: .onMyMac
        case .exchange: .exchange
        case .calDAV:
            CalendarAccountKind(calDAVTitle: source.title, calendarIdentifiers: calendars.map(\.calendarIdentifier))
        case .mobileMe: .iCloud
        case .subscribed: .subscribed
        case .birthdays: .birthdays
        @unknown default: .other
        }
    }
}
