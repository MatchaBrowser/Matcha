import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Touch ID for the vault (`VAULT.md` § 7.2): the vault root key wrapped by a P-256 key of this Mac's Secure Enclave,
/// whose use requires the current fingerprints. The Secure Enclave enforces it, not a check in this process; a change of
/// fingerprints makes the key unusable, and the password is asked again.
nonisolated enum VaultTouchID {
    static let info = Data("matcha.vault.touch-id.v1".utf8)

    /// What the keychain keeps (`SyncKeychain.Item.vaultTouchID`): the Secure Enclave key, usable on this Mac only,
    /// and the vault root key wrapped for it.
    struct Envelope: Codable, Equatable, Sendable {
        /// `dataRepresentation` of the Secure Enclave key: opaque, bound to this Mac.
        var key: Data
        /// Public key of the ephemeral key, X9.63.
        var ephemeralPublicKey: Data
        /// `nonce ‖ ciphertext ‖ tag` of the vault root key.
        var sealed: Data
    }

    enum Failure: Error, Equatable {
        /// No Secure Enclave or no fingerprint on this Mac.
        case unavailable
        /// The user cancelled, or the fingerprints don't match.
        case refused
        /// The key no longer opens: fingerprints changed, or another Mac.
        case invalidated
    }

    /// A Secure Enclave and enrolled fingerprints.
    static var isAvailable: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Wraps the vault root key for this Mac's Secure Enclave. No fingerprint is asked: only the public key works here.
    static func wrap(_ vaultRootKey: SymmetricKey) throws -> Envelope {
        var error: Unmanaged<CFError>?
        guard isAvailable, let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error,
        ) else {
            throw Failure.unavailable
        }
        let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let key = try derivedKey(ephemeral.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey), ephemeral: ephemeral.publicKey)
        let sealed = try SyncCrypto.seal(vaultRootKey.withUnsafeBytes { Data($0) }, key: key, aad: info)
        return Envelope(key: enclaveKey.dataRepresentation, ephemeralPublicKey: ephemeral.publicKey.x963Representation, sealed: sealed)
    }

    /// Asks for the fingerprint, then the Secure Enclave opens the envelope. A new context each time: no recent
    /// authentication is reused.
    static func unwrap(_ envelope: Envelope, reason: String) async throws -> SymmetricKey {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
                throw Failure.refused
            }
        } catch let error as LAError where error.code == .biometryNotAvailable || error.code == .biometryNotEnrolled {
            throw Failure.unavailable
        } catch is LAError {
            throw Failure.refused
        }
        do {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: envelope.key,
                authenticationContext: context,
            )
            let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralPublicKey)
            let key = try derivedKey(enclaveKey.sharedSecretFromKeyAgreement(with: ephemeral), ephemeral: ephemeral)
            let bytes = try SyncCrypto.open(envelope.sealed, key: key, aad: info)
            guard bytes.count == 32 else {
                throw Failure.invalidated
            }
            return SymmetricKey(data: bytes)
        } catch {
            throw Failure.invalidated
        }
    }

    /// HKDF-SHA256 of the shared secret, salt = the ephemeral public key, info = the label (`VAULT.md` § 7.2).
    private static func derivedKey(_ secret: SharedSecret, ephemeral: P256.KeyAgreement.PublicKey) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: ephemeral.x963Representation, sharedInfo: info, outputByteCount: 32)
    }
}
