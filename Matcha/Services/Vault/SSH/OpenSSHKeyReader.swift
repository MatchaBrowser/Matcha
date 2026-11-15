import Foundation

/// Reader of OpenSSH's private key format (`openssh-key-v1`, `PROTOCOL.key`), over untrusted bytes: unencrypted, or
/// encrypted with the `bcrypt` kdf (`BcryptPBKDF`) and an `OpenSSHCipher`. Like OpenSSH, a wrong passphrase shows in the
/// two check numbers at the start of the decrypted section, which then differ; the private key must also match the
/// public key in the clear, and the padding be 1, 2, 3… The key's type is checked before the passphrase is asked for.
/// Pure type.
nonisolated enum OpenSSHKeyReader {
    /// Highest `bcrypt` cost accepted (`ssh-keygen -a`, 16 by default, a tenth of a second on an Apple silicon Mac):
    /// about 6 s at this cost.
    static let maximumRounds = 1000
    private static let maximumSaltLength = 1024

    /// A key read, its comment, and the check number of its private section.
    struct Decoded {
        let key: SSHPrivateKey
        let comment: String
        let checkInt: UInt32
    }

    /// The key in `blob`, the binary content of an `OPENSSH PRIVATE KEY` block; `passphrase` is only used if the key is
    /// encrypted.
    static func read(_ blob: [UInt8], passphrase: String?) throws(SSHKeyError) -> Decoded {
        var reader = SSHWireReader(blob)
        guard try reader.readBytes(OpenSSHKeyWriter.magic.count) == OpenSSHKeyWriter.magic else {
            throw .malformed
        }
        let cipherName = try reader.readName()
        let kdfName = try reader.readName()
        let kdfOptions = try reader.readString()
        switch try reader.readUInt32() {
        case 0: throw .malformed
        case 1: break
        default: throw .unsupported(.multipleKeys)
        }
        let publicBlob = try reader.readString()
        let encrypted = try reader.readString()
        let tag = reader.readRemaining()

        var publicReader = SSHWireReader(publicBlob)
        let typeName = try publicReader.readName()
        guard SSHKeyType(rawValue: typeName) != nil else {
            throw .unsupported(.keyType(typeName))
        }
        let cipher = try cipher(named: cipherName, kdf: kdfName)
        guard tag.count == cipher.tagSize, encrypted.count >= cipher.blockSize, encrypted.count % cipher.blockSize == 0 else {
            throw .malformed
        }
        let section = try decrypt(encrypted, tag: tag, cipher: cipher, kdfOptions: kdfOptions, passphrase: passphrase)
        return try readSection(section, publicBlob: publicBlob, isEncrypted: cipher.mode != .none)
    }

    /// The cipher, which must go with the kdf: `none` with `none`, any other with `bcrypt`.
    private static func cipher(named name: String, kdf: String) throws(SSHKeyError) -> OpenSSHCipher {
        guard kdf == "none" || kdf == "bcrypt" else {
            throw .unsupported(.kdf(kdf))
        }
        guard let cipher = OpenSSHCipher(name: name) else {
            throw .unsupported(.cipher(name))
        }
        guard (cipher.mode == .none) == (kdf == "none") else {
            throw .malformed
        }
        return cipher
    }

    /// The private section in the clear. The kdf's options (`string salt, uint32 rounds`) are checked before the
    /// passphrase is asked for, so that a key Matcha won't open doesn't ask for it.
    private static func decrypt(
        _ encrypted: [UInt8],
        tag: [UInt8],
        cipher: OpenSSHCipher,
        kdfOptions: [UInt8],
        passphrase: String?,
    ) throws(SSHKeyError) -> [UInt8] {
        guard cipher.mode != .none else {
            guard kdfOptions.isEmpty else {
                throw .malformed
            }
            return encrypted
        }
        var options = SSHWireReader(kdfOptions)
        let salt = try options.readString()
        let rounds = try options.readUInt32()
        guard options.isAtEnd, !salt.isEmpty, salt.count <= maximumSaltLength, rounds >= 1 else {
            throw .malformed
        }
        guard rounds <= maximumRounds else {
            throw .unsupported(.kdfRounds(Int(rounds)))
        }
        guard let passphrase, !passphrase.isEmpty else {
            throw .needsPassphrase
        }
        let length = cipher.keySize + cipher.ivSize
        guard let derived = BcryptPBKDF.derive(password: Data(passphrase.utf8), salt: Data(salt), rounds: Int(rounds), length: length)
        else {
            throw .malformed
        }
        let bytes = Array(derived)
        return try cipher.decrypt(
            encrypted,
            key: Array(bytes[..<cipher.keySize]),
            initializationVector: Array(bytes[cipher.keySize...]),
            tag: tag,
        )
    }

    /// `uint32 check, uint32 check`, the key, `string comment`, then the padding.
    private static func readSection(_ section: [UInt8], publicBlob: [UInt8], isEncrypted: Bool) throws(SSHKeyError) -> Decoded {
        var reader = SSHWireReader(section)
        let checkInt = try reader.readUInt32()
        guard try reader.readUInt32() == checkInt else {
            throw isEncrypted ? .wrongPassphrase : .malformed
        }
        let key = try SSHPrivateKey.read(from: &reader)
        guard key.publicBlob == publicBlob else {
            throw .malformed
        }
        let comment = try reader.readText()
        var expected: UInt8 = 1
        while !reader.isAtEnd {
            guard try reader.readByte() == expected else {
                throw .malformed
            }
            expected &+= 1
        }
        return Decoded(key: key, comment: comment, checkInt: checkInt)
    }
}
