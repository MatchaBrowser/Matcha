import Foundation

/// SSH keys of the imported files (`VAULT.md` § 9.4).
nonisolated extension VaultImportDraft {
    /// Adds an `ssh-key` credential and makes the item an SSH key. A private key in OpenSSH format is kept as it is, one
    /// in PKCS#8 turned into OpenSSH; the public key and fingerprint are computed from it. A key this version can't read
    /// (encrypted, another type) is kept as it came, with the given public key and fingerprint, and reported.
    mutating func addSSHKey(privateKey: String, publicKey: String = "", fingerprint: String = "", comment: String = "") {
        category = .sshKey
        let publicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = publicKey.split(separator: " ", maxSplits: 2).map(String.init)
        let comment = comment.isEmpty && parts.count == 3 ? parts[2] : comment
        guard let key = VaultSSHKey(text: privateKey, comment: comment) else {
            addCredential(VaultCredentialType.sshKey, [
                "keyType": parts.first ?? "",
                "privateKey": privateKey,
                "publicKey": publicKey,
                "fingerprint": fingerprint,
                "keyComment": comment,
            ])
            if !privateKey.isEmpty {
                issues.append(.unconvertedSSHKey)
            }
            return
        }
        var credential = key.credential
        if privateKey.contains("BEGIN OPENSSH PRIVATE KEY") {
            credential.set("privateKey", privateKey)
        }
        addCredential(credential)
    }

    /// Adds the key of a PKCS#8 `PrivateKeyInfo` in DER (CXF), or keeps it in PEM and reports it if it can't be read.
    mutating func addSSHKey(pkcs8 der: Data, comment: String) {
        if let key = VaultSSHKey(pkcs8: der, comment: comment) {
            category = .sshKey
            addCredential(key.credential)
        } else {
            let base64 = Array(der.base64EncodedString())
            let lines = stride(from: 0, to: base64.count, by: 64).map { String(base64[$0 ..< min($0 + 64, base64.count)]) }
            let pem = (["-----BEGIN PRIVATE KEY-----"] + lines + ["-----END PRIVATE KEY-----"]).joined(separator: "\n") + "\n"
            addSSHKey(privateKey: pem, comment: comment)
        }
    }
}
