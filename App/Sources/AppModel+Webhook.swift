import AppKit
import CarbonCore
import Network

extension AppModel {
    /// Queues each new Meeting's event, and flushes the outbox once the network is known, on wake, when the network
    /// comes back and when a retry is due.
    func startWebhooks() {
        // Until the path monitor's first report: a launch offline must not use up attempts.
        webhooks.isOnline = false
        applyWebhookSettings()
        webhooks.onGiveUp = { [weak self] status in
            self?.notifier.post(
                status.response == .status(410)
                    ? "The webhook URL answered 410 Gone, so Carbon stopped sending \u{201C}\(status.title)\u{201D}."
                    : "Carbon couldn\u{2019}t send the webhook for \u{201C}\(status.title)\u{201D} and stopped trying.")
        }
        webhooks.onDiagnostic = { DiagnosticLog.shared.write($0) }
        library.onCreate = { [weak self] meeting, path in
            guard let self else { return }
            webhooks.meetingTranscribed(meeting, path: path, folder: library.folder)
            flushWebhooks()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            MainActor.assumeIsolated { self?.networkChanged(online: online) }
        }
        monitor.start(queue: .main)
        networkMonitor = monitor
        Task { [weak self] in
            // The retry timer runs on the continuous clock: left running, it would fire at wake, before the network.
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
                self?.webhooksAsleep = true
                self?.webhookRetry?.cancel()
            }
        }
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                // The path monitor may still report the network from before sleep: give it time to catch up.
                try? await Task.sleep(for: .seconds(10))
                self?.webhooksAsleep = false
                self?.flushWebhooks()
            }
        }
    }

    /// Settings › Webhook changed: the endpoint follows. Off, or with no valid URL, nothing is sent.
    func applyWebhookSettings() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.webhookEnabled) else {
            webhooks.endpoint = nil
            return
        }
        webhooks.endpoint = WebhookEndpoint(url: defaults.string(forKey: SettingsKey.webhookURL) ?? "", header: webhookHeader)
        flushWebhooks()
    }

    /// The auth header line, read from the Keychain only once the webhook is on. A failed read keeps the line read
    /// before, or empty, until Settings reads it again, so a denied Keychain prompt doesn't come back on every flush.
    private var webhookHeader: String {
        if let cachedWebhookHeader { return cachedWebhookHeader }
        return reloadWebhookHeader() ?? ""
    }

    /// Reads the header line from the Keychain again. Nil when it couldn't be read.
    @discardableResult
    func reloadWebhookHeader() -> String? {
        let header = WebhookSecret.read()
        cachedWebhookHeader = header ?? cachedWebhookHeader ?? ""
        return header
    }

    func saveWebhookHeader(_ header: String) {
        cachedWebhookHeader = header
        WebhookSecret.write(header)
        applyWebhookSettings()
    }

    /// "Send Test": a `webhook.test` event to the endpoint in Settings, once.
    func sendWebhookTest() async -> WebhookResponse? {
        guard let endpoint = webhooks.endpoint else { return nil }
        return await webhooks.sendTest(to: endpoint, folder: library.folder)
    }

    func flushWebhooks() {
        Task {
            // A flush already running schedules the next attempt itself once it's done.
            guard await webhooks.flush() else { return }
            scheduleWebhookRetry()
        }
    }

    private func networkChanged(online: Bool) {
        guard online != webhooks.isOnline else { return }
        webhooks.isOnline = online
        if online { flushWebhooks() }
    }

    /// A timer to the next due attempt. None while the Mac sleeps: the wake flush schedules it again.
    private func scheduleWebhookRetry() {
        webhookRetry?.cancel()
        guard !webhooksAsleep, webhooks.endpoint != nil, webhooks.isOnline, let next = webhooks.nextAttemptAt else { return }
        webhookRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.flushWebhooks()
        }
    }
}
