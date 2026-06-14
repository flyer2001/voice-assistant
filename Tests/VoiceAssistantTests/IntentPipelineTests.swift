import Foundation
import Testing
@testable import VoiceAssistant

@Suite("IntentPipeline — transcript to TurnsStore via BackendAdapter")
struct IntentPipelineTests {

    @Test("Success → store gains a turn whose reply is .success(Reply)")
    func happyPath() async {
        let store = TurnsStore()
        let fake = FakeBackendAdapter { _ in
            Reply(text: "3 open issues", latencyMs: 412)
        }
        let pipeline = IntentPipeline(dispatcher: fake, store: store)

        await pipeline.handle(transcript: "status cashflow", clientId: "iphone-15")

        #expect(store.turns.count == 1)
        #expect(store.turns[0].query == "status cashflow")
        #expect(store.turns[0].reply == .success(Reply(text: "3 open issues", latencyMs: 412)))
    }

    @Test("Pipeline forwards transcript + clientId into the BackendAdapter")
    func passesClientId() async {
        let store = TurnsStore()
        actor Box { var captured: TranscribedRequest?; func set(_ r: TranscribedRequest) { captured = r } }
        let box = Box()
        let fake = FakeBackendAdapter { req in
            await box.set(req)
            return Reply(text: "ok", latencyMs: 1)
        }
        let pipeline = IntentPipeline(dispatcher: fake, store: store)

        await pipeline.handle(transcript: "привет", clientId: "iphone-tester")

        let captured = await box.captured
        #expect(captured?.text == "привет")
        #expect(captured?.clientId == "iphone-tester")
    }

    @Test("BackendError.unauthorized → turn.reply == .failure(\"401 unauthorized\")")
    func unauthorizedLabeled() async {
        let store = TurnsStore()
        let fake = FakeBackendAdapter { _ in throw BackendError.unauthorized }
        let pipeline = IntentPipeline(dispatcher: fake, store: store)

        await pipeline.handle(transcript: "x", clientId: "y")

        #expect(store.turns[0].reply == .failure("401 unauthorized"))
    }

    @Test("BackendError.rateLimited(5000) → labeled with retry ms")
    func rateLimitedLabeled() async {
        let store = TurnsStore()
        let fake = FakeBackendAdapter { _ in throw BackendError.rateLimited(retryAfterMs: 5000) }
        let pipeline = IntentPipeline(dispatcher: fake, store: store)

        await pipeline.handle(transcript: "x", clientId: "y")

        #expect(store.turns[0].reply == .failure("429 rate_limited (retry 5000 ms)"))
    }

    @Test("BackendError.backendUnavailable → labeled 503")
    func backendUnavailableLabeled() async {
        let store = TurnsStore()
        let fake = FakeBackendAdapter { _ in throw BackendError.backendUnavailable }
        let pipeline = IntentPipeline(dispatcher: fake, store: store)

        await pipeline.handle(transcript: "x", clientId: "y")

        #expect(store.turns[0].reply == .failure("503 backend_unavailable"))
    }
}

// MARK: - Test fixture

struct FakeBackendAdapter: BackendAdapter, @unchecked Sendable {
    let onSend: @Sendable (TranscribedRequest) async throws -> Reply

    func send(_ request: TranscribedRequest) async throws -> Reply {
        try await onSend(request)
    }
}
