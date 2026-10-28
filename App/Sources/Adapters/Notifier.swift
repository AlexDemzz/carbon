import CarbonCore
import Foundation
import UserNotifications

/// Carbon's notifications: start, offer, ready and recovery banners, and the actions the person takes on them.
@MainActor
final class Notifier: NSObject {
    enum Response {
        case stop(meetingID: UUID)
        case switchLanguage(meetingID: UUID, language: Locale)
        case transcribe(app: String, language: Locale)
        /// The offer was dismissed.
        case decline(app: String)
        case never(app: String)
        case show(meetingID: UUID)
    }

    /// Called on the main actor for each action the person takes.
    var onResponse: ((Response) -> Void)?

    private let center = UNUserNotificationCenter.current()
    /// Categories by identifier: start banners and offers get one per set of language actions.
    private var categories: [String: UNNotificationCategory] = [:]
    /// The Meetings whose start banner is up.
    private var started: Set<UUID> = []

    private enum ID {
        static let offer = "offer"
        static func start(_ meetingID: UUID) -> String { "start.\(meetingID.uuidString)" }
    }

    private enum Action {
        static let stop = "stop"
        static let show = "show"
        static let never = "never"
        static let transcribePrefix = "transcribe."
        static let switchPrefix = "switch."
    }

    fileprivate enum Key {
        static let meetingID = "meetingID"
        static let app = "app"
    }

    override init() {
        super.init()
        center.delegate = self
        register(UNNotificationCategory(
            identifier: "ready",
            actions: [UNNotificationAction(identifier: Action.show, title: "Show", options: [.foreground])],
            intentIdentifiers: []))
    }

    /// The first-launch prompt. Later calls return the stored answer without asking.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// "Transcribing in <language>", "<title> · <Provider>", with Stop and one "Switch to <language>" per other
    /// Meeting Language.
    func postStarted(_ meeting: LiveMeeting, languages: MeetingLanguages?) {
        let others = languages?.others(than: meeting.language) ?? []
        let actions =
            [UNNotificationAction(identifier: Action.stop, title: "Stop", options: [.destructive])]
            + others.map {
                UNNotificationAction(
                    identifier: Action.switchPrefix + $0.identifier(.bcp47),
                    title: "Switch to \(Self.name(of: $0, in: languages))", options: [])
            }
        let category = (["start"] + others.map { $0.identifier(.bcp47) }).joined(separator: ".")
        register(UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: []))
        let content = UNMutableNotificationContent()
        content.title = "Transcribing in \(Self.name(of: meeting.language, in: languages))"
        content.body = "\(meeting.title) \u{00B7} \(meeting.provider)"
        content.categoryIdentifier = category
        content.userInfo = [Key.meetingID: meeting.id.uuidString]
        started.insert(meeting.id)
        add(ID.start(meeting.id), content)
    }

    /// Replaces the start banner, if it is still up, after the Meeting changed language.
    func restateStarted(_ meeting: LiveMeeting, languages: MeetingLanguages?) {
        guard started.contains(meeting.id) else { return }
        postStarted(meeting, languages: languages)
    }

    /// "<title>", "<Provider> is using the microphone.", with Transcribe, Transcribe in <language> and Never.
    /// Dismissing it declines.
    func postOffer(_ offer: Recorder.Offer, languages: MeetingLanguages?) {
        let otherLanguages = languages?.others(than: offer.language) ?? []
        let actions =
            [Self.transcribe(offer.language, title: "Transcribe")]
            + otherLanguages.map { Self.transcribe($0, title: "Transcribe in \(Self.name(of: $0, in: languages))") }
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

    func withdrawOffer() {
        remove(ID.offer)
    }

    /// "<title>", "Transcript ready.", with Show. Takes the start banner away.
    func postReady(meetingID: UUID, title: String) {
        removeStarted(meetingID)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Transcript ready."
        content.categoryIdentifier = "ready"
        content.userInfo = [Key.meetingID: meetingID.uuidString]
        add(UUID().uuidString, content)
    }

    func removeStarted(_ meetingID: UUID) {
        started.remove(meetingID)
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

    private static func name(of language: Locale, in languages: MeetingLanguages?) -> String {
        languages?.name(of: language) ?? languageName(language)
    }

    private static func language(_ action: String, after prefix: String) -> Locale {
        Locale(identifier: Locale.identifier(.icu, from: String(action.dropFirst(prefix.count))))
    }

    fileprivate func handle(action: String, meetingID: String?, app: String?) {
        let meetingID = meetingID.flatMap(UUID.init(uuidString:))
        let response: Response? =
            switch action {
            case Action.stop: meetingID.map { .stop(meetingID: $0) }
            case Action.show, UNNotificationDefaultActionIdentifier: meetingID.map { .show(meetingID: $0) }
            case Action.never: app.map { .never(app: $0) }
            case UNNotificationDismissActionIdentifier: app.map { .decline(app: $0) }
            case let action where action.hasPrefix(Action.transcribePrefix):
                app.map { .transcribe(app: $0, language: Self.language(action, after: Action.transcribePrefix)) }
            case let action where action.hasPrefix(Action.switchPrefix):
                meetingID.map {
                    .switchLanguage(meetingID: $0, language: Self.language(action, after: Action.switchPrefix))
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
