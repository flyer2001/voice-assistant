import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("HappyCrypto — AES-256-GCM bundle")
struct HappyCryptoTests {

    struct Envelope: Codable, Equatable {
        let role: String
        let text: String
    }

    @Test("encrypt → decrypt roundtrip preserves payload")
    func roundtrip() throws {
        // 32-byte zero key (just for test determinism)
        let key = Data(repeating: 0xAA, count: 32).base64EncodedString()
        let envelope = Envelope(role: "user", text: "что у меня по cashflow")
        let bundle = try HappyCrypto.encryptDataKey(envelope, keyBase64: key)
        // Bundle is base64, decode for shape check
        let raw = Data(base64Encoded: bundle)!
        #expect(raw[0] == 0, "version byte must be 0")
        #expect(raw.count >= 1 + 12 + 16, "minimum bundle = version + nonce + tag")

        let decoded: Envelope = try HappyCrypto.decryptDataKey(bundle, keyBase64: key, as: Envelope.self)
        #expect(decoded == envelope)
    }

    @Test("encryption is non-deterministic — nonce varies")
    func nonceVariation() throws {
        let key = Data(repeating: 0xBB, count: 32).base64EncodedString()
        let env = Envelope(role: "user", text: "test")
        let a = try HappyCrypto.encryptDataKey(env, keyBase64: key)
        let b = try HappyCrypto.encryptDataKey(env, keyBase64: key)
        #expect(a != b, "two encryptions of same payload should differ (random nonce)")
    }

    @Test("invalid key length throws")
    func invalidKey() {
        let shortKey = Data(repeating: 0xCC, count: 16).base64EncodedString()
        #expect(throws: HappyCrypto.Error.self) {
            try HappyCrypto.encryptDataKey(Envelope(role: "u", text: "x"), keyBase64: shortKey)
        }
    }
}
