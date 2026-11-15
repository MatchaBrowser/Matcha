import Foundation

/// Writer of SSH's binary encoding (RFC 4251 § 5), the counterpart of `SSHWireReader`. Pure type.
nonisolated struct SSHWireWriter {
    private(set) var bytes: [UInt8] = []

    mutating func write(byte: UInt8) {
        bytes.append(byte)
    }

    mutating func write(_ value: UInt32) {
        bytes += [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value &>> UInt32($0)) }
    }

    /// Bytes as they are, without length.
    mutating func write(raw: [UInt8]) {
        bytes += raw
    }

    /// A `string`: its length, then its bytes.
    mutating func write(string: [UInt8]) {
        write(UInt32(string.count))
        bytes += string
    }

    mutating func write(string: String) {
        write(string: Array(string.utf8))
    }

    /// A non-negative `mpint` from its big-endian magnitude: leading zeros removed, and a zero byte added when the
    /// first bit is set, so that the number doesn't read as negative.
    mutating func write(mpint magnitude: [UInt8]) {
        var value = Array(magnitude.drop { $0 == 0 })
        if let first = value.first, first & 0x80 != 0 {
            value.insert(0, at: 0)
        }
        write(string: value)
    }
}
