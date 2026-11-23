import CarbonCore
import Foundation
import Synchronization
import Testing

/// Answers each request with the next scripted response, `.status(200)` once the script runs out.
final class ScriptedTransport: WebhookTransport {
    private let state: Mutex<(script: [WebhookResponse], sent: [WebhookRequest])>

    init(_ script: [WebhookResponse] = []) {
        state = Mutex((script, []))
    }

    var sent: [WebhookRequest] { state.withLock { $0.sent } }

    func send(_ request: WebhookRequest) async -> WebhookResponse {
        state.withLock { state in
            state.sent.append(request)
            return state.script.isEmpty ? .status(200) : state.script.removeFirst()
        }
    }
}

@MainActor
struct WebhookTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-01-15T14:02:10Z"))
    let paris = TimeZone(identifier: "Europe/Paris")!
    let endpoint = WebhookEndpoint(url: "https://n8n.example.com/webhook/carbon", headerName: "X-Carbon-Key", headerValue: "s3cret")!

    var outboxFile: URL { support.url.appending(path: "webhooks.json") }

    func makeWebhooks(_ transport: ScriptedTransport, endpoint: WebhookEndpoint? = nil) -> Webhooks {
        let clock = clock
        let webhooks = Webhooks(file: outboxFile, transport: transport, now: { clock.now })
        webhooks.endpoint = endpoint ?? self.endpoint
        return webhooks
    }

    func meeting(_ title: String = "Remote control kickoff") -> FinishedMeeting {
        FinishedMeeting(
            id: UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!, title: title,
            start: date("2026-01-15T13:30:00Z"), end: date("2026-01-15T14:02:10Z"), timeZone: paris,
            language: Locale(identifier: "en_US"), provider: "Google Meet",
            participants: [Participant(name: "Dana Whitfield", email: "dana@example.com"), Participant(name: "Marcus Lee")],
            transcriptKind: .speakers)
    }

    func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Event

    @Test func aMeetingIsSentAsAThinMeetingTranscribedEvent() async throws {
        let transport = ScriptedTransport()
        let webhooks = makeWebhooks(transport)

        webhooks.meetingTranscribed(meeting(), path: "2026/2026-01-15-remote-control-kickoff.md", folder: folder.url)
        await webhooks.flush()

        let request = try #require(transport.sent.only)
        #expect(request.url == URL(string: "https://n8n.example.com/webhook/carbon"))
        let body = try json(request.body)
        #expect(body["type"] as? String == "meeting.transcribed")
        #expect(body["test"] == nil)
        #expect(body["timestamp"] as? String == "2026-01-15T15:02:10+01:00")
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["id"] as? String == "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")
        #expect(data["title"] as? String == "Remote control kickoff")
        #expect(data["provider"] as? String == "Google Meet")
        #expect(data["start"] as? String == "2026-01-15T14:30:00+01:00")
        #expect(data["end"] as? String == "2026-01-15T15:02:10+01:00")
        #expect(data["durationSeconds"] as? Int == 1930)
        #expect(data["language"] as? String == "en-US")
        #expect(data["path"] as? String == "2026/2026-01-15-remote-control-kickoff.md")
        #expect(data["absolutePath"] as? String
            == folder.url.appending(path: "2026/2026-01-15-remote-control-kickoff.md").path(percentEncoded: false))
        #expect(data["transcript"] == nil)
        let participants = try #require(data["participants"] as? [[String: String]])
        #expect(participants == [["name": "Dana Whitfield", "email": "dana@example.com"], ["name": "Marcus Lee"]])
    }

    @Test func theRequestCarriesStandardWebhooksHeadersAndTheAuthHeader() async throws {
        let transport = ScriptedTransport()
        let webhooks = Webhooks(
            file: outboxFile, transport: transport, now: { [clock] in clock.now }, makeID: { "msg_fixed" })
        webhooks.endpoint = endpoint

        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)
        await webhooks.flush()

        let headers = try #require(transport.sent.only).headers
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["webhook-id"] == "msg_fixed")
        #expect(headers["webhook-timestamp"] == "1768485730")
        #expect(headers["X-Carbon-Key"] == "s3cret")
    }

    @Test func theTestEventIsMarkedAndNeverQueued() async throws {
        let transport = ScriptedTransport([.status(401)])
        let webhooks = makeWebhooks(transport)

        let response = await webhooks.sendTest(to: endpoint, folder: folder.url)

        #expect(response == .status(401))
        let body = try json(try #require(transport.sent.only).body)
        #expect(body["type"] as? String == "webhook.test")
        #expect(body["test"] as? Bool == true)
        #expect((body["data"] as? [String: Any])?["title"] as? String == "Test from Carbon")
        #expect(webhooks.pending.isEmpty)
        #expect(webhooks.last == nil)
    }

    @Test func nothingIsQueuedWhileTheWebhookIsOff() async {
        let transport = ScriptedTransport()
        let webhooks = Webhooks(file: outboxFile, transport: transport)

        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)
        await webhooks.flush()

        #expect(transport.sent.isEmpty)
        #expect(webhooks.pending.isEmpty)
    }

    // MARK: Settings

    @Test(arguments: ["", "n8n.local/webhook", "ftp://example.com/x", "https://", "not a url"])
    func onlyAnHTTPAddressWithAHostIsAnEndpoint(url: String) {
        #expect(WebhookEndpoint(url: url) == nil)
    }

    @Test func anEmptyHeaderNameSendsNoHeader() {
        #expect(WebhookEndpoint(url: " http://192.168.1.10:5678/webhook ", headerName: " ", headerValue: "x")
            == WebhookEndpoint(url: URL(string: "http://192.168.1.10:5678/webhook")!))
    }

    @Test func changingTheURLDropsPendingDeliveries() async {
        let transport = ScriptedTransport([.status(500)])
        let webhooks = makeWebhooks(transport)
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)
        await webhooks.flush()

        webhooks.endpoint = WebhookEndpoint(url: "https://other.example.com/hook")
        clock.advance(by: 3600)
        await webhooks.flush()

        #expect(transport.sent.count == 1)
        #expect(webhooks.pending.isEmpty)
    }

    @Test func turningTheWebhookOffDropsPendingDeliveries() {
        let webhooks = makeWebhooks(ScriptedTransport())
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        webhooks.endpoint = nil

        #expect(webhooks.pending.isEmpty)
    }

    @Test func changingOnlyTheHeaderKeepsPendingDeliveriesAndSendsTheNewOne() async throws {
        let transport = ScriptedTransport()
        let webhooks = makeWebhooks(transport)
        webhooks.isOnline = false
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        webhooks.endpoint = WebhookEndpoint(url: endpoint.url.absoluteString, headerName: "Authorization", headerValue: "Bearer t")
        webhooks.isOnline = true
        await webhooks.flush()

        let headers = try #require(transport.sent.only).headers
        #expect(headers["Authorization"] == "Bearer t")
        #expect(headers["X-Carbon-Key"] == nil)
    }

    // MARK: Delivery

    @Test func aDeliverySurvivesARelaunch() async throws {
        let webhooks = makeWebhooks(ScriptedTransport())
        webhooks.isOnline = false
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        let transport = ScriptedTransport()
        let relaunched = makeWebhooks(transport)
        await relaunched.flush()

        #expect(transport.sent.count == 1)
        #expect(relaunched.pending.isEmpty)
        #expect(relaunched.last?.outcome == .delivered)
    }

    @Test func theWebhookIdStaysTheSameAcrossRetries() async throws {
        let transport = ScriptedTransport([.status(503), .timedOut])
        let webhooks = makeWebhooks(transport)
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        for _ in 0..<3 {
            await webhooks.flush()
            clock.advance(by: 3600)
        }

        let ids = Set(transport.sent.map { $0.headers["webhook-id"] })
        #expect(transport.sent.count == 3)
        #expect(ids.count == 1)
        #expect(webhooks.pending.isEmpty)
    }

    @Test func aFailedDeliveryWaitsForItsNextAttempt() async throws {
        let transport = ScriptedTransport([.status(500)])
        let webhooks = makeWebhooks(transport)
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)
        await webhooks.flush()

        clock.advance(by: 4)
        await webhooks.flush()
        #expect(transport.sent.count == 1)
        #expect(webhooks.nextAttemptAt == date("2026-01-15T14:02:15Z"))
        #expect(webhooks.last?.outcome == .retrying)

        clock.advance(by: 1)
        await webhooks.flush()
        #expect(transport.sent.count == 2)
    }

    @Test func aDeliveryIsDroppedAfterAboutThreeDaysOfFailures() async throws {
        let transport = ScriptedTransport(Array(repeating: .status(500), count: 20))
        let webhooks = makeWebhooks(transport)
        var givenUp: [WebhookStatus] = []
        webhooks.onGiveUp = { givenUp.append($0) }
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)
        let start = clock.now

        while let next = webhooks.nextAttemptAt {
            clock.set(next)
            await webhooks.flush()
        }

        #expect(transport.sent.count == Webhooks.retryDelays.count + 1)
        let span = clock.now.timeIntervalSince(start) / 3600
        #expect((72...80).contains(span))
        #expect(givenUp.map(\.outcome) == [.gaveUp])
        #expect(givenUp.first?.title == "Remote control kickoff")
    }

    @Test func goneStopsRetryingAtOnce() async throws {
        let transport = ScriptedTransport([.status(410)])
        let webhooks = makeWebhooks(transport)
        var givenUp: [WebhookStatus] = []
        webhooks.onGiveUp = { givenUp.append($0) }
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        await webhooks.flush()

        #expect(webhooks.pending.isEmpty)
        #expect(givenUp.map(\.response) == [.status(410)])
    }

    @Test(arguments: [WebhookResponse.status(301), .status(302), .status(404), .timedOut, .failed("Connection reset")])
    func anythingButTwoHundredsIsRetried(response: WebhookResponse) async throws {
        let webhooks = makeWebhooks(ScriptedTransport([response]))
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        await webhooks.flush()

        #expect(webhooks.pending.map(\.attempts) == [1])
        #expect(webhooks.last?.outcome == .retrying)
    }

    @Test func offlineTimeUsesUpNoAttempt() async throws {
        let transport = ScriptedTransport()
        let webhooks = makeWebhooks(transport)
        webhooks.isOnline = false
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        clock.advance(by: 7 * 24 * 3600)
        await webhooks.flush()
        #expect(transport.sent.isEmpty)

        webhooks.isOnline = true
        await webhooks.flush()
        #expect(transport.sent.count == 1)
        #expect(webhooks.pending.isEmpty)
    }

    @Test func notConnectedWhileThePathLooksOnlineCountsAsAnAttempt() async throws {
        // A denied Local Network prompt fails as "not connected" on a working network: it must not retry forever.
        let webhooks = makeWebhooks(ScriptedTransport([.offline]))
        webhooks.meetingTranscribed(meeting(), path: "2026/a.md", folder: folder.url)

        await webhooks.flush()

        #expect(webhooks.pending.map(\.attempts) == [1])
    }

    @Test func aFailingDeliveryDoesNotHoldUpTheNextOne() async throws {
        let transport = ScriptedTransport([.status(500), .status(200)])
        let webhooks = makeWebhooks(transport)
        webhooks.meetingTranscribed(meeting("First"), path: "2026/a.md", folder: folder.url)
        webhooks.meetingTranscribed(meeting("Second"), path: "2026/b.md", folder: folder.url)

        await webhooks.flush()

        #expect(transport.sent.map { try! json($0.body)["data"].flatMap { ($0 as? [String: Any])?["path"] as? String } }
            == ["2026/a.md", "2026/b.md"])
        #expect(webhooks.pending.map(\.title) == ["First"])
        #expect(webhooks.last?.title == "Second")
    }

    // MARK: Library

    @Test func onlyWritingAMeetingsFileSendsAnEvent() async throws {
        let clock = clock
        let library = Library(folder: folder.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in })
        let transport = ScriptedTransport()
        let webhooks = makeWebhooks(transport)
        library.onCreate = { meeting, path in webhooks.meetingTranscribed(meeting, path: path, folder: library.folder) }

        let url = try library.create(meeting(), transcript: "## Transcript\n\n**Speaker A** [0:00] Hello.\n")
        try library.load()
        let id = meeting().id
        try library.rename(id, title: "Renamed")
        try library.renameSpeaker(id, label: "Speaker A", name: "Sam Rivera", email: "sam@example.com")
        try library.save(id, editedMarkdown: try String(contentsOf: url, encoding: .utf8) + "\nMy note.\n")
        try library.delete(id)
        await webhooks.flush()

        let request = try #require(transport.sent.only)
        let data = try #require(try json(request.body)["data"] as? [String: Any])
        #expect(data["path"] as? String == "2026/2026-01-15-remote-control-kickoff.md")
        #expect(data["title"] as? String == "Remote control kickoff")
    }
}

extension Array {
    /// The single element, or nil when there are none or several.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
