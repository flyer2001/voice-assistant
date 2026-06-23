import Foundation

/// Orchestrates: read Happy state → encrypt → POST → wait for assistant reply
/// in target JSONL. Returns the reply text.
///
/// Use `make(targetCwd:timeout:)` to build a closure suitable for
/// `Configuration.replyProvider`.
public struct LiveHappyInjectMessenger: Sendable {

    public enum Error: Swift.Error {
        case state(HappyStateError)
        case crypto(HappyCrypto.Error)
        case http(HappyAPI.Error)
        case waitTimeout
        case unsupportedEncryptionVariant(String)
    }

    /// Envelope shape posted into the Happy session JSONL. Mirrors
    /// inject.mjs `buildEnvelope`.
    public struct UserEnvelope: Codable, Sendable {
        public let role: String
        public let content: Content
        public let meta: Meta

        public struct Content: Codable, Sendable {
            public let type: String
            public let text: String
        }
        public struct Meta: Codable, Sendable {
            public let sentFrom: String
        }
    }

    public let state: HappyState
    public let api: HappyAPI
    public let watcher: JsonlWatcher

    public init(
        state: HappyState = HappyState(happyHome: HappyState.defaultHome),
        api: HappyAPI = HappyAPI(),
        watcher: JsonlWatcher = JsonlWatcher()
    ) {
        self.state = state
        self.api = api
        self.watcher = watcher
    }

    /// Builds a closure for Configuration.replyProvider. `targetCwd` is the
    /// project folder to inject into (e.g. "/root/projects/cashflow").
    public func makeReplyProvider(targetCwd: String, timeout: Duration = .seconds(15)) -> @Sendable (IntentRequest) async throws -> String {
        let captured = self
        return { intent in
            try await captured.send(text: intent.text, targetCwd: targetCwd, timeout: timeout)
        }
    }

    /// Fire-and-forget inject: encrypt + POST, no JSONL wait. Returns when the
    /// Happy server has accepted the encrypted envelope. The dispatcher session
    /// is expected to reply asynchronously via a separate channel (e.g. POST
    /// /v1/vk/send for the VK bot path).
    public func injectNoWait(text: String, targetCwd: String) async throws {
        let token: String
        let sessions: [String: HappySessionRecord]
        do {
            token = try state.readToken()
            sessions = try state.readSessions()
        } catch let err as HappyStateError {
            throw Error.state(err)
        }

        let pick: (sid: String, record: HappySessionRecord)
        do {
            pick = try state.pickRunningSession(byCwd: targetCwd, sessions: sessions)
        } catch let err as HappyStateError {
            throw Error.state(err)
        }
        guard pick.record.encryptionVariant == "dataKey",
              let keyBase64 = pick.record.encryptionKey
        else {
            throw Error.unsupportedEncryptionVariant(pick.record.encryptionVariant ?? "nil")
        }

        let envelope = UserEnvelope(
            role: "user",
            content: .init(type: "text", text: text),
            meta: .init(sentFrom: "voice-service-swift")
        )
        let encrypted: String
        do {
            encrypted = try HappyCrypto.encryptDataKey(envelope, keyBase64: keyBase64)
        } catch let err as HappyCrypto.Error {
            throw Error.crypto(err)
        }

        do {
            try await api.postMessage(sid: pick.sid, token: token, encryptedB64: encrypted)
        } catch let err as HappyAPI.Error {
            throw Error.http(err)
        }
    }

    public func send(text: String, targetCwd: String, timeout: Duration) async throws -> String {
        let token: String
        let sessions: [String: HappySessionRecord]
        do {
            token = try state.readToken()
            sessions = try state.readSessions()
        } catch let err as HappyStateError {
            throw Error.state(err)
        }

        let pick: (sid: String, record: HappySessionRecord)
        do {
            pick = try state.pickRunningSession(byCwd: targetCwd, sessions: sessions)
        } catch let err as HappyStateError {
            throw Error.state(err)
        }
        guard pick.record.encryptionVariant == "dataKey",
              let keyBase64 = pick.record.encryptionKey
        else {
            throw Error.unsupportedEncryptionVariant(pick.record.encryptionVariant ?? "nil")
        }

        let envelope = UserEnvelope(
            role: "user",
            content: .init(type: "text", text: text),
            meta: .init(sentFrom: "voice-service-swift")
        )
        let encrypted: String
        do {
            encrypted = try HappyCrypto.encryptDataKey(envelope, keyBase64: keyBase64)
        } catch let err as HappyCrypto.Error {
            throw Error.crypto(err)
        }

        // Baseline JSONL before POSTing.
        let initialJsonl = watcher.findLatestJsonl(forCwd: targetCwd)
        let baseline = initialJsonl.map { watcher.fileSize($0) } ?? 0

        do {
            try await api.postMessage(sid: pick.sid, token: token, encryptedB64: encrypted)
        } catch let err as HappyAPI.Error {
            throw Error.http(err)
        }

        let reply = await watcher.waitForAssistantReply(
            targetCwd: targetCwd,
            initialJsonl: initialJsonl,
            baselineSize: baseline,
            timeout: timeout
        )
        switch reply {
        case .message(let text, _):
            return text
        case .timeout:
            throw Error.waitTimeout
        }
    }
}
