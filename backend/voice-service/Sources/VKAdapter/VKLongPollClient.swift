import Foundation

public enum VKPollOutcome: Equatable, Sendable {
    case updates([VKUpdate])
    case needsServerRefetch
}

extension VKPollOutcome {
    public static func == (lhs: VKPollOutcome, rhs: VKPollOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.needsServerRefetch, .needsServerRefetch):
            return true
        case (.updates(let a), .updates(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.type == $1.type }
        default:
            return false
        }
    }
}

public enum VKLongPollError: Error, Equatable {
    case invalidVersion
    case unknownFailedCode(Int)
}

public actor VKLongPollClient {
    private var server: VKLongPollServer
    private let httpClient: any VKHTTPClient
    private let waitSeconds: Int

    public init(server: VKLongPollServer, httpClient: any VKHTTPClient, waitSeconds: Int = 25) {
        self.server = server
        self.httpClient = httpClient
        self.waitSeconds = waitSeconds
    }

    public func replaceServer(_ newServer: VKLongPollServer) {
        self.server = newServer
    }

    public func nextBatch() async throws -> VKPollOutcome {
        let url = buildURL()
        let data = try await httpClient.send(method: "GET", url: url, headers: [:], body: nil)
        let response = try JSONDecoder().decode(VKLongPollUpdates.self, from: data)

        if let failed = response.failed {
            switch failed {
            case 1:
                if let newTs = response.ts {
                    server = VKLongPollServer(server: server.server, key: server.key, ts: newTs)
                }
                return .updates([])
            case 2, 3:
                return .needsServerRefetch
            case 4:
                throw VKLongPollError.invalidVersion
            default:
                throw VKLongPollError.unknownFailedCode(failed)
            }
        }

        if let newTs = response.ts {
            server = VKLongPollServer(server: server.server, key: server.key, ts: newTs)
        }
        return .updates(response.updates ?? [])
    }

    private func buildURL() -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        let query = [
            "act=a_check",
            "key=\(enc(server.key))",
            "ts=\(enc(server.ts))",
            "wait=\(waitSeconds)"
        ].joined(separator: "&")
        return "\(server.server)?\(query)"
    }
}
