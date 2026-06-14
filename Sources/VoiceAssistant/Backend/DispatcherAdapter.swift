import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Default adapter wired up in v0.1. POSTs the transcribed text to
/// the Hummingbird backend, which forwards into a Claude Code session
/// via the Happy inject API and returns the assistant's reply.
///
/// One of several future adapters. An open-source / sellable build of
/// the project will swap DispatcherAdapter for SlackAdapter,
/// RawHTTPAdapter, or OwnServerAdapter without touching the UI layer.
///
/// Wire format: specs/backend-protocol.md (POST /v1/voice/intent).
public struct DispatcherAdapter: BackendAdapter {

    public let baseURL: URL
    public let token: String
    public let session: URLSession

    public init(
        baseURL: URL,
        token: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func send(_ request: TranscribedRequest) async throws -> Reply {
        let url = baseURL.appendingPathComponent("/v1/voice/intent")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encodeBody(request)
        urlRequest.timeoutInterval = 15  // per backend-protocol.md client hard cap

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            if urlError.code == .timedOut { throw BackendError.timeout }
            throw BackendError.network(underlying: urlError.localizedDescription)
        } catch {
            throw BackendError.network(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.malformedResponse("not http")
        }

        switch http.statusCode {
        case 200:
            return try decodeSuccess(data: data)
        case 401:
            throw BackendError.unauthorized
        case 403:
            throw BackendError.forbidden
        case 429:
            throw BackendError.rateLimited(retryAfterMs: decode429RetryAfter(data))
        case 503:
            throw BackendError.backendUnavailable
        case 500...599:
            throw BackendError.backendUnavailable
        default:
            throw BackendError.malformedResponse("unexpected HTTP \(http.statusCode)")
        }
    }

    // MARK: - Body / response decoding

    private func encodeBody(_ request: TranscribedRequest) throws -> Data {
        let iso = ISO8601DateFormatter.dispatcherFractionalSeconds.string(from: request.timestamp)
        let dict: [String: Any] = [
            "text": request.text,
            "client_id": request.clientId,
            "ts": iso,
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func decodeSuccess(data: Data) throws -> Reply {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["reply"] as? String,
            let ms = json["latency_ms"] as? Int
        else {
            throw BackendError.malformedResponse("missing reply / latency_ms")
        }
        return Reply(text: text, latencyMs: ms)
    }

    private func decode429RetryAfter(_ data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["retry_after_ms"] as? Int
    }
}

private extension ISO8601DateFormatter {
    static let dispatcherFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
