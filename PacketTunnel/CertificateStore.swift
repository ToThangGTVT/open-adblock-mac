import CryptoKit
import Foundation
import OpenAdBlockCore
import os

private let logger = Logger(subsystem: "io.github.tothanggtvt.openadblock.mac", category: "certificate")

/// The local root CA for browser filtering. The P-256 key lives in the Secure Enclave when the
/// Mac has one (only an opaque, device-bound handle is stored), otherwise in a root-only file in
/// the extension's container. The core never sees the key: it asks `sign` for each certificate.
final class CertificateStore {
    struct Authority {
        let signer: CertificateSigner
        let publicPoint: Data
        let certificate: Data
        /// Lowercase hex SHA-256 of the DER certificate.
        let fingerprint: String
    }

    private var keyURL: URL { AppGroup.container.appendingPathComponent("root-ca.key") }
    private var certificateURL: URL { AppGroup.container.appendingPathComponent("root-ca.der") }
    private(set) var authority: Authority?

    /// Loads the CA, creating key and certificate on first use when `create` is set.
    @discardableResult
    func load(create: Bool, engine: NativeEngine) -> Authority? {
        if let authority { return authority }
        guard let signer = loadKey() ?? (create ? createKey() : nil) else { return nil }
        var certificate = try? Data(contentsOf: certificateURL)
        if certificate == nil, create {
            certificate = engine.generateRootCA(signer: signer, publicPoint: signer.publicPoint)
            if let certificate { try? write(certificate, to: certificateURL) }
        }
        guard let certificate else { return nil }
        let fingerprint = SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        authority = Authority(
            signer: signer, publicPoint: signer.publicPoint, certificate: certificate,
            fingerprint: fingerprint)
        logger.info("Root CA ready (\(signer.kind, privacy: .public) key)")
        return authority
    }

    private func loadKey() -> KeySigner? {
        guard let stored = try? Data(contentsOf: keyURL), let kind = stored.first else { return nil }
        let body = stored.dropFirst()
        switch kind {
        case 1:
            return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: body))
                .map(KeySigner.enclave)
        case 2:
            return (try? P256.Signing.PrivateKey(rawRepresentation: body)).map(KeySigner.software)
        default:
            return nil
        }
    }

    private func createKey() -> KeySigner? {
        if SecureEnclave.isAvailable, let key = try? SecureEnclave.P256.Signing.PrivateKey(),
            (try? write(Data([1]) + key.dataRepresentation, to: keyURL)) != nil
        {
            return .enclave(key)
        }
        let key = P256.Signing.PrivateKey()
        guard (try? write(Data([2]) + key.rawRepresentation, to: keyURL)) != nil else { return nil }
        return .software(key)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Signs certificates for the core with whichever key the store holds.
private final class KeySigner: CertificateSigner {
    private enum Key {
        case enclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)
    }

    private let key: Key
    private init(_ key: Key) { self.key = key }

    static func enclave(_ key: SecureEnclave.P256.Signing.PrivateKey) -> KeySigner {
        KeySigner(.enclave(key))
    }
    static func software(_ key: P256.Signing.PrivateKey) -> KeySigner { KeySigner(.software(key)) }

    var kind: String {
        switch key {
        case .enclave: "Secure Enclave"
        case .software: "software"
        }
    }

    var publicPoint: Data {
        switch key {
        case .enclave(let key): key.publicKey.x963Representation
        case .software(let key): key.publicKey.x963Representation
        }
    }

    func sign(_ data: Data) -> Data? {
        switch key {
        case .enclave(let key): try? key.signature(for: data).derRepresentation
        case .software(let key): try? key.signature(for: data).derRepresentation
        }
    }
}
