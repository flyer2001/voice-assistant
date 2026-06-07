import Testing
@testable import VoiceAssistant

@Suite("Package sanity")
struct PackageSanityTests {

    @Test("BackendAdapter protocol is reachable from tests")
    func protocolReachable() {
        let _: any BackendAdapter.Type = DispatcherAdapter.self
    }

    @Test("Reply equality")
    func replyEquality() {
        let a = Reply(text: "ok", latencyMs: 100)
        let b = Reply(text: "ok", latencyMs: 100)
        #expect(a == b)
    }
}
