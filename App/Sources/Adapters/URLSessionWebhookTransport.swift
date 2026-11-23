import CarbonCore
import Foundation

/// Posts the webhook with `URLSession`: 30 s per attempt, no cookies or cache, and redirects refused, so a
/// redirected POST can't count a landing page's 200 as a delivery.
final class URLSessionWebhookTransport: NSObject, WebhookTransport, URLSessionTaskDelegate {
    private let session: URLSession
    private let userAgent: String

    init(version: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        userAgent = "Carbon/\(version)"
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ request: WebhookRequest) async -> WebhookResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (_, response) = try await session.data(for: urlRequest, delegate: self)
            guard let response = response as? HTTPURLResponse else { return .failed("Not an HTTP response") }
            return .status(response.statusCode)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: return .timedOut
            case .notConnectedToInternet, .dataNotAllowed: return .offline
            case .appTransportSecurityRequiresSecureConnection:
                return .failed("http:// works only on your local network. Use https://.")
            default: return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
