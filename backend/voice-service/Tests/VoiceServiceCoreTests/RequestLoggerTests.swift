import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("RequestLogger — JSONL append-only contract")
struct RequestLoggerTests {

    func tempLogPath() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voice-log-\(UUID().uuidString).jsonl")
    }

    @Test("logSuccess writes JSON line with required fields")
    func successShape() throws {
        let path = tempLogPath()
        let logger = RequestLogger(path: path)
        logger.logSuccess(clientId: "iphone-1", text: "hello", reply: "world", latencyMs: 1234)

        let data = try Data(contentsOf: path)
        let line = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        let obj = try JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as! [String: Any]
        #expect(obj["client_id"] as? String == "iphone-1")
        #expect(obj["text"] as? String == "hello")
        #expect(obj["reply"] as? String == "world")
        #expect(obj["latency_ms"] as? Int == 1234)
        #expect(obj["error"] == nil, "no error field on success path")
        #expect(obj["ts"] is String)
    }

    @Test("logError writes error field instead of reply")
    func errorShape() throws {
        let path = tempLogPath()
        let logger = RequestLogger(path: path)
        logger.logError(clientId: "iphone-1", text: "bad", error: "backend_unavailable", latencyMs: 1500)

        let data = try Data(contentsOf: path)
        let line = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        let obj = try JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as! [String: Any]
        #expect(obj["error"] as? String == "backend_unavailable")
        #expect(obj["reply"] == nil, "no reply field on error path")
    }

    @Test("multiple writes produce multiple newline-separated lines")
    func appendOnly() throws {
        let path = tempLogPath()
        let logger = RequestLogger(path: path)
        logger.logSuccess(clientId: "c", text: "a", reply: "A", latencyMs: 100)
        logger.logSuccess(clientId: "c", text: "b", reply: "B", latencyMs: 200)
        let data = try Data(contentsOf: path)
        let s = String(data: data, encoding: .utf8)!
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        for line in lines {
            _ = try JSONSerialization.jsonObject(with: line.data(using: .utf8)!)
        }
    }
}
