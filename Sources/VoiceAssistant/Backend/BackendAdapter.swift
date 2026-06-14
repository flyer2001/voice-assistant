import Foundation

/// What the client sends to a backend after on-device STT.
public struct TranscribedRequest: Sendable, Equatable {
    public let text: String
    public let clientId: String
    public let timestamp: Date

    public init(text: String, clientId: String, timestamp: Date = Date()) {
        self.text = text
        self.clientId = clientId
        self.timestamp = timestamp
    }
}

/// What the client expects back from any backend.
public struct Reply: Sendable, Equatable {
    public let text: String
    public let latencyMs: Int

    public init(text: String, latencyMs: Int) {
        self.text = text
        self.latencyMs = latencyMs
    }
}

/// Errors any BackendAdapter can surface to the UI layer.
/// Adapter-specific failures must map into these cases.
public enum BackendError: Error, Sendable, Equatable {
    case network(underlying: String)
    case unauthorized
    case forbidden
    case rateLimited(retryAfterMs: Int?)
    case backendUnavailable
    case malformedResponse(String)
    case timeout
}

/// Contract every backend implementation honors. The client never knows
/// which concrete adapter is wired up — only the protocol.
///
/// See specs/backend-protocol.md for the wire-format contract that
/// DispatcherAdapter and any future HTTP-based adapter must follow.
public protocol BackendAdapter: Sendable {
    func send(_ request: TranscribedRequest) async throws -> Reply
}
