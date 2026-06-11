import Foundation
import HummingbirdTesting
import Hummingbird
import Testing
@testable import VoiceServiceCore

@Suite("POST /v1/voice/intent — contract")
struct IntentEndpointTests {

    // Triangulation step 1 (Empty/Single): happy path with hardcoded reply.
    @Test("200 OK with reply + latency_ms on valid request")
    func happyPath() async throws {
        let app = VoiceServiceApp.make(
            config: .init(token: "test-token-1", replyProvider: { req in
                "echo: \(req.text)"
            })
        )

        try await app.test(.router) { client in
            let body = #"{"text":"что у меня по cashflow","client_id":"iphone-15","ts":"2026-06-11T10:00:00.000Z"}"#
            try await client.execute(
                uri: "/v1/voice/intent",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token-1",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: body)
            ) { response in
                #expect(response.status == .ok)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["reply"] as? String == "echo: что у меня по cashflow")
                #expect(json?["latency_ms"] is Int)
            }
        }
    }

    @Test("401 unauthorized when Authorization header missing")
    func missingAuth() async throws {
        let app = VoiceServiceApp.make(
            config: .init(token: "test-token-1", replyProvider: { _ in "ok" })
        )

        try await app.test(.router) { client in
            let body = #"{"text":"x","client_id":"c","ts":"2026-06-11T10:00:00.000Z"}"#
            try await client.execute(
                uri: "/v1/voice/intent",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: body)
            ) { response in
                #expect(response.status == .unauthorized)
                let json = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                #expect(json?["error"] as? String == "unauthorized")
            }
        }
    }

    @Test("401 unauthorized on wrong Bearer token")
    func wrongToken() async throws {
        let app = VoiceServiceApp.make(
            config: .init(token: "expected", replyProvider: { _ in "ok" })
        )

        try await app.test(.router) { client in
            let body = #"{"text":"x","client_id":"c","ts":"2026-06-11T10:00:00.000Z"}"#
            try await client.execute(
                uri: "/v1/voice/intent",
                method: .post,
                headers: [
                    .authorization: "Bearer wrong",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: body)
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }
}
