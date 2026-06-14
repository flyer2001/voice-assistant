import Foundation

/// One conversation pair: the user's transcript (`query`) plus the
/// backend's `reply` (or its pending/failure state). Stored in
/// `TurnsStore` (E2.2) and rendered by `TurnView` (E2.1 UI side).
///
/// Mutated in-place by the pipeline: a turn is born pending when the
/// transcript lands, then transitions to `.success(Reply)` or
/// `.failure(message)` after `/v1/voice/intent` returns or fails.
public struct Turn: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let query: String
    public var reply: ReplyOutcome
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        query: String,
        reply: ReplyOutcome = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.reply = reply
        self.createdAt = createdAt
    }
}

public enum ReplyOutcome: Equatable, Sendable {
    case pending
    case success(Reply)
    case failure(String)
}
