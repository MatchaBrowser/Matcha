import Foundation

/// Writer of OpenSSH's private key format (`openssh-key-v1`, `PROTOCOL.key`) as `ssh-keygen` writes an unencrypted key:
/// cipher and kdf `none`, one key, the private section padded with 1, 2, 3… to a multiple of 8 bytes, base 64 in lines
/// of 70 characters between the `OPENSSH PRIVATE KEY` lines. Pure type.
nonisolated enum OpenSSHKeyWriter {
    /// `openssh-key-v1` and its terminating zero, at the start of the binary content.
    static let magic = Array("openssh-key-v1".utf8) + [0]
    static let label = "OPENSSH PRIVATE KEY"
    /// Block size of the cipher `none`, to which the private section is padded.
    static let unencryptedBlockSize = 8
    private static let lineWidth = 70

    /// The file's text, ending with a line break.
    static func text(of key: SSHPrivateKey, comment: String, checkInt: UInt32) -> String {
        var section = SSHWireWriter()
        section.write(checkInt)
        section.write(checkInt)
        key.writePrivate(to: &section)
        section.write(string: comment)
        var padding: UInt8 = 0
        while section.bytes.count % unencryptedBlockSize != 0 {
            padding += 1
            section.write(byte: padding)
        }

        var file = SSHWireWriter()
        file.write(raw: magic)
        file.write(string: "none")
        file.write(string: "none")
        file.write(string: [])
        file.write(UInt32(1))
        file.write(string: key.publicBlob)
        file.write(string: section.bytes)

        let encoded = Array(Data(file.bytes).base64EncodedString())
        let lines = stride(from: 0, to: encoded.count, by: lineWidth).map { start in
            String(encoded[start ..< min(start + lineWidth, encoded.count)])
        }
        return (["-----BEGIN \(label)-----"] + lines + ["-----END \(label)-----"]).joined(separator: "\n") + "\n"
    }
}
