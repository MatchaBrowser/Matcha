import Foundation

/// Why an SSH key could not be imported or generated (`VAULT.md` § 9.4). No text: the interface words each case.
nonisolated enum SSHKeyError: Error, Equatable, Sendable {
    /// What the file is or uses, when Matcha can't read it.
    enum Unsupported: Equatable, Sendable {
        /// A key type other than Ed25519, ECDSA P-256/P-384 and RSA: its OpenSSH name (`ssh-dss`,
        /// `sk-ssh-ed25519@openssh.com`) or, from a PEM file, the dotted identifier of its algorithm.
        case keyType(String)
        /// An OpenSSH key encrypted with another cipher (`chacha20-poly1305@openssh.com`, `3des-cbc`).
        case cipher(String)
        /// An OpenSSH key protected by another key derivation than `bcrypt`.
        case kdf(String)
        /// A `bcrypt` cost above `OpenSSHKeyReader.maximumRounds`, refused so that a file can't keep the Mac busy.
        case kdfRounds(Int)
        /// A file holding several keys.
        case multipleKeys
        /// A public key, not a private one (`id_ed25519.pub`, `BEGIN PUBLIC KEY`).
        case publicKey
        /// Another format: PuTTY, another PEM label.
        case format
    }

    /// The key is encrypted and no passphrase was given.
    case needsPassphrase
    /// The passphrase doesn't decrypt the key.
    case wrongPassphrase
    /// An encrypted PEM file (`BEGIN ENCRYPTED PRIVATE KEY`, or `Proc-Type: 4,ENCRYPTED`): to be decrypted first, or
    /// converted to the OpenSSH format (`ssh-keygen -p`).
    case encryptedPEM
    case unsupported(Unsupported)
    /// Not a key, truncated, inconsistent or larger than the limits.
    case malformed
    /// An RSA key of fewer than `SSHRSAKey.minimumImportBits` bits.
    case weakRSA
    /// Generation: an RSA size other than those of `SSHKeyGenerator.rsaSizes`.
    case invalidRSASize
    /// Generation: the system could not create the key.
    case generationFailed
}
