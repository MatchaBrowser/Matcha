import Foundation

/// Import of an SSH private key into the vault (`VAULT.md` § 9.4): OpenSSH's format, unencrypted or encrypted (the
/// passphrase decrypts it once, the vault then keeps it unencrypted), and PKCS#8, PKCS#1 or SEC1 in PEM, unencrypted.
/// The text is untrusted: its size is capped, as is every length inside, and anything unexpected is an `SSHKeyError`.
/// RSA keys of fewer than 2 048 bits are refused. Decrypting costs up to a few seconds (`OpenSSHKeyReader`): to be
/// called away from the main actor. Pure type.
nonisolated enum SSHKeyImporter {
    /// Largest text read, in UTF-8 bytes: a 16 384-bit RSA key, the largest OpenSSH has, takes about 13 KB.
    static let maximumTextSize = 64 * 1024

    /// The key in `text`, the content of a key file or what was pasted; `passphrase` is only used for an encrypted
    /// OpenSSH key, and an empty one counts as none.
    static func importKey(_ text: String, passphrase: String?) throws(SSHKeyError) -> SSHKey {
        guard text.utf8.count <= maximumTextSize else {
            throw .malformed
        }
        guard let block = try SSHPEMBlock.firstPrivateKey(in: text) else {
            throw unrecognized(text)
        }
        guard block.label == OpenSSHKeyWriter.label else {
            return try SSHKey(accepted(pemKey(block)), comment: "")
        }
        // The check number is kept: an unencrypted file is then stored exactly as it was.
        let decoded = try OpenSSHKeyReader.read(block.body, passphrase: passphrase)
        return try SSHKey(accepted(decoded.key), comment: decoded.comment, checkInt: decoded.checkInt)
    }

    /// The key of a PEM block other than OpenSSH's.
    private static func pemKey(_ block: SSHPEMBlock) throws(SSHKeyError) -> SSHPrivateKey {
        guard block.label != "ENCRYPTED PRIVATE KEY", !block.isEncrypted else {
            throw .encryptedPEM
        }
        switch block.label {
        case "PRIVATE KEY":
            return try SSHPEMKeyDecoder.pkcs8(block.body)
        case "RSA PRIVATE KEY":
            return try .rsa(SSHRSAKey(pkcs1: block.body))
        case "EC PRIVATE KEY":
            return try SSHPEMKeyDecoder.sec1(block.body, curve: nil)
        case "DSA PRIVATE KEY":
            throw .unsupported(.keyType("ssh-dss"))
        default:
            throw .unsupported(.format)
        }
    }

    /// `key`, unless it's an RSA key below `SSHRSAKey.minimumImportBits`.
    private static func accepted(_ key: SSHPrivateKey) throws(SSHKeyError) -> SSHPrivateKey {
        if let bits = key.bits, bits < SSHRSAKey.minimumImportBits {
            throw .weakRSA
        }
        return key
    }

    /// Why a text without a private key block is refused: a public key (an `authorized_keys` line, a PEM or RFC 4716
    /// public key), another format (PuTTY, another PEM label), or not a key at all.
    private static func unrecognized(_ text: String) -> SSHKeyError {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.prefix { !$0.isWhitespace }
        let publicPrefixes = ["ssh-", "ecdsa-", "sk-"]
        if publicPrefixes.contains(where: { firstWord.hasPrefix($0) }) || trimmed.contains("PUBLIC KEY") {
            return .unsupported(.publicKey)
        }
        if trimmed.hasPrefix("PuTTY-User-Key-File-") || trimmed.contains("-----BEGIN ") || trimmed.contains("---- BEGIN ") {
            return .unsupported(.format)
        }
        return .malformed
    }
}
