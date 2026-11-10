import Foundation

/// A PEM block (RFC 7468) holding a private key: its label (`OPENSSH PRIVATE KEY`, `RSA PRIVATE KEY`…), whether the
/// old encryption headers of RFC 1421 say it's encrypted (`Proc-Type: 4,ENCRYPTED`), and its decoded content. Line
/// breaks may be `\n` or `\r\n`, and lines indented; what surrounds the block is ignored. Pure type.
nonisolated struct SSHPEMBlock {
    let label: String
    let isEncrypted: Bool
    let body: [UInt8]

    /// The first block of `text` whose label names a private key (`… PRIVATE KEY`), skipping the others
    /// (`EC PARAMETERS`); nil if there's none. A block without its end line or with invalid base 64 is malformed.
    static func firstPrivateKey(in text: String) throws(SSHKeyError) -> SSHPEMBlock? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, line) in lines.enumerated() {
            guard let label = label(of: line, boundary: "BEGIN"), label.hasSuffix("PRIVATE KEY") else {
                continue
            }
            guard let end = lines[(index + 1)...].firstIndex(where: { Self.label(of: $0, boundary: "END") == label }) else {
                throw .malformed
            }
            let content = lines[(index + 1) ..< end]
            let headers = content.filter { $0.contains(":") }
            guard let body = Data(base64Encoded: content.filter { !$0.contains(":") }.joined()) else {
                throw .malformed
            }
            let isEncrypted = headers.contains { $0.hasPrefix("Proc-Type:") && $0.contains("ENCRYPTED") }
            return SSHPEMBlock(label: label, isEncrypted: isEncrypted, body: Array(body))
        }
        return nil
    }

    /// The label of a `-----BEGIN label-----` or `-----END label-----` line.
    private static func label(of line: String, boundary: String) -> String? {
        let prefix = "-----\(boundary) "
        let suffix = "-----"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix), line.count > prefix.count + suffix.count else {
            return nil
        }
        return String(line.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
