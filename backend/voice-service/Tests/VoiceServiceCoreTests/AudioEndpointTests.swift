import Foundation
import HummingbirdTesting
import Hummingbird
import Testing
@testable import VoiceServiceCore

@Suite("POST /v1/voice/audio — contract")
struct AudioEndpointTests {

    @Test("200 OK with mock STT result on multipart POST")
    func multipartHappyPath() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" },
                sttProvider: { bytes, clientId in
                    STTResult(
                        text: "[mock] \(bytes.count) bytes from \(clientId)",
                        sttEngine: "mock",
                        sttSource: "mock"
                    )
                }
            )
        )

        let body = makeMultipart(
            audioBytes: Data("fake-audio-bytes".utf8),   // 16 bytes
            clientId: "iphone-test",
            ts: "2026-06-14T16:34:00Z"
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token",
                    .contentType: "multipart/form-data; boundary=\(boundary)",
                ],
                body: ByteBuffer(data: body)
            ) { response in
                #expect(response.status == .ok)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["text"] as? String == "[mock] 16 bytes from iphone-test")
                #expect(json?["stt_engine"] as? String == "mock")
                #expect(json?["stt_source"] as? String == "mock")
                #expect(json?["lang"] as? String == "ru")
            }
        }
    }

    @Test("401 unauthorized when Authorization header missing")
    func missingAuth() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" },
                sttProvider: { _, _ in STTResult(text: "x", sttEngine: "mock", sttSource: "mock") }
            )
        )

        let body = makeMultipart(audioBytes: Data("x".utf8), clientId: "c", ts: "2026-06-14T00:00:00Z")

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [.contentType: "multipart/form-data; boundary=\(boundary)"],
                body: ByteBuffer(data: body)
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("503 stt_unavailable when sttProvider not configured")
    func sttProviderMissing() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" }
            )
        )

        let body = makeMultipart(audioBytes: Data("x".utf8), clientId: "c", ts: "2026-06-14T00:00:00Z")

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token",
                    .contentType: "multipart/form-data; boundary=\(boundary)",
                ],
                body: ByteBuffer(data: body)
            ) { response in
                #expect(response.status == .serviceUnavailable)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["error"] as? String == "stt_unavailable")
            }
        }
    }

    @Test("400 unsupported_format when content-type is not multipart")
    func nonMultipartRejected() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" },
                sttProvider: { _, _ in STTResult(text: "x", sttEngine: "mock", sttSource: "mock") }
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token",
                    .contentType: "application/octet-stream",
                ],
                body: ByteBuffer(string: "raw-bytes")
            ) { response in
                #expect(response.status == .badRequest)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["error"] as? String == "unsupported_format")
            }
        }
    }

    @Test("400 missing_field when multipart lacks audio part")
    func missingAudioField() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" },
                sttProvider: { _, _ in STTResult(text: "x", sttEngine: "mock", sttSource: "mock") }
            )
        )

        var body = ""
        body += "--\(boundary)\r\n"
        body += "Content-Disposition: form-data; name=\"client_id\"\r\n\r\n"
        body += "iphone-test\r\n"
        body += "--\(boundary)\r\n"
        body += "Content-Disposition: form-data; name=\"ts\"\r\n\r\n"
        body += "2026-06-14T00:00:00Z\r\n"
        body += "--\(boundary)--\r\n"

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token",
                    .contentType: "multipart/form-data; boundary=\(boundary)",
                ],
                body: ByteBuffer(string: body)
            ) { response in
                #expect(response.status == .badRequest)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["error"] as? String == "missing_field")
            }
        }
    }
}

// MARK: - Test helpers

private let boundary = "TestBoundaryABC123"

private func makeMultipart(audioBytes: Data, clientId: String, ts: String) -> Data {
    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"audio\"; filename=\"rec.caf\"\r\n")
    append("Content-Type: application/octet-stream\r\n\r\n")
    body.append(audioBytes)
    append("\r\n")

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"client_id\"\r\n\r\n")
    append("\(clientId)\r\n")

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"ts\"\r\n\r\n")
    append("\(ts)\r\n")

    append("--\(boundary)--\r\n")
    return body
}
