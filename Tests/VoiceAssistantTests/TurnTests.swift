import Testing
import Foundation
@testable import VoiceAssistant

@Suite("Turn — conversation pair model")
struct TurnTests {

    @Test("New turn from query starts in .pending reply state")
    func newTurnIsPending() {
        let turn = Turn(query: "status cashflow")

        #expect(turn.query == "status cashflow")
        #expect(turn.reply == .pending)
    }

    @Test("Completing a pending turn with Reply moves it to .success")
    func completeWithReplySucceeds() {
        var turn = Turn(query: "status cashflow")
        let reply = Reply(text: "3 open issues", latencyMs: 412)

        turn.reply = .success(reply)

        #expect(turn.reply == .success(reply))
    }

    @Test("Failing a pending turn carries the error message")
    func failingTurnCarriesMessage() {
        var turn = Turn(query: "status cashflow")

        turn.reply = .failure("503 backend_unavailable")

        #expect(turn.reply == .failure("503 backend_unavailable"))
    }

    @Test("Two turns created from the same query have different ids")
    func turnsHaveUniqueIdentity() {
        let a = Turn(query: "ping")
        let b = Turn(query: "ping")

        #expect(a.id != b.id)
    }

    @Test("createdAt is captured at init time")
    func capturesCreatedAt() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let turn = Turn(query: "hi", createdAt: fixed)

        #expect(turn.createdAt == fixed)
    }
}
