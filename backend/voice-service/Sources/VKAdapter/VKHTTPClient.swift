import Foundation
import AsyncHTTPClient
import NIOCore
import NIOFoundationCompat

public protocol VKHTTPClient: Sendable {
    func send(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?
    ) async throws -> Data
}

public struct LiveVKHTTPClient: VKHTTPClient {
    private let client: HTTPClient
    private let timeout: TimeAmount

    public init(client: HTTPClient = .shared, timeout: TimeAmount = .seconds(30)) {
        self.client = client
        self.timeout = timeout
    }

    public func send(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?
    ) async throws -> Data {
        var request = HTTPClientRequest(url: url)
        request.method = .init(rawValue: method)
        for (k, v) in headers {
            request.headers.add(name: k, value: v)
        }
        if let body {
            request.body = .bytes(body)
        }
        let response = try await client.execute(request, timeout: timeout)
        let buffer = try await response.body.collect(upTo: 10 * 1024 * 1024)
        return Data(buffer: buffer)
    }
}
