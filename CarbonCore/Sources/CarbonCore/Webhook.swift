import Foundation
import Observation

/// Where Carbon posts its webhook: Settings › Webhook's URL, with an optional auth header.
public struct WebhookEndpoint: Equatable, Sendable {
    public var url: URL
    /// A static header the receiver checks, such as n8n's Header Auth. Its value lives in the Keychain.
    public var header: (name: String, value: String)?

    public init(url: URL, header: (name: String, value: String)? = nil) {
        self.url = url
        self.header = header
    }

    /// The endpoint Settings describe, or nil when the URL isn't an `http(s)://` address with a host.
    /// An empty header name sends no header.
    public init?(url: String, headerName: String = "", headerValue: String = "") {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        let name = headerName.trimmingCharacters(in: .whitespaces)
        self.init(url: url, header: name.isEmpty ? nil : (name, headerValue))
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.url == b.url && a.header?.name == b.header?.name && a.header?.value == b.header?.value
    }
}

/// One POST to the endpoint.
public struct WebhookRequest: Equatable, Sendable {
    public var url: URL
    public var headers: [String: String]
    public var body: Data
}

/// What became of one attempt.
public enum WebhookResponse: Equatable, Sendable, Codable {
    /// The endpoint answered. Only 2xx is a delivery: a redirect is not followed, so 3xx is a failure.
    case status(Int)
    /// The Mac has no network.
    case offline
    case timedOut
    /// Any other failure, as the person can read it.
    case failed(String)

    public var isDelivered: Bool {
        if case .status(let code) = self { (200..<300).contains(code) } else { false }
    }
}

/// Sends one request and reports the outcome without throwing, such as `URLSession` with redirects refused.
public protocol WebhookTransport: Sendable {
    func send(_ request: WebhookRequest) async -> WebhookResponse
}

/// The JSON bodies Carbon sends: `{type, timestamp, data}`. One schema per `type`, changed only by adding fields.
public enum WebhookPayload {
    public static let meetingTranscribed = "meeting.transcribed"
    public static let test = "webhook.test"

    struct Body: Encodable {
        var type: String
        var test: Bool?
        var timestamp: String
        var data: MeetingData
    }

    struct MeetingData: Encodable {
        var id: UUID
        var title: String
        var provider: String
        var start: String
        var end: String
        var durationSeconds: Int
        var language: String
        var participants: [Participant]
        /// Relative to the Library folder.
        var path: String
        var absolutePath: String
    }

    /// The `meeting.transcribed` body of a Meeting whose file was just written at `path`, relative to `folder`.
    public static func meetingTranscribed(
        _ meeting: FinishedMeeting, path: String, folder: URL, writtenAt: Date
    ) -> Data {
        encode(Body(
            type: meetingTranscribed,
            timestamp: MeetingFormat.timestamp(writtenAt, in: meeting.timeZone),
            data: data(meeting, path: path, folder: folder)))
    }

    /// The `webhook.test` body: sample values in `meeting.transcribed`'s shape, marked `"test": true`.
    public static func test(folder: URL, now: Date, timeZone: TimeZone = .current) -> Data {
        let start = now.addingTimeInterval(-1_930)
        let sample = FinishedMeeting(
            id: UUID(), title: "Test from Carbon", start: start, end: now, timeZone: timeZone,
            language: Locale(identifier: "en_US"), provider: "Google Meet",
            participants: [Participant(name: "Jane Doe", email: "jane@example.com")], transcriptKind: .speakers)
        let path = "\(MeetingFormat.year(start, in: timeZone))/\(MeetingFormat.day(start, in: timeZone))-test-from-carbon.md"
        return encode(Body(
            type: test, test: true, timestamp: MeetingFormat.timestamp(now, in: timeZone),
            data: data(sample, path: path, folder: folder)))
    }

    private static func data(_ meeting: FinishedMeeting, path: String, folder: URL) -> MeetingData {
        MeetingData(
            id: meeting.id, title: meeting.title, provider: meeting.provider,
            start: MeetingFormat.timestamp(meeting.start, in: meeting.timeZone),
            end: MeetingFormat.timestamp(meeting.end, in: meeting.timeZone),
            durationSeconds: max(0, Int(meeting.end.timeIntervalSince(meeting.start).rounded(.down))),
            language: MeetingFormat.bcp47(meeting.language), participants: meeting.participants,
            path: path, absolutePath: folder.appending(path: path).path(percentEncoded: false))
    }

    private static func encode(_ body: Body) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // Every field is a String, a number or a Bool: encoding can't fail.
        return try! encoder.encode(body)
    }
}

/// An event waiting to reach the endpoint, kept in the outbox until it does or Carbon gives up.
public struct WebhookDelivery: Codable, Equatable, Sendable {
    /// `webhook-id`: the same on every attempt, so the receiver can dedupe.
    public var id: String
    /// The URL it was queued for. A different URL in Settings drops it.
    public var url: URL
    /// The Meeting's title, for the person only: Settings and the notification name it.
    public var title: String
    public var body: Data
    /// Attempts made while the Mac was online.
    public var attempts: Int
    public var nextAttemptAt: Date
}

/// The outcome Settings shows for the last delivery.
public struct WebhookStatus: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case delivered
        /// Failed, and another attempt is due later.
        case retrying
        /// Failed on every attempt, or answered 410 Gone: dropped.
        case gaveUp
    }

    public var date: Date
    public var title: String
    public var response: WebhookResponse
    public var outcome: Outcome
}

/// The webhook's outbox: events queued when a Meeting's file is first written, delivered one at a time, oldest
/// first, and kept in a file so they survive quit, crash and sleep. Carbon calls `flush()` at launch, on wake,
/// when the network comes back and when `nextAttemptAt` is due.
@MainActor
@Observable
public final class Webhooks {
    /// The waits after each failed attempt, about 3 days in all, after which a delivery is dropped.
    public static let retryDelays: [TimeInterval] = [
        5, 5 * 60, 30 * 60, 2 * 3600, 5 * 3600, 10 * 3600, 14 * 3600, 20 * 3600, 24 * 3600,
    ]

    /// Nil when the webhook is off or has no valid URL: nothing is queued. Pending deliveries for another URL are
    /// dropped.
    public var endpoint: WebhookEndpoint? {
        didSet {
            guard endpoint?.url != oldValue?.url else { return }
            let kept = outbox.deliveries.filter { $0.url == endpoint?.url }
            guard kept.count != outbox.deliveries.count else { return }
            outbox.deliveries = kept
            save()
        }
    }
    /// Offline, `flush()` waits for the network instead of using up attempts.
    @ObservationIgnored public var isOnline = true
    /// A delivery was dropped: it failed on every attempt, or the endpoint answered 410 Gone.
    @ObservationIgnored public var onGiveUp: ((WebhookStatus) -> Void)?

    public var last: WebhookStatus? { outbox.last }
    public var pending: [WebhookDelivery] { outbox.deliveries }
    /// When the next pending delivery is due, or nil when none is.
    public var nextAttemptAt: Date? { outbox.deliveries.map(\.nextAttemptAt).min() }

    private struct Outbox: Codable {
        var deliveries: [WebhookDelivery] = []
        var last: WebhookStatus?
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let transport: any WebhookTransport
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeID: @Sendable () -> String
    private var outbox: Outbox
    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var flushAgain = false

    /// - Parameter file: the outbox, `webhooks.json` next to `meetings.json`.
    public init(
        file: URL, transport: any WebhookTransport, now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { "msg_\(UUID().uuidString)" }
    ) {
        self.file = file
        self.transport = transport
        self.now = now
        self.makeID = makeID
        outbox = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Outbox.self, from: $0) } ?? Outbox()
    }

    /// Queues the `meeting.transcribed` event of a Meeting whose file was just written. Nothing when the webhook is off.
    public func meetingTranscribed(_ meeting: FinishedMeeting, path: String, folder: URL) {
        guard let endpoint else { return }
        let date = now()
        outbox.deliveries.append(WebhookDelivery(
            id: makeID(), url: endpoint.url, title: meeting.title,
            body: WebhookPayload.meetingTranscribed(meeting, path: path, folder: folder, writtenAt: date),
            attempts: 0, nextAttemptAt: date))
        save()
    }

    /// Sends every due delivery, one at a time, oldest first. A delivery that fails waits its turn again, so it
    /// never holds up the others. A call while one runs makes that one go round again.
    public func flush() async {
        guard !isFlushing else {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        repeat {
            flushAgain = false
            var tried = Set<String>()
            while isOnline, let endpoint,
                let delivery = outbox.deliveries.first(where: { $0.nextAttemptAt <= now() && !tried.contains($0.id) })
            {
                tried.insert(delivery.id)
                let response = await transport.send(request(delivery.body, id: delivery.id, to: endpoint))
                record(response, for: delivery.id)
            }
        } while flushAgain
    }

    /// Sends a `webhook.test` event once, outside the outbox, with no retries.
    public func sendTest(to endpoint: WebhookEndpoint, folder: URL) async -> WebhookResponse {
        await transport.send(request(WebhookPayload.test(folder: folder, now: now()), id: makeID(), to: endpoint))
    }

    private func request(_ body: Data, id: String, to endpoint: WebhookEndpoint) -> WebhookRequest {
        var headers = [
            "Content-Type": "application/json",
            "webhook-id": id,
            "webhook-timestamp": String(Int(now().timeIntervalSince1970)),
        ]
        if let header = endpoint.header { headers[header.name] = header.value }
        return WebhookRequest(url: endpoint.url, headers: headers, body: body)
    }

    private func record(_ response: WebhookResponse, for id: String) {
        // Settings may have dropped it while the request was out.
        guard let position = outbox.deliveries.firstIndex(where: { $0.id == id }) else { return }
        var delivery = outbox.deliveries[position]
        // The path monitor said offline: the attempt never had a chance, so it doesn't count.
        if response == .offline, !isOnline { return }
        let outcome: WebhookStatus.Outcome
        if response.isDelivered {
            outcome = .delivered
        } else if response == .status(410) || delivery.attempts >= Self.retryDelays.count {
            outcome = .gaveUp
        } else {
            outcome = .retrying
        }
        if outcome == .retrying {
            delivery.nextAttemptAt = now().addingTimeInterval(Self.retryDelays[delivery.attempts])
            delivery.attempts += 1
            outbox.deliveries[position] = delivery
        } else {
            outbox.deliveries.remove(at: position)
        }
        let status = WebhookStatus(date: now(), title: delivery.title, response: response, outcome: outcome)
        outbox.last = status
        save()
        if outcome == .gaveUp { onGiveUp?(status) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(outbox).write(to: file, options: .atomic)
        } catch {
            // The outbox stays in memory: the delivery goes out, it just won't survive a quit.
        }
    }
}
