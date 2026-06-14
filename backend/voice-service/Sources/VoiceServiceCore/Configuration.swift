import Foundation

/// Backend configuration. `token` is the static Bearer accepted on the
/// Authorization header. `replyProvider` produces the assistant reply for
/// a given intent request — in tests it's a stub closure, in production
/// it will forward to Happy inject (port of inject.mjs, see Tasks B4-B5).
public struct Configuration: Sendable {
    public let token: String
    public let replyProvider: @Sendable (IntentRequest) async throws -> String
    public let sttProvider: STTProvider?
    public let requestLogger: RequestLogger?

    public init(
        token: String,
        replyProvider: @escaping @Sendable (IntentRequest) async throws -> String,
        sttProvider: STTProvider? = nil,
        requestLogger: RequestLogger? = nil
    ) {
        self.token = token
        self.replyProvider = replyProvider
        self.sttProvider = sttProvider
        self.requestLogger = requestLogger
    }
}
