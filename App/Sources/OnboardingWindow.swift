import AppKit
import CarbonCore
import SwiftUI

/// The first launch's window: Welcome, a step per permission, the Meeting Languages, then Done, which says whether
/// Carbon can transcribe.
/// Only the system's own containers and controls: margins, section gaps and row insets are Form's, as in Settings.
struct OnboardingWindow: View {
    let model: AppModel
    @State private var calendarAccounts = CalendarAccounts()
    @State private var step = 0
    @State private var forward = true
    @State private var headerHeight: CGFloat = 0
    @State private var formHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var welcomeHeight: CGFloat = 0
    /// The Languages step's rows: the languages checked when it first showed, so an unchecked one can be checked again.
    @State private var seededLanguages: [Locale] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings

    private enum Step: Equatable {
        case welcome, permission(Permission), languages, done
    }

    private let steps: [Step] = [.welcome] + Permission.allCases.map(Step.permission) + [.languages, .done]

    /// Fits each step, never shorter than Welcome so the buttons don't jump, and past 680 pt the Form scrolls.
    private var height: CGFloat {
        max(welcomeHeight, min(headerHeight + formHeight + footerHeight, 680))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                Form { sections }
                    .formStyle(.grouped)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                    } action: { _, height in formHeight = height }
            }
            .id(step)
            .transition(stepTransition)
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .frame(width: 520, height: height)
        .onChange(of: headerHeight + formHeight + footerHeight) { _, fitted in
            if steps[step] == .welcome { welcomeHeight = fitted }
        }
        .task { await watchPermissions() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                calendarAccounts.refresh()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                calendarAccounts.refresh()
            }
        }
        .onChange(of: model.permissions.calendar, initial: true) { calendarAccounts.refresh() }
    }

    /// System Settings tells Carbon nothing when a permission changes there, so the window rereads every second.
    private func watchPermissions() async {
        while !Task.isCancelled {
            await model.refreshPermissions()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        ).combined(with: .opacity)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) { step += delta }
    }

    @ViewBuilder private var header: some View {
        switch steps[step] {
        case .welcome:
            OnboardingHero(
                title: "Welcome to Carbon",
                subtitle: "Meeting transcripts that stay on your Mac. Carbon needs two permissions to hear both sides of a Meeting, and two optional ones to name it and tell you when it\u{2019}s transcribing.")
        case .permission(let permission):
            OnboardingHero(
                symbol: permission.symbol, tint: permission.tint, title: permission.stepTitle, subtitle: permission.reason)
        case .languages:
            OnboardingHero(
                symbol: "globe", tint: .blue, title: "Languages You Speak in Meetings",
                subtitle: "Carbon transcribes each Meeting in whichever of these it hears, on your Mac. They come from your Mac\u{2019}s languages.")
        case .done:
            let conclusion = model.permissions.onboardingConclusion
            OnboardingHero(title: conclusion.title, subtitle: conclusion.subtitle)
        }
    }

    @ViewBuilder private var sections: some View {
        switch steps[step] {
        case .welcome:
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    LabeledContent {
                        PermissionStatusBadge(status: model.permissions[permission])
                    } label: {
                        PermissionLabel(permission: permission, subtitle: permission.isRequired ? "Required" : "Optional")
                    }
                }
            }
        case .permission(let permission):
            Section {
                LabeledContent(permission.name) { PermissionStatusBadge(status: model.permissions[permission]) }
            } footer: {
                if let hint = permission.hint(for: model.permissions[permission]) {
                    Text(hint).foregroundStyle(.secondary)
                }
            }
            if permission == .calendar {
                CalendarAccountsSection(accounts: calendarAccounts, isAllowed: model.permissions.calendar == .allowed)
            }
        case .languages:
            languagesSection
        case .done:
            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    let status = model.permissions[permission]
                    LabeledContent {
                        if status == .allowed {
                            PermissionStatusBadge(status: status)
                        } else {
                            AllowButton(model: model, permission: permission)
                        }
                    } label: {
                        PermissionLabel(permission: permission, subtitle: permission.hint(for: status))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { go(-1) } }
            Spacer()
            switch steps[step] {
            case .welcome:
                Button("Get Started") { go(1) }.keyboardShortcut(.defaultAction)
            case .permission(let permission) where model.permissions[permission] != .allowed:
                Button("Skip") { go(1) }
                AllowButton(model: model, permission: permission, isDefault: true)
            case .permission, .languages:
                Button("Continue") { go(1) }.keyboardShortcut(.defaultAction)
            case .done:
                Button("Done") { dismissWindow(id: AppModel.onboardingWindowID) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    /// Reserving and downloading start here, unless Detection already started them once permissions allowed it.
    private var languagesSection: some View {
        Section {
            if let languages = model.meetingLanguages {
                ForEach(seededLanguages, id: \.self) { language in
                    LanguageRow(model: model, language: language, languages: languages)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } footer: {
            HStack(spacing: 4) {
                Text("Missing a language?").foregroundStyle(.secondary)
                Button("Add Languages\u{2026}") {
                    model.settingsTab = .languages
                    openSettings()
                }
                .buttonStyle(.link)
            }
        }
        .task { await model.loadMeetingLanguages() }
        .onChange(of: model.meetingLanguages == nil, initial: true) {
            if seededLanguages.isEmpty, let languages = model.meetingLanguages { seededLanguages = languages.chosen }
        }
    }
}

private extension Permission {
    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .systemAudioRecording: "speaker.wave.2.fill"
        case .calendar: "calendar"
        case .notifications: "bell.badge.fill"
        }
    }

    var tint: Color {
        switch self {
        case .microphone: .orange
        case .systemAudioRecording: .purple
        case .calendar: .red
        case .notifications: .blue
        }
    }
}

/// The app icon on Welcome and Done, the step's symbol on the others.
private struct OnboardingHero: View {
    var symbol: String?
    var tint: Color = .accentColor
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                        .frame(height: 64)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
            }
            .accessibilityHidden(true)
            Text(title).font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PermissionLabel: View {
    let permission: Permission
    let subtitle: String?

    var body: some View {
        Label {
            Text(permission.name)
            if let subtitle { Text(subtitle) }
        } icon: {
            Image(systemName: permission.symbol).foregroundStyle(permission.tint)
        }
    }
}

/// Settings › Permissions' look, with never asked told apart from denied.
private struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        switch status {
        case .allowed: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .notAsked: Text("Not asked yet").foregroundStyle(.secondary)
        case .denied: Text("Not allowed").foregroundStyle(.secondary)
        case .unknown: Text("Unknown").foregroundStyle(.secondary)
        }
    }
}

/// "Allow…" while never asked, "Open System Settings" once answered. Nothing once allowed.
private struct AllowButton: View {
    let model: AppModel
    let permission: Permission
    var isDefault = false

    var body: some View {
        switch model.permissions[permission] {
        case .allowed:
            EmptyView()
        case .notAsked:
            Button("Allow\u{2026}") { Task { await model.allow(permission) } }
                .keyboardShortcut(isDefault ? .defaultAction : nil)
                .accessibilityLabel("Allow \(permission.name)\u{2026}")
        case .denied, .unknown:
            Button("Open System Settings") { Task { await model.allow(permission) } }
                .keyboardShortcut(isDefault ? .defaultAction : nil)
                .accessibilityLabel("Open System Settings for \(permission.name)")
        }
    }
}

/// The Calendar step's accounts. An account's calendars open in a sheet from "Details…", as Wi-Fi's networks do
/// in System Settings, rather than an inline outline.
private struct CalendarAccountsSection: View {
    let accounts: CalendarAccounts
    let isAllowed: Bool
    @State private var inspected: CalendarAccount?

    var body: some View {
        Section {
            if !isAllowed {
                Text("Once you allow Calendar, the accounts Carbon reads show here.").foregroundStyle(.secondary)
            } else if accounts.accounts.isEmpty {
                LabeledContent("No calendar accounts yet") {
                    Button("Open Internet Accounts") { CalendarAccounts.openInternetAccounts() }
                }
            } else {
                ForEach(accounts.accounts) { account in
                    LabeledContent {
                        HStack {
                            Text("^[\(account.calendars.count) calendar](inflect: true)").foregroundStyle(.secondary)
                            Button("Details\u{2026}") { inspected = account }
                                .accessibilityLabel("Details for \(account.title)")
                        }
                    } label: {
                        Label {
                            Text(account.title).lineLimit(1).truncationMode(.middle).help(account.title)
                            if let kind = account.kind.subtitle(under: account.title) { Text(kind) }
                        } icon: {
                            Image(systemName: account.kind.symbol)
                        }
                    }
                }
            }
        } header: {
            Text("Accounts in Calendar")
        } footer: {
            if isAllowed, !accounts.accounts.isEmpty {
                HStack(spacing: 4) {
                    Text("Missing an account?").foregroundStyle(.secondary)
                    Button("Open Internet Accounts") { CalendarAccounts.openInternetAccounts() }.buttonStyle(.link)
                }
            }
        }
        .sheet(item: $inspected) { account in
            CalendarAccountDetails(account: account) { inspected = nil }
        }
    }
}

private struct CalendarAccountDetails: View {
    let account: CalendarAccount
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(account.title) {
                    ForEach(account.calendars) { calendar in
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Circle().fill(calendar.color).frame(width: 10, height: 10)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 380, height: 320)
    }
}

private extension CalendarAccountKind {
    var symbol: String {
        switch self {
        case .onMyMac: "laptopcomputer"
        case .exchange: "building.2"
        case .iCloud: "icloud"
        case .google, .internetAccount: "at"
        case .subscribed: "antenna.radiowaves.left.and.right"
        case .birthdays: "gift"
        case .other: "calendar"
        }
    }
}
