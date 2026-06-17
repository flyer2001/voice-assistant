import Foundation

/// Contract every backend-token store honors. Production wires up
/// `KeychainTokenStore`; tests and the dev fallback use
/// `InMemoryTokenStore`. ContentView reads at launch and shows the
/// onboarding sheet if the result is nil.
public protocol TokenStore: Sendable {
    func read() throws -> String?
    func write(_ token: String) throws
    func clear() throws
}

/// In-memory implementation. Thread-safe enough for the iOS app's
/// single-threaded MainActor access pattern (NSLock guards in case a
/// background task picks it up). Used by tests and as a dev fallback
/// when Keychain access fails on simulator.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?
    private let lock = NSLock()

    public init(initial: String? = nil) {
        self.token = initial
    }

    public func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func write(_ token: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        self.token = nil
    }
}
