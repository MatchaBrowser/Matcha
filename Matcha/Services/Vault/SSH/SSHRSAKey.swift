import Foundation

/// The numbers of an RSA private key, each a big-endian magnitude without leading zeros: those OpenSSH keeps (modulus,
/// public and private exponents, `iqmp` = q⁻¹ mod p, the two primes), which PKCS#1 has too. Checked on creation: odd
/// modulus and exponent, at most `maximumBits` bits, and a modulus equal to the product of the primes, so that a damaged
/// key doesn't get into the vault with a public key that isn't its own. Pure type.
nonisolated struct SSHRSAKey: Equatable {
    /// Smallest modulus accepted at import (`VAULT.md` § 9.4); generated keys have 3 072 or 4 096 bits.
    static let minimumImportBits = 2048
    /// Largest modulus accepted, OpenSSH's limit.
    static let maximumBits = 16384

    let modulus: [UInt8]
    let publicExponent: [UInt8]
    let privateExponent: [UInt8]
    /// `iqmp`, PKCS#1's `coefficient`: the inverse of the second prime modulo the first.
    let coefficient: [UInt8]
    let firstPrime: [UInt8]
    let secondPrime: [UInt8]

    init(
        modulus: [UInt8],
        publicExponent: [UInt8],
        privateExponent: [UInt8],
        coefficient: [UInt8],
        primes: (first: [UInt8], second: [UInt8]),
    ) throws(SSHKeyError) {
        let numbers = [modulus, publicExponent, privateExponent, coefficient, primes.first, primes.second]
        guard numbers.allSatisfy({ $0.first.map { $0 != 0 } ?? false }),
              modulus.count <= Self.maximumBits / 8, (modulus.last ?? 0) & 1 == 1, (publicExponent.last ?? 0) & 1 == 1,
              publicExponent.count <= modulus.count, Self.product(primes.first, primes.second) == modulus
        else {
            throw .malformed
        }
        self.modulus = modulus
        self.publicExponent = publicExponent
        self.privateExponent = privateExponent
        self.coefficient = coefficient
        firstPrime = primes.first
        secondPrime = primes.second
    }

    /// From PKCS#1's `RSAPrivateKey` (RFC 8017, appendix A.1.2), alone (`BEGIN RSA PRIVATE KEY`) or inside PKCS#8:
    /// two-prime keys only.
    init(pkcs1 der: [UInt8]) throws(SSHKeyError) {
        var outer = SSHDERReader(der)
        var key = try outer.readNested()
        guard outer.isAtEnd, try key.readSmallInteger() == 0 else {
            throw .malformed
        }
        let modulus = try key.readInteger()
        let publicExponent = try key.readInteger()
        let privateExponent = try key.readInteger()
        let first = try key.readInteger()
        let second = try key.readInteger()
        _ = try key.readInteger() // d mod (p - 1)
        _ = try key.readInteger() // d mod (q - 1)
        let coefficient = try key.readInteger()
        guard key.isAtEnd else {
            throw .malformed
        }
        try self.init(
            modulus: modulus,
            publicExponent: publicExponent,
            privateExponent: privateExponent,
            coefficient: coefficient,
            primes: (first, second),
        )
    }

    /// From OpenSSH's private section, after the type name: `mpint n, e, d, iqmp, p, q`.
    init(reading reader: inout SSHWireReader) throws(SSHKeyError) {
        let modulus = try reader.readMPInt()
        let publicExponent = try reader.readMPInt()
        let privateExponent = try reader.readMPInt()
        let coefficient = try reader.readMPInt()
        let first = try reader.readMPInt()
        let second = try reader.readMPInt()
        try self.init(
            modulus: modulus,
            publicExponent: publicExponent,
            privateExponent: privateExponent,
            coefficient: coefficient,
            primes: (first, second),
        )
    }

    /// Size of the modulus in bits.
    var bits: Int {
        guard let first = modulus.first else {
            return 0
        }
        return (modulus.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    }

    /// The public key in SSH's encoding (RFC 4253 § 6.6): `string "ssh-rsa", mpint e, mpint n`.
    var publicBlob: [UInt8] {
        var writer = SSHWireWriter()
        writer.write(string: SSHKeyType.rsa.rawValue)
        writer.write(mpint: publicExponent)
        writer.write(mpint: modulus)
        return writer.bytes
    }

    /// OpenSSH's private fields, after the type name.
    func writePrivate(to writer: inout SSHWireWriter) {
        for number in [modulus, publicExponent, privateExponent, coefficient, firstPrime, secondPrime] {
            writer.write(mpint: number)
        }
    }

    /// The product of two big-endian magnitudes, without leading zeros (schoolbook multiplication, base 256).
    static func product(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        let left = Array(lhs.reversed())
        let right = Array(rhs.reversed())
        var digits = [UInt32](repeating: 0, count: left.count + right.count)
        for (leftIndex, leftDigit) in left.enumerated() {
            var carry: UInt32 = 0
            for (rightIndex, rightDigit) in right.enumerated() {
                let value = digits[leftIndex + rightIndex] + UInt32(leftDigit) * UInt32(rightDigit) + carry
                digits[leftIndex + rightIndex] = value & 0xFF
                carry = value >> 8
            }
            digits[leftIndex + right.count] += carry
        }
        return Array(digits.reversed().map { UInt8(truncatingIfNeeded: $0) }.drop { $0 == 0 })
    }
}
