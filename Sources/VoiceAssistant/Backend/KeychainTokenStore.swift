import Foundation
import Security

/// Production TokenStore backed by the system Keychain. Stores a single
/// generic-password item identified by (service, account). Defaults
/// match the dispatcher backend; integration apps can override service
/// for multi-environment installs (dev/staging/prod) without colliding.
///
/// Keychain access on iOS Simulator works without a Keychain Sharing
/// entitlement when the app is built with Personal Team signing
/// ("Sign to Run Locally"). For TestFlight / App Store releases the
/// app target needs the Keychain Sharing capability enabled.
public struct KeychainTokenStore: TokenStore {

    public let service: String
    public let account: String

    public init(
        service: String = "com.voiceassistant.backend.dispatcher",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainTokenStoreError.malformed
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.osStatus(status)
        }
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)

        // Try update first, fall back to add. Two-step keeps the API
        // idempotent without requiring callers to differentiate.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainTokenStoreError.osStatus(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainTokenStoreError.osStatus(addStatus)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.osStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public enum KeychainTokenStoreError: Error, Equatable, Sendable {
    case osStatus(OSStatus)
    case malformed
}
