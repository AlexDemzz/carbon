import AppKit
import CarbonCore
import Network

extension AppModel {
    /// Queues each new Meeting's event, and flushes the outbox at launch, on wake, when the network comes back and
    /// when a retry is due.
    func startWebhooks() {
        applyWebhookSettings()
        webhooks.onGiveUp = { [weak self] status in
            self?.notifier.post(
                status.response == .status(410)
                    ? "The webhook URL answered 410 Gone, so Carbon stopped sending \u{201C}\(status.title)\u{201D}."
                    : "Carbon couldn\u{2019}t send the webhook for \u{201C}\(status.title)\u{201D} and stopped trying.")
        }
        library.onCreate = { [weak self] meeting, path in
            guard let self else { return }
            webhooks.meetingTranscribed(meeting, path: path, folder: library.folder)
            flushWebhooks()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: .main)
        networkMonitor = monitor
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                self?.flushWebhooks()
            }
        }
        flushWebhooks()
    }

    /// Settings › Webhook changed: the endpoint follows. Off, or with no valid URL, nothing is sent.
    func applyWebhookSettings() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.webhookEnabled) else {
            webhooks.endpoint = nil
            return
        }
        webhooks.endpoint = WebhookEndpoint(
            url: defaults.string(forKey: SettingsKey.webhookURL) ?? "",
            headerName: defaults.string(forKey: SettingsKey.webhookHeaderName) ?? "",
            headerValue: webhookHeaderValue)
        flushWebhooks()
    }

    /// The auth header's value, read from the Keychain only once the webhook is on.
    var webhookHeaderValue: String {
        get {
            if let cachedWebhookHeaderValue { return cachedWebhookHeaderValue }
            let value = WebhookSecret.read()
            cachedWebhookHeaderValue = value
            return value
        }
        set {
            guard newValue != webhookHeaderValue else { return }
            cachedWebhookHeaderValue = newValue
            WebhookSecret.write(newValue)
            applyWebhookSettings()
        }
    }

    /// "Send Test": a `webhook.test` event to the endpoint in Settings, once.
    func sendWebhookTest() async -> WebhookResponse? {
        guard let endpoint = webhooks.endpoint else { return nil }
        return await webhooks.sendTest(to: endpoint, folder: library.folder)
    }

    func flushWebhooks() {
        Task {
            await webhooks.flush()
            scheduleWebhookRetry()
        }
    }

    private func networkChanged(online: Bool) {
        guard online != webhooks.isOnline else { return }
        webhooks.isOnline = online
        if online { flushWebhooks() }
    }

    /// A timer to the next due attempt. Its sleep runs on the continuous clock, so it fires on wake if it fell due
    /// during sleep.
    private func scheduleWebhookRetry() {
        webhookRetry?.cancel()
        guard webhooks.endpoint != nil, webhooks.isOnline, let next = webhooks.nextAttemptAt else { return }
        webhookRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.flushWebhooks()
        }
    }
}
