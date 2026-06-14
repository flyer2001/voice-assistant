import Foundation
import Observation

/// FIFO history of conversation Turns. SwiftUI observes `turns` via
/// `@Observable` macro (iOS 17+); the store is otherwise a plain class
/// so tests inspect state directly without subscribing to change
/// publishers.
///
/// `append` grows the buffer up to `maxCount`, then drops the oldest
/// entries on overflow. `updateReply` mutates a single turn in place,
/// which is what the pipeline does after `/v1/voice/intent` resolves.
@Observable
public final class TurnsStore {
    public private(set) var turns: [Turn] = []
    public let maxCount: Int

    public init(maxCount: Int = 10) {
        self.maxCount = maxCount
    }

    public func append(_ turn: Turn) {
        turns.append(turn)
        let overflow = turns.count - maxCount
        if overflow > 0 {
            turns.removeFirst(overflow)
        }
    }

    public func updateReply(id: UUID, to outcome: ReplyOutcome) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].reply = outcome
    }
}
