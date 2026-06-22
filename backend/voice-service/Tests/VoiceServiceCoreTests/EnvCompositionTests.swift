import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("parsePlan(env:) — независимые STT и Happy режимы")
struct EnvCompositionTests {

    // ── STT plan ─────────────────────────────────────────────────────────

    @Test("STT disabled when STT_MODE unset")
    func sttDisabledByDefault() throws {
        let plan = try parsePlan(env: [:])
        #expect(plan.stt == .disabled)
    }

    @Test("STT=mock")
    func sttMock() throws {
        let plan = try parsePlan(env: ["STT_MODE": "mock"])
        #expect(plan.stt == .mock)
    }

    @Test("STT=live uses WHISPER_URL when provided")
    func sttLiveWithCustomURL() throws {
        let plan = try parsePlan(env: [
            "STT_MODE": "live",
            "WHISPER_URL": "http://10.0.0.5:8000",
        ])
        #expect(plan.stt == .live(whisperURL: "http://10.0.0.5:8000"))
    }

    @Test("STT=live falls back to default WHISPER_URL")
    func sttLiveDefaultURL() throws {
        let plan = try parsePlan(env: ["STT_MODE": "live"])
        if case .live(let url) = plan.stt {
            #expect(!url.isEmpty)
            #expect(url.hasPrefix("http"))
        } else {
            Issue.record("expected .live, got \(plan.stt)")
        }
    }

    @Test("STT_MODE=garbage throws unknownSttMode")
    func sttUnknown() {
        #expect(throws: CompositionError.unknownSttMode("hocus-pocus")) {
            _ = try parsePlan(env: ["STT_MODE": "hocus-pocus"])
        }
    }

    // ── Happy plan ───────────────────────────────────────────────────────

    @Test("Happy=echo by default when VOICE_TARGET_CWD unset")
    func happyEchoByDefault() throws {
        let plan = try parsePlan(env: [:])
        #expect(plan.happy == .echo)
    }

    @Test("Happy=live when VOICE_TARGET_CWD set (backwards compat)")
    func happyLiveWhenCwdSet() throws {
        let plan = try parsePlan(env: ["VOICE_TARGET_CWD": "/root/projects/cashflow"])
        #expect(plan.happy == .live(targetCwd: "/root/projects/cashflow"))
    }

    @Test("HAPPY_MODE=echo overrides VOICE_TARGET_CWD")
    func happyEchoExplicitOverride() throws {
        let plan = try parsePlan(env: [
            "HAPPY_MODE": "echo",
            "VOICE_TARGET_CWD": "/x",
        ])
        #expect(plan.happy == .echo)
    }

    @Test("HAPPY_MODE=live requires VOICE_TARGET_CWD")
    func happyLiveRequiresCwd() {
        #expect(throws: CompositionError.missingTargetCwd) {
            _ = try parsePlan(env: ["HAPPY_MODE": "live"])
        }
    }

    @Test("HAPPY_MODE=garbage throws unknownHappyMode")
    func happyUnknown() {
        #expect(throws: CompositionError.unknownHappyMode("toaster")) {
            _ = try parsePlan(env: ["HAPPY_MODE": "toaster"])
        }
    }

    // ── Critical acceptance: STT и Happy одновременно live ──────────────

    @Test("STT=live + HAPPY=live одновременно (S2 → real assistant)")
    func sttAndHappyLiveSimultaneous() throws {
        let plan = try parsePlan(env: [
            "STT_MODE": "live",
            "WHISPER_URL": "http://192.168.88.13:8000",
            "HAPPY_MODE": "live",
            "VOICE_TARGET_CWD": "/root/projects/cashflow",
        ])
        #expect(plan.stt == .live(whisperURL: "http://192.168.88.13:8000"))
        #expect(plan.happy == .live(targetCwd: "/root/projects/cashflow"))
    }

    // ── Log path ─────────────────────────────────────────────────────────

    @Test("VOICE_LOG_PATH falls through to default")
    func logDefault() throws {
        let plan = try parsePlan(env: [:])
        #expect(plan.logPath == "/var/log/voice.jsonl")
    }

    @Test("VOICE_LOG_PATH override")
    func logOverride() throws {
        let plan = try parsePlan(env: ["VOICE_LOG_PATH": "/tmp/v.jsonl"])
        #expect(plan.logPath == "/tmp/v.jsonl")
    }
}

@Suite("buildConfiguration(token:plan:) — wires замыкания")
struct BuildConfigurationTests {

    @Test("echo replyProvider returns '[echo reply] <text>'")
    func echoReply() async throws {
        let plan = CompositionPlan(stt: .disabled, happy: .echo, logPath: nil)
        let config = buildConfiguration(token: "T", plan: plan)

        let reply = try await config.replyProvider(
            IntentRequest(text: "hello", client_id: "c", ts: "t")
        )
        #expect(reply == "[echo reply] hello")
        #expect(config.sttProvider == nil)
        #expect(config.requestLogger == nil)
    }

    @Test("mock sttProvider returns echo bytes-count")
    func mockSTT() async throws {
        let plan = CompositionPlan(stt: .mock, happy: .echo, logPath: nil)
        let config = buildConfiguration(token: "T", plan: plan)

        guard let stt = config.sttProvider else {
            Issue.record("expected non-nil sttProvider")
            return
        }
        let result = try await stt(Data("12345".utf8), "alice")
        #expect(result.text.contains("5 bytes"))
        #expect(result.text.contains("alice"))
        #expect(result.sttEngine == "mock")
    }

    @Test("live happy wires LiveHappyInjectMessenger (smoke — no real send)")
    func liveHappyWired() async throws {
        let plan = CompositionPlan(
            stt: .disabled,
            happy: .live(targetCwd: "/nonexistent/cwd"),
            logPath: nil
        )
        let config = buildConfiguration(token: "T", plan: plan)

        // Real messenger хочет ~/.happy/access.key — на CI / в тесте файлов нет,
        // должен бросить .state(accessKeyMissing). Достаточно убедиться что
        // closure не stub-echo (т.е. RealHappy завёрнут).
        await #expect(throws: (any Error).self) {
            _ = try await config.replyProvider(
                IntentRequest(text: "x", client_id: "c", ts: "t")
            )
        }
    }
}
