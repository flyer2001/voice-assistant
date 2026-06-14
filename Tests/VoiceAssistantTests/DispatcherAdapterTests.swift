import Foundation
import Testing
@testable import VoiceAssistant

@Suite("DispatcherAdapter — contract against POST /v1/voice/intent", .serialized)
struct DispatcherAdapterTests {

    @Test("200 OK with {reply, latency_ms} decodes into Reply")
    func happyPath() async throws {
        let adapter = makeAdapter { request in
            #expect(request.url?.path == "/v1/voice/intent")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"reply":"3 open issues","latency_ms":1840}"#.utf8)
            )
        }

        let reply = try await adapter.send(TranscribedRequest(
            text: "status cashflow",
            clientId: "iphone-15",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000)
        ))

        #expect(reply == Reply(text: "3 open issues", latencyMs: 1840))
    }

    @Test("Body is JSON with text / client_id / ISO8601 ts")
    func bodyShape() async throws {
        let adapter = makeAdapter { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"reply":"ok","latency_ms":1}"#.utf8)
            )
        }

        _ = try await adapter.send(TranscribedRequest(
            text: "привет",
            clientId: "iphone-tester",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000)
        ))

        let body = MockURLProtocol.lastBody ?? Data()
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["text"] as? String == "привет")
        #expect(json["client_id"] as? String == "iphone-tester")
        let ts = try #require(json["ts"] as? String)
        #expect(ts.hasPrefix("2025-06-15T"))
    }

    @Test("401 maps to .unauthorized")
    func unauthorized() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"unauthorized"}"#.utf8))
        }
        await #expect(throws: BackendError.unauthorized) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("403 maps to .forbidden")
    func forbidden() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"forbidden"}"#.utf8))
        }
        await #expect(throws: BackendError.forbidden) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("429 with retry_after_ms maps to .rateLimited(retryAfterMs: 5000)")
    func rateLimitedWithRetryAfter() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"rate_limited","retry_after_ms":5000}"#.utf8))
        }
        await #expect(throws: BackendError.rateLimited(retryAfterMs: 5000)) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("429 without retry_after_ms maps to .rateLimited(retryAfterMs: nil)")
    func rateLimitedWithoutRetryAfter() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"rate_limited"}"#.utf8))
        }
        await #expect(throws: BackendError.rateLimited(retryAfterMs: nil)) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("503 maps to .backendUnavailable")
    func backendUnavailable503() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"backend_unavailable"}"#.utf8))
        }
        await #expect(throws: BackendError.backendUnavailable) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("500 (generic 5xx) maps to .backendUnavailable")
    func generic5xx() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"internal"}"#.utf8))
        }
        await #expect(throws: BackendError.backendUnavailable) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }

    @Test("200 with malformed JSON body maps to .malformedResponse")
    func malformed200() async throws {
        let adapter = makeAdapter { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data("not-json".utf8))
        }
        await #expect(throws: BackendError.self) {
            _ = try await adapter.send(.init(text: "x", clientId: "y"))
        }
    }
}

// MARK: - Test helpers (reuses MockURLProtocol from STTUploaderTests)

private func makeAdapter(
    handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> DispatcherAdapter {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return DispatcherAdapter(
        baseURL: URL(string: "https://test.invalid")!,
        token: "test-token",
        session: session
    )
}
