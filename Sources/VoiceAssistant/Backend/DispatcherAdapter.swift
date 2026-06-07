import Foundation

/// Default adapter wired up in v0.0/v0.1. Posts the transcribed text to
/// the author's private Hummingbird endpoint, which forwards into a
/// Claude Code session via the Happy inject API.
///
/// This is one of several future adapters. An open-source / sellable build
/// of this project will swap DispatcherAdapter for SlackAdapter,
/// RawHTTPAdapter, or OwnServerAdapter without touching the UI layer.
///
/// Wire format: specs/backend-protocol.md.
public struct DispatcherAdapter: BackendAdapter {

    public let baseURL: URL
    public let token: String
    public let session: URLSession

    public init(
        baseURL: URL,
        token: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func send(_ request: TranscribedRequest) async throws -> Reply {
        // v0.0 skeleton — full implementation arrives in v0.1 once the
        // backend endpoint is up. See .claude/TASKS.md.
        //
        // Intentionally NOT implemented yet. The first BackendAdapter
        // test will be written against a Fake; this is here only to
        // anchor the type and confirm protocol conformance compiles.
        throw BackendError.backendUnavailable
    }
}
