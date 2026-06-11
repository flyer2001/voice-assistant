import Foundation

public struct IntentRequest: Codable, Sendable, Equatable {
    public let text: String
    public let client_id: String
    public let ts: String

    public init(text: String, client_id: String, ts: String) {
        self.text = text
        self.client_id = client_id
        self.ts = ts
    }
}

public struct IntentResponse: Codable, Sendable, Equatable {
    public let reply: String
    public let latency_ms: Int

    public init(reply: String, latency_ms: Int) {
        self.reply = reply
        self.latency_ms = latency_ms
    }
}
