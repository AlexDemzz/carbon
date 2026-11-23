import CarbonCore
import SwiftUI

/// Settings › Webhook: off by default. On, Carbon posts each new Meeting's details to the person's URL.
struct WebhookSettings: View {
    let model: AppModel
    @AppStorage(SettingsKey.webhookEnabled) private var enabled = false
    @AppStorage(SettingsKey.webhookURL) private var url = ""
    @AppStorage(SettingsKey.webhookHeaderName) private var headerName = ""
    @State private var headerValue = ""
    @State private var test: TestState = .idle

    private enum TestState: Equatable {
        case idle, sending
        case done(WebhookResponse)
    }

    private var urlIsValid: Bool { WebhookEndpoint(url: url) != nil }

    var body: some View {
        Form {
            Section {
                Toggle("Send a webhook when a Meeting is transcribed", isOn: $enabled)
            } footer: {
                Text(
                    "Carbon posts each new Meeting\u{2019}s title, date, participants and file path to your URL, never its Transcript."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                TextField("URL", text: $url, prompt: Text(verbatim: "https://example.com/webhook"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                if !url.isEmpty, !urlIsValid {
                    Label("Enter an address that starts with https:// or http://.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                TextField("Header name", text: $headerName, prompt: Text("Optional, such as Authorization"))
                    .autocorrectionDisabled()
                SecureField("Header value", text: $headerValue)
                HStack {
                    Button("Send Test") { sendTest() }
                        .disabled(!urlIsValid || test == .sending)
                    testResult
                }
            } footer: {
                Text(
                    "http:// works only on your local network, where titles and participant emails travel unencrypted. The first time, macOS asks to let Carbon find devices on your local network."
                )
                .foregroundStyle(.secondary)
            }
            .disabled(!enabled)
            Section {
                LabeledContent("Last delivery") { lastDelivery }
                if !model.webhooks.pending.isEmpty {
                    LabeledContent("Waiting to send", value: model.webhooks.pending.count.formatted())
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if enabled { headerValue = model.webhookHeaderValue }
        }
        .onChange(of: enabled) { _, on in
            if on { headerValue = model.webhookHeaderValue }
            model.applyWebhookSettings()
        }
        .onChange(of: url) {
            test = .idle
            model.applyWebhookSettings()
        }
        .onChange(of: headerName) { model.applyWebhookSettings() }
        .onChange(of: headerValue) { _, value in
            guard enabled else { return }
            model.webhookHeaderValue = value
        }
    }

    @ViewBuilder private var testResult: some View {
        switch test {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView().controlSize(.small)
        case .done(let response):
            if response.isDelivered {
                Label(Self.describe(response), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label(Self.describe(response), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var lastDelivery: some View {
        if let last = model.webhooks.last {
            VStack(alignment: .trailing) {
                Text("\u{201C}\(last.title)\u{201D}, \(last.date.formatted(date: .abbreviated, time: .shortened))")
                Text(Self.describe(last))
                    .foregroundStyle(last.outcome == .delivered ? Color.secondary : Color.red)
            }
        } else {
            Text("None yet").foregroundStyle(.secondary)
        }
    }

    private func sendTest() {
        test = .sending
        Task {
            test = await model.sendWebhookTest().map(TestState.done) ?? .idle
        }
    }

    private static func describe(_ status: WebhookStatus) -> String {
        switch status.outcome {
        case .delivered: describe(status.response)
        case .retrying: "\(describe(status.response)). Carbon will try again."
        case .gaveUp: "\(describe(status.response)). Carbon stopped trying."
        }
    }

    private static func describe(_ response: WebhookResponse) -> String {
        switch response {
        case .status(let code) where (200..<300).contains(code): "Delivered (\(code))"
        case .status(let code) where (300..<400).contains(code): "Redirected (\(code)): use the final URL"
        case .status(let code): "Failed (\(code))"
        case .offline: "Not connected. If you denied Local Network access, allow it in System Settings."
        case .timedOut: "Timed out after 30 seconds"
        case .failed(let message): message
        }
    }
}
