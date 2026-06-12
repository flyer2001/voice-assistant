import XCTest
@testable import VKAdapter

final class VKLongPollClientTests: XCTestCase {
    private let initialServer = VKLongPollServer(
        server: "https://lp.vk.com/wh111",
        key: "key-initial",
        ts: "100"
    )

    func testNextBatch_success_returnsUpdatesAndAdvancesTs() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: """
        {"ts":"101","updates":[{"type":"message_new","group_id":111,"object":{"message":{"id":1,"date":1,"peer_id":42,"from_id":42,"text":"hi"}}}]}
        """)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)

        let outcome = try await client.nextBatch()

        guard case .updates(let updates) = outcome else {
            return XCTFail("expected .updates, got \(outcome)")
        }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.type, "message_new")

        let call = try XCTUnwrap(mock.calls.first)
        XCTAssertEqual(call.method, "GET")
        XCTAssertTrue(call.url.hasPrefix("https://lp.vk.com/wh111?"), "got \(call.url)")
        XCTAssertTrue(call.url.contains("act=a_check"))
        XCTAssertTrue(call.url.contains("key=key-initial"))
        XCTAssertTrue(call.url.contains("ts=100"))
        XCTAssertTrue(call.url.contains("wait=25"))

        // Second poll picks up advanced ts
        mock.queueResponse(json: #"{"ts":"102","updates":[]}"#)
        _ = try await client.nextBatch()
        XCTAssertTrue(mock.calls[1].url.contains("ts=101"))
    }

    func testNextBatch_failed1_advancesTsAndReturnsEmptyUpdates() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"failed":1,"ts":"500"}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)

        let outcome = try await client.nextBatch()

        guard case .updates(let updates) = outcome else {
            return XCTFail("expected .updates(empty), got \(outcome)")
        }
        XCTAssertTrue(updates.isEmpty)

        mock.queueResponse(json: #"{"ts":"501","updates":[]}"#)
        _ = try await client.nextBatch()
        XCTAssertTrue(mock.calls[1].url.contains("ts=500"), "expected ts to advance to 500, url: \(mock.calls[1].url)")
    }

    func testNextBatch_failed2_signalsServerRefetch() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"failed":2}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)

        let outcome = try await client.nextBatch()

        XCTAssertEqual(outcome, .needsServerRefetch)
    }

    func testNextBatch_failed3_signalsServerRefetch() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"failed":3}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)

        let outcome = try await client.nextBatch()

        XCTAssertEqual(outcome, .needsServerRefetch)
    }

    func testNextBatch_failed4_throwsFatal() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"failed":4}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)

        do {
            _ = try await client.nextBatch()
            XCTFail("expected throw")
        } catch let error as VKLongPollError {
            XCTAssertEqual(error, .invalidVersion)
        }
    }

    func testReplaceServer_resetsTsAndKeyForSubsequentPolls() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"ts":"101","updates":[]}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 25)
        _ = try await client.nextBatch()

        let newServer = VKLongPollServer(server: "https://lp.vk.com/wh222", key: "key-fresh", ts: "9000")
        await client.replaceServer(newServer)

        mock.queueResponse(json: #"{"ts":"9001","updates":[]}"#)
        _ = try await client.nextBatch()

        let secondCall = mock.calls[1]
        XCTAssertTrue(secondCall.url.hasPrefix("https://lp.vk.com/wh222?"))
        XCTAssertTrue(secondCall.url.contains("key=key-fresh"))
        XCTAssertTrue(secondCall.url.contains("ts=9000"))
    }

    func testNextBatch_waitParameterRespectsConfiguredSeconds() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"ts":"101","updates":[]}"#)
        let client = VKLongPollClient(server: initialServer, httpClient: mock, waitSeconds: 10)

        _ = try await client.nextBatch()

        XCTAssertTrue(mock.calls[0].url.contains("wait=10"))
    }
}
