import Foundation

/// Reader of the DER subset that private keys in PEM use (PKCS#8, PKCS#1, SEC1), over untrusted bytes: definite
/// lengths of at most 4 bytes, each checked against what is left; anything else is `SSHKeyError.malformed`. Elements
/// are read one after the other, with a reader per nested sequence, so no input can make it recurse. Pure type.
nonisolated struct SSHDERReader {
    static let sequence: UInt8 = 0x30
    static let integer: UInt8 = 0x02
    static let bitString: UInt8 = 0x03
    static let octetString: UInt8 = 0x04
    static let null: UInt8 = 0x05
    static let objectIdentifier: UInt8 = 0x06

    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    /// The tag of the next element, nil at the end.
    var nextTag: UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    /// The content of the next element, which must have the tag `tag`.
    mutating func read(_ tag: UInt8) throws(SSHKeyError) -> [UInt8] {
        guard bytes.count - offset >= 2, bytes[offset] == tag else {
            throw .malformed
        }
        var cursor = offset + 1
        var length = Int(bytes[cursor])
        cursor += 1
        if length >= 0x80 {
            let count = length & 0x7F
            guard (1 ... 4).contains(count), bytes.count - cursor >= count else {
                throw .malformed
            }
            length = bytes[cursor ..< cursor + count].reduce(0) { ($0 << 8) | Int($1) }
            cursor += count
        }
        guard length <= bytes.count - cursor else {
            throw .malformed
        }
        offset = cursor + length
        return Array(bytes[cursor ..< offset])
    }

    /// The content of the next element if it has the tag `tag`; nil otherwise.
    mutating func readIfPresent(_ tag: UInt8) throws(SSHKeyError) -> [UInt8]? {
        guard nextTag == tag else {
            return nil
        }
        return try read(tag)
    }

    /// A reader over the next element, a sequence or a constructed element of tag `tag`.
    mutating func readNested(_ tag: UInt8 = sequence) throws(SSHKeyError) -> SSHDERReader {
        try SSHDERReader(read(tag))
    }

    /// A non-negative integer, as its big-endian magnitude without leading zeros (empty for zero).
    mutating func readInteger() throws(SSHKeyError) -> [UInt8] {
        let content = try read(Self.integer)
        guard let first = content.first, first & 0x80 == 0 else {
            throw .malformed
        }
        return Array(content.drop { $0 == 0 })
    }

    /// A small non-negative integer, such as a version number.
    mutating func readSmallInteger() throws(SSHKeyError) -> Int {
        let magnitude = try readInteger()
        guard magnitude.count <= 4 else {
            throw .malformed
        }
        return magnitude.reduce(0) { ($0 << 8) | Int($1) }
    }

    /// The bits of a bit string, which must not have unused bits.
    mutating func readBitString() throws(SSHKeyError) -> [UInt8] {
        let content = try read(Self.bitString)
        guard content.first == 0 else {
            throw .malformed
        }
        return Array(content.dropFirst())
    }
}

nonisolated extension SSHDERReader {
    /// The dotted form of an object identifier's content (`1.3.101.112`), to name an unsupported algorithm.
    static func dotted(_ identifier: [UInt8]) -> String {
        var parts: [String] = []
        var value: UInt64 = 0
        for byte in identifier.prefix(32) {
            value = (value &<< 7) | UInt64(byte & 0x7F)
            guard byte & 0x80 == 0 else {
                continue
            }
            if parts.isEmpty {
                parts += value < 80 ? ["\(value / 40)", "\(value % 40)"] : ["2", "\(value - 80)"]
            } else {
                parts.append("\(value)")
            }
            value = 0
        }
        return parts.joined(separator: ".")
    }
}
