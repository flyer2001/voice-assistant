import Foundation
import Crypto

/// AES-256-GCM bundle format used by Happy "dataKey" sessions.
/// Layout (matches `inject.mjs encryptDataKey`):
///   [version=0 : 1 byte][nonce : 12 bytes][ciphertext : N bytes][authTag : 16 bytes]
/// Encoded as base64 in the wire payload.
public enum HappyCrypto {

    public enum Error: Swift.Error, Equatable {
        case invalidKeyLength(Int)
        case invalidBundleLength(Int)
        case unsupportedVersion(UInt8)
        case decryptFailed(String)
    }

    /// Encrypt JSON-encoded payload with the session's 32-byte key (base64).
    public static func encryptDataKey<T: Encodable>(_ value: T, keyBase64: String) throws -> String {
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw Error.invalidKeyLength(0)
        }
        guard keyData.count == 32 else {
            throw Error.invalidKeyLength(keyData.count)
        }
        let key = SymmetricKey(data: keyData)
        let plaintext = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        // Manually compose [version=0][nonce:12][ct][tag:16]
        var bundle = Data([0])
        bundle.append(sealed.nonce.withUnsafeBytes { Data($0) })
        bundle.append(sealed.ciphertext)
        bundle.append(sealed.tag)
        return bundle.base64EncodedString()
    }

    /// Decrypt bundle (used by tests for roundtrip).
    public static func decryptDataKey<T: Decodable>(_ bundleBase64: String, keyBase64: String, as type: T.Type) throws -> T {
        guard let keyData = Data(base64Encoded: keyBase64), keyData.count == 32 else {
            throw Error.invalidKeyLength(0)
        }
        guard let bundle = Data(base64Encoded: bundleBase64) else {
            throw Error.invalidBundleLength(0)
        }
        guard bundle.count >= 1 + 12 + 16 else {
            throw Error.invalidBundleLength(bundle.count)
        }
        let version = bundle[0]
        guard version == 0 else {
            throw Error.unsupportedVersion(version)
        }
        let nonceData = bundle.subdata(in: 1..<13)
        let tagData = bundle.subdata(in: (bundle.count - 16)..<bundle.count)
        let ctData = bundle.subdata(in: 13..<(bundle.count - 16))
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ctData, tag: tagData)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealed, using: key)
        } catch {
            throw Error.decryptFailed(error.localizedDescription)
        }
        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}
