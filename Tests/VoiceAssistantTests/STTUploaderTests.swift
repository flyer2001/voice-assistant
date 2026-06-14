import Foundation
import Testing
@testable import VoiceAssistant

@Suite("LiveSTTUploader — contract against POST /v1/voice/audio", .serialized)
struct STTUploaderTests {

    @Test("200 OK decodes JSON into STTResponse")
    func happyPath() async throws {
        let json = #"""
        {"text":"привет","lang":"ru","duration_s":1.5,"stt_ms":400,"stt_engine":"whisper-large-v3-turbo","stt_source":"win-home"}
        """#
        let uploader = makeUploader { request in
            #expect(request.url?.path == "/v1/voice/audio")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let result = try await uploader.upload(
            audio: Data("fake-audio-bytes".utf8),
            clientId: "iphone-15",
            ts: Date(timeIntervalSince1970: 1750000000)
        )
        #expect(result == STTResponse(
            text: "привет", lang: "ru", durationS: 1.5,
            sttMs: 400, sttEngine: "whisper-large-v3-turbo", sttSource: "win-home"
        ))
    }

    @Test("Multipart body contains audio, client_id, ts parts")
    func multipartBodyShape() async throws {
        let uploader = makeUploader { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"text":"x","lang":"ru","duration_s":0,"stt_ms":0,"stt_engine":"mock","stt_source":"mock"}"#
            return (response, Data(json.utf8))
        }

        _ = try await uploader.upload(
            audio: Data("abcdef".utf8),
            clientId: "iphone-tester",
            ts: Date(timeIntervalSince1970: 1750000000)
        )

        // Body captured by MockURLProtocol.canInit before URLSession consumes the stream.
        let bodyString = String(data: MockURLProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyString.contains("name=\"audio\""))
        #expect(bodyString.contains("name=\"client_id\""))
        #expect(bodyString.contains("name=\"ts\""))
        #expect(bodyString.contains("iphone-tester"))
        #expect(bodyString.contains("abcdef"))
    }

    @Test("401 maps to .unauthorized")
    func unauthorized() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"unauthorized"}"#.utf8))
        }
        await #expect(throws: STTUploaderError.unauthorized) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("503 maps to .sttUnavailable")
    func sttUnavailable503() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"stt_unavailable"}"#.utf8))
        }
        await #expect(throws: STTUploaderError.sttUnavailable) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("504 maps to .sttTimeout")
    func timeout504() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 504, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"stt_timeout"}"#.utf8))
        }
        await #expect(throws: STTUploaderError.sttTimeout) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("400 unsupported_format maps to .unsupportedFormat")
    func badRequest_unsupportedFormat() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"unsupported_format"}"#.utf8))
        }
        await #expect(throws: STTUploaderError.unsupportedFormat) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("400 audio_too_short maps to .audioTooShort")
    func badRequest_tooShort() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"audio_too_short","min_bytes":1024,"got":42}"#.utf8))
        }
        await #expect(throws: STTUploaderError.audioTooShort) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("400 audio_too_long maps to .audioTooLong")
    func badRequest_tooLong() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"audio_too_long","max_seconds":60,"got":120}"#.utf8))
        }
        await #expect(throws: STTUploaderError.audioTooLong) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }

    @Test("200 with malformed JSON body maps to .malformedResponse")
    func malformed200() async throws {
        let uploader = makeUploader { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data("not-json".utf8))
        }
        await #expect(throws: STTUploaderError.self) {
            _ = try await uploader.upload(audio: Data(), clientId: "x", ts: .init())
        }
    }
}

// MARK: - Test helpers

private func makeUploader(
    handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> LiveSTTUploader {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return LiveSTTUploader(
        baseURL: URL(string: "https://test.invalid")!,
        token: "test-token",
        session: session,
        boundary: "TestBoundary"
    )
}

/// In-process URLProtocol that intercepts every request through its session
/// and answers via the closure stored in `handler`. `lastBody` captures the
/// request body in `canInit` BEFORE URLSession consumes the stream — without
/// this trick `httpBodyStream` is already drained by the time `startLoading`
/// runs. Use through `makeUploader(handler:)`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
