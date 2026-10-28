import UserNotifications

/// Posts Carbon's banners through the Notification Center, asking for permission the first time.
enum Notifier {
    static func post(_ body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Carbon"
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
