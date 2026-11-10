import Foundation

/// Reader of SSH's binary encoding (RFC 4251 § 5: `uint32`, `string`, `mpint`) over untrusted bytes: every length is
/// checked against what is left, and anything out of bounds is `SSHKeyError.malformed`. Pure type.
nonisolated struct SSHWireReader {
    /// Longest algorithm or curve name accepted (`sk-ecdsa-sha2-nistp256@openssh.com` has 34 characters).
    static let maximumNameLength = 64
    /// Longest `mpint` accepted, in bytes: a 16 384-bit RSA modulus and its sign byte, OpenSSH's limit.
    static let maximumMPIntLength = 16384 / 8 + 1

    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func readByte() throws(SSHKeyError) -> UInt8 {
        try readBytes(1)[0]
    }

    mutating func readUInt32() throws(SSHKeyError) -> UInt32 {
        try readBytes(4).reduce(0) { ($0 &<< 8) | UInt32($1) }
    }

    /// The next `count` bytes.
    mutating func readBytes(_ count: Int) throws(SSHKeyError) -> [UInt8] {
        guard count >= 0, count <= bytes.count - offset else {
            throw .malformed
        }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }

    /// A `string`: a `uint32` length, then as many bytes.
    mutating func readString() throws(SSHKeyError) -> [UInt8] {
        let length = try readUInt32()
        guard length <= UInt32(bytes.count - offset) else {
            throw .malformed
        }
        return try readBytes(Int(length))
    }

    /// A `string` holding a name (algorithm, cipher, curve): printable ASCII, at most `maximumNameLength` characters.
    mutating func readName() throws(SSHKeyError) -> String {
        let name = try readString()
        guard name.count <= Self.maximumNameLength, name.allSatisfy({ (0x21 ... 0x7E).contains($0) }),
              let text = String(bytes: name, encoding: .ascii)
        else {
            throw .malformed
        }
        return text
    }

    /// A `string` holding free text, such as a key's comment: invalid UTF-8 is replaced (U+FFFD) rather than refusing
    /// the whole key.
    mutating func readText() throws(SSHKeyError) -> String {
        let bytes = try readString()
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A non-negative `mpint`, as its big-endian magnitude without leading zeros (empty for zero).
    mutating func readMPInt() throws(SSHKeyError) -> [UInt8] {
        let value = try readString()
        guard value.count <= Self.maximumMPIntLength, (value.first ?? 0) & 0x80 == 0 else {
            throw .malformed
        }
        return Array(value.drop { $0 == 0 })
    }

    /// The bytes left.
    mutating func readRemaining() -> [UInt8] {
        defer { offset = bytes.count }
        return Array(bytes[offset...])
    }
}
