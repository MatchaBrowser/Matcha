import CryptoKit
import Foundation

/// An SSH private key without a passphrase, read from and written to the OpenSSH format the vault keeps
/// (`VAULT.md` § 9.4) and PKCS#8, which CXF and 1Password use: Ed25519, ECDSA P-256 and P-384, RSA. Its public key
/// (`authorized_keys` line) and fingerprint (`SHA256:…`, as `ssh-keygen -l`) are computed from it. Pure type.
nonisolated struct VaultSSHKey: Equatable {
    /// RSA in the order of OpenSSH's private section.
    struct RSA: Equatable {
        var modulus: [UInt8]
        var publicExponent: [UInt8]
        var privateExponent: [UInt8]
        var coefficient: [UInt8]
        var prime1: [UInt8]
        var prime2: [UInt8]
    }

    enum Material: Equatable {
        case ed25519(seed: [UInt8])
        /// `d`, 32 or 48 bytes.
        case p256([UInt8])
        case p384([UInt8])
        case rsa(RSA)
    }

    let material: Material
    var comment: String

    init(material: Material, comment: String) {
        self.material = material
        self.comment = comment
    }

    /// A key in PEM: OpenSSH (`BEGIN OPENSSH PRIVATE KEY`) or PKCS#8 (`BEGIN PRIVATE KEY`); nil for any other, an
    /// encrypted one, or a type this version doesn't read.
    init?(text: String, comment: String = "") {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first, let last = lines.last,
              let bytes = Data(base64Encoded: lines.dropFirst().dropLast().joined())
        else {
            return nil
        }
        switch (first, last) {
        case ("-----BEGIN OPENSSH PRIVATE KEY-----", "-----END OPENSSH PRIVATE KEY-----"):
            self.init(openSSH: [UInt8](bytes))
        case ("-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"):
            self.init(pkcs8: bytes, comment: comment)
        default:
            return nil
        }
        if !comment.isEmpty {
            self.comment = comment
        }
    }

    // MARK: Public part

    var keyType: String {
        switch material {
        case .ed25519: "ssh-ed25519"
        case .p256: "ecdsa-sha2-nistp256"
        case .p384: "ecdsa-sha2-nistp384"
        case .rsa: "ssh-rsa"
        }
    }

    /// The public key in the wire format; nil if the private key is not a valid one.
    var publicBlob: [UInt8]? {
        let encoding = VaultSSHEncoding.self
        switch material {
        case let .ed25519(seed):
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
                return nil
            }
            return encoding.string(keyType) + encoding.string(Array(key.publicKey.rawRepresentation))
        case let .p256(scalar):
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: scalar) else {
                return nil
            }
            return encoding.string(keyType) + encoding.string("nistp256") + encoding.string(Array(key.publicKey.x963Representation))
        case let .p384(scalar):
            guard let key = try? P384.Signing.PrivateKey(rawRepresentation: scalar) else {
                return nil
            }
            return encoding.string(keyType) + encoding.string("nistp384") + encoding.string(Array(key.publicKey.x963Representation))
        case let .rsa(rsa):
            return encoding.string(keyType) + encoding.mpint(rsa.publicExponent) + encoding.mpint(rsa.modulus)
        }
    }

    /// The `authorized_keys` line: type, key in base 64, comment.
    var publicKey: String {
        let line = "\(keyType) \(Data(publicBlob ?? []).base64EncodedString())"
        return comment.isEmpty ? line : "\(line) \(comment)"
    }

    /// `SHA256:` and the digest of the public key in base 64 without padding.
    var fingerprint: String {
        "SHA256:" + Data(SHA256.hash(data: publicBlob ?? [])).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    /// The `ssh-key` credential of the vault, without its `id`.
    var credential: VaultEntry {
        var entry = VaultEntry(["type": .string(VaultCredentialType.sshKey)])
        entry.set("keyType", keyType)
        entry.set("privateKey", openSSH)
        entry.set("publicKey", publicKey)
        entry.set("fingerprint", fingerprint)
        entry.set("keyComment", comment)
        return entry
    }
}

// MARK: OpenSSH

nonisolated extension VaultSSHKey {
    private static let magic = Array("openssh-key-v1\0".utf8)

    /// The binary content of an OpenSSH private key (PROTOCOL.key), unencrypted, with a single key.
    init?(openSSH bytes: [UInt8]) {
        var reader = VaultSSHEncoding.Reader(bytes)
        guard reader.bytes(Self.magic.count) == Self.magic, reader.text() == "none", reader.text() == "none",
              reader.string() != nil, reader.uint32() == 1, reader.string() != nil, let section = reader.string()
        else {
            return nil
        }
        var keys = VaultSSHEncoding.Reader(section)
        guard let check = keys.uint32(), keys.uint32() == check, let type = keys.text(), let material = Self.material(type, &keys),
              let comment = keys.text()
        else {
            return nil
        }
        self.init(material: material, comment: comment)
    }

    private static func material(_ type: String, _ reader: inout VaultSSHEncoding.Reader) -> Material? {
        switch type {
        case "ssh-ed25519":
            guard let publicKey = reader.string(), let privateKey = reader.string(), privateKey.count == 64,
                  Array(privateKey.suffix(32)) == publicKey
            else {
                return nil
            }
            return .ed25519(seed: Array(privateKey.prefix(32)))
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384":
            guard let curve = reader.text(), reader.string() != nil, let scalar = reader.mpint() else {
                return nil
            }
            let size = curve == "nistp256" ? 32 : 48
            guard "ecdsa-sha2-" + curve == type, scalar.count <= size else {
                return nil
            }
            let padded = [UInt8](repeating: 0, count: size - scalar.count) + scalar
            return curve == "nistp256" ? .p256(padded) : .p384(padded)
        case "ssh-rsa":
            guard let modulus = reader.mpint(), let exponent = reader.mpint(), let privateExponent = reader.mpint(),
                  let coefficient = reader.mpint(), let prime1 = reader.mpint(), let prime2 = reader.mpint()
            else {
                return nil
            }
            let rsa = RSA(
                modulus: modulus,
                publicExponent: exponent,
                privateExponent: privateExponent,
                coefficient: coefficient,
                prime1: prime1,
                prime2: prime2,
            )
            return .rsa(rsa)
        default:
            return nil
        }
    }

    /// The key in the OpenSSH format, in PEM (lines of 70 characters, as `ssh-keygen`). The check bytes, which only
    /// verify a decryption, are taken from the public key: the same key is always written the same way.
    var openSSH: String {
        let encoding = VaultSSHEncoding.self
        let check = Array(SHA256.hash(data: publicBlob ?? []).prefix(4))
        var section = check + check + encoding.string(keyType)
        switch material {
        case let .ed25519(seed):
            let publicKey = Array((try? Curve25519.Signing.PrivateKey(rawRepresentation: seed))?.publicKey.rawRepresentation ?? Data())
            section += encoding.string(publicKey) + encoding.string(seed + publicKey)
        case let .p256(scalar), let .p384(scalar):
            var reader = VaultSSHEncoding.Reader(publicBlob ?? [])
            _ = reader.string()
            section += encoding.string(reader.string() ?? []) + encoding.string(reader.string() ?? []) + encoding.mpint(scalar)
        case let .rsa(rsa):
            section += [rsa.modulus, rsa.publicExponent, rsa.privateExponent, rsa.coefficient, rsa.prime1, rsa.prime2]
                .flatMap(encoding.mpint)
        }
        section += encoding.string(comment)
        section += (0 ..< (8 - section.count % 8) % 8).map { UInt8($0 + 1) }
        let blob = Self.magic + encoding.string("none") + encoding.string("none") + encoding.string([UInt8]()) + encoding.uint32(1)
            + encoding.string(publicBlob ?? []) + encoding.string(section)
        let base64 = Array(Data(blob).base64EncodedString())
        let lines = stride(from: 0, to: base64.count, by: 70).map { String(base64[$0 ..< min($0 + 70, base64.count)]) }
        return (["-----BEGIN OPENSSH PRIVATE KEY-----"] + lines + ["-----END OPENSSH PRIVATE KEY-----"]).joined(separator: "\n") + "\n"
    }
}
