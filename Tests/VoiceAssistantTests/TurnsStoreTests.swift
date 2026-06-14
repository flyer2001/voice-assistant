import Testing
import Foundation
@testable import VoiceAssistant

@Suite("TurnsStore — FIFO conversation history")
struct TurnsStoreTests {

    @Test("New store is empty")
    func emptyOnInit() {
        let store = TurnsStore()
        #expect(store.turns.isEmpty)
    }

    @Test("Single append lands in turns")
    func singleAppend() {
        let store = TurnsStore()
        let turn = Turn(query: "status cashflow")

        store.append(turn)

        #expect(store.turns.count == 1)
        #expect(store.turns[0].id == turn.id)
    }

    @Test("Eleventh append drops the oldest (FIFO at default cap 10)")
    func fifoAtCapTen() {
        let store = TurnsStore()
        let turns = (1...11).map { Turn(query: "q\($0)") }

        for t in turns { store.append(t) }

        #expect(store.turns.count == 10)
        #expect(store.turns.first?.id == turns[1].id)
        #expect(store.turns.last?.id == turns[10].id)
    }

    @Test("updateReply mutates the matching turn")
    func updateReplyByID() {
        let store = TurnsStore()
        let turn = Turn(query: "status cashflow")
        store.append(turn)

        store.updateReply(id: turn.id, to: .success(Reply(text: "ok", latencyMs: 42)))

        #expect(store.turns[0].reply == .success(Reply(text: "ok", latencyMs: 42)))
    }

    @Test("updateReply with unknown id is a no-op")
    func updateReplyMissingID() {
        let store = TurnsStore()
        store.append(Turn(query: "kept"))
        let originalReply = store.turns[0].reply

        store.updateReply(id: UUID(), to: .failure("nope"))

        #expect(store.turns.count == 1)
        #expect(store.turns[0].reply == originalReply)
    }

    @Test("Custom maxCount caps history independently of default")
    func customMaxCount() {
        let store = TurnsStore(maxCount: 3)
        for i in 1...5 { store.append(Turn(query: "q\(i)")) }

        #expect(store.turns.count == 3)
        #expect(store.turns.first?.query == "q3")
        #expect(store.turns.last?.query == "q5")
    }
}
