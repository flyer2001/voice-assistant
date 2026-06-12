import XCTest
import Logging
@testable import VKAdapter

final class VKAPIClientTests: XCTestCase {
    func testGetLongPollServer_decodesSuccessResponse() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: """
        {"response":{"server":"https://lp.vk.com/x","key":"k1","ts":"100"}}
        """)
        let client = makeClient(http: mock)

        let server = try await client.getLongPollServer(groupId: 111)

        XCTAssertEqual(server, VKLongPollServer(server: "https://lp.vk.com/x", key: "k1", ts: "100"))
        let call = try XCTUnwrap(mock.calls.first)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url, "https://api.vk.com/method/groups.getLongPollServer")
        XCTAssertEqual(call.headers["Content-Type"], "application/x-www-form-urlencoded")
        let bodyString = String(data: call.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("access_token=t-secret"))
        XCTAssertTrue(bodyString.contains("v=5.199"))
        XCTAssertTrue(bodyString.contains("group_id=111"))
    }

    func testGetLongPollServer_propagatesAPIError() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: """
        {"error":{"error_code":100,"error_msg":"longpoll for this group is not enabled."}}
        """)
        let client = makeClient(http: mock)

        do {
            _ = try await client.getLongPollServer(groupId: 111)
            XCTFail("expected throw")
        } catch let error as VKAPIError {
            XCTAssertEqual(error.errorCode, 100)
            XCTAssertEqual(error.errorMsg, "longpoll for this group is not enabled.")
        }
    }

    func testSendMessage_returnsMessageIdAndPostsRequiredFields() async throws {
        let mock = MockVKHTTPClient()
        mock.queueResponse(json: #"{"response":12345}"#)
        let client = makeClient(http: mock)

        let messageId = try await client.sendMessage(peerId: 42, text: "привет")

        XCTAssertEqual(messageId, 12345)
        let call = try XCTUnwrap(mock.calls.first)
        XCTAssertEqual(call.url, "https://api.vk.com/method/messages.send")
        let body = String(data: call.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("peer_id=42"))
        // Cyrillic should be percent-encoded
        XCTAssertTrue(body.contains("message=%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82"))
        XCTAssertTrue(body.contains("random_id="))
    }

    func testEncodeFormBody_escapesReservedChars() {
        let encoded = VKAPIClient.encodeFormBody([
            "k": "a+b&c=d",
            "x": "hello world"
        ])
        let s = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("k=a%2Bb%26c%3Dd"))
        XCTAssertTrue(s.contains("x=hello%20world"))
    }

    // MARK: - Helpers

    private func makeClient(http: VKHTTPClient) -> VKAPIClient {
        VKAPIClient(
            token: "t-secret",
            apiVersion: "5.199",
            httpClient: http,
            logger: Logger(label: "test")
        )
    }
}

final class MockVKHTTPClient: VKHTTPClient, @unchecked Sendable {
    struct Call {
        let method: String
        let url: String
        let headers: [String: String]
        let body: Data?
    }

    private let lock = NSLock()
    private var responses: [Data] = []
    private(set) var calls: [Call] = []

    func queueResponse(json: String) {
        lock.lock(); defer { lock.unlock() }
        responses.append(json.data(using: .utf8)!)
    }

    func queueResponse(data: Data) {
        lock.lock(); defer { lock.unlock() }
        responses.append(data)
    }

    func send(method: String, url: String, headers: [String: String], body: Data?) async throws -> Data {
        lock.lock(); defer { lock.unlock() }
        calls.append(Call(method: method, url: url, headers: headers, body: body))
        guard !responses.isEmpty else {
            throw NSError(domain: "MockVKHTTPClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "no queued response"])
        }
        return responses.removeFirst()
    }
}
