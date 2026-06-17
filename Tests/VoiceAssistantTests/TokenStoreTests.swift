import Foundation
import Testing
@testable import VoiceAssistant

@Suite("InMemoryTokenStore — contract every TokenStore impl honors")
struct InMemoryTokenStoreTests {

    @Test("Fresh store reads nil")
    func emptyReadsNil() throws {
        let store = InMemoryTokenStore()
        #expect(try store.read() == nil)
    }

    @Test("write then read → roundtrip")
    func writeReadRoundtrip() throws {
        let store = InMemoryTokenStore()
        try store.write("dev-token")
        #expect(try store.read() == "dev-token")
    }

    @Test("write twice → second value wins")
    func writeOverwrites() throws {
        let store = InMemoryTokenStore()
        try store.write("old")
        try store.write("new")
        #expect(try store.read() == "new")
    }

    @Test("clear after write → read returns nil")
    func clearAfterWrite() throws {
        let store = InMemoryTokenStore()
        try store.write("temp")
        try store.clear()
        #expect(try store.read() == nil)
    }

    @Test("Store seeded with initial value reads it on first read")
    func seededInitial() throws {
        let store = InMemoryTokenStore(initial: "seeded")
        #expect(try store.read() == "seeded")
    }
}
