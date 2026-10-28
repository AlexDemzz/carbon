import UserNotifications

/// Posts Carbon's banners through the Notification Center, asking for permission the first time.
enum Notifier {
    static func post(_ body: String) async {
        await post(title: "Carbon", body: body)
    }

    /// Posts a banner whose buttons call `onAction` with the chosen action's identifier.
    @MainActor
    static func post(
        title: String, body: String, actions: [(id: String, title: String)] = [],
        onAction: (@MainActor (String) -> Void)? = nil
    ) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if !actions.isEmpty {
            let category = UNNotificationCategory(
                identifier: actions.map(\.id).joined(separator: "|") + ":" + actions.map(\.title).joined(separator: "|"),
                actions: actions.map { UNNotificationAction(identifier: $0.id, title: $0.title) },
                intentIdentifiers: [])
            let existing = await center.notificationCategories()
            center.setNotificationCategories(existing.union([category]))
            content.categoryIdentifier = category.identifier
        }
        let id = UUID().uuidString
        if let onAction { NotificationActions.shared.handlers[id] = onAction }
        center.delegate = NotificationActions.shared
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// Routes a banner's button back to the code that posted it.
@MainActor
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActions()
    var handlers: [String: @MainActor (String) -> Void] = [:]

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let (id, action) = (response.notification.request.identifier, response.actionIdentifier)
        await MainActor.run {
            guard let handler = handlers.removeValue(forKey: id) else { return }
            handler(action)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
