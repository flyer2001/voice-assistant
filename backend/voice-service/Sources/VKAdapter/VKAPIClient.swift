import Foundation
import Logging

public struct VKAPIClient: Sendable {
    private let token: String
    private let apiVersion: String
    private let httpClient: any VKHTTPClient
    private let logger: Logger
    private let baseURL: String

    public init(
        token: String,
        apiVersion: String = "5.199",
        httpClient: any VKHTTPClient,
        logger: Logger,
        baseURL: String = "https://api.vk.com"
    ) {
        self.token = token
        self.apiVersion = apiVersion
        self.httpClient = httpClient
        self.logger = logger
        self.baseURL = baseURL
    }

    public func getLongPollServer(groupId: Int) async throws -> VKLongPollServer {
        let resp: VKAPIResponse<VKLongPollServer> = try await call(
            method: "groups.getLongPollServer",
            params: ["group_id": String(groupId)]
        )
        return try unwrap(resp, method: "groups.getLongPollServer")
    }

    @discardableResult
    public func sendMessage(peerId: Int64, text: String) async throws -> VKMessageSendResult {
        let randomId = Int64.random(in: 1...Int64.max)
        logger.info("VK messages.send", metadata: [
            "peer_id": .stringConvertible(peerId),
            "text_len": .stringConvertible(text.count),
            "random_id": .stringConvertible(randomId)
        ])

        let resp: VKAPIResponse<VKMessageSendResult> = try await call(
            method: "messages.send",
            params: [
                "peer_id": String(peerId),
                "message": text,
                "random_id": String(randomId)
            ]
        )
        let messageId = try unwrap(resp, method: "messages.send")
        logger.info("VK messages.send ok", metadata: ["message_id": .stringConvertible(messageId)])
        return messageId
    }

    // MARK: - Private

    private func call<T: Decodable & Sendable>(
        method: String,
        params: [String: String]
    ) async throws -> VKAPIResponse<T> {
        let url = "\(baseURL)/method/\(method)"
        var allParams = params
        allParams["access_token"] = token
        allParams["v"] = apiVersion

        let body = Self.encodeFormBody(allParams)
        let data = try await httpClient.send(
            method: "POST",
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        return try JSONDecoder().decode(VKAPIResponse<T>.self, from: data)
    }

    private func unwrap<T>(_ resp: VKAPIResponse<T>, method: String) throws -> T {
        if let error = resp.error {
            logger.error("VK \(method) failed", metadata: [
                "error_code": .stringConvertible(error.errorCode),
                "error_msg": .string(error.errorMsg)
            ])
            throw error
        }
        guard let value = resp.response else {
            throw VKAPIError(errorCode: -1, errorMsg: "empty response for \(method)")
        }
        return value
    }

    static func encodeFormBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")

        let body = params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let ek = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let ev = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(ek)=\(ev)"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }
}
