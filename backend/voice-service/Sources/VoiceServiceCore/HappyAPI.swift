import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP client for Happy server REST relay. Used by
/// LiveHappyInjectMessenger to POST encrypted user-messages.
public struct HappyAPI: Sendable {

    public enum Error: Swift.Error, Equatable {
        case nonOKStatus(Int, String)
        case transportError(String)
    }

    public let serverURL: URL
    public let urlSession: URLSession

    public init(serverURL: URL? = nil, urlSession: URLSession = .shared) {
        let env = ProcessInfo.processInfo.environment["HAPPY_SERVER_URL"]
        self.serverURL = serverURL ?? URL(string: env ?? "https://api.cluster-fluster.com")!
        self.urlSession = urlSession
    }

    /// Send encrypted message to /v3/sessions/{sid}/messages.
    public func postMessage(sid: String, token: String, encryptedB64: String, localId: String = UUID().uuidString) async throws {
        let escapedSid = sid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sid
        let url = serverURL.appendingPathComponent("v3/sessions/\(escapedSid)/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("voice-service-swift/0.1", forHTTPHeaderField: "X-Happy-Client")
        let body: [String: Any] = [
            "messages": [["content": encryptedB64, "localId": localId]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw Error.transportError(error.localizedDescription)
        }
        let http = response as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw Error.nonOKStatus(http.statusCode, bodyStr)
        }
    }
}
