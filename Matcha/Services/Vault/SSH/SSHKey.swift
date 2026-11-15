import CryptoKit
import Foundation

/// An SSH key as the vault keeps it (`VAULT.md` § 9.4, credential `ssh-key`), whether generated (`SSHKeyGenerator`) or
/// imported (`SSHKeyImporter`): the private key in OpenSSH's format, without passphrase since the vault protects it,
/// and what is derived from it. The comment is free text, its control characters replaced with spaces so that the
/// public line stays a single `authorized_keys` line. Pure type.
nonisolated struct SSHKey: Sendable, Equatable {
    let keyType: SSHKeyType
    /// `-----BEGIN OPENSSH PRIVATE KEY-----`…, unencrypted, as `ssh-keygen` writes it.
    let privateKey: String
    /// The `authorized_keys` line: `ssh-ed25519 AAAA… comment`, without the comment when it's empty.
    let publicKey: String
    /// `SHA256:` then the base 64 of the public key's SHA-256, without padding, like `ssh-keygen -l`.
    let fingerprint: String
    let comment: String
    /// The size of an RSA key's modulus; nil for the other types.
    let bits: Int?

    /// The vault's form of `key`. `checkInt`, the random number that OpenSSH repeats at the start of the private
    /// section, is only given to reproduce a file.
    init(_ key: SSHPrivateKey, comment: String, checkInt: UInt32? = nil) {
        let comment = Self.sanitized(comment)
        let blob = Data(key.publicBlob)
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        keyType = key.keyType
        privateKey = OpenSSHKeyWriter.text(of: key, comment: comment, checkInt: checkInt ?? .random(in: .min ... .max))
        publicKey = ([key.keyType.rawValue, blob.base64EncodedString()] + (comment.isEmpty ? [] : [comment]))
            .joined(separator: " ")
        fingerprint = "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        self.comment = comment
        bits = key.bits
    }

    /// `comment` with its control characters and line or paragraph separators replaced with spaces.
    static func sanitized(_ comment: String) -> String {
        let scalars = comment.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: " "
            default: scalar
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
