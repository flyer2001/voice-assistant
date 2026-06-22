import XCTest
@testable import VKAdapter

final class AudioStorageTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audiostorage-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    func test_saveAudio_writesBytesUnderRawDir() throws {
        let storage = AudioStorage(
            rawDir: tmp.appendingPathComponent("raw"),
            auditPath: tmp.appendingPathComponent("audit.jsonl")
        )
        let bytes = Data([0x4F, 0x67, 0x67, 0x53])     // "OggS"

        let url = try storage.saveAudio(bytes, msgId: 42, ts: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(url.lastPathComponent.contains("msg42"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".ogg"))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func test_appendAudit_isAppendOnlyJSONL() throws {
        let storage = AudioStorage(
            rawDir: tmp.appendingPathComponent("raw"),
            auditPath: tmp.appendingPathComponent("audit.jsonl")
        )
        let e1 = AuditEntry(ts: "t1", msgId: 1, peerId: 100, decision: "used_vk", totalMs: 10, outcome: "success")
        let e2 = AuditEntry(ts: "t2", msgId: 2, peerId: 100, decision: "used_whisper", totalMs: 20, outcome: "success")

        try storage.appendAudit(e1)
        try storage.appendAudit(e2)

        let content = try String(contentsOf: storage.auditPath, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\"msg_id\":1"))
        XCTAssertTrue(lines[0].contains("\"decision\":\"used_vk\""))
        XCTAssertTrue(lines[1].contains("\"msg_id\":2"))
        XCTAssertTrue(lines[1].contains("\"decision\":\"used_whisper\""))
    }

    func test_compactStamp_isFilenameSafe() {
        let s = AudioStorage.compactStamp(from: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(s.contains(":"))
        XCTAssertTrue(s.contains("T"))
    }
}
