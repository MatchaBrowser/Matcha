import Foundation

/// The encodings under an SSH private key: the SSH wire format (RFC 4251 § 5: `uint32`, `string`, `mpint`), DER
/// (what PKCS#8 and PKCS#1 are written in) and the two operations on big integers an RSA key needs to go from OpenSSH
/// to PKCS#1. Integers are unsigned, big-endian, without leading zeros. Pure type.
nonisolated enum VaultSSHEncoding {
    /// Reads the SSH wire format; every read fails (nil) past the end.
    struct Reader {
        private let bytes: [UInt8]
        private var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        var isAtEnd: Bool {
            index >= bytes.count
        }

        mutating func uint32() -> UInt32? {
            guard index + 4 <= bytes.count else {
                return nil
            }
            defer { index += 4 }
            return bytes[index ..< index + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func string() -> [UInt8]? {
            guard let length = uint32().map(Int.init), length <= bytes.count - index else {
                return nil
            }
            defer { index += length }
            return Array(bytes[index ..< index + length])
        }

        mutating func text() -> String? {
            string().flatMap { String(validating: $0, as: UTF8.self) }
        }

        /// A positive `mpint`, without its sign byte.
        mutating func mpint() -> [UInt8]? {
            guard let value = string(), value.first.map({ $0 & 0x80 == 0 }) ?? true else {
                return nil
            }
            return VaultSSHEncoding.stripped(value)
        }

        mutating func bytes(_ count: Int) -> [UInt8]? {
            guard count <= bytes.count - index else {
                return nil
            }
            defer { index += count }
            return Array(bytes[index ..< index + count])
        }
    }

    // MARK: Writing

    static func uint32(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
    }

    static func string(_ value: [UInt8]) -> [UInt8] {
        uint32(UInt32(value.count)) + value
    }

    static func string(_ text: String) -> [UInt8] {
        string(Array(text.utf8))
    }

    /// A positive integer as an `mpint`: a zero byte in front when its high bit is set, as in DER.
    static func mpint(_ value: [UInt8]) -> [UInt8] {
        string(signed(value))
    }

    /// DER element of `tag` (lengths in short or long form).
    static func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let count = content.count
        let length: [UInt8] = switch count {
        case ..<0x80: [UInt8(count)]
        case ..<0x100: [0x81, UInt8(count)]
        case ..<0x10000: [0x82, UInt8(count >> 8), UInt8(count & 0xFF)]
        default: [0x83, UInt8(count >> 16), UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)]
        }
        return [tag] + length + content
    }

    static func derInteger(_ value: [UInt8]) -> [UInt8] {
        der(0x02, signed(value))
    }

    /// Without leading zeros.
    static func stripped(_ value: [UInt8]) -> [UInt8] {
        Array(value.drop { $0 == 0 })
    }

    /// With a zero byte in front when the high bit is set (two's complement of a positive number); `[0]` for zero in DER.
    private static func signed(_ value: [UInt8]) -> [UInt8] {
        let value = stripped(value)
        return value.first.map { $0 & 0x80 != 0 } ?? true ? [0] + value : value
    }

    // MARK: Big integers

    /// `value − 1`; nil for zero.
    static func minusOne(_ value: [UInt8]) -> [UInt8]? {
        var result = stripped(value)
        guard !result.isEmpty else {
            return nil
        }
        var index = result.count - 1
        while result[index] == 0 {
            result[index] = 0xFF
            index -= 1
        }
        result[index] -= 1
        return stripped(result)
    }

    /// `value mod modulus`, bit by bit (the exponents of a 4096-bit key: a few thousand steps); nil for a zero modulus.
    static func remainder(_ value: [UInt8], modulo modulus: [UInt8]) -> [UInt8]? {
        let modulus = stripped(modulus)
        guard !modulus.isEmpty else {
            return nil
        }
        // Big-endian 32-bit limbs, one more than the modulus for the doubling.
        let width = modulus.count / 4 + 2
        let limbs = { (bytes: [UInt8]) -> [UInt32] in
            let padded = [UInt8](repeating: 0, count: width * 4 - bytes.count) + bytes
            return stride(from: 0, to: padded.count, by: 4).map { padded[$0 ..< $0 + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        }
        let divisor = limbs(modulus)
        var rest = [UInt32](repeating: 0, count: width)
        for byte in value {
            for bit in (0 ..< 8).reversed() {
                // rest = 2 × rest + bit, then minus the modulus if it is past it.
                var carry = UInt32((byte >> bit) & 1)
                for index in rest.indices.reversed() {
                    let next = rest[index] >> 31
                    rest[index] = rest[index] << 1 | carry
                    carry = next
                }
                if !rest.lexicographicallyPrecedes(divisor) {
                    var borrow: UInt64 = 0
                    for index in rest.indices.reversed() {
                        let difference = UInt64(rest[index]) &- UInt64(divisor[index]) &- borrow
                        rest[index] = UInt32(truncatingIfNeeded: difference)
                        borrow = difference >> 63
                    }
                }
            }
        }
        return stripped(rest.flatMap { uint32($0) })
    }
}
