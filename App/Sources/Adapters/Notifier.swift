import CarbonCore
import Foundation
import UserNotifications

/// Carbon's notifications: start, offer, ready and recovery banners, and the actions the person takes on them.
@MainActor
final class Notifier: NSObject {
    enum Response {
        case stop(meetingID: UUID)
        case transcribe(app: String, language: Locale)
        /// The offer was dismissed.
        case decline(app: String)
        case never(app: String)
        case show(meetingID: UUID)
        /// "Switch to <app>" on the overlap banner, about the Meeting live when it was posted.
        case switchTo(app: String, meetingID: UUID)
    }

    /// Called on the main actor for each action the person takes.
    var onResponse: ((Response) -> Void)?

    private let center = UNUserNotificationCenter.current()
    /// Categories by identifier: offers get one per set of language actions.
    private var categories: [String: UNNotificationCategory] = [:]

    private enum ID {
        static let offer = "offer"
        static func start(_ meetingID: UUID) -> String { "start.\(meetingID.uuidString)" }
    }

    private enum Action {
        static let stop = "stop"
        static let show = "show"
        static let never = "never"
        static let transcribePrefix = "transcribe."
        static let switchTo = "switch"
    }

    fileprivate enum Key {
        static let meetingID = "meetingID"
        static let app = "app"
    }

    override init() {
        super.init()
        center.delegate = self
        register(UNNotificationCategory(
            identifier: "start",
            actions: [UNNotificationAction(identifier: Action.stop, title: "Stop", options: [.destructive])],
            intentIdentifiers: []))
        register(UNNotificationCategory(
            identifier: "ready",
            actions: [UNNotificationAction(identifier: Action.show, title: "Show", options: [.foreground])],
            intentIdentifiers: []))
    }

    /// The first-launch prompt. Later calls return the stored answer without asking.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// "Transcribing in <language>", "<title> · <Provider>", with Stop.
    func postStarted(_ meeting: LiveMeeting) {
        let content = UNMutableNotificationContent()
        content.title = "Transcribing in \(Self.languageName(meeting.language))"
        content.body = "\(meeting.title) \u{00B7} \(meeting.provider)"
        content.categoryIdentifier = "start"
        content.userInfo = [Key.meetingID: meeting.id.uuidString]
        add(ID.start(meeting.id), content)
    }

    /// "<title>", "<Provider> is using the microphone.", with Transcribe, Transcribe in <language> and Never.
    /// Dismissing it declines.
    func postOffer(_ offer: Recorder.Offer, otherLanguages: [Locale]) {
        let actions =
            [Self.transcribe(offer.language, title: "Transcribe")]
            + otherLanguages.map { Self.transcribe($0, title: "Transcribe in \(Self.languageName($0))") }
            + [UNNotificationAction(identifier: Action.never, title: "Never", options: [])]
        let category = "offer." + ([offer.language] + otherLanguages).map { $0.identifier(.bcp47) }.joined(separator: ",")
        register(UNNotificationCategory(
            identifier: category, actions: actions, intentIdentifiers: [], options: [.customDismissAction]))
        let content = UNMutableNotificationContent()
        content.title = offer.title
        content.body = "\(offer.provider) is using the microphone."
        content.categoryIdentifier = category
        content.userInfo = [Key.app: offer.app.bundleID]
        add(ID.offer, content)
    }

    /// "<Provider> is using the microphone.", "Carbon is still transcribing “<title>”.", with Switch to <Provider>.
    func postSwitchOffer(_ offer: Recorder.SwitchOffer) {
        let category = "switch." + offer.provider
        register(UNNotificationCategory(
            identifier: category,
            actions: [UNNotificationAction(identifier: Action.switchTo, title: "Switch to \(offer.provider)")],
            intentIdentifiers: []))
        let content = UNMutableNotificationContent()
        content.title = "\(offer.provider) is using the microphone."
        content.body = "Carbon is still transcribing “\(offer.meeting.title)”."
        content.categoryIdentifier = category
        content.userInfo = [Key.meetingID: offer.meeting.id.uuidString, Key.app: offer.app.bundleID]
        add(UUID().uuidString, content)
    }

    func withdrawOffer() {
        remove(ID.offer)
    }

    /// "<title>", "Transcript ready.", with Show. Takes the start banner away.
    func postReady(meetingID: UUID, title: String) {
        remove(ID.start(meetingID))
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Transcript ready."
        content.categoryIdentifier = "ready"
        content.userInfo = [Key.meetingID: meetingID.uuidString]
        add(UUID().uuidString, content)
    }

    func removeStarted(_ meetingID: UUID) {
        remove(ID.start(meetingID))
    }

    /// A plain banner, with Show when it is about a Meeting in the Library.
    func post(title: String = "Carbon", _ body: String, meetingID: UUID? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let meetingID {
            content.categoryIdentifier = "ready"
            content.userInfo = [Key.meetingID: meetingID.uuidString]
        }
        add(UUID().uuidString, content)
    }

    private func add(_ identifier: String, _ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error { DiagnosticLog.shared.write("Notification not posted: \(error.localizedDescription)") }
        }
    }

    private func remove(_ identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func register(_ category: UNNotificationCategory) {
        guard categories[category.identifier] == nil else { return }
        categories[category.identifier] = category
        center.setNotificationCategories(Set(categories.values))
    }

    private static func transcribe(_ language: Locale, title: String) -> UNNotificationAction {
        UNNotificationAction(identifier: Action.transcribePrefix + language.identifier(.bcp47), title: title, options: [])
    }

    static func languageName(_ language: Locale) -> String {
        let code = language.language.languageCode?.identifier ?? language.identifier
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    fileprivate func handle(action: String, meetingID: String?, app: String?) {
        let meetingID = meetingID.flatMap(UUID.init(uuidString:))
        let response: Response? =
            switch action {
            case Action.stop: meetingID.map { .stop(meetingID: $0) }
            case Action.show, UNNotificationDefaultActionIdentifier: meetingID.map { .show(meetingID: $0) }
            case Action.never: app.map { .never(app: $0) }
            case Action.switchTo: app.flatMap { app in meetingID.map { .switchTo(app: app, meetingID: $0) } }
            case UNNotificationDismissActionIdentifier: app.map { .decline(app: $0) }
            case let action where action.hasPrefix(Action.transcribePrefix):
                app.map {
                    .transcribe(
                        app: $0,
                        language: Locale(
                            identifier: Locale.identifier(
                                .icu, from: String(action.dropFirst(Action.transcribePrefix.count)))))
                }
            default: nil
            }
        if let response { onResponse?(response) }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let meetingID = userInfo[Key.meetingID] as? String
        let app = userInfo[Key.app] as? String
        await MainActor.run { handle(action: action, meetingID: meetingID, app: app) }
    }
}
