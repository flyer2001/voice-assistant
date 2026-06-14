import Foundation
import HummingbirdTesting
import Hummingbird
import Testing
@testable import VoiceServiceCore

@Suite("POST /v1/voice/audio — contract")
struct AudioEndpointTests {

    // Triangulation step 1 (Empty/Single): happy path with mock STT.
    // Slice 1 — body is treated as raw audio bytes. Multipart parsing
    // comes in a later slice once this contract is green.
    @Test("200 OK with mock STT result on valid POST")
    func mockHappyPath() async throws {
        let app = VoiceServiceApp.make(
            config: .init(
                token: "test-token",
                replyProvider: { _ in "" },
                sttProvider: { bytes, _ in
                    STTResult(
                        text: "[mock] \(bytes.count) bytes received",
                        sttEngine: "mock",
                        sttSource: "mock"
                    )
                }
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
                body: ByteBuffer(string: "fake-audio-bytes")
            ) { response in
                #expect(response.status == .ok)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["text"] as? String == "[mock] 16 bytes received")
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

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/audio",
                method: .post,
                headers: [.contentType: "application/octet-stream"],
                body: ByteBuffer(string: "fake")
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
                // sttProvider intentionally omitted
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
                body: ByteBuffer(string: "fake")
            ) { response in
                #expect(response.status == .serviceUnavailable)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["error"] as? String == "stt_unavailable")
            }
        }
    }
}
