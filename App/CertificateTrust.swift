import AppKit
import CryptoKit
import Foundation
import Security

/// Trust of the extension's local root CA in the user's login keychain. Browsers using the macOS
/// trust store (Safari, Chrome, Edge, Brave, Arc; Firefox with enterprise roots) then accept the
/// certificates the core mints for filtered sites.
enum CertificateTrust {
    static let label = "Open AdBlock Local CA"

    static func fingerprint(_ der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// True when macOS trusts the certificate as a root for TLS servers.
    static func isTrusted(_ der: Data) -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return false }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, nil), &trust) == errSecSuccess,
            let trust
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    /// Adds the certificate to the login keychain and marks it trusted for this user. macOS asks
    /// for the user's password. Throws when the user cancels or the keychain refuses.
    static func install(_ der: Data) throws {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw CocoaError(.coderInvalidValue)
        }
        let add = SecItemAdd(
            [
                kSecClass: kSecClassCertificate, kSecValueRef: certificate,
                kSecAttrLabel: label,
            ] as CFDictionary, nil)
        guard add == errSecSuccess || add == errSecDuplicateItem else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(add))
        }
        let settings: [[String: Any]] = [
            [kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
             kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue],
        ]
        let status = SecTrustSettingsSetTrustSettings(certificate, .user, settings as CFArray)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Removes the trust setting and the certificate from the login keychain.
    static func remove(_ der: Data) {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return }
        _ = SecTrustSettingsRemoveTrustSettings(certificate, .user)
        _ = SecItemDelete([kSecClass: kSecClassCertificate, kSecValueRef: certificate] as CFDictionary)
    }

    /// Fallback when the keychain API is refused: opens the certificate in Keychain Access, where
    /// the user sets "Always Trust" by hand.
    static func openInKeychainAccess(_ der: Data) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Open AdBlock Local CA.cer")
        try der.write(to: url, options: .atomic)
        NSWorkspace.shared.open(url)
    }
}
