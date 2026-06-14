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

        let body = DispatcherMockURLProtocol.lastBody ?? Data()
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

// MARK: - Test helpers

private func makeAdapter(
    handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> DispatcherAdapter {
    DispatcherMockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DispatcherMockURLProtocol.self]
    let session = URLSession(configuration: config)
    return DispatcherAdapter(
        baseURL: URL(string: "https://test.invalid")!,
        token: "test-token",
        session: session
    )
}

/// Dedicated URLProtocol stub for this suite. STTUploaderTests use a
/// sibling MockURLProtocol with the same static-handler pattern; Swift
/// Testing parallelizes suites, so a shared protocol class would let
/// handler assignments race. Each suite owns its own subclass.
final class DispatcherMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? readStream(request.httpBodyStream)
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func readStream(_ stream: InputStream?) -> Data {
    guard let stream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
